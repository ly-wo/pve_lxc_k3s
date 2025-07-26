#!/usr/bin/env bats
# Unit tests for configuration management system

# Setup test environment
setup() {
    # Get the project root directory
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    
    # Source the scripts
    source "$PROJECT_ROOT/scripts/config-loader.sh"
    source "$PROJECT_ROOT/scripts/config-validator.sh"
    
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    
    # Create test configuration file
    TEST_CONFIG="$TEST_DIR/test-template.yaml"
    cat > "$TEST_CONFIG" << 'EOF'
template:
  name: "test-alpine-k3s"
  version: "1.0.0"
  description: "Test template"
  author: "Test Author"
  base_image: "alpine:3.18"
  architecture: "amd64"

k3s:
  version: "v1.28.4+k3s1"
  install_options:
    - "--disable=traefik"
    - "--disable=servicelb"
  cluster_init: true

system:
  timezone: "UTC"
  locale: "en_US.UTF-8"
  packages:
    - curl
    - wget
  remove_packages:
    - docs

security:
  disable_root_login: true
  create_k3s_user: true
  k3s_user: "k3s"
  k3s_uid: 1000
  k3s_gid: 1000

build:
  cleanup_after_install: true
  optimize_size: true
  parallel_jobs: 2
EOF

    # Create test schema file
    TEST_SCHEMA="$TEST_DIR/test-schema.json"
    cp "$PROJECT_ROOT/config/template-schema.json" "$TEST_SCHEMA"
    
    # Reset configuration cache
    reset_config
}

# Cleanup test environment
teardown() {
    rm -rf "$TEST_DIR"
    reset_config
}

# Test configuration loading
@test "load_config should load configuration successfully" {
    run load_config "$TEST_CONFIG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Configuration loaded successfully" ]]
}

@test "load_config should fail with invalid file" {
    run load_config "/nonexistent/config.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Configuration file not found" ]]
}

# Test configuration value retrieval
@test "get_config should return correct values" {
    load_config "$TEST_CONFIG"
    
    result=$(get_config "template.name")
    [ "$result" = "test-alpine-k3s" ]
    
    result=$(get_config "template.version")
    [ "$result" = "1.0.0" ]
    
    result=$(get_config "k3s.version")
    [ "$result" = "v1.28.4+k3s1" ]
}

@test "get_config should return default values for missing keys" {
    load_config "$TEST_CONFIG"
    
    result=$(get_config "nonexistent.key" "default_value")
    [ "$result" = "default_value" ]
    
    # Test built-in defaults
    result=$(get_config "system.timezone")
    [ "$result" = "UTC" ]
}

@test "get_config should return built-in defaults" {
    load_config "$TEST_CONFIG"
    
    # Test default architecture
    result=$(get_config "template.architecture")
    [ "$result" = "amd64" ]
    
    # Test default build settings
    result=$(get_config "build.cleanup_after_install")
    [ "$result" = "true" ]
}

# Test configuration array handling
@test "get_config_array should return array elements" {
    load_config "$TEST_CONFIG"
    
    # Test system packages array
    run get_config_array "system.packages"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "curl" ]]
    [[ "$output" =~ "wget" ]]
    
    # Test K3s install options
    run get_config_array "k3s.install_options"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "--disable=traefik" ]]
    [[ "$output" =~ "--disable=servicelb" ]]
}

# Test configuration existence check
@test "config_exists should check key existence correctly" {
    load_config "$TEST_CONFIG"
    
    run config_exists "template.name"
    [ "$status" -eq 0 ]
    
    run config_exists "nonexistent.key"
    [ "$status" -eq 1 ]
}

# Test required configuration validation
@test "validate_required_config should pass with valid config" {
    load_config "$TEST_CONFIG"
    
    run validate_required_config
    [ "$status" -eq 0 ]
}

@test "validate_required_config should fail with missing required keys" {
    # Create config with missing required key
    INVALID_CONFIG="$TEST_DIR/invalid-config.yaml"
    cat > "$INVALID_CONFIG" << 'EOF'
template:
  name: "test-template"
  # Missing version and base_image
k3s:
  # Missing version
EOF
    
    load_config "$INVALID_CONFIG"
    
    run validate_required_config
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Missing required configuration keys" ]]
}

# Test configuration export
@test "export_config should export environment variables" {
    load_config "$TEST_CONFIG"
    
    export_config "TEST_"
    
    [ "$TEST_NAME" = "test-alpine-k3s" ]
    [ "$TEST_VERSION" = "1.0.0" ]
    [ "$TEST_K3S_VERSION" = "v1.28.4+k3s1" ]
    [ "$TEST_ARCHITECTURE" = "amd64" ]
}

# Test configuration report generation
@test "generate_config_report should create report" {
    load_config "$TEST_CONFIG"
    
    REPORT_FILE="$TEST_DIR/config-report.md"
    run generate_config_report "$REPORT_FILE"
    [ "$status" -eq 0 ]
    
    [ -f "$REPORT_FILE" ]
    
    # Check report content
    run cat "$REPORT_FILE"
    [[ "$output" =~ "Configuration Report" ]]
    [[ "$output" =~ "test-alpine-k3s" ]]
    [[ "$output" =~ "v1.28.4+k3s1" ]]
}

# Test YAML syntax validation
@test "validate_yaml_syntax should validate correct YAML" {
    run validate_yaml_syntax "$TEST_CONFIG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "YAML syntax is valid" ]]
}

@test "validate_yaml_syntax should fail with invalid YAML" {
    INVALID_YAML="$TEST_DIR/invalid.yaml"
    cat > "$INVALID_YAML" << 'EOF'
template:
  name: "test"
  invalid: [unclosed array
EOF
    
    run validate_yaml_syntax "$INVALID_YAML"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid YAML syntax" ]]
}

# Test schema validation
@test "validate_schema should pass with valid configuration" {
    run validate_schema "$TEST_CONFIG" "$TEST_SCHEMA"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Configuration validation passed" ]]
}

@test "validate_schema should fail with invalid version format" {
    INVALID_CONFIG="$TEST_DIR/invalid-version.yaml"
    cat > "$INVALID_CONFIG" << 'EOF'
template:
  name: "test-template"
  version: "invalid-version"
  base_image: "alpine:3.18"
k3s:
  version: "v1.28.4+k3s1"
system: {}
EOF
    
    run validate_schema "$INVALID_CONFIG" "$TEST_SCHEMA"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid template.version format" ]]
}

@test "validate_schema should fail with invalid k3s version format" {
    INVALID_CONFIG="$TEST_DIR/invalid-k3s-version.yaml"
    cat > "$INVALID_CONFIG" << 'EOF'
template:
  name: "test-template"
  version: "1.0.0"
  base_image: "alpine:3.18"
k3s:
  version: "invalid-k3s-version"
system: {}
EOF
    
    run validate_schema "$INVALID_CONFIG" "$TEST_SCHEMA"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid k3s.version format" ]]
}

@test "validate_schema should fail with invalid base image format" {
    INVALID_CONFIG="$TEST_DIR/invalid-base-image.yaml"
    cat > "$INVALID_CONFIG" << 'EOF'
template:
  name: "test-template"
  version: "1.0.0"
  base_image: "ubuntu:20.04"
k3s:
  version: "v1.28.4+k3s1"
system: {}
EOF
    
    run validate_schema "$INVALID_CONFIG" "$TEST_SCHEMA"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid template.base_image format" ]]
}

# Test configuration cache
@test "configuration should be cached after first load" {
    # First load
    run load_config "$TEST_CONFIG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Configuration loaded successfully" ]]
    
    # Second load should use cache
    run load_config "$TEST_CONFIG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Configuration already loaded from cache" ]]
}

@test "reset_config should clear cache" {
    load_config "$TEST_CONFIG"
    
    run reset_config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Configuration cache reset" ]]
    
    # Next load should not use cache
    run load_config "$TEST_CONFIG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Configuration loaded successfully" ]]
}

# Test error handling
@test "get_config should handle missing configuration gracefully" {
    # Don't load any config
    result=$(get_config "template.name" "default")
    [ "$result" = "default" ]
}

@test "validate_config should handle missing files gracefully" {
    run validate_config "/nonexistent/file.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Configuration file not found" ]]
}

# Test configuration summary
@test "print_config_summary should display configuration summary" {
    run print_config_summary "$TEST_CONFIG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Configuration Summary" ]]
    [[ "$output" =~ "Template Name: test-alpine-k3s" ]]
    [[ "$output" =~ "K3s Version: v1.28.4+k3s1" ]]
}