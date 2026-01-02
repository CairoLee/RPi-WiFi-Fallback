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

    # 检查是否需要安装任何依赖包
    # 注意：dnsmasq 不需要单独安装，NetworkManager 在 shared 模式下内置了 dnsmasq 功能
    NEED_APT_UPDATE=false
    for pkg in nftables pipx network-manager; do
        if ! package_installed "$pkg"; then
            NEED_APT_UPDATE=true
            break
        fi
    done

    # 只有在需要安装包时才执行 apt update
    if [ "$NEED_APT_UPDATE" = true ]; then
        echo "Updating package list..."
        apt update -y || { echo "Failed to update packages."; exit 1; }
    fi

    # 安装缺失的依赖包
    for pkg in nftables pipx; do
        if ! package_installed "$pkg"; then
            echo "Installing $pkg..."
            apt install -y "$pkg" || { echo "Failed to install $pkg."; exit 1; }
        fi
    done

    # 检查 NetworkManager 是否已安装
    if ! package_installed network-manager; then
        echo "Installing NetworkManager..."
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

    # 安装 uv 到系统路径（如果不存在）
    if ! command -v uv &> /dev/null; then
        echo "Installing uv..."
        PIPX_BIN_DIR=/usr/local/bin pipx install uv || { echo "Failed to install uv."; exit 1; }
    fi

    # 创建 Web 应用目录和日志目录
    mkdir -p /opt/wifi-config/logs
    echo "Creating /opt/wifi-config/app.py..."
    cat > /opt/wifi-config/app.py << 'PYEOF'
# @TEMPLATE: app.py
PYEOF
    # 替换 app.py 中的模板变量
    sed -i "s/{{AP_CONNECTION_NAME}}/$AP_CONNECTION_NAME/g" /opt/wifi-config/app.py

    # 创建 pyproject.toml
    echo "Creating /opt/wifi-config/pyproject.toml..."
    cat > /opt/wifi-config/pyproject.toml << 'TOMLEOF'
# @TEMPLATE: pyproject.toml
TOMLEOF

    # 创建虚拟环境并安装依赖
    echo "Creating Python virtual environment and installing dependencies..."
    cd /opt/wifi-config
    uv sync

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

    # 验证 Web 服务能否正常启动
    echo "Verifying web service..."
    systemctl start wifi-config.service
    verification_ok=false
    for i in $(seq 1 10); do
        if curl -s --connect-timeout 1 http://127.0.0.1/ > /dev/null 2>&1; then
            echo "Web service verification: OK (${i}s)"
            verification_ok=true
            break
        fi
        sleep 1
    done
    if [ "$verification_ok" = false ]; then
        echo "Warning: Web service verification failed. Check /opt/wifi-config/app.py"
    fi
    systemctl stop wifi-config.service

    echo ""
    echo "Installation complete."
    echo "WiFi fallback timer is now active and will check connectivity every 30 seconds."
}

