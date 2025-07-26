# Release Example

## 发布示例

本文档展示如何使用项目的发布工具创建和发布 PVE LXC K3s 模板。

## 场景 1: 自动发布（推荐）

### 创建标签触发自动发布

```bash
# 1. 确保代码已提交并推送到主分支
git add .
git commit -m "feat: prepare for v1.0.0 release"
git push origin main

# 2. 创建版本标签
git tag -a v1.0.0 -m "Release v1.0.0 - Initial stable release"

# 3. 推送标签触发 GitHub Actions
git push origin v1.0.0

# 4. 监控构建进度
# 访问 GitHub Actions 页面查看构建状态
# 或使用 GitHub CLI
gh run list --workflow="build-template.yml"
```

### 使用发布触发脚本

```bash
# 1. 使用脚本创建标签和触发发布
scripts/trigger-release.sh create-tag v1.0.0

# 2. 创建预发布版本
scripts/trigger-release.sh create-tag v1.0.0-beta --prerelease

# 3. 查看发布状态
scripts/trigger-release.sh status

# 4. 列出所有发布
scripts/trigger-release.sh list-releases
```

## 场景 2: 手动发布

### 使用 Make 目标

```bash
# 1. 构建发布制品
make release-build

# 2. 打包发布文件
make release-package

# 3. 创建完整发布（交互式）
make release-create
# 系统会提示输入版本标签，例如：v1.0.0

# 4. 上传到 GitHub Releases（交互式）
make release-upload
# 系统会提示输入版本标签、仓库和 Token
```

### 使用发布脚本

```bash
# 1. 构建制品
scripts/create-release.sh build

# 2. 打包指定版本
scripts/create-release.sh package v1.0.0

# 3. 创建完整发布
scripts/create-release.sh create v1.0.0

# 4. 上传到 GitHub（需要配置仓库和 Token）
scripts/create-release.sh upload v1.0.0 \
  --github-repo your-username/pve-lxc-k3s-template \
  --github-token ghp_your_token_here

# 5. 创建预发布版本
scripts/create-release.sh create v1.0.0-beta --prerelease

# 6. 创建草稿发布
scripts/create-release.sh create v1.0.0 --draft
```

## 场景 3: 开发和测试发布

### 本地测试构建

```bash
# 1. 测试构建过程
make build
make test

# 2. 验证模板
make validate

# 3. 构建发布制品（不上传）
scripts/create-release.sh build

# 4. 检查输出文件
ls -la output/
```

### 创建测试发布

```bash
# 1. 创建开发版本标签
git tag -a v1.0.0-dev -m "Development build for testing"
git push origin v1.0.0-dev

# 2. 或使用脚本创建
scripts/trigger-release.sh create-tag v1.0.0-dev --prerelease

# 3. 创建本地发布包
scripts/create-release.sh package v1.0.0-dev
```

## 场景 4: 紧急修复发布

### 快速补丁发布

```bash
# 1. 创建修复分支
git checkout -b hotfix/v1.0.1

# 2. 进行必要的修复
# ... 修复代码 ...

# 3. 提交修复
git add .
git commit -m "fix: critical security vulnerability"

# 4. 合并到主分支
git checkout main
git merge hotfix/v1.0.1

# 5. 创建补丁版本标签
git tag -a v1.0.1 -m "Hotfix v1.0.1 - Security fix"
git push origin main
git push origin v1.0.1

# 6. 清理分支
git branch -d hotfix/v1.0.1
```

## 场景 5: 预发布和测试

### 创建 Beta 版本

```bash
# 1. 创建 beta 版本
scripts/trigger-release.sh create-tag v1.1.0-beta --prerelease

# 2. 或手动创建
git tag -a v1.1.0-beta -m "Beta release for v1.1.0"
git push origin v1.1.0-beta
```

### 创建 Release Candidate

```bash
# 1. 创建 RC 版本
scripts/trigger-release.sh create-tag v1.1.0-rc1 --prerelease

# 2. 测试 RC 版本
# ... 进行测试 ...

# 3. 如果测试通过，创建正式版本
scripts/trigger-release.sh create-tag v1.1.0
```

## 场景 6: 批量发布管理

### 查看和管理发布

```bash
# 1. 列出所有发布
gh release list

# 2. 查看特定发布详情
gh release view v1.0.0

# 3. 下载发布资产
gh release download v1.0.0

# 4. 删除发布（谨慎操作）
gh release delete v1.0.0-beta

# 5. 编辑发布信息
gh release edit v1.0.0 --notes "Updated release notes"
```

### 发布状态监控

```bash
# 1. 监控工作流运行
gh run list --workflow="publish-artifacts.yml"

# 2. 查看特定运行详情
gh run view 1234567890

# 3. 实时监控运行
gh run watch 1234567890

# 4. 下载运行日志
gh run download 1234567890
```

## 环境变量配置

### GitHub Actions 环境

```bash
# 在 GitHub 仓库设置中配置以下 Secrets:
# GITHUB_TOKEN - 自动提供，用于发布
# 其他可选的 secrets...
```

### 本地开发环境

```bash
# 设置环境变量
export GITHUB_REPOSITORY="your-username/pve-lxc-k3s-template"
export GITHUB_TOKEN="ghp_your_token_here"
export OUTPUT_DIR="./output"
export RELEASE_DIR="./release"

# 或创建 .env 文件
cat > .env << EOF
GITHUB_REPOSITORY=your-username/pve-lxc-k3s-template
GITHUB_TOKEN=ghp_your_token_here
OUTPUT_DIR=./output
RELEASE_DIR=./release
EOF

# 加载环境变量
source .env
```

## 故障排除示例

### 构建失败

```bash
# 1. 检查构建日志
make build 2>&1 | tee build.log

# 2. 检查依赖
scripts/build-template.sh --help

# 3. 清理并重试
make clean
make build
```

### 发布上传失败

```bash
# 1. 检查 GitHub CLI 认证
gh auth status

# 2. 重新认证
gh auth login

# 3. 检查仓库权限
gh repo view

# 4. 手动上传文件
gh release upload v1.0.0 output/*.tar.gz
```

### 标签冲突

```bash
# 1. 删除本地标签
git tag -d v1.0.0

# 2. 删除远程标签
git push origin :refs/tags/v1.0.0

# 3. 重新创建标签
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

## 最佳实践示例

### 发布前检查清单

```bash
#!/bin/bash
# pre-release-check.sh

echo "🔍 Pre-release checklist"

# 1. 检查代码质量
echo "1. Running code quality checks..."
make lint

# 2. 运行测试
echo "2. Running tests..."
make test

# 3. 检查构建
echo "3. Testing build..."
make build

# 4. 验证模板
echo "4. Validating template..."
make validate

# 5. 检查文档
echo "5. Checking documentation..."
if [[ -f README.md && -f CHANGELOG.md ]]; then
    echo "✅ Documentation files present"
else
    echo "❌ Missing documentation files"
    exit 1
fi

echo "✅ Pre-release checks completed successfully"
```

### 发布后验证

```bash
#!/bin/bash
# post-release-verify.sh

VERSION="$1"
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>"
    exit 1
fi

echo "🔍 Post-release verification for $VERSION"

# 1. 检查发布是否存在
echo "1. Checking release exists..."
if gh release view "$VERSION" >/dev/null 2>&1; then
    echo "✅ Release $VERSION exists"
else
    echo "❌ Release $VERSION not found"
    exit 1
fi

# 2. 下载并验证文件
echo "2. Downloading and verifying files..."
mkdir -p verify-$VERSION
cd verify-$VERSION

gh release download "$VERSION"

# 验证校验和
for file in *.tar.gz; do
    if [[ -f "${file}.sha256" ]]; then
        if sha256sum -c "${file}.sha256"; then
            echo "✅ $file checksum verified"
        else
            echo "❌ $file checksum failed"
            exit 1
        fi
    fi
done

echo "✅ Post-release verification completed successfully"
```

## 总结

这些示例展示了如何在不同场景下使用项目的发布工具。选择最适合你需求的方法：

- **自动发布**: 适合大多数情况，推荐使用
- **手动发布**: 适合测试或特殊需求
- **脚本工具**: 提供更多控制和自动化选项

记住始终在发布前进行充分测试，并在发布后验证结果。