#!/bin/bash

# WiFi 回退设置脚本入口
# 此文件调用构建后的 dist/setup.sh
# 开发时请修改 src/ 目录下的源文件，然后运行 scripts/build.sh 重新构建

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_SCRIPT="$SCRIPT_DIR/dist/setup.sh"

# 检查构建产物是否存在
if [ ! -f "$DIST_SCRIPT" ]; then
    echo "错误: 未找到构建产物 $DIST_SCRIPT"
    echo "请先运行 scripts/build.sh 进行构建"
    exit 1
fi

# 执行构建后的脚本，传递所有参数
exec "$DIST_SCRIPT" "$@"
