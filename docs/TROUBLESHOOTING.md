# WiFi 回退机制开发踩坑记录

本文档记录了在 Raspberry Pi Zero 2 W (Debian Trixie) 上开发 WiFi 回退机制时遇到的问题及解决方案。

---

## 目录

1. [系统环境相关](#1-系统环境相关)
2. [NetworkManager 与 AP 配置](#2-networkmanager-与-ap-配置)
3. [强制门户（Captive Portal）](#3-强制门户captive-portal)
4. [Web 应用与后台任务](#4-web-应用与后台任务)
5. [WiFi 连接管理](#5-wifi-连接管理)

---

## 1. 系统环境相关

### 1.1 iptables vs nftables

**问题**：脚本使用 `iptables` 命令，但在 Debian Trixie 上执行失败。

**原因**：Debian Trixie 默认使用 `nftables`，不再预装 `iptables`。

**解决方案**：
```bash
# 错误：使用 iptables
iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 80 -j REDIRECT --to-port 80

# 正确：使用 nftables
nft add table ip captive_portal
nft add chain ip captive_portal prerouting { type nat hook prerouting priority -100 \; }
nft add rule ip captive_portal prerouting iifname "wlan0" tcp dport 80 redirect to :80
```

### 1.2 操作系统版本检测

**问题**：检测 `/etc/debian_version` 时，显示 "13.2" 而不是 "trixie"。

**原因**：某些系统配置下，`/etc/debian_version` 只包含版本号。

**解决方案**：同时检查 `/etc/debian_version` 和 `/etc/os-release`：
```bash
is_trixie=false
if grep -qi "trixie" /etc/debian_version 2>/dev/null; then
    is_trixie=true
elif grep -qi "VERSION_CODENAME=trixie" /etc/os-release 2>/dev/null; then
    is_trixie=true
fi
```

### 1.3 nmcli 命令兼容性

**问题**：`nmcli con show --order recent` 在某些版本上不支持。

**原因**：`--order` 选项在较新版本的 nmcli 中才支持。

**解决方案**：不使用 `--order` 参数，直接遍历所有连接：
```bash
nmcli -t -f NAME,TYPE con show | grep ":802-11-wireless$"
```

---

## 2. NetworkManager 与 AP 配置

### 2.1 iPhone 无法连接 AP

**问题**：iPhone 尝试连接 AP 时失败，提示"无法加入网络"或"低安全性"。

**原因**：AP 的安全配置不够明确，iPhone 对 WPA 安全性要求较严格。

**解决方案**：创建 AP 时明确指定 WPA2 安全参数：
```bash
nmcli con add type wifi ifname wlan0 con-name RPi-WiFi-Setup-Hotspot \
    autoconnect no ssid "RPi-WiFi-Setup" mode ap \
    802-11-wireless.band bg \
    802-11-wireless-security.key-mgmt wpa-psk \
    802-11-wireless-security.proto rsn \
    802-11-wireless-security.pairwise ccmp \
    802-11-wireless-security.group ccmp \
    802-11-wireless-security.psk "your-password" \
    ipv4.method shared ipv4.addresses "192.168.4.1/24"
```

### 2.2 WiFi 连接状态检测

**问题**：使用 `nmcli ... | grep 'wifi:connected'` 检测连接状态不准确。

**原因**：AP 模式下设备也显示为 "connected"，但实际没有外网连接。

**解决方案**：检测是否有默认网关（外网连接）：
```bash
# AP 模式下设备是网关本身，不会有外部默认路由
if ip route | grep -q '^default'; then
    echo "已连接到外部网络"
else
    echo "未连接到外部网络，需要启动 AP"
fi
```

---

## 3. 强制门户（Captive Portal）

### 3.1 DNS 服务冲突

**问题**：自定义的 `dnsmasq` 服务无法启动，端口 53 被占用。

**原因**：NetworkManager 在 `shared` 模式下会自动启动内置的 dnsmasq 实例。

**解决方案**：使用 NetworkManager 的 dnsmasq 配置目录：
```bash
# 创建配置文件
mkdir -p /etc/NetworkManager/dnsmasq-shared.d
cat > /etc/NetworkManager/dnsmasq-shared.d/captive-portal.conf << EOF
# 将所有域名解析到 AP IP，触发强制门户检测
address=/#/192.168.4.1
EOF

# NetworkManager 会在 shared 模式下自动加载此配置
```

### 3.2 HTTPS 重定向导致 SSL 错误

**问题**：重定向 HTTPS (443) 流量到本地 80 端口后，浏览器显示 SSL 证书错误。

**原因**：
- 没有有效的 SSL 证书
- HSTS (HTTP Strict Transport Security) 缓存导致后续 HTTP 访问也失败

**解决方案**：**不要劫持 HTTPS 流量**，只重定向 HTTP：
```bash
# 只重定向 HTTP，不处理 HTTPS
nft add rule ip captive_portal prerouting iifname "wlan0" tcp dport 80 redirect to :80
# 不添加 443 端口的规则
```

### 3.3 iOS 强制门户不自动弹出

**问题**：iPhone 连接 AP 后，强制门户页面不自动弹出。

**原因**：iOS 通过访问特定 URL 检测强制门户，Web 应用只响应根路径 `/`，返回 404。

**iOS 检测 URL**：`http://captive.apple.com/hotspot-detect.html`

**解决方案**：Flask 应用响应所有路径：
```python
@app.route('/', defaults={'path': ''}, methods=['GET', 'POST'])
@app.route('/<path:path>', methods=['GET', 'POST'])
def home(path):
    # 所有路径都返回配置页面
    return render_template_string(HTML)
```

### 3.4 各平台强制门户检测 URL

| 平台 | 检测 URL | 期望响应 |
|------|----------|----------|
| iOS/macOS | `http://captive.apple.com/hotspot-detect.html` | "Success" 文本 |
| Android | `http://connectivitycheck.gstatic.com/generate_204` | HTTP 204 |
| Windows | `http://www.msftconnecttest.com/connecttest.txt` | "Microsoft Connect Test" |
| Firefox | `http://detectportal.firefox.com/success.txt` | "success" |

返回非预期响应（如 HTML 页面）会触发强制门户弹窗。

---

## 4. Web 应用与后台任务

### 4.1 Python daemon 线程被提前终止

**问题**：用户提交 WiFi 配置后，后台线程没有完成执行，WiFi 连接失败。

**原因**：
- `daemon=True` 的线程在主进程退出时会被强制终止
- `systemctl stop` 会终止 Flask 进程，导致 daemon 线程也被杀死

**解决方案**：使用独立的 shell 脚本，通过 `nohup` 在完全独立的进程中执行：
```python
def schedule_wifi_connect(ssid, password):
    import os
    
    script_content = f'''#!/bin/bash
sleep 6
nmcli con down RPi-WiFi-Setup-Hotspot
# ... 其他命令
'''
    
    script_path = '/tmp/wifi-connect.sh'
    with open(script_path, 'w') as f:
        f.write(script_content)
    os.chmod(script_path, 0o755)
    
    # 使用 nohup 在独立进程中执行
    subprocess.Popen(
        ['nohup', 'bash', script_path],
        stdout=open('/tmp/wifi-connect.log', 'w'),
        stderr=subprocess.STDOUT,
        start_new_session=True,  # 创建新会话，不受父进程影响
        close_fds=True
    )
```

### 4.2 成功页面显示时间太短

**问题**：用户点击连接后，成功提示还没看清就被关闭了。

**原因**：AP 关闭后 iOS 立即关闭强制门户页面。

**解决方案**：
1. 增加延迟时间（6秒）
2. 显示带倒计时的成功页面
3. 添加提示信息告知用户页面即将关闭

---

## 5. WiFi 连接管理

### 5.1 AP 运行时无法连接 WiFi

**问题**：在 AP 运行时执行 `nmcli device wifi connect` 失败。

**错误信息**：`Error: 802-11-wireless-security.key-mgmt: property is missing.`

**原因**：WiFi 接口被 AP 占用，无法同时作为客户端连接其他网络。

**解决方案**：先关闭 AP，等待接口释放，再连接 WiFi：
```bash
# 1. 关闭 AP
nmcli con down RPi-WiFi-Setup-Hotspot

# 2. 等待接口释放
sleep 2

# 3. 连接 WiFi
nmcli device wifi connect "SSID" password "PASSWORD"
```

### 5.2 已存在的 WiFi 连接无法更新密码

**问题**：使用 `nmcli device wifi connect` 连接已存在的 SSID 时，使用旧密码而不是新输入的密码。

**原因**：如果 SSID 已有连接配置，nmcli 会尝试使用现有配置，忽略命令行提供的密码。

**解决方案**：检查是否存在同名连接，如果存在则修改密码：
```bash
SSID="Raspberry"
PASSWORD="new_password"

# 查找现有连接
EXISTING_CON=$(nmcli -t -f NAME,TYPE con show | grep ":802-11-wireless$" | cut -d: -f1 | while read name; do
    CON_SSID=$(nmcli -g 802-11-wireless.ssid con show "$name" 2>/dev/null)
    if [ "$CON_SSID" = "$SSID" ]; then
        echo "$name"
        break
    fi
done)

if [ -n "$EXISTING_CON" ]; then
    # 更新现有连接的密码
    nmcli con modify "$EXISTING_CON" wifi-sec.psk "$PASSWORD"
    # 激活连接
    nmcli con up "$EXISTING_CON"
else
    # 创建新连接
    nmcli device wifi connect "$SSID" password "$PASSWORD"
fi
```

### 5.3 无法获取 netplan 管理的 WiFi 密码

**问题**：尝试预填充已保存的 WiFi 密码时，获取到的是加密的派生密钥而不是原始密码。

**原因**：出于安全考虑，NetworkManager 存储的是 WPA PSK 派生密钥（64位十六进制），不是原始密码。

**解决方案**：只预填充 SSID，密码留空让用户输入：
```python
def get_last_wifi_ssid():
    """只获取 SSID，密码无法获取"""
    # ... 获取 SSID 的逻辑
    return ssid

# 在表单中
return render_template_string(HTML, ssid=ssid, password='')
```

---

## 总结

开发 WiFi 回退机制的关键点：

1. **了解目标系统环境**：Debian Trixie 使用 nftables，不是 iptables
2. **正确配置 AP 安全性**：明确指定 WPA2 参数以兼容 iPhone
3. **不要劫持 HTTPS**：会导致 SSL 错误和 HSTS 问题
4. **响应所有 HTTP 路径**：触发各平台的强制门户检测
5. **使用独立进程执行后台任务**：避免 daemon 线程被提前终止
6. **正确处理现有 WiFi 连接**：更新密码而不是创建新连接
7. **先关闭 AP 再连接 WiFi**：避免接口占用冲突

