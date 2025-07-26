#!/usr/bin/env bats
# End-to-End BATS tests for complete template generation workflow

# Setup test environment
setup() {
    # Get the project root directory
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    
    # Set up test environment variables
    export TEST_CONFIG_FILE="$TEST_DIR/test-config.yaml"
    export TEST_BUILD_DIR="$TEST_DIR/build"
    export TEST_OUTPUT_DIR="$TEST_DIR/output"
    export TEST_CACHE_DIR="$TEST_DIR/cache"
    
    # Create test directories
    mkdir -p "$TEST_BUILD_DIR" "$TEST_OUTPUT_DIR" "$TEST_CACHE_DIR"
    
    # Create comprehensive test configuration
    cat > "$TEST_CONFIG_FILE" << 'EOF'
template:
  name: "e2e-test-alpine-k3s"
  version: "1.0.0-e2e"
  description: "End-to-end test template"
  author: "E2E Test Suite"
  base_image: "alpine:3.18"
  architecture: "amd64"

k3s:
  version: "v1.28.4+k3s1"
  install_options:
    - "--disable=traefik"
    - "--disable=servicelb"
    - "--node-taint=CriticalAddonsOnly=true:NoExecute"
  cluster_init: true
  server_options:
    - "--node-label=node-type=server"
  agent_options:
    - "--node-label=node-type=agent"

system:
  timezone: "UTC"
  locale: "en_US.UTF-8"
  packages:
    - curl
    - wget
    - ca-certificates
    - openssl
  remove_packages:
    - apk-tools-doc
    - man-pages

security:
  disable_root_login: true
  create_k3s_user: true
  k3s_user: "k3s"
  k3s_uid: 1000
  k3s_gid: 1000
  firewall_rules:
    - "6443/tcp"
    - "10250/tcp"
    - "8472/udp"

build:
  cleanup_after_install: true
  optimize_size: true
  parallel_jobs: 2
EOF
}

# Cleanup test environment
teardown() {
    # Clean up test directory
    rm -rf "$TEST_DIR"
    
    # Clean up any leftover processes or mounts
    cleanup_test_processes
}

# Helper function to clean up test processes
cleanup_test_processes() {
    # Kill any background processes started during tests
    jobs -p | xargs -r kill 2>/dev/null || true
    
    # Unmount any test mount points
    if mountpoint -q "$TEST_BUILD_DIR/rootfs" 2>/dev/null; then
        umount "$TEST_BUILD_DIR/rootfs" || true
    fi
}

# Test complete workflow integration
@test "complete workflow runs without errors" {
    # Set environment variables for scripts
    export CONFIG_FILE="$TEST_CONFIG_FILE"
    export BUILD_DIR="$TEST_BUILD_DIR"
    export OUTPUT_DIR="$TEST_OUTPUT_DIR"
    export CACHE_DIR="$TEST_CACHE_DIR"
    export INTEGRATION_TEST_MODE=true
    
    # Test configuration validation
    run "$PROJECT_ROOT/scripts/config-validator.sh" validate "$TEST_CONFIG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Configuration validation passed" ]]
    
    # Test configuration loading
    source "$PROJECT_ROOT/scripts/config-loader.sh"
    run load_config "$TEST_CONFIG_FILE"
    [ "$status" -eq 0 ]
    
    # Verify configuration values
    template_name=$(get_config "template.name")
    [ "$template_name" = "e2e-test-alpine-k3s" ]
    
    k3s_version=$(get_config "k3s.version")
    [ "$k3s_version" = "v1.28.4+k3s1" ]
}

# Test all scripts exist and are executable
@test "all required scripts exist and are executable" {
    local required_scripts=(
        "build-template.sh"
        "config-loader.sh"
        "config-validator.sh"
        "base-image-manager.sh"
        "k3s-installer.sh"
        "k3s-service.sh"
        "k3s-cluster.sh"
        "k3s-security.sh"
        "security-hardening.sh"
        "system-optimizer.sh"
        "packager.sh"
        "template-validator.sh"
        "monitoring.sh"
        "logging.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        [ -f "$PROJECT_ROOT/scripts/$script" ]
        [ -x "$PROJECT_ROOT/scripts/$script" ]
    done
}

# Test configuration schema validation
@test "configuration schema validation works correctly" {
    # Test valid configuration
    run "$PROJECT_ROOT/scripts/config-validator.sh" validate "$TEST_CONFIG_FILE"
    [ "$status" -eq 0 ]
    
    # Test invalid configuration
    local invalid_config="$TEST_DIR/invalid-config.yaml"
    cat > "$invalid_config" << 'EOF'
template:
  name: "test"
  version: "invalid-version-format"
  base_image: "ubuntu:20.04"  # Invalid base image
k3s:
  version: "invalid-k3s-version"
EOF
    
    run "$PROJECT_ROOT/scripts/config-validator.sh" validate "$invalid_config"
    [ "$status" -ne 0 ]
}

# Test base image management workflow
@test "base image management workflow works" {
    export CONFIG_FILE="$TEST_CONFIG_FILE"
    export BUILD_DIR="$TEST_BUILD_DIR"
    export CACHE_DIR="$TEST_CACHE_DIR"
    export INTEGRATION_TEST_MODE=true
    
    # Test base image manager help
    run "$PROJECT_ROOT/scripts/base-image-manager.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Base Image Manager" ]]
    
    # Test download command (in test mode)
    run "$PROJECT_ROOT/scripts/base-image-manager.sh" download
    [ "$status" -eq 0 ]
    
    # Verify cache directory structure
    [ -d "$TEST_CACHE_DIR/images" ]
}

# Test K3s installer workflow
@test "K3s installer workflow works" {
    export CONFIG_FILE="$TEST_CONFIG_FILE"
    export BUILD_DIR="$TEST_BUILD_DIR"
    export INTEGRATION_TEST_MODE=true
    
    # Create mock rootfs environment
    mkdir -p "$TEST_BUILD_DIR/rootfs"/{bin,etc,usr/local/bin,var/lib/rancher/k3s}
    
    # Test K3s installer help
    run "$PROJECT_ROOT/scripts/k3s-installer.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s Installer" ]]
    
    # Test version validation
    run "$PROJECT_ROOT/scripts/k3s-installer.sh" verify
    [ "$status" -eq 0 ]
}

# Test security hardening workflow
@test "security hardening workflow works" {
    export CONFIG_FILE="$TEST_CONFIG_FILE"
    export BUILD_DIR="$TEST_BUILD_DIR"
    export INTEGRATION_TEST_MODE=true
    
    # Create mock environment
    mkdir -p "$TEST_BUILD_DIR/rootfs"/{etc,usr/sbin,home}
    
    # Test security hardening help
    run "$PROJECT_ROOT/scripts/security-hardening.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Security Hardening" ]]
    
    # Test verification
    run "$PROJECT_ROOT/scripts/security-hardening.sh" verify
    [ "$status" -eq 0 ]
}

# Test packaging workflow
@test "packaging workflow works" {
    export CONFIG_FILE="$TEST_CONFIG_FILE"
    export BUILD_DIR="$TEST_BUILD_DIR"
    export OUTPUT_DIR="$TEST_OUTPUT_DIR"
    export INTEGRATION_TEST_MODE=true
    
    # Create mock build output
    mkdir -p "$TEST_BUILD_DIR/rootfs"/{bin,etc,usr,var}
    echo "Mock rootfs content" > "$TEST_BUILD_DIR/rootfs/etc/mock-file"
    
    # Test packager help
    run "$PROJECT_ROOT/scripts/packager.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Template Packager" ]]
    
    # Test info command
    run "$PROJECT_ROOT/scripts/packager.sh" info
    [ "$status" -eq 0 ]
    
    # Test package command
    run "$PROJECT_ROOT/scripts/packager.sh" package
    [ "$status" -eq 0 ]
    
    # Verify output file exists
    [ -f "$TEST_OUTPUT_DIR/e2e-test-alpine-k3s-1.0.0-e2e.tar.gz" ]
}

# Test template validation workflow
@test "template validation workflow works" {
    export OUTPUT_DIR="$TEST_OUTPUT_DIR"
    export INTEGRATION_TEST_MODE=true
    
    # Ensure we have a template package from previous test
    if [ ! -f "$TEST_OUTPUT_DIR/e2e-test-alpine-k3s-1.0.0-e2e.tar.gz" ]; then
        # Create a mock template package
        mkdir -p "$TEST_OUTPUT_DIR"
        tar -czf "$TEST_OUTPUT_DIR/e2e-test-alpine-k3s-1.0.0-e2e.tar.gz" -C "$TEST_DIR" --files-from=/dev/null
    fi
    
    # Test validator help
    run "$PROJECT_ROOT/scripts/template-validator.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Template Validator" ]]
    
    # Test package validation
    run "$PROJECT_ROOT/scripts/template-validator.sh" package-only
    [ "$status" -eq 0 ]
}

# Test monitoring and logging integration
@test "monitoring and logging integration works" {
    export LOG_DIR="$TEST_DIR/logs"
    mkdir -p "$LOG_DIR"
    
    # Test logging functions
    source "$PROJECT_ROOT/scripts/logging.sh"
    
    # Test log functions
    run log_info "test-component" "Test info message"
    [ "$status" -eq 0 ]
    
    run log_error "test-component" "Test error message"
    [ "$status" -eq 0 ]
    
    # Test monitoring script
    run "$PROJECT_ROOT/scripts/monitoring.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Monitoring" ]]
}

# Test system diagnostics
@test "system diagnostics work correctly" {
    export LOG_DIR="$TEST_DIR/logs"
    mkdir -p "$LOG_DIR"
    
    # Test system diagnostics script
    run "$PROJECT_ROOT/scripts/system-diagnostics.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "System Diagnostics" ]]
    
    # Test basic diagnostics
    run "$PROJECT_ROOT/scripts/system-diagnostics.sh" basic
    [ "$status" -eq 0 ]
}

# Test health check functionality
@test "health check functionality works" {
    export CONFIG_FILE="$TEST_CONFIG_FILE"
    export INTEGRATION_TEST_MODE=true
    
    # Test K3s health check script
    run "$PROJECT_ROOT/scripts/k3s-health-check.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s Health Check" ]]
    
    # Test simple health check
    run "$PROJECT_ROOT/scripts/k3s-health-check-simple.sh" --help
    [ "$status" -eq 0 ]
}

# Test Makefile integration
@test "Makefile targets work correctly" {
    cd "$PROJECT_ROOT"
    
    # Test help target
    run make help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Available targets" ]]
    
    # Test version target
    run make version
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Template:" ]]
    
    # Test validate-config target
    run make validate-config
    [ "$status" -eq 0 ]
    
    # Test lint target (if shellcheck is available)
    if command -v shellcheck >/dev/null 2>&1; then
        run make lint
        [ "$status" -eq 0 ]
    fi
}

# Test error handling and recovery
@test "error handling and recovery work correctly" {
    export CONFIG_FILE="$TEST_CONFIG_FILE"
    export BUILD_DIR="$TEST_BUILD_DIR"
    export INTEGRATION_TEST_MODE=true
    
    # Test with invalid configuration file
    local invalid_config="$TEST_DIR/broken-config.yaml"
    echo "invalid: yaml: content:" > "$invalid_config"
    
    export CONFIG_FILE="$invalid_config"
    
    # Scripts should handle invalid config gracefully
    run "$PROJECT_ROOT/scripts/config-validator.sh" validate "$invalid_config"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid YAML syntax" ]] || [[ "$output" =~ "validation" ]]
    
    # Test with missing config file
    run "$PROJECT_ROOT/scripts/config-validator.sh" validate "/nonexistent/config.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" ]] || [[ "$output" =~ "does not exist" ]]
}

# Test performance and optimization
@test "performance optimizations work correctly" {
    export CONFIG_FILE="$TEST_CONFIG_FILE"
    export BUILD_DIR="$TEST_BUILD_DIR"
    export INTEGRATION_TEST_MODE=true
    
    # Test system optimizer
    run "$PROJECT_ROOT/scripts/system-optimizer.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "System Optimizer" ]]
    
    # Test optimization verification
    run "$PROJECT_ROOT/scripts/system-optimizer.sh" verify
    [ "$status" -eq 0 ]
}

# Test GitHub Actions workflow files
@test "GitHub Actions workflow files are valid" {
    # Check if workflow files exist
    [ -f "$PROJECT_ROOT/.github/workflows/build-template.yml" ]
    [ -f "$PROJECT_ROOT/.github/workflows/release.yml" ]
    
    # Basic YAML syntax check (if yq is available)
    if command -v yq >/dev/null 2>&1; then
        run yq eval '.name' "$PROJECT_ROOT/.github/workflows/build-template.yml"
        [ "$status" -eq 0 ]
        
        run yq eval '.name' "$PROJECT_ROOT/.github/workflows/release.yml"
        [ "$status" -eq 0 ]
    fi
}

# Test documentation completeness
@test "documentation is complete and accessible" {
    # Check main documentation files
    [ -f "$PROJECT_ROOT/README.md" ]
    [ -f "$PROJECT_ROOT/docs/README.md" ]
    [ -f "$PROJECT_ROOT/docs/installation.md" ]
    [ -f "$PROJECT_ROOT/docs/configuration.md" ]
    [ -f "$PROJECT_ROOT/docs/development.md" ]
    [ -f "$PROJECT_ROOT/docs/troubleshooting.md" ]
    
    # Check that README files are not empty
    [ -s "$PROJECT_ROOT/README.md" ]
    [ -s "$PROJECT_ROOT/docs/README.md" ]
}

# Test configuration schema completeness
@test "configuration schema is complete" {
    [ -f "$PROJECT_ROOT/config/template-schema.json" ]
    [ -f "$PROJECT_ROOT/config/template.yaml" ]
    
    # Verify schema file is valid JSON (if jq is available)
    if command -v jq >/dev/null 2>&1; then
        run jq '.' "$PROJECT_ROOT/config/template-schema.json"
        [ "$status" -eq 0 ]
    fi
}

# Test all unit test files
@test "all unit test files are executable and valid" {
    local test_files=(
        "test-config.bats"
        "test-k3s-installer.bats"
        "test-packaging.bats"
        "test-base-image-manager.bats"
    )
    
    for test_file in "${test_files[@]}"; do
        [ -f "$PROJECT_ROOT/tests/$test_file" ]
        [ -x "$PROJECT_ROOT/tests/$test_file" ]
        
        # Run a basic syntax check
        run bash -n "$PROJECT_ROOT/tests/$test_file"
        [ "$status" -eq 0 ]
    done
}

# Test integration test runner
@test "integration test runner works correctly" {
    [ -f "$PROJECT_ROOT/tests/run-integration-tests.sh" ]
    [ -x "$PROJECT_ROOT/tests/run-integration-tests.sh" ]
    
    # Test help output
    run "$PROJECT_ROOT/tests/run-integration-tests.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "集成测试运行器" ]]
}

# Test log management
@test "log management works correctly" {
    export LOG_DIR="$TEST_DIR/logs"
    mkdir -p "$LOG_DIR"
    
    # Test log manager script
    run "$PROJECT_ROOT/scripts/log-manager.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Log Manager" ]]
    
    # Test log cleanup
    touch "$LOG_DIR/test.log"
    run "$PROJECT_ROOT/scripts/log-manager.sh" cleanup
    [ "$status" -eq 0 ]
}

# Final integration verification
@test "final integration verification passes" {
    # Verify all components can work together
    export CONFIG_FILE="$TEST_CONFIG_FILE"
    export BUILD_DIR="$TEST_BUILD_DIR"
    export OUTPUT_DIR="$TEST_OUTPUT_DIR"
    export CACHE_DIR="$TEST_CACHE_DIR"
    export LOG_DIR="$TEST_DIR/logs"
    export INTEGRATION_TEST_MODE=true
    
    mkdir -p "$LOG_DIR"
    
    # Load configuration
    source "$PROJECT_ROOT/scripts/config-loader.sh"
    run load_config "$TEST_CONFIG_FILE"
    [ "$status" -eq 0 ]
    
    # Verify all configuration values are accessible
    template_name=$(get_config "template.name")
    [ "$template_name" = "e2e-test-alpine-k3s" ]
    
    template_version=$(get_config "template.version")
    [ "$template_version" = "1.0.0-e2e" ]
    
    k3s_version=$(get_config "k3s.version")
    [ "$k3s_version" = "v1.28.4+k3s1" ]
    
    # Verify logging system works
    source "$PROJECT_ROOT/scripts/logging.sh"
    run log_info "e2e-test" "Final integration test completed successfully"
    [ "$status" -eq 0 ]
    
    # Verify all scripts can be sourced without errors
    local core_scripts=(
        "config-loader.sh"
        "logging.sh"
    )
    
    for script in "${core_scripts[@]}"; do
        run bash -c "source '$PROJECT_ROOT/scripts/$script'"
        [ "$status" -eq 0 ]
    done
}