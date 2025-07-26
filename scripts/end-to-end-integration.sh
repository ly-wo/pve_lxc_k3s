#!/bin/bash
# End-to-End Integration Test Script
# 端到端集成测试脚本

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载依赖
source "${PROJECT_ROOT}/scripts/logging.sh"
source "${PROJECT_ROOT}/scripts/config-loader.sh"

# 组件名称
COMPONENT="end-to-end-integration"

# 默认配置
DEFAULT_CONFIG_FILE="${PROJECT_ROOT}/config/template.yaml"
DEFAULT_BUILD_DIR="${PROJECT_ROOT}/.build"
DEFAULT_OUTPUT_DIR="${PROJECT_ROOT}/output"
DEFAULT_TEST_DIR="${PROJECT_ROOT}/.test"

# 测试配置
CONFIG_FILE="${CONFIG_FILE:-$DEFAULT_CONFIG_FILE}"
BUILD_DIR="${BUILD_DIR:-$DEFAULT_BUILD_DIR}"
OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
TEST_DIR="${TEST_DIR:-$DEFAULT_TEST_DIR}"

# 测试结果
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# 显示帮助信息
show_help() {
    cat << EOF
端到端集成测试脚本

用法: $0 [选项]

选项:
    --config FILE           指定配置文件 (默认: $DEFAULT_CONFIG_FILE)
    --build-dir DIR         指定构建目录 (默认: $DEFAULT_BUILD_DIR)
    --output-dir DIR        指定输出目录 (默认: $DEFAULT_OUTPUT_DIR)
    --test-dir DIR          指定测试目录 (默认: $DEFAULT_TEST_DIR)
    --verbose               启用详细输出
    --help                  显示此帮助信息

环境变量:
    CONFIG_FILE             配置文件路径
    BUILD_DIR               构建目录
    OUTPUT_DIR              输出目录
    TEST_DIR                测试目录
    DEBUG                   启用调试模式

示例:
    # 运行完整的端到端测试
    $0
    
    # 使用自定义配置
    $0 --config custom-config.yaml
    
    # 启用详细输出
    $0 --verbose

EOF
}

# 初始化测试环境
initialize_test_environment() {
    log_info "$COMPONENT" "初始化端到端测试环境"
    
    # 创建测试目录
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$TEST_DIR"
    
    # 加载配置
    if [[ -f "$CONFIG_FILE" ]]; then
        load_config "$CONFIG_FILE"
        log_info "$COMPONENT" "配置文件加载成功: $CONFIG_FILE"
    else
        log_error "$COMPONENT" "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
    
    log_info "$COMPONENT" "测试环境初始化完成"
}

# 清理测试环境
cleanup_test_environment() {
    log_info "$COMPONENT" "清理测试环境"
    
    # 清理临时文件
    rm -rf "$TEST_DIR" || true
    
    # 清理构建缓存（可选）
    if [[ "${CLEANUP_BUILD:-false}" == "true" ]]; then
        rm -rf "$BUILD_DIR" || true
    fi
    
    log_info "$COMPONENT" "测试环境清理完成"
}

# 运行单个测试
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log_info "$COMPONENT" "运行测试: $test_name"
    
    if $test_function; then
        log_info "$COMPONENT" "✓ 测试通过: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$COMPONENT" "✗ 测试失败: $test_name"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

# 测试 1: 配置验证
test_config_validation() {
    log_info "$COMPONENT" "测试配置验证"
    
    # 测试配置文件验证
    if ! "${PROJECT_ROOT}/scripts/config-validator.sh" validate "$CONFIG_FILE"; then
        log_error "$COMPONENT" "配置文件验证失败"
        return 1
    fi
    
    # 测试配置加载
    local template_name
    template_name=$(get_config "template.name")
    if [[ -z "$template_name" ]]; then
        log_error "$COMPONENT" "无法获取模板名称"
        return 1
    fi
    
    log_info "$COMPONENT" "配置验证测试通过 - 模板名称: $template_name"
    return 0
}

# 测试 2: 基础镜像管理
test_base_image_management() {
    log_info "$COMPONENT" "测试基础镜像管理"
    
    # 设置环境变量
    export CONFIG_FILE="$CONFIG_FILE"
    export BUILD_DIR="$BUILD_DIR"
    export CACHE_DIR="${TEST_DIR}/cache"
    
    # 创建缓存目录
    mkdir -p "$CACHE_DIR"
    
    # 测试基础镜像下载
    if ! "${PROJECT_ROOT}/scripts/base-image-manager.sh" download; then
        log_error "$COMPONENT" "基础镜像下载失败"
        return 1
    fi
    
    log_info "$COMPONENT" "基础镜像管理测试通过"
    return 0
}

# 测试 3: K3s 安装器
test_k3s_installer() {
    log_info "$COMPONENT" "测试 K3s 安装器"
    
    # 设置环境变量
    export CONFIG_FILE="$CONFIG_FILE"
    export BUILD_DIR="$BUILD_DIR"
    
    # 测试 K3s 安装器验证
    if ! "${PROJECT_ROOT}/scripts/k3s-installer.sh" verify; then
        log_error "$COMPONENT" "K3s 安装器验证失败"
        return 1
    fi
    
    log_info "$COMPONENT" "K3s 安装器测试通过"
    return 0
}

# 测试 4: 安全加固
test_security_hardening() {
    log_info "$COMPONENT" "测试安全加固"
    
    # 设置环境变量
    export CONFIG_FILE="$CONFIG_FILE"
    export BUILD_DIR="$BUILD_DIR"
    
    # 测试安全加固验证
    if ! "${PROJECT_ROOT}/scripts/security-hardening.sh" verify; then
        log_error "$COMPONENT" "安全加固验证失败"
        return 1
    fi
    
    log_info "$COMPONENT" "安全加固测试通过"
    return 0
}

# 测试 5: 完整构建流程
test_full_build_process() {
    log_info "$COMPONENT" "测试完整构建流程"
    
    # 设置环境变量
    export CONFIG_FILE="$CONFIG_FILE"
    export BUILD_DIR="$BUILD_DIR"
    export OUTPUT_DIR="$OUTPUT_DIR"
    
    # 清理之前的构建
    rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
    
    # 执行完整构建
    if ! "${PROJECT_ROOT}/scripts/build-template.sh"; then
        log_error "$COMPONENT" "模板构建失败"
        return 1
    fi
    
    # 验证构建输出
    if [[ ! -d "$BUILD_DIR/rootfs" ]]; then
        log_error "$COMPONENT" "构建输出目录不存在"
        return 1
    fi
    
    log_info "$COMPONENT" "完整构建流程测试通过"
    return 0
}

# 测试 6: 模板打包
test_template_packaging() {
    log_info "$COMPONENT" "测试模板打包"
    
    # 设置环境变量
    export CONFIG_FILE="$CONFIG_FILE"
    export BUILD_DIR="$BUILD_DIR"
    export OUTPUT_DIR="$OUTPUT_DIR"
    
    # 执行模板打包
    if ! "${PROJECT_ROOT}/scripts/packager.sh" package; then
        log_error "$COMPONENT" "模板打包失败"
        return 1
    fi
    
    # 验证打包输出
    local template_files
    template_files=$(find "$OUTPUT_DIR" -name "*.tar.gz" -type f)
    
    if [[ -z "$template_files" ]]; then
        log_error "$COMPONENT" "未找到模板文件"
        return 1
    fi
    
    log_info "$COMPONENT" "模板打包测试通过"
    return 0
}

# 测试 7: 模板验证
test_template_validation() {
    log_info "$COMPONENT" "测试模板验证"
    
    # 设置环境变量
    export OUTPUT_DIR="$OUTPUT_DIR"
    
    # 执行模板验证
    if ! "${PROJECT_ROOT}/scripts/template-validator.sh" validate; then
        log_error "$COMPONENT" "模板验证失败"
        return 1
    fi
    
    log_info "$COMPONENT" "模板验证测试通过"
    return 0
}

# 测试 8: 系统优化
test_system_optimization() {
    log_info "$COMPONENT" "测试系统优化"
    
    # 设置环境变量
    export CONFIG_FILE="$CONFIG_FILE"
    export BUILD_DIR="$BUILD_DIR"
    
    # 测试系统优化验证
    if ! "${PROJECT_ROOT}/scripts/system-optimizer.sh" verify; then
        log_error "$COMPONENT" "系统优化验证失败"
        return 1
    fi
    
    log_info "$COMPONENT" "系统优化测试通过"
    return 0
}

# 测试 9: 日志系统
test_logging_system() {
    log_info "$COMPONENT" "测试日志系统"
    
    # 测试日志功能
    local test_log_file="${TEST_DIR}/test.log"
    export LOG_FILE="$test_log_file"
    
    # 测试各种日志级别
    log_debug "$COMPONENT" "调试消息测试"
    log_info "$COMPONENT" "信息消息测试"
    log_warn "$COMPONENT" "警告消息测试"
    log_error "$COMPONENT" "错误消息测试"
    
    # 验证日志文件
    if [[ -f "$test_log_file" ]]; then
        log_info "$COMPONENT" "日志文件创建成功"
    else
        log_error "$COMPONENT" "日志文件创建失败"
        return 1
    fi
    
    log_info "$COMPONENT" "日志系统测试通过"
    return 0
}

# 测试 10: 监控和诊断
test_monitoring_diagnostics() {
    log_info "$COMPONENT" "测试监控和诊断"
    
    # 测试系统诊断
    if ! "${PROJECT_ROOT}/scripts/system-diagnostics.sh" basic; then
        log_error "$COMPONENT" "系统诊断失败"
        return 1
    fi
    
    # 测试监控脚本
    if ! "${PROJECT_ROOT}/scripts/monitoring.sh" --help >/dev/null; then
        log_error "$COMPONENT" "监控脚本不可用"
        return 1
    fi
    
    log_info "$COMPONENT" "监控和诊断测试通过"
    return 0
}

# 生成测试报告
generate_test_report() {
    local report_file="${TEST_DIR}/end-to-end-test-report.md"
    
    log_info "$COMPONENT" "生成端到端测试报告: $report_file"
    
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
# 端到端集成测试报告

## 测试概要

- **测试时间**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
- **测试环境**: $(uname -a)
- **配置文件**: $CONFIG_FILE
- **构建目录**: $BUILD_DIR
- **输出目录**: $OUTPUT_DIR

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

- [x] 配置验证
- [x] 基础镜像管理
- [x] K3s 安装器
- [x] 安全加固
- [x] 完整构建流程
- [x] 模板打包
- [x] 模板验证
- [x] 系统优化
- [x] 日志系统
- [x] 监控和诊断

## 建议

EOF
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "所有端到端测试通过，系统集成良好。" >> "$report_file"
    else
        echo "发现 $TESTS_FAILED 个失败测试，需要修复后再次运行。" >> "$report_file"
    fi
    
    log_info "$COMPONENT" "端到端测试报告生成完成"
}

# 主函数
main() {
    log_info "$COMPONENT" "=========================================="
    log_info "$COMPONENT" "开始端到端集成测试"
    log_info "$COMPONENT" "=========================================="
    
    # 设置错误处理
    trap cleanup_test_environment EXIT
    
    # 初始化测试环境
    initialize_test_environment
    
    # 运行所有测试
    run_test "配置验证" test_config_validation
    run_test "基础镜像管理" test_base_image_management
    run_test "K3s安装器" test_k3s_installer
    run_test "安全加固" test_security_hardening
    run_test "完整构建流程" test_full_build_process
    run_test "模板打包" test_template_packaging
    run_test "模板验证" test_template_validation
    run_test "系统优化" test_system_optimization
    run_test "日志系统" test_logging_system
    run_test "监控和诊断" test_monitoring_diagnostics
    
    # 生成测试报告
    generate_test_report
    
    # 输出测试结果
    log_info "$COMPONENT" "=========================================="
    log_info "$COMPONENT" "端到端集成测试完成"
    log_info "$COMPONENT" "通过: $TESTS_PASSED, 失败: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "$COMPONENT" "✓ 所有端到端测试通过"
        log_info "$COMPONENT" "=========================================="
        return 0
    else
        log_error "$COMPONENT" "✗ 发现 $TESTS_FAILED 个失败测试"
        log_error "$COMPONENT" "失败测试: ${FAILED_TESTS[*]}"
        log_error "$COMPONENT" "=========================================="
        return 1
    fi
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --build-dir)
                BUILD_DIR="$2"
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
            --verbose)
                export LOG_LEVEL=DEBUG
                shift
                ;;
            --help|-h)
                show_help
                exit 0
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