#!/bin/bash

# ============================================
# 配置区域 - 根据需要修改以下变量
# ============================================

# 要从 known_hosts 中移除的主机名（不区分大小写）
TARGET_HOST="lds-ainas-printer-01.local"

# known_hosts 文件路径
KNOWN_HOSTS_FILE="${HOME}/.ssh/known_hosts"

# ============================================
# 脚本主体 - 通常无需修改
# ============================================

set -e  # 遇到错误立即退出

echo "🔍 正在清理 known_hosts 中的 ${TARGET_HOST} 记录..."
echo "📁 文件路径: ${KNOWN_HOSTS_FILE}"
echo ""

# 检查 known_hosts 文件是否存在
if [[ ! -f "${KNOWN_HOSTS_FILE}" ]]; then
    echo "⚠️  文件不存在: ${KNOWN_HOSTS_FILE}"
    exit 0
fi

# 统计匹配的行数（不区分大小写）
MATCH_COUNT=$(grep -ic "${TARGET_HOST}" "${KNOWN_HOSTS_FILE}" 2>/dev/null) || MATCH_COUNT=0

if [[ ${MATCH_COUNT} -eq 0 ]]; then
    echo "✅ 未找到包含 ${TARGET_HOST} 的记录，无需清理"
    exit 0
fi

echo "📋 找到 ${MATCH_COUNT} 条匹配记录："
grep -in "${TARGET_HOST}" "${KNOWN_HOSTS_FILE}" || true
echo ""

# 创建备份
BACKUP_FILE="${KNOWN_HOSTS_FILE}.bak"
cp "${KNOWN_HOSTS_FILE}" "${BACKUP_FILE}"
echo "💾 已创建备份: ${BACKUP_FILE}"

# 删除匹配的行（不区分大小写）
grep -iv "${TARGET_HOST}" "${KNOWN_HOSTS_FILE}" > "${KNOWN_HOSTS_FILE}.tmp" || true
mv "${KNOWN_HOSTS_FILE}.tmp" "${KNOWN_HOSTS_FILE}"

echo ""
echo "✅ 已删除 ${MATCH_COUNT} 条记录"
echo "🎉 清理完成！"

