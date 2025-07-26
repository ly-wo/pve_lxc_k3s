#!/usr/bin/env bats
# Unit tests for security hardening functionality

# Setup test environment
setup() {
    # Get the project root directory
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    
    # Source the script
    source "$PROJECT_ROOT/scripts/security-hardening.sh"
    
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    
    # Override directories for testing
    CONFIG_DIR="$TEST_DIR/config"
    LOG_DIR="$TEST_DIR/logs"
    LOG_FILE="$LOG_DIR/security-hardening.log"
    
    # Create directories
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    
    # Create test configuration file
    cat > "$CONFIG_DIR/template.yaml" << 'EOF'
template:
  name: "test-alpine-k3s"
  version: "1.0.0"

security:
  disable_root_login: true
  create_k3s_user: true
  k3s_user: "k3s"
  k3s_uid: 1000
  k3s_gid: 1000
  firewall_rules:
    - port: "6443"
      protocol: "tcp"
      description: "K3s API Server"
    - port: "10250"
      protocol: "tcp"
      description: "Kubelet API"
  remove_packages:
    - build-base
    - gcc

network:
  dns_servers:
    - "8.8.8.8"
    - "8.8.4.4"
  disable_ipv6: false
EOF
    
    # Mock system directories
    mkdir -p "$TEST_DIR/etc/sudoers.d"
    mkdir -p "$TEST_DIR/etc/ssh"
    mkdir -p "$TEST_DIR/etc/sysctl.d"
    mkdir -p "$TEST_DIR/etc/modprobe.d"
    mkdir -p "$TEST_DIR/etc/security"
    mkdir -p "$TEST_DIR/etc/init.d"
    mkdir -p "$TEST_DIR/etc/iptables"
    
    # Mock system files
    touch "$TEST_DIR/etc/shadow"
    touch "$TEST_DIR/etc/passwd"
    touch "$TEST_DIR/etc/group"
    touch "$TEST_DIR/etc/ssh/sshd_config"
    
    # Set EUID to root for testing
    EUID=0
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

# Test permission check
@test "check_permissions should pass with root privileges" {
    EUID=0
    
    run check_permissions
    [ "$status" -eq 0 ]
    [[ "$output" =~ "检查运行权限" ]]
    [[ "$output" =~ "权限检查通过" ]]
}

@test "check_permissions should fail without root privileges" {
    EUID=1000
    
    run check_permissions
    [ "$status" -eq 1 ]
    [[ "$output" =~ "此脚本需要 root 权限运行" ]]
}

# Test system security configuration
@test "configure_system_security should create security config files" {
    # Mock sysctl command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/sysctl" << 'EOF'
#!/bin/bash
if [ "$1" = "-p" ]; then
    echo "Applied sysctl configuration from $2"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/sysctl"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run configure_system_security
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置系统安全设置" ]]
    [[ "$output" =~ "系统安全设置配置完成" ]]
    
    # Check if configuration files were created
    [ -f "/etc/modprobe.d/blacklist-rare-network.conf" ]
    [ -f "/etc/sysctl.d/99-security.conf" ]
    
    # Check configuration content
    grep -q "install dccp /bin/true" "/etc/modprobe.d/blacklist-rare-network.conf"
    grep -q "net.ipv4.ip_forward = 1" "/etc/sysctl.d/99-security.conf"
    grep -q "kernel.dmesg_restrict = 1" "/etc/sysctl.d/99-security.conf"
}

# Test user permissions configuration
@test "configure_user_permissions should create k3s user and configure sudo" {
    # Mock system commands
    mkdir -p "$TEST_DIR/bin"
    
    # Mock getent command
    cat > "$TEST_DIR/bin/getent" << 'EOF'
#!/bin/bash
# Simulate user/group doesn't exist
exit 1
EOF
    chmod +x "$TEST_DIR/bin/getent"
    
    # Mock addgroup command
    cat > "$TEST_DIR/bin/addgroup" << 'EOF'
#!/bin/bash
echo "Adding group: $4 (GID: $2)"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/addgroup"
    
    # Mock adduser command
    cat > "$TEST_DIR/bin/adduser" << 'EOF'
#!/bin/bash
echo "Adding user: $4 (UID: $2)"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/adduser"
    
    # Mock passwd command
    cat > "$TEST_DIR/bin/passwd" << 'EOF'
#!/bin/bash
if [ "$1" = "-l" ]; then
    echo "Locking password for $2"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/passwd"
    
    export PATH="$TEST_DIR/bin:$PATH"
    
    # Set configuration variables
    CONFIG_SECURITY_K3S_USER="k3s"
    CONFIG_SECURITY_K3S_UID="1000"
    CONFIG_SECURITY_K3S_GID="1000"
    CONFIG_SECURITY_DISABLE_ROOT_LOGIN="true"
    
    run configure_user_permissions
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置用户权限" ]]
    [[ "$output" =~ "创建用户组: k3s" ]]
    [[ "$output" =~ "创建用户: k3s" ]]
    [[ "$output" =~ "已禁用 root 登录" ]]
    [[ "$output" =~ "用户权限配置完成" ]]
    
    # Check if sudo configuration was created
    [ -f "/etc/sudoers.d/k3s" ]
    grep -q "k3s ALL=(root) NOPASSWD: /usr/local/bin/k3s" "/etc/sudoers.d/k3s"
    
    # Check if login.defs was created
    [ -f "/etc/login.defs" ]
    grep -q "PASS_MAX_DAYS 90" "/etc/login.defs"
}

@test "configure_user_permissions should handle existing user" {
    # Mock getent to simulate existing user
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/getent" << 'EOF'
#!/bin/bash
if [ "$1" = "passwd" ] || [ "$1" = "group" ]; then
    echo "k3s:x:1000:1000::/home/k3s:/bin/sh"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/getent"
    export PATH="$TEST_DIR/bin:$PATH"
    
    CONFIG_SECURITY_K3S_USER="k3s"
    CONFIG_SECURITY_DISABLE_ROOT_LOGIN="false"
    
    run configure_user_permissions
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "创建用户组" ]]
    [[ ! "$output" =~ "创建用户" ]]
    [[ ! "$output" =~ "已禁用 root 登录" ]]
}

# Test firewall configuration
@test "configure_firewall should set up iptables rules" {
    # Mock system commands
    mkdir -p "$TEST_DIR/bin"
    
    # Mock command availability check
    cat > "$TEST_DIR/bin/command" << 'EOF'
#!/bin/bash
if [ "$1" = "-v" ] && [ "$2" = "iptables" ]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/command"
    
    # Mock iptables commands
    cat > "$TEST_DIR/bin/iptables" << 'EOF'
#!/bin/bash
echo "iptables: $*"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/iptables"
    
    # Mock iptables-save
    cat > "$TEST_DIR/bin/iptables-save" << 'EOF'
#!/bin/bash
echo "# Generated iptables rules"
echo "-A INPUT -p tcp --dport 6443 -j ACCEPT"
EOF
    chmod +x "$TEST_DIR/bin/iptables-save"
    
    # Mock rc-update
    cat > "$TEST_DIR/bin/rc-update" << 'EOF'
#!/bin/bash
echo "Adding service $2 to runlevel $3"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/rc-update"
    
    export PATH="$TEST_DIR/bin:$PATH"
    
    # Mock get_config_array function
    get_config_array() {
        if [ "$1" = "security.firewall_rules" ]; then
            echo '{"port": "6443", "protocol": "tcp", "description": "K3s API Server"}'
            echo '{"port": "10250", "protocol": "tcp", "description": "Kubelet API"}'
        fi
    }
    
    run configure_firewall
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置防火墙规则" ]]
    [[ "$output" =~ "添加防火墙规则: 6443/tcp" ]]
    [[ "$output" =~ "防火墙配置完成" ]]
    
    # Check if iptables restore script was created
    [ -f "/etc/init.d/iptables-restore" ]
    [ -x "/etc/init.d/iptables-restore" ]
}

@test "configure_firewall should install iptables if missing" {
    # Mock command to simulate iptables not available
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/command" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$TEST_DIR/bin/command"
    
    # Mock apk command
    cat > "$TEST_DIR/bin/apk" << 'EOF'
#!/bin/bash
if [ "$1" = "add" ] && [ "$2" = "--no-cache" ]; then
    echo "Installing: $3 $4"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/apk"
    
    # Mock iptables after installation
    cat > "$TEST_DIR/bin/iptables" << 'EOF'
#!/bin/bash
echo "iptables: $*"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/iptables"
    
    cat > "$TEST_DIR/bin/iptables-save" << 'EOF'
#!/bin/bash
echo "# Generated iptables rules"
EOF
    chmod +x "$TEST_DIR/bin/iptables-save"
    
    cat > "$TEST_DIR/bin/rc-update" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$TEST_DIR/bin/rc-update"
    
    export PATH="$TEST_DIR/bin:$PATH"
    
    get_config_array() { echo ""; }
    
    run configure_firewall
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Installing: iptables ip6tables" ]]
}

# Test package removal
@test "remove_unnecessary_packages should remove specified packages" {
    # Mock system commands
    mkdir -p "$TEST_DIR/bin"
    
    # Mock apk commands
    cat > "$TEST_DIR/bin/apk" << 'EOF'
#!/bin/bash
case "$1" in
    "info")
        if [ "$2" = "-e" ]; then
            # Simulate that build-base is installed
            if [ "$3" = "build-base" ]; then
                exit 0
            else
                exit 1
            fi
        fi
        ;;
    "del")
        echo "Removing package: $2"
        exit 0
        ;;
    "cache")
        if [ "$2" = "clean" ]; then
            echo "Cleaning package cache"
            exit 0
        fi
        ;;
esac
exit 1
EOF
    chmod +x "$TEST_DIR/bin/apk"
    export PATH="$TEST_DIR/bin:$PATH"
    
    # Mock get_config_array function
    get_config_array() {
        if [ "$1" = "security.remove_packages" ]; then
            echo "build-base"
            echo "gcc"
        fi
    }
    
    run remove_unnecessary_packages
    [ "$status" -eq 0 ]
    [[ "$output" =~ "移除不必要的软件包" ]]
    [[ "$output" =~ "移除软件包: build-base" ]]
    [[ "$output" =~ "移除开发包: gcc" ]]
    [[ "$output" =~ "软件包清理完成" ]]
}

# Test service security configuration
@test "configure_service_security should disable unnecessary services" {
    # Mock system commands
    mkdir -p "$TEST_DIR/bin"
    
    # Mock rc-service and rc-update
    cat > "$TEST_DIR/bin/rc-service" << 'EOF'
#!/bin/bash
if [ "$1" = "--exists" ]; then
    # Simulate telnet service exists
    if [ "$2" = "telnet" ]; then
        exit 0
    else
        exit 1
    fi
elif [ "$2" = "stop" ]; then
    echo "Stopping service: $1"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/rc-service"
    
    cat > "$TEST_DIR/bin/rc-update" << 'EOF'
#!/bin/bash
if [ "$1" = "del" ]; then
    echo "Removing service $2 from runlevels"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/rc-update"
    
    # Mock systemctl
    cat > "$TEST_DIR/bin/systemctl" << 'EOF'
#!/bin/bash
if [ "$1" = "mask" ]; then
    echo "Masking service: $2"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/systemctl"
    
    export PATH="$TEST_DIR/bin:$PATH"
    
    run configure_service_security
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置服务安全" ]]
    [[ "$output" =~ "禁用服务: telnet" ]]
    [[ "$output" =~ "服务安全配置完成" ]]
}

# Test filesystem security configuration
@test "configure_filesystem_security should set file permissions" {
    # Create test files
    touch "$TEST_DIR/etc/shadow"
    touch "$TEST_DIR/etc/passwd"
    touch "$TEST_DIR/etc/group"
    touch "$TEST_DIR/etc/ssh/sshd_config"
    mkdir -p "$TEST_DIR/var/log"
    touch "$TEST_DIR/var/log/test.log"
    
    # Mock commands
    mkdir -p "$TEST_DIR/bin"
    
    cat > "$TEST_DIR/bin/chmod" << 'EOF'
#!/bin/bash
echo "Setting permissions $1 on $2"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/chmod"
    
    cat > "$TEST_DIR/bin/chown" << 'EOF'
#!/bin/bash
echo "Changing ownership to $1 on $2"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/chown"
    
    cat > "$TEST_DIR/bin/find" << 'EOF'
#!/bin/bash
if [[ "$*" =~ "-perm -002" ]]; then
    echo "$TEST_DIR/var/log/test.log"
elif [[ "$*" =~ "-perm -4000" ]]; then
    echo "/usr/bin/sudo"
    echo "/bin/su"
fi
EOF
    chmod +x "$TEST_DIR/bin/find"
    
    export PATH="$TEST_DIR/bin:$PATH"
    
    run configure_filesystem_security
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置文件系统安全" ]]
    [[ "$output" =~ "扫描 SUID/SGID 文件" ]]
    [[ "$output" =~ "发现 SUID/SGID 文件: /usr/bin/sudo" ]]
    [[ "$output" =~ "文件系统安全配置完成" ]]
}

# Test network security configuration
@test "configure_network_security should set up network files" {
    # Mock get_config_array function
    get_config_array() {
        if [ "$1" = "network.dns_servers" ]; then
            echo "8.8.8.8"
            echo "8.8.4.4"
        fi
    }
    
    CONFIG_NETWORK_DISABLE_IPV6="false"
    
    run configure_network_security
    [ "$status" -eq 0 ]
    [[ "$output" =~ "配置网络安全" ]]
    [[ "$output" =~ "网络安全配置完成" ]]
    
    # Check if network files were created
    [ -f "/etc/hosts" ]
    [ -f "/etc/resolv.conf" ]
    
    # Check content
    grep -q "127.0.0.1.*localhost" "/etc/hosts"
    grep -q "nameserver 8.8.8.8" "/etc/resolv.conf"
    grep -q "nameserver 8.8.4.4" "/etc/resolv.conf"
}

@test "configure_network_security should disable IPv6 when configured" {
    # Mock sysctl command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/sysctl" << 'EOF'
#!/bin/bash
if [ "$1" = "-p" ]; then
    echo "Applied sysctl configuration from $2"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/sysctl"
    export PATH="$TEST_DIR/bin:$PATH"
    
    get_config_array() { echo ""; }
    CONFIG_NETWORK_DISABLE_IPV6="true"
    
    run configure_network_security
    [ "$status" -eq 0 ]
    [[ "$output" =~ "已禁用 IPv6" ]]
}

# Test security configuration verification
@test "verify_security_configuration should check all security settings" {
    # Mock system commands
    mkdir -p "$TEST_DIR/bin"
    
    # Mock getent to simulate k3s user exists
    cat > "$TEST_DIR/bin/getent" << 'EOF'
#!/bin/bash
if [ "$1" = "passwd" ] && [ "$2" = "k3s" ]; then
    echo "k3s:x:1000:1000::/home/k3s:/bin/sh"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/getent"
    
    # Mock iptables
    cat > "$TEST_DIR/bin/iptables" << 'EOF'
#!/bin/bash
if [ "$1" = "-L" ] && [ "$2" = "INPUT" ]; then
    echo "Chain INPUT (policy DROP)"
    echo "ACCEPT     tcp  --  anywhere             anywhere             tcp dpt:6443"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/iptables"
    
    # Mock sysctl
    cat > "$TEST_DIR/bin/sysctl" << 'EOF'
#!/bin/bash
if [ "$1" = "-n" ] && [ "$2" = "net.ipv4.ip_forward" ]; then
    echo "1"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/sysctl"
    
    # Mock stat
    cat > "$TEST_DIR/bin/stat" << 'EOF'
#!/bin/bash
if [ "$1" = "-c" ] && [ "$2" = "%a" ] && [ "$3" = "/etc/shadow" ]; then
    echo "600"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/stat"
    
    # Mock rc-service
    cat > "$TEST_DIR/bin/rc-service" << 'EOF'
#!/bin/bash
if [ "$1" = "iptables-restore" ] && [ "$2" = "status" ]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/rc-service"
    
    export PATH="$TEST_DIR/bin:$PATH"
    
    CONFIG_SECURITY_K3S_USER="k3s"
    
    run verify_security_configuration
    [ "$status" -eq 0 ]
    [[ "$output" =~ "验证安全配置" ]]
    [[ "$output" =~ "✓ K3s 用户存在: k3s" ]]
    [[ "$output" =~ "✓ K3s API Server 端口已开放" ]]
    [[ "$output" =~ "✓ IP 转发已启用" ]]
    [[ "$output" =~ "✓ /etc/shadow 权限正确" ]]
    [[ "$output" =~ "✓ 所有安全配置验证通过" ]]
}

@test "verify_security_configuration should report failures" {
    # Mock commands to simulate failures
    mkdir -p "$TEST_DIR/bin"
    
    # Mock getent to simulate user doesn't exist
    cat > "$TEST_DIR/bin/getent" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$TEST_DIR/bin/getent"
    
    # Mock iptables to not show K3s port
    cat > "$TEST_DIR/bin/iptables" << 'EOF'
#!/bin/bash
if [ "$1" = "-L" ] && [ "$2" = "INPUT" ]; then
    echo "Chain INPUT (policy DROP)"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/iptables"
    
    # Mock sysctl to show IP forwarding disabled
    cat > "$TEST_DIR/bin/sysctl" << 'EOF'
#!/bin/bash
if [ "$1" = "-n" ] && [ "$2" = "net.ipv4.ip_forward" ]; then
    echo "0"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/sysctl"
    
    # Mock stat to show wrong permissions
    cat > "$TEST_DIR/bin/stat" << 'EOF'
#!/bin/bash
if [ "$1" = "-c" ] && [ "$2" = "%a" ] && [ "$3" = "/etc/shadow" ]; then
    echo "644"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/stat"
    
    export PATH="$TEST_DIR/bin:$PATH"
    
    CONFIG_SECURITY_K3S_USER="k3s"
    
    run verify_security_configuration
    [ "$status" -eq 1 ]
    [[ "$output" =~ "K3s 用户不存在: k3s" ]]
    [[ "$output" =~ "K3s API Server 端口未开放" ]]
    [[ "$output" =~ "IP 转发未启用" ]]
    [[ "$output" =~ "/etc/shadow 权限不正确" ]]
    [[ "$output" =~ "发现 4 个安全配置问题" ]]
}

# Test get_config_array helper function
@test "get_config_array should parse YAML arrays" {
    # Mock yq command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/yq" << 'EOF'
#!/bin/bash
if [ "$1" = "e" ] && [ "$2" = ".security.firewall_rules[]" ]; then
    echo "port: 6443"
    echo "protocol: tcp"
    echo "---"
    echo "port: 10250"
    echo "protocol: tcp"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/bin/yq"
    export PATH="$TEST_DIR/bin:$PATH"
    
    result=$(get_config_array "security.firewall_rules")
    [[ "$result" =~ "port: 6443" ]]
    [[ "$result" =~ "port: 10250" ]]
}

@test "get_config_array should handle missing config file" {
    CONFIG_DIR="/nonexistent"
    
    result=$(get_config_array "security.firewall_rules")
    [ -z "$result" ]
}

# Test main function
@test "main function should execute all security hardening steps" {
    # Mock all required functions
    check_permissions() { echo "Permissions checked"; }
    configure_system_security() { echo "System security configured"; }
    configure_user_permissions() { echo "User permissions configured"; }
    configure_firewall() { echo "Firewall configured"; }
    remove_unnecessary_packages() { echo "Packages removed"; }
    configure_service_security() { echo "Service security configured"; }
    configure_filesystem_security() { echo "Filesystem security configured"; }
    configure_network_security() { echo "Network security configured"; }
    verify_security_configuration() { echo "Security verified"; return 0; }
    
    run main
    [ "$status" -eq 0 ]
    [[ "$output" =~ "开始系统安全加固" ]]
    [[ "$output" =~ "Permissions checked" ]]
    [[ "$output" =~ "System security configured" ]]
    [[ "$output" =~ "User permissions configured" ]]
    [[ "$output" =~ "Firewall configured" ]]
    [[ "$output" =~ "Packages removed" ]]
    [[ "$output" =~ "Service security configured" ]]
    [[ "$output" =~ "Filesystem security configured" ]]
    [[ "$output" =~ "Network security configured" ]]
    [[ "$output" =~ "Security verified" ]]
    [[ "$output" =~ "系统安全加固完成" ]]
}

# Test error handling
@test "main function should handle permission check failure" {
    check_permissions() { echo "Permission denied"; return 1; }
    
    run main
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Permission denied" ]]
}

@test "main function should handle verification failure" {
    check_permissions() { echo "Permissions OK"; }
    configure_system_security() { echo "System configured"; }
    configure_user_permissions() { echo "Users configured"; }
    configure_firewall() { echo "Firewall configured"; }
    remove_unnecessary_packages() { echo "Packages removed"; }
    configure_service_security() { echo "Services configured"; }
    configure_filesystem_security() { echo "Filesystem configured"; }
    configure_network_security() { echo "Network configured"; }
    verify_security_configuration() { echo "Verification failed"; return 1; }
    
    run main
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Verification failed" ]]
}