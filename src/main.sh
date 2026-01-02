#!/bin/bash

# 树莓派 Zero 2 W 的 WiFi 回退设置脚本，适用于 Raspberry Pi OS 64位版（Debian Trixie）
# 此脚本用于安装或卸载 WiFi 回退机制：
# - 检查 WiFi 连接；如果连接失败，则启动 AP 热点。
# - 允许通过 AP 上的 Web 界面配置 WiFi SSID/密码。
# - 需要 NetworkManager。
# - 自动检测 WiFi 接口。
# - 安装/卸载时需要使用 sudo 运行。
# - 用法: sudo ./setup.sh install（安装）
# -       sudo ./setup.sh uninstall（卸载）

# @INCLUDE: config.sh
# @INCLUDE: lib/utils.sh
# @INCLUDE: lib/install.sh
# @INCLUDE: lib/uninstall.sh

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run with sudo privileges."
    exit 1
fi

# 检查操作系统版本（同时检查 debian_version 和 os-release）
is_trixie=false
if grep -qi "trixie" /etc/debian_version 2>/dev/null; then
    is_trixie=true
elif grep -qi "VERSION_CODENAME=trixie" /etc/os-release 2>/dev/null; then
    is_trixie=true
fi

if [ "$is_trixie" = false ]; then
    echo "This script is designed for Debian Trixie (Raspberry Pi OS 64-bit). Aborting."
    exit 1
fi

# 显示帮助信息
show_help() {
    cat << EOF
WiFi Fallback Setup Script for Raspberry Pi

Usage: sudo $0 <command>

Commands:
  install      Install WiFi fallback mechanism
  uninstall    Remove WiFi fallback mechanism and all components

Examples:
  sudo $0 install      # Install
  sudo $0 uninstall    # Uninstall
EOF
}

# 解析命令行参数
case "$1" in
    install|--install)
        install
        ;;
    uninstall|--uninstall)
        uninstall
        ;;
    ""|--help|-h|help)
        show_help
        exit 0
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo
        show_help
        exit 1
        ;;
esac

