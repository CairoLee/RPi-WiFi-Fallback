#!/bin/bash

# ============================================
# 部署脚本 - 支持 .env 文件和环境变量配置
# ============================================

set -e  # 遇到错误立即退出

# 获取脚本所在目录的上级目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 加载 .env 文件（如果存在）
ENV_FILE="${PROJECT_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
    # 只加载非注释、非空行，支持带引号的值
    # 注意：|| [[ -n "$key" ]] 确保处理没有尾部换行符的最后一行
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # 跳过空行和注释
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        # 去除值两端的引号
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        # 导出变量（不覆盖已存在的环境变量）
        [ -z "${!key}" ] && export "$key=$value"
    done < "$ENV_FILE"
fi

# ============================================
# 配置区域 - 优先使用环境变量，否则使用默认值
# ============================================

# 远程服务器地址（用户名@主机名）
REMOTE_HOST="${DEPLOY_HOST:-ludashi@LDS-AINAS-PRINTER-01.local}"

# 远程目标目录
REMOTE_DIR="${DEPLOY_DIR:-/home/ludashi/Documents/rpi-wifi-fallback}"

# 排除的文件/文件夹列表
EXCLUDES=(
    ".git"
    ".env"
)

# 先运行构建脚本，生成可部署的单文件
echo "🔨 正在构建..."
"${PROJECT_DIR}/build.sh"
echo ""

echo "🚀 开始部署..."
echo "📍 目标服务器: ${REMOTE_HOST}"
echo "📁 目标目录: ${REMOTE_DIR}"
echo "📂 源目录: ${PROJECT_DIR}"
echo ""

# 构建排除参数
EXCLUDE_ARGS=""
for item in "${EXCLUDES[@]}"; do
    EXCLUDE_ARGS="${EXCLUDE_ARGS} --exclude=${item}"
done

# 使用 rsync 同步项目目录下的所有内容到远程服务器
# -a: 归档模式（保留权限、时间戳等）
# -v: 显示详细信息
# -z: 传输时压缩
# --progress: 显示传输进度
# 确保远程目录存在
echo "📂 创建远程目录..."
ssh "${REMOTE_HOST}" "mkdir -p '${REMOTE_DIR}'"

echo "📤 正在传输文件..."
rsync -avz --progress ${EXCLUDE_ARGS} "${PROJECT_DIR}/" "${REMOTE_HOST}:${REMOTE_DIR}/"

echo ""
echo "✅ 部署完成！"
echo "📍 文件已传输至: ${REMOTE_HOST}:${REMOTE_DIR}"

