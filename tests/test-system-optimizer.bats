#!/usr/bin/env bats
# Unit tests for system optimizer functionality

# Setup test environment
setup() {
    # Get the project root directory
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    
    # Source the script
    source "$PROJECT_ROOT/scripts/system-optimizer.sh"
    
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    
    # Override directories for testing
    CONFIG_FILE="$TEST_DIR/template.yaml"
    LOG_FILE="$TEST_DIR/system-optimizer.log"
    
    # Create test configuration file
    cat > "$CONFIG_FILE" << 'EOF'
template:
  name: "test-alpine-k3s"
  version: "1.0.0"

system:
  timezone: "Asia/Shanghai"
  locale: "zh_CN.UTF-8"
  packages:
    - curl
    - wget
    - git
  remove_packages:
    - docs
    - man-pages

security:
  remove_packages:
    - apk-tools
    - alpine-keys
EOF
    
    # Create mock directories
    mkdir -p "$TEST_DIR/usr/share/zoneinfo/Asia"
    mkdir -p "$TEST_DIR/usr/share/zoneinfo"
    echo "Asia/Shanghai" > "$TEST_DIR/usr/share/zoneinfo/Asia/Shanghai"
    echo "UTC" > "$TEST_DIR/usr/share/zoneinfo/UTC"
    
    # Mock system directories
    mkdir -p "$TEST_DIR/etc"
    mkdir -p "$TEST_DIR/var/cache/apk"
    mkdir -p "$TEST_DIR/tmp"
    mkdir -p "$TEST_DIR/var/tmp"
    mkdir -p "$TEST_DIR/var/log"
    mkdir -p "$TEST_DIR/usr/share/man"
    mkdir -p "$TEST_DIR/usr/share/doc"
    mkdir -p "$TEST_DIR/usr/share/locale/zh_CN"
    mkdir -p "$TEST_DIR/usr/share/locale/en_US"
    mkdir -p "$TEST_DIR/usr/share/locale/fr_FR"
}

# Cleanup test environment
teardown() {
    rm -rf "$TEST_DIR"
}

# Test logging functions
@test "log_info should write info messages" {
    run log_info "Test info message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "INFO" ]]
    [[ "$output" =~ "Test info message" ]]
    
    # Check log file
    [ -f "$LOG_FILE" ]
    grep -q "INFO.*Test info message" "$LOG_FILE"
}

@test "log_warn should write warning messages" {
    run log_warn "Test warning message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "Test warning message" ]]
}

@test "log_error should write error messages" {
    run log_error "Test error message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "Test error message" ]]
}

@test "error_exit should log error and exit" {
    run error_exit "Fatal error occurred"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR.*Fatal error occurred" ]]
}

# Test container environment check
@test "check_container_environment should detect non-Alpine environment" {
    # Remove Alpine release file
    rm -f "/etc/alpine-release"
    
    run check_container_environment
    [ "$status" -eq 0 ]
    [[ "$output" =~ "不在 Alpine 容器环境中" ]]
}

# Test package index update
@test "update_package_index should handle successful update" {
    # Mock apk command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/apk" << 'EOF'
#!/bin/bash
if [ "$1" = "update" ]; then
    echo "Updating package index..."
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/apk"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run update_package_index
    [ "$status" -eq 0 ]
    [[ "$output" =~ "更新包索引" ]]
    [[ "$output" =~ "包索引更新完成" ]]
}

@test "update_package_index should handle failed update" {
    # Mock failing apk command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/apk" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$TEST_DIR/bin/apk"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run update_package_index
    [ "$status" -eq 1 ]
    [[ "$output" =~ "包索引更新失败" ]]
}

# Test essential package installation
@test "install_essential_packages should install required packages" {
    # Mock apk command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/apk" << 'EOF'
#!/bin/bash
if [ "$1" = "add" ] && [ "$2" = "--no-cache" ]; then
    echo "Installing package: $3"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/apk"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run install_essential_packages
    [ "$status" -eq 0 ]
    [[ "$output" =~ "安装必要的系统包" ]]
    [[ "$output" =~ "安装包: curl" ]]
    [[ "$output" =~ "安装包: wget" ]]
    [[ "$output" =~ "必要系统包安装完成" ]]
}

@test "install_essential_packages should handle package installation failures" {
    # Mock apk command that fails for specific packages
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/apk" << 'EOF'
#!/bin/bash
if [ "$1" = "add" ] && [ "$2" = "--no-cache" ]; then
    if [ "$3" = "curl" ]; then
        echo "Installing package: $3"
        exit 0
    else
        echo "Package $3 not found"
        exit 1
    fi
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/apk"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run install_essential_packages
    [ "$status" -eq 0 ]
    [[ "$output" =~ "安装包: curl" ]]
    [[ "$output" =~ "包 wget 安装失败，跳过" ]]
}

# Test configured package installation
@test "install_configured_packages should install packages from config" {
    # Mock apk command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/apk" << 'EOF'
#!/bin/bash
if [ "$1" = "add" ] && [ "$2" = "--no-cache" ]; then
    echo "Installing configured package: $3"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/apk"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run install_configured_packages
    [ "$status" -eq 0 ]
    [[ "$output" =~ "安装配置文件中指定的包" ]]
    [[ "$output" =~ "安装配置包: curl" ]]
    [[ "$output" =~ "安装配置包: wget" ]]
    [[ "$output" =~ "安装配置包: git" ]]
}

@test "install_configured_packages should handle missing config file" {
    CONFIG_FILE="/nonexistent/config.yaml"
    
    run install_configured_packages
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置文件不存在，跳过配置包安装" ]]
}

@test "install_configured_packages should handle empty package list" {
    # Create config without packages
    cat > "$CONFIG_FILE" << 'EOF'
template:
  name: "test-template"
system:
  timezone: "UTC"
EOF
    
    run install_configured_packages
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置文件中没有指定要安装的包" ]]
}

# Test package removal
@test "remove_unnecessary_packages should remove specified packages" {
    # Mock apk commands
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/apk" << 'EOF'
#!/bin/bash
case "$1" in
    "info")
        if [ "$2" = "--installed" ]; then
            # Simulate that docs package is installed
            if [ "$3" = "docs" ]; then
                exit 0
            else
                exit 1
            fi
        fi
        ;;
    "del")
        if [ "$2" = "--no-cache" ]; then
            echo "Removing package: $3"
            exit 0
        fi
        ;;
    "autoremove")
        echo "Cleaning up orphaned packages"
        exit 0
        ;;
esac
exit 1
EOF
    chmod +x "$TEST_DIR/bin/apk"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run remove_unnecessary_packages
    [ "$status" -eq 0 ]
    [[ "$output" =~ "移除不必要的包" ]]
    [[ "$output" =~ "移除包: docs" ]]
    [[ "$output" =~ "清理孤立的依赖包" ]]
}

# Test timezone configuration
@test "configure_timezone should set correct timezone" {
    # Mock system directories
    ln -sf "$TEST_DIR/usr/share/zoneinfo" /usr/share/zoneinfo
    
    run configure_timezone "Asia/Shanghai"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置系统时区: Asia/Shanghai" ]]
    [[ "$output" =~ "时区设置完成: Asia/Shanghai" ]]
    
    # Check if timezone file was created
    [ -L "/etc/localtime" ]
    [ -f "/etc/timezone" ]
    [ "$(cat /etc/timezone)" = "Asia/Shanghai" ]
}

@test "configure_timezone should fallback to UTC for invalid timezone" {
    run configure_timezone "Invalid/Timezone"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "时区文件不存在: Invalid/Timezone" ]]
    [[ "$output" =~ "使用默认时区 UTC" ]]
}

@test "configure_timezone should use UTC as default" {
    run configure_timezone
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置系统时区: UTC" ]]
}

# Test locale configuration
@test "configure_locale should set system locale" {
    run configure_locale "zh_CN.UTF-8"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置系统语言环境: zh_CN.UTF-8" ]]
    [[ "$output" =~ "语言环境配置完成" ]]
    
    # Check if locale files were created
    [ -f "/etc/profile" ]
    [ -f "/etc/locale.conf" ]
    
    # Check locale content
    grep -q "LANG=zh_CN.UTF-8" "/etc/profile"
    grep -q "LANG=zh_CN.UTF-8" "/etc/locale.conf"
}

@test "configure_locale should use default locale" {
    run configure_locale
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置系统语言环境: en_US.UTF-8" ]]
}

# Test system configuration optimization
@test "optimize_system_configuration should create config files" {
    run optimize_system_configuration
    [ "$status" -eq 0 ]
    [[ "$output" =~ "优化系统配置" ]]
    [[ "$output" =~ "系统配置优化完成" ]]
    
    # Check if configuration files were created
    [ -f "/etc/sysctl.d/99-k3s-optimization.conf" ]
    [ -f "/etc/modules-load.d/k3s.conf" ]
    [ -f "/etc/security/limits.d/99-k3s.conf" ]
    
    # Check configuration content
    grep -q "net.bridge.bridge-nf-call-iptables = 1" "/etc/sysctl.d/99-k3s-optimization.conf"
    grep -q "br_netfilter" "/etc/modules-load.d/k3s.conf"
    grep -q "* soft nofile 1048576" "/etc/security/limits.d/99-k3s.conf"
}

# Test network configuration
@test "configure_network should set up network files" {
    run configure_network
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置网络设置" ]]
    [[ "$output" =~ "网络配置完成" ]]
    
    # Check if network files were created
    [ -f "/etc/resolv.conf" ]
    [ -f "/etc/hostname" ]
    [ -f "/etc/hosts" ]
    
    # Check content
    grep -q "nameserver 8.8.8.8" "/etc/resolv.conf"
    [ "$(cat /etc/hostname)" = "alpine-k3s" ]
    grep -q "127.0.0.1.*localhost" "/etc/hosts"
}

# Test service disabling
@test "disable_unnecessary_services should disable specified services" {
    # Mock rc-update command
    mkdir -p "$TEST_DIR/bin" "$TEST_DIR/etc/init.d"
    
    # Create mock service files
    touch "$TEST_DIR/etc/init.d/chronyd"
    touch "$TEST_DIR/etc/init.d/acpid"
    
    cat > "$TEST_DIR/bin/rc-update" << 'EOF'
#!/bin/bash
if [ "$1" = "del" ]; then
    echo "Removing service $2 from runlevel $3"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/rc-update"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run disable_unnecessary_services
    [ "$status" -eq 0 ]
    [[ "$output" =~ "禁用不必要的服务" ]]
    [[ "$output" =~ "禁用服务: chronyd" ]]
    [[ "$output" =~ "服务禁用完成" ]]
}

# Test system file cleanup
@test "cleanup_system_files should clean temporary and cache files" {
    # Create test files to be cleaned
    mkdir -p "$TEST_DIR/var/cache/apk"
    mkdir -p "$TEST_DIR/tmp"
    mkdir -p "$TEST_DIR/var/tmp"
    mkdir -p "$TEST_DIR/var/log"
    mkdir -p "$TEST_DIR/usr/share/man/man1"
    mkdir -p "$TEST_DIR/usr/share/doc/test"
    mkdir -p "$TEST_DIR/usr/share/locale/fr_FR"
    
    touch "$TEST_DIR/var/cache/apk/test.cache"
    touch "$TEST_DIR/tmp/test.tmp"
    touch "$TEST_DIR/var/tmp/test.tmp"
    touch "$TEST_DIR/var/log/test.log"
    touch "$TEST_DIR/usr/share/man/man1/test.1"
    touch "$TEST_DIR/usr/share/doc/test/readme.txt"
    touch "$TEST_DIR/usr/share/locale/fr_FR/messages.mo"
    
    # Override paths for testing
    cd "$TEST_DIR"
    
    run cleanup_system_files
    [ "$status" -eq 0 ]
    [[ "$output" =~ "清理系统文件" ]]
    [[ "$output" =~ "系统文件清理完成" ]]
    
    # Check files were removed
    [ ! -f "$TEST_DIR/var/cache/apk/test.cache" ]
    [ ! -f "$TEST_DIR/tmp/test.tmp" ]
    [ ! -f "$TEST_DIR/var/log/test.log" ]
    [ ! -f "$TEST_DIR/usr/share/man/man1/test.1" ]
    [ ! -f "$TEST_DIR/usr/share/doc/test/readme.txt" ]
    [ ! -f "$TEST_DIR/usr/share/locale/fr_FR/messages.mo" ]
    
    # Check directories still exist
    [ -d "$TEST_DIR/tmp" ]
    [ -d "$TEST_DIR/var/tmp" ]
    [ -d "$TEST_DIR/var/log" ]
}

# Test binary optimization
@test "optimize_binaries should strip debug symbols" {
    # Create mock binaries
    mkdir -p "$TEST_DIR/usr/bin" "$TEST_DIR/usr/lib"
    echo "mock binary" > "$TEST_DIR/usr/bin/test-binary"
    echo "mock library" > "$TEST_DIR/usr/lib/libtest.so.1"
    chmod +x "$TEST_DIR/usr/bin/test-binary"
    
    # Mock strip command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/strip" << 'EOF'
#!/bin/bash
echo "Stripping: $3"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/strip"
    
    # Mock find command to return our test files
    cat > "$TEST_DIR/bin/find" << 'EOF'
#!/bin/bash
if [[ "$*" =~ "-executable" ]]; then
    echo "$TEST_DIR/usr/bin/test-binary"
elif [[ "$*" =~ "*.so*" ]]; then
    echo "$TEST_DIR/usr/lib/libtest.so.1"
fi
EOF
    chmod +x "$TEST_DIR/bin/find"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run optimize_binaries
    [ "$status" -eq 0 ]
    [[ "$output" =~ "优化二进制文件" ]]
    [[ "$output" =~ "二进制文件优化完成" ]]
}

# Test system info generation
@test "generate_system_info should create info file" {
    # Mock commands
    mkdir -p "$TEST_DIR/bin" "$TEST_DIR/etc"
    
    echo "3.18.4" > "$TEST_DIR/etc/alpine-release"
    
    cat > "$TEST_DIR/bin/apk" << 'EOF'
#!/bin/bash
if [ "$1" = "list" ] && [ "$2" = "--installed" ]; then
    echo "package1-1.0-r0"
    echo "package2-2.0-r0"
    echo "package3-3.0-r0"
fi
EOF
    chmod +x "$TEST_DIR/bin/apk"
    
    cat > "$TEST_DIR/bin/uname" << 'EOF'
#!/bin/bash
case "$1" in
    "-m") echo "x86_64" ;;
    "-r") echo "5.15.0" ;;
esac
EOF
    chmod +x "$TEST_DIR/bin/uname"
    
    cat > "$TEST_DIR/bin/cat" << 'EOF'
#!/bin/bash
if [ "$1" = "/etc/alpine-release" ]; then
    echo "3.18.4"
fi
EOF
    chmod +x "$TEST_DIR/bin/cat"
    
    export PATH="$TEST_DIR/bin:$PATH"
    
    run generate_system_info
    [ "$status" -eq 0 ]
    [[ "$output" =~ "生成系统信息" ]]
    [[ "$output" =~ "系统信息生成完成" ]]
    
    # Check info file was created
    [ -f "/etc/alpine-k3s-info" ]
    
    # Check content
    grep -q "Template Name: alpine-k3s" "/etc/alpine-k3s-info"
    grep -q "Alpine Version: 3.18.4" "/etc/alpine-k3s-info"
    grep -q "Architecture: x86_64" "/etc/alpine-k3s-info"
}

# Test optimization verification
@test "verify_optimization should check required components" {
    # Create required files and directories
    mkdir -p "/etc/modules-load.d" "/etc/sysctl.d"
    touch "/etc/modules-load.d/k3s.conf"
    touch "/etc/sysctl.d/99-k3s-optimization.conf"
    touch "/etc/resolv.conf"
    
    # Mock required commands
    mkdir -p "$TEST_DIR/bin"
    for cmd in curl wget iptables mount umount; do
        cat > "$TEST_DIR/bin/$cmd" << 'EOF'
#!/bin/bash
echo "Mock command: $0"
EOF
        chmod +x "$TEST_DIR/bin/$cmd"
    done
    export PATH="$TEST_DIR/bin:$PATH"
    
    run verify_optimization
    [ "$status" -eq 0 ]
    [[ "$output" =~ "验证系统优化" ]]
    [[ "$output" =~ "系统优化验证通过" ]]
}

@test "verify_optimization should fail with missing components" {
    # Don't create required files
    export PATH="/nonexistent:$PATH"
    
    run verify_optimization
    [ "$status" -eq 1 ]
    [[ "$output" =~ "系统优化验证失败" ]]
}

# Test main function commands
@test "main function should handle optimize command" {
    # Mock all required functions
    check_container_environment() { echo "Container check passed"; }
    update_package_index() { echo "Package index updated"; }
    install_essential_packages() { echo "Essential packages installed"; }
    install_configured_packages() { echo "Configured packages installed"; }
    remove_unnecessary_packages() { echo "Unnecessary packages removed"; }
    configure_timezone() { echo "Timezone configured"; }
    configure_locale() { echo "Locale configured"; }
    optimize_system_configuration() { echo "System configuration optimized"; }
    configure_network() { echo "Network configured"; }
    disable_unnecessary_services() { echo "Services disabled"; }
    cleanup_system_files() { echo "System files cleaned"; }
    optimize_binaries() { echo "Binaries optimized"; }
    generate_system_info() { echo "System info generated"; }
    verify_optimization() { echo "Optimization verified"; return 0; }
    
    run main optimize
    [ "$status" -eq 0 ]
    [[ "$output" =~ "开始系统优化" ]]
    [[ "$output" =~ "系统优化完成" ]]
}

@test "main function should handle cleanup command" {
    cleanup_system_files() { echo "System files cleaned"; }
    
    run main cleanup
    [ "$status" -eq 0 ]
    [[ "$output" =~ "执行系统清理" ]]
    [[ "$output" =~ "系统清理完成" ]]
}

@test "main function should handle verify command" {
    verify_optimization() { echo "Optimization verified"; return 0; }
    
    run main verify
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Optimization verified" ]]
}

@test "main function should handle info command" {
    echo "Test system info" > "/etc/alpine-k3s-info"
    
    run main info
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Test system info" ]]
}

@test "main function should handle info command with missing file" {
    rm -f "/etc/alpine-k3s-info"
    
    run main info
    [ "$status" -eq 0 ]
    [[ "$output" =~ "系统信息文件不存在" ]]
}

@test "main function should show usage for unknown command" {
    run main unknown-command
    [ "$status" -eq 1 ]
    [[ "$output" =~ "用法:" ]]
    [[ "$output" =~ "optimize" ]]
    [[ "$output" =~ "cleanup" ]]
    [[ "$output" =~ "verify" ]]
    [[ "$output" =~ "info" ]]
}