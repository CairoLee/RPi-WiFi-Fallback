# 检测 WiFi 接口的函数
detect_wifi_interface() {
    AP_INTERFACE=$(nmcli -t -f DEVICE,TYPE device | grep ':wifi' | cut -d: -f1 | head -n1)
    if [ -z "$AP_INTERFACE" ]; then
        echo "No WiFi interface detected. Aborting."
        exit 1
    fi
    echo "Detected WiFi interface: $AP_INTERFACE"
}

# 检查软件包是否已安装的函数
package_installed() {
    dpkg -s "$1" 2>/dev/null | grep -q "Status: install ok installed"
}

