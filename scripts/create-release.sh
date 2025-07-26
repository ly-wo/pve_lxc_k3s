#!/bin/bash
# Create Release Script
# 创建发布脚本

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载依赖
source "${PROJECT_ROOT}/scripts/logging.sh"
source "${PROJECT_ROOT}/scripts/config-loader.sh"

# 组件名称
COMPONENT="create-release"

# 默认配置
DEFAULT_OUTPUT_DIR="${PROJECT_ROOT}/output"
DEFAULT_RELEASE_DIR="${PROJECT_ROOT}/release"

# 发布配置
OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
RELEASE_DIR="${RELEASE_DIR:-$DEFAULT_RELEASE_DIR}"
GITHUB_REPO="${GITHUB_REPOSITORY:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# 显示帮助信息
show_help() {
    cat << EOF
创建发布脚本

用法: $0 <命令> [选项]

命令:
    build                       构建发布制品
    package                     打包发布文件
    upload <tag>                上传到 GitHub Releases
    create <tag>                创建完整发布
    help                        显示此帮助信息

选项:
    --output-dir DIR            指定输出目录 (默认: $DEFAULT_OUTPUT_DIR)
    --release-dir DIR           指定发布目录 (默认: $DEFAULT_RELEASE_DIR)
    --github-repo REPO          指定 GitHub 仓库 (格式: owner/repo)
    --github-token TOKEN        指定 GitHub Token
    --prerelease                标记为预发布版本
    --draft                     创建草稿发布
    --force                     强制覆盖现有文件

环境变量:
    OUTPUT_DIR                  输出目录
    RELEASE_DIR                 发布目录
    GITHUB_REPOSITORY           GitHub 仓库
    GITHUB_TOKEN                GitHub Token

示例:
    # 构建发布制品
    $0 build
    
    # 创建完整发布
    $0 create v1.0.0
    
    # 上传到 GitHub Releases
    $0 upload v1.0.0 --github-repo owner/repo --github-token ghp_xxx
    
    # 创建预发布版本
    $0 create v1.0.0-beta --prerelease

EOF
}

# 初始化发布环境
initialize_release() {
    log_info "$COMPONENT" "初始化发布环境"
    
    # 创建必要目录
    mkdir -p "$OUTPUT_DIR" "$RELEASE_DIR"
    
    # 加载配置
    if [[ -f "${PROJECT_ROOT}/config/template.yaml" ]]; then
        load_config "${PROJECT_ROOT}/config/template.yaml"
    else
        log_error "$COMPONENT" "配置文件不存在: ${PROJECT_ROOT}/config/template.yaml"
        exit 1
    fi
    
    log_info "$COMPONENT" "发布环境初始化完成"
}

# 构建发布制品
build_release_artifacts() {
    log_info "$COMPONENT" "构建发布制品"
    
    # 清理输出目录
    rm -rf "$OUTPUT_DIR"/*
    
    # 执行构建
    log_info "$COMPONENT" "执行模板构建"
    if ! "${PROJECT_ROOT}/scripts/build-template.sh"; then
        log_error "$COMPONENT" "模板构建失败"
        return 1
    fi
    
    # 执行打包
    log_info "$COMPONENT" "执行模板打包"
    if ! "${PROJECT_ROOT}/scripts/packager.sh" package; then
        log_error "$COMPONENT" "模板打包失败"
        return 1
    fi
    
    # 验证输出文件
    local template_files
    template_files=$(find "$OUTPUT_DIR" -name "*.tar.gz" -type f)
    
    if [[ -z "$template_files" ]]; then
        log_error "$COMPONENT" "未找到模板文件"
        return 1
    fi
    
    log_info "$COMPONENT" "发布制品构建完成"
    return 0
}

# 生成校验和
generate_checksums() {
    log_info "$COMPONENT" "生成校验和文件"
    
    cd "$OUTPUT_DIR"
    
    for file in *.tar.gz; do
        if [[ -f "$file" ]]; then
            log_info "$COMPONENT" "生成 $file 的校验和"
            
            # 生成各种校验和
            sha256sum "$file" > "${file}.sha256"
            sha512sum "$file" > "${file}.sha512"
            md5sum "$file" > "${file}.md5"
            
            # 验证校验和
            if sha256sum -c "${file}.sha256" >/dev/null 2>&1; then
                log_info "$COMPONENT" "SHA256 校验和验证通过: $file"
            else
                log_error "$COMPONENT" "SHA256 校验和验证失败: $file"
                return 1
            fi
        fi
    done
    
    log_info "$COMPONENT" "校验和生成完成"
    return 0
}

# 打包发布文件
package_release() {
    local version="${1:-}"
    
    if [[ -z "$version" ]]; then
        version=$(get_config "template.version" "1.0.0")
    fi
    
    log_info "$COMPONENT" "打包发布文件: $version"
    
    # 创建发布目录
    local release_version_dir="${RELEASE_DIR}/${version}"
    mkdir -p "$release_version_dir"
    
    # 复制模板文件
    cp "$OUTPUT_DIR"/*.tar.gz "$release_version_dir/" 2>/dev/null || true
    cp "$OUTPUT_DIR"/*.sha256 "$release_version_dir/" 2>/dev/null || true
    cp "$OUTPUT_DIR"/*.sha512 "$release_version_dir/" 2>/dev/null || true
    cp "$OUTPUT_DIR"/*.md5 "$release_version_dir/" 2>/dev/null || true
    
    # 复制文档
    cp "${PROJECT_ROOT}/README.md" "$release_version_dir/" 2>/dev/null || true
    cp -r "${PROJECT_ROOT}/docs" "$release_version_dir/" 2>/dev/null || true
    cp -r "${PROJECT_ROOT}/config" "$release_version_dir/" 2>/dev/null || true
    
    # 生成发布信息文件
    generate_release_info "$version" "$release_version_dir"
    
    # 创建发布压缩包
    local release_archive="${RELEASE_DIR}/pve-lxc-k3s-template-${version}.tar.gz"
    tar -czf "$release_archive" -C "$RELEASE_DIR" "${version}"
    
    log_info "$COMPONENT" "发布文件打包完成: $release_archive"
    return 0
}

# 生成发布信息文件
generate_release_info() {
    local version="$1"
    local release_dir="$2"
    
    log_info "$COMPONENT" "生成发布信息文件"
    
    local template_name
    template_name=$(get_config "template.name" "alpine-k3s")
    local k3s_version
    k3s_version=$(get_config "k3s.version" "latest")
    local base_image
    base_image=$(get_config "template.base_image" "alpine:3.18")
    
    # 生成发布信息
    cat > "${release_dir}/RELEASE_INFO.md" << EOF
# PVE LXC K3s Template Release ${version}

## Release Information

- **Release Version**: ${version}
- **Template Name**: ${template_name}
- **K3s Version**: ${k3s_version}
- **Base Image**: ${base_image}
- **Architecture**: amd64
- **Release Date**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
- **Build Host**: $(hostname)
- **Build User**: $(whoami)

## Template Files

EOF
    
    # 添加文件列表
    for file in "${release_dir}"/*.tar.gz; do
        if [[ -f "$file" ]]; then
            local filename
            filename=$(basename "$file")
            local filesize
            filesize=$(du -h "$file" | cut -f1)
            echo "- **${filename}** (${filesize})" >> "${release_dir}/RELEASE_INFO.md"
        fi
    done
    
    # 添加校验和信息
    cat >> "${release_dir}/RELEASE_INFO.md" << EOF

## Checksums

### SHA256
\`\`\`
EOF
    
    for file in "${release_dir}"/*.sha256; do
        if [[ -f "$file" ]]; then
            cat "$file" >> "${release_dir}/RELEASE_INFO.md"
        fi
    done
    
    cat >> "${release_dir}/RELEASE_INFO.md" << EOF
\`\`\`

### SHA512
\`\`\`
EOF
    
    for file in "${release_dir}"/*.sha512; do
        if [[ -f "$file" ]]; then
            cat "$file" >> "${release_dir}/RELEASE_INFO.md"
        fi
    done
    
    cat >> "${release_dir}/RELEASE_INFO.md" << EOF
\`\`\`

## Installation Instructions

1. Download the template file
2. Upload to your Proxmox VE server:
   \`\`\`bash
   pveam upload local ${template_name}-${version}.tar.gz
   \`\`\`
3. Create LXC container:
   \`\`\`bash
   pct create 100 local:vztmpl/${template_name}-${version}.tar.gz \\
     --hostname k3s-node \\
     --memory 2048 \\
     --cores 2 \\
     --net0 name=eth0,bridge=vmbr0,ip=dhcp
   \`\`\`
4. Start the container:
   \`\`\`bash
   pct start 100
   \`\`\`

## Verification

Verify the K3s cluster is running:
\`\`\`bash
pct exec 100 -- k3s kubectl get nodes
\`\`\`

## Support

- Documentation: See README.md
- Issues: Report via GitHub Issues
- Discussions: Join GitHub Discussions

EOF
    
    log_info "$COMPONENT" "发布信息文件生成完成"
}

# 上传到 GitHub Releases
upload_to_github() {
    local tag="$1"
    local is_prerelease="${2:-false}"
    local is_draft="${3:-false}"
    
    log_info "$COMPONENT" "上传到 GitHub Releases: $tag"
    
    # 检查必要参数
    if [[ -z "$GITHUB_REPO" ]]; then
        log_error "$COMPONENT" "GitHub 仓库未指定"
        return 1
    fi
    
    if [[ -z "$GITHUB_TOKEN" ]]; then
        log_error "$COMPONENT" "GitHub Token 未指定"
        return 1
    fi
    
    # 检查 GitHub CLI
    if ! command -v gh >/dev/null 2>&1; then
        log_error "$COMPONENT" "GitHub CLI (gh) 未安装"
        return 1
    fi
    
    # 设置 GitHub CLI 认证
    export GH_TOKEN="$GITHUB_TOKEN"
    export GH_REPO="$GITHUB_REPO"
    
    # 生成发布说明
    local release_notes_file
    release_notes_file=$(mktemp)
    generate_github_release_notes "$tag" "$release_notes_file"
    
    # 构建发布命令
    local release_cmd=(
        gh release create "$tag"
        --title "PVE LXC K3s Template $tag"
        --notes-file "$release_notes_file"
    )
    
    if [[ "$is_prerelease" == "true" ]]; then
        release_cmd+=(--prerelease)
    fi
    
    if [[ "$is_draft" == "true" ]]; then
        release_cmd+=(--draft)
    fi
    
    # 添加文件
    for file in "$OUTPUT_DIR"/*.tar.gz "$OUTPUT_DIR"/*.sha256 "$OUTPUT_DIR"/*.sha512 "$OUTPUT_DIR"/*.md5; do
        if [[ -f "$file" ]]; then
            release_cmd+=("$file")
        fi
    done
    
    # 执行发布
    if "${release_cmd[@]}"; then
        log_info "$COMPONENT" "GitHub Release 创建成功: $tag"
    else
        log_error "$COMPONENT" "GitHub Release 创建失败"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$release_notes_file"
    
    return 0
}

# 生成 GitHub 发布说明
generate_github_release_notes() {
    local tag="$1"
    local output_file="$2"
    
    local template_name
    template_name=$(get_config "template.name" "alpine-k3s")
    local template_version
    template_version=$(get_config "template.version" "1.0.0")
    local k3s_version
    k3s_version=$(get_config "k3s.version" "latest")
    
    cat > "$output_file" << EOF
# PVE LXC K3s Template ${tag}

## 📦 Template Information

- **Template Version**: ${template_version}
- **K3s Version**: ${k3s_version}
- **Base Image**: Alpine Linux 3.18
- **Architecture**: amd64
- **Release Date**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

## 🚀 Features

- ✅ Pre-installed K3s Kubernetes cluster
- ✅ Optimized Alpine Linux base
- ✅ Security hardening applied
- ✅ Auto-start K3s service
- ✅ Multi-node cluster support
- ✅ Comprehensive logging

## 📋 Quick Installation

1. Download the template file
2. Upload to Proxmox VE: \`pveam upload local template.tar.gz\`
3. Create container: \`pct create 100 local:vztmpl/template.tar.gz --memory 2048 --cores 2\`
4. Start container: \`pct start 100\`
5. Verify: \`pct exec 100 -- k3s kubectl get nodes\`

## 📁 Release Assets

EOF
    
    # 添加文件列表
    for file in "$OUTPUT_DIR"/*.tar.gz; do
        if [[ -f "$file" ]]; then
            local filename
            filename=$(basename "$file")
            local filesize
            filesize=$(du -h "$file" | cut -f1)
            echo "- **${filename}** (${filesize}) - Main template file" >> "$output_file"
        fi
    done
    
    # 添加校验和
    echo "" >> "$output_file"
    echo "## 🔐 Checksums" >> "$output_file"
    echo "" >> "$output_file"
    echo "\`\`\`" >> "$output_file"
    
    for file in "$OUTPUT_DIR"/*.sha256; do
        if [[ -f "$file" ]]; then
            cat "$file" >> "$output_file"
        fi
    done
    
    echo "\`\`\`" >> "$output_file"
    
    # 添加支持信息
    cat >> "$output_file" << EOF

## 🆘 Support

- **Documentation**: Repository README
- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions

For detailed installation and configuration instructions, see the repository documentation.
EOF
}

# 创建完整发布
create_full_release() {
    local tag="$1"
    local is_prerelease="${2:-false}"
    local is_draft="${3:-false}"
    
    log_info "$COMPONENT" "创建完整发布: $tag"
    
    # 构建制品
    if ! build_release_artifacts; then
        log_error "$COMPONENT" "构建制品失败"
        return 1
    fi
    
    # 生成校验和
    if ! generate_checksums; then
        log_error "$COMPONENT" "生成校验和失败"
        return 1
    fi
    
    # 打包发布
    if ! package_release "$tag"; then
        log_error "$COMPONENT" "打包发布失败"
        return 1
    fi
    
    # 上传到 GitHub（如果配置了）
    if [[ -n "$GITHUB_REPO" && -n "$GITHUB_TOKEN" ]]; then
        if ! upload_to_github "$tag" "$is_prerelease" "$is_draft"; then
            log_error "$COMPONENT" "上传到 GitHub 失败"
            return 1
        fi
    else
        log_info "$COMPONENT" "跳过 GitHub 上传（未配置仓库或令牌）"
    fi
    
    log_info "$COMPONENT" "完整发布创建成功: $tag"
    return 0
}

# 主函数
main() {
    local command="${1:-help}"
    shift || true
    
    # 解析选项
    local is_prerelease=false
    local is_draft=false
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --release-dir)
                RELEASE_DIR="$2"
                shift 2
                ;;
            --github-repo)
                GITHUB_REPO="$2"
                shift 2
                ;;
            --github-token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            --prerelease)
                is_prerelease=true
                shift
                ;;
            --draft)
                is_draft=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            -*)
                log_error "$COMPONENT" "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                # 非选项参数，重新放回参数列表
                set -- "$1" "$@"
                break
                ;;
        esac
    done
    
    # 初始化环境
    if [[ "$command" != "help" ]]; then
        initialize_release
    fi
    
    # 执行命令
    case "$command" in
        "build")
            build_release_artifacts
            generate_checksums
            ;;
        "package")
            local version="${1:-}"
            package_release "$version"
            ;;
        "upload")
            local tag="${1:-}"
            if [[ -z "$tag" ]]; then
                log_error "$COMPONENT" "请指定标签"
                show_help
                exit 1
            fi
            upload_to_github "$tag" "$is_prerelease" "$is_draft"
            ;;
        "create")
            local tag="${1:-}"
            if [[ -z "$tag" ]]; then
                log_error "$COMPONENT" "请指定标签"
                show_help
                exit 1
            fi
            create_full_release "$tag" "$is_prerelease" "$is_draft"
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi