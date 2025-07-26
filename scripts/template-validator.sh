#!/bin/bash
# PVE LXC K3s Template Validator
# 模板验证和测试脚本，验证模板完整性和基础功能

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/config/template.yaml"
LOG_DIR="${PROJECT_ROOT}/logs"
OUTPUT_DIR="${PROJECT_ROOT}/output"
TEST_DIR="${PROJECT_ROOT}/.test"

# 创建必要的目录
mkdir -p "$LOG_DIR" "$TEST_DIR"

# 日志配置
LOG_FILE="${LOG_DIR}/template-validator.log"
VALIDATION_LOG="${LOG_DIR}/validation-$(date +%Y%m%d-%H%M%S).log"

# 测试配置
TEST_TIMEOUT=300  # 5分钟超时
K3S_READY_TIMEOUT=120  # K3s就绪超时
API_CHECK_RETRIES=10   # API检查重试次数

# 日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" | tee -a "$VALIDATION_LOG"
}

log_info() { log "INFO" "$1"; }
log_warn() { log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }
log_debug() { 
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "$1"
    fi
}

# 测试结果跟踪
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=()

# 测试函数
test_start() {
    local test_name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log_info "🧪 开始测试: $test_name"
}

test_pass() {
    local test_name="$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TEST_RESULTS+=("✅ PASS: $test_name")
    log_info "✅ 测试通过: $test_name"
}

test_fail() {
    local test_name="$1"
    local reason="${2:-未知原因}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TEST_RESULTS+=("❌ FAIL: $test_name - $reason")
    log_error "❌ 测试失败: $test_name - $reason"
}

# 错误处理
error_exit() {
    local error_message="$1"
    local exit_code="${2:-1}"
    log_error "$error_message"
    cleanup_test_environment
    exit "$exit_code"
}

# 清理测试环境
cleanup_test_environment() {
    log_info "清理测试环境..."
    
    # 停止测试容器
    if [[ -n "${TEST_CONTAINER_ID:-}" ]]; then
        log_info "停止测试容器: $TEST_CONTAINER_ID"
        docker stop "$TEST_CONTAINER_ID" >/dev/null 2>&1 || true
        docker rm "$TEST_CONTAINER_ID" >/dev/null 2>&1 || true
    fi
    
    # 清理临时文件
    rm -rf "${TEST_DIR}/temp" || true
    
    log_info "测试环境清理完成"
}

# 信号处理
trap 'error_exit "验证过程被中断" 130' INT TERM
trap 'cleanup_test_environment' EXIT

# 加载配置
load_configuration() {
    log_info "加载配置文件"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "配置文件不存在: $CONFIG_FILE"
    fi
    
    # 使用 yq 或简单的 grep/awk 解析 YAML
    if command -v yq >/dev/null 2>&1; then
        TEMPLATE_NAME=$(yq eval '.template.name' "$CONFIG_FILE" 2>/dev/null || echo "alpine-k3s")
        TEMPLATE_VERSION=$(yq eval '.template.version' "$CONFIG_FILE" 2>/dev/null || echo "1.0.0")
        ARCHITECTURE=$(yq eval '.template.architecture' "$CONFIG_FILE" 2>/dev/null || echo "amd64")
        K3S_VERSION=$(yq eval '.k3s.version' "$CONFIG_FILE" 2>/dev/null)
    else
        # 简单的 grep/awk 解析作为后备方案
        TEMPLATE_NAME=$(grep -A 10 "^template:" "$CONFIG_FILE" | grep "name:" | awk '{print $2}' | tr -d '"' || echo "alpine-k3s")
        TEMPLATE_VERSION=$(grep -A 10 "^template:" "$CONFIG_FILE" | grep "version:" | awk '{print $2}' | tr -d '"' || echo "1.0.0")
        ARCHITECTURE=$(grep -A 10 "^template:" "$CONFIG_FILE" | grep "architecture:" | awk '{print $2}' | tr -d '"' || echo "amd64")
        K3S_VERSION=$(grep -A 10 "^k3s:" "$CONFIG_FILE" | grep "version:" | awk '{print $2}' | tr -d '"\n')
    fi
    
    # 验证必要配置
    if [[ -z "$K3S_VERSION" ]]; then
        error_exit "K3s 版本未在配置中指定"
    fi
    
    log_info "配置加载完成:"
    log_info "  模板名称: $TEMPLATE_NAME"
    log_info "  模板版本: $TEMPLATE_VERSION"
    log_info "  系统架构: $ARCHITECTURE"
    log_info "  K3s版本: $K3S_VERSION"
}

# 验证模板包完整性
validate_template_package() {
    test_start "模板包完整性验证"
    
    local template_filename="${TEMPLATE_NAME}-${TEMPLATE_VERSION}-${ARCHITECTURE}.tar.gz"
    local template_package="${OUTPUT_DIR}/$template_filename"
    
    # 检查模板包是否存在
    if [[ ! -f "$template_package" ]]; then
        test_fail "模板包完整性验证" "模板包不存在: $template_package"
        return 1
    fi
    
    # 验证压缩包完整性
    if ! tar -tzf "$template_package" >/dev/null 2>&1; then
        test_fail "模板包完整性验证" "模板包损坏或格式错误"
        return 1
    fi
    
    # 验证必要文件存在
    local required_files=("rootfs.tar.gz" "config" "template" "manifest.json")
    for file in "${required_files[@]}"; do
        if ! tar -tzf "$template_package" | grep -q "^$file$"; then
            test_fail "模板包完整性验证" "缺少必要文件: $file"
            return 1
        fi
    done
    
    # 验证校验和
    if [[ -f "${template_package}.sha256" ]]; then
        if ! sha256sum -c "${template_package}.sha256" >/dev/null 2>&1; then
            test_fail "模板包完整性验证" "校验和验证失败"
            return 1
        fi
    fi
    
    test_pass "模板包完整性验证"
}

# 验证模板元数据
validate_template_metadata() {
    test_start "模板元数据验证"
    
    local template_filename="${TEMPLATE_NAME}-${TEMPLATE_VERSION}-${ARCHITECTURE}.tar.gz"
    local template_package="${OUTPUT_DIR}/$template_filename"
    local temp_extract="${TEST_DIR}/temp/extract"
    
    mkdir -p "$temp_extract"
    
    # 提取模板包
    if ! tar -xzf "$template_package" -C "$temp_extract"; then
        test_fail "模板元数据验证" "无法提取模板包"
        return 1
    fi
    
    # 验证配置文件
    if [[ ! -f "${temp_extract}/config" ]]; then
        test_fail "模板元数据验证" "配置文件不存在"
        return 1
    fi
    
    # 验证模板脚本
    if [[ ! -x "${temp_extract}/template" ]]; then
        test_fail "模板元数据验证" "模板脚本不存在或不可执行"
        return 1
    fi
    
    # 验证清单文件
    if [[ ! -f "${temp_extract}/manifest.json" ]]; then
        test_fail "模板元数据验证" "清单文件不存在"
        return 1
    fi
    
    # 验证清单文件格式
    if command -v jq >/dev/null 2>&1; then
        if ! jq empty "${temp_extract}/manifest.json" >/dev/null 2>&1; then
            test_fail "模板元数据验证" "清单文件格式错误"
            return 1
        fi
        
        # 验证必要字段
        local required_fields=("template.name" "template.version" "template.architecture")
        for field in "${required_fields[@]}"; do
            if ! jq -e ".$field" "${temp_extract}/manifest.json" >/dev/null 2>&1; then
                test_fail "模板元数据验证" "清单文件缺少字段: $field"
                return 1
            fi
        done
    fi
    
    test_pass "模板元数据验证"
}

# 验证根文件系统
validate_rootfs() {
    test_start "根文件系统验证"
    
    local template_filename="${TEMPLATE_NAME}-${TEMPLATE_VERSION}-${ARCHITECTURE}.tar.gz"
    local template_package="${OUTPUT_DIR}/$template_filename"
    local temp_extract="${TEST_DIR}/temp/extract"
    local rootfs_extract="${TEST_DIR}/temp/rootfs"
    
    mkdir -p "$rootfs_extract"
    
    # 提取根文件系统
    if ! tar -xzf "${temp_extract}/rootfs.tar.gz" -C "$rootfs_extract"; then
        test_fail "根文件系统验证" "无法提取根文件系统"
        return 1
    fi
    
    # 验证关键目录结构
    local required_dirs=("bin" "etc" "usr" "var" "lib" "sbin")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "${rootfs_extract}/$dir" ]]; then
            test_fail "根文件系统验证" "缺少关键目录: $dir"
            return 1
        fi
    done
    
    # 验证 K3s 安装
    if [[ ! -x "${rootfs_extract}/usr/local/bin/k3s" ]]; then
        test_fail "根文件系统验证" "K3s 二进制文件不存在或不可执行"
        return 1
    fi
    
    # 验证 K3s 配置目录
    if [[ ! -d "${rootfs_extract}/etc/rancher/k3s" ]]; then
        test_fail "根文件系统验证" "K3s 配置目录不存在"
        return 1
    fi
    
    # 验证系统服务文件
    if [[ ! -f "${rootfs_extract}/etc/init.d/k3s" ]] && [[ ! -f "${rootfs_extract}/lib/systemd/system/k3s.service" ]]; then
        test_fail "根文件系统验证" "K3s 服务文件不存在"
        return 1
    fi
    
    # 验证模板信息文件
    if [[ ! -f "${rootfs_extract}/etc/lxc-template-info" ]]; then
        test_fail "根文件系统验证" "模板信息文件不存在"
        return 1
    fi
    
    test_pass "根文件系统验证"
}

# 测试模板大小优化
test_template_size() {
    test_start "模板大小优化测试"
    
    local template_filename="${TEMPLATE_NAME}-${TEMPLATE_VERSION}-${ARCHITECTURE}.tar.gz"
    local template_package="${OUTPUT_DIR}/$template_filename"
    local rootfs_extract="${TEST_DIR}/temp/rootfs"
    
    # 计算模板包大小
    local package_size
    package_size=$(stat -c%s "$template_package")
    local package_size_mb=$((package_size / 1024 / 1024))
    
    log_info "模板包大小: ${package_size_mb}MB"
    
    # 检查大小是否合理（应该小于500MB）
    if [[ $package_size_mb -gt 500 ]]; then
        test_fail "模板大小优化测试" "模板包过大: ${package_size_mb}MB > 500MB"
        return 1
    fi
    
    # 计算根文件系统大小
    local rootfs_size
    rootfs_size=$(du -sb "$rootfs_extract" | cut -f1)
    local rootfs_size_mb=$((rootfs_size / 1024 / 1024))
    
    log_info "根文件系统大小: ${rootfs_size_mb}MB"
    
    # 检查压缩比
    local compression_ratio=$(( (rootfs_size - package_size) * 100 / rootfs_size ))
    log_info "压缩比: ${compression_ratio}%"
    
    if [[ $compression_ratio -lt 30 ]]; then
        test_fail "模板大小优化测试" "压缩比过低: ${compression_ratio}% < 30%"
        return 1
    fi
    
    # 检查是否存在不必要的文件
    local unnecessary_patterns=(
        "*.log"
        "*.cache"
        "*/cache/*"
        "*/tmp/*"
        "*/.git/*"
        "*/man/*"
        "*/doc/*"
    )
    
    local found_unnecessary=false
    for pattern in "${unnecessary_patterns[@]}"; do
        if find "$rootfs_extract" -path "$pattern" -type f | head -1 | grep -q .; then
            log_warn "发现可能不必要的文件: $pattern"
            found_unnecessary=true
        fi
    done
    
    if [[ "$found_unnecessary" == "true" ]]; then
        log_warn "建议进一步清理不必要的文件以优化大小"
    fi
    
    test_pass "模板大小优化测试"
}

# 使用 Docker 模拟 LXC 环境测试
test_k3s_functionality() {
    test_start "K3s 功能测试"
    
    local rootfs_extract="${TEST_DIR}/temp/rootfs"
    
    # 检查 Docker 是否可用
    if ! command -v docker >/dev/null 2>&1; then
        log_warn "Docker 不可用，跳过 K3s 功能测试"
        return 0
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_warn "Docker 守护进程不可用，跳过 K3s 功能测试"
        return 0
    fi
    
    # 创建测试用的 Dockerfile
    cat > "${TEST_DIR}/Dockerfile" << 'EOF'
FROM alpine:3.18

# 复制根文件系统
COPY rootfs/ /

# 设置环境变量
ENV PATH="/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin"

# 创建必要的目录和设备文件
RUN mkdir -p /dev /proc /sys /tmp /run \
    && mknod /dev/null c 1 3 \
    && mknod /dev/zero c 1 5 \
    && mknod /dev/random c 1 8 \
    && mknod /dev/urandom c 1 9 \
    && chmod 666 /dev/null /dev/zero /dev/random /dev/urandom

# 设置启动脚本
COPY test-startup.sh /test-startup.sh
RUN chmod +x /test-startup.sh

CMD ["/test-startup.sh"]
EOF
    
    # 创建测试启动脚本
    cat > "${TEST_DIR}/test-startup.sh" << 'EOF'
#!/bin/sh
set -e

echo "=== K3s 功能测试开始 ==="

# 检查 K3s 二进制文件
echo "检查 K3s 二进制文件..."
if [ ! -x "/usr/local/bin/k3s" ]; then
    echo "ERROR: K3s 二进制文件不存在"
    exit 1
fi

# 检查 K3s 版本
echo "检查 K3s 版本..."
k3s_version=$(k3s --version | head -n1 | awk '{print $3}')
echo "K3s 版本: $k3s_version"

# 检查配置文件
echo "检查 K3s 配置..."
if [ ! -d "/etc/rancher/k3s" ]; then
    echo "ERROR: K3s 配置目录不存在"
    exit 1
fi

# 尝试启动 K3s（在后台）
echo "启动 K3s 服务..."
export K3S_KUBECONFIG_MODE="644"
export K3S_NODE_NAME="test-node"

# 在后台启动 K3s
k3s server --disable=traefik --disable=servicelb --write-kubeconfig-mode=644 &
K3S_PID=$!

# 等待 K3s 启动
echo "等待 K3s 启动..."
sleep 30

# 检查 K3s 进程
if ! kill -0 $K3S_PID 2>/dev/null; then
    echo "ERROR: K3s 进程已退出"
    exit 1
fi

# 检查 kubeconfig 文件
if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
    echo "✓ kubeconfig 文件存在"
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
else
    echo "ERROR: kubeconfig 文件不存在"
    kill $K3S_PID
    exit 1
fi

# 等待 API 服务器就绪
echo "等待 API 服务器就绪..."
for i in $(seq 1 30); do
    if k3s kubectl get nodes >/dev/null 2>&1; then
        echo "✓ API 服务器就绪"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: API 服务器未就绪"
        kill $K3S_PID
        exit 1
    fi
    sleep 2
done

# 检查节点状态
echo "检查节点状态..."
if k3s kubectl get nodes | grep -q "Ready"; then
    echo "✓ 节点状态正常"
else
    echo "ERROR: 节点状态异常"
    k3s kubectl get nodes
    kill $K3S_PID
    exit 1
fi

# 检查系统 Pod
echo "检查系统 Pod..."
if k3s kubectl get pods -n kube-system | grep -q "Running"; then
    echo "✓ 系统 Pod 运行正常"
else
    echo "WARNING: 部分系统 Pod 可能未就绪"
    k3s kubectl get pods -n kube-system
fi

# 清理
echo "清理测试环境..."
kill $K3S_PID
wait $K3S_PID 2>/dev/null || true

echo "=== K3s 功能测试完成 ==="
EOF
    
    chmod +x "${TEST_DIR}/test-startup.sh"
    
    # 构建测试镜像
    log_info "构建测试镜像..."
    if ! docker build -t "k3s-template-test:${TEMPLATE_VERSION}" "${TEST_DIR}" >/dev/null 2>&1; then
        test_fail "K3s 功能测试" "无法构建测试镜像"
        return 1
    fi
    
    # 运行测试容器
    log_info "运行 K3s 功能测试..."
    local container_output
    if container_output=$(timeout $TEST_TIMEOUT docker run --rm --privileged \
        --tmpfs /run --tmpfs /var/run \
        -v /lib/modules:/lib/modules:ro \
        "k3s-template-test:${TEMPLATE_VERSION}" 2>&1); then
        
        log_info "K3s 功能测试输出:"
        echo "$container_output" | while IFS= read -r line; do
            log_info "  $line"
        done
        
        test_pass "K3s 功能测试"
    else
        log_error "K3s 功能测试输出:"
        echo "$container_output" | while IFS= read -r line; do
            log_error "  $line"
        done
        
        test_fail "K3s 功能测试" "K3s 启动或功能测试失败"
        return 1
    fi
    
    # 清理测试镜像
    docker rmi "k3s-template-test:${TEMPLATE_VERSION}" >/dev/null 2>&1 || true
}

# 性能基准测试
test_performance_benchmark() {
    test_start "性能基准测试"
    
    local template_filename="${TEMPLATE_NAME}-${TEMPLATE_VERSION}-${ARCHITECTURE}.tar.gz"
    local template_package="${OUTPUT_DIR}/$template_filename"
    local rootfs_extract="${TEST_DIR}/temp/rootfs"
    
    # 测试解压时间
    log_info "测试模板解压性能..."
    local extract_start=$(date +%s)
    
    local temp_extract_perf="${TEST_DIR}/temp/perf_extract"
    mkdir -p "$temp_extract_perf"
    
    if tar -xzf "$template_package" -C "$temp_extract_perf" >/dev/null 2>&1; then
        local extract_end=$(date +%s)
        local extract_time=$((extract_end - extract_start))
        log_info "模板解压时间: ${extract_time}秒"
        
        if [[ $extract_time -gt 60 ]]; then
            log_warn "模板解压时间较长: ${extract_time}秒 > 60秒"
        fi
    else
        test_fail "性能基准测试" "模板解压失败"
        return 1
    fi
    
    # 测试根文件系统解压时间
    local rootfs_start=$(date +%s)
    local temp_rootfs_perf="${TEST_DIR}/temp/perf_rootfs"
    mkdir -p "$temp_rootfs_perf"
    
    if tar -xzf "${temp_extract_perf}/rootfs.tar.gz" -C "$temp_rootfs_perf" >/dev/null 2>&1; then
        local rootfs_end=$(date +%s)
        local rootfs_time=$((rootfs_end - rootfs_start))
        log_info "根文件系统解压时间: ${rootfs_time}秒"
        
        if [[ $rootfs_time -gt 120 ]]; then
            log_warn "根文件系统解压时间较长: ${rootfs_time}秒 > 120秒"
        fi
    else
        test_fail "性能基准测试" "根文件系统解压失败"
        return 1
    fi
    
    # 统计文件数量
    local file_count
    file_count=$(find "$temp_rootfs_perf" -type f | wc -l)
    log_info "根文件系统文件数量: $file_count"
    
    # 统计目录数量
    local dir_count
    dir_count=$(find "$temp_rootfs_perf" -type d | wc -l)
    log_info "根文件系统目录数量: $dir_count"
    
    # 计算平均文件大小
    local total_size
    total_size=$(du -sb "$temp_rootfs_perf" | cut -f1)
    local avg_file_size=$((total_size / file_count))
    log_info "平均文件大小: $(numfmt --to=iec $avg_file_size)"
    
    test_pass "性能基准测试"
}

# 生成验证报告
generate_validation_report() {
    local report_file="${OUTPUT_DIR}/validation-report.txt"
    
    log_info "生成验证报告: $report_file"
    
    cat > "$report_file" << EOF
# PVE LXC K3s Template Validation Report

## Validation Information
Validation Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Validation Host: $(hostname)
Validation User: $(whoami)
Template Name: $TEMPLATE_NAME
Template Version: $TEMPLATE_VERSION
Architecture: $ARCHITECTURE
K3s Version: $K3S_VERSION

## Test Summary
Total Tests: $TESTS_TOTAL
Passed: $TESTS_PASSED
Failed: $TESTS_FAILED
Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%

## Test Results
$(printf '%s\n' "${TEST_RESULTS[@]}")

## Validation Logs
Main Log: $LOG_FILE
Validation Log: $VALIDATION_LOG

## Recommendations
$(if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ 所有测试通过，模板可以发布"
else
    echo "❌ 存在失败的测试，建议修复后重新验证"
fi)

## Next Steps
$(if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "1. 模板已通过验证，可以上传到发布仓库"
    echo "2. 更新文档和变更日志"
    echo "3. 创建 GitHub Release"
else
    echo "1. 查看失败的测试详情"
    echo "2. 修复发现的问题"
    echo "3. 重新构建和验证模板"
fi)

EOF
    
    log_info "验证报告生成完成"
}

# 主验证函数
main() {
    local start_time=$SECONDS
    
    log_info "=========================================="
    log_info "PVE LXC K3s Template Validator 开始验证"
    log_info "=========================================="
    
    # 加载配置
    load_configuration
    
    # 执行验证测试
    validate_template_package
    validate_template_metadata
    validate_rootfs
    test_template_size
    test_k3s_functionality
    test_performance_benchmark
    
    # 生成报告
    generate_validation_report
    
    local validation_time=$((SECONDS - start_time))
    log_info "验证完成"
    log_info "总验证时间: $((validation_time / 60)) 分钟 $((validation_time % 60)) 秒"
    log_info "测试结果: $TESTS_PASSED/$TESTS_TOTAL 通过"
    
    # 返回适当的退出码
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "✅ 所有验证测试通过"
        return 0
    else
        log_error "❌ 验证测试失败: $TESTS_FAILED 个测试未通过"
        return 1
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
PVE LXC K3s Template Validator

用法: $0 [选项] [命令]

命令:
    validate            验证模板 (默认)
    quick               快速验证（跳过功能测试）
    package-only        仅验证模板包
    performance         仅运行性能测试

选项:
    --config FILE       指定配置文件路径 (默认: config/template.yaml)
    --output-dir DIR    指定输出目录 (默认: output)
    --test-dir DIR      指定测试目录 (默认: .test)
    --timeout SECONDS   设置测试超时时间 (默认: 300)
    --debug             启用调试输出
    --help              显示此帮助信息

环境变量:
    DEBUG=true          启用调试输出
    SKIP_DOCKER_TESTS=true  跳过需要 Docker 的测试

示例:
    # 完整验证
    $0 validate
    
    # 快速验证
    $0 quick
    
    # 仅验证模板包
    $0 package-only
    
    # 启用调试模式
    $0 --debug validate

EOF
}

# 解析命令行参数
parse_arguments() {
    local command="validate"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            validate|quick|package-only|performance)
                command="$1"
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --test-dir)
                TEST_DIR="$2"
                shift 2
                ;;
            --timeout)
                TEST_TIMEOUT="$2"
                shift 2
                ;;
            --debug)
                export DEBUG=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 执行命令
    case $command in
        validate)
            main
            ;;
        quick)
            load_configuration
            validate_template_package
            validate_template_metadata
            validate_rootfs
            test_template_size
            generate_validation_report
            ;;
        package-only)
            load_configuration
            validate_template_package
            validate_template_metadata
            generate_validation_report
            ;;
        performance)
            load_configuration
            validate_template_package
            validate_template_metadata
            validate_rootfs
            test_performance_benchmark
            generate_validation_report
            ;;
    esac
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
fi