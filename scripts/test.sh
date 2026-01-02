#!/bin/bash

# ============================================
# WiFi Fallback 环境测试脚本
# 用于验证 setup.sh 的前提条件和依赖是否满足
# 
# 安全保证：此脚本仅执行只读操作，不会修改网络配置或中断 WiFi 连接
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 计数器
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# 输出函数
print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

print_subheader() {
    echo ""
    echo -e "${BLUE}── $1 ──${NC}"
}

print_pass() {
    echo -e "  ${GREEN}✓ PASS${NC}: $1"
    ((PASS_COUNT++))
}

print_fail() {
    echo -e "  ${RED}✗ FAIL${NC}: $1"
    ((FAIL_COUNT++))
}

print_warn() {
    echo -e "  ${YELLOW}⚠ WARN${NC}: $1"
    ((WARN_COUNT++))
}

print_info() {
    echo -e "  ${NC}ℹ INFO${NC}: $1"
}

# ============================================
# 1. 系统信息收集
# ============================================
print_header "1. 系统信息收集"

print_subheader "主机名"
HOSTNAME=$(hostname)
print_info "主机名: $HOSTNAME"

print_subheader "操作系统版本"
DEBIAN_VERSION=""
if [ -f /etc/debian_version ]; then
    DEBIAN_VERSION=$(cat /etc/debian_version)
    print_info "Debian 版本: $DEBIAN_VERSION"
fi

if [ -f /etc/os-release ]; then
    echo ""
    echo "  /etc/os-release 内容:"
    cat /etc/os-release | sed 's/^/    /'
fi

# 检查是否为 Trixie（同时检查 debian_version 和 os-release）
is_trixie=false
if echo "$DEBIAN_VERSION" | grep -qi "trixie"; then
    is_trixie=true
elif grep -qi "VERSION_CODENAME=trixie" /etc/os-release 2>/dev/null; then
    is_trixie=true
fi

if [ "$is_trixie" = true ]; then
    print_pass "检测到 Debian Trixie"
else
    print_fail "未检测到 Debian Trixie"
fi

print_subheader "内核版本"
KERNEL=$(uname -r)
print_info "内核: $KERNEL"

print_subheader "架构信息"
ARCH=$(uname -m)
print_info "架构: $ARCH"
if [ "$ARCH" = "aarch64" ]; then
    print_pass "64位 ARM 架构 (适合 Raspberry Pi Zero 2 W)"
elif [ "$ARCH" = "armv7l" ]; then
    print_warn "32位 ARM 架构 (建议使用 64位系统)"
else
    print_info "非 ARM 架构: $ARCH"
fi

# ============================================
# 2. 命令可用性检查
# ============================================
print_header "2. 命令可用性检查"

check_command() {
    local cmd=$1
    local required=$2
    
    if command -v "$cmd" &> /dev/null; then
        local path=$(command -v "$cmd")
        print_pass "$cmd 可用 ($path)"
    else
        if [ "$required" = "required" ]; then
            print_fail "$cmd 不可用 (必需)"
        else
            print_warn "$cmd 不可用 (可选)"
        fi
    fi
}

print_subheader "核心命令"
check_command "nmcli" "required"
check_command "apt" "required"
check_command "systemctl" "required"
check_command "dpkg" "required"

print_subheader "网络命令"
check_command "nft" "required"
check_command "ip" "required"

print_subheader "Python"
check_command "python3" "required"
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1)
    print_info "Python 版本: $PYTHON_VERSION"
fi

print_subheader "基础工具"
check_command "grep" "required"
check_command "cut" "required"
check_command "head" "required"
check_command "cat" "required"

# ============================================
# 3. NetworkManager 状态
# ============================================
print_header "3. NetworkManager 状态"

print_subheader "服务状态"
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    print_pass "NetworkManager 服务正在运行"
else
    print_fail "NetworkManager 服务未运行"
fi

if systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    print_pass "NetworkManager 已设置开机启动"
else
    print_warn "NetworkManager 未设置开机启动"
fi

print_subheader "WiFi 接口检测"
if command -v nmcli &> /dev/null; then
    WIFI_INTERFACE=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep ':wifi' | cut -d: -f1 | head -n1)
    if [ -n "$WIFI_INTERFACE" ]; then
        print_pass "检测到 WiFi 接口: $WIFI_INTERFACE"
        
        # 获取接口详细信息
        echo ""
        echo "  WiFi 接口详情:"
        nmcli device show "$WIFI_INTERFACE" 2>/dev/null | grep -E "(DEVICE|TYPE|STATE|CONNECTION|WIFI)" | sed 's/^/    /'
    else
        print_fail "未检测到 WiFi 接口"
    fi
    
    print_subheader "当前连接状态"
    echo "  设备状态列表:"
    nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | sed 's/^/    /'
    
    print_subheader "已保存的连接"
    echo "  连接列表:"
    nmcli -t -f NAME,TYPE,DEVICE connection show 2>/dev/null | sed 's/^/    /'
    
    # 检查是否已存在 MyHotspot 连接
    if nmcli con show "MyHotspot" &>/dev/null; then
        print_warn "已存在名为 'MyHotspot' 的连接 (安装时会删除并重建)"
    fi
else
    print_fail "nmcli 命令不可用，无法检测 WiFi"
fi

# ============================================
# 4. 软件包状态
# ============================================
print_header "4. 软件包状态"

check_package() {
    local pkg=$1
    if dpkg -s "$pkg" 2>/dev/null | grep -q "Status: install ok installed"; then
        print_pass "$pkg 已安装"
        return 0
    else
        print_info "$pkg 未安装 (安装时会自动安装)"
        return 1
    fi
}

check_package "network-manager"
check_package "python3-flask"
check_package "nftables"
check_package "dnsmasq"

# 检查 dnsmasq 服务状态
if dpkg -s "dnsmasq" 2>/dev/null | grep -q "Status: install ok installed"; then
    print_subheader "dnsmasq 服务状态"
    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
        print_info "dnsmasq 服务正在运行 (安装时会禁用默认服务)"
    else
        print_info "dnsmasq 服务未运行"
    fi
fi

# ============================================
# 5. 系统服务状态
# ============================================
print_header "5. 系统服务状态"

print_subheader "systemd 状态"
if pidof systemd &>/dev/null; then
    print_pass "systemd 正在运行"
else
    print_fail "systemd 未运行"
fi

print_subheader "现有 wifi-fallback 相关服务"
for service in wifi-fallback.timer wifi-fallback.service wifi-config.service dnsmasq-captive.service; do
    if systemctl list-unit-files "$service" &>/dev/null 2>&1; then
        STATUS=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        ENABLED=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
        print_info "$service: $STATUS / $ENABLED"
    else
        print_info "$service: 不存在"
    fi
done

# 检查现有文件
print_subheader "现有安装文件检查"
for file in /usr/local/bin/wifi-fallback.sh /opt/wifi-config/app.py /etc/dnsmasq-captive.conf; do
    if [ -f "$file" ]; then
        print_warn "$file 已存在 (可能是之前的安装)"
    else
        print_info "$file 不存在"
    fi
done

# ============================================
# 6. 目录和权限检查
# ============================================
print_header "6. 目录和权限检查"

check_dir_writable() {
    local dir=$1
    if [ -d "$dir" ]; then
        if [ -w "$dir" ]; then
            print_pass "$dir 存在且可写"
        else
            print_fail "$dir 存在但不可写"
        fi
    else
        print_warn "$dir 不存在"
    fi
}

print_subheader "目录权限 (需要 root 权限才能写入)"
check_dir_writable "/usr/local/bin"
check_dir_writable "/opt"
check_dir_writable "/etc/systemd/system"
check_dir_writable "/etc"

print_subheader "当前用户"
print_info "用户: $(whoami)"
print_info "UID: $(id -u)"
if [ "$(id -u)" -eq 0 ]; then
    print_pass "当前以 root 权限运行"
else
    print_warn "当前非 root 用户 (安装时需要 sudo)"
fi

# ============================================
# 7. 网络信息（只读）
# ============================================
print_header "7. 网络信息（只读）"

print_subheader "IP 地址"
if command -v ip &>/dev/null; then
    ip -4 addr show 2>/dev/null | grep -E "(inet |^[0-9]+:)" | sed 's/^/    /'
fi

print_subheader "默认网关"
if ip route | grep -q '^default'; then
    DEFAULT_GW=$(ip route | grep '^default' | head -n1)
    print_pass "存在默认网关"
    print_info "$DEFAULT_GW"
else
    print_warn "无默认网关 (可能未连接到外部网络)"
fi

print_subheader "DNS 配置"
if [ -f /etc/resolv.conf ]; then
    echo "  /etc/resolv.conf 内容:"
    cat /etc/resolv.conf | grep -v "^#" | grep -v "^$" | sed 's/^/    /'
fi

print_subheader "路由表"
echo "  路由表:"
ip route 2>/dev/null | sed 's/^/    /'

# ============================================
# 8. nftables 状态
# ============================================
print_header "8. nftables 状态"

print_subheader "当前规则集"
if command -v nft &>/dev/null; then
    NFT_RULES=$(nft list ruleset 2>/dev/null)
    if [ -n "$NFT_RULES" ]; then
        echo "  nftables 规则:"
        echo "$NFT_RULES" | sed 's/^/    /'
    else
        print_info "nftables 规则集为空或无法读取 (可能需要 root 权限)"
    fi
    
    # 检查是否存在 captive_portal 表
    if nft list table ip captive_portal &>/dev/null 2>&1; then
        print_warn "captive_portal 表已存在 (可能是之前的安装)"
    else
        print_info "captive_portal 表不存在 (正常)"
    fi
else
    print_fail "nft 命令不可用"
fi

# ============================================
# 9. AP 热点能力测试
# ============================================
print_header "9. AP 热点能力检测"

if [ -n "$WIFI_INTERFACE" ] && command -v iw &>/dev/null; then
    print_subheader "无线网卡能力"
    AP_SUPPORT=$(iw list 2>/dev/null | grep -A 10 "Supported interface modes:" | grep "AP")
    if [ -n "$AP_SUPPORT" ]; then
        print_pass "无线网卡支持 AP 模式"
    else
        print_warn "无法确认无线网卡是否支持 AP 模式"
    fi
elif [ -n "$WIFI_INTERFACE" ]; then
    print_info "iw 命令不可用，跳过 AP 能力检测"
else
    print_info "无 WiFi 接口，跳过 AP 能力检测"
fi

# ============================================
# 测试结果汇总
# ============================================
print_header "测试结果汇总"

echo ""
echo -e "  ${GREEN}通过${NC}: $PASS_COUNT"
echo -e "  ${RED}失败${NC}: $FAIL_COUNT"
echo -e "  ${YELLOW}警告${NC}: $WARN_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ 所有必要条件已满足，可以运行 setup.sh${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  ✗ 存在 $FAIL_COUNT 个失败项，请先解决后再运行 setup.sh${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
fi

echo ""

