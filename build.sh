#!/bin/bash

# WiFi Fallback 构建脚本
# 将模块化的源文件合并成单个可部署的 setup.sh 文件

set -e

# 获取项目根目录（脚本所在目录）
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRC_DIR="$PROJECT_ROOT/src"
DIST_DIR="$PROJECT_ROOT/dist"
OUTPUT_FILE="$DIST_DIR/setup.sh"

echo "=== WiFi Fallback 构建脚本 ==="
echo "项目根目录: $PROJECT_ROOT"
echo "源文件目录: $SRC_DIR"
echo "输出文件: $OUTPUT_FILE"
echo ""

# 确保输出目录存在
mkdir -p "$DIST_DIR"

# 读取模板文件内容的函数
# 参数1: 模板文件名
# 参数2: heredoc 结束标记类型 (normal/quoted)
# 参数3: 是否需要变量替换 (yes/no)
get_template_content() {
    local template_name="$1"
    local template_file="$SRC_DIR/templates/$template_name"
    
    if [ ! -f "$template_file" ]; then
        echo "错误: 找不到模板文件 $template_file" >&2
        exit 1
    fi
    
    cat "$template_file"
}

# 处理 wifi-fallback.sh 模板（需要变量替换）
# 将 {{VAR}} 转换为 $VAR 或 'value' 形式
process_wifi_fallback_template() {
    local content
    content=$(get_template_content "wifi-fallback.sh")
    
    # 替换占位符为 shell 变量引用
    # {{WIFI_AP_CONNECTION_NAME}} -> $WIFI_AP_CONNECTION_NAME (在单引号内)
    # {{AP_INTERFACE}} -> $AP_INTERFACE (内部检测变量，保持不变)
    echo "$content" | \
        sed "s/{{WIFI_AP_CONNECTION_NAME}}/\$WIFI_AP_CONNECTION_NAME/g" | \
        sed "s/{{AP_INTERFACE}}/\$AP_INTERFACE/g"
}

# 处理 captive-portal.conf 模板（需要变量替换）
process_captive_portal_template() {
    local content
    content=$(get_template_content "captive-portal.conf")
    
    # {{WIFI_AP_IP_ADDR}} -> $WIFI_AP_IP_ADDR
    echo "$content" | sed "s/{{WIFI_AP_IP_ADDR}}/\$WIFI_AP_IP_ADDR/g"
}

# 处理 app.py 模板（嵌入 wifi-connect.sh 脚本模板）
process_app_py_template() {
    local app_content
    app_content=$(get_template_content "app.py")
    
    # 读取 wifi-connect.sh 模板内容
    local script_content
    script_content=$(get_template_content "wifi-connect.sh")
    
    # 将包含 @SCRIPT_TEMPLATE 标记的行替换为实际脚本内容
    # 格式: WIFI_CONNECT_SCRIPT_TEMPLATE = '''# @SCRIPT_TEMPLATE: wifi-connect.sh
    # 需要保留行首的变量定义部分
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" == *"# @SCRIPT_TEMPLATE: wifi-connect.sh"* ]]; then
            # 提取标记之前的部分（如 "WIFI_CONNECT_SCRIPT_TEMPLATE = '''"）
            local prefix="${line%%# @SCRIPT_TEMPLATE:*}"
            # 输出前缀 + 脚本内容
            echo "${prefix}${script_content}"
        else
            echo "$line"
        fi
    done <<< "$app_content"
}

# 处理 @INCLUDE 指令
# 将 lib 文件内容嵌入到主脚本
process_includes() {
    local input="$1"
    local output=""
    local line
    
    while IFS= read -r line || [ -n "$line" ]; do
        if echo "$line" | grep -qE "^#[[:space:]]*@INCLUDE:"; then
            local include_file
            include_file=$(echo "$line" | sed -E "s/^#[[:space:]]*@INCLUDE:[[:space:]]*//")
            # config.sh 在根目录，其他文件在 src/lib 目录
            local include_path
            if [ "$include_file" = "config.sh" ]; then
                include_path="$PROJECT_ROOT/$include_file"
            else
                include_path="$SRC_DIR/$include_file"
            fi
            
            if [ ! -f "$include_path" ]; then
                echo "错误: 找不到包含文件 $include_path" >&2
                exit 1
            fi
            
            echo "  嵌入: $include_file" >&2
            output+=$(cat "$include_path")
            output+=$'\n'
        else
            output+="$line"$'\n'
        fi
    done <<< "$input"
    
    echo "$output"
}

# 处理 @TEMPLATE 指令
# 将模板内容嵌入到 heredoc 中
process_templates() {
    local input="$1"
    local in_heredoc=false
    local heredoc_marker=""
    local current_template=""
    local output=""
    local line
    
    while IFS= read -r line || [ -n "$line" ]; do
        # 检测 heredoc 开始 (匹配 cat > file << EOF 或 cat > file << 'EOF' 格式)
        if echo "$line" | grep -qE "cat[[:space:]]*>[[:space:]]*.+<<[[:space:]]*'?[A-Z]+"; then
            # 提取 heredoc 结束标记
            heredoc_marker=$(echo "$line" | sed -E "s/.*<<[[:space:]]*'?([A-Z]+)'?.*/\1/")
            in_heredoc=true
            output+="$line"$'\n'
            continue
        fi
        
        # 在 heredoc 内部
        if [ "$in_heredoc" = true ]; then
            # 检测模板标记
            if echo "$line" | grep -qE "^#[[:space:]]*@TEMPLATE:"; then
                current_template=$(echo "$line" | sed -E "s/^#[[:space:]]*@TEMPLATE:[[:space:]]*//")
                echo "  嵌入模板: $current_template" >&2
                
                # 根据模板类型进行处理
                case "$current_template" in
                    "wifi-fallback.sh")
                        output+=$(process_wifi_fallback_template)
                        output+=$'\n'
                        ;;
                    "captive-portal.conf")
                        output+=$(process_captive_portal_template)
                        output+=$'\n'
                        ;;
                    "app.py")
                        output+=$(process_app_py_template)
                        output+=$'\n'
                        ;;
                    *)
                        output+=$(get_template_content "$current_template")
                        output+=$'\n'
                        ;;
                esac
                continue
            fi
            
            # 检测 heredoc 结束
            if [ "$line" = "$heredoc_marker" ]; then
                in_heredoc=false
                heredoc_marker=""
                current_template=""
            fi
        fi
        
        output+="$line"$'\n'
    done <<< "$input"
    
    echo "$output"
}

# 主构建流程
echo "步骤 1: 读取主脚本..."
main_content=$(cat "$SRC_DIR/main.sh")

echo "步骤 2: 处理 @INCLUDE 指令..."
main_content=$(process_includes "$main_content")

echo "步骤 3: 处理 @TEMPLATE 指令..."
main_content=$(process_templates "$main_content")

echo "步骤 4: 写入输出文件..."
# 使用 printf 避免额外换行符，并去除开头的空行
printf '%s' "$main_content" | sed '/./,$!d' > "$OUTPUT_FILE"

# 添加执行权限
chmod +x "$OUTPUT_FILE"

echo ""
echo "=== 构建完成 ==="
echo "输出文件: $OUTPUT_FILE"
echo "文件大小: $(wc -c < "$OUTPUT_FILE") 字节"
echo "代码行数: $(wc -l < "$OUTPUT_FILE") 行"

