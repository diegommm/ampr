#!/bin/bash

pingmon(){

#
#pingmon: Monitor a connection and determine it's status.
# Copyright (C) 2013 Diego Augusto Molina
#
# This program is free software; you can redistribute it and/or modify it under the terms of the GNU
# General Public Licence Version 2 as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public Licence for more details.
#
# You should have recieved a copy of the GNU General Public Licence along with this program; if not,
# write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307,
# USA.
#

##### Declaration ##################################################################################

    ## Strictness
  set -o posix;
  set -u;
  set +H;
  set +e;
  export LC_ALL=C;

    ## Aux vars
  local -r SIG_KEEP_ALIVE="### SIGNAL: KEEP ALIVE ###";
  local -r SIG_PING_FAILED="### SIGNAL: PING FAILED ###";
  local -r PINGMON_TRAPS="RETURN SIGTERM SIGINT SIGHUP EXIT";
  local -ar PING_OPTS_WO_ARGS=( A b B d n D U v ) PING_OPTS_W_ARGS=( m c i I l p Q s S t T M w W );
  local i=0;
  local -i retval=0;
  local -ir RET_OK_WORK=0 RET_OK_KEEP_GOING=125 RET_OK_NO_WORK=126 RET_FAIL_PRE_WORK=127;

    ## Default values
  local KEEP_ALIVE_TIME=3 REMOTE_HOST="";
  local -i PING_TIME_TRESHOLD=500 MAX_PING_TIME_COUNT=6 MAX_KEEP_ALIVE=3 MAX_UNSEQUENCED=10;
  local -i MAX_ICMP_FAIL=0 ACC_MIN_COUNT=5 QUIT_ON_ERROR=1 DRY_RUN=0;
  local -a REAL_PING_OPTS=();

##### Display help #################################################################################

    ## Display help if no arguments are recieved
  if [ $# -eq 0 ]; then
    echo -ne "
pingmon: Monitor a connection and determine it's status.
  Copyright (C) 2013 Diego Augusto Molina

  This program is free software; you can redistribute it and/or modify it under the terms of the GNU
  General Public Licence Version 2 as published by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
  even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
  General Public Licence for more details.

  You should have recieved a copy of the GNU General Public Licence along with this program; if not,
  write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307,
  USA.

Usage:
  $FUNCNAME [options] HOST

Options:
  -C ACC_MIN_COUNT (=$ACC_MIN_COUNT)
    Minimum consecutive good replies recieved before considering connection is acceptable. 0
    disables this function.
  -F MAX_ICMP_FAIL (=$MAX_ICMP_FAIL)
    Maximum number of consecutive non successful ICMP replies recieved (i.e. Net Unreachable, Host
    Unreachable, etc.). -1 disables this function.
  -k KEEP_ALIVE_TIME (=$KEEP_ALIVE_TIME)
    Interval of time in which ping answer is expected (option for 'sleep' command).
  -K MAX_KEEP_ALIVE (=$MAX_KEEP_ALIVE)
    Maximum number of KEEP_ALIVE_TIME intervals to wait before quitting when ping gives no output. 0
    disables this function.
  -n DRY_RUN (=$DRY_RUN)
    Determines wether to actually run (=0) or make checks and exit before actually doing anythig
    (!=0).
  -q QUIT_ON_ERROR (=$QUIT_ON_ERROR)
    If non zero, quit immediatly after detecting any connection error.
  -U MAX_UNSEQUENCED (=$MAX_UNSEQUENCED)
    Maximum number of consecutive out of sync ping responses to wait before quitting. -1 disables
    this function.
  -x PING_TIME_TRESHOLD (=$PING_TIME_TRESHOLD)
    Maximum ping time in milliseconds which do not trigger a treshold event.
  -X MAX_PING_TIME_COUNT (=$MAX_PING_TIME_COUNT)
    Maximum number of treshold events to wait before quitting. -1 disables this function.

The following is a white space separated list of arguments which will be accepted and passed to the
'ping' command:\n ">&2;
    for i in "${PING_OPTS_WO_ARGS[@]}"; do
      echo -n " -$i" >&2;
    done;
    for i in "${PING_OPTS_W_ARGS[@]}"; do
      echo -n " -$i ARG" >&2;
    done;
    echo "

These are the initial options passed to 'ping': ${REAL_PING_OPTS[*]:-(none set)}
" >&2;
    return $RET_OK_NO_WORK;
  fi;

##### Command line options proccessing #############################################################

    ## Arguments
  while [ $# -gt 0 ]; do

      ## Ping options which do not require additional arguments
    for i in "${PING_OPTS_WO_ARGS[@]}"; do
      if [ "$1" = "-$i" ]; then
        REAL_PING_OPTS[${#REAL_PING_OPTS[@]}]="$1";
        shift;
        continue 2;
      fi;
    done;

      ## Ping options which require additional arguments
    for i in "${PING_OPTS_W_ARGS[@]}"; do
      if [ "$1" = "-$i" ]; then
        if [ $# -gt 1 ]; then
          REAL_PING_OPTS[${#REAL_PING_OPTS[@]}]="$1";
          REAL_PING_OPTS[${#REAL_PING_OPTS[@]}]="$2";
          shift 2;
          continue 2;
        else
          echo "Expected argument for option '$1'." >&2;
          return $RET_FAIL_PRE_WORK;
        fi;
      fi;
    done;

      ## Own options, overwriting default values
    case "$1" in
      -C)
        ACC_MIN_COUNT="${2:?Expected argument for option "'$1'".}";
        if [ "$ACC_MIN_COUNT" != "$2" ] || [ $ACC_MIN_COUNT -lt 0 ]; then
          echo "Non negative integer expected as argument for option '$1'." >&2;
          return $RET_FAIL_PRE_WORK;
        fi;
        shift;
        ;;
      -F)
        MAX_ICMP_FAIL="${2:?Expected argument for option "'$1'".}";
        if [ "$MAX_ICMP_FAIL" != "$2" ] || [ $MAX_ICMP_FAIL -lt -1 ]; then
          echo "Integer greater than -2 expected as argument for option '$1'." >&2;
          return $RET_FAIL_PRE_WORK;
        fi;
        shift;
        ;;
      -k)
        KEEP_ALIVE_TIME="${2:?Expected argument for option "'$1'".}";
        if [ -n "$( echo "$KEEP_ALIVE_TIME" |
        sed 's/^[[:digit:]]*\(\.[[:digit:]]*\)\?[smhd]\?$//' )" ]; then
          echo -n "Invalid argument for keep alive time. It must satisfy regular expression " >&2;
          echo "'[[:digit:]]*\(\.[[:digit:]]*\)\?[smhd]\?'." >&2;
          return $RET_FAIL_PRE_WORK;
        fi;
        shift;
        ;;
      -n)
        DRY_RUN="${2:?Expected argument for option "'$1'".}";
        if [ "$DRY_RUN" != "$2" ]; then
          echo "Integer expected as argument for option '$1'." >&2;
          return $RET_FAIL_PRE_WORK;
        fi;
        shift;
        ;;
      -K)
        MAX_KEEP_ALIVE="${2:?Expected argument for option "'$1'".}";
        if [ "$MAX_KEEP_ALIVE" != "$2" ] || [ $MAX_KEEP_ALIVE -lt 0 ]; then
          echo "Non negative integer expected as argument for option '$1'." >&2;
          return $RET_FAIL_PRE_WORK;
        fi;
        shift;
        ;;
      -q)
        QUIT_ON_ERROR="${2:?Expected argument for option "'$1'".}";
        if [ "$QUIT_ON_ERROR" != "$2" ]; then
          echo "Integer expected as argument for option '$1'." >&2;
          return $RET_FAIL_PRE_WORK;
        fi;
        shift;
        ;;
      -U)
        MAX_UNSEQUENCED="${2:?Expected argument for option "'$1'".}";
        if [ "$MAX_UNSEQUENCED" != "$2" ] || [ $MAX_UNSEQUENCED -lt -1 ]; then
          echo "Integer greater than -2 expected as argument for option '$1'." >&2;
          return $RET_FAIL_PRE_WORK;
        fi;
        shift;
        ;;
      -x)
        PING_TIME_TRESHOLD="${2:?Expected argument for option "'$1'".}";
        if [ "$PING_TIME_TRESHOLD" != "$2" ] || [ $PING_TIME_TRESHOLD -lt 1 ]; then
          echo "Integer greater than zero expected as argument for option '$1'." >&2;
          return $RET_FAIL_PRE_WORK;
        fi;
        shift;
        ;;
      -X)
        MAX_PING_TIME_COUNT="${2:?Expected argument for option "'$1'".}";
        if [ "$MAX_PING_TIME_COUNT" != "$2" ] || [ $MAX_PING_TIME_COUNT -lt -1 ]; then
          echo "Integer greater than -2 expected as argument for option '$1'." >&2;
          return $RET_FAIL_PRE_WORK;
        shift;
        fi;
        ;;
      *)
        REMOTE_HOST="$1";
        ;;
    esac;
    shift;

  done;

##### Controls #####################################################################################

    # Make options readonly from now on, just to make sure we don't do something stupid later
  readonly KEEP_ALIVE_TIME REMOTE_HOST PING_TIME_TRESHOLD MAX_PING_TIME_COUNT MAX_KEEP_ALIVE;
  readonly MAX_UNSEQUENCED REAL_PING_OPTS MAX_ICMP_FAIL ACC_MIN_COUNT;

    ## Only the remote host is mandatory, all other arguments have safe defaults
  if [ -z "${REMOTE_HOST:-}" ]; then
    echo "No remote host given to ping." >&2;
    return $RET_FAIL_PRE_WORK;
  fi;

    ## Test ping for unacceptable options
  if [ ${#REAL_PING_OPTS[@]} -gt 0 ]; then
    if ! ping "${REAL_PING_OPTS[@]}" -c 1 127.0.0.1 > /dev/null; then
      echo -ne "\nFailed to ping '127.0.0.1'. Either something is *terribly* wrong in your" >&2;
      echo -ne " network configuration or you missed a ping configuration option. See above " >&2;
      echo "(something should have been written)." >&2;
      return $RET_FAIL_PRE_WORK;
    fi;
  fi;

    ## If on a dry run, quit before actually doing anythng
  if [ $DRY_RUN -ne 0 ]; then
    return $RET_OK_NO_WORK;
  fi;

##### Main program #################################################################################

    # Trap signals and kill background processes
  trap "kill -9 0;" $PINGMON_TRAPS;

    ## Work!
  while sleep 1; do
    {
      if [ $MAX_KEEP_ALIVE -gt 0 ]; then
        while sleep "$KEEP_ALIVE_TIME"; do
          echo "$SIG_KEEP_ALIVE";
        done & 
      fi;

      if [ ${#REAL_PING_OPTS[@]} -gt 0 ]; then
        ping "${REAL_PING_OPTS[@]}" "$REMOTE_HOST"
      else
        ping "$REMOTE_HOST"
      fi 2> /dev/null ||
        echo "$SIG_PING_FAILED";

      return $RET_OK_KEEP_GOING;
    } | {
      declare -i ping_time ping_time_count=0 keep_alive_count=0 req=-1 last_req=0 req_count=0;
      declare -i icmp_fail_count=0 acc_count=0 acc_status=0;
      declare aux="" PINGMON_REPLY="";

      while read PINGMON_REPLY; do

          # Ping failed
        if [ "$PINGMON_REPLY" = "$SIG_PING_FAILED" ]; then
          echo "### ERROR #1 Ping failed." >&2;
          acc_count=0;
          if [ $QUIT_ON_ERROR -ne 0 ]; then
            return 1;
          fi;
        fi;

          # Keep alive
        if [ $MAX_KEEP_ALIVE -gt 0 ]; then
          if [ "$PINGMON_REPLY" = "$SIG_KEEP_ALIVE" ]; then
            let keep_alive_count=1+$keep_alive_count;
            if [ $keep_alive_count -eq $(( $MAX_KEEP_ALIVE + 1 )) ]; then
              echo "### ERROR #2 Keep-alives exceeded maximum of $MAX_KEEP_ALIVE." >&2;
              acc_count=0;
              if [ $QUIT_ON_ERROR -ne 0 ]; then
                return 2;
              fi;
            fi;
            continue;
          fi;
        fi;

          # No signals caught so far? Then print the line, for it is actual part of ping's output
        echo "$PINGMON_REPLY";

          # Initialization
        acc_status=-1;
        keep_alive_count=0;

          # Ping time treshold
        if [ $MAX_PING_TIME_COUNT -ge 0 ]; then
          aux="$( echo "$PINGMON_REPLY" | sed -n 's/^.*time=\([[:digit:]]*\)[^[:digit:]].*$/\1/p' )";
          ping_time="$aux";
          if [ "$aux" = "$ping_time" ]; then
            if [ $acc_status -eq -1 ]; then
              acc_status=1;
            fi;
            if [ $ping_time -gt $PING_TIME_TRESHOLD ]; then
              acc_status=0;
              let ping_time_count=1+$ping_time_count;
              if [ $ping_time_count -eq $(( $MAX_PING_TIME_COUNT + 1 )) ]; then
                echo -n "### ERROR #3 Amount of consecutive pings with higher time than " >&2;
                echo -n "treshold of ${PING_TIME_TRESHOLD}ms exceeded maximum of " >&2;
                echo "$MAX_PING_TIME_COUNT." >&2;
                acc_count=0;
                if [ $QUIT_ON_ERROR -ne 0 ]; then
                  return 3;
                fi;
              fi;
            else
              ping_time_count=0;
            fi;
          fi;
        fi;

          # Ping sequence number
        if [ $MAX_UNSEQUENCED -ge 0 ]; then
          aux="$( echo "$PINGMON_REPLY" | sed -n 's/^.*icmp_[sr]eq=\([[:digit:]]*\)[^[:digit:]].*$/\1/p' )";
          req="$aux";
          if [ "$aux" = "$req" ]; then
            if [ $acc_status -eq -1 ]; then
              acc_status=1;
            fi;
            if [ $req -ne $(( $last_req + 1 )) ]; then
              acc_status=0;
              let req_count=1+$req_count;
              if [ $req_count -eq $(( $MAX_UNSEQUENCED + 1 )) ]; then
                echo -n "### ERROR #4 Amount of out of sequence consecutive pings exceeded " >&2;
                echo maximum of "$MAX_UNSEQUENCED." >&2;
                acc_count=0;
                if [ $QUIT_ON_ERROR -ne 0 ]; then
                  return 4;
                fi;
              fi;
            else
              req_count=0;
            fi;
            last_req=$req;
          fi;
        fi;

          # ICMP fail count
        if [ $MAX_ICMP_FAIL -ge 0 ]; then
          if echo "$PINGMON_REPLY" |
          grep -iqE "unreach|unknown|failed|isolated|prhibit|filtered|violation|cutoff|frag needed"; then
            acc_status=0;
            let icmp_fail_count=1+$icmp_fail_count;
            if [ $icmp_fail_count -eq $(( $MAX_ICMP_FAIL + 1 )) ]; then
              echo -n "### ERROR #5 Amount of consecutive non successful ICMP replies" >&2;
              echo " recieved exceeded maximum of $MAX_ICMP_FAIL." >&2;
              acc_count=0;
              if [ $QUIT_ON_ERROR -ne 0 ]; then
                return 5;
              fi;
            fi;
          fi;
        fi;

          # Acceptable connection
        if [ $ACC_MIN_COUNT -gt 0 ]; then
          if [ $acc_status -eq 1 ]; then
            let acc_count=1+$acc_count;
            if [ $acc_count -eq $ACC_MIN_COUNT ]; then
              echo "### ERROR #0 Acceptable connection" >&2;
                # Reset error counters
              keep_alive_count=0;
              ping_time_count=0;
              req_count=0;
              icmp_fail_count=0;
            fi;
          fi;
        fi;

      done;
    };
    retval=$?;

    if [ $retval -ne $RET_OK_KEEP_GOING ]; then
      return $retval;
    fi;

  done;

  return $RET_OK_WORK;
};

