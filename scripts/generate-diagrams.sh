#!/usr/bin/env bash
#
# 流程图生成脚本
# 使用 Mermaid CLI 将 .mmd 文件转换为 PNG 图片
#
# 依赖: @mermaid-js/mermaid-cli (npm install -g @mermaid-js/mermaid-cli)
#

set -euo pipefail

# 获取脚本所在目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 目录配置
DIAGRAMS_DIR="$PROJECT_ROOT/diagrams"
OUTPUT_DIR="$PROJECT_ROOT/.github/images"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Mermaid CLI 命令（优先使用全局安装，否则使用 npx）
MMDC_CMD=""

# 检查依赖并确定使用哪个命令
check_dependencies() {
    if command -v mmdc &> /dev/null; then
        MMDC_CMD="mmdc"
        log_info "使用全局安装的 mmdc"
    elif command -v npx &> /dev/null; then
        MMDC_CMD="npx -y @mermaid-js/mermaid-cli"
        log_info "使用 npx 运行 @mermaid-js/mermaid-cli"
    else
        log_error "未找到 mmdc 或 npx 命令"
        echo ""
        echo "请安装 Mermaid CLI 或 Node.js:"
        echo "  npm install -g @mermaid-js/mermaid-cli"
        echo ""
        echo "或安装 Node.js 以使用 npx"
        exit 1
    fi
}

# 创建输出目录
setup_output_dir() {
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_info "创建输出目录: $OUTPUT_DIR"
        mkdir -p "$OUTPUT_DIR"
    fi
}

# 生成单个图表
generate_diagram() {
    local input_file="$1"
    local filename
    filename=$(basename "$input_file" .mmd)
    local output_file="$OUTPUT_DIR/${filename}.png"

    log_info "生成图表: $filename.mmd -> $filename.png"

    # 使用 Mermaid CLI 生成 PNG 图片
    # -b: 深色背景
    # -s 2: 缩放比例，提高清晰度
    local bg_color="#1e2228"
    if $MMDC_CMD -i "$input_file" -o "$output_file" -b "$bg_color" -s 2 2>/dev/null; then
        log_info "✓ 已生成: $output_file"
    else
        log_error "✗ 生成失败: $input_file"
        return 1
    fi
}

# 生成所有图表
generate_all() {
    local count=0
    local failed=0

    if [[ ! -d "$DIAGRAMS_DIR" ]]; then
        log_error "图表目录不存在: $DIAGRAMS_DIR"
        exit 1
    fi

    # 查找所有 .mmd 文件
    while IFS= read -r -d '' file; do
        if generate_diagram "$file"; then
            count=$((count + 1))
        else
            failed=$((failed + 1))
        fi
    done < <(find "$DIAGRAMS_DIR" -name "*.mmd" -type f -print0)

    echo ""
    if [[ $count -eq 0 && $failed -eq 0 ]]; then
        log_warn "未找到任何 .mmd 文件"
    else
        log_info "生成完成: 成功 $count 个, 失败 $failed 个"
        log_info "输出目录: $OUTPUT_DIR"
    fi
}

# 显示帮助
show_help() {
    cat << EOF
流程图生成脚本

用法:
    $(basename "$0") [选项]

选项:
    -h, --help      显示此帮助信息
    -c, --check     仅检查依赖，不生成图表

描述:
    将 diagrams/ 目录下的 .mmd 文件转换为 PNG 图片，
    保存到 .github/images/ 目录中。

依赖:
    @mermaid-js/mermaid-cli (npm install -g @mermaid-js/mermaid-cli)

示例:
    $(basename "$0")           # 生成所有图表
    $(basename "$0") --check   # 检查依赖
EOF
}

# 主函数
main() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--check)
            check_dependencies
            log_info "依赖检查通过"
            exit 0
            ;;
        "")
            check_dependencies
            setup_output_dir
            generate_all
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"

