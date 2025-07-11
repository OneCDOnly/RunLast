#!/usr/bin/env bash
###############################################################################
# runlast.sh
#	Copyright 2019-2025 OneCD
#
# Contact:
#	one.cd.only@gmail.com
#
# Description:
#	This script is part of the 'RunLast' package
#
# Available in the MyQNAP store:
#	https://www.myqnap.org/product/runlast
#
# And via the sherpa package manager:
#	https://git.io/sherpa
#
# Project source:
#	https://github.com/OneCDOnly/RunLast
#
# Community forum:
#	https://community.qnap.com/t/qpkg-runlast/1102
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
readonly r_user_args_raw=$*

Init()
	{

	readonly r_qpkg_name=RunLast

	# KLUDGE: mark QPKG installation as complete.

	/sbin/setcfg $r_qpkg_name Status complete -f /etc/config/qpkg.conf

	# KLUDGE: 'clean' the QTS 4.5.1+ App Center notifier status.

	[[ -e /sbin/qpkg_cli ]] && /sbin/qpkg_cli --clean $r_qpkg_name &> /dev/null

	local -r r_qpkg_path=$(/sbin/getcfg $r_qpkg_name Install_Path -f /etc/config/qpkg.conf)
		readonly r_script_store_path=$r_qpkg_path/scripts
		readonly r_sysv_store_path=$r_qpkg_path/init.d

	local -r r_gui_log_pathfile=/home/httpd/$r_qpkg_name.log
	readonly r_log_pathfile=/var/log/$r_qpkg_name.log
	readonly r_qpkg_version=$(/sbin/getcfg $r_qpkg_name Version -f /etc/config/qpkg.conf)
	readonly r_service_action_pathfile=/var/log/$r_qpkg_name.action
	readonly r_service_result_pathfile=/var/log/$r_qpkg_name.result
	readonly r_sleeper_log_pathfile=/var/log/$r_qpkg_name-sleeper.log

	[[ ! -e $r_log_pathfile ]] && touch "$r_log_pathfile"
	[[ ! -L $r_gui_log_pathfile ]] && ln -s "$r_log_pathfile" "$r_gui_log_pathfile"
	[[ ! -d $r_sysv_store_path ]] && mkdir -p "$r_sysv_store_path"
	[[ ! -d $r_script_store_path ]] && mkdir -p "$r_script_store_path"

	SetOsFirmwareVer

	}

StartQPKG()
	{

	if [[ ${package_status:=none} = INSTALLING ]]; then
		operation=installation
		RecordStart "$operation"
		RecordEnd "$operation"
		return
	fi

	if IsNotQPKGEnabled; then
		echo -e "This QPKG is disabled. Please enable it first with:\n\tqpkg_service enable $r_qpkg_name"
		return 1
	fi

	local -i start_seconds=$(/bin/date +%s)
	local -i timeout_seconds=1800
	local -i timeout_limit_seconds=$((start_seconds+timeout_seconds))
	local -i recheck_seconds=10
	local -i now_seconds=0

	WriteToSleeperLog 'initial QPKG startup check ...'

	while true; do
		now_seconds=$(/bin/date +%s)

		if IsOsStartingPackages; then
			if [[ $now_seconds -ge $timeout_limit_seconds ]]; then
				AppendToSleeperLog "$(GetOsName) startup timeout reached ($timeout_seconds seconds). Unable to execute userscripts."
				return 1
			fi

			AppendToSleeperLog "$(GetOsName) is starting packages (recheck in $recheck_seconds seconds)."
			/bin/sleep $recheck_seconds
		else
			AppendToSleeperLog "$(GetOsName) is NOT starting packages (after $((now_seconds-start_seconds)) seconds)."

			operation="'start' scripts"
			RecordStart "$operation"
			ProcessSysV start
			ProcessScripts
			RecordEnd "$operation"
			break
		fi
	done

	}

StopQPKG()
	{

	if [[ ${package_status:=none} != INSTALLING ]]; then
		if IsQPKGEnabled SortMyQPKGs; then
			testver=$(/sbin/getcfg SortMyQPKGs Version -d 0 -f /etc/config/qpkg.conf)

			if [[ ${testver:0:6} -ge 181217 ]]; then
				RecordInfo 'SortMyQPKGs will reorder this package'
			else
				RecordWarning 'your SortMyQPKGs version is incompatible with this package'
			fi
		elif ! IsOsCanAsyncQpkgActions; then
			operation='package reorder'
			RecordStart "$operation"
			MoveConfigToBottom $r_qpkg_name
			RecordEnd "$operation"
		fi

		operation="'stop' scripts"
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

	# Inputs: (local)
	#	$1 = 'start' or 'stop'

	[[ -z ${1:-} ]] && return

	local script_pathname=''

	case ${1:-} in
		start)
			# Execute 'init.d' script names in-order.

			ls "$r_sysv_store_path"/* 2>/dev/null | while read -r script_pathname; do
				[[ -x $script_pathname ]] && RunAndLog "$script_pathname start"
			done
			;;
		stop)
			# Execute 'init.d' script names in reverse-order.

			ls -r "$r_sysv_store_path"/* 2>/dev/null | while read -r script_pathname; do
				[[ -x $script_pathname ]] && RunAndLog "$script_pathname stop"
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

	ls "$r_script_store_path"/* 2>/dev/null | while read -r script_pathname; do
		[[ -x $script_pathname ]] && RunAndLog "$script_pathname"
	done

	}

ShowTitle()
	{

	echo "$(ShowAsTitleName) $(ShowAsVersion)"

	}

ShowAsTitleName()
	{

	TextBrightWhite $r_qpkg_name

	}

ShowAsVersion()
	{

	printf '%s' "v$r_qpkg_version"

	}

ShowAsUsage()
	{

	echo -e "\nUsage: $0 {start|stop|restart|status}"
	echo -e "\nTo execute files in the $r_qpkg_name 'init.d' path, then files in the 'scripts' path:\n\t$0 start"
	echo -e "\nTo execute files in the $r_qpkg_name 'init.d' path in reverse order:\n\t$0 stop"
	echo -e "\nTo stop, then start this QPKG:\n\t$0 restart"

	}

RunAndLog()
	{

	# Inputs: (local)
	#	$1 = command to run

	# Inputs: (global)
	#	$r_log_pathfile

	if [[ -z ${1:-} ]]; then
		echo 'command not specified'
		return 1
	fi

	local stdout=''
	local stderr=''

	FormatAsLog "-> execute: '$1' ..." | /usr/bin/tee -a "$r_log_pathfile"

		{	# https://unix.stackexchange.com/a/430182/110015

		stdout=$(eval "$1" 2> /dev/fd/3)
		exitcode=$?
		stderr=$(/bin/cat<&3)

		} 3<<EOF
EOF

		{

		FormatAsLog "==> exitcode: '$exitcode'"
		FormatAsLog "==> stdout: \"$stdout\""
		FormatAsLog "==> stderr: \"$stderr\""

		} | /usr/bin/tee -a "$r_log_pathfile"

	return 0

	}

MoveConfigToBottom()
	{

	# Move $1 (QPKG name) to the bottom of /etc/config/qpkg.conf

	[[ -n ${1:-} ]] || return

	local a=''

	a=$(GetConfigBlock ${1:-})
	[[ -n $a ]] || return

	/sbin/rmcfg ${1:-} -f /etc/config/qpkg.conf
	echo -e "\n${a}" >> /etc/config/qpkg.conf

	}

GetConfigBlock()
	{

	# Output the config block for $1 (QPKG name).

	[[ -n ${1:-} ]] || return

	local -i sl=0		# start line number of config block.
	local -i ll=0		# last line number in file.
	local -i tl=0		# total lines in config block.
	local -i el=0		# end line number of config block.

	sl=$(/bin/grep -n "^\[${1:-}\]" /etc/config/qpkg.conf | /usr/bin/cut -f1 -d':')
	[[ -n $sl ]] || return

	ll=$(/usr/bin/wc -l < /etc/config/qpkg.conf | /bin/tr -d ' ')
	tl=$(/usr/bin/tail -n$((ll-sl)) < /etc/config/qpkg.conf | /bin/grep -n '^\[' | /usr/bin/head -n1 | /usr/bin/cut -f1 -d':')

	[[ $tl -ne 0 ]] && el=$((sl+tl-1)) || el=$ll
	[[ -n $el ]] || return

	echo -e "$(/bin/sed -n "$sl,${el}p" /etc/config/qpkg.conf)"		# Output this with 'echo' to strip trailing LFs from config block.

	}

RecordStart()
	{

	# Inputs: (local)
	#	$1 = operation

	# Inputs: (global)
	#	$r_qpkg_name
	#	$r_qpkg_version

	[[ -n ${1:-} ]] || return

	local a="begin processing $1 ..."

	if [[ -s $r_log_pathfile ]]; then
		local -i spacer_width=80
		local b=''
		printf -v b "%${spacer_width}s"
		AppendToLog "${b// /─}"
	fi

	FormatAsLog "$a"
	AppendToLog "$r_qpkg_name ($r_qpkg_version)"
	AppendToLog "$a"
	AppendToQTSLog "$a" 0

	}

RecordEnd()
	{

	# Inputs: (local)
	#	$1 = operation

	[[ -n ${1:-} ]] || return

	local a="end of processing $1"

	FormatAsLog "$a"
	AppendToLog "$a"
	AppendToQTSLog "$a" 0

	SetServiceResultAsOK

	}

RecordInfo()
	{

	# Inputs: (local)
	#	$1 = message

	[[ -n ${1:-} ]] || return

	AppendToLog "$1"
	AppendToQTSLog "$1" 0

	}

RecordWarning()
	{

	# Inputs: (local)
	#	$1 = message

	[[ -n ${1:-} ]] || return

	AppendToLog "$1"
	AppendToQTSLog "$1" 1

	}

FormatAsLog()
	{

	[[ -n ${1:-} ]] || return

	printf '%s - %s\n' "$(/bin/date)" "$1"

	}

FormatAsQTSLog()
	{

	[[ -n ${1:-} ]] || return

	printf '[%s] %s\n' "$r_qpkg_name" "$1"

	}

AppendToLog()
	{

	# Inputs: (local)
	#	$1 = message to add to temporary log

	[[ -n ${1:-} ]] || return

	FormatAsLog "$1" >> "$r_log_pathfile"

	}

AppendToSleeperLog()
	{

	# Inputs: (local)
	#	$1 = message to add to sleeper log

	[[ -n ${1:-} ]] || return

	FormatAsLog "$1" >> "$r_sleeper_log_pathfile"

	}

AppendToQTSLog()
	{

	# Inputs: (local)
	#	$1 = message to add to NAS system log
	#	$2 = event type:
	#		0 : Information
	#		1 : Warning
	#		2 : Error

	[[ -n ${1:-} && -n ${2:-} ]] || return

	/sbin/log_tool --append "$(FormatAsQTSLog "$1")" --type "$2"

	}

WriteToSleeperLog()
	{

	# Inputs: (local)
	#	$1 = message to write into sleeper log

	[[ -n ${1:-} ]] || return

	[[ -e $r_sleeper_log_pathfile ]] && rm "$r_sleeper_log_pathfile"

	AppendToSleeperLog "$1"

	}

IsQuTS()
	{

	/bin/grep zfs /proc/filesystems

	} &> /dev/null

IsQPKGEnabled()
	{

	# Inputs: (local)
	#	$1 = (optional) package name to check. If unspecified, default is $r_qpkg_name

	# Outputs: (local)
	#	$? = 0 : true
	#	$? = 1 : false

	[[ $(Lowercase "$(/sbin/getcfg ${1:-$r_qpkg_name} Enable -d false -f /etc/config/qpkg.conf)") = true ]]

	}

IsNotQPKGEnabled()
	{

	# Inputs: (local)
	#	$1 = (optional) package name to check. If unspecified, default is $r_qpkg_name

	# Outputs: (local)
	#	$? = 0 : true
	#	$? = 1 : false

	! IsQPKGEnabled "${1:-$r_qpkg_name}"

	}

IsOsCanAsyncQpkgActions()
	{

	# Inputs: (global)
	#	$r_nas_firmware_ver

	SetOsFirmwareVer

	[[ $r_nas_firmware_ver -ge 520 ]]

	}

IsOsStarting()
	{

	/bin/ps | /bin/grep '/bin/sh /etc/init.d/rcS' | /bin/grep -v grep

	} &> /dev/null

IsOsStartingPackages()
	{

	if IsOsCanAsyncQpkgActions; then
		/bin/ps | /bin/grep '/usr/local/sbin/qpkg_service start' | /bin/grep -v grep | /bin/grep -v $r_qpkg_name
	else
		IsOsStarting
	fi

	} &> /dev/null

GetOsName()
	{

	# Outputs: (local)
	#	stdout = text string.

	if IsQuTS; then
		printf 'QuTS hero'
	else
		printf QTS
	fi

	}

GetOsFirmwareVer()
	{

	# Same as firmware version, but an integer-only (no periods).

	# Outputs: (local)
	#	stdout = integer.
	#	$? = 0 if found, 250 if not.

	/sbin/getcfg System Version -d undefined -f /etc/config/uLinux.conf | /bin/tr -d '.'

	}

SetOsFirmwareVer()
	{

	# Same as firmware version, but as an integer-only (no periods).

	# Outputs: (global)
	#	$r_nas_firmware_ver

	[[ ${r_nas_firmware_ver:-unset} = unset ]] && readonly r_nas_firmware_ver=$(GetOsFirmwareVer)

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

	echo "$service_action" > "$r_service_action_pathfile"

	}

CommitServiceResult()
	{

	echo "$service_result" > "$r_service_result_pathfile"

	}

TextBrightWhite()
	{

	[[ -n ${1:-} ]] || return

	printf '\033[1;97m%s\033[0m' "${1:-}"

	}

Lowercase()
	{

	/bin/tr 'A-Z' 'a-z' <<< "${1:-}"

	}

Init

user_arg=${r_user_args_raw%% *}		# Only process first argument.

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

exit 0
