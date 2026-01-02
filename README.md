# RPi-WiFi-Fallback

树莓派 WiFi 回退机制：当 WiFi 连接失败时自动启动 AP 热点，通过 Web 界面配置新的 WiFi 网络。

## 功能特性

- **自动检测**：每 30 秒检查 WiFi 连接状态
- **AP 热点回退**：连接失败时自动启动 WPA2 加密的 AP 热点
- **强制门户**：连接热点后自动弹出配置页面（支持 iOS/Android/Windows）
- **Web 配置界面**：移动端友好的 WiFi 配置页面
- **自动恢复**：配置新 WiFi 后自动关闭热点并尝试连接

## 适用环境

| 要求 | 说明 |
|------|------|
| 硬件 | Raspberry Pi Zero 2 W（或其他带 WiFi 的树莓派） |
| 系统 | Raspberry Pi OS 64-bit（Debian Trixie） |
| 网络管理 | NetworkManager |

## 快速开始

### 一键安装

```bash
# 下载并运行安装脚本
curl -sSL https://raw.githubusercontent.com/CairoLee/RPi-WiFi-Fallback/main/dist/setup.sh | sudo bash -s install
```

### 手动安装

```bash
# 克隆仓库
git clone https://github.com/CairoLee/RPi-WiFi-Fallback.git
cd RPi-WiFi-Fallback

# 运行安装脚本
sudo ./dist/setup.sh install
```

### 卸载

```bash
sudo ./dist/setup.sh uninstall
```

## 工作原理

```
┌─────────────────────────────────────────────────────────────┐
│                   systemd 定时器 (每 30 秒)                   │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  检查网络连接   │
                    │  (默认网关检测) │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
      ┌───────────────┐            ┌───────────────┐
      │   已连接外网   │            │   未连接外网   │
      │   → 无操作    │            │   → 启动 AP   │
      └───────────────┘            └───────┬───────┘
                                           │
                                           ▼
                                  ┌─────────────────┐
                                  │  启动 Web 服务  │
                                  │  (强制门户)     │
                                  └────────┬────────┘
                                           │
                                           ▼
                                  ┌─────────────────┐
                                  │  用户配置 WiFi  │
                                  └────────┬────────┘
                                           │
                                           ▼
                                  ┌─────────────────┐
                                  │  关闭 AP 热点   │
                                  │  连接新 WiFi    │
                                  └─────────────────┘
```

## 配置说明

安装前可编辑 `config.sh` 自定义 AP 热点参数：

```bash
AP_SSID="RPi-WiFi-Setup"                      # AP 热点 SSID
AP_PASSWORD="raspberry2026"                   # AP 热点密码（至少8个字符）
AP_CONNECTION_NAME="RPi-WiFi-Setup-Hotspot"   # NetworkManager 连接名称
AP_IP="192.168.4.1/24"                        # AP IP 地址范围
```

## 开发指南

### 项目结构

```
rpi-wifi-fallback/
├── config.sh           # 用户配置文件
├── build.sh            # 构建脚本
├── src/                # 源文件目录
│   ├── lib/            # Shell 脚本库
│   ├── templates/      # 部署模板
│   └── main.sh         # 脚本入口
├── dist/
│   └── setup.sh        # 构建输出（部署用单文件）
├── scripts/            # 运维脚本
└── docs/               # 文档目录
```

### 开发流程

```bash
# 1. 修改源文件
vim src/templates/app.py

# 2. 构建
./build.sh

# 3. 部署到树莓派
./scripts/deploy.sh
```

### 安装的组件

| 文件 | 位置 | 说明 |
|------|------|------|
| `wifi-fallback.sh` | `/usr/local/bin/` | WiFi 检测脚本 |
| `wifi-fallback.timer` | `/etc/systemd/system/` | 定时触发（每 30 秒） |
| `wifi-fallback.service` | `/etc/systemd/system/` | 回退服务单元 |
| `wifi-config.service` | `/etc/systemd/system/` | Web 配置服务 |
| `app.py` | `/opt/wifi-config/` | Flask Web 应用 |

## 常见问题

### iPhone 无法连接 AP 热点

确保 AP 使用 WPA2 加密，脚本已默认配置。如仍有问题，检查密码是否至少 8 个字符。

### 强制门户页面不弹出

部分浏览器或系统可能需要手动访问 `http://192.168.4.1`。

### 查看运行日志

```bash
# 查看系统日志
journalctl -t wifi-fallback -f

# 查看调试日志
cat /tmp/wifi-fallback.log
```

## 许可证

本项目采用 [MIT License](LICENSE) 开源许可证。

## 贡献

欢迎提交 Issue 和 Pull Request！

- [提交问题](https://github.com/CairoLee/RPi-WiFi-Fallback/issues)
- [贡献代码](https://github.com/CairoLee/RPi-WiFi-Fallback/pulls)

