# 安装机制的函数
install() {
    echo "Starting installation..."

    # 验证 AP 密码长度
    if [ ${#AP_PASSWORD} -lt 8 ]; then
        echo "Error: AP password must be at least 8 characters."
        exit 1
    fi

    # 检测 WiFi 接口
    detect_wifi_interface

    # 更新软件包列表
    apt update -y || { echo "Failed to update packages."; exit 1; }

    # 如果依赖项不存在则安装（使用 nftables，无需 iptables）
    # 注意：dnsmasq 不需要单独安装，NetworkManager 在 shared 模式下内置了 dnsmasq 功能
    for pkg in python3-flask nftables; do
        if ! package_installed "$pkg"; then
            echo "Installing $pkg..."
            apt install -y "$pkg" || { echo "Failed to install $pkg."; exit 1; }
        else
            echo "$pkg is already installed."
        fi
    done

    # 检查 NetworkManager 是否已安装并处于活动状态
    if ! package_installed network-manager; then
        echo "NetworkManager not found. Installing..."
        apt install -y network-manager || { echo "Failed to install NetworkManager."; exit 1; }
    fi
    if ! systemctl is-active --quiet NetworkManager; then
        echo "Starting NetworkManager..."
        systemctl enable --now NetworkManager || { echo "Failed to start NetworkManager."; exit 1; }
    fi

    # 创建或重新创建 AP 连接
    nmcli con show "$AP_CONNECTION_NAME" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Deleting existing $AP_CONNECTION_NAME connection..."
        nmcli con delete "$AP_CONNECTION_NAME" || { echo "Failed to delete existing connection."; exit 1; }
    fi
    echo "Creating AP connection..."
    nmcli con add type wifi ifname "$AP_INTERFACE" con-name "$AP_CONNECTION_NAME" autoconnect no ssid "$AP_SSID" mode ap 802-11-wireless.band bg 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.proto rsn 802-11-wireless-security.pairwise ccmp 802-11-wireless-security.group ccmp 802-11-wireless-security.psk "$AP_PASSWORD" ipv4.method shared ipv4.addresses "$AP_IP" || { echo "Failed to create AP connection."; exit 1; }

    # 创建回退脚本
    echo "Creating /usr/local/bin/wifi-fallback.sh..."
    cat > /usr/local/bin/wifi-fallback.sh << EOF
# @TEMPLATE: wifi-fallback.sh
EOF
    chmod +x /usr/local/bin/wifi-fallback.sh || { echo "Failed to make fallback script executable."; exit 1; }

    # 创建 Web 应用目录和脚本
    mkdir -p /opt/wifi-config
    echo "Creating /opt/wifi-config/app.py..."
    cat > /opt/wifi-config/app.py << 'PYEOF'
# @TEMPLATE: app.py
PYEOF

    # 提取 AP IP 地址（去掉 CIDR 后缀）
    AP_IP_ADDR=${AP_IP%/*}

    # 创建 NetworkManager dnsmasq 共享配置（强制门户 DNS 劫持）
    # NetworkManager 在 shared 模式下会自动加载此配置
    echo "Creating /etc/NetworkManager/dnsmasq-shared.d/captive-portal.conf..."
    mkdir -p /etc/NetworkManager/dnsmasq-shared.d
    cat > /etc/NetworkManager/dnsmasq-shared.d/captive-portal.conf << DNSEOF
# @TEMPLATE: captive-portal.conf
DNSEOF

    # 创建 systemd 定时器
    echo "Creating /etc/systemd/system/wifi-fallback.timer..."
    cat > /etc/systemd/system/wifi-fallback.timer << EOF
# @TEMPLATE: wifi-fallback.timer
EOF

    # 创建回退功能的 systemd 服务
    echo "Creating /etc/systemd/system/wifi-fallback.service..."
    cat > /etc/systemd/system/wifi-fallback.service << EOF
# @TEMPLATE: wifi-fallback.service
EOF

    # 创建 Web 配置的 systemd 服务
    echo "Creating /etc/systemd/system/wifi-config.service..."
    cat > /etc/systemd/system/wifi-config.service << EOF
# @TEMPLATE: wifi-config.service
EOF

    # 重新加载并启用
    systemctl daemon-reload || { echo "Failed to reload systemd."; exit 1; }
    systemctl enable wifi-fallback.timer || { echo "Failed to enable timer."; exit 1; }
    systemctl start wifi-fallback.timer || { echo "Failed to start timer."; exit 1; }

    echo "Installation complete. WiFi fallback timer is now active and will check connectivity every 30 seconds."
}

