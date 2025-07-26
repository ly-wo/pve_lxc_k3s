#!/bin/bash
# PVE LXC K3s Template Builder - Main Build Script
# 主构建脚本，协调整个模板构建流程

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/config/template.yaml"
LOG_DIR="${PROJECT_ROOT}/logs"
BUILD_DIR="${PROJECT_ROOT}/.build"
CACHE_DIR="${PROJECT_ROOT}/.cache"

# 加载统一日志系统
source "${SCRIPT_DIR}/logging.sh"

# 创建必要的目录
mkdir -p "$LOG_DIR" "$BUILD_DIR" "$CACHE_DIR"

# 日志配置
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export LOG_FORMAT="${LOG_FORMAT:-structured}"
BUILD_LOG="build-$(date +%Y%m%d-%H%M%S).log"

# 组件名称
COMPONENT="build-template"

# 进度跟踪
TOTAL_STEPS=10
CURRENT_STEP=0

show_progress() {
    local step_name="$1"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local context="{\"step\": $CURRENT_STEP, \"total_steps\": $TOTAL_STEPS, \"percentage\": $percentage}"
    log_info "$COMPONENT" "$COMPONENT" "[$CURRENT_STEP/$TOTAL_STEPS] ($percentage%) $step_name" "$context" "" "" "$BUILD_LOG"
}

# 性能监控
start_time=""
start_timer() {
    start_time=$(date +%s)
}

end_timer() {
    local operation="$1"
    if [[ -n "$start_time" ]]; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local context="{\"start_time\": $start_time, \"end_time\": $end_time}"
        log_performance "$COMPONENT" "$operation" "${duration}s" "$context"
    fi
}

# 错误处理
error_exit() {
    local error_message="$1"
    local exit_code="${2:-1}"
    log_error "$COMPONENT" "$COMPONENT" "$error_message"
    log_error "$COMPONENT" "$COMPONENT" "构建失败，退出码: $exit_code"
    cleanup_on_error
    exit "$exit_code"
}

# 错误时清理
cleanup_on_error() {
    log_info "$COMPONENT" "$COMPONENT" "执行错误清理..."
    
    # 卸载可能的挂载点
    if mountpoint -q "${BUILD_DIR}/rootfs" 2>/dev/null; then
        umount "${BUILD_DIR}/rootfs" || true
    fi
    
    # 清理临时文件
    rm -rf "${BUILD_DIR}/temp" || true
    
    log_info "$COMPONENT" "$COMPONENT" "错误清理完成"
}

# 信号处理
trap 'error_exit "构建过程被中断" 130' INT TERM
trap 'cleanup_on_error' EXIT

# 加载配置
load_configuration() {
    show_progress "加载配置文件"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "配置文件不存在: $CONFIG_FILE"
    fi
    
    # 验证配置文件格式
    if ! "${SCRIPT_DIR}/config-validator.sh" "$CONFIG_FILE"; then
        error_exit "配置文件验证失败"
    fi
    
    # 加载配置变量
    source "${SCRIPT_DIR}/config-loader.sh"
    
    # 读取关键配置
    TEMPLATE_NAME=$(get_config "template.name" "alpine-k3s")
    TEMPLATE_VERSION=$(get_config "template.version" "1.0.0")
    BASE_IMAGE=$(get_config "template.base_image" "alpine:3.18")
    ARCHITECTURE=$(get_config "template.architecture" "amd64")
    K3S_VERSION=$(get_config "k3s.version")
    
    # 验证必要配置
    if [[ -z "$K3S_VERSION" ]]; then
        error_exit "K3s 版本未在配置中指定"
    fi
    
    log_info "$COMPONENT" "$COMPONENT" "配置加载完成:"
    log_info "$COMPONENT" "$COMPONENT" "  模板名称: $TEMPLATE_NAME"
    log_info "$COMPONENT" "$COMPONENT" "  模板版本: $TEMPLATE_VERSION"
    log_info "$COMPONENT" "$COMPONENT" "  基础镜像: $BASE_IMAGE"
    log_info "$COMPONENT" "$COMPONENT" "  系统架构: $ARCHITECTURE"
    log_info "$COMPONENT" "$COMPONENT" "  K3s 版本: $K3S_VERSION"
}

# 检查构建环境
check_build_environment() {
    show_progress "检查构建环境"
    
    # 检查必要的命令
    local required_commands=("curl" "wget" "tar" "gzip" "chroot" "mount" "umount")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error_exit "必要命令不存在: $cmd"
        fi
    done
    
    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        error_exit "构建脚本需要 root 权限运行"
    fi
    
    # 检查磁盘空间
    local available_space
    available_space=$(df "$BUILD_DIR" | awk 'NR==2 {print $4}')
    local required_space=2097152  # 2GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        error_exit "磁盘空间不足，需要至少 2GB 可用空间"
    fi
    
    # 检查内核模块
    local required_modules=("loop" "overlay")
    for module in "${required_modules[@]}"; do
        if ! lsmod | grep -q "^$module"; then
            if ! modprobe "$module"; then
                error_exit "无法加载内核模块: $module"
            fi
        fi
    done
    
    log_info "$COMPONENT" "构建环境检查通过"
}

# 准备构建目录
prepare_build_directory() {
    show_progress "准备构建目录"
    
    # 清理旧的构建目录
    if [[ -d "$BUILD_DIR" ]]; then
        log_info "$COMPONENT" "清理旧的构建目录"
        rm -rf "$BUILD_DIR"
    fi
    
    # 创建构建目录结构
    mkdir -p "$BUILD_DIR"/{rootfs,temp,output}
    
    # 设置权限
    chmod 755 "$BUILD_DIR"
    
    log_info "$COMPONENT" "构建目录准备完成: $BUILD_DIR"
}

# 下载基础镜像
download_base_image() {
    show_progress "下载基础镜像"
    
    log_info "$COMPONENT" "开始下载基础镜像: $BASE_IMAGE"
    
    if ! "${SCRIPT_DIR}/base-image-manager.sh" download; then
        error_exit "基础镜像下载失败"
    fi
    
    log_info "$COMPONENT" "基础镜像下载完成"
}

# 提取基础镜像
extract_base_image() {
    show_progress "提取基础镜像"
    
    local image_name="${BASE_IMAGE%:*}"
    local image_tag="${BASE_IMAGE#*:}"
    local cache_path="${CACHE_DIR}/images/${image_name}_${image_tag}_${ARCHITECTURE}.tar.gz"
    
    if [[ ! -f "$cache_path" ]]; then
        error_exit "基础镜像文件不存在: $cache_path"
    fi
    
    log_info "$COMPONENT" "提取基础镜像到: ${BUILD_DIR}/rootfs"
    
    # 提取镜像
    if ! tar -xzf "$cache_path" -C "${BUILD_DIR}/rootfs"; then
        error_exit "基础镜像提取失败"
    fi
    
    # 验证提取结果
    if [[ ! -d "${BUILD_DIR}/rootfs/bin" ]] || [[ ! -d "${BUILD_DIR}/rootfs/etc" ]]; then
        error_exit "基础镜像提取不完整"
    fi
    
    log_info "$COMPONENT" "基础镜像提取完成"
}

# 系统优化
optimize_system() {
    show_progress "系统优化"
    
    log_info "$COMPONENT" "开始系统优化"
    
    if ! "${SCRIPT_DIR}/system-optimizer.sh" optimize; then
        error_exit "系统优化失败"
    fi
    
    # 在 chroot 环境中执行优化
    if ! "${SCRIPT_DIR}/base-image-manager.sh" optimize "${BUILD_DIR}/rootfs"; then
        error_exit "系统包管理和优化失败"
    fi
    
    log_info "$COMPONENT" "系统优化完成"
}

# 安装 K3s
install_k3s() {
    show_progress "安装 K3s"
    
    log_info "$COMPONENT" "开始安装 K3s"
    
    # 在 chroot 环境中安装 K3s
    cat > "${BUILD_DIR}/rootfs/tmp/install_k3s.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# 设置环境变量
export PATH="/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin"

# 执行 K3s 安装
cd /tmp
if [[ -f "/scripts/k3s-installer.sh" ]]; then
    /scripts/k3s-installer.sh install
else
    echo "ERROR: K3s installer script not found"
    exit 1
fi
EOF
    
    # 复制安装脚本到 chroot 环境
    mkdir -p "${BUILD_DIR}/rootfs/scripts"
    cp "${SCRIPT_DIR}/k3s-installer.sh" "${BUILD_DIR}/rootfs/scripts/"
    cp "${SCRIPT_DIR}/config-loader.sh" "${BUILD_DIR}/rootfs/scripts/"
    cp "$CONFIG_FILE" "${BUILD_DIR}/rootfs/tmp/"
    
    # 设置权限
    chmod +x "${BUILD_DIR}/rootfs/tmp/install_k3s.sh"
    chmod +x "${BUILD_DIR}/rootfs/scripts/k3s-installer.sh"
    
    # 执行安装
    if ! chroot "${BUILD_DIR}/rootfs" /tmp/install_k3s.sh; then
        error_exit "K3s 安装失败"
    fi
    
    # 清理安装脚本
    rm -f "${BUILD_DIR}/rootfs/tmp/install_k3s.sh"
    rm -rf "${BUILD_DIR}/rootfs/scripts"
    rm -f "${BUILD_DIR}/rootfs/tmp/template.yaml"
    
    log_info "$COMPONENT" "K3s 安装完成"
}

# 配置 K3s 服务
configure_k3s_service() {
    show_progress "配置 K3s 服务"
    
    log_info "$COMPONENT" "配置 K3s 服务"
    
    # 在 chroot 环境中配置服务
    cat > "${BUILD_DIR}/rootfs/tmp/configure_k3s.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# 复制服务配置脚本
if [[ -f "/scripts/k3s-service.sh" ]]; then
    /scripts/k3s-service.sh configure
else
    echo "ERROR: K3s service script not found"
    exit 1
fi
EOF
    
    # 复制服务脚本
    mkdir -p "${BUILD_DIR}/rootfs/scripts"
    cp "${SCRIPT_DIR}/k3s-service.sh" "${BUILD_DIR}/rootfs/scripts/"
    
    chmod +x "${BUILD_DIR}/rootfs/tmp/configure_k3s.sh"
    chmod +x "${BUILD_DIR}/rootfs/scripts/k3s-service.sh"
    
    # 执行配置
    if ! chroot "${BUILD_DIR}/rootfs" /tmp/configure_k3s.sh; then
        error_exit "K3s 服务配置失败"
    fi
    
    # 清理脚本
    rm -f "${BUILD_DIR}/rootfs/tmp/configure_k3s.sh"
    rm -rf "${BUILD_DIR}/rootfs/scripts"
    
    log_info "$COMPONENT" "K3s 服务配置完成"
}

# 安全加固
apply_security_hardening() {
    show_progress "安全加固"
    
    log_info "$COMPONENT" "开始安全加固"
    
    # 在 chroot 环境中执行安全加固
    cat > "${BUILD_DIR}/rootfs/tmp/security_hardening.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# 复制安全加固脚本和配置
if [[ -f "/scripts/security-hardening.sh" ]]; then
    /scripts/security-hardening.sh
else
    echo "ERROR: Security hardening script not found"
    exit 1
fi
EOF
    
    # 复制安全脚本和配置
    mkdir -p "${BUILD_DIR}/rootfs/scripts"
    mkdir -p "${BUILD_DIR}/rootfs/config"
    cp "${SCRIPT_DIR}/security-hardening.sh" "${BUILD_DIR}/rootfs/scripts/"
    cp "${SCRIPT_DIR}/config-loader.sh" "${BUILD_DIR}/rootfs/scripts/"
    cp "$CONFIG_FILE" "${BUILD_DIR}/rootfs/config/"
    
    chmod +x "${BUILD_DIR}/rootfs/tmp/security_hardening.sh"
    chmod +x "${BUILD_DIR}/rootfs/scripts/security-hardening.sh"
    
    # 执行安全加固
    if ! chroot "${BUILD_DIR}/rootfs" /tmp/security_hardening.sh; then
        error_exit "安全加固失败"
    fi
    
    # 清理脚本
    rm -f "${BUILD_DIR}/rootfs/tmp/security_hardening.sh"
    rm -rf "${BUILD_DIR}/rootfs/scripts"
    rm -rf "${BUILD_DIR}/rootfs/config"
    
    log_info "$COMPONENT" "安全加固完成"
}

# 最终清理和优化
final_cleanup() {
    show_progress "最终清理和优化"
    
    log_info "$COMPONENT" "执行最终清理"
    
    # 清理临时文件
    rm -rf "${BUILD_DIR}/rootfs/tmp"/*
    rm -rf "${BUILD_DIR}/rootfs/var/cache/apk"/*
    rm -rf "${BUILD_DIR}/rootfs/var/log"/*
    
    # 清理包管理器缓存
    chroot "${BUILD_DIR}/rootfs" /bin/sh -c "apk cache clean" || true
    
    # 创建必要的空目录
    mkdir -p "${BUILD_DIR}/rootfs/tmp"
    mkdir -p "${BUILD_DIR}/rootfs/var/log"
    mkdir -p "${BUILD_DIR}/rootfs/var/cache/apk"
    
    # 设置正确的权限
    chmod 1777 "${BUILD_DIR}/rootfs/tmp"
    chmod 755 "${BUILD_DIR}/rootfs/var/log"
    
    # 生成模板信息文件
    cat > "${BUILD_DIR}/rootfs/etc/lxc-template-info" << EOF
# PVE LXC K3s Template Information
Template Name: $TEMPLATE_NAME
Template Version: $TEMPLATE_VERSION
Build Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Base Image: $BASE_IMAGE
Architecture: $ARCHITECTURE
K3s Version: $K3S_VERSION
Builder: PVE LXC K3s Template Generator

# Build Configuration
$(cat "$CONFIG_FILE")
EOF
    
    log_info "$COMPONENT" "最终清理完成"
}

# 验证构建结果
verify_build() {
    show_progress "验证构建结果"
    
    log_info "$COMPONENT" "验证构建结果"
    
    local errors=0
    
    # 检查关键文件和目录
    local critical_paths=(
        "/usr/local/bin/k3s"
        "/etc/rancher/k3s"
        "/var/lib/rancher/k3s"
        "/etc/lxc-template-info"
    )
    
    for path in "${critical_paths[@]}"; do
        if [[ ! -e "${BUILD_DIR}/rootfs${path}" ]]; then
            log_error "$COMPONENT" "关键路径不存在: $path"
            ((errors++))
        else
            log_info "$COMPONENT" "✓ 验证通过: $path"
        fi
    done
    
    # 检查 K3s 二进制文件
    if [[ -x "${BUILD_DIR}/rootfs/usr/local/bin/k3s" ]]; then
        local k3s_version
        k3s_version=$(chroot "${BUILD_DIR}/rootfs" /usr/local/bin/k3s --version | head -n1 | awk '{print $3}')
        if [[ "$k3s_version" == "$K3S_VERSION" ]]; then
            log_info "$COMPONENT" "✓ K3s 版本验证通过: $k3s_version"
        else
            log_error "$COMPONENT" "K3s 版本不匹配: 期望 $K3S_VERSION, 实际 $k3s_version"
            ((errors++))
        fi
    else
        log_error "$COMPONENT" "K3s 二进制文件不存在或不可执行"
        ((errors++))
    fi
    
    # 检查配置文件
    if [[ -f "${BUILD_DIR}/rootfs/etc/rancher/k3s/config.yaml" ]]; then
        log_info "$COMPONENT" "✓ K3s 配置文件存在"
    else
        log_error "$COMPONENT" "K3s 配置文件不存在"
        ((errors++))
    fi
    
    # 计算根文件系统大小
    local rootfs_size
    rootfs_size=$(du -sh "${BUILD_DIR}/rootfs" | cut -f1)
    log_info "$COMPONENT" "根文件系统大小: $rootfs_size"
    
    if [[ $errors -eq 0 ]]; then
        log_info "$COMPONENT" "✓ 构建验证通过"
        return 0
    else
        log_error "$COMPONENT" "构建验证失败，发现 $errors 个错误"
        return 1
    fi
}

# 生成构建报告
generate_build_report() {
    local report_file="${BUILD_DIR}/build-report.txt"
    
    log_info "$COMPONENT" "生成构建报告: $report_file"
    
    cat > "$report_file" << EOF
# PVE LXC K3s Template Build Report

## Build Information
Build Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Build Host: $(hostname)
Build User: $(whoami)
Build Directory: $BUILD_DIR

## Template Information
Template Name: $TEMPLATE_NAME
Template Version: $TEMPLATE_VERSION
Base Image: $BASE_IMAGE
Architecture: $ARCHITECTURE
K3s Version: $K3S_VERSION

## Build Statistics
Root Filesystem Size: $(du -sh "${BUILD_DIR}/rootfs" | cut -f1)
Total Build Time: $((SECONDS / 60)) minutes $((SECONDS % 60)) seconds
Build Steps Completed: $CURRENT_STEP/$TOTAL_STEPS

## File Counts
Total Files: $(find "${BUILD_DIR}/rootfs" -type f | wc -l)
Total Directories: $(find "${BUILD_DIR}/rootfs" -type d | wc -l)
Executable Files: $(find "${BUILD_DIR}/rootfs" -type f -executable | wc -l)

## Package Information
$(chroot "${BUILD_DIR}/rootfs" apk list --installed | wc -l) packages installed

## Build Logs
Main Log: $LOG_FILE
Build Log: $BUILD_LOG

## Next Steps
1. Package the template using packager.sh
2. Test the template deployment
3. Upload to distribution repository

EOF
    
    log_info "$COMPONENT" "构建报告生成完成"
}

# 主构建函数
main() {
    local start_time=$SECONDS
    
    log_info "$COMPONENT" "=========================================="
    log_info "$COMPONENT" "PVE LXC K3s Template Builder 开始构建"
    log_info "$COMPONENT" "=========================================="
    
    # 执行构建步骤
    load_configuration
    check_build_environment
    prepare_build_directory
    download_base_image
    extract_base_image
    optimize_system
    install_k3s
    configure_k3s_service
    apply_security_hardening
    final_cleanup
    
    # 验证构建结果
    if verify_build; then
        log_info "$COMPONENT" "构建成功完成"
        generate_build_report
        
        local build_time=$((SECONDS - start_time))
        log_info "$COMPONENT" "总构建时间: $((build_time / 60)) 分钟 $((build_time % 60)) 秒"
        log_info "$COMPONENT" "构建输出目录: $BUILD_DIR"
        
        # 清理成功标志
        trap - EXIT
        
        return 0
    else
        error_exit "构建验证失败"
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
PVE LXC K3s Template Builder

用法: $0 [选项]

选项:
    --config FILE       指定配置文件路径 (默认: config/template.yaml)
    --build-dir DIR     指定构建目录 (默认: .build)
    --debug             启用调试输出
    --clean             构建前清理缓存
    --help              显示此帮助信息

环境变量:
    DEBUG=true          启用调试输出
    BUILD_PARALLEL=N    并行构建任务数 (默认: 2)

示例:
    # 使用默认配置构建
    $0
    
    # 启用调试模式构建
    $0 --debug
    
    # 使用自定义配置文件
    $0 --config /path/to/config.yaml
    
    # 清理缓存后构建
    $0 --clean

EOF
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
            --debug)
                export DEBUG=true
                shift
                ;;
            --clean)
                log_info "$COMPONENT" "清理缓存目录"
                rm -rf "$CACHE_DIR"
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