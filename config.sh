# 配置变量（支持环境变量覆盖，未设置时使用默认值）
: "${WIFI_AP_SSID:=RPi-WiFi-Setup}"                      # AP 热点 SSID
: "${WIFI_AP_PASSWORD:=raspberry2026}"                   # AP 热点密码（至少8个字符）
: "${WIFI_AP_CONNECTION_NAME:=RPi-WiFi-Setup-Hotspot}"   # NetworkManager 连接名称
: "${WIFI_AP_IP:=192.168.4.1/24}"                        # AP IP 地址范围
