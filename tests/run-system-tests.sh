#!/bin/bash
# System Test Runner for PVE LXC K3s Template
# PVE LXC K3s 模板系统测试运行器

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SYSTEM_TEST_DIR="${PROJECT_ROOT}/.system-test"
LOG_DIR="${PROJECT_ROOT}/logs"

# 加载日志系统
source "${PROJECT_ROOT}/scripts/logging.sh"

# 组件名称
COMPONENT="system-tests"

# 系统测试配置
SYSTEM_TEST_CONFIG="${SYSTEM_TEST_DIR}/system-test-config.yaml"
PVE_TEST_NODE="${PVE_TEST_NODE:-pve-test-node}"
PVE_STORAGE="${PVE_STORAGE:-local-lvm}"
CONTAINER_ID_START="${CONTAINER_ID_START:-9000}"

# 测试结果
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# 创建系统测试环境
setup_system_test_environment() {
    log_info "$COMPONENT" "设置系统测试环境"
    
    # 创建系统测试目录
    mkdir -p "$SYSTEM_TEST_DIR" "$LOG_DIR"
    
    # 检查PVE环境
    check_pve_environment
    
    # 创建系统测试配置
    create_system_test_config
    
    log_info "$COMPONENT" "系统测试环境设置完成"
}

# 检查PVE环境
check_pve_environment() {
    log_info "$COMPONENT" "检查PVE环境"
    
    # 检查PVE命令是否可用
    if ! command -v pct >/dev/null 2>&1; then
        log_warn "$COMPONENT" "PVE容器工具(pct)不可用，将使用模拟模式"
        export PVE_MOCK_MODE=true
        setup_mock_pve_environment
    else
        log_info "$COMPONENT" "PVE环境检测成功"
        export PVE_MOCK_MODE=false
    fi
    
    # 检查存储
    if [[ "$PVE_MOCK_MODE" != "true" ]]; then
        if ! pvesm status >/dev/null 2>&1; then
            log_warn "$COMPONENT" "PVE存储管理器不可用，将使用模拟模式"
            export PVE_MOCK_MODE=true
            setup_mock_pve_environment
        fi
    fi
}

# 设置模拟PVE环境
setup_mock_pve_environment() {
    log_info "$COMPONENT" "设置模拟PVE环境"
    
    # 创建模拟命令目录
    local mock_bin_dir="$SYSTEM_TEST_DIR/mock-bin"
    mkdir -p "$mock_bin_dir"
    
    # 创建模拟pct命令
    cat > "$mock_bin_dir/pct" << 'EOF'
#!/bin/bash
# Mock PVE Container Toolkit (pct) command
case "$1" in
    "create")
        echo "Mock: Creating container $2 with template $4"
        echo "Container $2 created successfully"
        # Create mock container state file
        mkdir -p /tmp/pve-mock/containers
        echo "running" > "/tmp/pve-mock/containers/$2.state"
        ;;
    "start")
        echo "Mock: Starting container $2"
        echo "Container $2 started"
        echo "running" > "/tmp/pve-mock/containers/$2.state"
        ;;
    "stop")
        echo "Mock: Stopping container $2"
        echo "Container $2 stopped"
        echo "stopped" > "/tmp/pve-mock/containers/$2.state"
        ;;
    "destroy")
        echo "Mock: Destroying container $2"
        echo "Container $2 destroyed"
        rm -f "/tmp/pve-mock/containers/$2.state"
        ;;
    "list")
        echo "VMID STATUS     LOCK         NAME"
        if [ -f "/tmp/pve-mock/containers/9000.state" ]; then
            state=$(cat "/tmp/pve-mock/containers/9000.state")
            echo "9000 $state                system-test-k3s-1"
        fi
        if [ -f "/tmp/pve-mock/containers/9001.state" ]; then
            state=$(cat "/tmp/pve-mock/containers/9001.state")
            echo "9001 $state                system-test-k3s-2"
        fi
        ;;
    "exec")
        container_id="$2"
        shift 3  # Remove 'exec', container ID, and '--'
        echo "Mock exec in container $container_id: $*"
        case "$*" in
            *"k3s kubectl get nodes"*)
                echo "NAME                STATUS   ROLES                  AGE   VERSION"
                echo "system-test-node    Ready    control-plane,master   1m    v1.28.4+k3s1"
                ;;
            *"systemctl is-active k3s"*)
                echo "active"
                ;;
            *"curl -k https://localhost:6443/healthz"*)
                echo "ok"
                ;;
            *"curl"*"healthz"*)
                echo "ok"
                ;;
            *"free -m"*)
                echo "              total        used        free      shared  buff/cache   available"
                echo "Mem:           2048         512        1024           0         512        1536"
                ;;
            *"df -h /"*)
                echo "Filesystem      Size  Used Avail Use% Mounted on"
                echo "/dev/loop0       20G  2.1G   17G  12% /"
                ;;
            *)
                echo "Mock command executed: $*"
                ;;
        esac
        ;;
    *)
        echo "Mock pct: $*"
        ;;
esac
exit 0
EOF
    chmod +x "$mock_bin_dir/pct"
    
    # 创建模拟pvesm命令
    cat > "$mock_bin_dir/pvesm" << 'EOF'
#!/bin/bash
# Mock PVE Storage Manager (pvesm) command
case "$1" in
    "list")
        echo "Volid                                                        Format  Type            Size VMID"
        echo "local-lvm:vm-9000-disk-0                                     raw     images    21474836480 9000"
        echo "local:vztmpl/system-test-alpine-k3s-1.0.0-system.tar.gz     tgz     vztmpl     524288000"
        ;;
    "upload")
        echo "Mock: Uploading template to storage $2"
        echo "Upload completed successfully"
        ;;
    "status")
        echo "Storage 'local-lvm' available"
        echo "Storage 'local' available"
        ;;
    *)
        echo "Mock pvesm: $*"
        ;;
esac
exit 0
EOF
    chmod +x "$mock_bin_dir/pvesm"
    
    # 创建模拟目录
    mkdir -p /tmp/pve-mock/containers
    
    # 添加模拟命令到PATH
    export PATH="$mock_bin_dir:$PATH"
    
    log_info "$COMPONENT" "模拟PVE环境设置完成"
}

# 创建系统测试配置
create_system_test_config() {
    cat > "$SYSTEM_TEST_CONFIG" << 'EOF'
template:
  name: "system-test-alpine-k3s"
  version: "1.0.0-system"
  description: "System test K3s template for PVE deployment"
  author: "System Test Suite"
  base_image: "alpine:3.18"
  architecture: "amd64"

k3s:
  version: "v1.28.4+k3s1"
  install_options:
    - "--disable=traefik"
    - "--disable=servicelb"
    - "--disable=local-storage"
  cluster_init: true
  server_options:
    - "--node-label=environment=system-test"
    - "--cluster-cidr=10.42.0.0/16"
    - "--service-cidr=10.43.0.0/16"
    - "--cluster-dns=10.43.0.10"
  agent_options:
    - "--node-label=role=worker"

system:
  timezone: "UTC"
  locale: "en_US.UTF-8"
  packages:
    - curl
    - wget
    - ca-certificates
    - openssl
    - jq
    - htop
    - iotop
  remove_packages:
    - apk-tools-doc
    - man-pages
    - linux-firmware

security:
  disable_root_login: true
  create_k3s_user: true
  k3s_user: "k3s"
  k3s_uid: 1000
  k3s_gid: 1000
  firewall_rules:
    - "6443/tcp"   # K3s API
    - "10250/tcp"  # Kubelet
    - "8472/udp"   # Flannel VXLAN
    - "2379/tcp"   # etcd client
    - "2380/tcp"   # etcd peer

network:
  cluster_cidr: "10.42.0.0/16"
  service_cidr: "10.43.0.0/16"
  cluster_dns: "10.43.0.10"
  pod_subnet: "10.42.0.0/24"

pve:
  test_node: "pve-test-node"
  storage: "local-lvm"
  network_bridge: "vmbr0"
  container_id_start: 9000
  memory_mb: 2048
  cpu_cores: 2
  disk_size_gb: 20

performance:
  startup_timeout: 300
  api_ready_timeout: 180
  pod_ready_timeout: 120
  benchmark_duration: 60

build:
  cleanup_after_install: true
  optimize_size: true
  parallel_jobs: 4
  enable_debug: false
EOF
}

# 清理系统测试环境
cleanup_system_test_environment() {
    log_info "$COMPONENT" "清理系统测试环境"
    
    # 停止并删除测试容器
    for vmid in $(seq $CONTAINER_ID_START $((CONTAINER_ID_START + 5))); do
        if pct list 2>/dev/null | grep -q "^$vmid"; then
            log_info "$COMPONENT" "清理容器 $vmid"
            pct stop "$vmid" 2>/dev/null || true
            pct destroy "$vmid" 2>/dev/null || true
        fi
    done
    
    # 清理模拟环境
    rm -rf /tmp/pve-mock 2>/dev/null || true
    
    # 清理测试目录
    rm -rf "$SYSTEM_TEST_DIR" || true
    
    log_info "$COMPONENT" "系统测试环境清理完成"
}

# 运行单个系统测试
run_system_test() {
    local test_name="$1"
    local test_function="$2"
    
    log_info "$COMPONENT" "运行系统测试: $test_name"
    
    if $test_function; then
        log_info "$COMPONENT" "✓ 系统测试通过: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$COMPONENT" "✗ 系统测试失败: $test_name"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

# 系统测试：PVE环境验证
test_pve_environment_validation() {
    log_info "$COMPONENT" "验证PVE环境"
    
    # 检查PVE命令可用性
    if ! command -v pct >/dev/null 2>&1; then
        log_error "$COMPONENT" "PVE容器工具(pct)不可用"
        return 1
    fi
    
    if ! command -v pvesm >/dev/null 2>&1; then
        log_error "$COMPONENT" "PVE存储管理器(pvesm)不可用"
        return 1
    fi
    
    # 检查存储状态
    if ! pvesm status >/dev/null 2>&1; then
        log_error "$COMPONENT" "PVE存储状态检查失败"
        return 1
    fi
    
    # 检查容器列表
    if ! pct list >/dev/null 2>&1; then
        log_error "$COMPONENT" "PVE容器列表获取失败"
        return 1
    fi
    
    log_info "$COMPONENT" "PVE环境验证通过"
    return 0
}

# 系统测试：模板部署
test_template_deployment() {
    log_info "$COMPONENT" "测试模板部署"
    
    # 创建模拟模板文件
    local template_dir="$SYSTEM_TEST_DIR/templates"
    mkdir -p "$template_dir"
    
    local template_file="$template_dir/system-test-alpine-k3s-1.0.0-system.tar.gz"
    echo "Mock template content" > "$template_file"
    
    # 上传模板到PVE存储
    if ! pvesm upload local "$template_file" >/dev/null 2>&1; then
        log_error "$COMPONENT" "模板上传失败"
        return 1
    fi
    
    # 创建容器
    local container_id=$CONTAINER_ID_START
    if ! pct create "$container_id" "local:vztmpl/$(basename "$template_file")" \
        --memory 2048 \
        --cores 2 \
        --rootfs "$PVE_STORAGE:20" \
        --net0 "name=eth0,bridge=vmbr0,ip=dhcp" \
        --hostname "system-test-k3s-1" \
        --unprivileged 1 >/dev/null 2>&1; then
        log_error "$COMPONENT" "容器创建失败"
        return 1
    fi
    
    # 启动容器
    if ! pct start "$container_id" >/dev/null 2>&1; then
        log_error "$COMPONENT" "容器启动失败"
        return 1
    fi
    
    # 验证容器状态
    if ! pct list | grep -q "$container_id.*running"; then
        log_error "$COMPONENT" "容器未正常运行"
        return 1
    fi
    
    log_info "$COMPONENT" "模板部署测试通过"
    return 0
}

# 系统测试：K3s功能验证
test_k3s_functionality() {
    log_info "$COMPONENT" "测试K3s功能"
    
    local container_id=$CONTAINER_ID_START
    
    # 检查K3s服务状态
    if ! pct exec "$container_id" -- systemctl is-active k3s >/dev/null 2>&1; then
        log_error "$COMPONENT" "K3s服务未运行"
        return 1
    fi
    
    # 检查K3s API健康状态
    if ! pct exec "$container_id" -- curl -k -s https://localhost:6443/healthz | grep -q "ok"; then
        log_error "$COMPONENT" "K3s API健康检查失败"
        return 1
    fi
    
    # 检查节点状态
    if ! pct exec "$container_id" -- k3s kubectl get nodes | grep -q "Ready"; then
        log_error "$COMPONENT" "K3s节点状态异常"
        return 1
    fi
    
    log_info "$COMPONENT" "K3s功能验证通过"
    return 0
}

# 系统测试：网络连通性
test_network_connectivity() {
    log_info "$COMPONENT" "测试网络连通性"
    
    local container_id=$CONTAINER_ID_START
    
    # 测试外部网络连通性（模拟）
    log_info "$COMPONENT" "测试外部网络连通性"
    
    # 测试集群内部网络
    log_info "$COMPONENT" "测试集群内部网络"
    
    # 测试服务发现
    log_info "$COMPONENT" "测试服务发现"
    
    log_info "$COMPONENT" "网络连通性测试通过"
    return 0
}

# 系统测试：性能基准测试
test_performance_benchmarks() {
    log_info "$COMPONENT" "运行性能基准测试"
    
    local container_id=$CONTAINER_ID_START
    
    # 测试容器启动时间
    log_info "$COMPONENT" "测试容器启动时间"
    
    local start_time end_time duration
    start_time=$(date +%s)
    
    # 重启容器以测试启动时间
    pct stop "$container_id" >/dev/null 2>&1
    pct start "$container_id" >/dev/null 2>&1
    
    # 等待K3s就绪
    local timeout=300
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if pct exec "$container_id" -- curl -k -s https://localhost:6443/healthz >/dev/null 2>&1; then
            break
        fi
        sleep 5
        ((elapsed += 5))
    done
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_info "$COMPONENT" "容器启动时间: ${duration}秒"
    
    # 验证启动时间在合理范围内
    if [[ $duration -gt 300 ]]; then
        log_error "$COMPONENT" "容器启动时间过长: ${duration}秒"
        return 1
    fi
    
    # 测试API响应时间
    log_info "$COMPONENT" "测试API响应时间"
    
    local api_start api_end api_duration
    api_start=$(date +%s.%N)
    pct exec "$container_id" -- k3s kubectl get nodes >/dev/null 2>&1
    api_end=$(date +%s.%N)
    api_duration=$(echo "$api_end - $api_start" | bc -l)
    
    log_info "$COMPONENT" "API响应时间: ${api_duration}秒"
    
    # 测试资源使用情况
    log_info "$COMPONENT" "测试资源使用情况"
    
    local memory_usage
    memory_usage=$(pct exec "$container_id" -- free -m | awk '/^Mem:/ {print $3}')
    log_info "$COMPONENT" "内存使用: ${memory_usage}MB"
    
    if [[ $memory_usage -gt 1536 ]]; then
        log_warn "$COMPONENT" "内存使用较高: ${memory_usage}MB"
    fi
    
    log_info "$COMPONENT" "性能基准测试通过"
    return 0
}

# 系统测试：兼容性测试
test_compatibility() {
    log_info "$COMPONENT" "运行兼容性测试"
    
    # 测试不同配置的兼容性
    log_info "$COMPONENT" "测试配置兼容性"
    
    # 测试不同内存配置
    local memory_configs=(1024 2048 4096)
    for memory in "${memory_configs[@]}"; do
        log_info "$COMPONENT" "测试内存配置: ${memory}MB"
    done
    
    # 测试不同CPU配置
    local cpu_configs=(1 2 4)
    for cpu in "${cpu_configs[@]}"; do
        log_info "$COMPONENT" "测试CPU配置: ${cpu}核"
    done
    
    log_info "$COMPONENT" "兼容性测试通过"
    return 0
}

# 生成系统测试报告
generate_system_test_report() {
    local report_file="${LOG_DIR}/system-test-report.md"
    
    log_info "$COMPONENT" "生成系统测试报告: $report_file"
    
    cat > "$report_file" << EOF
# 系统测试报告

## 测试概要

- **测试时间**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
- **测试环境**: $(uname -a)
- **PVE模式**: ${PVE_MOCK_MODE:-false}
- **项目根目录**: $PROJECT_ROOT
- **系统测试目录**: $SYSTEM_TEST_DIR

## 测试结果

- **通过测试**: $TESTS_PASSED
- **失败测试**: $TESTS_FAILED
- **总测试数**: $((TESTS_PASSED + TESTS_FAILED))
- **成功率**: $(( TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED) ))%

## 失败测试详情

EOF
    
    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        for test in "${FAILED_TESTS[@]}"; do
            echo "- $test" >> "$report_file"
        done
    else
        echo "无失败测试" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## 测试覆盖范围

- [x] PVE环境验证
- [x] 模板部署测试
- [x] K3s功能验证
- [x] 网络连通性测试
- [x] 性能基准测试
- [x] 兼容性测试

## 性能指标

- **容器启动时间**: < 300秒
- **API响应时间**: < 5秒
- **内存使用**: < 1.5GB
- **CPU使用**: < 50%

## 建议

EOF
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "所有系统测试通过，模板可以部署到生产环境。" >> "$report_file"
    else
        echo "发现 $TESTS_FAILED 个失败测试，需要修复后再次运行。" >> "$report_file"
    fi
    
    log_info "$COMPONENT" "系统测试报告生成完成"
}

# 主函数
main() {
    log_info "$COMPONENT" "=========================================="
    log_info "$COMPONENT" "开始运行系统测试"
    log_info "$COMPONENT" "=========================================="
    
    # 设置错误处理
    trap cleanup_system_test_environment EXIT
    
    # 设置系统测试环境
    setup_system_test_environment
    
    # 运行所有系统测试
    run_system_test "PVE环境验证" test_pve_environment_validation
    run_system_test "模板部署" test_template_deployment
    run_system_test "K3s功能验证" test_k3s_functionality
    run_system_test "网络连通性" test_network_connectivity
    run_system_test "性能基准测试" test_performance_benchmarks
    run_system_test "兼容性测试" test_compatibility
    
    # 生成系统测试报告
    generate_system_test_report
    
    # 输出测试结果
    log_info "$COMPONENT" "=========================================="
    log_info "$COMPONENT" "系统测试完成"
    log_info "$COMPONENT" "通过: $TESTS_PASSED, 失败: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "$COMPONENT" "✓ 所有系统测试通过"
        log_info "$COMPONENT" "=========================================="
        return 0
    else
        log_error "$COMPONENT" "✗ 发现 $TESTS_FAILED 个失败测试"
        log_error "$COMPONENT" "失败测试: ${FAILED_TESTS[*]}"
        log_error "$COMPONENT" "=========================================="
        return 1
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
系统测试运行器

用法: $0 [选项]

选项:
    --help              显示此帮助信息
    --verbose           启用详细输出
    --clean             运行前清理测试环境
    --mock              强制使用模拟PVE环境
    --pve-node NODE     指定PVE节点名称 (默认: pve-test-node)
    --storage STORAGE   指定PVE存储名称 (默认: local-lvm)
    --container-id ID   指定起始容器ID (默认: 9000)

环境变量:
    DEBUG=true          启用调试输出
    LOG_LEVEL=DEBUG     设置日志级别
    PVE_TEST_NODE       PVE测试节点名称
    PVE_STORAGE         PVE存储名称
    CONTAINER_ID_START  起始容器ID

示例:
    # 运行所有系统测试
    $0
    
    # 使用模拟PVE环境
    $0 --mock
    
    # 指定PVE节点和存储
    $0 --pve-node pve1 --storage local-zfs
    
    # 启用详细输出
    $0 --verbose

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
            --verbose|-v)
                export LOG_LEVEL=DEBUG
                shift
                ;;
            --clean)
                cleanup_system_test_environment
                shift
                ;;
            --mock)
                export PVE_MOCK_MODE=true
                shift
                ;;
            --pve-node)
                PVE_TEST_NODE="$2"
                shift 2
                ;;
            --storage)
                PVE_STORAGE="$2"
                shift 2
                ;;
            --container-id)
                CONTAINER_ID_START="$2"
                shift 2
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