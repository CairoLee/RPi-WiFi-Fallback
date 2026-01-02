# WiFi Fallback 工程目录结构

本文档描述项目的目录结构和各文件的用途，帮助开发者快速了解项目组织方式。

---

## 目录树

```
rpi-wifi-fallback/
├── config.sh                      # 用户配置文件（AP 热点参数）
├── build.sh                       # 构建脚本：合并源文件生成 dist/setup.sh
├── src/                           # 源文件目录（开发时编辑这里）
│   ├── lib/                       # Shell 脚本库
│   │   ├── utils.sh               # 辅助函数
│   │   ├── install.sh             # 安装逻辑
│   │   └── uninstall.sh           # 卸载逻辑
│   ├── templates/                 # 部署到树莓派的模板文件
│   │   ├── wifi-fallback.sh       # WiFi 回退脚本
│   │   ├── app.py                 # Flask Web 配置应用
│   │   ├── wifi-fallback.timer    # systemd 定时器
│   │   ├── wifi-fallback.service  # systemd 回退服务
│   │   ├── wifi-config.service    # systemd Web 配置服务
│   │   └── captive-portal.conf    # dnsmasq 强制门户配置
│   └── main.sh                    # 脚本入口（权限检查、版本检查、参数解析）
├── scripts/                       # 运维脚本
│   ├── deploy.sh                  # 部署脚本：同步到树莓派
│   ├── test.sh                    # 测试脚本
│   └── clean-known-hosts.sh       # SSH known_hosts 清理工具
├── dist/                          # 构建输出目录
│   └── setup.sh                   # 构建生成的单文件（用于部署）
├── docs/                          # 文档目录
│   ├── PROJECT_STRUCTURE.md       # 本文件：工程结构说明
│   └── TROUBLESHOOTING.md         # 开发踩坑记录
├── setup.sh                       # 入口脚本（调用 dist/setup.sh）
└── CLAUDE.md                      # AI 辅助开发指南
```

---

## 核心概念

### 模块化开发 + 单文件部署

项目采用 **源文件分离，构建时合并** 的模式：

- **开发时**：编辑 `src/` 目录下的模块化文件，便于维护和修改
- **部署时**：通过 `./build.sh` 将所有源文件合并成单个 `dist/setup.sh`
- **优点**：兼顾开发体验和部署便利性（只需拉取一个文件）

### 构建流程

```
config.sh ─────┐
               │
src/lib/*.sh ──┼──▶ ./build.sh ──▶ dist/setup.sh
               │
src/main.sh ───┤
               │
src/templates/* ┘（嵌入到 heredoc 中）
```

---

## 文件详解

### 根目录文件

| 文件 | 说明 |
|------|------|
| `config.sh` | AP 热点的默认配置（SSID、密码、IP 范围等） |
| `build.sh` | 构建脚本：合并源文件生成可部署的单文件 |
| `setup.sh` | 入口脚本：调用 dist/setup.sh |
| `CLAUDE.md` | AI 辅助开发指南 |

### `src/lib/` - Shell 脚本库

| 文件 | 说明 |
|------|------|
| `utils.sh` | 辅助函数：WiFi 接口检测、软件包检查 |
| `install.sh` | 安装逻辑：安装依赖、创建 AP、部署服务 |
| `uninstall.sh` | 卸载逻辑：移除所有组件和配置 |

### `src/templates/` - 部署模板

| 文件 | 部署位置 | 说明 |
|------|----------|------|
| `wifi-fallback.sh` | `/usr/local/bin/` | WiFi 检测与 AP 切换逻辑 |
| `app.py` | `/opt/wifi-config/` | Flask Web 应用（WiFi 配置页面） |
| `wifi-fallback.timer` | `/etc/systemd/system/` | 定时触发 WiFi 检测（每分钟） |
| `wifi-fallback.service` | `/etc/systemd/system/` | WiFi 回退服务单元 |
| `wifi-config.service` | `/etc/systemd/system/` | Web 配置服务单元 |
| `captive-portal.conf` | `/etc/NetworkManager/dnsmasq-shared.d/` | DNS 劫持配置（强制门户） |

### 模板变量占位符

模板中使用 `{{VAR}}` 格式的占位符，构建时替换为实际的 Shell 变量引用：

| 占位符 | 替换为 | 用途 |
|--------|--------|------|
| `{{AP_CONNECTION_NAME}}` | `$AP_CONNECTION_NAME` | AP 连接名称 |
| `{{AP_INTERFACE}}` | `$AP_INTERFACE` | WiFi 接口名 |
| `{{AP_IP_ADDR}}` | `$AP_IP_ADDR` | AP 的 IP 地址 |

### `scripts/` - 运维脚本

| 脚本 | 用途 |
|------|------|
| `deploy.sh` | 使用 rsync 同步到树莓派（自动先构建） |
| `test.sh` | 远程测试脚本 |
| `clean-known-hosts.sh` | 清理 SSH known_hosts 中的旧条目 |

---

## 开发工作流

### 1. 修改源文件

```bash
# 编辑配置
vim config.sh

# 编辑 Flask 应用
vim src/templates/app.py

# 编辑安装逻辑
vim src/lib/install.sh
```

### 2. 构建

```bash
./build.sh
```

### 3. 部署

```bash
./scripts/deploy.sh
```

部署脚本会自动先运行构建，然后使用 rsync 同步到树莓派。

### 4. 在树莓派上安装

```bash
cd ~/rpi-wifi-fallback
sudo ./dist/setup.sh            # 安装
sudo ./dist/setup.sh --uninstall # 卸载
```

---

## 注意事项

### 模板中的变量转义

`src/templates/wifi-fallback.sh` 中的 Shell 变量需要使用 `\$` 转义，因为它们会被嵌入到 heredoc 中：

```bash
# 正确：使用 \$ 转义
log() {
    logger -t wifi-fallback "\$1"    # 在目标脚本中变成 $1
}
```

### 构建标记语法

源文件中使用特殊注释标记：

- `# @INCLUDE: path` - 嵌入指定的 lib 文件
- `# @TEMPLATE: filename` - 嵌入指定的模板文件（在 heredoc 内部使用）

---

## 相关文档

- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - 开发踩坑记录
