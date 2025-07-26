#!/bin/bash
# PVE LXC K3s 模板安全加固脚本
# 此脚本实现系统级别的安全配置和加固措施

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"
LOG_DIR="${SCRIPT_DIR}/../logs"

# 日志配置
LOG_FILE="${LOG_DIR}/security-hardening.log"
mkdir -p "${LOG_DIR}"

# 日志函数
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# 加载配置
source "${SCRIPT_DIR}/config-loader.sh"

# 主要安全加固函数
main() {
    log_info "开始系统安全加固..."
    
    # 检查运行权限
    check_permissions
    
    # 系统安全配置
    configure_system_security
    
    # 用户权限配置
    configure_user_permissions
    
    # 防火墙配置
    configure_firewall
    
    # 移除不必要的软件包
    remove_unnecessary_packages
    
    # 服务安全配置
    configure_service_security
    
    # 文件系统安全
    configure_filesystem_security
    
    # 网络安全配置
    configure_network_security
    
    # 验证安全配置
    verify_security_configuration
    
    log_info "系统安全加固完成"
}

# 检查运行权限
check_permissions() {
    log_info "检查运行权限..."
    
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
    
    log_info "权限检查通过"
}

# 系统安全配置
configure_system_security() {
    log_info "配置系统安全设置..."
    
    # 禁用不必要的内核模块
    cat > /etc/modprobe.d/blacklist-rare-network.conf << 'EOF'
# 禁用不常用的网络协议
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF
    
    # 设置内核安全参数
    cat > /etc/sysctl.d/99-security.conf << 'EOF'
# 网络安全参数
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1

# IPv6 安全参数
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# 内存保护
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1

# 文件系统保护
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
EOF
    
    # 应用内核参数
    sysctl -p /etc/sysctl.d/99-security.conf
    
    log_info "系统安全设置配置完成"
}

# 用户权限配置
configure_user_permissions() {
    log_info "配置用户权限..."
    
    local k3s_user="${CONFIG_SECURITY_K3S_USER:-k3s}"
    local k3s_uid="${CONFIG_SECURITY_K3S_UID:-1000}"
    local k3s_gid="${CONFIG_SECURITY_K3S_GID:-1000}"
    
    # 创建 k3s 用户组
    if ! getent group "$k3s_user" > /dev/null 2>&1; then
        addgroup -g "$k3s_gid" "$k3s_user"
        log_info "创建用户组: $k3s_user (GID: $k3s_gid)"
    fi
    
    # 创建 k3s 用户
    if ! getent passwd "$k3s_user" > /dev/null 2>&1; then
        adduser -D -u "$k3s_uid" -G "$k3s_user" -s /bin/sh "$k3s_user"
        log_info "创建用户: $k3s_user (UID: $k3s_uid)"
    fi
    
    # 配置 sudo 权限（仅限 k3s 相关命令）
    cat > "/etc/sudoers.d/$k3s_user" << EOF
# K3s 用户权限配置
$k3s_user ALL=(root) NOPASSWD: /usr/local/bin/k3s
$k3s_user ALL=(root) NOPASSWD: /bin/systemctl start k3s
$k3s_user ALL=(root) NOPASSWD: /bin/systemctl stop k3s
$k3s_user ALL=(root) NOPASSWD: /bin/systemctl restart k3s
$k3s_user ALL=(root) NOPASSWD: /bin/systemctl status k3s
EOF
    
    # 设置正确的权限
    chmod 440 "/etc/sudoers.d/$k3s_user"
    
    # 禁用 root 登录（如果配置要求）
    if [[ "${CONFIG_SECURITY_DISABLE_ROOT_LOGIN:-true}" == "true" ]]; then
        # 锁定 root 账户密码
        passwd -l root
        
        # 禁用 root SSH 登录
        if [[ -f /etc/ssh/sshd_config ]]; then
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        fi
        
        log_info "已禁用 root 登录"
    fi
    
    # 设置密码策略
    cat > /etc/login.defs << 'EOF'
# 密码策略配置
PASS_MAX_DAYS 90
PASS_MIN_DAYS 1
PASS_WARN_AGE 7
PASS_MIN_LEN 8
EOF
    
    log_info "用户权限配置完成"
}

# 防火墙配置
configure_firewall() {
    log_info "配置防火墙规则..."
    
    # 安装 iptables
    if ! command -v iptables > /dev/null 2>&1; then
        apk add --no-cache iptables ip6tables
    fi
    
    # 清除现有规则
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    
    # 设置默认策略
    iptables -P INPUT DROP
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # 允许本地回环
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # 允许已建立的连接
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # 允许 K3s 相关端口
    local firewall_rules
    firewall_rules=$(get_config_array "security.firewall_rules")
    
    if [[ -n "$firewall_rules" ]]; then
        while IFS= read -r rule; do
            local port protocol description
            port=$(echo "$rule" | yq e '.port' -)
            protocol=$(echo "$rule" | yq e '.protocol' -)
            description=$(echo "$rule" | yq e '.description' -)
            
            if [[ "$port" != "null" && "$protocol" != "null" ]]; then
                iptables -A INPUT -p "$protocol" --dport "$port" -j ACCEPT
                log_info "添加防火墙规则: $port/$protocol ($description)"
            fi
        done <<< "$firewall_rules"
    else
        # 默认 K3s 端口
        iptables -A INPUT -p tcp --dport 6443 -j ACCEPT  # K3s API Server
        iptables -A INPUT -p tcp --dport 10250 -j ACCEPT # Kubelet API
        iptables -A INPUT -p udp --dport 8472 -j ACCEPT  # Flannel VXLAN
        log_info "应用默认 K3s 防火墙规则"
    fi
    
    # 允许 SSH（如果存在）
    if [[ -f /etc/ssh/sshd_config ]]; then
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        log_info "允许 SSH 连接"
    fi
    
    # 保存防火墙规则
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules-save
    
    # 创建防火墙服务启动脚本
    cat > /etc/init.d/iptables-restore << 'EOF'
#!/sbin/openrc-run

name="iptables-restore"
description="Restore iptables rules"

depend() {
    need net
    before k3s
}

start() {
    ebegin "Restoring iptables rules"
    if [ -f /etc/iptables/rules-save ]; then
        iptables-restore < /etc/iptables/rules-save
    fi
    eend $?
}

stop() {
    ebegin "Clearing iptables rules"
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    eend $?
}
EOF
    
    chmod +x /etc/init.d/iptables-restore
    rc-update add iptables-restore default
    
    log_info "防火墙配置完成"
}

# 移除不必要的软件包
remove_unnecessary_packages() {
    log_info "移除不必要的软件包..."
    
    local remove_packages
    remove_packages=$(get_config_array "security.remove_packages")
    
    if [[ -n "$remove_packages" ]]; then
        while IFS= read -r package; do
            if [[ -n "$package" && "$package" != "null" ]]; then
                if apk info -e "$package" > /dev/null 2>&1; then
                    apk del "$package" || log_warn "无法移除软件包: $package"
                    log_info "移除软件包: $package"
                fi
            fi
        done <<< "$remove_packages"
    fi
    
    # 移除开发工具和文档
    local dev_packages=(
        "build-base"
        "gcc"
        "g++"
        "make"
        "cmake"
        "git"
        "man-pages"
        "man-pages-posix"
        "docs"
        "apk-tools-doc"
    )
    
    for package in "${dev_packages[@]}"; do
        if apk info -e "$package" > /dev/null 2>&1; then
            apk del "$package" 2>/dev/null || true
            log_info "移除开发包: $package"
        fi
    done
    
    # 清理包缓存
    apk cache clean
    rm -rf /var/cache/apk/*
    
    log_info "软件包清理完成"
}

# 服务安全配置
configure_service_security() {
    log_info "配置服务安全..."
    
    # 禁用不必要的服务
    local services_to_disable=(
        "telnet"
        "rsh"
        "rlogin"
        "vsftpd"
        "httpd"
        "nginx"
        "apache2"
    )
    
    for service in "${services_to_disable[@]}"; do
        if rc-service --exists "$service"; then
            rc-service "$service" stop 2>/dev/null || true
            rc-update del "$service" 2>/dev/null || true
            log_info "禁用服务: $service"
        fi
    done
    
    # 配置 systemd 安全选项（如果使用 systemd）
    if command -v systemctl > /dev/null 2>&1; then
        # 禁用 core dumps
        systemctl mask systemd-coredump.socket
        systemctl mask systemd-coredump@.service
    fi
    
    log_info "服务安全配置完成"
}

# 文件系统安全
configure_filesystem_security() {
    log_info "配置文件系统安全..."
    
    # 设置重要文件权限
    chmod 600 /etc/shadow
    chmod 644 /etc/passwd
    chmod 644 /etc/group
    chmod 600 /etc/gshadow 2>/dev/null || true
    
    # 设置 SSH 配置权限
    if [[ -f /etc/ssh/sshd_config ]]; then
        chmod 600 /etc/ssh/sshd_config
        chown root:root /etc/ssh/sshd_config
    fi
    
    # 创建安全的临时目录
    mkdir -p /tmp
    chmod 1777 /tmp
    
    # 设置日志目录权限
    if [[ -d /var/log ]]; then
        chmod 755 /var/log
        find /var/log -type f -exec chmod 640 {} \;
    fi
    
    # 移除世界可写文件
    find / -xdev -type f -perm -002 -exec chmod o-w {} \; 2>/dev/null || true
    
    # 查找并报告 SUID/SGID 文件
    log_info "扫描 SUID/SGID 文件..."
    find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | while read -r file; do
        log_info "发现 SUID/SGID 文件: $file"
    done
    
    log_info "文件系统安全配置完成"
}

# 网络安全配置
configure_network_security() {
    log_info "配置网络安全..."
    
    # 配置 /etc/hosts
    cat > /etc/hosts << 'EOF'
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
    
    # 配置 DNS
    local dns_servers
    dns_servers=$(get_config_array "network.dns_servers")
    
    if [[ -n "$dns_servers" ]]; then
        echo "# DNS 配置" > /etc/resolv.conf
        while IFS= read -r dns; do
            if [[ -n "$dns" && "$dns" != "null" ]]; then
                echo "nameserver $dns" >> /etc/resolv.conf
            fi
        done <<< "$dns_servers"
    else
        # 默认 DNS
        cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
    fi
    
    # 禁用 IPv6（如果不需要）
    if [[ "${CONFIG_NETWORK_DISABLE_IPV6:-false}" == "true" ]]; then
        echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.d/99-security.conf
        echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.d/99-security.conf
        sysctl -p /etc/sysctl.d/99-security.conf
        log_info "已禁用 IPv6"
    fi
    
    log_info "网络安全配置完成"
}

# 验证安全配置
verify_security_configuration() {
    log_info "验证安全配置..."
    
    local errors=0
    
    # 检查用户配置
    local k3s_user="${CONFIG_SECURITY_K3S_USER:-k3s}"
    if ! getent passwd "$k3s_user" > /dev/null 2>&1; then
        log_error "K3s 用户不存在: $k3s_user"
        ((errors++))
    else
        log_info "✓ K3s 用户存在: $k3s_user"
    fi
    
    # 检查防火墙规则
    if iptables -L INPUT | grep -q "6443"; then
        log_info "✓ K3s API Server 端口已开放"
    else
        log_error "K3s API Server 端口未开放"
        ((errors++))
    fi
    
    # 检查内核参数
    if [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]]; then
        log_info "✓ IP 转发已启用"
    else
        log_error "IP 转发未启用"
        ((errors++))
    fi
    
    # 检查文件权限
    if [[ "$(stat -c %a /etc/shadow)" == "600" ]]; then
        log_info "✓ /etc/shadow 权限正确"
    else
        log_error "/etc/shadow 权限不正确"
        ((errors++))
    fi
    
    # 检查服务状态
    if rc-service iptables-restore status > /dev/null 2>&1; then
        log_info "✓ 防火墙服务已配置"
    else
        log_warn "防火墙服务未运行"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "✓ 所有安全配置验证通过"
        return 0
    else
        log_error "发现 $errors 个安全配置问题"
        return 1
    fi
}

# 获取配置数组的辅助函数
get_config_array() {
    local key="$1"
    local config_file="${CONFIG_DIR}/template.yaml"
    
    if [[ -f "$config_file" ]]; then
        yq e ".$key[]" "$config_file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# 错误处理
trap 'log_error "脚本执行失败，退出码: $?"' ERR

# 执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi