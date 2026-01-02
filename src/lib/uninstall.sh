# 卸载机制的函数
uninstall() {
    echo "Starting uninstallation..."

    # 如果需要清理则检测 WiFi 接口
    AP_INTERFACE=$(nmcli -t -f DEVICE,TYPE device | grep ':wifi' | cut -d: -f1 | head -n1)

    # 停止并禁用服务/定时器
    systemctl stop wifi-config.service 2>/dev/null
    systemctl stop wifi-fallback.service 2>/dev/null
    systemctl stop wifi-fallback.timer 2>/dev/null
    systemctl disable wifi-fallback.timer 2>/dev/null
    systemctl disable wifi-config.service 2>/dev/null  # 虽然默认未启用

    # 移除 systemd 文件
    rm -f /etc/systemd/system/wifi-fallback.timer
    rm -f /etc/systemd/system/wifi-fallback.service
    rm -f /etc/systemd/system/wifi-config.service
    systemctl daemon-reload

    # 移除 NetworkManager dnsmasq 配置
    rm -f /etc/NetworkManager/dnsmasq-shared.d/captive-portal.conf

    # 移除脚本和应用
    rm -f /usr/local/bin/wifi-fallback.sh
    rm -rf /opt/wifi-config

    # 删除 AP 连接
    nmcli con delete "$AP_CONNECTION_NAME" 2>/dev/null

    # 移除 nftables 规则（删除整个表）
    nft delete table ip captive_portal 2>/dev/null

    echo "Uninstallation complete. All components removed."
}

