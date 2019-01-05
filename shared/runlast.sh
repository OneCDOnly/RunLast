#!/usr/bin/env bash
############################################################################
# runlast.sh - (C)opyright 2019 OneCD [one.cd.only@gmail.com]
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
    LC_ALL=C

    [[ ! -e $CONFIG_PATHFILE ]] && { echo "file not found [$CONFIG_PATHFILE]"; exit 1 ;}

    local QPKG_PATH=$(getcfg $THIS_QPKG_NAME Install_Path -f "$CONFIG_PATHFILE")
    REAL_LOG_PATHFILE="${QPKG_PATH}/${THIS_QPKG_NAME}.log"
    TEMP_LOG_PATHFILE="${REAL_LOG_PATHFILE}.tmp"
    GUI_LOG_PATHFILE="/home/httpd/${THIS_QPKG_NAME}.log"
    SCRIPT_STORE_PATH="${QPKG_PATH}/scripts"

    [[ ! -e $REAL_LOG_PATHFILE ]] && touch "$REAL_LOG_PATHFILE"
    [[ -e $TEMP_LOG_PATHFILE ]] && rm -f "$TEMP_LOG_PATHFILE"
    [[ ! -L $GUI_LOG_PATHFILE ]] && ln -s "$REAL_LOG_PATHFILE" "$GUI_LOG_PATHFILE"
    [[ ! -d $SCRIPT_STORE_PATH ]] && mkdir -p "$SCRIPT_STORE_PATH"

    }

ProcessScripts()
    {

    [[ $exitcode -gt 0 ]] && return

    for i in ${SCRIPT_STORE_PATH}/*; do
        if [[ -x $i ]]; then
            echo "[$(date)] $i" >> "$TEMP_LOG_PATHFILE"
            $i 2>&1 >> "$TEMP_LOG_PATHFILE"
        fi
    done

    }

SendToEnd()
    {

    # sends $1 to the end of qpkg.conf

    local buffer=$(ShowDataBlock "$1")
    [[ $? -gt 0 ]] && { echo "error - ${buffer}!"; return 2 ;}

    rmcfg "$1" -f "$CONFIG_PATHFILE"
    echo -e "$buffer" >> "$CONFIG_PATHFILE"

    }

ShowDataBlock()
    {

    # returns the data block for the QPKG name specified as $1

    [[ -z $1 ]] && { echo "QPKG not specified"; return 1 ;}
    ! (grep -q $1 $CONFIG_PATHFILE) && { echo "QPKG not found"; return 2 ;}

    sl=$(grep -n "^\[$1\]" "$CONFIG_PATHFILE" | cut -f1 -d':')
    ll=$(wc -l < "$CONFIG_PATHFILE" | tr -d ' ')
    bl=$(tail -n$((ll-sl)) < "$CONFIG_PATHFILE" | grep -n '^\[' | head -n1 | cut -f1 -d':')
    [[ ! -z $bl ]] && el=$((sl+bl-1)) || el=$ll

    echo "$(sed -n "$sl,${el}p" "$CONFIG_PATHFILE")"

    }

TrimGUILog()
    {

    local max_ops=10
    local op_lines=$(grep -n "^──" "$REAL_LOG_PATHFILE")
    local op_count=$(echo "$op_lines" | wc -l)

    if [[ $op_count -gt $max_ops ]]; then
        local last_op_line_num=$(echo "$op_lines" | head -n$((max_ops+1)) | tail -n1 | cut -f1 -d:)
        head -n${last_op_line_num} "$REAL_LOG_PATHFILE" > "$TEMP_LOG_PATHFILE"
        mv "$TEMP_LOG_PATHFILE" "$REAL_LOG_PATHFILE"
    fi

    }

RecordStart()
    {

    # $1 = operation

    local buffer="[$(date)] '$1' started"
    local length=${#buffer}
    local temp=$(printf "%${length}s")
    local build=$(getcfg $THIS_QPKG_NAME Build -f $CONFIG_PATHFILE)

    echo -e "${temp// /─}\n$THIS_QPKG_NAME ($build)\n$buffer\n" >> "$TEMP_LOG_PATHFILE"

    WriteQTSLog "'$1' started" 0
    echo "'$1' started"

    }

RecordComplete()
    {

    # $1 = operation

    local buffer="\n[$(date)] '$1' completed"

    echo -e "$buffer" >> "$TEMP_LOG_PATHFILE"

    WriteQTSLog "'$1' completed" 0
    echo "'$1' completed"

    }

RecordWarning()
    {

    # $1 = message

    local buffer="\n[$(date)] '$1'"

    echo -e "$buffer" >> "$TEMP_LOG_PATHFILE"

    WriteQTSLog "'$1'" 1
    echo "'$1'"

    }

RecordError()
    {

    # $1 = message

    local buffer="\n[$(date)] '$1'"

    echo -e "$buffer" >> "$TEMP_LOG_PATHFILE"

    WriteQTSLog "'$1'" 2
    echo "'$1'"

    }

CommitGUILog()
    {

    echo -e "$(<$TEMP_LOG_PATHFILE)\n$(<$REAL_LOG_PATHFILE)" > "$REAL_LOG_PATHFILE"

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
    #   $package_is_enabled = true / false
    #   $? = 0 (true) or 1 (false)

    package_is_enabled=false

    [[ -z $1 ]] && return 1

    if [[ $(getcfg "$1" Enable -u -f "$CONFIG_PATHFILE") != 'TRUE' ]]; then
        return 1
    else
        package_is_enabled=true
        return 0
    fi

    }

Init

case "$1" in
    start)
        if [[ $package_status = INSTALLING ]]; then
            operation='installation'
            RecordStart "$operation"
        else
            operation='script processing'
            RecordStart "$operation"
            ProcessScripts
        fi
        RecordComplete "$operation"
        CommitGUILog
        ;;
    stop)
        if [[ $package_status != REMOVE ]]; then
            operation='package shuffle'
            RecordStart "$operation"
            if (IsQPKGEnabled SortMyQPKGs); then
                if [[ $(getcfg SortMyQPKGs Version -d 0 -f $CONFIG_PATHFILE) -ge 181217 ]]; then
                    RecordWarning "SortMyQPKGs will be used to reorder this package"
                else
                    RecordError "SortMyQPKGs version is incompatible with this package"
                fi
            else
                SendToEnd $THIS_QPKG_NAME
            fi
            RecordComplete "$operation"
            CommitGUILog
        fi
        ;;
    *)
        # do nothing
        sleep 1
        ;;
esac

[[ -e $TEMP_LOG_PATHFILE ]] && rm -f "$TEMP_LOG_PATHFILE"
