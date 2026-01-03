from flask import Flask, request, render_template_string, redirect, make_response
import subprocess

from config import AP_CONNECTION_NAME

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
WIFI_CONNECT_SCRIPT_TEMPLATE = '''# @SCRIPT_TEMPLATE: wifi-connect.sh
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
                if conn_name in (AP_CONNECTION_NAME, 'MyHotspot'):
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
        .replace('{{ap_connection_name}}', AP_CONNECTION_NAME)
    
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

