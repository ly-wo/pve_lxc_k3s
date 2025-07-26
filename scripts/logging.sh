#!/bin/bash
# 统一日志管理系统
# 提供结构化日志输出、错误分类和日志轮转功能

set -euo pipefail

# 日志级别定义（使用函数代替关联数组以兼容旧版本 bash）
get_log_level_num() {
    case "$1" in
        "DEBUG") echo 0 ;;
        "INFO") echo 1 ;;
        "WARN") echo 2 ;;
        "ERROR") echo 3 ;;
        "FATAL") echo 4 ;;
        *) echo 1 ;;
    esac
}

# 默认配置
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_DIR="${LOG_DIR:-logs}"
LOG_MAX_SIZE="${LOG_MAX_SIZE:-10485760}"  # 10MB
LOG_MAX_FILES="${LOG_MAX_FILES:-5}"
LOG_FORMAT="${LOG_FORMAT:-structured}"  # structured 或 simple

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 获取调用者信息
get_caller_info() {
    local frame=${1:-2}
    local caller_script=$(basename "${BASH_SOURCE[$frame]}")
    local caller_line="${BASH_LINENO[$((frame-1))]}"
    local caller_func="${FUNCNAME[$frame]:-main}"
    echo "${caller_script}:${caller_line}:${caller_func}"
}

# 检查日志级别
should_log() {
    local level="$1"
    local current_level_num=$(get_log_level_num "${LOG_LEVEL:-INFO}")
    local message_level_num=$(get_log_level_num "$level")
    [[ $message_level_num -ge $current_level_num ]]
}

# 结构化日志输出
log_structured() {
    local level="$1"
    local component="$2"
    local message="$3"
    local context="${4:-{}}"
    local error_code="${5:-}"
    local suggestions="${6:-[]}"
    
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local caller=$(get_caller_info 3)
    
    # 构建 JSON 格式日志
    local log_entry=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "level": "$level",
  "component": "$component",
  "message": "$message",
  "caller": "$caller",
  "context": $context,
  "error_code": "$error_code",
  "suggestions": $suggestions
}
EOF
)
    
    echo "$log_entry"
}

# 简单格式日志输出
log_simple() {
    local level="$1"
    local component="$2"
    local message="$3"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] [$component] $message"
}

# 通用日志函数
write_log() {
    local level="$1"
    local component="$2"
    local message="$3"
    local context="${4:-{}}"
    local error_code="${5:-}"
    local suggestions="${6:-[]}"
    local log_file="${7:-${component}.log}"
    
    # 检查是否应该记录此级别的日志
    if ! should_log "$level"; then
        return 0
    fi
    
    local log_path="${LOG_DIR}/${log_file}"
    
    # 日志轮转检查
    rotate_log_if_needed "$log_path"
    
    # 根据格式输出日志
    local log_output
    if [[ "$LOG_FORMAT" == "structured" ]]; then
        log_output=$(log_structured "$level" "$component" "$message" "$context" "$error_code" "$suggestions")
    else
        log_output=$(log_simple "$level" "$component" "$message")
    fi
    
    # 写入日志文件和标准输出
    echo "$log_output" | tee -a "$log_path"
}

# 日志轮转
rotate_log_if_needed() {
    local log_file="$1"
    
    if [[ ! -f "$log_file" ]]; then
        return 0
    fi
    
    local file_size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
    
    if [[ $file_size -gt $LOG_MAX_SIZE ]]; then
        rotate_log "$log_file"
    fi
}

# 执行日志轮转
rotate_log() {
    local log_file="$1"
    local base_name=$(basename "$log_file" .log)
    local log_dir=$(dirname "$log_file")
    
    # 移动现有的轮转文件
    for ((i=$((LOG_MAX_FILES-1)); i>=1; i--)); do
        local old_file="${log_dir}/${base_name}.log.$i"
        local new_file="${log_dir}/${base_name}.log.$((i+1))"
        
        if [[ -f "$old_file" ]]; then
            if [[ $i -eq $((LOG_MAX_FILES-1)) ]]; then
                rm -f "$old_file"  # 删除最老的文件
            else
                mv "$old_file" "$new_file"
            fi
        fi
    done
    
    # 轮转当前日志文件
    if [[ -f "$log_file" ]]; then
        mv "$log_file" "${log_dir}/${base_name}.log.1"
    fi
    
    log_info "logging" "日志文件已轮转: $log_file"
}

# 便捷的日志函数
log_debug() {
    local component="$1"
    local message="$2"
    local context="${3:-{}}"
    write_log "DEBUG" "$component" "$message" "$context"
}

log_info() {
    local component="$1"
    local message="$2"
    local context="${3:-{}}"
    write_log "INFO" "$component" "$message" "$context"
}

log_warn() {
    local component="$1"
    local message="$2"
    local context="${3:-{}}"
    local suggestions="${4:-[]}"
    write_log "WARN" "$component" "$message" "$context" "" "$suggestions"
}

log_error() {
    local component="$1"
    local message="$2"
    local context="${3:-{}}"
    local error_code="${4:-}"
    local suggestions="${5:-[]}"
    write_log "ERROR" "$component" "$message" "$context" "$error_code" "$suggestions"
}

log_fatal() {
    local component="$1"
    local message="$2"
    local context="${3:-{}}"
    local error_code="${4:-}"
    local suggestions="${5:-[]}"
    write_log "FATAL" "$component" "$message" "$context" "$error_code" "$suggestions"
    exit 1
}

# 错误分类和处理
classify_error() {
    local error_message="$1"
    local exit_code="${2:-1}"
    
    case "$error_message" in
        *"curl"*|*"wget"*|*"download"*)
            echo "NETWORK_ERROR"
            ;;
        *"permission"*|*"denied"*)
            echo "PERMISSION_ERROR"
            ;;
        *"space"*|*"disk"*)
            echo "STORAGE_ERROR"
            ;;
        *"timeout"*)
            echo "TIMEOUT_ERROR"
            ;;
        *"not found"*|*"404"*)
            echo "NOT_FOUND_ERROR"
            ;;
        *)
            echo "GENERAL_ERROR"
            ;;
    esac
}

# 获取错误建议
get_error_suggestions() {
    local error_type="$1"
    
    case "$error_type" in
        "NETWORK_ERROR")
            echo '["检查网络连接", "验证 DNS 解析", "尝试使用代理或镜像源"]'
            ;;
        "PERMISSION_ERROR")
            echo '["检查文件权限", "确认用户权限", "使用 sudo 或切换用户"]'
            ;;
        "STORAGE_ERROR")
            echo '["检查磁盘空间", "清理临时文件", "检查磁盘权限"]'
            ;;
        "TIMEOUT_ERROR")
            echo '["增加超时时间", "检查网络稳定性", "重试操作"]'
            ;;
        "NOT_FOUND_ERROR")
            echo '["检查文件路径", "验证 URL 有效性", "确认资源存在"]'
            ;;
        *)
            echo '["查看详细错误信息", "检查系统日志", "联系技术支持"]'
            ;;
    esac
}

# 错误处理包装器
handle_error() {
    local error_message="$1"
    local component="$2"
    local exit_code="${3:-1}"
    local context="${4:-{}}"
    
    local error_type=$(classify_error "$error_message" "$exit_code")
    local suggestions=$(get_error_suggestions "$error_type")
    
    log_error "$component" "$error_message" "$context" "$error_type" "$suggestions"
    
    return "$exit_code"
}

# 性能监控日志
log_performance() {
    local component="$1"
    local operation="$2"
    local duration="$3"
    local context="${4:-{}}"
    
    local perf_context=$(echo "$context" | jq --arg dur "$duration" --arg op "$operation" '. + {duration: $dur, operation: $op}' 2>/dev/null || echo "{\"duration\": \"$duration\", \"operation\": \"$operation\"}")
    
    log_info "$component" "性能监控" "$perf_context"
}

# 清理旧日志文件
cleanup_old_logs() {
    local days="${1:-7}"
    
    log_info "logging" "清理 $days 天前的日志文件"
    
    find "$LOG_DIR" -name "*.log.*" -type f -mtime +$days -delete 2>/dev/null || true
    
    log_info "logging" "日志清理完成"
}

# 获取日志统计信息
get_log_stats() {
    local log_file="${1:-}"
    
    if [[ -n "$log_file" && -f "$LOG_DIR/$log_file" ]]; then
        local file_path="$LOG_DIR/$log_file"
    else
        local file_path="$LOG_DIR"
    fi
    
    echo "=== 日志统计信息 ==="
    echo "日志目录: $file_path"
    
    if [[ -f "$file_path" ]]; then
        echo "文件大小: $(du -h "$file_path" | cut -f1)"
        echo "行数: $(wc -l < "$file_path")"
        echo "最后修改: $(stat -f%Sm "$file_path" 2>/dev/null || stat -c%y "$file_path" 2>/dev/null)"
    else
        echo "总大小: $(du -sh "$file_path" 2>/dev/null | cut -f1 || echo "0B")"
        echo "文件数量: $(find "$file_path" -name "*.log*" -type f | wc -l)"
        echo "文件列表:"
        find "$file_path" -name "*.log*" -type f -exec basename {} \; | sort
    fi
}

# 导出函数供其他脚本使用
export -f log_debug log_info log_warn log_error log_fatal
export -f handle_error log_performance cleanup_old_logs get_log_stats
export -f classify_error get_error_suggestions