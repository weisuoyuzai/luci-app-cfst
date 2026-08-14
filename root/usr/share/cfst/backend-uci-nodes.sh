#!/bin/sh
# Generic UCI "nodes" style backend implementation shared by
# backend-passwall.sh and backend-passwall2.sh (both PassWall generations
# use the same section layout: anonymous sections with .remarks/.address
# fields, and a @global[0].localhost_proxy toggle).
#
# All functions take the uci config name (e.g. "passwall2") as their first
# argument. Meant to be sourced, not executed directly.

uci_nodes_list_nodes() {
	local conf="$1" sid remark address type
	uci show "$conf" 2>/dev/null | grep "\.remarks=" | cut -d'.' -f2 | sort -u | \
	while read -r sid; do
		[ -n "$sid" ] || continue
		remark=$(uci get "$conf.$sid.remarks" 2>/dev/null)
		address=$(uci get "$conf.$sid.address" 2>/dev/null)
		type=$(uci get "$conf.$sid.type" 2>/dev/null)
		printf '%s\t%s\t%s\t%s\n' "$sid" "$remark" "$address" "$type"
	done
}

uci_nodes_match_keyword() {
	local conf="$1" kw="$2"
	[ -n "$kw" ] || return 0
	uci show "$conf" 2>/dev/null | grep "remarks='.*${kw}.*'" | cut -d'.' -f2 | sort -u
}

uci_nodes_update_node() {
	local conf="$1" sid="$2" new_addr="$3" old_addr
	if uci get "$conf.$sid" >/dev/null 2>&1; then
		old_addr=$(uci get "$conf.$sid.address" 2>/dev/null)
		uci set "$conf.$sid.address=$new_addr"
		log "节点 $sid: $old_addr -> $new_addr"
		return 0
	fi
	log "警告: 节点 sid $sid 不存在，跳过"
	return 1
}

uci_nodes_commit_restart() {
	local conf="$1"
	uci commit "$conf"
	log "配置已提交，重启 $conf 服务..."
	/etc/init.d/"$conf" restart >> "$LOG_FILE" 2>&1
	log "$conf 已重启"
}

# Sets globals PROXY_DISABLED / PROXY_WAS_TOGGLED / ORIG_LOCALHOST_PROXY,
# consumed later by uci_nodes_restore_local_proxy_config and cfst-run's
# exit trap. Mirrors the original cfst.sh disable_local_proxy() verbatim.
uci_nodes_disable_local_proxy() {
	local conf="$1"
	ORIG_LOCALHOST_PROXY=$(uci get "$conf".@global[0].localhost_proxy 2>/dev/null)
	if [ -z "$ORIG_LOCALHOST_PROXY" ]; then
		log "提示: 未找到 localhost_proxy 配置项，可能本机流量本来就没走代理，跳过关闭步骤"
		return
	fi
	if [ "$ORIG_LOCALHOST_PROXY" = "0" ]; then
		log "本机代理当前已是关闭状态，无需处理"
		return
	fi
	uci set "$conf".@global[0].localhost_proxy='0'
	uci commit "$conf"
	/etc/init.d/"$conf" restart >> "$LOG_FILE" 2>&1
	sleep 3
	PROXY_DISABLED=1
	PROXY_WAS_TOGGLED=1
	log "已临时关闭本机代理，用于直连测速"
}

uci_nodes_restore_local_proxy_config() {
	local conf="$1"
	if [ "$PROXY_DISABLED" = "1" ]; then
		uci set "$conf".@global[0].localhost_proxy="$ORIG_LOCALHOST_PROXY"
		uci commit "$conf"
		log "已恢复本机代理配置（等待统一重启生效）"
		PROXY_DISABLED=0
	fi
}
