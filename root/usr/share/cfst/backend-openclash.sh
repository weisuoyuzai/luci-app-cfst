#!/bin/sh
# OpenClash backend -- BEST EFFORT.
#
# OpenClash nodes are not UCI sections; they live in a YAML profile under a
# top-level "proxies:" list. This script edits that YAML directly (via `yq`
# if present, otherwise a conservative awk state-machine) and is inherently
# best-effort: profile formatting varies across OpenClash versions and
# subscriptions. On any doubt it logs and skips rather than risking a
# corrupted config. See plan caveats for details.
#
# Meant to be sourced by cfst-run after backend-common.sh.

CFST_BACKEND_CONF="openclash"

# Resolves the *source* profile YAML (never the merged runtime file under
# /tmp/etc/openclash/clash_run/, which is regenerated on every restart).
_openclash_yaml_path() {
	local raw candidate

	raw=$(uci -q get openclash.config.config_path)
	case "$raw" in
		/*) candidate="$raw" ;;
		"") candidate="" ;;
		*) candidate="/etc/openclash/config/$raw" ;;
	esac
	if [ -n "$candidate" ] && [ -f "$candidate" ]; then
		echo "$candidate"
		return 0
	fi

	candidate=$(ls -t /etc/openclash/config/*.yaml 2>/dev/null | head -n1)
	if [ -n "$candidate" ] && [ -f "$candidate" ]; then
		echo "$candidate"
		return 0
	fi

	return 1
}

# Parses "proxies:" list entries from stdin, printing name\tserver\tport\ttype.
# Assumes the common OpenClash/Clash YAML block-list convention:
#   proxies:
#     - name: "xxx"
#       server: 1.2.3.4
#       port: 443
#       type: vmess
_openclash_parse_awk() {
	awk '
		BEGIN { in_proxies=0; have=0; name=""; server=""; port=""; type="" }
		{
			line = $0
			if (line ~ /^proxies:/) { in_proxies=1; next }
			if (in_proxies && line ~ /^[A-Za-z0-9_-]+:/ && line !~ /^proxies:/) {
				if (have) { print name "\t" server "\t" port "\t" type; have=0 }
				in_proxies=0
				next
			}
			if (in_proxies && line ~ /^[ \t]*-[ \t]*name:/) {
				if (have) { print name "\t" server "\t" port "\t" type }
				v = line
				sub(/^[ \t]*-[ \t]*name:[ \t]*/, "", v)
				if (substr(v,1,1) == "\"" || substr(v,1,1) == "'"'"'") { v = substr(v, 2) }
				sub(/["'"'"'][ \t]*$/, "", v)
				sub(/[ \t]*#.*/, "", v)
				name = v; server=""; port=""; type=""; have=1
				next
			}
			if (in_proxies && have) {
				if (line ~ /^[ \t]+server:/) {
					v = line; sub(/^[ \t]+server:[ \t]*/, "", v)
					if (substr(v,1,1) == "\"" || substr(v,1,1) == "'"'"'") { v = substr(v, 2) }
					sub(/["'"'"'][ \t]*$/, "", v); sub(/[ \t]*#.*/, "", v)
					server = v
				} else if (line ~ /^[ \t]+port:/) {
					v = line; sub(/^[ \t]+port:[ \t]*/, "", v); sub(/[ \t]*#.*/, "", v)
					port = v
				} else if (line ~ /^[ \t]+type:/) {
					v = line; sub(/^[ \t]+type:[ \t]*/, "", v); sub(/[ \t]*#.*/, "", v)
					type = v
				}
			}
		}
		END { if (have) print name "\t" server "\t" port "\t" type }
	'
}

list_nodes() {
	local yaml
	yaml=$(_openclash_yaml_path) || { log "错误: 未找到 OpenClash 配置文件"; return 1; }
	if command -v yq >/dev/null 2>&1; then
		local yq_out
		yq_out=$(yq e '.proxies[] | (.name // "") + "\t" + (.server // "") + "\t" + ((.port // "") | tostring) + "\t" + (.type // "")' "$yaml" 2>/dev/null)
		if [ -n "$yq_out" ]; then
			echo "$yq_out"
			return 0
		fi
	fi
	_openclash_parse_awk < "$yaml"
}

match_keyword() {
	local kw="$1" name
	[ -n "$kw" ] || return 0
	list_nodes | while IFS="$(printf '\t')" read -r name _rest; do
		case "$name" in
			*"$kw"*) echo "$name" ;;
		esac
	done
}

update_node() {
	local target="$1" new_addr="$2" yaml tmp status_file applied
	yaml=$(_openclash_yaml_path) || { log "错误: 未找到 OpenClash 配置文件，跳过节点 '$target'"; return 1; }

	local orig_lines orig_names
	orig_lines=$(wc -l < "$yaml")
	orig_names=$(grep -c "^[ \t]*- name:" "$yaml")

	cp "$yaml" "$yaml.cfst.bak" 2>/dev/null

	tmp="${yaml}.cfst.tmp"
	status_file="${yaml}.cfst.status"

	awk -v target="$target" -v newaddr="$new_addr" '
		BEGIN { in_proxies=0; block_is_target=0; applied=0 }
		{
			line = $0
			if (line ~ /^proxies:/) { in_proxies=1; print line; next }
			if (in_proxies && line ~ /^[A-Za-z0-9_-]+:/ && line !~ /^proxies:/) { in_proxies=0 }
			if (in_proxies && line ~ /^[ \t]*-[ \t]*name:/) {
				nm = line
				sub(/^[ \t]*-[ \t]*name:[ \t]*/, "", nm)
				if (substr(nm,1,1) == "\"" || substr(nm,1,1) == "'"'"'") { nm = substr(nm, 2) }
				sub(/["'"'"'][ \t]*$/, "", nm)
				sub(/[ \t]*#.*/, "", nm)
				block_is_target = (nm == target) ? 1 : 0
				print line
				next
			}
			if (in_proxies && block_is_target && line ~ /^[ \t]+server:/) {
				match(line, /^[ \t]+server:[ \t]*/)
				prefix = substr(line, 1, RLENGTH)
				rest = substr(line, RLENGTH + 1)
				quote = ""
				if (substr(rest,1,1) == "\"") quote = "\""
				else if (substr(rest,1,1) == "'"'"'") quote = "'"'"'"
				print prefix quote newaddr quote
				applied = 1
				next
			}
			print line
		}
		END { print applied > "'"$status_file"'" }
	' "$yaml" > "$tmp"

	applied=$(cat "$status_file" 2>/dev/null)
	rm -f "$status_file"

	if [ "$applied" != "1" ]; then
		log "警告: 未能在 OpenClash 配置中定位到节点 '$target' 的 server 字段，跳过（配置文件未修改）"
		rm -f "$tmp"
		return 1
	fi

	local new_lines new_names
	new_lines=$(wc -l < "$tmp")
	new_names=$(grep -c "^[ \t]*- name:" "$tmp")

	if [ "$new_lines" != "$orig_lines" ] || [ "$new_names" != "$orig_names" ]; then
		log "错误: 修改 OpenClash 配置后行数/节点数发生异常变化，已放弃本次修改以避免损坏配置（节点 '$target'）"
		rm -f "$tmp"
		return 1
	fi

	mv -f "$tmp" "$yaml"
	log "OpenClash 节点 $target: -> $new_addr"
	return 0
}

# OpenClash has no single "localhost proxy" toggle comparable to
# PassWall/PassWall2's localhost_proxy -- stopping OpenClash entirely to
# force a direct-connect test would be too disruptive to do automatically.
# This is a documented limitation, not a silent no-op.
disable_local_proxy() {
	log "提示: OpenClash 无对应的本机直连测速开关，跳过该步骤（测速流量可能仍经过 OpenClash 代理）"
}

restore_local_proxy_config() {
	:
}

commit_restart() {
	log "正在重启 OpenClash 使配置生效（这可能需要较长时间）..."
	/etc/init.d/openclash restart >> "$LOG_FILE" 2>&1
	log "OpenClash 已重启"
}
