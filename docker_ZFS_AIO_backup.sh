#!/bin/bash

################################################################################
#               UNRAID DOCKER CONTAINER ZFS AIO BACKUP v1.000                  #
#           https://github.com/Blasman/Unraid_Docker_ZFS_AIO_Backup            #
################################################################################

# Written/intended for Plex, but will work with any single docker container. Ideal for containers with large/complex appdata folders.
# The goal is to do a full/custom backup of docker containers appdata and to minimize docker container downtime.

# Simplified order of operations and functions of this script:
# 1. Stop docker.
# 2. Snapshot docker dataset.
# 3. Start docker.
# 4. Optional: Replicate docker dataset and snapshots to another pool/dataset using syncoid.
# The following options may use the snapshot from Step 2 as a source by creating a temporary clone of it:
# 5. Optional: Create timestamped rsynced folder any folders/files.
# 6. Optional: Create timestamped tarfile of any files/folders.

################################################################################
#                              USER CONFIG BELOW                               #
################################################################################
DOCKER_NAME="plex"  # Name of docker container.
SOURCE_DATASET="pool_main/appdata/plex"  # Docker container's appdata dataset.
REPLICATE_DATASET=false  # Replicate most recent snapshot to another dataset using syncoid. If 'true', then EDIT THE 'REPLICATION SETTINGS' BELOW!
BACKUP_FILES=false  # Create a timestamped rsync folder of the DB files and Preferences.xml (or any files/folders). If 'true', then EDIT THE 'BACKUP FILES SETTINGS' BELOW!
TAR_FILES=false  # Create a timestamped tarfile of docker container's 'Media' and 'Metadata' folders (or any files/folders). If 'true', then EDIT THE 'TARFILE SETTINGS' BELOW!
MANAGE_SANOID_CONFIG=true  # Have this script automatically create and update your sanoid .conf files.
SANOID_DEFAULT_CONFIG_DIR="/etc/sanoid"  # You shouldn't need to change this.
SANOID_DOCKER_CONFIG_DIR="/etc/sanoid/$DOCKER_NAME"  # You shouldn't need to change this. Path will be created if it does not exist.
# Set sanoid's snapshot retention policy below. "How many snapshots of X timeframe will be kept before deleting old snapshots of said timeframe?"
SNAPSHOT_HOURS="0"
SNAPSHOT_DAYS="7"
SNAPSHOT_WEEKS="4"
SNAPSHOT_MONTHS="3"
SNAPSHOT_YEARS="0"
ALLOW_SNAPSHOTS_OUTSIDE_OF_RETENTION_POLICY=false  # sanoid will not take new snapshots if ran before its next retention policy interval. Set to 'true' to allow additional snapshots to be taken.
# DELETE_EXTRA_SNAPSHOTS_OLDER_THAN_X_DAYS="7"  # Uncomment line to delete any '_extra' snapshots (taken when ALLOW_EXTRA_SNAPSHOTS_OUTSIDE_OF_RETENTION_POLICY=true) that are older than this many days.
# --------------------------- REPLICATION SETTINGS --------------------------- #
REPLICATED_DATASET="pool_ssds/backup_appdata/plex"  # Define the name of the dataset that you want to replicate to. DATASET(S) WILL BE CREATED IF THEY DO NOT EXIST!
SYNCOID_ARGS="-r --delete-target-snapshots --force-delete --no-sync-snap --quiet"  # OPTIONALLY (and carefully) customize the syncoid command line arguments. See: https://github.com/jimsalterjrs/sanoid/wiki/Syncoid#options
# --------------------- BACKUP FILES & TARFILE SETTINGS ---------------------- #
TEMP_DATASET_TO_CLONE_TO="pool_main/temp"  # Dataset to temporarily clone the most recent snapshot of the docker container's appdata dataset. A dataset is created within this dataset during backup, and is then destoyed after backup.
# -------------------------- BACKUP FILES SETTINGS --------------------------- #
BACKUP_DIR="/mnt/pool_ssds/backup_plex_db"  # Backup directory to rsync DB files and Preferences.xml to (or any other files/folders as specified in BACKUP_INCLUDES).
BACKUP_DATASET_PATH="pool_ssds/backup_plex_db"  # If backing up files to a dataset, uncomment line and specify the dataset name to back up files to (needed for MOUNT_BACKUP_DATASET option). DATASET(S) WILL BE CREATED IF THEY DO NOT EXIST!
HOURS_TO_KEEP_BACKUPS_FOR="95"  # Delete backups older than this many hours. [Hours=Days|72=3|96=4|120=5|144=6|168=7|336=14|720=30] Tip: subtract one hour if desired to ensure oldest backup is always deleted.
# Specify full paths to any files/folders (do *NOT* use '/mnt/user', use pool dir instead ie '/mnt/pool_name') and where to copy them to. Each line essentially becomes a 'rsync -a' command.
BACKUP_INCLUDES=(  # <APPDATA_DIR> will be replaced with the folder path to your pool's docker container's appdata folder. <GENERATED_BACKUP_DIR> will be replaced with the scripts generated timestamped backup directory.
    # "source" "destination"
    "<APPDATA_DIR>/Library/Application Support/Plex Media Server/Preferences.xml"                                                "<GENERATED_BACKUP_DIR>/Preferences.xml"
    "<APPDATA_DIR>/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"       "<GENERATED_BACKUP_DIR>/com.plexapp.plugins.library.db"
    "<APPDATA_DIR>/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.blobs.db" "<GENERATED_BACKUP_DIR>/com.plexapp.plugins.library.blobs.db"
)
# ---------------------- OPTIONAL BACKUP FILES SETTINGS ---------------------- #
MOUNT_BACKUP_DATASET=false  # If using a database that needs to be mounted before backup and unmounted after backup, set to 'true' to use.
BACKUP_PERMISSIONS="755"  # OPTIONALLY change to any 3 or 4 digit value to have chmod set those permissions on the timestamped backup sub-directory (but not the rsynced folders/files).
BACKUP_SUBDIR_TEXT="${DOCKER_NAME} Backup"  # OPTIONALLY customize the text for the backup sub-directory name. As a precaution, the script only deletes old backups that match this pattern.
BACKUP_TIMESTAMP() { date +"%Y_%m_%d@%H.%M.%S"; }  # OPTIONALLY customize TIMESTAMP for backup sub-directory name.
BACKUP_SUBDIR_COMPLETE_NAME() { echo "[$(BACKUP_TIMESTAMP)] $BACKUP_SUBDIR_TEXT"; }  # OPTIONALLY customize the complete backup sub-directory name with the TIMESTAMP and BACKUP_SUBDIR_TEXT.
# ----------------------------- TARFILE SETTINGS ----------------------------- #
TARFILE_DIR="/mnt/pool_ssds/backup_plex_tarfiles"  # Backup directory to store the created tarfiles.
TARFILE_DATASET_PATH="pool_ssds/backup_plex_tarfiles"  # If saving tarfiles to a dataset, uncomment line and specify the dataset name (needed for MOUNT_TARFILE_DATASET option). DATASET(S) WILL BE CREATED IF THEY DO NOT EXIST!
HOURS_TO_KEEP_TARFILES_FOR="335"  # Delete backups older than this many hours. [Hours=Days|72=3|96=4|120=5|144=6|168=7|336=14|720=30] Tip: subtract one hour if desired to ensure oldest backup is always deleted.
# Specify full paths to any files/folders (do *NOT* use '/mnt/user', use pool dir instead ie '/mnt/pool_name') to add to the tarfile (nothing is included by default).
TARFILE_INCLUDES=(  # <APPDATA_DIR> will be replaced with the folder path to your pool's docker container's appdata folder.
    "<APPDATA_DIR>/Library/Application Support/Plex Media Server/Logs"
    "<APPDATA_DIR>/Library/Application Support/Plex Media Server/Scanners"
    "<APPDATA_DIR>/Library/Application Support/Plex Media Server/Logs"
)
# ------------------------ OPTIONAL TARFILE SETTINGS ------------------------- #
TARFILE_COMPRESSION_LEVEL="1"  # Specify tarfile compression. "0" == none | "1" == GZIP | "2" or higher == ZSTD (number is the amount of CPU cores to use).
TARFILE_PERMISSIONS="640"  # Set to any 3 or 4 digit value to have chmod set those permissions on the final tar file.
MOUNT_TARFILE_DATASET=false  # If using a database that needs to be mounted before backup and unmounted after backup, set to 'true' to use.
TARFILE_TEXT="${DOCKER_NAME} Backup"  # OPTIONALLY customize the text for the backup tar file. As a precaution, the script only deletes old backups that match this pattern.
TARFILE_TIMESTAMP() { date +"%Y_%m_%d@%H.%M.%S"; }  # OPTIONALLY customize TIMESTAMP for the tar filename.
TARFILE_COMPLETE_FILENAME() { echo "[$(TARFILE_TIMESTAMP)] $TARFILE_TEXT.tar"; }  # OPTIONALLY customize the complete tar file name with the TIMESTAMP and TARFILE_TEXT. (compression extensions are added automatically!)
# -------------------------- OPTIONAL MISC SETTINGS -------------------------- #
# Specify patterns to match to be added as '--exclude' arguments for the tar and rsync commands.
EXCLUDES=(
  # "logs"
  # "*.log"
)
STOP_DOCKER=true  # Shutdown docker container before snapshot and always restart it after snapshot. Set to 'true' to use.
UNRAID_WEBGUI_START_MSG=false  # Send backup start message to the Unraid Web GUI. Set to 'true' to use.
UNRAID_WEBGUI_SUCCESS_MSG=true  # Send backup success message to the Unraid Web GUI. Set to 'true' to use.
UNRAID_WEBGUI_FAILURE_MSG=true  # Send backup failure message to the Unraid Web GUI. Set to 'true' to use.
USE_LOCK_FILE=false  # Set to 'true' to enable use of lock file to prevent overlapping backups. 'rm /tmp/zfs_backup_lock_file.tmp' to delete lock file if required.
# REPLICATION_SCHEDULE="1 2 3 4 5 6 7"  # OPTIONALLY restrict the days of the week that replications can take place. 1 = Monday.
# BACKUP_SCHEDULE="1 2 3 4 5 6 7"  # OPTIONALLY restrict the days of the week that files can be backed up. 1 = Monday.
# TARFILE_SCHEDULE="1 2 3 4 5 6 7"  # OPTIONALLY restrict the days of the week that tarfiles can be created. 1 = Monday.
################################################################################
#                              END OF USER CONFIG                              #
################################################################################

echo_ts() { printf "[%(%Y_%m_%d)T %(%H:%M:%S)T.${EPOCHREALTIME: -6:3}] $@\\n"; }

unraid_notify() { /usr/local/emhttp/webGui/scripts/notify -s "$DOCKER_NAME ZFS Backup Script" -i $1 -d "$2"; }

run_timer() {
    local run_time=$((${2/./} - ${1/./}))                                                                                         # Output Examples
    if [[ $run_time -lt 1000000 ]]; then printf -v run_time "%06d" $run_time; echo ".${run_time: -6:4}s"                          # ==       .1234s
    elif [[ $run_time -lt 10000000 ]]; then echo "${run_time:0:1}.${run_time: -6:3}s"                                             # ==       1.234s
    elif [[ $run_time -lt 60000000 ]]; then echo "${run_time:0:2}.${run_time: -6:3}s"                                             # ==      12.345s
    elif [[ $run_time -lt 3600000000 ]]; then echo "$((run_time % 3600000000 / 60000000))m $((run_time % 60000000 / 1000000))s"   # ==       1m 23s
    elif [[ $run_time -lt 86400000000 ]]; then echo "$((run_time / 3600000000))h $((run_time % 3600000000 / 60000000))m"          # ==       1h 23m
    else echo "$((run_time / 86400000000))d $((run_time / 3600000000 % 24))h $((run_time % 3600000000 / 60000000))m"; fi          # ==   1d 23h 45m
}

create_or_update_sanoid_config() {
    if [[ ! -d "$SANOID_DOCKER_CONFIG_DIR" ]]; then mkdir -p "$SANOID_DOCKER_CONFIG_DIR"; fi
    if [[ ! -f "$SANOID_DOCKER_CONFIG_DIR/sanoid.defaults.conf" ]]; then cp "$SANOID_DEFAULT_CONFIG_DIR/sanoid.defaults.conf" "$SANOID_DOCKER_CONFIG_DIR/sanoid.defaults.conf"; fi
    sanoid_scripts_config_file="$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
    if [[ -f "$sanoid_scripts_config_file" ]]; then
        update_setting() {
            local key=$1 new_value=$2 current_value
            current_value=$(grep "^$key = " "$sanoid_scripts_config_file" | awk -F ' = ' '{print $2}')
            if [[ "$current_value" != "$new_value" ]]; then
                sed -i "s/^$key = .*/$key = $new_value/" "$sanoid_scripts_config_file"
                echo_ts "[CONFIG CHANGE] Updated '$key' to '$new_value' in '$sanoid_scripts_config_file'."
            fi
        }
        update_setting "hourly" "$SNAPSHOT_HOURS"
        update_setting "daily" "$SNAPSHOT_DAYS"
        update_setting "weekly" "$SNAPSHOT_WEEKS"
        update_setting "monthly" "$SNAPSHOT_MONTHS"
        update_setting "yearly" "$SNAPSHOT_YEARS"
    else
        echo "[$SOURCE_DATASET]" > "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
        echo "use_template = production" >> "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
        echo "recursive = yes" >> "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
        echo "" >> "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
        echo "[template_production]" >> "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
        echo "hourly = $SNAPSHOT_HOURS" >> "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
        echo "daily = $SNAPSHOT_DAYS" >> "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
        echo "weekly = $SNAPSHOT_WEEKS" >> "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
        echo "monthly = $SNAPSHOT_MONTHS" >> "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
        echo "yearly = $SNAPSHOT_YEARS" >> "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
        echo "autosnap = yes" >> "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
        echo "autoprune = yes" >> "$SANOID_DOCKER_CONFIG_DIR/sanoid.conf"
    fi
}

exit_with_error() {
    graceful_exit_with_error=true
    echo_ts "[❌] $1"
    if [[ $UNRAID_WEBGUI_FAILURE_MSG == true ]]; then unraid_notify alert "$1"; fi
    exit 1
}

change_backup_types_to_false_if_ran_outside_of_schedule() {
    local current_day_of_the_week=$(date +%u)
    if [[ -n "$REPLICATION_SCHEDULE" && "$REPLICATION_SCHEDULE" != *"$current_day_of_the_week"* ]]; then REPLICATE_DATASET=false; fi
    if [[ -n "$BACKUP_SCHEDULE" && "$BACKUP_SCHEDULE" != *"$current_day_of_the_week"* ]]; then BACKUP_FILES=false; fi
    if [[ -n "$TARFILE_SCHEDULE" && "$TARFILE_SCHEDULE" != *"$current_day_of_the_week"* ]]; then TAR_FILES=false; fi
}

clean_up() {
    if [ $? -ne 0 ] && [[ $UNRAID_WEBGUI_FAILURE_MSG == true ]] && [[ $graceful_exit_with_error != true ]]; then unraid_notify alert "Exited with an unexpected error."; fi
    if [[ -n "$cloned_mount_point" ]] && zfs list -o name -H "$cloned_mount_point" &>/dev/null; then destroy_clone; fi
    if [[ $MOUNT_BACKUP_DATASET == true ]] && [[ $(zfs get -H -o value mounted "$BACKUP_DATASET_PATH") == "yes" ]]; then unmount_dataset "$BACKUP_DATASET_PATH" yes; fi
    if [[ $MOUNT_TARFILE_DATASET == true ]] && [[ $(zfs get -H -o value mounted "$TARFILE_DATASET_PATH") == "yes" ]]; then unmount_dataset "$TARFILE_DATASET_PATH" yes; fi
    if [[ $USE_LOCK_FILE == true ]] && [[ -f "$lockfile" ]]; then rm -f "$lockfile"; fi
    if [[ $STOP_DOCKER == true ]] && [[ $(get_docker_state) == "stopped" ]]; then docker start "$DOCKER_NAME" >/dev/null; fi
    trap - EXIT
}

get_docker_state() {
    local response=$(docker inspect -f '{{.State.Status}}' "$DOCKER_NAME" 2>/dev/null)
    if [[ "$response" =~ ^(started|running|restarting)$ ]]; then echo "running";
    elif [[ "$response" =~ ^(stopped|created|exited|paused)$ ]]; then echo "stopped";
    else echo "unknown"; fi
}

pre_checks_and_start_script() {
    script_start_time=$EPOCHREALTIME
    if [[ $USE_LOCK_FILE == true ]]; then
        lockfile="/tmp/zfs_backup_lock_file.tmp"
        if [[ -f "$lockfile" ]]; then
            exit_with_error "$DOCKER_NAME backup is currently active! Lock file can be removed by typing 'rm $lockfile'. Exiting."; fi
    fi
    if [[ ! -x "$(which zfs)" ]]; then
        exit_with_error "ZFS not found on this system ('which zfs'). This script is meant for Unraid 6.12 or above (which includes ZFS support). Please ensure you are using the correct Unraid version."; fi
    if [[ ! -x /usr/local/sbin/sanoid ]]; then
        exit_with_error "sanoid not found or executable at '/usr/local/sbin/sanoid'. Please make sure that it is installed from the Unraid Community Apps."; fi
    clean_directory_variables() { for var in "$@"; do if [ -n "${!var}" ]; then eval "$var=\"/$(echo ${!var} | sed 's|^/||; s|/$||')\""; fi; done }
    clean_directory_variables SANOID_DEFAULT_CONFIG_DIR SANOID_DOCKER_CONFIG_DIR BACKUP_DIR TARFILE_DIR
    if [[ ! -d "$SANOID_DEFAULT_CONFIG_DIR" ]]; then
        exit_with_error "sanoid default config file directory 'SANOID_DEFAULT_CONFIG_DIR' not found at '$SANOID_DEFAULT_CONFIG_DIR'."; fi
    if [[ ! -f "$SANOID_DEFAULT_CONFIG_DIR/sanoid.defaults.conf" ]] || [[ ! -f "$SANOID_DEFAULT_CONFIG_DIR/sanoid.conf" ]]; then
        exit_with_error "sanoid config files not found at '$SANOID_DEFAULT_CONFIG_DIR'. You need 'sanoid.defaults.conf' and 'sanoid.conf' in this directory."; fi
    if ! zfs list -o name -H "$SOURCE_DATASET" &>/dev/null; then
        exit_with_error "The source dataset '$SOURCE_DATASET' does not exist."; fi
    if [[ $(zfs get -H -o value used "$SOURCE_DATASET") == 0B ]]; then
        exit_with_error "The source dataset '$SOURCE_DATASET' is empty. Nothing to do."; fi
    if [[ $STOP_DOCKER == true ]]; then
        docker_state="$(get_docker_state)"
        if [[ "$docker_state" == "unknown" ]]; then
            exit_with_error "Could not find '$DOCKER_NAME' docker. Exiting."; fi
    fi
    if [[ -n "$REPLICATION_SCHEDULE" || -n "$BACKUP_SCHEDULE" || -n "$TARFILE_SCHEDULE" ]]; then change_backup_types_to_false_if_ran_outside_of_schedule; fi
    if [[ $REPLICATE_DATASET == true ]] && [[ ! -x /usr/local/sbin/syncoid ]]; then
        echo_ts "[❌] Syncoid not found or executable at '/usr/local/sbin/syncoid'. Please install syncoid (part of sanoid) plugin. Skipping replication job."
        REPLICATE_DATASET=false
    fi
    docker_folder_path=$(zfs get -H -o value mountpoint "$SOURCE_DATASET")
    if [[ -z "$docker_folder_path" ]]; then exit_with_error "Could not get mountpoint for '$SOURCE_DATASET'."; fi
    if [[ $MANAGE_SANOID_CONFIG == true ]]; then create_or_update_sanoid_config; fi
    trap clean_up EXIT
    if [[ $USE_LOCK_FILE == true ]]; then touch "$lockfile"; fi
    echo_ts "[${DOCKER_NAME^^} BACKUP STARTED]"
    if [[ $UNRAID_WEBGUI_START_MSG == true ]]; then unraid_notify normal "$DOCKER_NAME ZFS Backup Script Started."; fi
}

destroy_clone() {
    zfs destroy "$cloned_mount_point"
    if zfs list -o name -H "$cloned_mount_point" &>/dev/null; then echo_ts "[❌] Could not destroy '"$cloned_mount_point"'."; return 1; fi
    echo_ts "Destroyed clone '"$cloned_mount_point"'."
}

stop_docker() {
    if [[ "$docker_state" == "running" ]]; then
        echo_ts "Stopping $DOCKER_NAME docker..."
        stop_docker_start_time=$EPOCHREALTIME
        docker stop "$DOCKER_NAME" >/dev/null
        local stop_docker_finish_time=$EPOCHREALTIME
        echo_ts "$DOCKER_NAME docker stopped in $(run_timer $stop_docker_start_time $stop_docker_finish_time)."
    else
        echo_ts "$DOCKER_NAME docker already stopped. Skipping docker stop."
    fi
}

start_docker() {
    docker_state="$(get_docker_state)"
    if [[ "$docker_state" == "stopped" ]]; then
        echo_ts "Starting $DOCKER_NAME docker..."
        local start_docker_start_time=$EPOCHREALTIME
        docker start "$DOCKER_NAME" >/dev/null
        local start_docker_finish_time=$EPOCHREALTIME
        echo_ts "$DOCKER_NAME docker started in $(run_timer $start_docker_start_time $start_docker_finish_time). ⏱️ $(run_timer $stop_docker_start_time $start_docker_finish_time) of total $DOCKER_NAME downtime since start of 'docker stop' command."
    else
        echo_ts "$DOCKER_NAME docker already started. Skipping docker start."
    fi
}

get_age_in_seconds() { echo $(($(date +%s) - $(stat -c %Y "$1"))); }

delete_old_files() {
    local dir=$1 hours_to_keep=$2 text_pattern=$3 type=$4
    local cutoff_age=$(($hours_to_keep * 3600))
    for match in "$dir"/*"$text_pattern"*; do
        if [[ ( "$type" == "folder" && -d "$match" ) || ( "$type" == "file" && -f "$match" ) ]]; then
            if [ "$(get_age_in_seconds "$match")" -gt "$cutoff_age" ]; then
                if [ "$type" == "folder" ]; then rm -r "$match";
                else rm -f "$match"; fi
                echo_ts "Deleted old $type '$(basename "$match")'."
            fi
        fi
    done
}

snapshot_dataset() {
    echo_ts "Creating ZFS snapshot of '$SOURCE_DATASET' using sanoid..."
    local snapshot_start_time=$EPOCHREALTIME
    local sanoid_output=$(/usr/local/sbin/sanoid --configdir="$SANOID_DOCKER_CONFIG_DIR" --take-snapshots -v); local sanoid_exit=$?
    local snapshot_finish_time=$EPOCHREALTIME
    if [ $sanoid_exit -ne 0 ]; then exit_with_error "Automatic snapshot creation using sanoid failed for source '$SOURCE_DATASET'."; fi
    most_recent_autosnap_name=$(zfs list -t snapshot -o name -S creation -r "$SOURCE_DATASET" | awk '/autosnap_/ {print; exit}')
    most_recent_autosnap_age=$(( $(date +%s) - $(zfs get -Hp creation "$most_recent_autosnap_name" | awk '{print $3}') ))
    if [[ $(echo "$sanoid_output" | tail -n 1) == *"INFO: taking snapshots..."* ]] || [[ "$most_recent_autosnap_age" -gt 15 ]]; then
        if [[ $ALLOW_SNAPSHOTS_OUTSIDE_OF_RETENTION_POLICY == true ]]; then
            echo_ts "[⚠️] Last 'autosnap' found is '$most_recent_autosnap_name' taken $most_recent_autosnap_age seconds ago. Taking snapshot with 'zfs snapshot' instead."
            zfs snapshot "$SOURCE_DATASET@autosnap_$(date +"%Y-%m-%d_%H:%M:%S")_extra" &>/dev/null
            if [ $? -ne 0 ]; then exit_with_error "Failed to create snapshot for source: '$SOURCE_DATASET'.";
            else echo_ts "[✔️] '$(zfs list -t snapshot -o name -S creation -r "$SOURCE_DATASET" | awk '/autosnap_/ {print; exit}')' created in $(run_timer $snapshot_start_time $snapshot_finish_time)."; fi
        else
            exit_with_error "Last 'autosnap' found is '$most_recent_autosnap_name' taken $most_recent_autosnap_age seconds ago. Enable 'ALLOW_SNAPSHOTS_OUTSIDE_OF_RETENTION_POLICY' in script config to allow extra snapshots to be taken."
        fi
    else
        echo_ts "[✔️] '$most_recent_autosnap_name' created in $(run_timer $snapshot_start_time $snapshot_finish_time)."
    fi
}

create_all_required_datasets_from_path() {
    local dataset="$1" type="$2"
    if ! zfs list -o name -H "$dataset" &>/dev/null; then
        IFS='/' read -r -a components <<< "$dataset"
        local path="${components[0]}"
        for ((i=1; i<${#components[@]}; i++)); do
            path+="/${components[i]}"
            if ! zfs list -o name -H "$path" &>/dev/null; then
                echo_ts "Creating dataset '$path'..."
                zfs create "$path"
                if [ $? -ne 0 ]; then echo_ts "[❌] Failed to create dataset '$path'. Skipping $type."; return 1; fi
                echo_ts "[✔️] Successfully created dataset '$path'."
            fi
        done
    fi
}

pre_checks_for_various_backup_types() {
    local operation_type=$1 dataset_path=$2 mount_dataset_flag=$3 dir=$4 output_path_var_name=$5 custom_name_var_name=$6
    check_for_proper_dataset_paths() {
        local -n array="$1"
        for x in "${array[@]}"; do
            if [[ "$x" == *"/mnt/user/"* ]]; then
                echo_ts "[❌] Do not use '/mnt/user/' folder paths for '$1' variable. Use the pool devices folder paths instead."
                return 1
            fi
        done
    }
    check_for_proper_dataset_paths "${operation_type^^}_INCLUDES"
    if [ $? -ne 0 ]; then return 1; fi
    if [[ -n "$dataset_path" ]]; then
        create_all_required_datasets_from_path "$dataset_path" "$operation_type"
        if [ $? -ne 0 ]; then return 1; fi
    fi
    if [[ $mount_dataset_flag == true ]]; then
        mount_dataset "$dataset_path"
        if [ $? -ne 0 ]; then 
            echo_ts "[❌] Failed to mount snapshot '$dataset_path'. Skipping $operation_type."
            return 1
        fi
    fi
    if [[ ! -d "$dir" ]]; then
        echo_ts "[❌] '$operation_type directory' not found at '$dir'. Skipping $operation_type."
        if [[ $mount_dataset_flag == true ]]; then unmount_dataset "$dataset_path"; fi
        return 1
    fi
    eval "$output_path_var_name=\"$dir/$($custom_name_var_name)\""
}

get_file_or_folder_size() {
    if [[ -f "$1" ]]; then local size=$(stat -c%s "$1")
    elif [[ -d "$1" ]]; then local size=$(du -sb "$1" | cut -f1)
    else return 1; fi
    if [ "$size" -lt 1024 ]; then echo "${size}B"
    elif [ "$size" -lt $((1024 * 1024)) ]; then echo "$((size / 1024))KB"
    elif [ "$size" -lt $((1024 * 1024 * 1024)) ]; then echo "$((size / (1024 * 1024)))MB"
    else echo "$((size / (1024 * 1024 * 1024)))GB"; fi
}

backup_files() {
    pre_checks_for_various_backup_types "backup" "$BACKUP_DATASET_PATH" "$MOUNT_BACKUP_DATASET" "$BACKUP_DIR" "backup_path" "BACKUP_SUBDIR_COMPLETE_NAME"
    if [ $? -ne 0 ]; then return 1; fi
    local rsync_jobs backup_start_time backup_finish_time
    for path in "${BACKUP_INCLUDES[@]}"; do rsync_jobs+=("$(echo "$path" | sed -E "s|$docker_folder_path|$cloned_folder_path|g; s|<APPDATA_DIR>|$cloned_folder_path|g; s|<GENERATED_BACKUP_DIR>|$backup_path|g")"); done
    echo_ts "Copying files to '$backup_path'..."
    backup_start_time=$EPOCHREALTIME
    mkdir -p "$backup_path"
    for ((i=0; i<${#rsync_jobs[@]}; i+=2)); do rsync -a ${exclude_arg[@]:+$exclude_arg[@]} "${rsync_jobs[$i]}" "${rsync_jobs[$i+1]}"; done
    if [ $? -ne 0 ]; then echo_ts "[❌] Could not back up files to '$backup_path'."; return 1; fi
    backup_finish_time=$EPOCHREALTIME
    if [ -z "$(shopt -s nullglob dotglob; echo $backup_path/*)" ]; then echo_ts "[❌] Rsync didn't add any files to '$backup_path'."; return 1; fi
    backup_path_filesize=$(get_file_or_folder_size "$backup_path")
    echo_ts "[✔️] Copied $backup_path_filesize of data in $(run_timer $backup_start_time $backup_finish_time)."
    chown nobody:users "$backup_path"
    if [[ $BACKUP_PERMISSIONS =~ ^[0-9]{3,4}$ ]]; then chmod $BACKUP_PERMISSIONS "$backup_path"; fi
    if [[ $HOURS_TO_KEEP_BACKUPS_FOR =~ ^[0-9]+$ ]]; then delete_old_files "$BACKUP_DIR" "$HOURS_TO_KEEP_BACKUPS_FOR" "$BACKUP_SUBDIR_TEXT" "folder"; fi
}

tar_files() {
    pre_checks_for_various_backup_types "tarfile" "$TARFILE_DATASET_PATH" "$MOUNT_TARFILE_DATASET" "$TARFILE_DIR" "tarfile_complete_path" "TARFILE_COMPLETE_FILENAME"
    if [ $? -ne 0 ]; then return 1; fi
    local tar_paths=() compression ext tarfile_start_time tar_error_output tarfile_finish_time
    for path in "${TARFILE_INCLUDES[@]}"; do tar_paths+=("$(echo "$path" | sed -E "s|$docker_folder_path|$cloned_folder_path|g; s|<APPDATA_DIR>|$cloned_folder_path|g")"); done
    if [[ $TARFILE_COMPRESSION_LEVEL -eq 1 ]]; then compression="-z" ext=".gz"
    elif [[ $TARFILE_COMPRESSION_LEVEL -ge 2 ]]; then compression="-I zstd -T$TARFILE_COMPRESSION_LEVEL" ext=".zst"; fi
    tarfile_complete_path=$tarfile_complete_path$ext
    echo_ts "Creating file '$tarfile_complete_path'..."
    tarfile_start_time=$EPOCHREALTIME
    tar_error_output=$(tar ${exclude_arg[@]:+$exclude_arg[@]} -cf "$tarfile_complete_path" ${compression:+"$compression"} --transform "s|^${cloned_folder_path#/}|$docker_folder_path|" "${tar_paths[@]}" 2>&1 >/dev/null)
    if [ $? -ne 0 ]; then echo_ts "[❌] Could not create '$tarfile_complete_path'. Tar error: $tar_error_output"; return 1
    elif [[ ! -f "$tarfile_complete_path" ]]; then echo_ts "[❌] File '$tarfile_complete_path' was not created by tar."; return 1; fi
    tarfile_finish_time=$EPOCHREALTIME
    tarfile_file_size=$(get_file_or_folder_size "$tarfile_complete_path")
    echo_ts "[✔️] Created $tarfile_file_size size tarfile in $(run_timer $tarfile_start_time $tarfile_finish_time)."
    chown nobody:users "$tarfile_complete_path"
    if [[ $TARFILE_PERMISSIONS =~ ^[0-9]{3,4}$ ]]; then chmod $TARFILE_PERMISSIONS "$tarfile_complete_path"; fi
    if [[ $HOURS_TO_KEEP_TARFILES_FOR =~ ^[0-9]+$ ]]; then delete_old_files "$TARFILE_DIR" "$HOURS_TO_KEEP_TARFILES_FOR" "$TARFILE_TEXT" "file"; fi
}

mount_dataset() {
    local mount_status=$(zfs get -H -o value mounted "$1")
    if [[ "$mount_status" == "no" ]]; then
        zfs mount "$1" &>/dev/null
        if [[ $(zfs get -H -o value mounted "$1") == "yes" ]]; then echo_ts "Mounted '$1'."
        else return 1; fi
    elif [[ "$mount_status" == "yes" ]]; then echo_ts "[⚠️] '$1' was already mounted."
    else echo_ts "[❌] $mount_status."; return 1; fi
}

unmount_dataset() {
    local mount_status
    if [[ "$2" == "yes" ]]; then mount_status="yes"
    else mount_status=$(zfs get -H -o value mounted "$1"); fi
    if [[ "$mount_status" == "yes" ]]; then
        zfs unmount "$1" &>/dev/null
        if [[ $(zfs get -H -o value mounted "$1") == "no" ]]; then echo_ts "Unmounted '$1'."
        else echo_ts "[⚠️] Could not unmount '$1'."; fi
    elif [[ "$mount_status" == "no" ]]; then echo_ts "[⚠️] '$1' was not mounted."; fi
}

replicate_dataset() {
    create_all_required_datasets_from_path "$REPLICATED_DATASET" "replication"
    if [ $? -ne 0 ]; then return; fi
    echo_ts "Starting ZFS replication using syncoid..."
    replicate_dataset_start_time=$EPOCHREALTIME
    /usr/local/sbin/syncoid $SYNCOID_ARGS "$SOURCE_DATASET" "$REPLICATED_DATASET" >/dev/null; local syncoid_exit=$?
    replicate_dataset_finish_time=$EPOCHREALTIME
    if [ $syncoid_exit -eq 0 ]; then echo_ts "[✔️] '$SOURCE_DATASET' >> '$REPLICATED_DATASET'. Successful Replication in $(run_timer $replicate_dataset_start_time $replicate_dataset_finish_time).";
    else echo_ts "[❌] Replication failed from '$SOURCE_DATASET' to '$REPLICATED_DATASET'."; fi
}

delete_old_extra_snapshots() {
    zfs list -t snapshot -o name,creation -S creation -r "$SOURCE_DATASET" | awk -v cutoff_date="$(date -d "$DELETE_EXTRA_SNAPSHOTS_OLDER_THAN_X_DAYS days ago" +%s)" '
    /autosnap_.*_extra/ {
        split($0, fields, " ")
        creation_date = fields[length(fields)-4] " " fields[length(fields)-3] " " fields[length(fields)-2] " " fields[length(fields)-1] " " fields[length(fields)]
        snapshot_name = substr($0, 1, length($0) - length(creation_date) - 1)
        cmd = "date -d \"" creation_date "\" +%s"
        cmd | getline snapshot_date
        close(cmd)
        if (snapshot_date < cutoff_date) { print snapshot_name }
    }' | while read -r snapshot; do
        zfs destroy "$snapshot" &>/dev/null
        echo_ts "Deleted old snapshot '$snapshot'."
    done
}

delete_old_snapshots() {
    /usr/local/sbin/sanoid --configdir="$SANOID_DOCKER_CONFIG_DIR" --prune-snapshots
    if [[ $DELETE_EXTRA_SNAPSHOTS_OLDER_THAN_X_DAYS =~ ^[0-9]+$ ]]; then delete_old_extra_snapshots; fi
}

complete_backup() {
    clean_up
    run_time=$(run_timer $script_start_time $EPOCHREALTIME)
    echo_ts "[${DOCKER_NAME^^} BACKUP FINISHED] Run Time: $run_time."
    if [[ $UNRAID_WEBGUI_SUCCESS_MSG == true ]]; then unraid_notify normal "Finished in $run_time."; fi
}

clone_recent_snapshot() {
    if ! zfs list -o name -H "$TEMP_DATASET_TO_CLONE_TO" &>/dev/null; then echo_ts "[❌] The source dataset '$TEMP_DATASET_TO_CLONE_TO' does not exist.."; return 1; fi
    cloned_mount_point=$TEMP_DATASET_TO_CLONE_TO/_temp_${SOURCE_DATASET##*/}
    zfs clone "$most_recent_autosnap_name" "$cloned_mount_point"
    if ! zfs list -o name -H "$cloned_mount_point" &>/dev/null; then echo_ts "[❌] Failed to clone '$most_recent_autosnap_name' to '$cloned_mount_point'."; return 1; fi
    echo_ts "Created clone '$cloned_mount_point' from '$most_recent_autosnap_name'."
    zfs set readonly=on "$cloned_mount_point"
    cloned_folder_path=$(zfs get -H -o value mountpoint "$cloned_mount_point")
}

perform_additional_backups() {
    clone_recent_snapshot
    if [ $? -ne 0 ]; then return; fi
    for pattern in "${EXCLUDES[@]}"; do exclude_arg+=("--exclude=${pattern}"); done
    if [[ $BACKUP_FILES == true ]]; then backup_files; fi
    if [[ $TAR_FILES == true ]]; then tar_files; fi
}

################################################################################
#                               BEGIN PROCESSING                               #
################################################################################

# Verify correctly set user variables and other error handling.
pre_checks_and_start_script

# Stop Docker.
if [[ $STOP_DOCKER == true ]]; then stop_docker; fi

# Create ZFS snapshot of docker container's appdata.
snapshot_dataset

# Start Docker.
if [[ $STOP_DOCKER == true ]]; then start_docker; fi

# Delete old snapshots.
delete_old_snapshots

# Replicate ZFS snapshot of docker container's appdata.
if [[ $REPLICATE_DATASET == true ]]; then replicate_dataset; fi

# Perform additional rsync and/or tarfile backups using a clone of most recent snapshot.
if [[ $BACKUP_FILES == true || $TAR_FILES == true ]]; then perform_additional_backups; fi

# Clean up checks and print backup complete message with run time for script.
complete_backup

# Exit with success.
exit 0
