#!/bin/sh
# PassWall (legacy v4) backend. Meant to be sourced by cfst-run after
# backend-common.sh.
#
# PassWall and PassWall2 are from the same author and share the same node
# section layout (anonymous sections with .remarks/.address fields), but
# this is not guaranteed across all versions -- list_nodes defensively
# warns if the schema doesn't look as expected instead of assuming.

. /usr/share/cfst/backend-uci-nodes.sh

CFST_BACKEND_CONF="passwall"

list_nodes() {
	local section_count remark_count out
	out=$(uci_nodes_list_nodes "$CFST_BACKEND_CONF")
	if [ -z "$out" ]; then
		section_count=$(uci show "$CFST_BACKEND_CONF" 2>/dev/null | grep -c "=")
		if [ "$section_count" -gt 0 ]; then
			log "警告: passwall 存在配置项，但未找到任何 remarks 字段，节点数据结构可能与预期不符（请检查 passwall 版本）"
		fi
		return 0
	fi
	echo "$out"
}

match_keyword() {
	uci_nodes_match_keyword "$CFST_BACKEND_CONF" "$1"
}

update_node() {
	uci_nodes_update_node "$CFST_BACKEND_CONF" "$1" "$2"
}

disable_local_proxy() {
	uci_nodes_disable_local_proxy "$CFST_BACKEND_CONF"
}

restore_local_proxy_config() {
	uci_nodes_restore_local_proxy_config "$CFST_BACKEND_CONF"
}

commit_restart() {
	uci_nodes_commit_restart "$CFST_BACKEND_CONF"
}
