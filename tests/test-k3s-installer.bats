#!/usr/bin/env bats
# Unit tests for K3s installer functionality

# Setup test environment
setup() {
    # Get the project root directory
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    
    # Source the script
    source "$PROJECT_ROOT/scripts/k3s-installer.sh"
    
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    
    # Override directories for testing
    K3S_INSTALL_DIR="$TEST_DIR/usr/local/bin"
    K3S_CONFIG_DIR="$TEST_DIR/etc/rancher/k3s"
    K3S_DATA_DIR="$TEST_DIR/var/lib/rancher/k3s"
    K3S_LOG_DIR="$TEST_DIR/var/log/k3s"
    
    # Create test directories
    mkdir -p "$K3S_INSTALL_DIR" "$K3S_CONFIG_DIR" "$K3S_DATA_DIR" "$K3S_LOG_DIR"
    
    # Create test configuration file
    TEST_CONFIG="$TEST_DIR/test-template.yaml"
    cat > "$TEST_CONFIG" << 'EOF'
template:
  name: "test-alpine-k3s"
  version: "1.0.0"
  base_image: "alpine:3.18"

k3s:
  version: "v1.28.4+k3s1"
  cluster_init: true
  install_options:
    - "--disable=traefik"
    - "--disable=servicelb"
    - "--write-kubeconfig-mode=644"
  server_options:
    - "--node-taint=CriticalAddonsOnly=true:NoExecute"
  agent_options:
    - "--kubelet-arg=max-pods=110"

system:
  timezone: "UTC"
EOF
    
    # Override config file for testing
    CONFIG_FILE="$TEST_CONFIG"
    
    # Reset global variables
    K3S_VERSION=""
    K3S_INSTALL_OPTIONS=()
    K3S_SERVER_OPTIONS=()
    K3S_AGENT_OPTIONS=()
    CLUSTER_INIT=""
    INSTALL_METHOD="script"
}

# Cleanup test environment
teardown() {
    rm -rf "$TEST_DIR"
}

# Test configuration initialization
@test "init_config should load K3s configuration successfully" {
    run init_config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Initializing K3s installer configuration" ]]
    [[ "$output" =~ "K3s installer configured" ]]
    
    # Check loaded values
    [ "$K3S_VERSION" = "v1.28.4+k3s1" ]
    [ "$CLUSTER_INIT" = "true" ]
    [ ${#K3S_INSTALL_OPTIONS[@]} -eq 3 ]
    [ ${#K3S_SERVER_OPTIONS[@]} -eq 1 ]
    [ ${#K3S_AGENT_OPTIONS[@]} -eq 1 ]
}

@test "init_config should fail with missing K3s version" {
    # Create config without K3s version
    INVALID_CONFIG="$TEST_DIR/invalid-config.yaml"
    cat > "$INVALID_CONFIG" << 'EOF'
template:
  name: "test-template"
k3s: {}
EOF
    CONFIG_FILE="$INVALID_CONFIG"
    
    run init_config
    [ "$status" -eq 1 ]
    [[ "$output" =~ "K3s version not specified" ]]
}

# Test version validation
@test "verify_version_format should accept valid K3s versions" {
    run verify_version_format "v1.28.4+k3s1"
    [ "$status" -eq 0 ]
    
    run verify_version_format "v1.27.10+k3s2"
    [ "$status" -eq 0 ]
    
    run verify_version_format "v1.29.0+k3s1"
    [ "$status" -eq 0 ]
}

@test "verify_version_format should reject invalid K3s versions" {
    run verify_version_format "1.28.4+k3s1"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid K3s version format" ]]
    
    run verify_version_format "v1.28.4"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid K3s version format" ]]
    
    run verify_version_format "latest"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid K3s version format" ]]
    
    run verify_version_format "v1.28.4+k3s"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid K3s version format" ]]
}

# Test system requirements check
@test "check_requirements should pass with required commands available" {
    # Mock required commands
    mkdir -p "$TEST_DIR/bin"
    for cmd in curl wget tar gzip; do
        echo '#!/bin/bash' > "$TEST_DIR/bin/$cmd"
        chmod +x "$TEST_DIR/bin/$cmd"
    done
    
    # Add test bin to PATH
    export PATH="$TEST_DIR/bin:$PATH"
    
    # Mock EUID check
    EUID=0
    
    run check_requirements
    [ "$status" -eq 0 ]
    [[ "$output" =~ "System requirements check passed" ]]
}

@test "check_requirements should fail without root privileges" {
    # Mock EUID as non-root
    EUID=1000
    
    run check_requirements
    [ "$status" -eq 1 ]
    [[ "$output" =~ "K3s installation requires root privileges" ]]
}

@test "check_requirements should fail with missing commands" {
    # Mock EUID as root
    EUID=0
    
    # Don't add any commands to PATH
    export PATH="/nonexistent"
    
    run check_requirements
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Required command not found" ]]
}

# Test directory creation
@test "create_directories should create all required directories" {
    run create_directories
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s directories created successfully" ]]
    
    # Check directories exist
    [ -d "$K3S_CONFIG_DIR" ]
    [ -d "$K3S_DATA_DIR" ]
    [ -d "$K3S_LOG_DIR" ]
    
    # Check permissions
    [ "$(stat -c %a "$K3S_CONFIG_DIR")" = "755" ]
    [ "$(stat -c %a "$K3S_DATA_DIR")" = "755" ]
    [ "$(stat -c %a "$K3S_LOG_DIR")" = "755" ]
}

# Test download functionality
@test "download_with_retry should succeed on first attempt" {
    # Mock curl command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/bin/bash
# Mock successful curl
echo "mock content" > "$4"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/curl"
    export PATH="$TEST_DIR/bin:$PATH"
    
    OUTPUT_FILE="$TEST_DIR/test-download"
    
    run download_with_retry "https://example.com/test" "$OUTPUT_FILE" "test file"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test file downloaded successfully" ]]
    [ -f "$OUTPUT_FILE" ]
    [ "$(cat "$OUTPUT_FILE")" = "mock content" ]
}

@test "download_with_retry should retry on failure and eventually succeed" {
    # Mock curl command that fails twice then succeeds
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/bin/bash
# Mock curl that fails first two times
COUNTER_FILE="/tmp/curl_counter"
if [ ! -f "$COUNTER_FILE" ]; then
    echo "1" > "$COUNTER_FILE"
    exit 1
elif [ "$(cat "$COUNTER_FILE")" = "1" ]; then
    echo "2" > "$COUNTER_FILE"
    exit 1
else
    echo "mock content" > "$4"
    rm -f "$COUNTER_FILE"
    exit 0
fi
EOF
    chmod +x "$TEST_DIR/bin/curl"
    export PATH="$TEST_DIR/bin:$PATH"
    
    OUTPUT_FILE="$TEST_DIR/test-download"
    
    run download_with_retry "https://example.com/test" "$OUTPUT_FILE" "test file"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Download failed" ]]
    [[ "$output" =~ "retrying" ]]
    [[ "$output" =~ "test file downloaded successfully" ]]
}

@test "download_with_retry should fail after max retries" {
    # Mock curl command that always fails
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$TEST_DIR/bin/curl"
    export PATH="$TEST_DIR/bin:$PATH"
    
    OUTPUT_FILE="$TEST_DIR/test-download"
    
    run download_with_retry "https://example.com/test" "$OUTPUT_FILE" "test file"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Failed to download test file after 3 attempts" ]]
}

# Test binary URL generation
@test "get_k3s_binary_url should generate correct URLs" {
    result=$(get_k3s_binary_url "v1.28.4+k3s1" "amd64")
    expected="https://github.com/k3s-io/k3s/releases/download/v1.28.4+k3s1/k3s"
    [ "$result" = "$expected" ]
    
    result=$(get_k3s_binary_url "v1.27.10+k3s2" "arm64")
    expected="https://github.com/k3s-io/k3s/releases/download/v1.27.10+k3s2/k3s"
    [ "$result" = "$expected" ]
}

# Test K3s configuration creation
@test "create_k3s_config should create valid configuration file" {
    # Initialize configuration first
    init_config
    
    run create_k3s_config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s configuration file created" ]]
    
    # Check config file exists
    [ -f "$K3S_CONFIG_DIR/config.yaml" ]
    
    # Check config content
    local config_content
    config_content=$(cat "$K3S_CONFIG_DIR/config.yaml")
    [[ "$config_content" =~ "cluster-init: true" ]]
    [[ "$config_content" =~ "write-kubeconfig-mode: \"0644\"" ]]
    [[ "$config_content" =~ "disable:" ]]
    [[ "$config_content" =~ "- traefik" ]]
    [[ "$config_content" =~ "- servicelb" ]]
}

@test "create_k3s_config should handle agent-only configuration" {
    # Modify config for agent mode
    CLUSTER_INIT="false"
    K3S_INSTALL_OPTIONS=()
    K3S_SERVER_OPTIONS=()
    K3S_AGENT_OPTIONS=("--kubelet-arg=max-pods=110")
    
    run create_k3s_config
    [ "$status" -eq 0 ]
    
    # Check config content
    local config_content
    config_content=$(cat "$K3S_CONFIG_DIR/config.yaml")
    [[ "$config_content" =~ "cluster-init: false" ]]
    [[ "$config_content" =~ "Agent options" ]]
    [[ "$config_content" =~ "kubelet-arg: max-pods=110" ]]
}

# Test installation verification
@test "verify_installation should pass with correct installation" {
    # Create mock K3s binary
    cat > "$K3S_INSTALL_DIR/k3s" << 'EOF'
#!/bin/bash
if [ "$1" = "--version" ]; then
    echo "k3s version v1.28.4+k3s1 (12345678)"
    echo "go version go1.20.10"
fi
EOF
    chmod +x "$K3S_INSTALL_DIR/k3s"
    
    # Create symlinks
    ln -sf "$K3S_INSTALL_DIR/k3s" "$K3S_INSTALL_DIR/kubectl"
    ln -sf "$K3S_INSTALL_DIR/k3s" "$K3S_INSTALL_DIR/crictl"
    ln -sf "$K3S_INSTALL_DIR/k3s" "$K3S_INSTALL_DIR/ctr"
    
    # Set expected version
    K3S_VERSION="v1.28.4+k3s1"
    
    run verify_installation
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s installation verified successfully" ]]
    [[ "$output" =~ "Installed version: v1.28.4+k3s1" ]]
}

@test "verify_installation should fail with missing binary" {
    K3S_VERSION="v1.28.4+k3s1"
    
    run verify_installation
    [ "$status" -eq 1 ]
    [[ "$output" =~ "K3s binary not found or not executable" ]]
}

@test "verify_installation should fail with version mismatch" {
    # Create mock K3s binary with wrong version
    cat > "$K3S_INSTALL_DIR/k3s" << 'EOF'
#!/bin/bash
if [ "$1" = "--version" ]; then
    echo "k3s version v1.27.10+k3s2 (12345678)"
fi
EOF
    chmod +x "$K3S_INSTALL_DIR/k3s"
    
    K3S_VERSION="v1.28.4+k3s1"
    
    run verify_installation
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Version mismatch" ]]
}

# Test binary installation method
@test "install_k3s_binary should install K3s binary successfully" {
    # Mock curl for binary download
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/bin/bash
# Mock K3s binary download
cat > "$4" << 'BINARY_EOF'
#!/bin/bash
if [ "$1" = "--version" ]; then
    echo "k3s version v1.28.4+k3s1 (12345678)"
fi
BINARY_EOF
exit 0
EOF
    chmod +x "$TEST_DIR/bin/curl"
    export PATH="$TEST_DIR/bin:$PATH"
    
    # Set version
    K3S_VERSION="v1.28.4+k3s1"
    
    run install_k3s_binary
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s binary installed successfully" ]]
    
    # Check binary exists and is executable
    [ -x "$K3S_INSTALL_DIR/k3s" ]
    
    # Check symlinks
    [ -L "$K3S_INSTALL_DIR/kubectl" ]
    [ -L "$K3S_INSTALL_DIR/crictl" ]
    [ -L "$K3S_INSTALL_DIR/ctr" ]
}

# Test uninstallation
@test "uninstall_k3s should remove all K3s components" {
    # Create mock installation
    mkdir -p "$K3S_INSTALL_DIR" "$K3S_CONFIG_DIR" "$K3S_DATA_DIR" "$K3S_LOG_DIR"
    touch "$K3S_INSTALL_DIR/k3s"
    touch "$K3S_INSTALL_DIR/kubectl"
    touch "$K3S_CONFIG_DIR/config.yaml"
    touch "$K3S_DATA_DIR/server"
    touch "$K3S_LOG_DIR/k3s.log"
    
    # Mock systemctl
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/systemctl" << 'EOF'
#!/bin/bash
case "$1" in
    "is-active") exit 1 ;;  # Not active
    "is-enabled") exit 1 ;; # Not enabled
    "stop"|"disable"|"daemon-reload") exit 0 ;;
esac
EOF
    chmod +x "$TEST_DIR/bin/systemctl"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run uninstall_k3s
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s uninstalled successfully" ]]
    
    # Check files are removed
    [ ! -f "$K3S_INSTALL_DIR/k3s" ]
    [ ! -f "$K3S_INSTALL_DIR/kubectl" ]
    [ ! -d "$K3S_CONFIG_DIR" ]
    [ ! -d "$K3S_DATA_DIR" ]
    [ ! -d "$K3S_LOG_DIR" ]
}

# Test status reporting
@test "show_status should report installation status correctly" {
    # Create partial installation
    mkdir -p "$K3S_INSTALL_DIR" "$K3S_CONFIG_DIR"
    cat > "$K3S_INSTALL_DIR/k3s" << 'EOF'
#!/bin/bash
if [ "$1" = "--version" ]; then
    echo "k3s version v1.28.4+k3s1 (12345678)"
fi
EOF
    chmod +x "$K3S_INSTALL_DIR/k3s"
    touch "$K3S_CONFIG_DIR/config.yaml"
    
    run show_status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✓ K3s binary installed: v1.28.4+k3s1" ]]
    [[ "$output" =~ "✓ K3s configuration file exists" ]]
    [[ "$output" =~ "✓ Directory exists: $K3S_CONFIG_DIR" ]]
    [[ "$output" =~ "✗ Directory missing: $K3S_DATA_DIR" ]]
}

# Test error handling
@test "install_k3s should handle configuration initialization failure" {
    # Create invalid config
    CONFIG_FILE="/nonexistent/config.yaml"
    
    run install_k3s
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Failed to initialize configuration" ]]
}

@test "install_k3s should handle invalid version format" {
    # Set invalid version directly
    K3S_VERSION="invalid-version"
    
    # Mock init_config to succeed but set invalid version
    init_config() {
        K3S_VERSION="invalid-version"
        return 0
    }
    
    run install_k3s
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid K3s version format" ]]
}

# Test main function command parsing
@test "main function should handle install command" {
    # Mock install_k3s function
    install_k3s() {
        echo "K3s installation completed"
        return 0
    }
    
    run main install
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s installation completed" ]]
}

@test "main function should handle status command" {
    # Mock show_status function
    show_status() {
        echo "K3s status report"
        return 0
    }
    
    run main status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s status report" ]]
}

@test "main function should handle uninstall command" {
    # Mock uninstall_k3s function
    uninstall_k3s() {
        echo "K3s uninstalled"
        return 0
    }
    
    run main uninstall
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s uninstalled" ]]
}

@test "main function should handle help command" {
    run main help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s Installer Script" ]]
    [[ "$output" =~ "Usage:" ]]
}

@test "main function should handle unknown command" {
    run main unknown-command
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown command: unknown-command" ]]
}

# Test option parsing
@test "main function should handle --method option" {
    # Mock install_k3s function
    install_k3s() {
        echo "Install method: $INSTALL_METHOD"
        return 0
    }
    
    run main install --method binary
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Install method: binary" ]]
}

@test "main function should handle --version option" {
    # Mock install_k3s function
    install_k3s() {
        echo "K3s version: $K3S_VERSION"
        return 0
    }
    
    run main install --version v1.27.10+k3s2
    [ "$status" -eq 0 ]
    [[ "$output" =~ "K3s version: v1.27.10+k3s2" ]]
}

@test "main function should handle --debug option" {
    # Mock install_k3s function
    install_k3s() {
        echo "Debug mode: $DEBUG"
        return 0
    }
    
    run main install --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Debug mode: true" ]]
}