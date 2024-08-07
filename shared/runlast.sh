#!/usr/bin/env bash
###############################################################################
# runlast.sh
#	copyright 2019-2024 OneCD
#
# Contact:
#	one.cd.only@gmail.com
#
# This script is part of the 'RunLast' package
#
# Available in the MyQNAP store: https://www.myqnap.org/product/runlast
# Project source: https://github.com/OneCDOnly/RunLast
# Community forum: https://forum.qnap.com/viewtopic.php?t=145975
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
###############################################################################

set -o nounset -o pipefail
shopt -s extglob
ln -fns /proc/self/fd /dev/fd		# KLUDGE: `/dev/fd` isn't always created by QTS.

readonly USER_ARGS_RAW=$*

Init()
    {

    readonly QPKG_NAME=RunLast

    local -r QPKG_PATH=$(/sbin/getcfg $QPKG_NAME Install_Path -f /etc/config/qpkg.conf)
		readonly SCRIPT_STORE_PATH=$QPKG_PATH/scripts
		readonly SYSV_STORE_PATH=$QPKG_PATH/init.d

    readonly QPKG_VERSION=$(/sbin/getcfg $QPKG_NAME Version -f /etc/config/qpkg.conf)
    local -r GUI_LOG_PATHFILE=/home/httpd/$QPKG_NAME.log
    readonly LINK_LOG_PATHFILE=/var/log/$QPKG_NAME.log
    readonly REAL_LOG_PATHFILE=$QPKG_PATH/$QPKG_NAME.log
		readonly TEMP_LOG_PATHFILE=$REAL_LOG_PATHFILE.tmp
	readonly SERVICE_ACTION_PATHFILE=/var/log/$QPKG_NAME.action
	readonly SERVICE_RESULT_PATHFILE=/var/log/$QPKG_NAME.result

    /sbin/setcfg "$QPKG_NAME" Status complete -f /etc/config/qpkg.conf

    # KLUDGE: 'clean' the QTS 4.5.1 App Center notifier status
    [[ -e /sbin/qpkg_cli ]] && /sbin/qpkg_cli --clean "$QPKG_NAME" > /dev/null 2>&1

    [[ ! -e $REAL_LOG_PATHFILE ]] && touch "$REAL_LOG_PATHFILE"
    [[ -e $TEMP_LOG_PATHFILE ]] && rm -f "$TEMP_LOG_PATHFILE"
    [[ ! -L $GUI_LOG_PATHFILE ]] && ln -s "$REAL_LOG_PATHFILE" "$GUI_LOG_PATHFILE"
    [[ ! -L $LINK_LOG_PATHFILE ]] && ln -s "$REAL_LOG_PATHFILE" "$LINK_LOG_PATHFILE"
    [[ ! -d $SYSV_STORE_PATH ]] && mkdir -p "$SYSV_STORE_PATH"
    [[ ! -d $SCRIPT_STORE_PATH ]] && mkdir -p "$SCRIPT_STORE_PATH"

    }

StartQPKG()
	{

	if [[ ${package_status:=none} = INSTALLING ]]; then
		operation='installation'
		RecordStart "$operation"
		RecordEnd "$operation"
	else
        if IsNotQPKGEnabled; then
            echo -e "This QPKG is disabled. Please enable it first with:\n\tqpkg_service enable $QPKG_NAME"
            return 1
        else
            operation='"start" scripts'
            RecordStart "$operation"
            ProcessSysV start
            ProcessScripts
            RecordEnd "$operation"
        fi
	fi

	}

StopQPKG()
	{

	if [[ ${package_status:=none} != INSTALLING ]]; then
		operation='package reorder'
		RecordStart "$operation"

		if IsQPKGEnabled SortMyQPKGs; then
			testver=$(/sbin/getcfg SortMyQPKGs Version -d 0 -f /etc/config/qpkg.conf)

			if [[ ${testver:0:6} -ge 181217 ]]; then
				RecordInfo 'SortMyQPKGs will reorder this package'
			else
				RecordWarning 'your SortMyQPKGs version is incompatible with this package'
			fi
		else
			MoveConfigToBottom "$QPKG_NAME"
		fi

		RecordEnd "$operation"

		operation='"stop" scripts'
		RecordStart "$operation"
		ProcessSysV stop
		RecordEnd "$operation"
	fi

	}

StatusQPKG()
	{

    if IsQPKGEnabled; then
        echo active
        exit 0
    else
        echo inactive
        exit 1
    fi

	}

ProcessSysV()
    {

    # $1 = 'start' or 'stop'

    [[ -z $1 ]] && return

    local script_pathname=''

    case $1 in
        start)
            # Execute 'init.d' script names in-order.

            ls "$SYSV_STORE_PATH"/* 2>/dev/null | while read -r script_pathname; do
                [[ -x $script_pathname ]] && RunAndLog "'$script_pathname' start"
            done
            ;;
        stop)
            # Execute 'init.d' script names in reverse-order.

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

    # Read 'scripts' script names in order and execute.

    ls "$SCRIPT_STORE_PATH"/* 2>/dev/null | while read -r script_pathname; do
        [[ -x $script_pathname ]] && RunAndLog "'$script_pathname'"
    done

    }

ShowTitle()
    {

    echo "$(ShowAsTitleName) $(ShowAsVersion)"

    }

ShowAsTitleName()
	{

	TextBrightWhite $QPKG_NAME

	}

ShowAsVersion()
	{

	printf '%s' "v$QPKG_VERSION"

	}

ShowAsUsage()
    {

    echo -e "\nUsage: $0 {start|stop|restart|status}"
    echo -e "\nTo execute files in the $QPKG_NAME 'init.d' path, then the 'scripts' path:\n\t$0 start"
    echo -e "\nTo execute execute files in the $QPKG_NAME 'init.d' path in reverse order:\n\t$0 stop"
    echo -e "\nTo stop, then start this QPKG:\n\t$0 restart"

	}

RunAndLog()
    {

    # $1 = command to run

    if [[ -z $1 ]]; then
        echo 'command not specified'
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

MoveConfigToBottom()
    {

    # Move $1 to the bottom of /etc/config/qpkg.conf

    [[ -n ${1:-} ]] || return

    local a=''

    a=$(GetConfigBlock "$1")
    [[ -n $a ]] || return

    /sbin/rmcfg "$1" -f /etc/config/qpkg.conf
    echo -e "\n${a}" >> /etc/config/qpkg.conf

    }

GetConfigBlock()
    {

    # Return the config block for the QPKG name specified as $1

    [[ -n ${1:-} ]] || return

    local -i sl=0       # line number: start of specified config block
    local -i ll=0       # line number: last line in file
    local -i bl=0       # total lines in specified config block
    local -i el=0       # line number: end of specified config block

    sl=$(/bin/grep -n "^\[$1\]" /etc/config/qpkg.conf | /usr/bin/cut -f1 -d':')
    [[ -n $sl ]] || return

    ll=$(/usr/bin/wc -l < /etc/config/qpkg.conf | /bin/tr -d ' ')
    bl=$(/usr/bin/tail -n$((ll-sl)) < /etc/config/qpkg.conf | /bin/grep -n '^\[' | /usr/bin/head -n1 | /usr/bin/cut -f1 -d':')

    [[ $bl -ne 0 ]] && el=$((sl+bl-1)) || el=$ll
    [[ -n $el ]] || return

    echo -e "$(/bin/sed -n "$sl,${el}p" /etc/config/qpkg.conf)"     # Output this with 'echo' to strip trailing LFs from config block.

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

    echo -e "${temp// /─}\n$QPKG_NAME ($QPKG_VERSION)\n$buffer" > "$TEMP_LOG_PATHFILE"

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
    SetServiceResultAsOK

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

# RecordError()
#     {
#
#     # $1 = message
#
#     local buffer="[$(date)] $1"
#
#     echo -e "$buffer" >> "$TEMP_LOG_PATHFILE"
#
#     WriteQTSLog "$1" 2
#     echo "$buffer"
#
#     }

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
	#   $1 = (optional) package name to check. If unspecified, default is $QPKG_NAME

	# output:
	#   $? = 0 : true
	#   $? = 1 : false

	[[ $(Lowercase "$(/sbin/getcfg "${1:-$QPKG_NAME}" Enable -d false -f /etc/config/qpkg.conf)") = true ]]

	}

IsNotQPKGEnabled()
	{

	# input:
	#   $1 = (optional) package name to check. If unspecified, default is $QPKG_NAME

	# output:
	#   $? = 0 : true
	#   $? = 1 : false

	! IsQPKGEnabled "${1:-$QPKG_NAME}"

	}

SetServiceAction()
	{

	service_action=${1:-none}
	CommitServiceAction
	SetServiceResultAsInProgress

	}

SetServiceResultAsOK()
	{

	service_result=ok
	CommitServiceResult

	}

SetServiceResultAsFailed()
	{

	service_result=failed
	CommitServiceResult

	}

SetServiceResultAsInProgress()
	{

	# Selected action is in-progress and hasn't generated a result yet.

	service_result=in-progress
	CommitServiceResult

	}

CommitServiceAction()
	{

    echo "$service_action" > "$SERVICE_ACTION_PATHFILE"

	}

CommitServiceResult()
	{

    echo "$service_result" > "$SERVICE_RESULT_PATHFILE"

	}

TextBrightWhite()
	{

	[[ -n ${1:-} ]] || return

    printf '\033[1;97m%s\033[0m' "$1"

	}

Lowercase()
	{

	/bin/tr 'A-Z' 'a-z' <<< "$1"

	}

Init

user_arg=${USER_ARGS_RAW%% *}		# Only process first argument.

case $user_arg in
    ?(-)r|?(--)restart)
        SetServiceAction restart

        if StopQPKG && StartQPKG; then
            SetServiceResultAsOK
        else
            SetServiceResultAsFailed
        fi
        ;;
    ?(--)start)
        SetServiceAction start

        if StartQPKG; then
            SetServiceResultAsOK
        else
            SetServiceResultAsFailed
        fi
        ;;
    ?(-)s|?(--)status)
        StatusQPKG
        ;;
    ?(--)stop)
        SetServiceAction stop

        if StopQPKG; then
            SetServiceResultAsOK
        else
            SetServiceResultAsFailed
        fi
        ;;
    *)
        ShowTitle
        ShowAsUsage
esac

[[ -e $TEMP_LOG_PATHFILE ]] && rm -f "$TEMP_LOG_PATHFILE"

exit 0
