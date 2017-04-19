#!/bin/bash
#
#  USAGE:
#    secure_files [-dogscfhv]
#
#  OPTIONS
#    -d   delete the file if it is an orphan
#    -o   Check for file ownership
#    -g   Check for group ownership
#    -s   Sticky Bit check
#    -c   Change it - correct it for all check types
#    -f   force (ie, don't prompt)
#    -h   display help text
#    -v   verbose

OPTERR=0
STICKYCHK=1
WWFILESCHK=0
VERBOSE=0
CHANGEIT=0
LOGDIR=/var/log/security

# Random Sleep
# sleep $[ ( $RANDOM % 3600 ) +1 ]s

# Output functions both screen and logfile
function printOK {
  echo -e "${GREEN}[OK]\t\t $1 ${RESET}"
  echo -e "$(date +'%H:%M:%S') - [OK] - $1" >> "${LOGFILE}"
}

function printWarning {
  echo -e "$(date +'%H:%M:%S') - [WARN] - $1" >> "${LOGFILE}"
}

function printError {
  echo -e "$(date +'%H:%M:%S') - [ERROR] - $1" >> "${LOGFILE}"
}

function printInfo {
  echo -e "$(date +'%H:%M:%S') - [INFO] - $1" >> "${LOGFILE}"
}

function remedialAction {
  echo -e "$1" | tee -a "${LOGFILE}"
}

add_log_dir()
{
  if [ ! -d ${LOGDIR} ]; then
     [ ${VERBOSE} -eq 1 ] && echo "No log file directory found. Will create."
    mkdir -p ${LOGDIR}
  fi
  [ ${VERBOSE} -eq 1 ] && echo "Changing ${LOGDIR} permissions to root:root only"
  chown root:root ${LOGDIR}
  chmod 700 ${LOGDIR}
}

sticky_bit_check()
{
  SBCLOG=${LOGDIR}/world-write-dir-sticky-bits
  if [ -f ${SBCLOG} ]; then
    rm -f ${SBCLOG}
  fi
  [ ${VERBOSE} -eq 1 ] && echo "Working on world-writable directories without the sticky-bit set"
  /bin/df --local -P | /usr/bin/awk {'if (NR!=1) print $6'} | /usr/bin/xargs -I '{}' /usr/bin/find '{}' -xdev -type d \( -perm -0002 -a ! -perm -1000 \) > /tmp/.unstickydir.$$
  SBCEXCLUDES=/usr/local/etc/world-write-dir-excludes
  if [ ! -f ${SBCEXCLUDES} ]; then
    touch ${SBCEXCLUDES}
  fi
  FILECOUNT=$(sed '/^\s*$/d' /tmp/.unstickydir.$$ | wc -l)
  if [ "${FILECOUNT}" -eq 0 ]; then
     [ ${VERBOSE} -eq 1 ] && echo "No un-stickybit directories found"
    rm -f /tmp/.unstickydir.$$
    return 0
  else
    [ ${VERBOSE} -eq 1 ] && echo "Found some world writable directories without the sticky bit on them..."
    for FILEPATH in `cat /tmp/.unstickydir.$$`
    do
      if [ -f ${SBCEXCLUDES} ]; then
        grep -Eq "${FILEPATH}$" ${SBCEXCLUDES} && EXCLUDEIT=1 || EXCLUDEIT=0
      else
        EXCLUDEIT=0
      fi  
      if [ ${EXCLUDEIT} -eq 1 ]; then
        [ ${VERBOSE} -eq 1 ] && echo "${FILEPATH} is listed as an exclusion"
      else
        [ ${VERBOSE} -eq 1 ] && echo "Working on directory: ${FILEPATH}"
        if [ -d "${FILEPATH}" ]; then
          if [ ${CHANGEIT} -eq 1 ]; then
            [ ${VERBOSE} -eq 1 ] && echo "Adding sticky bit to directory"
            chmod 1777 "${FILEPATH}"
          else
            echo "Directory: ${FILEPATH} is showing as a world-writable directory without sticky-bit set" >> ${SBCLOG}
          fi
        else
          [ ${VERBOSE} -eq 1 ] && echo "File: ${FILEPATH} not a file, directory , or missing"
        fi
      fi
    done
    if [ -f "${SBCLOG}" ]; then
      NUMOFWWD=$(wc -l "${SBCLOG}" | awk '{print $1}')
      logger -p authpriv.info "Number of world-writable directories without sticky-bit set: ${NUMOFWWD}"
    fi
  fi
  rm -f /tmp/.unstickydir.$$
}

world_writable_files_check()
{
  WWFLOG=${LOGDIR}/world-write-files
  if [ -f ${WWFLOG} ]; then
    rm -f ${WWFLOG}
  fi
  [ ${VERBOSE} -eq 1 ] && echo "Working on world-writable files"
  /bin/df --local -P | /usr/bin/awk {'if (NR!=1) print $6'} | /usr/bin/xargs -I '{}' /usr/bin/find '{}' -xdev -type f \( -perm -0002 \) > /tmp/.wwfiles.$$
  WWFEXCLUDES=/usr/local/etc/world-write-files-excludes
  if [ ! -f ${WWFEXCLUDES} ]; then
    touch ${WWFEXCLUDES}
  fi
  WWFCOUNT=$(sed '/^\s*$/d' /tmp/.wwfiles.$$ | wc -l)
  if [ "${WWFCOUNT}" -eq 0 ]; then
     [ ${VERBOSE} -eq 1 ] && echo "No world-writable files found"
    rm -f /tmp/.wwfiles.$$
    return 0
  else
    [ ${VERBOSE} -eq 1 ] && echo "Found some world writable files."
    for WWFFILE in `cat /tmp/.wwfiles.$$`
    do
      if [ -f ${WWFEXCLUDES} ]; then
        grep -Eq "${WWFFILE}$" ${WWFEXCLUDES}  && EXCLUDEIT=1 || EXCLUDEIT=0
      else
        EXCLUDEIT=0
      fi
      if [ ${EXCLUDEIT} -eq 1 ]; then
        [ ${VERBOSE} -eq 1 ] && echo "${WWFFILE} is listed as an exclusion"
      else
        [ ${VERBOSE} -eq 1 ] && echo "Working on file: ${WWFFILE}"
        if [ -f "${WWFFILE}" ]; then
          if [ ${CHANGEIT} -eq 1 ]; then
            [ ${VERBOSE} -eq 1 ] && echo "Removing world write ability from ${WWFFILE}"
            chmod o-w "${WWFFILE}"
          else
            echo "File: ${WWFFILE} is showing as a world-writable file." >> ${WWFLOG}
          fi
        else
          [ ${VERBOSE} -eq 1 ] && echo "File: ${FILEPATH} not a file ?"
        fi
      fi
    done
    if [ -f "${WWFLOG}" ]; then
      NUMOFWWF=$(wc -l "${WWFLOG}" | awk '{print $1}')
      logger -p authpriv.info "Number of world-writable files: ${NUMOFWWF}"
    fi
  fi
  rm -f /tmp/.wwfiles.$$
}

usage()
{
  echo
  echo "  USAGE:"
  echo "    file_cleanup [-dogscfhv]"
  echo
  echo "  OPTIONS:"
  echo "    -a   Run all file checks"
  echo "    -w   World-Writable Files Check"
  echo "    -d   World-Writable Directories Sticky Bit Check"
  echo "    -c   Changes Applied - will add stickybit to WW directories and remove world write from files"
  echo "    -h   display this help text"
  echo "    -v   verbose"
  echo
}

  while getopts awdchv opt
  do
    case $opt in
      a)
        STICKYCHK=1
        WWFILESCHK=1
      ;;
      w)
        WWFILESCHK=1
      ;;
      d)
        STICKYCHK=1
      ;;
      c)
        CHANGEIT=1
      ;;
      h)
        usage
      ;;
      v)
        VERBOSE=1
      ;;
      *)
        echo "unrecognized flag $OPTARG"
      ;;
    esac
done

add_log_dir

if [ ${STICKYCHK} -eq 1 ]; then
  sticky_bit_check
fi

if [ ${WWFILESCHK} -eq 1 ]; then
  world_writable_files_check
fi

exit 0
