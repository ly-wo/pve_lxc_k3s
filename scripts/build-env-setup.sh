#!/bin/bash
# Build Environment Setup Script for PVE LXC K3s Template
# 构建环境初始化脚本，负责依赖检查、工具安装和构建缓存管理

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/config/template.yaml"
LOG_DIR="${PROJECT_ROOT}/logs"
CACHE_DIR="${PROJECT_ROOT}/.cache"
BUILD_DIR="${PROJECT_ROOT}/.build"

# 创建必要的目录
mkdir -p "$LOG_DIR" "$CACHE_DIR" "$BUILD_DIR"

# 日志配置
LOG_FILE="${LOG_DIR}/build-env-setup.log"

# 日志函数
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { 
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "$@"
    fi
}

# 错误处理
error_exit() {
    log_error "$1"
    exit 1
}

# 检测操作系统
detect_os() {
    log_info "检测操作系统"
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_NAME="$PRETTY_NAME"
    elif [[ -f /etc/alpine-release ]]; then
        OS_ID="alpine"
        OS_VERSION=$(cat /etc/alpine-release)
        OS_NAME="Alpine Linux $OS_VERSION"
    elif [[ -f /etc/debian_version ]]; then
        OS_ID="debian"
        OS_VERSION=$(cat /etc/debian_version)
        OS_NAME="Debian $OS_VERSION"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_NAME="Unknown OS"
    fi
    
    log_info "操作系统: $OS_NAME"
    log_debug "OS ID: $OS_ID, Version: $OS_VERSION"
    
    # 检查支持的操作系统
    case "$OS_ID" in
        "alpine"|"debian"|"ubuntu"|"centos"|"rhel"|"fedora")
            log_info "支持的操作系统: $OS_ID"
            ;;
        *)
            log_warn "未测试的操作系统: $OS_ID，可能存在兼容性问题"
            ;;
    esac
}

# 检查系统架构
check_architecture() {
    log_info "检查系统架构"
    
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64|amd64)
            SYSTEM_ARCH="amd64"
            ;;
        aarch64|arm64)
            SYSTEM_ARCH="arm64"
            ;;
        armv7l|armhf)
            SYSTEM_ARCH="arm"
            ;;
        *)
            log_warn "未测试的架构: $arch"
            SYSTEM_ARCH="$arch"
            ;;
    esac
    
    log_info "系统架构: $SYSTEM_ARCH ($arch)"
}

# 检查系统权限
check_permissions() {
    log_info "检查系统权限"
    
    if [[ $EUID -ne 0 ]]; then
        error_exit "构建环境设置需要 root 权限"
    fi
    
    # 检查关键目录的写权限
    local test_dirs=("$PROJECT_ROOT" "$CACHE_DIR" "$BUILD_DIR" "$LOG_DIR")
    for dir in "${test_dirs[@]}"; do
        if [[ ! -w "$dir" ]]; then
            error_exit "目录没有写权限: $dir"
        fi
    done
    
    log_info "权限检查通过"
}

# 检查磁盘空间
check_disk_space() {
    log_info "检查磁盘空间"
    
    # 检查项目根目录的可用空间
    local available_kb
    available_kb=$(df "$PROJECT_ROOT" | awk 'NR==2 {print $4}')
    local available_gb=$((available_kb / 1024 / 1024))
    
    # 最小需要 5GB 空间
    local required_gb=5
    
    if [[ $available_gb -lt $required_gb ]]; then
        error_exit "磁盘空间不足: 可用 ${available_gb}GB，需要至少 ${required_gb}GB"
    fi
    
    log_info "磁盘空间检查通过: 可用 ${available_gb}GB"
    
    # 检查各个目录的空间使用情况
    if [[ -d "$CACHE_DIR" ]]; then
        local cache_size
        cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
        log_info "缓存目录大小: $cache_size"
    fi
    
    if [[ -d "$BUILD_DIR" ]]; then
        local build_size
        build_size=$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1 || echo "0")
        log_info "构建目录大小: $build_size"
    fi
}

# 检查内核模块
check_kernel_modules() {
    log_info "检查内核模块"
    
    local required_modules=("loop" "overlay" "br_netfilter" "iptable_nat")
    local missing_modules=()
    
    for module in "${required_modules[@]}"; do
        if lsmod | grep -q "^$module"; then
            log_debug "内核模块已加载: $module"
        elif modprobe "$module" 2>/dev/null; then
            log_info "成功加载内核模块: $module"
        else
            log_warn "无法加载内核模块: $module"
            missing_modules+=("$module")
        fi
    done
    
    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        log_warn "缺少内核模块: ${missing_modules[*]}"
        log_warn "某些功能可能无法正常工作"
    else
        log_info "所有必要的内核模块都可用"
    fi
}

# 安装系统依赖
install_system_dependencies() {
    log_info "安装系统依赖"
    
    local base_packages=()
    local extra_packages=()
    
    # 根据操作系统选择包管理器和包名
    case "$OS_ID" in
        "alpine")
            local pkg_manager="apk"
            base_packages=(
                "curl" "wget" "tar" "gzip" "bzip2" "xz"
                "bash" "coreutils" "util-linux" "findutils"
                "mount" "umount" "chroot"
                "iptables" "ip6tables" "bridge-utils"
                "ca-certificates" "openssl"
            )
            extra_packages=(
                "jq" "yq" "git" "rsync"
                "docker" "containerd"
                "python3" "py3-pip"
            )
            ;;
        "debian"|"ubuntu")
            local pkg_manager="apt"
            base_packages=(
                "curl" "wget" "tar" "gzip" "bzip2" "xz-utils"
                "bash" "coreutils" "util-linux" "findutils"
                "mount" "chroot"
                "iptables" "bridge-utils"
                "ca-certificates" "openssl"
            )
            extra_packages=(
                "jq" "git" "rsync"
                "docker.io" "containerd"
                "python3" "python3-pip"
            )
            ;;
        "centos"|"rhel"|"fedora")
            local pkg_manager="yum"
            if command -v dnf >/dev/null 2>&1; then
                pkg_manager="dnf"
            fi
            base_packages=(
                "curl" "wget" "tar" "gzip" "bzip2" "xz"
                "bash" "coreutils" "util-linux" "findutils"
                "mount" "chroot"
                "iptables" "bridge-utils"
                "ca-certificates" "openssl"
            )
            extra_packages=(
                "jq" "git" "rsync"
                "docker" "containerd"
                "python3" "python3-pip"
            )
            ;;
        *)
            log_warn "未知的操作系统，跳过包安装"
            return 0
            ;;
    esac
    
    # 更新包索引
    log_info "更新包索引"
    case "$pkg_manager" in
        "apk")
            apk update
            ;;
        "apt")
            apt-get update
            ;;
        "yum"|"dnf")
            $pkg_manager makecache
            ;;
    esac
    
    # 安装基础包
    log_info "安装基础依赖包"
    for package in "${base_packages[@]}"; do
        if ! install_package "$pkg_manager" "$package"; then
            log_warn "基础包安装失败: $package"
        fi
    done
    
    # 安装额外包（可选）
    log_info "安装额外工具包"
    for package in "${extra_packages[@]}"; do
        if ! install_package "$pkg_manager" "$package"; then
            log_debug "额外包安装失败（可选）: $package"
        fi
    done
    
    log_info "系统依赖安装完成"
}

# 安装单个包的辅助函数
install_package() {
    local pkg_manager="$1"
    local package="$2"
    
    # 检查包是否已安装
    case "$pkg_manager" in
        "apk")
            if apk info -e "$package" >/dev/null 2>&1; then
                log_debug "包已安装: $package"
                return 0
            fi
            apk add --no-cache "$package"
            ;;
        "apt")
            if dpkg -l "$package" >/dev/null 2>&1; then
                log_debug "包已安装: $package"
                return 0
            fi
            apt-get install -y "$package"
            ;;
        "yum"|"dnf")
            if rpm -q "$package" >/dev/null 2>&1; then
                log_debug "包已安装: $package"
                return 0
            fi
            $pkg_manager install -y "$package"
            ;;
        *)
            log_error "不支持的包管理器: $pkg_manager"
            return 1
            ;;
    esac
}

# 验证必要工具
verify_required_tools() {
    log_info "验证必要工具"
    
    local required_tools=(
        "curl" "wget" "tar" "gzip"
        "bash" "mount" "umount" "chroot"
        "iptables" "sha256sum"
    )
    
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version
            case "$tool" in
                "bash")
                    version=$($tool --version | head -n1 | awk '{print $4}')
                    ;;
                "curl")
                    version=$($tool --version | head -n1 | awk '{print $2}')
                    ;;
                "tar")
                    version=$($tool --version | head -n1 | awk '{print $4}')
                    ;;
                *)
                    version="installed"
                    ;;
            esac
            log_debug "工具可用: $tool ($version)"
        else
            log_error "必要工具缺失: $tool"
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error_exit "缺少必要工具: ${missing_tools[*]}"
    fi
    
    log_info "所有必要工具验证通过"
}

# 安装可选工具
install_optional_tools() {
    log_info "安装可选工具"
    
    # 安装 yq (YAML 处理工具)
    if ! command -v yq >/dev/null 2>&1; then
        log_info "安装 yq"
        local yq_version="v4.35.2"
        local yq_binary="yq_linux_${SYSTEM_ARCH}"
        local yq_url="https://github.com/mikefarah/yq/releases/download/${yq_version}/${yq_binary}"
        
        if curl -fsSL "$yq_url" -o /usr/local/bin/yq; then
            chmod +x /usr/local/bin/yq
            log_info "yq 安装成功"
        else
            log_warn "yq 安装失败，将使用替代方案"
        fi
    fi
    
    # 安装 jq (JSON 处理工具)
    if ! command -v jq >/dev/null 2>&1; then
        log_info "尝试安装 jq"
        case "$OS_ID" in
            "alpine")
                apk add --no-cache jq || log_warn "jq 安装失败"
                ;;
            "debian"|"ubuntu")
                apt-get install -y jq || log_warn "jq 安装失败"
                ;;
            "centos"|"rhel"|"fedora")
                yum install -y jq || dnf install -y jq || log_warn "jq 安装失败"
                ;;
        esac
    fi
    
    # 验证 Docker（如果需要）
    if command -v docker >/dev/null 2>&1; then
        if docker --version >/dev/null 2>&1; then
            log_info "Docker 可用: $(docker --version)"
        else
            log_warn "Docker 已安装但无法运行"
        fi
    else
        log_info "Docker 未安装（可选）"
    fi
}

# 设置构建缓存
setup_build_cache() {
    log_info "设置构建缓存"
    
    # 创建缓存目录结构
    local cache_dirs=(
        "$CACHE_DIR/images"
        "$CACHE_DIR/packages"
        "$CACHE_DIR/downloads"
        "$CACHE_DIR/temp"
    )
    
    for dir in "${cache_dirs[@]}"; do
        mkdir -p "$dir"
        log_debug "创建缓存目录: $dir"
    done
    
    # 设置缓存权限
    chmod 755 "$CACHE_DIR"
    chmod 755 "$CACHE_DIR"/*
    
    # 创建缓存配置文件
    cat > "$CACHE_DIR/cache-config.json" << EOF
{
    "version": "1.0",
    "created": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "directories": {
        "images": "$CACHE_DIR/images",
        "packages": "$CACHE_DIR/packages", 
        "downloads": "$CACHE_DIR/downloads",
        "temp": "$CACHE_DIR/temp"
    },
    "settings": {
        "max_age_days": 30,
        "max_size_gb": 10,
        "cleanup_enabled": true
    }
}
EOF
    
    log_info "构建缓存设置完成"
}

# 清理构建缓存
cleanup_build_cache() {
    local max_age_days="${1:-30}"
    local max_size_gb="${2:-10}"
    
    log_info "清理构建缓存 (保留 $max_age_days 天，最大 ${max_size_gb}GB)"
    
    if [[ ! -d "$CACHE_DIR" ]]; then
        log_info "缓存目录不存在，跳过清理"
        return 0
    fi
    
    # 按时间清理
    log_info "清理超过 $max_age_days 天的缓存文件"
    find "$CACHE_DIR" -type f -mtime +$max_age_days -delete 2>/dev/null || true
    
    # 按大小清理
    local current_size_gb
    current_size_gb=$(du -s "$CACHE_DIR" | awk '{print int($1/1024/1024)}')
    
    if [[ $current_size_gb -gt $max_size_gb ]]; then
        log_info "缓存大小超限 (${current_size_gb}GB > ${max_size_gb}GB)，清理最旧的文件"
        
        # 删除最旧的文件直到大小符合要求
        find "$CACHE_DIR" -type f -printf '%T@ %p\n' | sort -n | while read -r timestamp file; do
            rm -f "$file"
            current_size_gb=$(du -s "$CACHE_DIR" | awk '{print int($1/1024/1024)}')
            if [[ $current_size_gb -le $max_size_gb ]]; then
                break
            fi
        done
    fi
    
    # 清理空目录
    find "$CACHE_DIR" -type d -empty -delete 2>/dev/null || true
    
    # 更新缓存统计
    local final_size
    final_size=$(du -sh "$CACHE_DIR" | cut -f1)
    log_info "缓存清理完成，当前大小: $final_size"
}

# 验证构建环境
verify_build_environment() {
    log_info "验证构建环境"
    
    local errors=0
    
    # 检查必要工具
    local tools=("curl" "wget" "tar" "gzip" "bash" "mount" "chroot")
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_debug "✓ 工具可用: $tool"
        else
            log_error "✗ 工具缺失: $tool"
            ((errors++))
        fi
    done
    
    # 检查目录权限
    local dirs=("$PROJECT_ROOT" "$CACHE_DIR" "$BUILD_DIR" "$LOG_DIR")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" && -w "$dir" ]]; then
            log_debug "✓ 目录可写: $dir"
        else
            log_error "✗ 目录不可写: $dir"
            ((errors++))
        fi
    done
    
    # 检查内核模块
    local modules=("loop" "overlay")
    for module in "${modules[@]}"; do
        if lsmod | grep -q "^$module" || modprobe "$module" 2>/dev/null; then
            log_debug "✓ 内核模块可用: $module"
        else
            log_warn "⚠ 内核模块不可用: $module"
        fi
    done
    
    # 检查磁盘空间
    local available_gb
    available_gb=$(df "$PROJECT_ROOT" | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $available_gb -ge 5 ]]; then
        log_debug "✓ 磁盘空间充足: ${available_gb}GB"
    else
        log_error "✗ 磁盘空间不足: ${available_gb}GB < 5GB"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "✓ 构建环境验证通过"
        return 0
    else
        log_error "✗ 构建环境验证失败，发现 $errors 个问题"
        return 1
    fi
}

# 生成环境信息报告
generate_environment_report() {
    local report_file="${PROJECT_ROOT}/build-environment-report.txt"
    
    log_info "生成环境信息报告: $report_file"
    
    cat > "$report_file" << EOF
# Build Environment Report

## System Information
OS: $OS_NAME
Architecture: $SYSTEM_ARCH ($(uname -m))
Kernel: $(uname -r)
Hostname: $(hostname)
Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

## Available Tools
$(for tool in curl wget tar gzip bash mount chroot iptables docker jq yq; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "$tool: $(command -v "$tool") ($(${tool} --version 2>/dev/null | head -n1 || echo "version unknown"))"
    else
        echo "$tool: not available"
    fi
done)

## Disk Space
$(df -h "$PROJECT_ROOT")

## Cache Information
Cache Directory: $CACHE_DIR
Cache Size: $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")

## Kernel Modules
$(lsmod | grep -E "(loop|overlay|br_netfilter|iptable)" || echo "No relevant modules loaded")

## Environment Variables
PATH=$PATH
HOME=$HOME
USER=$(whoami)
SHELL=$SHELL

## Build Configuration
Project Root: $PROJECT_ROOT
Config File: $CONFIG_FILE
Log Directory: $LOG_DIR
Build Directory: $BUILD_DIR
Cache Directory: $CACHE_DIR

EOF
    
    log_info "环境信息报告生成完成"
}

# 主函数
main() {
    local action="${1:-setup}"
    
    case "$action" in
        "setup")
            log_info "开始构建环境设置"
            detect_os
            check_architecture
            check_permissions
            check_disk_space
            check_kernel_modules
            install_system_dependencies
            verify_required_tools
            install_optional_tools
            setup_build_cache
            
            if verify_build_environment; then
                log_info "构建环境设置完成"
                generate_environment_report
            else
                error_exit "构建环境设置失败"
            fi
            ;;
        "verify")
            log_info "验证构建环境"
            detect_os
            check_architecture
            verify_build_environment
            ;;
        "cleanup")
            log_info "清理构建缓存"
            cleanup_build_cache "${2:-30}" "${3:-10}"
            ;;
        "report")
            log_info "生成环境报告"
            detect_os
            check_architecture
            generate_environment_report
            ;;
        "reset")
            log_info "重置构建环境"
            rm -rf "$CACHE_DIR" "$BUILD_DIR"
            mkdir -p "$CACHE_DIR" "$BUILD_DIR"
            log_info "构建环境已重置"
            ;;
        *)
            echo "用法: $0 {setup|verify|cleanup|report|reset}"
            echo "  setup    - 设置构建环境"
            echo "  verify   - 验证构建环境"
            echo "  cleanup  - 清理构建缓存 [天数] [大小GB]"
            echo "  report   - 生成环境报告"
            echo "  reset    - 重置构建环境"
            exit 1
            ;;
    esac
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi