#!/bin/sh
# ===========================================================================
# cfst_passwall2.sh —— OpenWrt + PassWall2 定时优选 Cloudflare IP 脚本
#
# 功能：
#   1. 调用 CloudflareSpeedTest (CloudflareST) 测速优选延迟低、速度快的 CF IP
#   2. 取出最优 IP，自动写入 PassWall2 指定节点的 address 字段
#   3. uci commit 并重启 PassWall2 生效
#
# 使用前必读：
#   1. 需要先在路由器上放好 CloudflareST 可执行文件（见下方"安装步骤"）
#   2. 需要知道要更新的 PassWall2 节点 UCI sid（见下方"查找节点 sid"）
#   3. 首次务必手动执行一次，确认无误后再加入 crontab 定时任务
# ===========================================================================

# ------------------------- 1. 基本配置（必改） -------------------------

# CloudflareST 所在目录（自己创建，比如 /root/cfst）
CFST_DIR="/root/cfst"

# CloudflareST 可执行文件名（从 github release 下载后放到 CFST_DIR 并 chmod +x）
CFST_BIN="$CFST_DIR/cfst"

# 自定义 IP 段文件，可选。留空则使用 CloudflareST 内置的官方 IP 段
IP_TXT=""

# 测速结果输出文件
RESULT_CSV="$CFST_DIR/result.csv"

# 日志文件
LOG_FILE="$CFST_DIR/cfst.log"

# 要更新的 PassWall2 节点 sid，可以填一个或多个（空格分隔）
# 查找方法见下方说明，例如：PW2_NODE_SIDS="cfg0a1b2c cfg0d3e4f"
PW2_NODE_SIDS=""

# 如果不想手动填 sid，可以改用"备注关键字"自动匹配（二选一，优先用 PW2_NODE_SIDS）
# 例如你的节点备注里包含 "CF优选"，这里填 "CF优选" 即可自动查找
NODE_REMARK_KEYWORD="cf优选"

# 测速时是否临时关闭 PassWall2 的"本机代理"，让测速流量直连出去，测完再恢复
# 因为如果路由器本机流量也被代理转发，测速测的其实是"经过代理的速度"，不准确
# 1=开启（推荐） 0=关闭（如果你确定本机流量本来就没走代理，可以设为0）
BYPASS_PROXY_FOR_TEST=1

# ------------------------- 2. 测速参数（可按需调整） -------------------------

# -n   延迟测速并发数        -t   延迟测速次数
# -dn  下载测速数量           -dt  下载测速时间(秒)
# -tl  平均延迟上限(ms)       -tlr 丢包率上限(0~1)
# -sl  下载速度下限(MB/s)     -p   显示结果条数
CFST_ARGS="-n 200 -t 4 -dn 10 -dt 10 -tl 200 -tlr 0.2 -sl 5 -p 5"

# ===========================================================================
# 以下为脚本主体，一般不需要修改
# ===========================================================================

log() {
    # 只写入日志文件，不打印到终端，避免大量输出导致低配设备卡死
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

mkdir -p "$CFST_DIR"

PROXY_DISABLED=0
ORIG_LOCALHOST_PROXY=""
PROXY_WAS_TOGGLED=0

# 临时关闭 PassWall2 的本机代理，让测速直连
disable_local_proxy() {
    ORIG_LOCALHOST_PROXY=$(uci get passwall2.@global[0].localhost_proxy 2>/dev/null)
    if [ -z "$ORIG_LOCALHOST_PROXY" ]; then
        log "提示: 未找到 localhost_proxy 配置项，可能本机流量本来就没走代理，跳过关闭步骤"
        return
    fi
    if [ "$ORIG_LOCALHOST_PROXY" = "0" ]; then
        log "本机代理当前已是关闭状态，无需处理"
        return
    fi
    uci set passwall2.@global[0].localhost_proxy='0'
    uci commit passwall2
    /etc/init.d/passwall2 restart >> "$LOG_FILE" 2>&1
    sleep 3
    PROXY_DISABLED=1
    PROXY_WAS_TOGGLED=1
    log "已临时关闭本机代理，用于直连测速"
}

# 恢复本机代理设置（只改配置，不重启，交给后续统一重启生效）
restore_local_proxy_config() {
    if [ "$PROXY_DISABLED" = "1" ]; then
        uci set passwall2.@global[0].localhost_proxy="$ORIG_LOCALHOST_PROXY"
        uci commit passwall2
        log "已恢复本机代理配置（等待统一重启生效）"
        PROXY_DISABLED=0
    fi
}

# 兜底：如果脚本中途异常退出，确保本机代理设置被恢复，避免代理被永久关闭
safety_restore_on_exit() {
    if [ "$PROXY_DISABLED" = "1" ]; then
        log "检测到脚本异常退出，正在恢复本机代理设置..."
        uci set passwall2.@global[0].localhost_proxy="$ORIG_LOCALHOST_PROXY"
        uci commit passwall2
        /etc/init.d/passwall2 restart >> "$LOG_FILE" 2>&1
        log "已恢复本机代理并重启 PassWall2"
    fi
}
trap safety_restore_on_exit EXIT

if [ ! -x "$CFST_BIN" ]; then
    log "错误: 未找到可执行文件 $CFST_BIN，请检查安装是否正确"
    exit 1
fi

cd "$CFST_DIR" || exit 1

log "===== 开始测速 ====="

if [ "$BYPASS_PROXY_FOR_TEST" = "1" ]; then
    disable_local_proxy
fi

# 拼接完整命令
FULL_ARGS="$CFST_ARGS -o $RESULT_CSV"
if [ -n "$IP_TXT" ] && [ -f "$IP_TXT" ]; then
    FULL_ARGS="$FULL_ARGS -f $IP_TXT"
fi

# 执行测速（只写入日志文件，不向终端输出，避免大量刷屏导致低配设备卡死）
$CFST_BIN $FULL_ARGS >> "$LOG_FILE" 2>&1

if [ ! -f "$RESULT_CSV" ]; then
    log "错误: 测速未生成结果文件，本次跳过"
    exit 1
fi

# 取结果文件第二行（第一行是表头），第一列即为最优 IP
BEST_IP=$(awk -F, 'NR==2{print $1}' "$RESULT_CSV")

# 简单校验 IP 格式
case "$BEST_IP" in
    [0-9]*.[0-9]*.[0-9]*.[0-9]*)
        ;;
    *)
        log "错误: 未能从结果中解析出有效 IP，本次跳过（原始值: $BEST_IP）"
        exit 1
        ;;
esac

log "测速完成，最优 IP: $BEST_IP"

# 测速完成，恢复本机代理配置（先只改配置，跟节点 IP 一起在下面统一重启生效）
restore_local_proxy_config

# ------------------------- 确定要更新的节点 sid -------------------------

SIDS="$PW2_NODE_SIDS"

if [ -z "$SIDS" ] && [ -n "$NODE_REMARK_KEYWORD" ]; then
    SIDS=$(uci show passwall2 | grep "remarks='.*${NODE_REMARK_KEYWORD}.*'" | \
           cut -d'.' -f2 | sort -u | tr '\n' ' ')
fi

if [ -z "$SIDS" ]; then
    log "错误: 未指定或未匹配到任何 PassWall2 节点 sid，请检查 PW2_NODE_SIDS 或 NODE_REMARK_KEYWORD 配置"
    if [ "$PROXY_WAS_TOGGLED" -eq 1 ]; then
        log "本机代理配置已恢复，重启 PassWall2 使其生效..."
        /etc/init.d/passwall2 restart >> "$LOG_FILE" 2>&1
    fi
    exit 1
fi

# ------------------------- 更新 PassWall2 节点 IP -------------------------

CHANGED=0
for sid in $SIDS; do
    if uci get passwall2."$sid" >/dev/null 2>&1; then
        OLD_IP=$(uci get passwall2."$sid".address 2>/dev/null)
        uci set passwall2."$sid".address="$BEST_IP"
        log "节点 $sid: $OLD_IP -> $BEST_IP"
        CHANGED=1
    else
        log "警告: 节点 sid $sid 不存在，跳过"
    fi
done

if [ "$CHANGED" -eq 1 ] || [ "$PROXY_WAS_TOGGLED" -eq 1 ]; then
    uci commit passwall2
    log "配置已提交，重启 PassWall2 服务..."
    /etc/init.d/passwall2 restart >> "$LOG_FILE" 2>&1
    log "PassWall2 已重启"
else
    log "没有任何节点被更新"
fi

log "===== 本次任务结束 ====="
echo "" >> "$LOG_FILE"

exit 0