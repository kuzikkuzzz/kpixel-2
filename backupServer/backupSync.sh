#!/bin/bash
TMPDIR="/tmp/backup"
SSHHOST="storage"
DESTPATH="/srv/canvas"

DATE_TODAY=`printf "%(%Y/%m/%d)T" -1`
DATE_YESTERDAY=`printf "%(%Y/%m/%d)T" $(( $(printf "%(%s)T" -1) - 24*3600 ))`

#delete older daily backup folders from local filesystem if exist
if [ -d "${TMPDIR}/${DATE_YESTERDAY}" ]
  then
    rm -rf "${TMPDIR}/${DATE_YESTERDAY}"
    echo "Deleting folder of past day ${DATE_YESTERDAY}"
fi

echo "Syncing"

set -e
rsync -v -r ${TMPDIR}/ ${SSHHOST}:${DESTPATH}

#clear current daily folder
#we do NOT delete the daily folder itself, because the backup script would create
#a new full backup if it's missing
rm -rf ${TMPDIR}/${DATE_TODAY}/*
