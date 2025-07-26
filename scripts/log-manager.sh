#!/bin/bash
# 日志管理工具
# 提供日志查看、分析、清理和轮转功能

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_ROOT}/logs"

# 加载日志库
source "${SCRIPT_DIR}/logging.sh"

# 显示帮助信息
show_help() {
    cat <<EOF
日志管理工具

用法: $0 [命令] [选项]

命令:
  list                    列出所有日志文件
  show <file>            显示日志文件内容
  tail <file> [lines]    实时查看日志文件末尾
  stats [file]           显示日志统计信息
  rotate <file>          手动轮转日志文件
  cleanup [days]         清理指定天数前的日志文件
  analyze <file>         分析日志文件中的错误和警告
  search <pattern> [file] 在日志中搜索指定模式
  export <file> <format> 导出日志文件为指定格式

选项:
  -h, --help             显示此帮助信息
  -v, --verbose          详细输出
  -q, --quiet            静默模式

示例:
  $0 list                           # 列出所有日志文件
  $0 show build-template.log        # 显示构建日志
  $0 tail k3s-installer.log 50      # 实时查看最后50行
  $0 analyze build-template.log     # 分析构建日志中的问题
  $0 cleanup 7                      # 清理7天前的日志
  $0 search "ERROR" build-template.log  # 搜索错误信息
EOF
}

# 列出所有日志文件
list_logs() {
    echo "=== 日志文件列表 ==="
    if [[ ! -d "$LOG_DIR" ]]; then
        echo "日志目录不存在: $LOG_DIR"
        return 1
    fi
    
    find "$LOG_DIR" -name "*.log*" -type f | while read -r log_file; do
        local file_name=$(basename "$log_file")
        local file_size=$(du -h "$log_file" | cut -f1)
        local mod_time=$(stat -f%Sm "$log_file" 2>/dev/null || stat -c%y "$log_file" 2>/dev/null | cut -d' ' -f1)
        printf "%-30s %8s %s\n" "$file_name" "$file_size" "$mod_time"
    done | sort
}

# 显示日志文件内容
show_log() {
    local log_file="$1"
    local full_path="$LOG_DIR/$log_file"
    
    if [[ ! -f "$full_path" ]]; then
        echo "日志文件不存在: $full_path"
        return 1
    fi
    
    echo "=== $log_file ==="
    cat "$full_path"
}

# 实时查看日志文件
tail_log() {
    local log_file="$1"
    local lines="${2:-20}"
    local full_path="$LOG_DIR/$log_file"
    
    if [[ ! -f "$full_path" ]]; then
        echo "日志文件不存在: $full_path"
        return 1
    fi
    
    echo "=== 实时查看 $log_file (最后 $lines 行) ==="
    tail -n "$lines" -f "$full_path"
}

# 分析日志文件
analyze_log() {
    local log_file="$1"
    local full_path="$LOG_DIR/$log_file"
    
    if [[ ! -f "$full_path" ]]; then
        echo "日志文件不存在: $full_path"
        return 1
    fi
    
    echo "=== 日志分析: $log_file ==="
    
    # 统计各级别日志数量
    echo "日志级别统计:"
    for level in DEBUG INFO WARN ERROR FATAL; do
        local count=$(grep -c "\[$level\]" "$full_path" 2>/dev/null || echo 0)
        printf "  %-6s: %d\n" "$level" "$count"
    done
    
    echo ""
    
    # 显示最近的错误和警告
    echo "最近的错误和警告:"
    grep -E "\[(ERROR|FATAL|WARN)\]" "$full_path" | tail -10 || echo "  无错误或警告"
    
    echo ""
    
    # 错误分类统计
    echo "错误分类统计:"
    if grep -q "ERROR" "$full_path"; then
        grep "ERROR" "$full_path" | while read -r line; do
            if [[ "$line" =~ error_code.*:.*\"([^\"]+)\" ]]; then
                echo "${BASH_REMATCH[1]}"
            fi
        done | sort | uniq -c | sort -nr | head -5
    else
        echo "  无错误记录"
    fi
    
    echo ""
    
    # 性能统计
    echo "性能统计:"
    if grep -q "duration" "$full_path"; then
        grep "duration" "$full_path" | tail -5 | while read -r line; do
            if [[ "$line" =~ \"operation\":\"([^\"]+)\".*\"duration\":\"([^\"]+)\" ]]; then
                printf "  %-20s: %s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
            fi
        done
    else
        echo "  无性能数据"
    fi
}

# 在日志中搜索
search_log() {
    local pattern="$1"
    local log_file="${2:-}"
    
    if [[ -n "$log_file" ]]; then
        local full_path="$LOG_DIR/$log_file"
        if [[ ! -f "$full_path" ]]; then
            echo "日志文件不存在: $full_path"
            return 1
        fi
        echo "=== 在 $log_file 中搜索: $pattern ==="
        grep -n --color=always "$pattern" "$full_path" || echo "未找到匹配项"
    else
        echo "=== 在所有日志文件中搜索: $pattern ==="
        find "$LOG_DIR" -name "*.log" -type f -exec grep -l "$pattern" {} \; | while read -r file; do
            echo "--- $(basename "$file") ---"
            grep -n --color=always "$pattern" "$file" | head -5
            echo ""
        done
    fi
}

# 导出日志文件
export_log() {
    local log_file="$1"
    local format="${2:-txt}"
    local full_path="$LOG_DIR/$log_file"
    
    if [[ ! -f "$full_path" ]]; then
        echo "日志文件不存在: $full_path"
        return 1
    fi
    
    local base_name=$(basename "$log_file" .log)
    local output_file="${LOG_DIR}/${base_name}_export.${format}"
    
    case "$format" in
        "csv")
            echo "timestamp,level,component,message" > "$output_file"
            grep -E "\[.*\]" "$full_path" | while IFS= read -r line; do
                if [[ "$line" =~ ^\[([^\]]+)\]\ \[([^\]]+)\]\ \[([^\]]+)\]\ (.*)$ ]]; then
                    echo "\"${BASH_REMATCH[1]}\",\"${BASH_REMATCH[2]}\",\"${BASH_REMATCH[3]}\",\"${BASH_REMATCH[4]}\"" >> "$output_file"
                fi
            done
            ;;
        "json")
            echo "[" > "$output_file"
            local first=true
            grep -E "^\{" "$full_path" | while IFS= read -r line; do
                if [[ "$first" == "true" ]]; then
                    echo "  $line" >> "$output_file"
                    first=false
                else
                    echo "  ,$line" >> "$output_file"
                fi
            done
            echo "]" >> "$output_file"
            ;;
        "txt"|*)
            cp "$full_path" "$output_file"
            ;;
    esac
    
    echo "日志已导出到: $output_file"
}

# 生成日志报告
generate_report() {
    local output_file="${LOG_DIR}/log_report_$(date +%Y%m%d_%H%M%S).html"
    
    cat > "$output_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>日志分析报告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 10px; border-radius: 5px; }
        .section { margin: 20px 0; }
        .error { color: red; }
        .warn { color: orange; }
        .info { color: blue; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>日志分析报告</h1>
        <p>生成时间: $(date)</p>
        <p>日志目录: $LOG_DIR</p>
    </div>
    
    <div class="section">
        <h2>日志文件概览</h2>
        <table>
            <tr><th>文件名</th><th>大小</th><th>修改时间</th><th>行数</th></tr>
EOF
    
    find "$LOG_DIR" -name "*.log" -type f | while read -r log_file; do
        local file_name=$(basename "$log_file")
        local file_size=$(du -h "$log_file" | cut -f1)
        local mod_time=$(stat -f%Sm "$log_file" 2>/dev/null || stat -c%y "$log_file" 2>/dev/null | cut -d' ' -f1)
        local line_count=$(wc -l < "$log_file")
        echo "            <tr><td>$file_name</td><td>$file_size</td><td>$mod_time</td><td>$line_count</td></tr>" >> "$output_file"
    done
    
    cat >> "$output_file" <<EOF
        </table>
    </div>
    
    <div class="section">
        <h2>错误统计</h2>
        <table>
            <tr><th>日志文件</th><th>错误数</th><th>警告数</th></tr>
EOF
    
    find "$LOG_DIR" -name "*.log" -type f | while read -r log_file; do
        local file_name=$(basename "$log_file")
        local error_count=$(grep -c "\[ERROR\]" "$log_file" 2>/dev/null || echo 0)
        local warn_count=$(grep -c "\[WARN\]" "$log_file" 2>/dev/null || echo 0)
        echo "            <tr><td>$file_name</td><td class=\"error\">$error_count</td><td class=\"warn\">$warn_count</td></tr>" >> "$output_file"
    done
    
    cat >> "$output_file" <<EOF
        </table>
    </div>
</body>
</html>
EOF
    
    echo "日志报告已生成: $output_file"
}

# 主函数
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi
    
    case "$1" in
        "list")
            list_logs
            ;;
        "show")
            if [[ $# -lt 2 ]]; then
                echo "错误: 请指定日志文件名"
                exit 1
            fi
            show_log "$2"
            ;;
        "tail")
            if [[ $# -lt 2 ]]; then
                echo "错误: 请指定日志文件名"
                exit 1
            fi
            tail_log "$2" "${3:-20}"
            ;;
        "stats")
            get_log_stats "$2"
            ;;
        "rotate")
            if [[ $# -lt 2 ]]; then
                echo "错误: 请指定日志文件名"
                exit 1
            fi
            rotate_log "$LOG_DIR/$2"
            ;;
        "cleanup")
            cleanup_old_logs "${2:-7}"
            ;;
        "analyze")
            if [[ $# -lt 2 ]]; then
                echo "错误: 请指定日志文件名"
                exit 1
            fi
            analyze_log "$2"
            ;;
        "search")
            if [[ $# -lt 2 ]]; then
                echo "错误: 请指定搜索模式"
                exit 1
            fi
            search_log "$2" "${3:-}"
            ;;
        "export")
            if [[ $# -lt 2 ]]; then
                echo "错误: 请指定日志文件名"
                exit 1
            fi
            export_log "$2" "${3:-txt}"
            ;;
        "report")
            generate_report
            ;;
        "-h"|"--help")
            show_help
            ;;
        *)
            echo "错误: 未知命令 '$1'"
            show_help
            exit 1
            ;;
    esac
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi