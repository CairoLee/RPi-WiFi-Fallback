#!/bin/bash
# ============================================
# WiFi 连接脚本模板
# ============================================
# 变量替换说明（全部运行时替换，Python .replace()）：
#   - {{ssid}}:              用户输入的 WiFi 名称
#   - {{password}}:          用户输入的 WiFi 密码
#   - {{ap_connection_name}}: AP 热点连接名称（来自 config.py）
# ============================================

# 使用时间戳命名日志，保留历史记录
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="/opt/wifi-config/logs/wifi-connect-$TIMESTAMP.log"

log() {
    echo "[$(date '+%H:%M:%S')] $1" >> $LOG
}

echo "=== WiFi 连接脚本开始 ===" > $LOG
date >> $LOG

SSID="{{ssid}}"
PASSWORD="{{password}}"
TARGET_AP="{{ap_connection_name}}"

log "目标 SSID: $SSID"

# 停止 wifi-fallback.timer，防止在连接过程中被干扰
log "停止 wifi-fallback.timer..."
systemctl stop wifi-fallback.timer 2>> $LOG
log "timer 状态: $(systemctl is-active wifi-fallback.timer)"

# 等待页面响应发送完成
log "等待 6 秒..."
sleep 6

# 关闭 AP 热点
log "关闭 AP..."
nmcli con down "$TARGET_AP" 2>> $LOG

# 等待 WiFi 接口释放
log "等待接口释放..."
sleep 3

# 获取 WiFi 接口
WIFI_IF=$(nmcli -t -f DEVICE,TYPE device | grep ':wifi' | cut -d: -f1 | head -n1)
log "WiFi 接口: $WIFI_IF"

# 记录当前连接状态
log "关闭 AP 后的连接状态:"
nmcli con show --active >> $LOG
log "当前路由:"
ip route >> $LOG

# 检查是否存在同名 SSID 的连接配置
log "检查现有连接配置..."
EXISTING_CON=$(nmcli -t -f NAME,TYPE con show | grep ":802-11-wireless$" | cut -d: -f1 | while read name; do
    CON_SSID=$(nmcli -g 802-11-wireless.ssid con show "$name" 2>/dev/null)
    if [ "$CON_SSID" = "$SSID" ]; then
        echo "$name"
        break
    fi
done)

if [ -n "$EXISTING_CON" ]; then
    log "找到现有连接: $EXISTING_CON，更新密码并重新连接..."
    # 先断开（如果已连接）
    nmcli con down "$EXISTING_CON" 2>> $LOG
    # 更新密码
    nmcli con modify "$EXISTING_CON" wifi-sec.psk "$PASSWORD" 2>> $LOG
    # 激活连接
    log "激活连接..."
    CONNECT_RESULT=$(nmcli con up "$EXISTING_CON" 2>&1)
    log "连接结果: $CONNECT_RESULT"
else
    log "未找到现有连接，创建新连接..."
    CONNECT_RESULT=$(nmcli device wifi connect "$SSID" password "$PASSWORD" 2>&1)
    log "连接结果: $CONNECT_RESULT"
fi

# 等待连接完成（最多 15 秒）
# 不仅检测默认网关，还要确认连接的是目标 SSID
log "等待连接完成..."
CONNECTED=false
for i in $(seq 1 15); do
    # 检查是否连接到目标 SSID
    CURRENT_SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2)
    log "第 ${i} 秒：SSID=$CURRENT_SSID, 网关=$(ip route | grep -q '^default' && echo '有' || echo '无')"
    
    if [ "$CURRENT_SSID" = "$SSID" ] && ip route | grep -q '^default'; then
        log "已连接到目标 SSID 且检测到默认网关"
        CONNECTED=true
        break
    fi
    sleep 1
done

log "最终连接状态:"
nmcli con show --active >> $LOG
log "最终路由:"
ip route >> $LOG

# 根据连接结果决定后续操作
if [ "$CONNECTED" = true ]; then
    log "连接成功，停止配置服务..."
    systemctl stop wifi-config.service
else
    log "连接失败，重新启动 AP 和配置服务..."
    nmcli con up "$TARGET_AP" 2>> $LOG
    
    # 重新设置 nftables 强制门户规则
    NFT_TABLE="captive_portal"
    nft delete table ip $NFT_TABLE 2>/dev/null
    nft add table ip $NFT_TABLE
    nft add chain ip $NFT_TABLE prerouting '{ type nat hook prerouting priority -100 ; }'
    nft add rule ip $NFT_TABLE prerouting iifname "$WIFI_IF" tcp dport 80 redirect to :80
    log "nftables 规则已重新设置 (接口: $WIFI_IF)"
    
    systemctl start wifi-config.service
fi

# 恢复 wifi-fallback.timer
log "恢复 wifi-fallback.timer..."
systemctl start wifi-fallback.timer 2>> $LOG
log "timer 状态: $(systemctl is-active wifi-fallback.timer)"

log "=== 脚本完成 ==="

# 删除自身
rm -f "$0"

