#!/bin/bash
# System Optimizer for PVE LXC K3s Template
# 负责系统包管理、清理和优化配置

set -euo pipefail

# 脚本目录和配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/config/template.yaml"
LOG_FILE="${PROJECT_ROOT}/logs/system-optimizer.log"

# 创建日志目录
mkdir -p "$(dirname "$LOG_FILE")"

# 日志函数
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# 错误处理
error_exit() {
    log_error "$1"
    exit 1
}

# 检查是否在容器环境中
check_container_environment() {
    if [[ ! -f "/etc/alpine-release" ]] && [[ ! -f "/.dockerenv" ]]; then
        log_warn "不在 Alpine 容器环境中，某些操作可能失败"
    fi
}

# 检测执行环境
detect_environment() {
    if command -v apk >/dev/null 2>&1; then
        echo "alpine"
    elif [[ -f /etc/alpine-release ]]; then
        echo "alpine"
    else
        echo "host"
    fi
}

# 更新包索引
update_package_index() {
    local env=$(detect_environment)
    
    if [[ "$env" == "host" ]]; then
        log_info "在主机环境中跳过包索引更新（将在 chroot 中执行）"
        return 0
    fi
    
    log_info "更新包索引"
    
    if ! apk update; then
        error_exit "包索引更新失败"
    fi
    
    log_info "包索引更新完成"
}

# 安装必要的系统包
install_essential_packages() {
    local env=$(detect_environment)
    
    if [[ "$env" == "host" ]]; then
        log_info "在主机环境中跳过包安装（将在 chroot 中执行）"
        return 0
    fi
    
    log_info "安装必要的系统包"
    
    local essential_packages=(
        "curl"
        "wget" 
        "ca-certificates"
        "openssl"
        "bash"
        "coreutils"
        "util-linux"
        "procps"
        "shadow"
        "sudo"
        "iptables"
        "ip6tables"
        "bridge-utils"
        "conntrack-tools"
    )
    
    for package in "${essential_packages[@]}"; do
        log_info "安装包: $package"
        if ! apk add --no-cache "$package"; then
            log_warn "包 $package 安装失败，跳过"
        fi
    done
    
    log_info "必要系统包安装完成"
}

# 安装配置文件中指定的包
install_configured_packages() {
    local env=$(detect_environment)
    
    if [[ "$env" == "host" ]]; then
        log_info "在主机环境中跳过配置包安装（将在 chroot 中执行）"
        return 0
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warn "配置文件不存在，跳过配置包安装"
        return 0
    fi
    
    log_info "安装配置文件中指定的包"
    
    # 解析配置文件中的包列表
    local packages=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.+)$ ]]; then
            local package="${BASH_REMATCH[1]}"
            packages+=("$package")
        fi
    done < <(sed -n '/^[[:space:]]*packages:/,/^[[:space:]]*[^[:space:]-]/p' "$CONFIG_FILE" | grep '^[[:space:]]*-')
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_info "配置文件中没有指定要安装的包"
        return 0
    fi
    
    for package in "${packages[@]}"; do
        log_info "安装配置包: $package"
        if ! apk add --no-cache "$package"; then
            log_warn "配置包 $package 安装失败，跳过"
        fi
    done
    
    log_info "配置包安装完成"
}

# 移除不必要的包
remove_unnecessary_packages() {
    local env=$(detect_environment)
    
    if [[ "$env" == "host" ]]; then
        log_info "在主机环境中跳过包移除（将在 chroot 中执行）"
        return 0
    fi
    
    log_info "移除不必要的包"
    
    # 默认要移除的包
    local default_remove_packages=(
        "apk-tools-doc"
        "man-pages"
        "docs"
        "alpine-keys"
    )
    
    # 从配置文件读取要移除的包
    local config_remove_packages=()
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.+)$ ]]; then
                local package="${BASH_REMATCH[1]}"
                config_remove_packages+=("$package")
            fi
        done < <(sed -n '/^[[:space:]]*remove_packages:/,/^[[:space:]]*[^[:space:]-]/p' "$CONFIG_FILE" | grep '^[[:space:]]*-')
    fi
    
    # 合并包列表
    local all_remove_packages=("${default_remove_packages[@]}" "${config_remove_packages[@]}")
    
    for package in "${all_remove_packages[@]}"; do
        if apk info --installed "$package" >/dev/null 2>&1; then
            log_info "移除包: $package"
            if ! apk del --no-cache "$package"; then
                log_warn "包 $package 移除失败，跳过"
            fi
        else
            log_info "包 $package 未安装，跳过"
        fi
    done
    
    # 清理孤立的依赖
    log_info "清理孤立的依赖包"
    apk autoremove || true
    
    log_info "不必要包移除完成"
}

# 配置系统时区
configure_timezone() {
    local timezone="${1:-UTC}"
    
    log_info "配置系统时区: $timezone"
    
    if [[ -f "/usr/share/zoneinfo/$timezone" ]]; then
        ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
        echo "$timezone" > /etc/timezone
        log_info "时区设置完成: $timezone"
    else
        log_warn "时区文件不存在: $timezone，使用默认时区 UTC"
        ln -sf /usr/share/zoneinfo/UTC /etc/localtime
        echo "UTC" > /etc/timezone
    fi
}

# 配置系统语言环境
configure_locale() {
    local locale="${1:-en_US.UTF-8}"
    
    log_info "配置系统语言环境: $locale"
    
    # 设置环境变量
    cat >> /etc/profile << EOF

# Locale configuration
export LANG=$locale
export LC_ALL=$locale
export LANGUAGE=\${LANG%.*}
EOF
    
    # 设置默认语言环境
    echo "export LANG=$locale" > /etc/locale.conf
    
    log_info "语言环境配置完成"
}

# 优化系统配置
optimize_system_configuration() {
    log_info "优化系统配置"
    
    # 配置 sysctl 参数
    cat > /etc/sysctl.d/99-k3s-optimization.conf << 'EOF'
# K3s 和容器优化配置
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 内存管理优化
vm.overcommit_memory = 1
vm.panic_on_oom = 0
vm.swappiness = 1

# 内核参数优化
kernel.panic = 10
kernel.panic_on_oops = 1
kernel.pid_max = 4194304
kernel.threads-max = 1000000

# 网络优化
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15

# 文件系统优化
fs.file-max = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
EOF
    
    # 配置内核模块加载
    cat > /etc/modules-load.d/k3s.conf << 'EOF'
# K3s 所需的内核模块
br_netfilter
overlay
iptable_nat
iptable_filter
iptable_mangle
ip_tables
ip6_tables
netfilter_conntrack
nf_conntrack_netlink
xt_conntrack
xt_MASQUERADE
xt_addrtype
xt_mark
xt_multiport
xt_comment
EOF
    
    # 配置系统限制
    cat > /etc/security/limits.d/99-k3s.conf << 'EOF'
# K3s 系统限制配置
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
* soft memlock unlimited
* hard memlock unlimited
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 1048576
root hard nproc 1048576
EOF
    
    log_info "系统配置优化完成"
}

# 配置网络设置
configure_network() {
    log_info "配置网络设置"
    
    # 配置 DNS
    cat > /etc/resolv.conf << 'EOF'
# DNS configuration for K3s LXC template
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 1.0.0.1
options timeout:2 attempts:3 rotate single-request-reopen
EOF
    
    # 配置主机名
    echo "alpine-k3s" > /etc/hostname
    
    # 配置 hosts 文件
    cat > /etc/hosts << 'EOF'
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
127.0.1.1   alpine-k3s
EOF
    
    log_info "网络配置完成"
}

# 禁用不必要的服务
disable_unnecessary_services() {
    log_info "禁用不必要的服务"
    
    local services_to_disable=(
        "chronyd"
        "acpid" 
        "crond"
        "syslog"
        "klogd"
    )
    
    for service in "${services_to_disable[@]}"; do
        if [[ -f "/etc/init.d/$service" ]]; then
            log_info "禁用服务: $service"
            rc-update del "$service" default 2>/dev/null || true
            rc-update del "$service" boot 2>/dev/null || true
        fi
    done
    
    log_info "服务禁用完成"
}

# 清理系统文件
cleanup_system_files() {
    local env=$(detect_environment)
    
    if [[ "$env" == "host" ]]; then
        log_info "在主机环境中跳过系统文件清理（将在 chroot 中执行）"
        return 0
    fi
    
    log_info "清理系统文件"
    
    # 清理包缓存
    rm -rf /var/cache/apk/* 2>/dev/null || true
    rm -rf /etc/apk/cache/* 2>/dev/null || true
    
    # 清理临时文件
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf /var/tmp/* 2>/dev/null || true
    
    # 清理日志文件
    find /var/log -type f -name "*.log" -delete 2>/dev/null || true
    find /var/log -type f -name "*.log.*" -delete 2>/dev/null || true
    
    # 清理文档和手册页
    rm -rf /usr/share/man/* 2>/dev/null || true
    rm -rf /usr/share/doc/* 2>/dev/null || true
    rm -rf /usr/share/info/* 2>/dev/null || true
    rm -rf /usr/share/gtk-doc/* 2>/dev/null || true
    
    # 清理语言文件（保留英文）
    find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'en*' -exec rm -rf {} + 2>/dev/null || true
    
    # 清理其他不必要的文件
    rm -rf /var/cache/misc/*
    rm -rf /usr/share/pixmaps/*
    rm -rf /usr/share/applications/*
    
    # 创建必要的空目录
    mkdir -p /var/log
    mkdir -p /tmp
    mkdir -p /var/tmp
    mkdir -p /var/cache/apk
    
    # 设置正确的权限
    chmod 1777 /tmp
    chmod 1777 /var/tmp
    
    log_info "系统文件清理完成"
}

# 优化二进制文件
optimize_binaries() {
    log_info "优化二进制文件"
    
    # 移除调试符号
    find /usr/bin /bin /sbin /usr/sbin -type f -executable \
         -exec strip --strip-unneeded {} \; 2>/dev/null || true
    
    # 移除共享库的调试符号
    find /usr/lib /lib -name "*.so*" -type f \
         -exec strip --strip-unneeded {} \; 2>/dev/null || true
    
    log_info "二进制文件优化完成"
}

# 生成系统信息
generate_system_info() {
    local env=$(detect_environment)
    
    if [[ "$env" == "host" ]]; then
        log_info "在主机环境中跳过系统信息生成（将在 chroot 中执行）"
        return 0
    fi
    
    log_info "生成系统信息"
    
    # Get package count safely
    local package_count="Unknown"
    if command -v apk >/dev/null 2>&1; then
        package_count=$(apk list --installed 2>/dev/null | wc -l || echo "Unknown")
    fi
    
    cat > /etc/alpine-k3s-info << EOF
# Alpine K3s LXC Template Information
Template Name: alpine-k3s
Build Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Alpine Version: $(cat /etc/alpine-release 2>/dev/null || echo "Unknown")
Architecture: $(uname -m)
Kernel Version: $(uname -r)

# Installed Packages
${package_count} packages installed

# System Optimization Applied:
- Kernel parameters optimized for K3s
- Network configuration optimized
- Unnecessary services disabled
- System files cleaned up
- Binary files stripped

# Next Steps:
1. Install K3s using k3s-installer.sh
2. Configure security hardening
3. Package as LXC template
EOF
    
    log_info "系统信息生成完成"
}

# 验证系统优化
verify_optimization() {
    log_info "验证系统优化"
    
    local errors=0
    
    # 检查必要的命令是否存在
    local required_commands=("curl" "wget" "iptables" "mount" "umount")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "必要命令不存在: $cmd"
            ((errors++))
        fi
    done
    
    # 检查内核模块配置
    if [[ ! -f "/etc/modules-load.d/k3s.conf" ]]; then
        log_error "内核模块配置文件不存在"
        ((errors++))
    fi
    
    # 检查 sysctl 配置
    if [[ ! -f "/etc/sysctl.d/99-k3s-optimization.conf" ]]; then
        log_error "sysctl 配置文件不存在"
        ((errors++))
    fi
    
    # 检查网络配置
    if [[ ! -f "/etc/resolv.conf" ]]; then
        log_error "DNS 配置文件不存在"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "系统优化验证通过"
        return 0
    else
        log_error "系统优化验证失败，发现 $errors 个错误"
        return 1
    fi
}

# 主函数
main() {
    local action="${1:-optimize}"
    
    case "$action" in
        "optimize")
            log_info "开始系统优化"
            check_container_environment
            update_package_index
            install_essential_packages
            install_configured_packages
            remove_unnecessary_packages
            
            # 从配置文件读取时区和语言设置
            local timezone="UTC"
            local locale="en_US.UTF-8"
            if [[ -f "$CONFIG_FILE" ]]; then
                timezone=$(grep "timezone:" "$CONFIG_FILE" | sed 's/.*timezone: *"\([^"]*\)".*/\1/' || echo "UTC")
                locale=$(grep "locale:" "$CONFIG_FILE" | sed 's/.*locale: *"\([^"]*\)".*/\1/' || echo "en_US.UTF-8")
            fi
            
            configure_timezone "$timezone"
            configure_locale "$locale"
            optimize_system_configuration
            configure_network
            disable_unnecessary_services
            cleanup_system_files
            optimize_binaries
            generate_system_info
            
            if verify_optimization; then
                log_info "系统优化完成"
            else
                error_exit "系统优化验证失败"
            fi
            ;;
        "cleanup")
            log_info "执行系统清理"
            cleanup_system_files
            log_info "系统清理完成"
            ;;
        "verify")
            verify_optimization
            ;;
        "info")
            if [[ -f "/etc/alpine-k3s-info" ]]; then
                cat /etc/alpine-k3s-info
            else
                log_error "系统信息文件不存在，请先运行优化"
            fi
            ;;
        *)
            echo "用法: $0 {optimize|cleanup|verify|info}"
            echo "  optimize  - 执行完整的系统优化"
            echo "  cleanup   - 仅执行系统文件清理"
            echo "  verify    - 验证系统优化状态"
            echo "  info      - 显示系统信息"
            exit 1
            ;;
    esac
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi