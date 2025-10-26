#!/bin/sh
set -e
TODAY_YEAR=`date +%Y`
TODAY_MONTH=`date +%m`
TODAY_DAY=`date +%d`

clean_backup_dir () {
  local PPWD=${PWD}
  local BACKUP_DIR="${1}"
  cd "${BACKUP_DIR}" 
  for FILE in *; do
    [ "`echo ${FILE} | sed -n '/^[0-9]\{8\}-/p'`" != "${FILE}" ] && {
      echo "${FILE} is not a backup file"
      continue
    }
    local YEAR=$(expr substr $FILE 1 4)
    local MONTH=$(expr substr $FILE 5 2)
    local DAY=$(expr substr $FILE 7 2)
    # should not need that since sed got it covered above
    #[ $(expr "x$YEAR" : "x[0-9]*$") -eq 0 ]  || [ $(expr "x$YEAR" : "x[0-9]*$") -eq 0 ] || [ $(expr "x$YEAR" : "x[0-9]*$") -eq 0 ] && {
    #  echo "${FILE} not a backup file"
    #  continue
    #}
    [ $YEAR -eq  $TODAY_YEAR ] && [ $MONTH -eq $TODAY_MONTH ] && {
      echo "${FILE} is current month, do not delete it"
      continue
    }
    [ $DAY -eq 1 ] && {
      echo "${FILE} is first backup in month, do not delete it"
      continue
    }
    [ $YEAR -eq $TODAY_YEAR ] && [ $(expr $TODAY_MONTH - $MONTH) -eq 1 ] && [ $(expr $TODAY_DAY - $DAY) -lt 0 ] && {
      echo "${FILE} is within a month, do not delete it"
      continue
    }
    [ $TODAY_MONTH -eq 1 ] && [ $MONTH -eq 12 ] && [ $(expr $TODAY_DAY - $DAY) -lt 0 ] && {
      echo "${FILE} is within a month, do not delete it"
      continue
    }
    echo "DELETE ${FILE}"
    rm "${FILE}"
  done
  cd ${PWD}
}

clean_backup_dir "/srv/backups/redis-backups"
clean_backup_dir "/srv/backups/mysql-backups"
