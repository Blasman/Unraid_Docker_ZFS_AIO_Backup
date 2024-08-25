# Unraid Docker Container ZFS AIO Backup Script

A user script for Unraid that utilizes the capabilities of the ZFS filesytem to backup a *single* docker containers appdata (or any files/folders) and minimize docker downtime. Although originally intended for Plex appdata, it can be used for any docker container. It is ideal for large/complex appdata datasets.

For creating ZFS snapshots and backups for *any/all* of your docker containers appdata datasets, see my [Appdata Backup ZFS Script](https://github.com/Blasman/Appdata_Backup_ZFS_Script) instead of or in addition to this one.

The basic functions of this script work as follows:
1. Stop docker.
2. Take snapshot of docker appdata dataset by using [sanoid](https://github.com/jimsalterjrs/sanoid).
3. Start docker.
4. Optional: Replicate dataset/snapshots to another pool/dataset by using [syncoid](https://github.com/jimsalterjrs/sanoid?tab=readme-ov-file#syncoid).

Then, by creating a temporary clone of the snapshot from step 2 above, the script may perform the various functions:

5. Optional: Backup files using rsync (ideal for Plex database files).
6. Optional: Tar files (ideal for Plex 'Media' and 'Metadata' folders).

## Installation (easiest way)
1. Copy and paste the scripts [RAW text](https://raw.githubusercontent.com/Blasman/Unraid_Docker_ZFS_AIO_Backup/main/docker_ZFS_AIO_backup.sh) as a new custom user script in Unraid's [CA User Scripts plugin](https://forums.unraid.net/topic/48286-plugin-ca-user-scripts/).
   
2. Edit all the required/desired sections in the 'user config' at the top of the script and then save the changes. Carefully read all the comments there as every option is explained.
   
3. Set a cron schedule in the User Scripts plugin for the script.

## Log File Example

See the sample log file for an ideal of how the script functions:

```
[2024_08_19 13:29:50.435] [PLEX BACKUP STARTED]
[2024_08_19 13:29:50.436] Stopping plex docker...
[2024_08_19 13:29:53.760] plex docker stopped in 3.323s.
[2024_08_19 13:29:53.760] Creating ZFS snapshot of 'pool_main/appdata/plex' using sanoid...
[2024_08_19 13:29:54.032] [✔️] 'pool_main/appdata/plex@autosnap_2024-08-19_13:29:53_daily' created in .2509s.
[2024_08_19 13:29:54.044] Starting plex docker...
[2024_08_19 13:29:54.217] plex docker started in .1711s. ⏱️ 3.779s of total plex downtime since start of 'docker stop' command.
[2024_08_19 13:29:54.316] Starting ZFS replication using syncoid...
[2024_08_19 13:29:54.775] [✔️] 'pool_main/appdata/plex' >> 'pool_ssds/backup_appdata/plex'. Successful Replication in .4589s.
[2024_08_19 13:29:54.803] Created clone 'pool_main/temp/_temp_plex' from 'pool_main/appdata/plex@autosnap_2024-08-19_13:29:53_daily'.
[2024_08_19 13:29:54.851] Mounted 'pool_ssds/backup_plex_db'.
[2024_08_19 13:29:54.875] Copying files to '/mnt/pool_ssds/backup_plex_db/[2024_08_19@13.29.54] plex Backup'...
[2024_08_19 13:29:55.959] [✔️] Copied 1017MB of data in 1.076s. 
[2024_08_19 13:29:56.044] Destroyed clone 'pool_main/temp/_temp_plex'.
[2024_08_19 13:29:58.158] Unmounted 'pool_ssds/backup_plex_db'.
[2024_08_19 13:29:58.173] [PLEX BACKUP FINISHED] Run Time: 7.737s.
```
