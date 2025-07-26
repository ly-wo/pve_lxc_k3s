#!/bin/bash
# 综合监控脚本
# 整合健康检查、系统诊断和性能监控功能

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载日志系统
source "${SCRIPT_DIR}/logging.sh"

COMPONENT="monitoring"
MONITOR_LOG="monitoring.log"

# 配置
MONITOR_INTERVAL="${MONITOR_INTERVAL:-300}"  # 5分钟
ALERT_THRESHOLD_CPU="${ALERT_THRESHOLD_CPU:-80}"
ALERT_THRESHOLD_MEMORY="${ALERT_THRESHOLD_MEMORY:-85}"
ALERT_THRESHOLD_DISK="${ALERT_THRESHOLD_DISK:-90}"
HEALTH_CHECK_ENABLED="${HEALTH_CHECK_ENABLED:-true}"
PERFORMANCE_MONITORING_ENABLED="${PERFORMANCE_MONITORING_ENABLED:-true}"

# 显示帮助信息
show_help() {
    cat <<EOF
综合监控工具

用法: $0 [命令] [选项]

命令:
  start               启动监控守护进程
  stop                停止监控守护进程
  status              显示监控状态
  check               执行一次健康检查
  diagnose            执行系统诊断
  performance         显示性能指标
  alerts              显示告警信息
  dashboard           显示监控仪表板

选项:
  -h, --help          显示帮助信息
  -i, --interval SEC  设置监控间隔（秒）
  -d, --daemon        以守护进程模式运行
  -v, --verbose       详细输出

环境变量:
  MONITOR_INTERVAL              监控间隔（默认: 300秒）
  ALERT_THRESHOLD_CPU           CPU 告警阈值（默认: 80%）
  ALERT_THRESHOLD_MEMORY        内存告警阈值（默认: 85%）
  ALERT_THRESHOLD_DISK          磁盘告警阈值（默认: 90%）
  HEALTH_CHECK_ENABLED          启用健康检查（默认: true）
  PERFORMANCE_MONITORING_ENABLED 启用性能监控（默认: true）

示例:
  $0 start                      # 启动监控
  $0 check                      # 执行健康检查
  $0 performance                # 显示性能指标
  $0 start -i 60               # 每60秒监控一次
EOF
}

# 获取系统指标
get_system_metrics() {
    local metrics="{}"
    
    # CPU 使用率
    local cpu_usage="unknown"
    if command -v top >/dev/null 2>&1; then
        # Linux
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null || echo "unknown")
        # macOS
        if [[ "$cpu_usage" == "unknown" ]]; then
            cpu_usage=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' 2>/dev/null || echo "unknown")
        fi
    fi
    
    # 内存使用率
    local memory_usage="unknown"
    if command -v free >/dev/null 2>&1; then
        memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "unknown")
    fi
    
    # 磁盘使用率
    local disk_usage="unknown"
    disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//' 2>/dev/null || echo "unknown")
    
    # 系统负载
    local load_avg="unknown"
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//' 2>/dev/null || echo "unknown")
    
    # 网络连接数
    local network_connections="unknown"
    if command -v ss >/dev/null 2>&1; then
        network_connections=$(ss -tuln | wc -l 2>/dev/null || echo "unknown")
    elif command -v netstat >/dev/null 2>&1; then
        network_connections=$(netstat -tuln | wc -l 2>/dev/null || echo "unknown")
    fi
    
    # 构建 JSON 格式的指标
    metrics=$(cat <<EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "cpu_usage": "$cpu_usage",
  "memory_usage": "$memory_usage",
  "disk_usage": "$disk_usage",
  "load_average": "$load_avg",
  "network_connections": "$network_connections"
}
EOF
)
    
    echo "$metrics"
}

# 检查告警条件
check_alerts() {
    local metrics="$1"
    local alerts=()
    
    # 提取指标值
    local cpu_usage=$(echo "$metrics" | grep -o '"cpu_usage": "[^"]*"' | cut -d'"' -f4)
    local memory_usage=$(echo "$metrics" | grep -o '"memory_usage": "[^"]*"' | cut -d'"' -f4)
    local disk_usage=$(echo "$metrics" | grep -o '"disk_usage": "[^"]*"' | cut -d'"' -f4)
    
    # CPU 告警
    if [[ "$cpu_usage" != "unknown" && "$cpu_usage" != "" ]]; then
        local cpu_num=$(echo "$cpu_usage" | sed 's/[^0-9.]//g')
        if [[ -n "$cpu_num" ]] && (( $(echo "$cpu_num > $ALERT_THRESHOLD_CPU" | bc -l 2>/dev/null || echo 0) )); then
            alerts+=("CPU 使用率过高: ${cpu_usage}% (阈值: ${ALERT_THRESHOLD_CPU}%)")
        fi
    fi
    
    # 内存告警
    if [[ "$memory_usage" != "unknown" && "$memory_usage" != "" ]]; then
        local mem_num=$(echo "$memory_usage" | sed 's/[^0-9.]//g')
        if [[ -n "$mem_num" ]] && (( $(echo "$mem_num > $ALERT_THRESHOLD_MEMORY" | bc -l 2>/dev/null || echo 0) )); then
            alerts+=("内存使用率过高: ${memory_usage}% (阈值: ${ALERT_THRESHOLD_MEMORY}%)")
        fi
    fi
    
    # 磁盘告警
    if [[ "$disk_usage" != "unknown" && "$disk_usage" != "" ]]; then
        local disk_num=$(echo "$disk_usage" | sed 's/[^0-9.]//g')
        if [[ -n "$disk_num" ]] && (( $(echo "$disk_num > $ALERT_THRESHOLD_DISK" | bc -l 2>/dev/null || echo 0) )); then
            alerts+=("磁盘使用率过高: ${disk_usage}% (阈值: ${ALERT_THRESHOLD_DISK}%)")
        fi
    fi
    
    # 记录告警
    for alert in "${alerts[@]}"; do
        log_warn "$COMPONENT" "$alert" "$metrics" "[\"检查系统资源\", \"清理不必要文件\", \"优化系统配置\"]" "$MONITOR_LOG"
    done
    
    # 返回告警数量
    echo "${#alerts[@]}"
}

# 执行健康检查
run_health_check() {
    log_info "$COMPONENT" "执行健康检查" "{}" "" "" "$MONITOR_LOG"
    
    if [[ "$HEALTH_CHECK_ENABLED" == "true" ]]; then
        if [[ -x "${SCRIPT_DIR}/k3s-health-check.sh" ]]; then
            "${SCRIPT_DIR}/k3s-health-check.sh" || log_warn "$COMPONENT" "健康检查发现问题" "{}" "[\"查看健康检查报告\", \"检查 K3s 状态\"]" "$MONITOR_LOG"
        else
            log_warn "$COMPONENT" "健康检查脚本不可用" "{\"script\": \"${SCRIPT_DIR}/k3s-health-check.sh\"}" "[\"检查脚本权限\", \"重新安装脚本\"]" "$MONITOR_LOG"
        fi
    else
        log_debug "$COMPONENT" "健康检查已禁用" "{}" "" "" "$MONITOR_LOG"
    fi
}

# 收集性能指标
collect_performance_metrics() {
    if [[ "$PERFORMANCE_MONITORING_ENABLED" == "true" ]]; then
        local metrics=$(get_system_metrics)
        log_performance "$COMPONENT" "系统指标收集" "0s" "$metrics"
        
        # 检查告警
        local alert_count=$(check_alerts "$metrics")
        
        if [[ $alert_count -gt 0 ]]; then
            log_warn "$COMPONENT" "发现 $alert_count 个告警" "$metrics" "[\"查看系统状态\", \"检查资源使用\"]" "$MONITOR_LOG"
        fi
        
        echo "$metrics"
    fi
}

# 监控循环
monitoring_loop() {
    log_info "$COMPONENT" "启动监控循环" "{\"interval\": $MONITOR_INTERVAL}" "" "" "$MONITOR_LOG"
    
    while true; do
        local start_time=$(date +%s)
        
        # 收集性能指标
        collect_performance_metrics >/dev/null
        
        # 执行健康检查
        run_health_check
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log_debug "$COMPONENT" "监控周期完成" "{\"duration\": \"${duration}s\", \"interval\": $MONITOR_INTERVAL}" "" "" "$MONITOR_LOG"
        
        # 等待下一个监控周期
        sleep "$MONITOR_INTERVAL"
    done
}

# 启动监控
start_monitoring() {
    local daemon_mode="${1:-false}"
    
    # 检查是否已经在运行
    local pid_file="${PROJECT_ROOT}/logs/monitoring.pid"
    
    if [[ -f "$pid_file" ]]; then
        local old_pid=$(cat "$pid_file")
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "监控已在运行 (PID: $old_pid)"
            return 1
        else
            rm -f "$pid_file"
        fi
    fi
    
    log_info "$COMPONENT" "启动监控服务" "{\"daemon_mode\": $daemon_mode, \"interval\": $MONITOR_INTERVAL}" "" "" "$MONITOR_LOG"
    
    if [[ "$daemon_mode" == "true" ]]; then
        # 守护进程模式
        nohup bash -c "
            echo \$\$ > '$pid_file'
            exec '$0' _monitoring_loop
        " >/dev/null 2>&1 &
        
        local pid=$!
        echo "监控已启动 (PID: $pid)"
        echo "日志文件: ${PROJECT_ROOT}/logs/$MONITOR_LOG"
    else
        # 前台模式
        echo $$ > "$pid_file"
        trap "rm -f '$pid_file'; exit" INT TERM
        monitoring_loop
    fi
}

# 停止监控
stop_monitoring() {
    local pid_file="${PROJECT_ROOT}/logs/monitoring.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$pid_file"
            log_info "$COMPONENT" "监控服务已停止" "{\"pid\": $pid}" "" "" "$MONITOR_LOG"
            echo "监控已停止"
        else
            rm -f "$pid_file"
            echo "监控未运行"
        fi
    else
        echo "监控未运行"
    fi
}

# 显示监控状态
show_status() {
    local pid_file="${PROJECT_ROOT}/logs/monitoring.pid"
    
    echo "=== 监控状态 ==="
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "状态: 运行中 (PID: $pid)"
            echo "启动时间: $(ps -o lstart= -p "$pid" 2>/dev/null || echo "未知")"
        else
            echo "状态: 已停止 (PID 文件存在但进程不存在)"
            rm -f "$pid_file"
        fi
    else
        echo "状态: 未运行"
    fi
    
    echo "配置:"
    echo "  监控间隔: ${MONITOR_INTERVAL}s"
    echo "  CPU 告警阈值: ${ALERT_THRESHOLD_CPU}%"
    echo "  内存告警阈值: ${ALERT_THRESHOLD_MEMORY}%"
    echo "  磁盘告警阈值: ${ALERT_THRESHOLD_DISK}%"
    echo "  健康检查: $HEALTH_CHECK_ENABLED"
    echo "  性能监控: $PERFORMANCE_MONITORING_ENABLED"
    
    echo ""
    echo "最近的指标:"
    collect_performance_metrics | jq . 2>/dev/null || collect_performance_metrics
}

# 显示性能仪表板
show_dashboard() {
    clear
    echo "=== 系统监控仪表板 ==="
    echo "更新时间: $(date)"
    echo ""
    
    # 获取当前指标
    local metrics=$(collect_performance_metrics)
    
    # 解析指标
    local cpu_usage=$(echo "$metrics" | grep -o '"cpu_usage": "[^"]*"' | cut -d'"' -f4)
    local memory_usage=$(echo "$metrics" | grep -o '"memory_usage": "[^"]*"' | cut -d'"' -f4)
    local disk_usage=$(echo "$metrics" | grep -o '"disk_usage": "[^"]*"' | cut -d'"' -f4)
    local load_avg=$(echo "$metrics" | grep -o '"load_average": "[^"]*"' | cut -d'"' -f4)
    
    # 显示指标
    printf "%-15s: %s\n" "CPU 使用率" "${cpu_usage}%"
    printf "%-15s: %s\n" "内存使用率" "${memory_usage}%"
    printf "%-15s: %s\n" "磁盘使用率" "${disk_usage}%"
    printf "%-15s: %s\n" "系统负载" "$load_avg"
    
    echo ""
    
    # K3s 状态
    echo "=== K3s 状态 ==="
    if command -v systemctl >/dev/null 2>&1; then
        local k3s_status=$(systemctl is-active k3s 2>/dev/null || echo "unknown")
        printf "%-15s: %s\n" "K3s 服务" "$k3s_status"
    fi
    
    if [[ -f /etc/rancher/k3s/k3s.yaml ]]; then
        export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
        local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "unknown")
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "unknown")
        printf "%-15s: %s/%s\n" "集群节点" "$ready_nodes" "$node_count"
    fi
    
    echo ""
    echo "按 Ctrl+C 退出"
}

# 主函数
main() {
    local command=""
    local daemon_mode=false
    local interval=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            start|stop|status|check|diagnose|performance|alerts|dashboard)
                command="$1"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--interval)
                interval="$2"
                shift 2
                ;;
            -d|--daemon)
                daemon_mode=true
                shift
                ;;
            -v|--verbose)
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            _monitoring_loop)
                # 内部命令，用于守护进程
                monitoring_loop
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 设置监控间隔
    if [[ -n "$interval" ]]; then
        MONITOR_INTERVAL="$interval"
    fi
    
    # 执行命令
    case "$command" in
        "start")
            start_monitoring "$daemon_mode"
            ;;
        "stop")
            stop_monitoring
            ;;
        "status")
            show_status
            ;;
        "check")
            run_health_check
            ;;
        "diagnose")
            if [[ -x "${SCRIPT_DIR}/system-diagnostics.sh" ]]; then
                "${SCRIPT_DIR}/system-diagnostics.sh"
            else
                echo "系统诊断脚本不可用"
                exit 1
            fi
            ;;
        "performance")
            collect_performance_metrics | jq . 2>/dev/null || collect_performance_metrics
            ;;
        "alerts")
            echo "=== 告警信息 ==="
            local metrics=$(collect_performance_metrics)
            local alert_count=$(check_alerts "$metrics")
            if [[ $alert_count -eq 0 ]]; then
                echo "当前无告警"
            fi
            ;;
        "dashboard")
            while true; do
                show_dashboard
                sleep 5
            done
            ;;
        "")
            echo "请指定命令"
            show_help
            exit 1
            ;;
        *)
            echo "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi