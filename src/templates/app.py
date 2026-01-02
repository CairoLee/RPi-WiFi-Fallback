from flask import Flask, request, render_template_string
import subprocess

app = Flask(__name__)

# 配置常量（安装时由 sed 替换）
AP_CONNECTION_NAME = '{{AP_CONNECTION_NAME}}'

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
                if conn_name in ('{{AP_CONNECTION_NAME}}', 'MyHotspot'):
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
    
    # 创建临时脚本文件
    # 注意：如果 SSID 已有连接配置，需要更新密码而不是创建新连接
    script_content = f'''#!/bin/bash
# 使用时间戳命名日志，保留历史记录
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="/tmp/wifi-connect-$TIMESTAMP.log"
echo "=== WiFi 连接脚本开始 ===" > $LOG
date >> $LOG

SSID="{ssid}"
PASSWORD="{password}"
TARGET_AP="{AP_CONNECTION_NAME}"

echo "目标 SSID: $SSID" >> $LOG

# 等待页面响应发送完成
echo "等待 6 秒..." >> $LOG
sleep 6

# 关闭 AP 热点
echo "关闭 AP..." >> $LOG
nmcli con down "$TARGET_AP" 2>> $LOG

# 等待 WiFi 接口释放
echo "等待接口释放..." >> $LOG
sleep 3

# 获取 WiFi 接口
WIFI_IF=$(nmcli -t -f DEVICE,TYPE device | grep ':wifi' | cut -d: -f1 | head -n1)
echo "WiFi 接口: $WIFI_IF" >> $LOG

# 记录当前连接状态
echo "关闭 AP 后的连接状态:" >> $LOG
nmcli con show --active >> $LOG
echo "当前路由:" >> $LOG
ip route >> $LOG

# 检查是否存在同名 SSID 的连接配置
echo "检查现有连接配置..." >> $LOG
EXISTING_CON=$(nmcli -t -f NAME,TYPE con show | grep ":802-11-wireless$" | cut -d: -f1 | while read name; do
    CON_SSID=$(nmcli -g 802-11-wireless.ssid con show "$name" 2>/dev/null)
    if [ "$CON_SSID" = "$SSID" ]; then
        echo "$name"
        break
    fi
done)

if [ -n "$EXISTING_CON" ]; then
    echo "找到现有连接: $EXISTING_CON，更新密码并重新连接..." >> $LOG
    # 先断开（如果已连接）
    nmcli con down "$EXISTING_CON" 2>> $LOG
    # 更新密码
    nmcli con modify "$EXISTING_CON" wifi-sec.psk "$PASSWORD" 2>> $LOG
    # 激活连接
    echo "激活连接..." >> $LOG
    CONNECT_RESULT=$(nmcli con up "$EXISTING_CON" 2>&1)
    echo "连接结果: $CONNECT_RESULT" >> $LOG
else
    echo "未找到现有连接，创建新连接..." >> $LOG
    CONNECT_RESULT=$(nmcli device wifi connect "$SSID" password "$PASSWORD" 2>&1)
    echo "连接结果: $CONNECT_RESULT" >> $LOG
fi

# 等待连接完成（最多 15 秒）
# 不仅检测默认网关，还要确认连接的是目标 SSID
echo "等待连接完成..." >> $LOG
CONNECTED=false
for i in $(seq 1 15); do
    # 检查是否连接到目标 SSID
    CURRENT_SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2)
    echo "第 ${{i}} 秒：当前 SSID=$CURRENT_SSID" >> $LOG
    
    if [ "$CURRENT_SSID" = "$SSID" ] && ip route | grep -q '^default'; then
        echo "第 ${{i}} 秒：已连接到目标 SSID 且检测到默认网关" >> $LOG
        CONNECTED=true
        break
    fi
    sleep 1
done

echo "最终连接状态:" >> $LOG
nmcli con show --active >> $LOG
echo "最终路由:" >> $LOG
ip route >> $LOG

# 根据连接结果决定后续操作
if [ "$CONNECTED" = true ]; then
    echo "连接成功，停止配置服务..." >> $LOG
    systemctl stop wifi-config.service
else
    echo "连接失败，重新启动 AP 和配置服务..." >> $LOG
    nmcli con up "$TARGET_AP" 2>> $LOG
    
    # 重新设置 nftables 强制门户规则
    NFT_TABLE="captive_portal"
    nft delete table ip $NFT_TABLE 2>/dev/null
    nft add table ip $NFT_TABLE
    nft add chain ip $NFT_TABLE prerouting '{{ type nat hook prerouting priority -100 ; }}'
    nft add rule ip $NFT_TABLE prerouting iifname "$WIFI_IF" tcp dport 80 redirect to :80
    echo "nftables 规则已重新设置 (接口: $WIFI_IF)" >> $LOG
    
    systemctl start wifi-config.service
fi

echo "=== 脚本完成 ===" >> $LOG
date >> $LOG

# 删除自身
rm -f "$0"
'''
    
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

@app.route('/', defaults={'path': ''}, methods=['GET', 'POST'])
@app.route('/<path:path>', methods=['GET', 'POST'])
def home(path):
    ssid = get_last_wifi_ssid()
    
    if request.method == 'POST':
        new_ssid = request.form['ssid']
        new_password = request.form['pass']
        
        # 启动独立的后台进程执行 WiFi 连接
        schedule_wifi_connect(new_ssid, new_password)
        
        # 返回成功页面（带倒计时）
        return render_template_string(SUCCESS_HTML, ssid=new_ssid)
    
    return render_template_string(FORM_HTML, ssid=ssid, password='', error='')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)

