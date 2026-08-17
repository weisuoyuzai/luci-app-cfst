#!/bin/sh
# Shared paths, logging and small helpers used by cfst-run, download-cfst.sh
# and all backend-*.sh scripts. Meant to be sourced, not executed directly.

# The downloaded cfst binary lives under /usr/share (persistent across
# reboots, part of the overlay but just a single small file) so it doesn't
# need to be re-downloaded every boot. Everything else (log, pid, status,
# result csv) is short-lived run state and lives on tmpfs (/tmp) instead of
# /root -- /root sits on the same small r/w overlay as the rest of the
# firmware, and constantly rewriting logs/results there risks filling it up
# (which then causes writes to silently fail) and generally isn't the right
# place for a package to keep runtime state.
CFST_BIN_DIR="/usr/share/cfst/bin"
CFST_RUN_DIR="/tmp/cfst"
CFST_BIN="$CFST_BIN_DIR/cfst"
RESULT_CSV="$CFST_RUN_DIR/result.csv"
LOG_FILE="$CFST_RUN_DIR/cfst.log"
PID_FILE="$CFST_RUN_DIR/run.pid"
RUN_STATUS_FILE="$CFST_RUN_DIR/run_status.json"
DOWNLOAD_STATUS_FILE="$CFST_RUN_DIR/download.status"
DOWNLOAD_PID_FILE="$CFST_RUN_DIR/download.pid"

mkdir -p "$CFST_BIN_DIR" "$CFST_RUN_DIR"

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Escapes backslash and double-quote for safe embedding in a JSON string value.
json_escape() {
	echo "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Returns 0 (true) if the pid in $1's file is alive, 1 otherwise.
pid_file_alive() {
	local pid_file="$1" pid
	[ -f "$pid_file" ] || return 1
	pid=$(cat "$pid_file" 2>/dev/null)
	[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# Maps `uname -m` (cross-checked against /etc/openwrt_release) to the asset
# suffix used by XIU2/CloudflareSpeedTest release files: cfst_linux_<suffix>.tar.gz
detect_arch() {
	local m
	m=$(uname -m 2>/dev/null)
	case "$m" in
		x86_64) echo "amd64" ;;
		i386|i486|i586|i686) echo "386" ;;
		aarch64|aarch64_be) echo "arm64" ;;
		armv5*) echo "armv5" ;;
		armv6*) echo "armv6" ;;
		armv7*|armv7l) echo "armv7" ;;
		mips64) echo "mips64" ;;
		mips64el) echo "mips64le" ;;
		mipsel) echo "mipsle" ;;
		mips) echo "mips" ;;
		*) echo "" ;;
	esac
}

# Probes whether a given backend appears installed: config file + init script.
backend_available() {
	local name="$1"
	[ -f "/etc/config/$name" ] && [ -x "/etc/init.d/$name" ]
}

# Resolves the configured backend, applying "auto" detection across
# passwall2, passwall, openclash. Prints the resolved name on success.
# Returns 1 (nothing printed) with a log() message on failure/ambiguity.
resolve_backend() {
	local configured="$1" found="" count=0 b

	if [ -n "$configured" ] && [ "$configured" != "auto" ]; then
		case "$configured" in
			passwall2|passwall|openclash) ;;
			*)
				log "错误: 配置的后端类型 '$configured' 无效，请在基础设置中重新选择后端"
				return 1
				;;
		esac
		if backend_available "$configured"; then
			echo "$configured"
			return 0
		fi
		log "错误: 配置的后端 '$configured' 未安装（缺少 /etc/config/$configured 或 /etc/init.d/$configured）"
		return 1
	fi

	for b in passwall2 passwall openclash; do
		if backend_available "$b"; then
			found="$b"
			count=$((count + 1))
		fi
	done

	if [ "$count" -eq 1 ]; then
		echo "$found"
		return 0
	elif [ "$count" -eq 0 ]; then
		log "错误: 未检测到 PassWall / PassWall2 / OpenClash 中的任何一个，请先安装代理插件"
		return 1
	else
		log "错误: 检测到多个后端同时安装，无法自动判断，请在基础设置中手动选择后端类型"
		return 1
	fi
}

# Sources the backend-<name>.sh implementation for a resolved backend name.
source_backend() {
	case "$1" in
		passwall2) . /usr/share/cfst/backend-passwall2.sh ;;
		passwall)  . /usr/share/cfst/backend-passwall.sh ;;
		openclash) . /usr/share/cfst/backend-openclash.sh ;;
		*) return 1 ;;
	esac
}
