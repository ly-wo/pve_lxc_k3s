#!/bin/bash
# 系统诊断工具
# 收集系统信息、性能指标和故障排查数据

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载日志系统
source "${SCRIPT_DIR}/logging.sh"

COMPONENT="system-diagnostics"
DIAG_LOG="system-diagnostics.log"

# 配置
DIAG_DIR="${PROJECT_ROOT}/logs/diagnostics"
REPORT_FILE="${DIAG_DIR}/diagnostic-report-$(date +%Y%m%d-%H%M%S).txt"

# 创建诊断目录
mkdir -p "$DIAG_DIR"

# 显示帮助信息
show_help() {
    cat <<EOF
系统诊断工具

用法: $0 [选项] [模块]

选项:
  -h, --help          显示帮助信息
  -o, --output FILE   指定输出文件
  -v, --verbose       详细输出
  -q, --quick         快速诊断（跳过耗时检查）

模块:
  system              系统基本信息
  network             网络配置和连通性
  storage             存储和磁盘信息
  k3s                 K3s 相关诊断
  performance         性能指标
  logs                日志分析
  all                 所有模块（默认）

示例:
  $0                  # 运行完整诊断
  $0 system network   # 只检查系统和网络
  $0 -q k3s          # 快速 K3s 诊断
EOF
}

# 收集系统基本信息
collect_system_info() {
    log_info "$COMPONENT" "收集系统基本信息" "{}" "" "" "$DIAG_LOG"
    
    echo "=== 系统基本信息 ===" >> "$REPORT_FILE"
    echo "收集时间: $(date)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 操作系统信息
    echo "--- 操作系统 ---" >> "$REPORT_FILE"
    if [[ -f /etc/os-release ]]; then
        cat /etc/os-release >> "$REPORT_FILE"
    elif [[ -f /etc/alpine-release ]]; then
        echo "Alpine Linux $(cat /etc/alpine-release)" >> "$REPORT_FILE"
    else
        uname -a >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # 内核信息
    echo "--- 内核信息 ---" >> "$REPORT_FILE"
    uname -a >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 硬件信息
    echo "--- 硬件信息 ---" >> "$REPORT_FILE"
    echo "CPU 信息:" >> "$REPORT_FILE"
    if command -v lscpu >/dev/null 2>&1; then
        lscpu >> "$REPORT_FILE" 2>/dev/null || echo "lscpu 不可用" >> "$REPORT_FILE"
    else
        grep -E "processor|model name|cpu cores" /proc/cpuinfo | head -10 >> "$REPORT_FILE" 2>/dev/null || echo "CPU 信息不可用" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    echo "内存信息:" >> "$REPORT_FILE"
    if command -v free >/dev/null 2>&1; then
        free -h >> "$REPORT_FILE"
    else
        # macOS 使用 vm_stat
        vm_stat >> "$REPORT_FILE" 2>/dev/null || echo "内存信息不可用" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # 运行时间和负载
    echo "--- 系统状态 ---" >> "$REPORT_FILE"
    echo "运行时间:" >> "$REPORT_FILE"
    uptime >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 进程信息
    echo "--- 进程信息 ---" >> "$REPORT_FILE"
    echo "进程数量: $(ps aux | wc -l)" >> "$REPORT_FILE"
    echo "CPU 使用率最高的进程:" >> "$REPORT_FILE"
    ps aux --sort=-%cpu | head -10 >> "$REPORT_FILE" 2>/dev/null || ps aux | head -10 >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    log_info "$COMPONENT" "系统信息收集完成" "{}" "" "" "$DIAG_LOG"
}

# 收集网络信息
collect_network_info() {
    log_info "$COMPONENT" "收集网络信息" "{}" "" "" "$DIAG_LOG"
    
    echo "=== 网络信息 ===" >> "$REPORT_FILE"
    
    # 网络接口
    echo "--- 网络接口 ---" >> "$REPORT_FILE"
    if command -v ip >/dev/null 2>&1; then
        ip addr show >> "$REPORT_FILE" 2>/dev/null
    else
        ifconfig >> "$REPORT_FILE" 2>/dev/null || echo "网络接口信息不可用" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # 路由表
    echo "--- 路由表 ---" >> "$REPORT_FILE"
    if command -v ip >/dev/null 2>&1; then
        ip route show >> "$REPORT_FILE" 2>/dev/null
    else
        route -n >> "$REPORT_FILE" 2>/dev/null || netstat -rn >> "$REPORT_FILE" 2>/dev/null || echo "路由信息不可用" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # DNS 配置
    echo "--- DNS 配置 ---" >> "$REPORT_FILE"
    if [[ -f /etc/resolv.conf ]]; then
        cat /etc/resolv.conf >> "$REPORT_FILE"
    else
        echo "DNS 配置文件不存在" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # 网络连通性测试
    echo "--- 网络连通性测试 ---" >> "$REPORT_FILE"
    local test_hosts=("8.8.8.8" "google.com" "github.com")
    
    for host in "${test_hosts[@]}"; do
        echo "测试连接到 $host:" >> "$REPORT_FILE"
        if ping -c 3 -W 5 "$host" >> "$REPORT_FILE" 2>&1; then
            echo "✓ $host 连接正常" >> "$REPORT_FILE"
        else
            echo "✗ $host 连接失败" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
    done
    
    # 端口监听状态
    echo "--- 端口监听状态 ---" >> "$REPORT_FILE"
    if command -v ss >/dev/null 2>&1; then
        ss -tuln >> "$REPORT_FILE" 2>/dev/null
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln >> "$REPORT_FILE" 2>/dev/null
    else
        echo "端口信息不可用" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    log_info "$COMPONENT" "网络信息收集完成" "{}" "" "" "$DIAG_LOG"
}

# 收集存储信息
collect_storage_info() {
    log_info "$COMPONENT" "收集存储信息" "{}" "" "" "$DIAG_LOG"
    
    echo "=== 存储信息 ===" >> "$REPORT_FILE"
    
    # 磁盘使用情况
    echo "--- 磁盘使用情况 ---" >> "$REPORT_FILE"
    df -h >> "$REPORT_FILE" 2>/dev/null || echo "磁盘信息不可用" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # inode 使用情况
    echo "--- inode 使用情况 ---" >> "$REPORT_FILE"
    df -i >> "$REPORT_FILE" 2>/dev/null || echo "inode 信息不可用" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 挂载点
    echo "--- 挂载点 ---" >> "$REPORT_FILE"
    mount >> "$REPORT_FILE" 2>/dev/null || echo "挂载信息不可用" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 磁盘 I/O 统计
    echo "--- 磁盘 I/O 统计 ---" >> "$REPORT_FILE"
    if command -v iostat >/dev/null 2>&1; then
        iostat -x 1 3 >> "$REPORT_FILE" 2>/dev/null || echo "iostat 不可用" >> "$REPORT_FILE"
    elif [[ -f /proc/diskstats ]]; then
        cat /proc/diskstats >> "$REPORT_FILE"
    else
        echo "磁盘 I/O 统计不可用" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # 检查重要目录的空间使用
    echo "--- 重要目录空间使用 ---" >> "$REPORT_FILE"
    local important_dirs=("/var/log" "/tmp" "/var/lib/rancher" "/etc/rancher")
    
    for dir in "${important_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "$dir: $(du -sh "$dir" 2>/dev/null | cut -f1)" >> "$REPORT_FILE"
        fi
    done
    echo "" >> "$REPORT_FILE"
    
    log_info "$COMPONENT" "存储信息收集完成" "{}" "" "" "$DIAG_LOG"
}

# 收集 K3s 诊断信息
collect_k3s_info() {
    log_info "$COMPONENT" "收集 K3s 诊断信息" "{}" "" "" "$DIAG_LOG"
    
    echo "=== K3s 诊断信息 ===" >> "$REPORT_FILE"
    
    # K3s 版本信息
    echo "--- K3s 版本信息 ---" >> "$REPORT_FILE"
    if command -v k3s >/dev/null 2>&1; then
        k3s --version >> "$REPORT_FILE" 2>/dev/null || echo "无法获取 K3s 版本" >> "$REPORT_FILE"
    else
        echo "K3s 命令不可用" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # K3s 服务状态
    echo "--- K3s 服务状态 ---" >> "$REPORT_FILE"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status k3s >> "$REPORT_FILE" 2>&1 || echo "K3s 服务状态不可用" >> "$REPORT_FILE"
    else
        echo "systemctl 不可用" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # K3s 配置文件
    echo "--- K3s 配置文件 ---" >> "$REPORT_FILE"
    local k3s_configs=("/etc/rancher/k3s/k3s.yaml" "/etc/rancher/k3s/config.yaml")
    
    for config in "${k3s_configs[@]}"; do
        if [[ -f "$config" ]]; then
            echo "配置文件: $config" >> "$REPORT_FILE"
            echo "文件大小: $(ls -lh "$config" | awk '{print $5}')" >> "$REPORT_FILE"
            echo "修改时间: $(ls -l "$config" | awk '{print $6, $7, $8}')" >> "$REPORT_FILE"
            echo "权限: $(ls -l "$config" | awk '{print $1}')" >> "$REPORT_FILE"
        else
            echo "配置文件不存在: $config" >> "$REPORT_FILE"
        fi
    done
    echo "" >> "$REPORT_FILE"
    
    # K3s 进程信息
    echo "--- K3s 进程信息 ---" >> "$REPORT_FILE"
    ps aux | grep -E "(k3s|containerd)" | grep -v grep >> "$REPORT_FILE" || echo "未找到 K3s 相关进程" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Kubernetes 集群信息
    echo "--- Kubernetes 集群信息 ---" >> "$REPORT_FILE"
    if [[ -f /etc/rancher/k3s/k3s.yaml ]]; then
        export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
        
        echo "集群信息:" >> "$REPORT_FILE"
        kubectl cluster-info >> "$REPORT_FILE" 2>&1 || echo "无法获取集群信息" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "节点信息:" >> "$REPORT_FILE"
        kubectl get nodes -o wide >> "$REPORT_FILE" 2>&1 || echo "无法获取节点信息" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "系统 Pod 状态:" >> "$REPORT_FILE"
        kubectl get pods -n kube-system >> "$REPORT_FILE" 2>&1 || echo "无法获取系统 Pod 信息" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    else
        echo "K3s 配置文件不存在，跳过 Kubernetes 信息收集" >> "$REPORT_FILE"
    fi
    
    log_info "$COMPONENT" "K3s 信息收集完成" "{}" "" "" "$DIAG_LOG"
}

# 收集性能指标
collect_performance_info() {
    log_info "$COMPONENT" "收集性能指标" "{}" "" "" "$DIAG_LOG"
    
    echo "=== 性能指标 ===" >> "$REPORT_FILE"
    
    # CPU 使用率
    echo "--- CPU 使用率 ---" >> "$REPORT_FILE"
    if command -v top >/dev/null 2>&1; then
        # 运行 top 命令 3 次，每次间隔 1 秒
        for i in {1..3}; do
            echo "采样 $i:" >> "$REPORT_FILE"
            top -b -n1 | head -20 >> "$REPORT_FILE" 2>/dev/null || top -l 1 | head -20 >> "$REPORT_FILE" 2>/dev/null
            echo "" >> "$REPORT_FILE"
            [[ $i -lt 3 ]] && sleep 1
        done
    else
        echo "top 命令不可用" >> "$REPORT_FILE"
    fi
    
    # 内存使用详情
    echo "--- 内存使用详情 ---" >> "$REPORT_FILE"
    if [[ -f /proc/meminfo ]]; then
        cat /proc/meminfo >> "$REPORT_FILE"
    else
        vm_stat >> "$REPORT_FILE" 2>/dev/null || echo "内存详情不可用" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # 系统负载历史
    echo "--- 系统负载 ---" >> "$REPORT_FILE"
    if [[ -f /proc/loadavg ]]; then
        echo "当前负载: $(cat /proc/loadavg)" >> "$REPORT_FILE"
    fi
    uptime >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 网络统计
    echo "--- 网络统计 ---" >> "$REPORT_FILE"
    if [[ -f /proc/net/dev ]]; then
        cat /proc/net/dev >> "$REPORT_FILE"
    else
        netstat -i >> "$REPORT_FILE" 2>/dev/null || echo "网络统计不可用" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    log_info "$COMPONENT" "性能指标收集完成" "{}" "" "" "$DIAG_LOG"
}

# 分析日志文件
analyze_logs() {
    log_info "$COMPONENT" "分析日志文件" "{}" "" "" "$DIAG_LOG"
    
    echo "=== 日志分析 ===" >> "$REPORT_FILE"
    
    # 系统日志分析
    echo "--- 系统日志分析 ---" >> "$REPORT_FILE"
    
    # 检查 journalctl 日志
    if command -v journalctl >/dev/null 2>&1; then
        echo "最近的系统错误:" >> "$REPORT_FILE"
        journalctl --since "1 hour ago" --priority=err --no-pager >> "$REPORT_FILE" 2>/dev/null || echo "无法获取系统日志" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "K3s 服务日志:" >> "$REPORT_FILE"
        journalctl -u k3s --since "1 hour ago" --no-pager >> "$REPORT_FILE" 2>/dev/null || echo "无法获取 K3s 服务日志" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    # 分析项目日志
    echo "--- 项目日志分析 ---" >> "$REPORT_FILE"
    local log_dir="${PROJECT_ROOT}/logs"
    
    if [[ -d "$log_dir" ]]; then
        echo "日志目录: $log_dir" >> "$REPORT_FILE"
        echo "日志文件列表:" >> "$REPORT_FILE"
        ls -la "$log_dir" >> "$REPORT_FILE" 2>/dev/null
        echo "" >> "$REPORT_FILE"
        
        # 统计错误和警告
        echo "错误和警告统计:" >> "$REPORT_FILE"
        find "$log_dir" -name "*.log" -type f | while read -r log_file; do
            local file_name=$(basename "$log_file")
            local error_count=$(grep -c "ERROR" "$log_file" 2>/dev/null || echo 0)
            local warn_count=$(grep -c "WARN" "$log_file" 2>/dev/null || echo 0)
            echo "  $file_name: $error_count 错误, $warn_count 警告" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
        
        # 显示最近的错误
        echo "最近的错误信息:" >> "$REPORT_FILE"
        find "$log_dir" -name "*.log" -type f -exec grep -l "ERROR" {} \; | head -3 | while read -r log_file; do
            echo "--- $(basename "$log_file") ---" >> "$REPORT_FILE"
            grep "ERROR" "$log_file" | tail -5 >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        done
    else
        echo "项目日志目录不存在: $log_dir" >> "$REPORT_FILE"
    fi
    
    log_info "$COMPONENT" "日志分析完成" "{}" "" "" "$DIAG_LOG"
}

# 生成诊断摘要
generate_summary() {
    log_info "$COMPONENT" "生成诊断摘要" "{}" "" "" "$DIAG_LOG"
    
    echo "" >> "$REPORT_FILE"
    echo "=== 诊断摘要 ===" >> "$REPORT_FILE"
    echo "诊断完成时间: $(date)" >> "$REPORT_FILE"
    echo "报告文件: $REPORT_FILE" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 关键指标摘要
    echo "--- 关键指标 ---" >> "$REPORT_FILE"
    
    # 磁盘使用率
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//' 2>/dev/null || echo "unknown")
    echo "根分区使用率: ${disk_usage}%" >> "$REPORT_FILE"
    
    # 内存使用率
    if command -v free >/dev/null 2>&1; then
        local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "unknown")
        echo "内存使用率: ${mem_usage}%" >> "$REPORT_FILE"
    fi
    
    # 系统负载
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//' 2>/dev/null || echo "unknown")
    echo "系统负载: $load_avg" >> "$REPORT_FILE"
    
    echo "" >> "$REPORT_FILE"
    
    # 建议
    echo "--- 建议 ---" >> "$REPORT_FILE"
    
    if [[ "$disk_usage" != "unknown" && $disk_usage -gt 80 ]]; then
        echo "• 磁盘使用率较高，建议清理不必要的文件" >> "$REPORT_FILE"
    fi
    
    if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active --quiet k3s; then
        echo "• K3s 服务未运行，建议检查服务状态" >> "$REPORT_FILE"
    fi
    
    echo "• 定期运行诊断工具以监控系统健康状态" >> "$REPORT_FILE"
    echo "• 查看详细日志以获取更多故障排查信息" >> "$REPORT_FILE"
    
    echo "" >> "$REPORT_FILE"
    echo "诊断报告生成完成。" >> "$REPORT_FILE"
    
    log_info "$COMPONENT" "诊断摘要生成完成" "{\"report_file\": \"$REPORT_FILE\"}" "" "" "$DIAG_LOG"
}

# 主函数
main() {
    local modules=()
    local quick_mode=false
    local verbose=false
    local output_file=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            -q|--quick)
                quick_mode=true
                shift
                ;;
            system|network|storage|k3s|performance|logs|all)
                modules+=("$1")
                shift
                ;;
            *)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 设置输出文件
    if [[ -n "$output_file" ]]; then
        REPORT_FILE="$output_file"
        mkdir -p "$(dirname "$REPORT_FILE")"
    fi
    
    # 如果没有指定模块，默认运行所有模块
    if [[ ${#modules[@]} -eq 0 ]]; then
        modules=("all")
    fi
    
    log_info "$COMPONENT" "开始系统诊断" "{\"modules\": \"${modules[*]}\", \"quick_mode\": $quick_mode, \"output_file\": \"$REPORT_FILE\"}" "" "" "$DIAG_LOG"
    
    # 初始化报告文件
    echo "系统诊断报告" > "$REPORT_FILE"
    echo "===============" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 执行诊断模块
    for module in "${modules[@]}"; do
        case "$module" in
            "system"|"all")
                collect_system_info
                ;;
            "network"|"all")
                collect_network_info
                ;;
            "storage"|"all")
                collect_storage_info
                ;;
            "k3s"|"all")
                collect_k3s_info
                ;;
            "performance"|"all")
                if [[ "$quick_mode" == "false" ]]; then
                    collect_performance_info
                fi
                ;;
            "logs"|"all")
                analyze_logs
                ;;
        esac
        
        # 在 all 模式下，只执行一次所有模块
        if [[ "$module" == "all" ]]; then
            if [[ "$quick_mode" == "false" ]]; then
                collect_performance_info
            fi
            analyze_logs
            break
        fi
    done
    
    # 生成摘要
    generate_summary
    
    echo "诊断完成！报告文件: $REPORT_FILE"
    
    log_info "$COMPONENT" "系统诊断完成" "{\"report_file\": \"$REPORT_FILE\"}" "" "" "$DIAG_LOG"
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi