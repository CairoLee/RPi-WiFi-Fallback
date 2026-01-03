# 默认配置（支持通过环境变量覆盖）
# 环境变量格式：WIFI_AP_SSID, WIFI_AP_PASSWORD, WIFI_AP_CONNECTION_NAME, WIFI_AP_IP
AP_SSID="${WIFI_AP_SSID:-RPi-WiFi-Setup}"                        # AP 热点 SSID
AP_PASSWORD="${WIFI_AP_PASSWORD:-raspberry2026}"                 # AP 热点密码（至少8个字符）
AP_CONNECTION_NAME="${WIFI_AP_CONNECTION_NAME:-RPi-WiFi-Setup-Hotspot}"  # NetworkManager 连接名称
AP_IP="${WIFI_AP_IP:-192.168.4.1/24}"                            # AP IP 地址范围
