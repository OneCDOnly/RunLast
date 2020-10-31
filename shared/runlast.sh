#!/usr/bin/env bash
############################################################################
# runlast.sh - (C)opyright 2019-2020 OneCD [one.cd.only@gmail.com]
#
# This script is part of the 'RunLast' package
#
# For more info: [https://forum.qnap.com/viewtopic.php?f=320&t=145975]
#
# Available in the Qnapclub Store: [https://qnapclub.eu/en/qpkg/690]
# Project source: [https://github.com/OneCDOnly/RunLast]
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.
############################################################################

Init()
    {

    THIS_QPKG_NAME=RunLast
    CONFIG_PATHFILE=/etc/config/qpkg.conf

    if [[ ! -e $CONFIG_PATHFILE ]]; then
        echo "file not found [$CONFIG_PATHFILE]"
        exit 1
    fi

    readonly GETCFG_CMD=/sbin/getcfg
    readonly RMCFG_CMD=/sbin/rmcfg
    local -r QPKG_PATH=$($GETCFG_CMD $THIS_QPKG_NAME Install_Path -f "$CONFIG_PATHFILE")
    readonly REAL_LOG_PATHFILE=$QPKG_PATH/$THIS_QPKG_NAME.log
    readonly TEMP_LOG_PATHFILE=$REAL_LOG_PATHFILE.tmp
    local -r GUI_LOG_PATHFILE=/home/httpd/$THIS_QPKG_NAME.log
    readonly SYSV_STORE_PATH=$QPKG_PATH/init.d
    readonly SCRIPT_STORE_PATH=$QPKG_PATH/scripts
    readonly BUILD=$($GETCFG_CMD $THIS_QPKG_NAME Build -f $CONFIG_PATHFILE)
    readonly LC_ALL=C

    echo "$THIS_QPKG_NAME ($BUILD)"

    [[ ! -e $REAL_LOG_PATHFILE ]] && touch "$REAL_LOG_PATHFILE"
    [[ -e $TEMP_LOG_PATHFILE ]] && rm -f "$TEMP_LOG_PATHFILE"
    [[ ! -L $GUI_LOG_PATHFILE ]] && ln -s "$REAL_LOG_PATHFILE" "$GUI_LOG_PATHFILE"
    [[ ! -d $SYSV_STORE_PATH ]] && mkdir -p "$SYSV_STORE_PATH"
    [[ ! -d $SCRIPT_STORE_PATH ]] && mkdir -p "$SCRIPT_STORE_PATH"

    }

ProcessSysV()
    {

    # $1 = 'start' or 'stop'

    [[ -z $1 ]] && return

    local script_pathname=''

    case $1 in
        start)
            # execute 'init.d' script names in-order
            ls "$SYSV_STORE_PATH"/* 2>/dev/null | while read script_pathname; do
                [[ -x $script_pathname ]] && RunAndLog "'$script_pathname' start"
            done
            ;;
        stop)
            # execute 'init.d' script names in reverse-order
            ls -r "$SYSV_STORE_PATH"/* 2>/dev/null | while read script_pathname; do
                [[ -x $script_pathname ]] && RunAndLog "'$script_pathname' stop"
            done
            ;;
        *)
            return 1
            ;;
    esac

    }

ProcessScripts()
    {

    local script_pathname=''

    # read 'scripts' script names in order and execute
    ls "$SCRIPT_STORE_PATH"/* 2>/dev/null | while read script_pathname; do
        [[ -x $script_pathname ]] && RunAndLog "'$script_pathname'"
    done

    }

RunAndLog()
    {

    # $1 = command to run

    [[ -z $1 ]] && return 1

    echo "[$(date)] executing: \"$1\" ..." | tee -a "$TEMP_LOG_PATHFILE"

    {   # https://unix.stackexchange.com/a/430182/110015
        stdout=$(eval "$1" 2> /dev/fd/3)
        returncode=$?
        stderr=$(cat<&3)
    } 3<<EOF
EOF

    echo -e "[$(date)] returncode: ($returncode)\n[$(date)] stdout: \"$stdout\"\n[$(date)] stderr: \"$stderr\"" | tee -a "$TEMP_LOG_PATHFILE"

    return 0

    }

SendToEnd()
    {

    # sends $1 to the end of qpkg.conf

    local buffer=$(ShowDataBlock "$1")
    if [[ $? -gt 0 ]]; then
        echo "error - ${buffer}!"
        return 2
    fi

    $RMCFG_CMD "$1" -f "$CONFIG_PATHFILE"
    echo -e "$buffer" >> "$CONFIG_PATHFILE"

    }

ShowDataBlock()
    {

    # returns the data block for the QPKG name specified as $1

    [[ -z $1 ]] && { echo "QPKG not specified"; return 1 ;}
    ! (grep -q "$1" $CONFIG_PATHFILE) && { echo "QPKG not found"; return 2 ;}

    sl=$(grep -n "^\[$1\]" "$CONFIG_PATHFILE" | cut -f1 -d':')
    ll=$(wc -l < "$CONFIG_PATHFILE" | tr -d ' ')
    bl=$(tail -n$((ll-sl)) < "$CONFIG_PATHFILE" | grep -n '^\[' | head -n1 | cut -f1 -d':')
    [[ ! -z $bl ]] && el=$((sl+bl-1)) || el=$ll

    sed -n "$sl,${el}p" "$CONFIG_PATHFILE"

    }

TrimGUILog()
    {

    local max_ops=10
    local op_lines=$(grep -n "^──" "$REAL_LOG_PATHFILE")
    local op_count=$(echo "$op_lines" | wc -l)

    if [[ $op_count -gt $max_ops ]]; then
        local last_op_line_num=$(echo "$op_lines" | head -n$((max_ops+1)) | tail -n1 | cut -f1 -d:)
        head -n"$last_op_line_num" "$REAL_LOG_PATHFILE" > "$TEMP_LOG_PATHFILE"
        mv "$TEMP_LOG_PATHFILE" "$REAL_LOG_PATHFILE"
    fi

    }

RecordStart()
    {

    # $1 = operation

    local op="$1 started"
    local buffer="[$(date)] $op"
    local length=${#buffer}
    local temp=$(printf "%${length}s")

    echo -e "${temp// /─}\n$THIS_QPKG_NAME ($BUILD)\n$buffer" > "$TEMP_LOG_PATHFILE"

    WriteQTSLog "$op" 0
    echo "$buffer"

    }

RecordComplete()
    {

    # $1 = operation

    local op="$1 completed"
    local buffer="[$(date)] $op"

    echo -e "$buffer" >> "$TEMP_LOG_PATHFILE"

    WriteQTSLog "$op" 0
    echo "$buffer"
    CommitGUILog

    }

RecordWarning()
    {

    # $1 = message

    local buffer="\n[$(date)] $1"

    echo -e "$buffer" >> "$TEMP_LOG_PATHFILE"

    WriteQTSLog "$1" 1
    echo "$1"

    }

RecordError()
    {

    # $1 = message

    local buffer="\n[$(date)] $1"

    echo -e "$buffer" >> "$TEMP_LOG_PATHFILE"

    WriteQTSLog "$1" 2
    echo "$1"

    }

CommitGUILog()
    {

    echo -e "$(<"$TEMP_LOG_PATHFILE")\n$(<"$REAL_LOG_PATHFILE")" > "$REAL_LOG_PATHFILE"

    TrimGUILog

    }

WriteQTSLog()
    {

    # $1 = message to write into NAS system log
    # $2 = event type:
    #    0 : Information
    #    1 : Warning
    #    2 : Error

    log_tool --append "[$THIS_QPKG_NAME] $1" --type "$2"

    }

IsQPKGEnabled()
    {

    # input:
    #   $1 = package name to check
    # output:
    #   $? = 0 (true) or 1 (false)

    [[ -z $1 ]] && return 1

    if [[ $($GETCFG_CMD "$1" Enable -u -f "$CONFIG_PATHFILE") != 'TRUE' ]]; then
        return 1
    else
        return 0
    fi

    }

Init

case "$1" in
    start)
        # shellcheck disable=SC2154
        if [[ $package_status = INSTALLING ]]; then
            operation='installation'
            RecordStart "$operation"
        else
            operation='script processing'
            RecordStart "$operation"
            ProcessSysV start
            ProcessScripts
        fi
        RecordComplete "$operation"
        ;;
    stop)
        if [[ $package_status != REMOVE ]]; then
            operation='package shuffle'
            RecordStart "$operation"
            if IsQPKGEnabled SortMyQPKGs; then
                if [[ $($GETCFG_CMD SortMyQPKGs Version -d 0 -f $CONFIG_PATHFILE) -ge 181217 ]]; then
                    RecordWarning "SortMyQPKGs will reorder this package"
                else
                    RecordError "your SortMyQPKGs version is incompatible with this package"
                fi
            else
                SendToEnd $THIS_QPKG_NAME
            fi
            RecordComplete "$operation"
        fi
        operation='script processing'
        RecordStart "$operation"
        ProcessSysV stop
        RecordComplete "$operation"
        ;;
    *)
        echo "use '$0 start' to execute files in the 'init.d' path, then the 'scripts' path"
        echo "use '$0 stop' to execute files in the 'init.d' path in reverse order"
        ;;
esac

[[ -e $TEMP_LOG_PATHFILE ]] && rm -f "$TEMP_LOG_PATHFILE"
