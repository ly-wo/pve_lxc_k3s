#!/usr/bin/env bats
# Unit tests for template validator functionality

# Setup test environment
setup() {
    # Get the project root directory
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    
    # Source the script
    source "$PROJECT_ROOT/scripts/template-validator.sh"
    
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    
    # Override directories for testing
    CONFIG_FILE="$TEST_DIR/template.yaml"
    LOG_DIR="$TEST_DIR/logs"
    OUTPUT_DIR="$TEST_DIR/output"
    TEST_DIR_OVERRIDE="$TEST_DIR/.test"
    
    # Create directories
    mkdir -p "$LOG_DIR" "$OUTPUT_DIR" "$TEST_DIR_OVERRIDE"
    
    # Override global variables
    LOG_FILE="$LOG_DIR/template-validator.log"
    VALIDATION_LOG="$LOG_DIR/validation-$(date +%Y%m%d-%H%M%S).log"
    
    # Create test configuration file
    cat > "$CONFIG_FILE" << 'EOF'
template:
  name: "alpine-k3s"
  version: "1.0.0"
  architecture: "amd64"
  description: "Test Alpine K3s template"

k3s:
  version: "v1.28.4+k3s1"
  cluster_init: true

system:
  timezone: "UTC"
  packages:
    - curl
    - wget
EOF
    
    # Reset test counters
    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TEST_RESULTS=()
    
    # Create mock template package
    create_mock_template_package
}

# Cleanup test environment
teardown() {
    rm -rf "$TEST_DIR"
}

# Helper function to create mock template package
create_mock_template_package() {
    local template_filename="alpine-k3s-1.0.0-amd64.tar.gz"
    local template_package="$OUTPUT_DIR/$template_filename"
    local temp_build="$TEST_DIR/build"
    
    mkdir -p "$temp_build"
    
    # Create mock files
    echo "mock config content" > "$temp_build/config"
    echo "#!/bin/bash" > "$temp_build/template"
    chmod +x "$temp_build/template"
    
    # Create mock manifest.json
    cat > "$temp_build/manifest.json" << 'EOF'
{
  "template": {
    "name": "alpine-k3s",
    "version": "1.0.0",
    "architecture": "amd64",
    "description": "Test Alpine K3s template"
  },
  "k3s": {
    "version": "v1.28.4+k3s1"
  },
  "build": {
    "timestamp": "2024-01-01T00:00:00Z",
    "builder": "test"
  }
}
EOF
    
    # Create mock rootfs
    local rootfs_dir="$temp_build/rootfs"
    mkdir -p "$rootfs_dir/bin" "$rootfs_dir/etc" "$rootfs_dir/usr/local/bin" "$rootfs_dir/etc/rancher/k3s" "$rootfs_dir/lib/systemd/system"
    
    echo "#!/bin/sh" > "$rootfs_dir/usr/local/bin/k3s"
    chmod +x "$rootfs_dir/usr/local/bin/k3s"
    
    echo "cluster-init: true" > "$rootfs_dir/etc/rancher/k3s/config.yaml"
    echo "[Unit]" > "$rootfs_dir/lib/systemd/system/k3s.service"
    echo "Template: alpine-k3s" > "$rootfs_dir/etc/lxc-template-info"
    
    # Create rootfs.tar.gz
    (cd "$temp_build" && tar -czf rootfs.tar.gz -C rootfs .)
    
    # Create template package
    (cd "$temp_build" && tar -czf "$template_package" config template manifest.json rootfs.tar.gz)
    
    # Create checksum
    (cd "$OUTPUT_DIR" && sha256sum "$template_filename" > "${template_filename}.sha256")
}

# Test logging functions
@test "log_info should write info messages with timestamp" {
    run log_info "Test info message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "INFO" ]]
    [[ "$output" =~ "Test info message" ]]
    [[ "$output" =~ "[0-9]{4}-[0-9]{2}-[0-9]{2}" ]]
    
    # Check log files
    [ -f "$LOG_FILE" ]
    [ -f "$VALIDATION_LOG" ]
    grep -q "INFO.*Test info message" "$LOG_FILE"
}

@test "log_error should write error messages" {
    run log_error "Test error message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "Test error message" ]]
}

@test "log_debug should write debug messages when debug enabled" {
    DEBUG=true
    
    run log_debug "Test debug message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DEBUG" ]]
    [[ "$output" =~ "Test debug message" ]]
}

@test "log_debug should not write when debug disabled" {
    DEBUG=false
    
    run log_debug "Test debug message"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "DEBUG" ]]
}

# Test test tracking functions
@test "test_start should increment test counter" {
    local initial_total=$TESTS_TOTAL
    
    run test_start "Sample test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "🧪 开始测试: Sample test" ]]
    
    [ $TESTS_TOTAL -eq $((initial_total + 1)) ]
}

@test "test_pass should increment passed counter and record result" {
    local initial_passed=$TESTS_PASSED
    
    run test_pass "Sample test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ 测试通过: Sample test" ]]
    
    [ $TESTS_PASSED -eq $((initial_passed + 1)) ]
    [[ "${TEST_RESULTS[*]}" =~ "✅ PASS: Sample test" ]]
}

@test "test_fail should increment failed counter and record result" {
    local initial_failed=$TESTS_FAILED
    
    run test_fail "Sample test" "Test reason"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "❌ 测试失败: Sample test - Test reason" ]]
    
    [ $TESTS_FAILED -eq $((initial_failed + 1)) ]
    [[ "${TEST_RESULTS[*]}" =~ "❌ FAIL: Sample test - Test reason" ]]
}

# Test configuration loading
@test "load_configuration should load config successfully" {
    run load_configuration
    [ "$status" -eq 0 ]
    [[ "$output" =~ "加载配置文件" ]]
    [[ "$output" =~ "配置加载完成" ]]
    
    # Check loaded variables
    [ "$TEMPLATE_NAME" = "alpine-k3s" ]
    [ "$TEMPLATE_VERSION" = "1.0.0" ]
    [ "$ARCHITECTURE" = "amd64" ]
    [ "$K3S_VERSION" = "v1.28.4+k3s1" ]
}

@test "load_configuration should fail with missing config file" {
    CONFIG_FILE="/nonexistent/config.yaml"
    
    run load_configuration
    [ "$status" -eq 1 ]
    [[ "$output" =~ "配置文件不存在" ]]
}

@test "load_configuration should fail with missing K3s version" {
    # Create config without K3s version
    cat > "$CONFIG_FILE" << 'EOF'
template:
  name: "test-template"
  version: "1.0.0"
EOF
    
    run load_configuration
    [ "$status" -eq 1 ]
    [[ "$output" =~ "K3s 版本未在配置中指定" ]]
}

@test "load_configuration should work without yq using fallback parsing" {
    # Mock yq to not exist
    mkdir -p "$TEST_DIR/bin"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run load_configuration
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置加载完成" ]]
}

# Test template package validation
@test "validate_template_package should pass with valid package" {
    run validate_template_package
    [ "$status" -eq 0 ]
    
    # Check test was recorded
    [[ "${TEST_RESULTS[*]}" =~ "✅ PASS: 模板包完整性验证" ]]
}

@test "validate_template_package should fail with missing package" {
    # Remove template package
    rm -f "$OUTPUT_DIR/alpine-k3s-1.0.0-amd64.tar.gz"
    
    run validate_template_package
    [ "$status" -eq 1 ]
    
    # Check test failure was recorded
    [[ "${TEST_RESULTS[*]}" =~ "❌ FAIL: 模板包完整性验证" ]]
}

@test "validate_template_package should fail with corrupted package" {
    # Create corrupted package
    echo "corrupted data" > "$OUTPUT_DIR/alpine-k3s-1.0.0-amd64.tar.gz"
    
    run validate_template_package
    [ "$status" -eq 1 ]
    [[ "${TEST_RESULTS[*]}" =~ "模板包损坏或格式错误" ]]
}

@test "validate_template_package should fail with missing required files" {
    # Create package without required files
    local temp_build="$TEST_DIR/build_invalid"
    mkdir -p "$temp_build"
    echo "incomplete" > "$temp_build/incomplete"
    (cd "$temp_build" && tar -czf "$OUTPUT_DIR/alpine-k3s-1.0.0-amd64.tar.gz" incomplete)
    
    run validate_template_package
    [ "$status" -eq 1 ]
    [[ "${TEST_RESULTS[*]}" =~ "缺少必要文件" ]]
}

@test "validate_template_package should validate checksum if present" {
    # Create invalid checksum
    echo "invalid_checksum  alpine-k3s-1.0.0-amd64.tar.gz" > "$OUTPUT_DIR/alpine-k3s-1.0.0-amd64.tar.gz.sha256"
    
    run validate_template_package
    [ "$status" -eq 1 ]
    [[ "${TEST_RESULTS[*]}" =~ "校验和验证失败" ]]
}

# Test template metadata validation
@test "validate_template_metadata should pass with valid metadata" {
    run validate_template_metadata
    [ "$status" -eq 0 ]
    [[ "${TEST_RESULTS[*]}" =~ "✅ PASS: 模板元数据验证" ]]
}

@test "validate_template_metadata should fail with missing config file" {
    # Create package without config file
    local temp_build="$TEST_DIR/build_no_config"
    mkdir -p "$temp_build"
    echo "#!/bin/bash" > "$temp_build/template"
    chmod +x "$temp_build/template"
    echo "{}" > "$temp_build/manifest.json"
    echo "dummy" > "$temp_build/rootfs.tar.gz"
    (cd "$temp_build" && tar -czf "$OUTPUT_DIR/alpine-k3s-1.0.0-amd64.tar.gz" template manifest.json rootfs.tar.gz)
    
    run validate_template_metadata
    [ "$status" -eq 1 ]
    [[ "${TEST_RESULTS[*]}" =~ "配置文件不存在" ]]
}

@test "validate_template_metadata should fail with invalid JSON manifest" {
    # Create package with invalid JSON
    local temp_build="$TEST_DIR/build_invalid_json"
    mkdir -p "$temp_build"
    echo "mock config" > "$temp_build/config"
    echo "#!/bin/bash" > "$temp_build/template"
    chmod +x "$temp_build/template"
    echo "invalid json {" > "$temp_build/manifest.json"
    echo "dummy" > "$temp_build/rootfs.tar.gz"
    (cd "$temp_build" && tar -czf "$OUTPUT_DIR/alpine-k3s-1.0.0-amd64.tar.gz" config template manifest.json rootfs.tar.gz)
    
    # Mock jq command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/jq" << 'EOF'
#!/bin/bash
if [ "$1" = "empty" ]; then
    exit 1  # Simulate invalid JSON
fi
exit 0
EOF
    chmod +x "$TEST_DIR/bin/jq"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run validate_template_metadata
    [ "$status" -eq 1 ]
    [[ "${TEST_RESULTS[*]}" =~ "清单文件格式错误" ]]
}

# Test rootfs validation
@test "validate_rootfs should pass with valid rootfs" {
    run validate_rootfs
    [ "$status" -eq 0 ]
    [[ "${TEST_RESULTS[*]}" =~ "✅ PASS: 根文件系统验证" ]]
}

@test "validate_rootfs should fail with missing K3s binary" {
    # Create rootfs without K3s binary
    local temp_build="$TEST_DIR/build_no_k3s"
    mkdir -p "$temp_build/rootfs/bin" "$temp_build/rootfs/etc"
    echo "dummy rootfs" > "$temp_build/rootfs/bin/sh"
    (cd "$temp_build" && tar -czf rootfs.tar.gz -C rootfs .)
    
    echo "config" > "$temp_build/config"
    echo "#!/bin/bash" > "$temp_build/template"
    chmod +x "$temp_build/template"
    echo "{}" > "$temp_build/manifest.json"
    (cd "$temp_build" && tar -czf "$OUTPUT_DIR/alpine-k3s-1.0.0-amd64.tar.gz" config template manifest.json rootfs.tar.gz)
    
    run validate_rootfs
    [ "$status" -eq 1 ]
    [[ "${TEST_RESULTS[*]}" =~ "K3s 二进制文件不存在或不可执行" ]]
}

# Test template size optimization
@test "test_template_size should pass with reasonable size" {
    run test_template_size
    [ "$status" -eq 0 ]
    [[ "${TEST_RESULTS[*]}" =~ "✅ PASS: 模板大小优化测试" ]]
}

@test "test_template_size should fail with oversized template" {
    # Create a large dummy file to simulate oversized template
    dd if=/dev/zero of="$OUTPUT_DIR/alpine-k3s-1.0.0-amd64.tar.gz" bs=1M count=600 2>/dev/null
    
    run test_template_size
    [ "$status" -eq 1 ]
    [[ "${TEST_RESULTS[*]}" =~ "模板包过大" ]]
}

# Test K3s functionality (mocked)
@test "test_k3s_functionality should skip when Docker unavailable" {
    # Mock docker command to not exist
    mkdir -p "$TEST_DIR/bin"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run test_k3s_functionality
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Docker 不可用，跳过 K3s 功能测试" ]]
}

@test "test_k3s_functionality should skip when Docker daemon unavailable" {
    # Mock docker command that fails on info
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/docker" << 'EOF'
#!/bin/bash
if [ "$1" = "info" ]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$TEST_DIR/bin/docker"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run test_k3s_functionality
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Docker 守护进程不可用，跳过 K3s 功能测试" ]]
}

@test "test_k3s_functionality should pass with successful Docker test" {
    # Mock docker commands
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/docker" << 'EOF'
#!/bin/bash
case "$1" in
    "info") exit 0 ;;
    "build") 
        echo "Building test image..."
        exit 0 ;;
    "run")
        echo "=== K3s 功能测试开始 ==="
        echo "检查 K3s 二进制文件..."
        echo "✓ K3s 版本: v1.28.4+k3s1"
        echo "✓ kubeconfig 文件存在"
        echo "✓ API 服务器就绪"
        echo "✓ 节点状态正常"
        echo "✓ 系统 Pod 运行正常"
        echo "=== K3s 功能测试完成 ==="
        exit 0 ;;
    "rmi") exit 0 ;;
esac
exit 1
EOF
    chmod +x "$TEST_DIR/bin/docker"
    
    # Mock timeout command
    cat > "$TEST_DIR/bin/timeout" << 'EOF'
#!/bin/bash
shift  # Remove timeout value
exec "$@"
EOF
    chmod +x "$TEST_DIR/bin/timeout"
    
    export PATH="$TEST_DIR/bin:$PATH"
    
    run test_k3s_functionality
    [ "$status" -eq 0 ]
    [[ "${TEST_RESULTS[*]}" =~ "✅ PASS: K3s 功能测试" ]]
}

@test "test_k3s_functionality should fail with Docker test failure" {
    # Mock docker commands with failure
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/docker" << 'EOF'
#!/bin/bash
case "$1" in
    "info") exit 0 ;;
    "build") exit 0 ;;
    "run")
        echo "ERROR: K3s 启动失败"
        exit 1 ;;
    "rmi") exit 0 ;;
esac
exit 1
EOF
    chmod +x "$TEST_DIR/bin/docker"
    
    cat > "$TEST_DIR/bin/timeout" << 'EOF'
#!/bin/bash
shift
exec "$@"
EOF
    chmod +x "$TEST_DIR/bin/timeout"
    
    export PATH="$TEST_DIR/bin:$PATH"
    
    run test_k3s_functionality
    [ "$status" -eq 1 ]
    [[ "${TEST_RESULTS[*]}" =~ "❌ FAIL: K3s 功能测试" ]]
}

# Test performance benchmark
@test "test_performance_benchmark should measure extraction times" {
    run test_performance_benchmark
    [ "$status" -eq 0 ]
    [[ "$output" =~ "测试模板解压性能" ]]
    [[ "$output" =~ "模板解压时间:" ]]
    [[ "$output" =~ "根文件系统解压时间:" ]]
    [[ "$output" =~ "根文件系统文件数量:" ]]
    [[ "${TEST_RESULTS[*]}" =~ "✅ PASS: 性能基准测试" ]]
}

# Test validation report generation
@test "generate_validation_report should create report file" {
    # Set up some test results
    TESTS_TOTAL=5
    TESTS_PASSED=4
    TESTS_FAILED=1
    TEST_RESULTS=("✅ PASS: Test 1" "❌ FAIL: Test 2" "✅ PASS: Test 3")
    
    run generate_validation_report
    [ "$status" -eq 0 ]
    [[ "$output" =~ "生成验证报告" ]]
    [[ "$output" =~ "验证报告生成完成" ]]
    
    # Check report file exists
    [ -f "$OUTPUT_DIR/validation-report.txt" ]
    
    # Check report content
    local report_content
    report_content=$(cat "$OUTPUT_DIR/validation-report.txt")
    [[ "$report_content" =~ "PVE LXC K3s Template Validation Report" ]]
    [[ "$report_content" =~ "Template Name: alpine-k3s" ]]
    [[ "$report_content" =~ "Total Tests: 5" ]]
    [[ "$report_content" =~ "Passed: 4" ]]
    [[ "$report_content" =~ "Failed: 1" ]]
    [[ "$report_content" =~ "Success Rate: 80%" ]]
}

# Test cleanup function
@test "cleanup_test_environment should clean up test resources" {
    # Set up test container ID
    TEST_CONTAINER_ID="test-container-123"
    
    # Mock docker commands
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/docker" << 'EOF'
#!/bin/bash
case "$1" in
    "stop") echo "Stopping container $2"; exit 0 ;;
    "rm") echo "Removing container $2"; exit 0 ;;
esac
exit 1
EOF
    chmod +x "$TEST_DIR/bin/docker"
    export PATH="$TEST_DIR/bin:$PATH"
    
    # Create temp files
    mkdir -p "$TEST_DIR_OVERRIDE/temp"
    touch "$TEST_DIR_OVERRIDE/temp/test-file"
    
    run cleanup_test_environment
    [ "$status" -eq 0 ]
    [[ "$output" =~ "清理测试环境" ]]
    [[ "$output" =~ "停止测试容器: test-container-123" ]]
    [[ "$output" =~ "测试环境清理完成" ]]
    
    # Check temp files were removed
    [ ! -d "$TEST_DIR_OVERRIDE/temp" ]
}

# Test main validation function
@test "main function should execute all validation steps" {
    # Mock all validation functions to succeed
    load_configuration() { 
        TEMPLATE_NAME="alpine-k3s"
        TEMPLATE_VERSION="1.0.0"
        ARCHITECTURE="amd64"
        K3S_VERSION="v1.28.4+k3s1"
        echo "Configuration loaded"
    }
    validate_template_package() { test_pass "模板包完整性验证"; }
    validate_template_metadata() { test_pass "模板元数据验证"; }
    validate_rootfs() { test_pass "根文件系统验证"; }
    test_template_size() { test_pass "模板大小优化测试"; }
    test_k3s_functionality() { test_pass "K3s 功能测试"; }
    test_performance_benchmark() { test_pass "性能基准测试"; }
    generate_validation_report() { echo "Report generated"; }
    
    run main
    [ "$status" -eq 0 ]
    [[ "$output" =~ "PVE LXC K3s Template Validator 开始验证" ]]
    [[ "$output" =~ "验证完成" ]]
    [[ "$output" =~ "✅ 所有验证测试通过" ]]
}

@test "main function should return error code when tests fail" {
    # Mock functions with one failure
    load_configuration() { 
        TEMPLATE_NAME="alpine-k3s"
        TEMPLATE_VERSION="1.0.0"
        ARCHITECTURE="amd64"
        K3S_VERSION="v1.28.4+k3s1"
        echo "Configuration loaded"
    }
    validate_template_package() { test_pass "模板包完整性验证"; }
    validate_template_metadata() { test_fail "模板元数据验证" "测试失败"; }
    validate_rootfs() { test_pass "根文件系统验证"; }
    test_template_size() { test_pass "模板大小优化测试"; }
    test_k3s_functionality() { test_pass "K3s 功能测试"; }
    test_performance_benchmark() { test_pass "性能基准测试"; }
    generate_validation_report() { echo "Report generated"; }
    
    run main
    [ "$status" -eq 1 ]
    [[ "$output" =~ "❌ 验证测试失败: 1 个测试未通过" ]]
}

# Test command line argument parsing
@test "parse_arguments should handle validate command" {
    main() { echo "Running full validation"; return 0; }
    
    run parse_arguments validate
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Running full validation" ]]
}

@test "parse_arguments should handle quick command" {
    load_configuration() { echo "Config loaded"; }
    validate_template_package() { echo "Package validated"; }
    validate_template_metadata() { echo "Metadata validated"; }
    validate_rootfs() { echo "Rootfs validated"; }
    test_template_size() { echo "Size tested"; }
    generate_validation_report() { echo "Report generated"; }
    
    run parse_arguments quick
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Config loaded" ]]
    [[ "$output" =~ "Package validated" ]]
    [[ ! "$output" =~ "K3s 功能测试" ]]
}

@test "parse_arguments should handle package-only command" {
    load_configuration() { echo "Config loaded"; }
    validate_template_package() { echo "Package validated"; }
    validate_template_metadata() { echo "Metadata validated"; }
    generate_validation_report() { echo "Report generated"; }
    
    run parse_arguments package-only
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Package validated" ]]
    [[ "$output" =~ "Metadata validated" ]]
    [[ ! "$output" =~ "根文件系统验证" ]]
}

@test "parse_arguments should handle performance command" {
    load_configuration() { echo "Config loaded"; }
    validate_template_package() { echo "Package validated"; }
    validate_template_metadata() { echo "Metadata validated"; }
    validate_rootfs() { echo "Rootfs validated"; }
    test_performance_benchmark() { echo "Performance tested"; }
    generate_validation_report() { echo "Report generated"; }
    
    run parse_arguments performance
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Performance tested" ]]
}

@test "parse_arguments should handle --config option" {
    main() { echo "Config file: $CONFIG_FILE"; return 0; }
    
    run parse_arguments --config /custom/config.yaml validate
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Config file: /custom/config.yaml" ]]
}

@test "parse_arguments should handle --debug option" {
    main() { echo "Debug: $DEBUG"; return 0; }
    
    run parse_arguments --debug validate
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Debug: true" ]]
}

@test "parse_arguments should handle --help option" {
    run parse_arguments --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "PVE LXC K3s Template Validator" ]]
    [[ "$output" =~ "用法:" ]]
    [[ "$output" =~ "validate" ]]
    [[ "$output" =~ "quick" ]]
}

@test "parse_arguments should handle unknown option" {
    run parse_arguments --unknown-option
    [ "$status" -eq 1 ]
    [[ "$output" =~ "未知选项: --unknown-option" ]]
}

# Test show_help function
@test "show_help should display usage information" {
    run show_help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "PVE LXC K3s Template Validator" ]]
    [[ "$output" =~ "用法:" ]]
    [[ "$output" =~ "命令:" ]]
    [[ "$output" =~ "选项:" ]]
    [[ "$output" =~ "环境变量:" ]]
    [[ "$output" =~ "示例:" ]]
}