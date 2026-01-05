#!/bin/bash

# 树莓派 WiFi 回退设置脚本，适用于 Raspberry Pi OS 64 位版（Debian Bookworm/Trixie）
# 此脚本用于安装或卸载 WiFi 回退机制：
# - 检查 WiFi 连接；如果连接失败，则启动 AP 热点。
# - 允许通过 AP 上的 Web 界面配置 WiFi SSID/密码。
# - 需要 NetworkManager。
# - 自动检测 WiFi 接口。
# - 安装/卸载时需要使用 sudo 运行。
# - 用法: sudo ./setup.sh install（安装）
# -       sudo ./setup.sh uninstall（卸载）

# 配置变量（支持环境变量覆盖，未设置时使用默认值）
: "${WIFI_AP_SSID:=RPi-WiFi-Setup}"                      # AP 热点 SSID
: "${WIFI_AP_PASSWORD:=raspberry2026}"                   # AP 热点密码（至少8个字符）
: "${WIFI_AP_CONNECTION_NAME:=RPi-WiFi-Setup-Hotspot}"   # NetworkManager 连接名称
: "${WIFI_AP_IP:=192.168.4.1/24}"                        # AP IP 地址范围
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
# 安装机制的函数
install() {
    echo "Starting installation..."

    # 验证 AP 密码长度
    if [ ${#WIFI_AP_PASSWORD} -lt 8 ]; then
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
    nmcli con show "$WIFI_AP_CONNECTION_NAME" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Deleting existing $WIFI_AP_CONNECTION_NAME connection..."
        nmcli con delete "$WIFI_AP_CONNECTION_NAME" || { echo "Failed to delete existing connection."; exit 1; }
    fi
    echo "Creating AP connection..."
    nmcli con add type wifi ifname "$AP_INTERFACE" con-name "$WIFI_AP_CONNECTION_NAME" autoconnect no ssid "$WIFI_AP_SSID" mode ap 802-11-wireless.band bg 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.proto rsn 802-11-wireless-security.pairwise ccmp 802-11-wireless-security.group ccmp 802-11-wireless-security.psk "$WIFI_AP_PASSWORD" ipv4.method shared ipv4.addresses "$WIFI_AP_IP" || { echo "Failed to create AP connection."; exit 1; }

    # 创建回退脚本
    echo "Creating /usr/local/bin/wifi-fallback.sh..."
    cat > /usr/local/bin/wifi-fallback.sh << EOF
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
    if nmcli con show --active | grep -q '$WIFI_AP_CONNECTION_NAME'; then
        log "关闭 AP..."
        nmcli con down '$WIFI_AP_CONNECTION_NAME'
        systemctl stop wifi-config.service
        # 移除 nftables 规则（删除整个表）
        nft delete table ip \$NFT_TABLE 2>/dev/null
    fi
    exit 0
fi

# 检查 AP 是否已经在运行
if nmcli con show --active | grep -q '$WIFI_AP_CONNECTION_NAME'; then
    log "AP 已在运行"
    
    # 确保 nftables 规则存在（可能被其他进程清除）
    if ! nft list table ip \$NFT_TABLE > /dev/null 2>&1; then
        log "nftables 规则丢失，重新添加..."
        nft add table ip \$NFT_TABLE
        nft add chain ip \$NFT_TABLE prerouting { type nat hook prerouting priority -100 \; }
        nft add rule ip \$NFT_TABLE prerouting iifname "$AP_INTERFACE" tcp dport 80 redirect to :80
    fi
    
    # 检查配置服务状态
    FLASK_STATUS=\$(systemctl is-active wifi-config.service)
    log "Flask 服务状态: \$FLASK_STATUS"
    
    if [ "\$FLASK_STATUS" != "active" ]; then
        log "启动配置服务..."
        systemctl start wifi-config.service
        sleep 2
    fi
    
    # 每次都验证 Flask 是否真正可访问
    if curl -s --connect-timeout 2 http://127.0.0.1/ > /dev/null 2>&1; then
        log "Flask 可访问: 是"
    else
        log "Flask 可访问: 否! 尝试重启..."
        systemctl restart wifi-config.service
        sleep 2
        if curl -s --connect-timeout 2 http://127.0.0.1/ > /dev/null 2>&1; then
            log "重启后 Flask 可访问: 是"
        else
            log "重启后 Flask 可访问: 否!"
        fi
    fi
    exit 0
fi

log "未检测到默认网关，启动 AP 模式"

# 未连接到外部网络，启动 AP
AP_RESULT=\$(nmcli con up '$WIFI_AP_CONNECTION_NAME' 2>&1)
log "AP 启动: \$AP_RESULT"

# 先删除可能存在的旧表（防止重复）
nft delete table ip \$NFT_TABLE 2>/dev/null

# 创建 nftables 表和链用于强制门户重定向
nft add table ip \$NFT_TABLE
nft add chain ip \$NFT_TABLE prerouting { type nat hook prerouting priority -100 \; }

# 设置强制门户重定向规则（仅 HTTP）
# 注意：不劫持 HTTPS，因为会导致证书错误
# DNS 由 NetworkManager 的内置 dnsmasq 处理
nft add rule ip \$NFT_TABLE prerouting iifname "$AP_INTERFACE" tcp dport 80 redirect to :80
log "nftables 规则已添加"

# 启动 Web 配置服务
systemctl start wifi-config.service
FLASK_STATUS=\$(systemctl is-active wifi-config.service)
log "wifi-config.service 状态: \$FLASK_STATUS"

# 验证服务是否真正启动（最多等待 5 秒）
log "等待 Flask 服务就绪..."
FLASK_READY=false
for i in 1 2 3 4 5; do
    sleep 1
    if curl -s --connect-timeout 2 http://127.0.0.1/ > /dev/null 2>&1; then
        log "Flask 服务验证: 第 \${i} 秒响应正常"
        FLASK_READY=true
        break
    fi
    log "Flask 服务验证: 第 \${i} 秒无响应"
done

if [ "\$FLASK_READY" = false ]; then
    log "Flask 服务 5 秒内未就绪，尝试重启..."
    systemctl restart wifi-config.service
    sleep 2
    if curl -s --connect-timeout 2 http://127.0.0.1/ > /dev/null 2>&1; then
        log "重启后 Flask 服务: 正常响应"
    else
        log "重启后 Flask 服务: 仍无响应!"
    fi
fi

log "脚本执行完毕"
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
from flask import Flask, request, render_template_string, redirect, make_response
import subprocess

from config import WIFI_AP_CONNECTION_NAME

app = Flask(__name__)

# Captive Portal Detection 端点列表
# 这些是各操作系统用于检测 captive portal 的 URL
CAPTIVE_PORTAL_PATHS = {
    # Apple iOS/macOS
    'hotspot-detect.html',
    'library/test/success.html',
    # Android
    'generate_204',
    'gen_204',
    'connectivitycheck.gstatic.com',
    # Windows
    'ncsi.txt',
    'connecttest.txt',
    # Firefox
    'success.txt',
}

# WiFi 连接脚本模板（构建时嵌入）
# 运行时由 Python .replace() 替换所有 {{变量}}
WIFI_CONNECT_SCRIPT_TEMPLATE = '''#!/bin/bash
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
'''

FORM_HTML = '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <title>WiFi 配置</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .container {
      background: white;
      border-radius: 16px;
      padding: 32px 24px;
      width: 100%;
      max-width: 360px;
      box-shadow: 0 10px 40px rgba(0,0,0,0.2);
    }
    h1 {
      color: #333;
      font-size: 24px;
      font-weight: 600;
      text-align: center;
      margin-bottom: 8px;
    }
    .subtitle {
      color: #666;
      font-size: 14px;
      text-align: center;
      margin-bottom: 24px;
    }
    .form-group { margin-bottom: 16px; }
    label {
      display: block;
      color: #555;
      font-size: 14px;
      font-weight: 500;
      margin-bottom: 6px;
    }
    input[type="text"] {
      width: 100%;
      padding: 12px 14px;
      font-size: 16px;
      border: 2px solid #e0e0e0;
      border-radius: 8px;
      outline: none;
      transition: border-color 0.2s;
      -webkit-appearance: none;
    }
    input[type="text"]:focus { border-color: #667eea; }
    button {
      width: 100%;
      padding: 14px;
      font-size: 16px;
      font-weight: 600;
      color: white;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      border: none;
      border-radius: 8px;
      cursor: pointer;
      margin-top: 8px;
    }
    button:active { transform: scale(0.98); }
    .message {
      margin-top: 16px;
      padding: 12px;
      border-radius: 8px;
      font-size: 14px;
      text-align: center;
      background: #f8d7da;
      color: #721c24;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>📶 WiFi 配置</h1>
    <p class="subtitle">请输入要连接的 WiFi 信息</p>
    <form method="post" autocomplete="off">
      <div class="form-group">
        <label for="ssid">网络名称 (SSID)</label>
        <input type="text" id="ssid" name="ssid" value="{{ ssid }}" 
               autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false"
               placeholder="输入 WiFi 名称" required>
      </div>
      <div class="form-group">
        <label for="pass">密码</label>
        <input type="text" id="pass" name="pass" value="{{ password }}"
               autocomplete="off" 
               placeholder="输入 WiFi 密码" required>
      </div>
      <button type="submit">连接 WiFi</button>
    </form>
    {% if error %}<div class="message">{{ error }}</div>{% endif %}
  </div>
</body>
</html>
'''

SUCCESS_HTML = '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <title>配置成功</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .container {
      background: white;
      border-radius: 16px;
      padding: 40px 24px;
      width: 100%;
      max-width: 360px;
      box-shadow: 0 10px 40px rgba(0,0,0,0.2);
      text-align: center;
    }
    .icon {
      font-size: 64px;
      margin-bottom: 16px;
    }
    h1 {
      color: #155724;
      font-size: 24px;
      font-weight: 600;
      margin-bottom: 12px;
    }
    .info {
      color: #666;
      font-size: 14px;
      margin-bottom: 8px;
    }
    .ssid {
      color: #333;
      font-size: 18px;
      font-weight: 600;
      margin-bottom: 24px;
      padding: 12px;
      background: #f0f0f0;
      border-radius: 8px;
    }
    .countdown {
      color: #888;
      font-size: 14px;
    }
    .countdown span {
      font-weight: 600;
      color: #11998e;
      font-size: 18px;
    }
    .hint {
      margin-top: 20px;
      padding: 12px;
      background: #fff3cd;
      border-radius: 8px;
      color: #856404;
      font-size: 13px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">✅</div>
    <h1>配置已保存</h1>
    <p class="info">正在连接到网络:</p>
    <div class="ssid">{{ ssid }}</div>
    <p class="countdown">页面将在 <span id="timer">6</span> 秒后关闭</p>
    <div class="hint">💡 倒计时结束后，设备将尝试连接 WiFi。<br>如果连接失败，配置热点会重新开启。</div>
  </div>
  <script>
    var seconds = 6;
    var timer = document.getElementById('timer');
    setInterval(function() {
      seconds--;
      if (seconds >= 0) timer.textContent = seconds;
    }, 1000);
  </script>
</body>
</html>
'''

def get_last_wifi_ssid():
    """获取最近使用的 WiFi SSID（排除 AP 热点，按最后连接时间排序）
    注意：密码以加密形式存储，无法获取原始密码，因此只返回 SSID
    """
    try:
        # 获取所有 WiFi 连接及其最后使用时间戳
        result = subprocess.run(
            ['nmcli', '-t', '-f', 'NAME,TYPE,TIMESTAMP', 'con', 'show'],
            capture_output=True, text=True
        )
        
        wifi_connections = []
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            parts = line.split(':')
            if len(parts) >= 3 and parts[1] == '802-11-wireless':
                conn_name = parts[0]
                # 排除 AP 热点连接（支持新旧名称）
                if conn_name in (WIFI_AP_CONNECTION_NAME, 'MyHotspot'):
                    continue
                try:
                    timestamp = int(parts[2]) if parts[2] else 0
                except ValueError:
                    timestamp = 0
                wifi_connections.append((conn_name, timestamp))
        
        # 按时间戳降序排序（最近使用的在前）
        wifi_connections.sort(key=lambda x: x[1], reverse=True)
        
        # 获取最近使用的连接的 SSID
        for conn_name, _ in wifi_connections:
            ssid_result = subprocess.run(
                ['nmcli', '-s', '-g', '802-11-wireless.ssid', 'con', 'show', conn_name],
                capture_output=True, text=True
            )
            ssid = ssid_result.stdout.strip()
            if ssid:
                return ssid
    except Exception:
        pass
    return ''

def schedule_wifi_connect(ssid, password):
    """使用独立的 shell 脚本在后台执行 WiFi 连接，不依赖 Python 进程"""
    import os
    
    # 从模板生成脚本（替换运行时变量）
    # 所有占位符在运行时统一替换
    script_content = WIFI_CONNECT_SCRIPT_TEMPLATE \
        .replace('{{ssid}}', ssid) \
        .replace('{{password}}', password) \
        .replace('{{ap_connection_name}}', WIFI_AP_CONNECTION_NAME)
    
    # 写入临时脚本
    script_path = '/tmp/wifi-connect.sh'
    with open(script_path, 'w') as f:
        f.write(script_content)
    os.chmod(script_path, 0o755)
    
    # 使用 nohup 在完全独立的进程中执行（不受父进程影响）
    subprocess.Popen(
        ['nohup', 'bash', script_path],
        stdout=open('/tmp/wifi-connect.log', 'w'),
        stderr=subprocess.STDOUT,
        start_new_session=True,
        close_fds=True
    )

def is_captive_portal_check(path):
    """检查请求是否为操作系统的 captive portal detection"""
    path_lower = path.lower()
    return any(cp_path in path_lower for cp_path in CAPTIVE_PORTAL_PATHS)

@app.route('/', defaults={'path': ''}, methods=['GET', 'POST'])
@app.route('/<path:path>', methods=['GET', 'POST'])
def home(path):
    # 对 captive portal detection 请求返回 302 重定向
    # 这比直接返回 HTML 更可靠地触发设备弹出门户窗口
    if is_captive_portal_check(path):
        # 使用请求的 host 动态构建重定向 URL，避免硬编码 IP
        redirect_url = f'http://{request.host}/'
        response = redirect(redirect_url, code=302)
        response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        return response
    
    ssid = get_last_wifi_ssid()
    
    if request.method == 'POST':
        new_ssid = request.form['ssid']
        new_password = request.form['pass']
        
        # 启动独立的后台进程执行 WiFi 连接
        schedule_wifi_connect(new_ssid, new_password)
        
        # 返回成功页面（带倒计时）
        response = make_response(render_template_string(SUCCESS_HTML, ssid=new_ssid))
        response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
        return response
    
    response = make_response(render_template_string(FORM_HTML, ssid=ssid, password='', error=''))
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
    return response

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
PYEOF

    # 生成运行时配置文件（用不带引号的 heredoc，变量自动展开）
    echo "Creating /opt/wifi-config/config.py..."
    cat > /opt/wifi-config/config.py << CONFIGEOF
# 运行时配置（安装时生成）
# 支持通过环境变量覆盖默认配置
WIFI_AP_CONNECTION_NAME = "$WIFI_AP_CONNECTION_NAME"
CONFIGEOF

    # 创建 pyproject.toml
    echo "Creating /opt/wifi-config/pyproject.toml..."
    cat > /opt/wifi-config/pyproject.toml << 'TOMLEOF'
[project]
name = "rpi-wifi-fallback-web"
version = "1.0.0"
description = "Web interface for RPi WiFi Fallback"
requires-python = ">=3.11"
dependencies = [
    "flask",
]

[[tool.uv.index]]
url = "https://mirrors.aliyun.com/pypi/simple/"
default = true
TOMLEOF

    # 创建虚拟环境并安装依赖
    echo "Creating Python virtual environment and installing dependencies..."
    cd /opt/wifi-config
    uv sync

    # 提取 AP IP 地址（去掉 CIDR 后缀）
    WIFI_AP_IP_ADDR=${WIFI_AP_IP%/*}

    # 创建 NetworkManager dnsmasq 共享配置（强制门户 DNS 劫持）
    # NetworkManager 在 shared 模式下会自动加载此配置
    echo "Creating /etc/NetworkManager/dnsmasq-shared.d/captive-portal.conf..."
    mkdir -p /etc/NetworkManager/dnsmasq-shared.d
    cat > /etc/NetworkManager/dnsmasq-shared.d/captive-portal.conf << DNSEOF
# 强制门户 DNS 劫持
# 将所有域名解析到 AP IP，触发强制门户检测
address=/#/$WIFI_AP_IP_ADDR
DNSEOF

    # 创建 systemd 定时器
    echo "Creating /etc/systemd/system/wifi-fallback.timer..."
    cat > /etc/systemd/system/wifi-fallback.timer << EOF
[Unit]
Description=WiFi Fallback Timer

[Timer]
OnBootSec=30s
OnUnitActiveSec=15s

[Install]
WantedBy=timers.target
EOF

    # 创建回退功能的 systemd 服务
    echo "Creating /etc/systemd/system/wifi-fallback.service..."
    cat > /etc/systemd/system/wifi-fallback.service << EOF
[Unit]
Description=WiFi Fallback Service

[Service]
ExecStart=/usr/local/bin/wifi-fallback.sh
EOF

    # 创建 Web 配置的 systemd 服务
    echo "Creating /etc/systemd/system/wifi-config.service..."
    cat > /etc/systemd/system/wifi-config.service << EOF
[Unit]
Description=WiFi Config Web App
After=network.target

[Service]
ExecStart=/opt/wifi-config/.venv/bin/python /opt/wifi-config/app.py
Restart=always
User=root
# 只杀死主进程，不影响通过 nohup 启动的 wifi-connect.sh 子进程
KillMode=process

[Install]
WantedBy=multi-user.target
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

    echo "WiFi fallback timer is now active and will check connectivity every 30 seconds."
    echo "Installation complete."
}
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
    nmcli con delete "$WIFI_AP_CONNECTION_NAME" 2>/dev/null

    # 移除 nftables 规则（删除整个表）
    nft delete table ip captive_portal 2>/dev/null

    echo "Uninstallation complete. All components removed."
}

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run with sudo privileges."
    exit 1
fi

# 检查操作系统版本（支持 Bookworm 和 Trixie）
is_supported=false
for codename in bookworm trixie; do
    if grep -qi "$codename" /etc/debian_version 2>/dev/null; then
        is_supported=true
        break
    elif grep -qi "VERSION_CODENAME=$codename" /etc/os-release 2>/dev/null; then
        is_supported=true
        break
    fi
done

if [ "$is_supported" = false ]; then
    echo "This script is designed for Debian Bookworm/Trixie (Raspberry Pi OS 64-bit). Aborting."
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