#!/bin/bash

# 使用 logger 写入 systemd journal（断电重启后仍保留）
log() {
    logger -t wifi-fallback "\$1"
    echo "[\$(date)] \$1" >> /tmp/wifi-fallback.log
    sync  # 强制刷新到磁盘
}

log "脚本开始执行"

# nftables 表名（用于强制门户重定向）
NFT_TABLE="captive_portal"

# 检查是否有默认网关（表示已连接到外部网络）
# AP 模式下设备是网关本身，不会有外部网关路由
if ip route | grep -q '^default'; then
    log "检测到默认网关，已连接外网"
    # 已连接到外部网络，如果 AP 处于活动状态则关闭
    if nmcli con show --active | grep -q '{{AP_CONNECTION_NAME}}'; then
        log "关闭 AP..."
        nmcli con down '{{AP_CONNECTION_NAME}}'
        systemctl stop wifi-config.service
        # 移除 nftables 规则（删除整个表）
        nft delete table ip \$NFT_TABLE 2>/dev/null
    fi
    exit 0
fi

log "未检测到默认网关，启动 AP 模式"

# 未连接到外部网络，启动 AP
AP_RESULT=\$(nmcli con up '{{AP_CONNECTION_NAME}}' 2>&1)
log "AP 启动: \$AP_RESULT"

# 先删除可能存在的旧表（防止重复）
nft delete table ip \$NFT_TABLE 2>/dev/null

# 创建 nftables 表和链用于强制门户重定向
nft add table ip \$NFT_TABLE
nft add chain ip \$NFT_TABLE prerouting { type nat hook prerouting priority -100 \; }

# 设置强制门户重定向规则（仅 HTTP）
# 注意：不劫持 HTTPS，因为会导致证书错误
# DNS 由 NetworkManager 的内置 dnsmasq 处理
nft add rule ip \$NFT_TABLE prerouting iifname "{{AP_INTERFACE}}" tcp dport 80 redirect to :80
log "nftables 规则已添加"

# 启动 Web 配置服务
systemctl start wifi-config.service
FLASK_STATUS=\$(systemctl is-active wifi-config.service)
log "wifi-config.service 状态: \$FLASK_STATUS"

# 验证服务是否真正启动
sleep 1
if curl -s --connect-timeout 2 http://127.0.0.1/ > /dev/null 2>&1; then
    log "Flask 服务验证: 正常响应"
else
    log "Flask 服务验证: 无响应!"
fi

log "脚本执行完毕"
