#!/bin/sh
# Downloads/updates the CloudflareST (cfst) binary matching this router's
# CPU architecture, via an optional GitHub-mirror prefix.
#
# Usage: download-cfst.sh [mirror_prefix_override]
# When called with no argument, reads mirror_prefix/cfst_bin_url from uci.
# Writes $DOWNLOAD_STATUS_FILE (JSON) so the LuCI UI can poll progress.

. /usr/share/cfst/backend-common.sh

GITHUB_RELEASE_URL="https://github.com/XIU2/CloudflareSpeedTest/releases/latest/download"

write_status() {
	# $1=state(running|success|failed) $2=message
	local state="$1" message="$2" arch="$3"
	cat > "$DOWNLOAD_STATUS_FILE" <<-EOF
	{"state":"$state","time":$(date +%s),"arch":"$(json_escape "$arch")","message":"$(json_escape "$message")"}
	EOF
}

echo $$ > "$DOWNLOAD_PID_FILE"
trap 'rm -f "$DOWNLOAD_PID_FILE"' EXIT

MIRROR_ARG="$1"
. /lib/functions.sh
config_load cfst
config_get MIRROR_UCI global mirror_prefix 'https://ghproxy.com/'
config_get BIN_URL_OVERRIDE global cfst_bin_url ''

MIRROR_PREFIX="${MIRROR_ARG:-$MIRROR_UCI}"

ARCH=$(detect_arch)

if [ -z "$BIN_URL_OVERRIDE" ] && [ -z "$ARCH" ]; then
	log "错误: 无法识别当前设备架构，无法自动下载 cfst，请使用高级设置中的自定义下载地址"
	write_status "failed" "unsupported architecture ($(uname -m 2>/dev/null))" ""
	exit 1
fi

if [ -n "$BIN_URL_OVERRIDE" ]; then
	URL="$BIN_URL_OVERRIDE"
else
	URL="${MIRROR_PREFIX}${GITHUB_RELEASE_URL}/cfst_linux_${ARCH}.tar.gz"
fi

log "开始下载 cfst: $URL"
write_status "running" "downloading" "$ARCH"

TAR_FILE="$CFST_RUN_DIR/cfst_download.tar.gz"
EXTRACT_DIR="$CFST_RUN_DIR/cfst_extract"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

DL_OK=0
if command -v curl >/dev/null 2>&1; then
	curl -fL -sS --connect-timeout 15 -o "$TAR_FILE" "$URL" >> "$LOG_FILE" 2>&1 && DL_OK=1
else
	uclient-fetch -O "$TAR_FILE" "$URL" >> "$LOG_FILE" 2>&1 && DL_OK=1
fi

if [ "$DL_OK" != "1" ] || [ ! -s "$TAR_FILE" ]; then
	log "错误: cfst 下载失败: $URL"
	write_status "failed" "download failed" "$ARCH"
	rm -f "$TAR_FILE"
	exit 1
fi

if ! tar -xzf "$TAR_FILE" -C "$EXTRACT_DIR" >> "$LOG_FILE" 2>&1; then
	log "错误: cfst 压缩包解压失败"
	write_status "failed" "extract failed" "$ARCH"
	rm -f "$TAR_FILE"
	rm -rf "$EXTRACT_DIR"
	exit 1
fi

# Locate the extracted binary: prefer a file literally named "cfst" or
# "CloudflareST", else fall back to the first executable regular file found.
BIN_PATH=$(find "$EXTRACT_DIR" -maxdepth 2 -type f \( -iname "cfst" -o -iname "cloudflarest" \) 2>/dev/null | head -n1)
if [ -z "$BIN_PATH" ]; then
	BIN_PATH=$(find "$EXTRACT_DIR" -maxdepth 2 -type f -perm -100 2>/dev/null | head -n1)
fi

if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH" ]; then
	log "错误: 解压后未找到 cfst 可执行文件"
	write_status "failed" "binary not found in archive" "$ARCH"
	rm -f "$TAR_FILE"
	rm -rf "$EXTRACT_DIR"
	exit 1
fi

[ -f "$CFST_BIN" ] && cp "$CFST_BIN" "$CFST_BIN.bak" 2>/dev/null

cp "$BIN_PATH" "$CFST_BIN"
chmod +x "$CFST_BIN"

rm -f "$TAR_FILE"
rm -rf "$EXTRACT_DIR"

log "cfst 下载/更新完成 (架构: $ARCH)"
write_status "success" "" "$ARCH"

exit 0
