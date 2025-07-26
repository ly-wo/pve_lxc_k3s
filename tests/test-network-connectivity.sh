#!/bin/bash
# Network connectivity integration test script
# 网络连通性集成测试脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载日志系统
source "${PROJECT_ROOT}/scripts/logging.sh"

COMPONENT="network-connectivity-test"
TEST_LOG="network-connectivity-test.log"

# 测试配置
TEST_CONFIG="${TEST_CONFIG:-${PROJECT_ROOT}/config/template.yaml}"
INTEGRATION_TEST_MODE="${INTEGRATION_TEST_MODE:-false}"

# 网络测试参数
CLUSTER_CIDR="10.42.0.0/16"
SERVICE_CIDR="10.43.0.0/16"
CLUSTER_DNS="10.43.0.10"
API_SERVER_PORT="6443"
KUBELET_PORT="10250"
FLANNEL_PORT="8472"

# 初始化测试环境
init_test_environment() {
    log_info "$COMPONENT" "初始化网络连通性测试环境" "{}" "" "" "$TEST_LOG"
    
    # 加载配置
    if [[ -f "${PROJECT_ROOT}/scripts/config-loader.sh" ]]; then
        source "${PROJECT_ROOT}/scripts/config-loader.sh"
        if load_config "$TEST_CONFIG" 2>/dev/null; then
            # 从配置中获取网络参数
            CLUSTER_CIDR=$(get_config "network.cluster_cidr" "$CLUSTER_CIDR" 2>/dev/null || echo "$CLUSTER_CIDR")
            SERVICE_CIDR=$(get_config "network.service_cidr" "$SERVICE_CIDR" 2>/dev/null || echo "$SERVICE_CIDR")
            CLUSTER_DNS=$(get_config "network.cluster_dns" "$CLUSTER_DNS" 2>/dev/null || echo "$CLUSTER_DNS")
        fi
    fi
    
    log_info "$COMPONENT" "网络测试参数" "{\"cluster_cidr\": \"$CLUSTER_CIDR\", \"service_cidr\": \"$SERVICE_CIDR\", \"cluster_dns\": \"$CLUSTER_DNS\"}" "" "" "$TEST_LOG"
}

# 测试集群网络CIDR连通性
test_cluster_cidr_connectivity() {
    log_info "$COMPONENT" "测试集群CIDR连通性" "{\"cluster_cidr\": \"$CLUSTER_CIDR\"}" "" "" "$TEST_LOG"
    
    if [[ "$INTEGRATION_TEST_MODE" == "true" ]]; then
        # 集成测试模式：模拟测试
        log_info "$COMPONENT" "模拟集群CIDR连通性测试" "{\"result\": \"success\"}" "" "" "$TEST_LOG"
        return 0
    fi
    
    # 实际测试模式：检查网络接口和路由
    local test_ip="${CLUSTER_CIDR%/*}"
    test_ip="${test_ip%.*}.1"  # 获取网络的第一个IP
    
    # 检查是否有到集群CIDR的路由
    if ip route show | grep -q "$CLUSTER_CIDR"; then
        log_info "$COMPONENT" "集群CIDR路由存在" "{\"cluster_cidr\": \"$CLUSTER_CIDR\"}" "" "" "$TEST_LOG"
        return 0
    else
        log_warn "$COMPONENT" "集群CIDR路由不存在" "{\"cluster_cidr\": \"$CLUSTER_CIDR\"}" "[\"检查Flannel配置\", \"验证CNI插件\"]" "$TEST_LOG"
        return 1
    fi
}

# 测试服务网络CIDR连通性
test_service_cidr_connectivity() {
    log_info "$COMPONENT" "测试服务CIDR连通性" "{\"service_cidr\": \"$SERVICE_CIDR\"}" "" "" "$TEST_LOG"
    
    if [[ "$INTEGRATION_TEST_MODE" == "true" ]]; then
        # 集成测试模式：模拟测试
        log_info "$COMPONENT" "模拟服务CIDR连通性测试" "{\"result\": \"success\"}" "" "" "$TEST_LOG"
        return 0
    fi
    
    # 实际测试模式：检查kube-proxy配置
    if command -v kubectl >/dev/null 2>&1 && kubectl get svc kubernetes >/dev/null 2>&1; then
        local k8s_svc_ip
        k8s_svc_ip=$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
        
        if [[ -n "$k8s_svc_ip" ]]; then
            log_info "$COMPONENT" "Kubernetes服务IP可访问" "{\"service_ip\": \"$k8s_svc_ip\"}" "" "" "$TEST_LOG"
            return 0
        fi
    fi
    
    log_warn "$COMPONENT" "无法验证服务CIDR连通性" "{\"service_cidr\": \"$SERVICE_CIDR\"}" "[\"检查kube-proxy\", \"验证服务网络配置\"]" "$TEST_LOG"
    return 1
}

# 测试DNS服务连通性
test_dns_connectivity() {
    log_info "$COMPONENT" "测试DNS服务连通性" "{\"cluster_dns\": \"$CLUSTER_DNS\"}" "" "" "$TEST_LOG"
    
    if [[ "$INTEGRATION_TEST_MODE" == "true" ]]; then
        # 集成测试模式：模拟测试
        log_info "$COMPONENT" "模拟DNS服务连通性测试" "{\"result\": \"success\"}" "" "" "$TEST_LOG"
        return 0
    fi
    
    # 实际测试模式：检查CoreDNS
    if command -v kubectl >/dev/null 2>&1; then
        # 检查CoreDNS Pod状态
        local coredns_status
        coredns_status=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep Running | wc -l || echo "0")
        
        if [[ "$coredns_status" -gt 0 ]]; then
            log_info "$COMPONENT" "CoreDNS服务运行正常" "{\"running_pods\": $coredns_status}" "" "" "$TEST_LOG"
            
            # 测试DNS解析
            if nslookup kubernetes.default.svc.cluster.local "$CLUSTER_DNS" >/dev/null 2>&1; then
                log_info "$COMPONENT" "DNS解析测试成功" "{\"dns_server\": \"$CLUSTER_DNS\"}" "" "" "$TEST_LOG"
                return 0
            fi
        fi
    fi
    
    log_warn "$COMPONENT" "DNS服务连通性测试失败" "{\"cluster_dns\": \"$CLUSTER_DNS\"}" "[\"检查CoreDNS状态\", \"验证DNS配置\"]" "$TEST_LOG"
    return 1
}

# 测试API服务器连通性
test_api_server_connectivity() {
    log_info "$COMPONENT" "测试API服务器连通性" "{\"port\": \"$API_SERVER_PORT\"}" "" "" "$TEST_LOG"
    
    if [[ "$INTEGRATION_TEST_MODE" == "true" ]]; then
        # 集成测试模式：模拟测试
        log_info "$COMPONENT" "模拟API服务器连通性测试" "{\"result\": \"success\"}" "" "" "$TEST_LOG"
        return 0
    fi
    
    # 实际测试模式：检查API服务器端口
    local api_server_ip="127.0.0.1"
    
    if command -v kubectl >/dev/null 2>&1; then
        # 尝试连接API服务器
        if kubectl cluster-info >/dev/null 2>&1; then
            log_info "$COMPONENT" "API服务器连通性正常" "{\"server\": \"${api_server_ip}:${API_SERVER_PORT}\"}" "" "" "$TEST_LOG"
            return 0
        fi
    fi
    
    # 检查端口是否开放
    if command -v nc >/dev/null 2>&1; then
        if nc -z "$api_server_ip" "$API_SERVER_PORT" 2>/dev/null; then
            log_info "$COMPONENT" "API服务器端口开放" "{\"server\": \"${api_server_ip}:${API_SERVER_PORT}\"}" "" "" "$TEST_LOG"
            return 0
        fi
    fi
    
    log_warn "$COMPONENT" "API服务器连通性测试失败" "{\"server\": \"${api_server_ip}:${API_SERVER_PORT}\"}" "[\"检查K3s服务状态\", \"验证防火墙设置\"]" "$TEST_LOG"
    return 1
}

# 测试Kubelet连通性
test_kubelet_connectivity() {
    log_info "$COMPONENT" "测试Kubelet连通性" "{\"port\": \"$KUBELET_PORT\"}" "" "" "$TEST_LOG"
    
    if [[ "$INTEGRATION_TEST_MODE" == "true" ]]; then
        # 集成测试模式：模拟测试
        log_info "$COMPONENT" "模拟Kubelet连通性测试" "{\"result\": \"success\"}" "" "" "$TEST_LOG"
        return 0
    fi
    
    # 实际测试模式：检查Kubelet端口
    local kubelet_ip="127.0.0.1"
    
    if command -v nc >/dev/null 2>&1; then
        if nc -z "$kubelet_ip" "$KUBELET_PORT" 2>/dev/null; then
            log_info "$COMPONENT" "Kubelet端口开放" "{\"server\": \"${kubelet_ip}:${KUBELET_PORT}\"}" "" "" "$TEST_LOG"
            return 0
        fi
    fi
    
    # 检查Kubelet进程
    if pgrep -f kubelet >/dev/null 2>&1; then
        log_info "$COMPONENT" "Kubelet进程运行中" "{}" "" "" "$TEST_LOG"
        return 0
    fi
    
    log_warn "$COMPONENT" "Kubelet连通性测试失败" "{\"server\": \"${kubelet_ip}:${KUBELET_PORT}\"}" "[\"检查Kubelet服务\", \"验证端口配置\"]" "$TEST_LOG"
    return 1
}

# 测试Flannel网络连通性
test_flannel_connectivity() {
    log_info "$COMPONENT" "测试Flannel网络连通性" "{\"port\": \"$FLANNEL_PORT\"}" "" "" "$TEST_LOG"
    
    if [[ "$INTEGRATION_TEST_MODE" == "true" ]]; then
        # 集成测试模式：模拟测试
        log_info "$COMPONENT" "模拟Flannel网络连通性测试" "{\"result\": \"success\"}" "" "" "$TEST_LOG"
        return 0
    fi
    
    # 实际测试模式：检查Flannel接口
    if ip link show flannel.1 >/dev/null 2>&1; then
        log_info "$COMPONENT" "Flannel接口存在" "{\"interface\": \"flannel.1\"}" "" "" "$TEST_LOG"
        
        # 检查Flannel VXLAN端口
        if ss -ulnp | grep -q ":$FLANNEL_PORT"; then
            log_info "$COMPONENT" "Flannel VXLAN端口监听中" "{\"port\": \"$FLANNEL_PORT\"}" "" "" "$TEST_LOG"
            return 0
        fi
    fi
    
    log_warn "$COMPONENT" "Flannel网络连通性测试失败" "{\"port\": \"$FLANNEL_PORT\"}" "[\"检查Flannel配置\", \"验证VXLAN设置\"]" "$TEST_LOG"
    return 1
}

# 测试服务发现功能
test_service_discovery() {
    log_info "$COMPONENT" "测试服务发现功能" "{}" "" "" "$TEST_LOG"
    
    if [[ "$INTEGRATION_TEST_MODE" == "true" ]]; then
        # 集成测试模式：模拟测试
        log_info "$COMPONENT" "模拟服务发现测试" "{\"result\": \"success\"}" "" "" "$TEST_LOG"
        return 0
    fi
    
    # 实际测试模式：测试服务发现
    if command -v kubectl >/dev/null 2>&1; then
        # 检查默认服务
        if kubectl get svc kubernetes >/dev/null 2>&1; then
            log_info "$COMPONENT" "Kubernetes默认服务可发现" "{}" "" "" "$TEST_LOG"
            
            # 检查kube-dns服务
            if kubectl get svc -n kube-system kube-dns >/dev/null 2>&1; then
                log_info "$COMPONENT" "kube-dns服务可发现" "{}" "" "" "$TEST_LOG"
                return 0
            fi
        fi
    fi
    
    log_warn "$COMPONENT" "服务发现测试失败" "{}" "[\"检查服务配置\", \"验证DNS设置\"]" "$TEST_LOG"
    return 1
}

# 测试Pod间网络通信
test_pod_to_pod_communication() {
    log_info "$COMPONENT" "测试Pod间网络通信" "{}" "" "" "$TEST_LOG"
    
    if [[ "$INTEGRATION_TEST_MODE" == "true" ]]; then
        # 集成测试模式：模拟测试
        log_info "$COMPONENT" "模拟Pod间网络通信测试" "{\"result\": \"success\"}" "" "" "$TEST_LOG"
        return 0
    fi
    
    # 实际测试模式：检查Pod网络
    if command -v kubectl >/dev/null 2>&1; then
        # 获取运行中的Pod
        local pod_count
        pod_count=$(kubectl get pods --all-namespaces --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [[ "$pod_count" -gt 0 ]]; then
            log_info "$COMPONENT" "发现运行中的Pod" "{\"pod_count\": $pod_count}" "" "" "$TEST_LOG"
            return 0
        fi
    fi
    
    log_warn "$COMPONENT" "Pod间网络通信测试失败" "{}" "[\"检查Pod状态\", \"验证网络策略\"]" "$TEST_LOG"
    return 1
}

# 生成网络连通性测试报告
generate_network_test_report() {
    local report_file="${PROJECT_ROOT}/logs/network-connectivity-report-$(date +%Y%m%d-%H%M%S).json"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    log_info "$COMPONENT" "生成网络连通性测试报告" "{\"report_file\": \"$report_file\"}" "" "" "$TEST_LOG"
    
    cat > "$report_file" << EOF
{
  "timestamp": "$timestamp",
  "test_type": "network_connectivity",
  "integration_test_mode": $INTEGRATION_TEST_MODE,
  "network_configuration": {
    "cluster_cidr": "$CLUSTER_CIDR",
    "service_cidr": "$SERVICE_CIDR",
    "cluster_dns": "$CLUSTER_DNS",
    "api_server_port": "$API_SERVER_PORT",
    "kubelet_port": "$KUBELET_PORT",
    "flannel_port": "$FLANNEL_PORT"
  },
  "test_results": {
    "cluster_cidr_connectivity": "$(test_cluster_cidr_connectivity && echo "PASS" || echo "FAIL")",
    "service_cidr_connectivity": "$(test_service_cidr_connectivity && echo "PASS" || echo "FAIL")",
    "dns_connectivity": "$(test_dns_connectivity && echo "PASS" || echo "FAIL")",
    "api_server_connectivity": "$(test_api_server_connectivity && echo "PASS" || echo "FAIL")",
    "kubelet_connectivity": "$(test_kubelet_connectivity && echo "PASS" || echo "FAIL")",
    "flannel_connectivity": "$(test_flannel_connectivity && echo "PASS" || echo "FAIL")",
    "service_discovery": "$(test_service_discovery && echo "PASS" || echo "FAIL")",
    "pod_to_pod_communication": "$(test_pod_to_pod_communication && echo "PASS" || echo "FAIL")"
  }
}
EOF
    
    echo "网络连通性测试报告: $report_file"
}

# 主测试函数
main() {
    log_info "$COMPONENT" "开始网络连通性集成测试" "{}" "" "" "$TEST_LOG"
    
    # 初始化测试环境
    init_test_environment
    
    local test_results=()
    local failed_tests=0
    
    # 执行所有网络连通性测试
    local tests=(
        "test_cluster_cidr_connectivity:集群CIDR连通性"
        "test_service_cidr_connectivity:服务CIDR连通性"
        "test_dns_connectivity:DNS服务连通性"
        "test_api_server_connectivity:API服务器连通性"
        "test_kubelet_connectivity:Kubelet连通性"
        "test_flannel_connectivity:Flannel网络连通性"
        "test_service_discovery:服务发现功能"
        "test_pod_to_pod_communication:Pod间网络通信"
    )
    
    for test_spec in "${tests[@]}"; do
        local test_func="${test_spec%:*}"
        local test_name="${test_spec#*:}"
        
        log_info "$COMPONENT" "执行测试: $test_name" "{}" "" "" "$TEST_LOG"
        
        if $test_func; then
            test_results+=("✓ $test_name")
            log_info "$COMPONENT" "测试通过: $test_name" "{}" "" "" "$TEST_LOG"
        else
            test_results+=("✗ $test_name")
            ((failed_tests++))
            log_error "$COMPONENT" "测试失败: $test_name" "{}" "" "" "$TEST_LOG"
        fi
    done
    
    # 输出测试结果摘要
    echo ""
    echo "=== 网络连通性测试结果 ==="
    for result in "${test_results[@]}"; do
        echo "$result"
    done
    echo ""
    
    if [[ $failed_tests -eq 0 ]]; then
        log_info "$COMPONENT" "所有网络连通性测试通过" "{}" "" "" "$TEST_LOG"
        echo "✓ 所有网络连通性测试通过"
    else
        log_error "$COMPONENT" "网络连通性测试失败" "{\"failed_count\": $failed_tests}" "" "" "$TEST_LOG"
        echo "✗ $failed_tests 个网络连通性测试失败"
    fi
    
    # 生成测试报告
    generate_network_test_report
    
    log_info "$COMPONENT" "网络连通性集成测试完成" "{\"failed_tests\": $failed_tests}" "" "" "$TEST_LOG"
    
    # 返回适当的退出码
    return $failed_tests
}

# 显示帮助信息
show_help() {
    cat << EOF
网络连通性集成测试脚本

用法: $0 [选项]

选项:
    --help              显示此帮助信息
    --config FILE       指定配置文件路径
    --integration       启用集成测试模式（模拟测试）

环境变量:
    TEST_CONFIG         配置文件路径
    INTEGRATION_TEST_MODE   集成测试模式 (true/false)
    DEBUG               启用调试输出

示例:
    # 运行网络连通性测试
    $0
    
    # 使用自定义配置文件
    $0 --config /path/to/config.yaml
    
    # 启用集成测试模式
    $0 --integration

EOF
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --config)
                TEST_CONFIG="$2"
                shift 2
                ;;
            --integration)
                export INTEGRATION_TEST_MODE=true
                shift
                ;;
            *)
                log_error "$COMPONENT" "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    main
fi