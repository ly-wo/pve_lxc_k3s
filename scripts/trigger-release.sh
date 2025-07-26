#!/bin/bash
# Trigger GitHub Actions Release
# 触发 GitHub Actions 发布

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载依赖
source "${PROJECT_ROOT}/scripts/logging.sh"

# 组件名称
COMPONENT="trigger-release"

# 默认配置
GITHUB_REPO="${GITHUB_REPOSITORY:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# 显示帮助信息
show_help() {
    cat << EOF
GitHub Actions 发布触发器

用法: $0 <命令> [选项]

命令:
    create-tag <version>        创建标签并触发发布
    dispatch <version>          手动触发发布工作流
    status <run-id>             查看工作流状态
    list-releases               列出所有发布
    help                        显示此帮助信息

选项:
    --github-repo REPO          指定 GitHub 仓库 (格式: owner/repo)
    --github-token TOKEN        指定 GitHub Token
    --prerelease                标记为预发布版本
    --force                     强制创建标签（覆盖现有标签）
    --message MESSAGE           标签消息

环境变量:
    GITHUB_REPOSITORY           GitHub 仓库
    GITHUB_TOKEN                GitHub Token

示例:
    # 创建标签并触发发布
    $0 create-tag v1.0.0
    
    # 创建预发布版本
    $0 create-tag v1.0.0-beta --prerelease
    
    # 手动触发发布工作流
    $0 dispatch v1.0.0
    
    # 查看工作流状态
    $0 status 1234567890
    
    # 列出所有发布
    $0 list-releases

EOF
}

# 检查依赖
check_dependencies() {
    log_info "$COMPONENT" "检查依赖"
    
    # 检查 GitHub CLI
    if ! command -v gh >/dev/null 2>&1; then
        log_error "$COMPONENT" "GitHub CLI (gh) 未安装"
        log_info "$COMPONENT" "请访问 https://cli.github.com/ 安装 GitHub CLI"
        return 1
    fi
    
    # 检查 git
    if ! command -v git >/dev/null 2>&1; then
        log_error "$COMPONENT" "Git 未安装"
        return 1
    fi
    
    # 检查仓库配置
    if [[ -z "$GITHUB_REPO" ]]; then
        # 尝试从 git remote 获取
        if git remote get-url origin >/dev/null 2>&1; then
            local remote_url
            remote_url=$(git remote get-url origin)
            if [[ "$remote_url" =~ github\.com[:/]([^/]+/[^/]+) ]]; then
                GITHUB_REPO="${BASH_REMATCH[1]%.git}"
                log_info "$COMPONENT" "从 git remote 获取仓库: $GITHUB_REPO"
            fi
        fi
        
        if [[ -z "$GITHUB_REPO" ]]; then
            log_error "$COMPONENT" "GitHub 仓库未指定"
            return 1
        fi
    fi
    
    # 设置 GitHub CLI 环境
    export GH_REPO="$GITHUB_REPO"
    if [[ -n "$GITHUB_TOKEN" ]]; then
        export GH_TOKEN="$GITHUB_TOKEN"
    fi
    
    # 验证认证
    if ! gh auth status >/dev/null 2>&1; then
        log_error "$COMPONENT" "GitHub CLI 未认证"
        log_info "$COMPONENT" "请运行 'gh auth login' 进行认证"
        return 1
    fi
    
    log_info "$COMPONENT" "依赖检查通过"
    return 0
}

# 创建标签
create_tag() {
    local version="$1"
    local message="${2:-Release $version}"
    local force="${3:-false}"
    
    log_info "$COMPONENT" "创建标签: $version"
    
    # 检查标签是否已存在
    if git tag -l | grep -q "^${version}$"; then
        if [[ "$force" == "true" ]]; then
            log_warn "$COMPONENT" "标签已存在，强制覆盖: $version"
            git tag -d "$version" || true
            git push origin ":refs/tags/$version" || true
        else
            log_error "$COMPONENT" "标签已存在: $version"
            log_info "$COMPONENT" "使用 --force 选项强制覆盖"
            return 1
        fi
    fi
    
    # 创建标签
    if git tag -a "$version" -m "$message"; then
        log_info "$COMPONENT" "标签创建成功: $version"
    else
        log_error "$COMPONENT" "标签创建失败: $version"
        return 1
    fi
    
    # 推送标签
    if git push origin "$version"; then
        log_info "$COMPONENT" "标签推送成功: $version"
    else
        log_error "$COMPONENT" "标签推送失败: $version"
        return 1
    fi
    
    log_info "$COMPONENT" "标签创建完成，GitHub Actions 将自动触发构建"
    return 0
}

# 手动触发工作流
dispatch_workflow() {
    local version="$1"
    local prerelease="${2:-false}"
    
    log_info "$COMPONENT" "手动触发发布工作流: $version"
    
    # 构建工作流输入
    local inputs="{\"version\":\"$version\",\"prerelease\":$prerelease}"
    
    # 触发工作流
    if gh workflow run "publish-artifacts.yml" --json --field inputs="$inputs"; then
        log_info "$COMPONENT" "工作流触发成功"
        
        # 等待一下，然后显示运行状态
        sleep 5
        show_latest_workflow_run
    else
        log_error "$COMPONENT" "工作流触发失败"
        return 1
    fi
    
    return 0
}

# 显示最新工作流运行状态
show_latest_workflow_run() {
    log_info "$COMPONENT" "获取最新工作流运行状态"
    
    local run_info
    run_info=$(gh run list --workflow="publish-artifacts.yml" --limit=1 --json=databaseId,status,conclusion,url,createdAt)
    
    if [[ -n "$run_info" ]]; then
        local run_id
        run_id=$(echo "$run_info" | jq -r '.[0].databaseId')
        local status
        status=$(echo "$run_info" | jq -r '.[0].status')
        local conclusion
        conclusion=$(echo "$run_info" | jq -r '.[0].conclusion')
        local url
        url=$(echo "$run_info" | jq -r '.[0].url')
        local created_at
        created_at=$(echo "$run_info" | jq -r '.[0].createdAt')
        
        echo "最新工作流运行:"
        echo "  ID: $run_id"
        echo "  状态: $status"
        echo "  结果: $conclusion"
        echo "  创建时间: $created_at"
        echo "  URL: $url"
        
        # 如果工作流正在运行，提供监控命令
        if [[ "$status" == "in_progress" || "$status" == "queued" ]]; then
            echo ""
            echo "监控工作流进度:"
            echo "  $0 status $run_id"
            echo "  gh run watch $run_id"
        fi
    else
        log_warn "$COMPONENT" "未找到工作流运行记录"
    fi
}

# 查看工作流状态
show_workflow_status() {
    local run_id="$1"
    
    log_info "$COMPONENT" "查看工作流状态: $run_id"
    
    # 显示工作流详情
    gh run view "$run_id"
    
    # 显示日志（如果工作流已完成）
    local status
    status=$(gh run view "$run_id" --json=status -q '.status')
    
    if [[ "$status" == "completed" ]]; then
        echo ""
        echo "工作流日志:"
        gh run view "$run_id" --log
    fi
}

# 列出所有发布
list_releases() {
    log_info "$COMPONENT" "列出所有发布"
    
    # 显示发布列表
    gh release list --limit 20
    
    echo ""
    echo "查看特定发布详情:"
    echo "  gh release view <tag>"
    echo ""
    echo "下载发布资产:"
    echo "  gh release download <tag>"
}

# 验证版本格式
validate_version() {
    local version="$1"
    
    # 检查版本格式 (vX.Y.Z 或 vX.Y.Z-suffix)
    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
        log_error "$COMPONENT" "版本格式无效: $version"
        log_info "$COMPONENT" "正确格式: v1.0.0 或 v1.0.0-beta"
        return 1
    fi
    
    return 0
}

# 主函数
main() {
    local command="${1:-help}"
    shift || true
    
    # 解析选项
    local prerelease=false
    local force=false
    local message=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --github-repo)
                GITHUB_REPO="$2"
                shift 2
                ;;
            --github-token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            --prerelease)
                prerelease=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --message)
                message="$2"
                shift 2
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
    
    # 检查依赖
    if [[ "$command" != "help" ]]; then
        if ! check_dependencies; then
            exit 1
        fi
    fi
    
    # 执行命令
    case "$command" in
        "create-tag")
            local version="${1:-}"
            if [[ -z "$version" ]]; then
                log_error "$COMPONENT" "请指定版本"
                show_help
                exit 1
            fi
            
            if ! validate_version "$version"; then
                exit 1
            fi
            
            local tag_message="$message"
            if [[ -z "$tag_message" ]]; then
                if [[ "$prerelease" == "true" ]]; then
                    tag_message="Pre-release $version"
                else
                    tag_message="Release $version"
                fi
            fi
            
            create_tag "$version" "$tag_message" "$force"
            ;;
        "dispatch")
            local version="${1:-}"
            if [[ -z "$version" ]]; then
                log_error "$COMPONENT" "请指定版本"
                show_help
                exit 1
            fi
            
            if ! validate_version "$version"; then
                exit 1
            fi
            
            dispatch_workflow "$version" "$prerelease"
            ;;
        "status")
            local run_id="${1:-}"
            if [[ -z "$run_id" ]]; then
                show_latest_workflow_run
            else
                show_workflow_status "$run_id"
            fi
            ;;
        "list-releases")
            list_releases
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