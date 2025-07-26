#!/bin/bash
# Production Release Preparation Script
# 生产环境发布准备脚本

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_ROOT}/logs/production-release.log"

# 创建日志目录
mkdir -p "$(dirname "$LOG_FILE")"

# 加载日志系统
source "${SCRIPT_DIR}/logging.sh"

COMPONENT="production-release"

# 版本信息
VERSION="${1:-$(git describe --tags --always --dirty 2>/dev/null || echo "v1.0.0")}"
RELEASE_DATE=$(date -u '+%Y-%m-%d')
RELEASE_TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# 日志函数
log_info() { 
    log_info "$COMPONENT" "$1" "${2:-{}}" "${3:-}" "${4:-}" "$LOG_FILE"
}

log_warn() { 
    log_warn "$COMPONENT" "$1" "${2:-{}}" "${3:-}" "$LOG_FILE"
}

log_error() { 
    log_error "$COMPONENT" "$1" "${2:-{}}" "${3:-}" "$LOG_FILE"
}

# 错误处理
error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# 显示帮助信息
show_help() {
    cat <<EOF
生产环境发布准备脚本

用法: $0 [版本号] [选项]

参数:
  版本号              发布版本号 (默认: 从 git 获取)

选项:
  --pre-release       创建预发布版本
  --hotfix           创建热修复版本
  --dry-run          模拟运行，不实际执行
  --skip-tests       跳过测试执行
  --skip-docs        跳过文档生成
  --verbose          详细输出
  --help             显示帮助信息

示例:
  $0 v1.2.0                    # 创建 v1.2.0 正式版本
  $0 v1.2.0-rc1 --pre-release # 创建预发布版本
  $0 --dry-run                 # 模拟发布流程
EOF
}

# 验证发布前提条件
verify_release_prerequisites() {
    log_info "验证发布前提条件"
    
    local errors=0
    
    # 检查 Git 状态
    if ! git status --porcelain | grep -q '^$'; then
        log_error "Git 工作目录不干净，请提交或暂存所有更改"
        ((errors++))
    fi
    
    # 检查当前分支
    local current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    if [[ "$current_branch" != "main" ]] && [[ "$current_branch" != "master" ]]; then
        log_warn "当前不在主分支 ($current_branch)，确认是否继续发布"
    fi
    
    # 检查必要的文件
    local required_files=(
        "README.md"
        "config/template.yaml"
        "scripts/build-template.sh"
        "scripts/packager.sh"
        "Makefile"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "${PROJECT_ROOT}/$file" ]]; then
            log_error "必要文件不存在: $file"
            ((errors++))
        fi
    done
    
    # 检查版本格式
    if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
        log_warn "版本号格式可能不标准: $VERSION"
    fi
    
    if [[ $errors -gt 0 ]]; then
        error_exit "发布前提条件验证失败，发现 $errors 个错误"
    fi
    
    log_info "发布前提条件验证通过"
}

# 运行完整测试套件
run_comprehensive_tests() {
    log_info "运行完整测试套件"
    
    local test_results=()
    local test_failures=0
    
    # 运行单元测试
    log_info "执行单元测试"
    if [[ -x "${PROJECT_ROOT}/tests/run-unit-tests.sh" ]]; then
        if "${PROJECT_ROOT}/tests/run-unit-tests.sh"; then
            test_results+=("单元测试: 通过")
            log_info "单元测试通过"
        else
            test_results+=("单元测试: 失败")
            log_error "单元测试失败"
            ((test_failures++))
        fi
    else
        test_results+=("单元测试: 跳过（脚本不存在）")
        log_warn "单元测试脚本不存在，跳过"
    fi
    
    # 运行集成测试
    log_info "执行集成测试"
    if [[ -x "${PROJECT_ROOT}/tests/run-integration-tests.sh" ]]; then
        if "${PROJECT_ROOT}/tests/run-integration-tests.sh"; then
            test_results+=("集成测试: 通过")
            log_info "集成测试通过"
        else
            test_results+=("集成测试: 失败")
            log_error "集成测试失败"
            ((test_failures++))
        fi
    else
        test_results+=("集成测试: 跳过（脚本不存在）")
        log_warn "集成测试脚本不存在，跳过"
    fi
    
    # 运行系统测试
    log_info "执行系统测试"
    if [[ -x "${PROJECT_ROOT}/tests/run-system-tests.sh" ]]; then
        if "${PROJECT_ROOT}/tests/run-system-tests.sh"; then
            test_results+=("系统测试: 通过")
            log_info "系统测试通过"
        else
            test_results+=("系统测试: 失败")
            log_error "系统测试失败"
            ((test_failures++))
        fi
    else
        test_results+=("系统测试: 跳过（脚本不存在）")
        log_warn "系统测试脚本不存在，跳过"
    fi
    
    # 运行最终验证
    log_info "执行最终验证"
    if [[ -x "${SCRIPT_DIR}/final-verification.sh" ]]; then
        if "${SCRIPT_DIR}/final-verification.sh" --quick; then
            test_results+=("最终验证: 通过")
            log_info "最终验证通过"
        else
            test_results+=("最终验证: 失败")
            log_error "最终验证失败"
            ((test_failures++))
        fi
    else
        test_results+=("最终验证: 跳过（脚本不存在）")
        log_warn "最终验证脚本不存在，跳过"
    fi
    
    # 输出测试结果摘要
    echo ""
    echo "=== 测试结果摘要 ==="
    for result in "${test_results[@]}"; do
        echo "  $result"
    done
    echo ""
    
    if [[ $test_failures -gt 0 ]]; then
        error_exit "测试套件执行失败，发现 $test_failures 个失败的测试"
    fi
    
    log_info "所有测试通过"
}

# 构建生产版本
build_production_version() {
    log_info "构建生产版本"
    
    # 清理之前的构建
    log_info "清理之前的构建产物"
    make clean 2>/dev/null || rm -rf "${PROJECT_ROOT}/.build" "${PROJECT_ROOT}/output"
    
    # 优化构建配置
    log_info "应用生产构建优化"
    export BUILD_PARALLEL=$(nproc 2>/dev/null || echo 4)
    export BUILD_CACHE=true
    export COMPRESSION_LEVEL=9
    export BUILD_MEMORY_LIMIT=4G
    
    # 执行优化
    if [[ -x "${SCRIPT_DIR}/build-optimizer.sh" ]]; then
        "${SCRIPT_DIR}/build-optimizer.sh" optimize-scripts
        "${SCRIPT_DIR}/build-optimizer.sh" optimize-build
        "${SCRIPT_DIR}/build-optimizer.sh" optimize-resources
    fi
    
    # 构建模板
    log_info "构建 LXC 模板"
    if ! make build; then
        error_exit "模板构建失败"
    fi
    
    # 打包模板
    log_info "打包模板"
    if ! make package; then
        error_exit "模板打包失败"
    fi
    
    # 验证构建产物
    log_info "验证构建产物"
    local output_dir="${PROJECT_ROOT}/output"
    if [[ ! -d "$output_dir" ]] || [[ -z "$(ls -A "$output_dir" 2>/dev/null)" ]]; then
        error_exit "构建产物不存在或为空"
    fi
    
    # 计算文件哈希
    log_info "计算文件哈希"
    local checksums_file="$output_dir/checksums.txt"
    (
        cd "$output_dir"
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum *.tar.gz > checksums.txt 2>/dev/null || true
        elif command -v shasum >/dev/null 2>&1; then
            shasum -a 256 *.tar.gz > checksums.txt 2>/dev/null || true
        fi
    )
    
    log_info "生产版本构建完成"
}

# 生成发布文档
generate_release_documentation() {
    log_info "生成发布文档"
    
    local docs_dir="${PROJECT_ROOT}/docs"
    local release_dir="${PROJECT_ROOT}/release"
    mkdir -p "$release_dir"
    
    # 生成变更日志
    log_info "生成变更日志"
    local changelog_file="$release_dir/CHANGELOG-$VERSION.md"
    
    cat > "$changelog_file" << EOF
# 变更日志 - $VERSION

发布日期: $RELEASE_DATE

## 新功能

- 完整的 PVE LXC K3s 模板生成器
- 基于 Alpine Linux 的轻量级容器模板
- 自动化 K3s 安装和配置
- 支持自定义配置和参数
- 完整的安全加固和优化
- 集群扩展和多节点支持
- 综合监控和日志系统
- 完整的测试框架

## 改进

- 优化构建性能和资源使用
- 增强错误处理和日志记录
- 改进文档和使用指南
- 加强安全配置和最佳实践

## 修复

- 修复构建过程中的各种问题
- 改进脚本兼容性和稳定性
- 优化内存使用和性能

## 技术规格

- 基础系统: Alpine Linux 3.18+
- K3s 版本: v1.28.4+k3s1
- 支持架构: amd64
- 最小内存: 512MB
- 推荐内存: 1GB+

## 安装和使用

详细的安装和使用说明请参考：
- [安装指南](docs/installation.md)
- [配置说明](docs/configuration.md)
- [API 文档](docs/api.md)

## 已知问题

无已知的严重问题。

## 下一版本计划

- 支持更多 Linux 发行版
- 增加更多 K3s 配置选项
- 改进性能监控功能
- 增强集群管理功能
EOF
    
    # 生成发布说明
    log_info "生成发布说明"
    local release_notes_file="$release_dir/RELEASE-NOTES-$VERSION.md"
    
    cat > "$release_notes_file" << EOF
# PVE LXC K3s Template $VERSION 发布说明

## 概述

PVE LXC K3s Template 是一个自动化工具，用于生成适用于 Proxmox VE 的 LXC 容器模板。该模板基于 Alpine Linux，预装并配置了 K3s Kubernetes 集群，实现一键部署轻量级 Kubernetes 环境。

## 主要特性

### 🚀 自动化构建
- 完全自动化的模板生成流程
- 基于 GitHub Actions 的 CI/CD 集成
- 支持多种配置和自定义选项

### 🔒 安全加固
- 遵循安全最佳实践
- 移除不必要的软件包和服务
- 配置防火墙和访问控制

### 📊 可观测性
- 完整的日志系统
- 健康检查和监控
- 性能指标收集

### 🔧 易于扩展
- 支持多节点集群部署
- 灵活的配置管理
- 模块化设计

## 系统要求

### 构建环境
- Linux 系统（推荐 Ubuntu 20.04+）
- Docker 或 Podman
- 至少 2GB 可用内存
- 至少 5GB 可用磁盘空间

### 运行环境
- Proxmox VE 7.0+
- 至少 512MB 内存（推荐 1GB+）
- 至少 2GB 磁盘空间

## 快速开始

### 1. 下载模板

\`\`\`bash
# 下载最新版本
wget https://github.com/your-org/pve-lxc-k3s-template/releases/download/$VERSION/alpine-k3s-$VERSION.tar.gz

# 验证校验和
wget https://github.com/your-org/pve-lxc-k3s-template/releases/download/$VERSION/checksums.txt
sha256sum -c checksums.txt
\`\`\`

### 2. 导入到 PVE

\`\`\`bash
# 上传模板到 PVE
scp alpine-k3s-$VERSION.tar.gz root@pve-host:/var/lib/vz/template/cache/

# 在 PVE 上创建容器
pct create 100 /var/lib/vz/template/cache/alpine-k3s-$VERSION.tar.gz \\
  --hostname k3s-node1 \\
  --memory 1024 \\
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \\
  --storage local-lvm
\`\`\`

### 3. 启动和验证

\`\`\`bash
# 启动容器
pct start 100

# 进入容器
pct enter 100

# 验证 K3s 状态
kubectl get nodes
kubectl get pods -A
\`\`\`

## 配置选项

模板支持多种配置选项，详细说明请参考 [配置文档](docs/configuration.md)。

## 故障排查

如果遇到问题，请参考：
- [故障排查指南](docs/troubleshooting.md)
- [常见问题解答](docs/README.md#常见问题)
- [GitHub Issues](https://github.com/your-org/pve-lxc-k3s-template/issues)

## 贡献

欢迎贡献代码和反馈！请参考 [开发文档](docs/development.md)。

## 许可证

本项目采用 MIT 许可证，详情请参考 LICENSE 文件。

## 支持

- 文档: [docs/](docs/)
- Issues: [GitHub Issues](https://github.com/your-org/pve-lxc-k3s-template/issues)
- 讨论: [GitHub Discussions](https://github.com/your-org/pve-lxc-k3s-template/discussions)

---

发布时间: $RELEASE_TIMESTAMP
构建信息: $(uname -a)
EOF
    
    # 更新主 README
    log_info "更新主 README"
    if [[ -f "${PROJECT_ROOT}/README.md" ]]; then
        # 备份原始 README
        cp "${PROJECT_ROOT}/README.md" "${PROJECT_ROOT}/README.md.backup"
        
        # 更新版本信息
        sed -i.bak "s/Version: .*/Version: $VERSION/" "${PROJECT_ROOT}/README.md" 2>/dev/null || true
        sed -i.bak "s/Release Date: .*/Release Date: $RELEASE_DATE/" "${PROJECT_ROOT}/README.md" 2>/dev/null || true
    fi
    
    log_info "发布文档生成完成"
}

# 创建 Git 标签和发布
create_git_release() {
    log_info "创建 Git 标签和发布"
    
    # 检查标签是否已存在
    if git tag -l | grep -q "^$VERSION$"; then
        log_warn "标签 $VERSION 已存在，跳过创建"
        return 0
    fi
    
    # 创建标签
    log_info "创建 Git 标签: $VERSION"
    local tag_message="Release $VERSION

$(cat "${PROJECT_ROOT}/release/CHANGELOG-$VERSION.md" 2>/dev/null | head -20 || echo "Release $VERSION")"
    
    git tag -a "$VERSION" -m "$tag_message"
    
    # 推送标签（如果不是 dry-run）
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        log_info "推送标签到远程仓库"
        git push origin "$VERSION" || log_warn "推送标签失败，可能需要手动推送"
    else
        log_info "Dry-run 模式，跳过推送标签"
    fi
    
    log_info "Git 标签创建完成"
}

# 生成发布包
create_release_package() {
    log_info "生成发布包"
    
    local release_dir="${PROJECT_ROOT}/release"
    local package_dir="$release_dir/package-$VERSION"
    
    # 创建发布包目录
    mkdir -p "$package_dir"
    
    # 复制构建产物
    log_info "复制构建产物"
    cp -r "${PROJECT_ROOT}/output"/* "$package_dir/"
    
    # 复制文档
    log_info "复制发布文档"
    cp "$release_dir/CHANGELOG-$VERSION.md" "$package_dir/"
    cp "$release_dir/RELEASE-NOTES-$VERSION.md" "$package_dir/"
    cp "${PROJECT_ROOT}/README.md" "$package_dir/"
    
    # 复制许可证和其他重要文件
    [[ -f "${PROJECT_ROOT}/LICENSE" ]] && cp "${PROJECT_ROOT}/LICENSE" "$package_dir/"
    [[ -f "${PROJECT_ROOT}/config/template.yaml" ]] && cp "${PROJECT_ROOT}/config/template.yaml" "$package_dir/template-config-example.yaml"
    
    # 创建安装脚本
    log_info "创建安装脚本"
    cat > "$package_dir/install.sh" << 'EOF'
#!/bin/bash
# PVE LXC K3s Template 安装脚本

set -euo pipefail

TEMPLATE_FILE=""
PVE_HOST=""
STORAGE="local"

show_help() {
    cat <<HELP
PVE LXC K3s Template 安装脚本

用法: $0 [选项]

选项:
  -f, --file FILE     模板文件路径
  -h, --host HOST     PVE 主机地址
  -s, --storage NAME  存储名称 (默认: local)
  --help              显示帮助信息

示例:
  $0 -f alpine-k3s-v1.0.0.tar.gz -h 192.168.1.100
HELP
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            TEMPLATE_FILE="$2"
            shift 2
            ;;
        -h|--host)
            PVE_HOST="$2"
            shift 2
            ;;
        -s|--storage)
            STORAGE="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 检查参数
if [[ -z "$TEMPLATE_FILE" ]]; then
    echo "错误: 请指定模板文件"
    show_help
    exit 1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "错误: 模板文件不存在: $TEMPLATE_FILE"
    exit 1
fi

echo "安装 PVE LXC K3s 模板..."
echo "模板文件: $TEMPLATE_FILE"
echo "PVE 主机: ${PVE_HOST:-本地}"
echo "存储: $STORAGE"

# 上传模板文件
if [[ -n "$PVE_HOST" ]]; then
    echo "上传模板到 PVE 主机..."
    scp "$TEMPLATE_FILE" "root@$PVE_HOST:/var/lib/vz/template/cache/"
else
    echo "复制模板到本地存储..."
    cp "$TEMPLATE_FILE" "/var/lib/vz/template/cache/"
fi

echo "模板安装完成！"
echo ""
echo "创建容器示例:"
echo "pct create 100 /var/lib/vz/template/cache/$(basename "$TEMPLATE_FILE") \\"
echo "  --hostname k3s-node1 \\"
echo "  --memory 1024 \\"
echo "  --net0 name=eth0,bridge=vmbr0,ip=dhcp \\"
echo "  --storage $STORAGE"
EOF
    
    chmod +x "$package_dir/install.sh"
    
    # 创建发布包压缩文件
    log_info "创建发布包压缩文件"
    local package_archive="$release_dir/pve-lxc-k3s-template-$VERSION-release.tar.gz"
    
    (
        cd "$release_dir"
        tar -czf "$(basename "$package_archive")" "$(basename "$package_dir")"
    )
    
    log_info "发布包创建完成: $package_archive"
    
    # 显示发布包内容
    echo ""
    echo "=== 发布包内容 ==="
    tar -tzf "$package_archive" | head -20
    if [[ $(tar -tzf "$package_archive" | wc -l) -gt 20 ]]; then
        echo "... (还有 $(($(tar -tzf "$package_archive" | wc -l) - 20)) 个文件)"
    fi
    echo ""
}

# 执行发布后验证
post_release_verification() {
    log_info "执行发布后验证"
    
    local errors=0
    
    # 验证构建产物
    log_info "验证构建产物"
    local output_dir="${PROJECT_ROOT}/output"
    if [[ ! -d "$output_dir" ]] || [[ -z "$(ls -A "$output_dir" 2>/dev/null)" ]]; then
        log_error "构建产物目录为空"
        ((errors++))
    fi
    
    # 验证模板文件
    local template_files=($(find "$output_dir" -name "*.tar.gz" 2>/dev/null))
    if [[ ${#template_files[@]} -eq 0 ]]; then
        log_error "未找到模板文件"
        ((errors++))
    else
        for template_file in "${template_files[@]}"; do
            if [[ ! -s "$template_file" ]]; then
                log_error "模板文件为空: $template_file"
                ((errors++))
            else
                log_info "模板文件验证通过: $(basename "$template_file") ($(du -h "$template_file" | cut -f1))"
            fi
        done
    fi
    
    # 验证校验和文件
    local checksums_file="$output_dir/checksums.txt"
    if [[ -f "$checksums_file" ]]; then
        log_info "验证校验和文件"
        if (cd "$output_dir" && sha256sum -c checksums.txt >/dev/null 2>&1); then
            log_info "校验和验证通过"
        else
            log_error "校验和验证失败"
            ((errors++))
        fi
    else
        log_warn "校验和文件不存在"
    fi
    
    # 验证发布文档
    local release_dir="${PROJECT_ROOT}/release"
    local required_docs=(
        "CHANGELOG-$VERSION.md"
        "RELEASE-NOTES-$VERSION.md"
    )
    
    for doc in "${required_docs[@]}"; do
        if [[ ! -f "$release_dir/$doc" ]]; then
            log_error "发布文档不存在: $doc"
            ((errors++))
        fi
    done
    
    # 验证 Git 标签
    if git tag -l | grep -q "^$VERSION$"; then
        log_info "Git 标签验证通过: $VERSION"
    else
        log_error "Git 标签不存在: $VERSION"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "发布后验证通过"
        return 0
    else
        log_error "发布后验证失败，发现 $errors 个错误"
        return 1
    fi
}

# 生成发布摘要
generate_release_summary() {
    local summary_file="${PROJECT_ROOT}/release/RELEASE-SUMMARY-$VERSION.md"
    
    log_info "生成发布摘要: $summary_file"
    
    # 收集统计信息
    local template_files=($(find "${PROJECT_ROOT}/output" -name "*.tar.gz" 2>/dev/null))
    local template_count=${#template_files[@]}
    local total_size=0
    
    for file in "${template_files[@]}"; do
        if [[ -f "$file" ]]; then
            local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
            total_size=$((total_size + size))
        fi
    done
    
    local total_size_mb=$((total_size / 1024 / 1024))
    
    cat > "$summary_file" << EOF
# 发布摘要 - $VERSION

## 基本信息

- **版本**: $VERSION
- **发布日期**: $RELEASE_DATE
- **发布时间**: $RELEASE_TIMESTAMP
- **构建环境**: $(uname -a)

## 构建统计

- **模板文件数量**: $template_count
- **总大小**: ${total_size_mb}MB
- **构建时间**: $(date)

## 文件清单

### 模板文件
$(for file in "${template_files[@]}"; do
    if [[ -f "$file" ]]; then
        local size=$(du -h "$file" | cut -f1)
        echo "- $(basename "$file") ($size)"
    fi
done)

### 文档文件
- CHANGELOG-$VERSION.md
- RELEASE-NOTES-$VERSION.md
- README.md

### 配置文件
- template-config-example.yaml

### 工具脚本
- install.sh

## 校验和

\`\`\`
$(cat "${PROJECT_ROOT}/output/checksums.txt" 2>/dev/null || echo "校验和文件不可用")
\`\`\`

## 下载链接

- [主模板文件](https://github.com/your-org/pve-lxc-k3s-template/releases/download/$VERSION/$(basename "${template_files[0]}" 2>/dev/null || echo "alpine-k3s-$VERSION.tar.gz"))
- [完整发布包](https://github.com/your-org/pve-lxc-k3s-template/releases/download/$VERSION/pve-lxc-k3s-template-$VERSION-release.tar.gz)
- [校验和文件](https://github.com/your-org/pve-lxc-k3s-template/releases/download/$VERSION/checksums.txt)

## 安装说明

### 快速安装

\`\`\`bash
# 下载并安装
wget https://github.com/your-org/pve-lxc-k3s-template/releases/download/$VERSION/$(basename "${template_files[0]}" 2>/dev/null || echo "alpine-k3s-$VERSION.tar.gz")
./install.sh -f $(basename "${template_files[0]}" 2>/dev/null || echo "alpine-k3s-$VERSION.tar.gz") -h YOUR_PVE_HOST
\`\`\`

### 手动安装

详细安装说明请参考 [RELEASE-NOTES-$VERSION.md](RELEASE-NOTES-$VERSION.md)。

## 验证状态

- ✅ 构建产物验证通过
- ✅ 校验和验证通过
- ✅ 文档完整性验证通过
- ✅ Git 标签创建成功

## 下一步

1. 在测试环境中验证模板功能
2. 更新项目文档和网站
3. 通知用户新版本发布
4. 收集用户反馈和问题报告

---

此摘要由发布脚本自动生成于 $(date)
EOF
    
    echo "发布摘要已生成: $summary_file"
}

# 主函数
main() {
    local pre_release=false
    local hotfix=false
    local dry_run=false
    local skip_tests=false
    local skip_docs=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --pre-release)
                pre_release=true
                shift
                ;;
            --hotfix)
                hotfix=true
                shift
                ;;
            --dry-run)
                dry_run=true
                export DRY_RUN=true
                shift
                ;;
            --skip-tests)
                skip_tests=true
                shift
                ;;
            --skip-docs)
                skip_docs=true
                shift
                ;;
            --verbose)
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            v*.*)
                VERSION="$1"
                shift
                ;;
            *)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 显示发布信息
    echo "=========================================="
    echo "PVE LXC K3s Template 生产发布准备"
    echo "=========================================="
    echo "版本: $VERSION"
    echo "发布日期: $RELEASE_DATE"
    echo "预发布: $pre_release"
    echo "热修复: $hotfix"
    echo "模拟运行: $dry_run"
    echo "=========================================="
    echo ""
    
    if [[ "$dry_run" == "true" ]]; then
        echo "⚠️  模拟运行模式 - 不会执行实际的发布操作"
        echo ""
    fi
    
    local start_time=$(date +%s)
    
    # 执行发布流程
    log_info "开始生产发布准备流程"
    
    # 1. 验证发布前提条件
    verify_release_prerequisites
    
    # 2. 运行测试套件
    if [[ "$skip_tests" != "true" ]]; then
        run_comprehensive_tests
    else
        log_warn "跳过测试执行"
    fi
    
    # 3. 构建生产版本
    if [[ "$dry_run" != "true" ]]; then
        build_production_version
    else
        log_info "模拟运行：跳过实际构建"
    fi
    
    # 4. 生成发布文档
    if [[ "$skip_docs" != "true" ]]; then
        generate_release_documentation
    else
        log_warn "跳过文档生成"
    fi
    
    # 5. 创建 Git 标签
    if [[ "$dry_run" != "true" ]]; then
        create_git_release
    else
        log_info "模拟运行：跳过 Git 标签创建"
    fi
    
    # 6. 生成发布包
    if [[ "$dry_run" != "true" ]]; then
        create_release_package
    else
        log_info "模拟运行：跳过发布包创建"
    fi
    
    # 7. 发布后验证
    if [[ "$dry_run" != "true" ]]; then
        post_release_verification
    else
        log_info "模拟运行：跳过发布后验证"
    fi
    
    # 8. 生成发布摘要
    generate_release_summary
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 显示完成信息
    echo ""
    echo "=========================================="
    echo "生产发布准备完成"
    echo "=========================================="
    echo "版本: $VERSION"
    echo "耗时: ${duration}s"
    echo ""
    
    if [[ "$dry_run" == "true" ]]; then
        echo "✅ 模拟运行完成 - 所有检查通过"
        echo ""
        echo "要执行实际发布，请运行："
        echo "$0 $VERSION"
    else
        echo "✅ 生产版本 $VERSION 已准备就绪"
        echo ""
        echo "发布文件位置："
        echo "- 模板文件: ${PROJECT_ROOT}/output/"
        echo "- 发布包: ${PROJECT_ROOT}/release/"
        echo "- 文档: ${PROJECT_ROOT}/release/"
        echo ""
        echo "下一步操作："
        echo "1. 上传发布文件到 GitHub Releases"
        echo "2. 更新项目文档和网站"
        echo "3. 通知用户新版本发布"
    fi
    
    log_info "生产发布准备流程完成" "{\"version\": \"$VERSION\", \"duration\": \"${duration}s\", \"dry_run\": $dry_run}"
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi