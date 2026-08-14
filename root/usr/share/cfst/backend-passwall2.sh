#!/bin/sh
# PassWall2 backend. Meant to be sourced by cfst-run after backend-common.sh.

. /usr/share/cfst/backend-uci-nodes.sh

CFST_BACKEND_CONF="passwall2"

list_nodes() {
	uci_nodes_list_nodes "$CFST_BACKEND_CONF"
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
