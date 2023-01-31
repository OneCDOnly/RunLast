#!/usr/bin/env bash
###############################################################################
# runlast.sh - (C)opyright 2019-2023 OneCD - one.cd.only@gmail.com

# This script is part of the 'RunLast' package

# For more info: https://forum.qnap.com/viewtopic.php?f=320&t=145975

# Available in the MyQNAP store: https://www.myqnap.org/product/runlast
# Project source: https://github.com/OneCDOnly/RunLast

# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.

# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.

# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.
###############################################################################

readonly USER_ARGS_RAW=$*

Init()
    {

    QPKG_NAME=RunLast

    [[ ! -e /dev/fd ]] && ln -s /proc/self/fd /dev/fd   # sometimes, '/dev/fd' isn't created by QTS. Don't know why.

    local -r QPKG_PATH=$(/sbin/getcfg $QPKG_NAME Install_Path -f /etc/config/qpkg.conf)
    readonly REAL_LOG_PATHFILE=$QPKG_PATH/$QPKG_NAME.log
    readonly TEMP_LOG_PATHFILE=$REAL_LOG_PATHFILE.tmp
    readonly LINK_LOG_PATHFILE=/var/log/$QPKG_NAME.log
    local -r GUI_LOG_PATHFILE=/home/httpd/$QPKG_NAME.log
    readonly SYSV_STORE_PATH=$QPKG_PATH/init.d
    readonly SCRIPT_STORE_PATH=$QPKG_PATH/scripts
    readonly BUILD=$(/sbin/getcfg $QPKG_NAME Build -f /etc/config/qpkg.conf)
    readonly SERVICE_STATUS_PATHFILE=/var/run/$QPKG_NAME.last.operation

    /sbin/setcfg "$QPKG_NAME" Status complete -f /etc/config/qpkg.conf

    # KLUDGE: 'clean' the QTS 4.5.1 App Center notifier status
    [[ -e /sbin/qpkg_cli ]] && /sbin/qpkg_cli --clean "$QPKG_NAME" > /dev/null 2>&1
    [[ ${#USER_ARGS_RAW} -eq 0 ]] && echo "$QPKG_NAME ($BUILD)"
    [[ ! -e $REAL_LOG_PATHFILE ]] && touch "$REAL_LOG_PATHFILE"
    [[ -e $TEMP_LOG_PATHFILE ]] && rm -f "$TEMP_LOG_PATHFILE"
    [[ ! -L $GUI_LOG_PATHFILE ]] && ln -s "$REAL_LOG_PATHFILE" "$GUI_LOG_PATHFILE"
    [[ ! -L $LINK_LOG_PATHFILE ]] && ln -s "$REAL_LOG_PATHFILE" "$LINK_LOG_PATHFILE"
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
            ls "$SYSV_STORE_PATH"/* 2>/dev/null | while read -r script_pathname; do
                [[ -x $script_pathname ]] && RunAndLog "'$script_pathname' start"
            done
            ;;
        stop)
            # execute 'init.d' script names in reverse-order
            ls -r "$SYSV_STORE_PATH"/* 2>/dev/null | while read -r script_pathname; do
                [[ -x $script_pathname ]] && RunAndLog "'$script_pathname' stop"
            done
            ;;
        *)
            return 1
    esac

    }

ProcessScripts()
    {

    local script_pathname=''

    # read 'scripts' script names in order and execute
    ls "$SCRIPT_STORE_PATH"/* 2>/dev/null | while read -r script_pathname; do
        [[ -x $script_pathname ]] && RunAndLog "'$script_pathname'"
    done

    }

RunAndLog()
    {

    # $1 = command to run

    if [[ -z $1 ]]; then
        echo "command not specified"
        return 1
    fi

    echo "[$(date)] -> execute: \"$1\" ..." | tee -a "$TEMP_LOG_PATHFILE"

    {   # https://unix.stackexchange.com/a/430182/110015
        stdout=$(eval "$1" 2> /dev/fd/3)
        exitcode=$?
        stderr=$(cat<&3)
    } 3<<EOF
EOF

    echo -e "[$(date)] => exitcode: ($exitcode)\n[$(date)] => stdout: \"$stdout\"\n[$(date)] => stderr: \"$stderr\"" | tee -a "$TEMP_LOG_PATHFILE"

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

    /sbin/rmcfg "$1" -f /etc/config/qpkg.conf
    echo -e "$buffer" >> /etc/config/qpkg.conf

    }

ShowDataBlock()
    {

    # returns the data block for the QPKG name specified as $1

    if [[ -z $1 ]]; then
        echo "QPKG not specified"
        return 1
    fi

    if ! grep -q "$1" /etc/config/qpkg.conf; then
        echo "QPKG not found"
        return 2
    fi

    sl=$(grep -n "^\[$1\]" /etc/config/qpkg.conf | cut -f1 -d':')
    ll=$(wc -l < /etc/config/qpkg.conf | tr -d ' ')
    bl=$(tail -n$((ll-sl)) < /etc/config/qpkg.conf | grep -n '^\[' | head -n1 | cut -f1 -d':')
    [[ -n $bl ]] && el=$((sl+bl-1)) || el=$ll

    sed -n "$sl,${el}p" /etc/config/qpkg.conf

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

    local op="begin $1 ..."
    local buffer="[$(date)] $op"
    local length=${#buffer}
    local temp=$(printf "%${length}s")

    echo -e "${temp// /─}\n$QPKG_NAME ($BUILD)\n$buffer" > "$TEMP_LOG_PATHFILE"

    WriteQTSLog "$op" 0
    echo "$buffer"

    }

RecordEnd()
    {

    # $1 = operation

    local op="end $1"
    local buffer="[$(date)] $op"

    echo -e "$buffer" >> "$TEMP_LOG_PATHFILE"

    WriteQTSLog "$op" 0
    echo "$buffer"
    CommitGUILog
    SetServiceOperationResultOK

    }

RecordInfo()
    {

    # $1 = message

    local buffer="[$(date)] $1"

    echo -e "$buffer" >> "$TEMP_LOG_PATHFILE"

    WriteQTSLog "$1" 0
    echo "$buffer"

    }

RecordWarning()
    {

    # $1 = message

    local buffer="[$(date)] $1"

    echo -e "$buffer" >> "$TEMP_LOG_PATHFILE"

    WriteQTSLog "$1" 1
    echo "$buffer"

    }

RecordError()
    {

    # $1 = message

    local buffer="[$(date)] $1"

    echo -e "$buffer" >> "$TEMP_LOG_PATHFILE"

    WriteQTSLog "$1" 2
    echo "$buffer"

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

    log_tool --append "[$QPKG_NAME] $1" --type "$2"

    }

IsQPKGEnabled()
    {

    # input:
    #   $1 = package name to check
    # output:
    #   $? = 0 (true) or 1 (false)

    [[ -z $1 ]] && return 1

    if [[ $(/sbin/getcfg "$1" Enable -u -f /etc/config/qpkg.conf) != 'TRUE' ]]; then
        return 1
    else
        return 0
    fi

    }

SetServiceOperationResultOK()
    {

    SetServiceOperationResult ok

    }

SetServiceOperationResultFailed()
    {

    SetServiceOperationResult failed

    }

SetServiceOperationResult()
    {

    # $1 = result of operation to recorded

    [[ -n $1 && -n $SERVICE_STATUS_PATHFILE ]] && echo "$1" > "$SERVICE_STATUS_PATHFILE"

    }

Init

case "$1" in
    start)
        # shellcheck disable=SC2154
        if [[ $package_status = INSTALLING ]]; then
            operation='installation'
            RecordStart "$operation"
        else
            operation='"start" scripts'
            RecordStart "$operation"
            ProcessSysV start
            ProcessScripts
        fi
        RecordEnd "$operation"
        ;;
    stop)
        if [[ $package_status != INSTALLING ]]; then
            operation='package reorder'
            RecordStart "$operation"
            if IsQPKGEnabled SortMyQPKGs; then
                testver=$(/sbin/getcfg SortMyQPKGs Version -d 0 -f /etc/config/qpkg.conf)

                if [[ ${testver:0:6} -ge 181217 ]]; then
                    RecordInfo "SortMyQPKGs will reorder this package"
                else
                    RecordWarning "your SortMyQPKGs version is incompatible with this package"
                fi
            else
                SendToEnd "$QPKG_NAME"
            fi
            RecordEnd "$operation"

            operation='"stop" scripts'
            RecordStart "$operation"
            ProcessSysV stop
            RecordEnd "$operation"
        fi
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    *)
        echo "  use '$0 start' to execute files in the 'init.d' path, then the 'scripts' path"
        echo "  use '$0 stop' to execute files in the 'init.d' path in reverse order"
        echo "  use '$0 restart' to stop, then start this QPKG"
esac

[[ -e $TEMP_LOG_PATHFILE ]] && rm -f "$TEMP_LOG_PATHFILE"

exit 0
