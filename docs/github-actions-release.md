# GitHub Actions 自动发布指南

## 概述

本项目已配置完整的 GitHub Actions 自动化发布流程，可以自动构建、测试、打包和发布 PVE LXC K3s 模板到 GitHub Releases。

## 🚀 快速开始

### 方法 1: 标签触发（推荐）

最简单的发布方式是创建版本标签：

```bash
# 创建版本标签
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

GitHub Actions 将自动：
- ✅ 构建模板
- ✅ 运行测试
- ✅ 生成校验和
- ✅ 创建 GitHub Release
- ✅ 上传制品文件
- ✅ 发布到容器注册表

### 方法 2: 手动触发

通过 GitHub 网页界面手动触发：

1. 访问仓库的 **Actions** 标签页
2. 选择 **Publish Artifacts to Release** 工作流
3. 点击 **Run workflow**
4. 输入版本标签（如 `v1.0.0`）
5. 选择是否为预发布版本
6. 点击 **Run workflow**

### 方法 3: 使用脚本工具

项目提供了便捷的脚本工具：

```bash
# 创建标签并触发发布
scripts/trigger-release.sh create-tag v1.0.0

# 创建预发布版本
scripts/trigger-release.sh create-tag v1.0.0-beta --prerelease

# 查看发布状态
scripts/trigger-release.sh status
```

## 📋 GitHub Actions 工作流

### 1. 构建模板工作流 (build-template.yml)

**触发条件**:
- 推送到 `main` 或 `develop` 分支
- 创建 Pull Request 到 `main`
- 推送版本标签 (`v*`)
- 手动触发

**主要功能**:
- 配置验证
- 代码质量检查
- 单元测试
- 模板构建
- 集成测试
- 安全扫描
- 自动发布（仅标签触发）

### 2. 发布制品工作流 (publish-artifacts.yml)

**触发条件**:
- 推送版本标签 (`v*`)
- 手动触发

**主要功能**:
- 构建发布制品
- 创建 GitHub Release
- 发布到容器注册表
- 成功/失败通知

### 3. 发布管理工作流 (release.yml)

**触发条件**:
- 发布已发布事件
- 手动触发

**主要功能**:
- 发布信息验证
- 构建发布制品
- 更新发布资产
- 发布到容器注册表
- 更新文档
- 后续处理任务

### 4. 变更日志工作流 (changelog.yml)

**触发条件**:
- 推送到 `main` 分支
- 推送版本标签
- 手动触发

**主要功能**:
- 自动生成变更日志
- 创建发布草稿
- 更新文档

### 5. 依赖更新工作流 (update-dependencies.yml)

**触发条件**:
- 定时执行（每周日）
- 手动触发

**主要功能**:
- 检查 K3s 版本更新
- 检查 Alpine 版本更新
- 自动创建更新 PR
- 安全更新通知

## 🔧 配置说明

### 必需的仓库设置

1. **Actions 权限**:
   - 启用 GitHub Actions
   - 允许 Actions 创建和批准 Pull Requests
   - 允许 Actions 写入仓库内容

2. **Secrets 配置**:
   - `GITHUB_TOKEN` - 自动提供，用于发布操作

3. **分支保护**（可选但推荐）:
   - 保护 `main` 分支
   - 要求 PR 审查
   - 要求状态检查通过

### 工作流权限

工作流使用以下权限：

```yaml
permissions:
  contents: write      # 创建发布和标签
  packages: write      # 发布到容器注册表
  pull-requests: write # 创建和更新 PR
  issues: write        # 创建问题和通知
```

## 📦 发布制品

每个发布包含以下制品：

### 模板文件
- `alpine-k3s-{version}.tar.gz` - 主模板文件
- `alpine-k3s-{version}.tar.gz.sha256` - SHA256 校验和
- `alpine-k3s-{version}.tar.gz.sha512` - SHA512 校验和
- `alpine-k3s-{version}.tar.gz.md5` - MD5 校验和

### 容器镜像
- `ghcr.io/{owner}/{repo}:{version}` - 版本化镜像
- `ghcr.io/{owner}/{repo}:latest` - 最新稳定版本

### 发布信息
- 详细的发布说明
- 安装指南
- 变更日志
- 技术规格

## 🏷️ 版本标签规范

### 标签格式

- **稳定版本**: `v1.0.0`, `v1.2.3`
- **预发布版本**: `v1.0.0-alpha`, `v1.0.0-beta`, `v1.0.0-rc1`
- **开发版本**: `v1.0.0-dev`

### 版本号规则

遵循 [语义化版本](https://semver.org/) 规范：

- **主版本号** (Major): 不兼容的 API 修改
- **次版本号** (Minor): 向下兼容的功能性新增
- **修订号** (Patch): 向下兼容的问题修正

### 标签创建示例

```bash
# 主版本发布
git tag -a v2.0.0 -m "Major release v2.0.0 - Breaking changes"

# 次版本发布
git tag -a v1.1.0 -m "Minor release v1.1.0 - New features"

# 修订版发布
git tag -a v1.0.1 -m "Patch release v1.0.1 - Bug fixes"

# 预发布版本
git tag -a v1.1.0-beta -m "Beta release v1.1.0-beta"

# 推送标签
git push origin v1.0.0
```

## 🔍 监控和调试

### 查看工作流状态

```bash
# 使用 GitHub CLI
gh run list --workflow="build-template.yml"
gh run view <run-id>
gh run watch <run-id>

# 或访问 GitHub 网页界面
# https://github.com/{owner}/{repo}/actions
```

### 常见问题排查

#### 1. 构建失败

```bash
# 检查构建日志
gh run view <run-id> --log

# 本地测试构建
make build
make test
```

#### 2. 发布创建失败

- 检查标签格式是否正确
- 验证仓库权限设置
- 确认 Actions 权限配置

#### 3. 制品上传失败

- 检查网络连接
- 验证 GitHub Token 权限
- 确认存储空间充足

### 调试模式

启用调试模式获取详细日志：

1. 在工作流输入中设置 `debug_enabled: true`
2. 或在仓库设置中添加 Secret: `ACTIONS_STEP_DEBUG=true`

## 🛠️ 本地开发工具

### Make 目标

```bash
# 构建发布制品
make release-build

# 打包发布文件
make release-package

# 创建完整发布
make release-create

# 上传到 GitHub
make release-upload
```

### 脚本工具

```bash
# 发布管理脚本
scripts/create-release.sh build
scripts/create-release.sh create v1.0.0

# GitHub Actions 触发脚本
scripts/trigger-release.sh create-tag v1.0.0
scripts/trigger-release.sh status
```

## 🔒 安全考虑

### 发布安全

- 所有发布都包含校验和验证
- 容器镜像自动扫描漏洞
- 发布制品不可变更
- 使用最小权限原则

### 访问控制

- 只有维护者可以创建发布
- 工作流使用安全的 Secrets 管理
- 敏感操作需要手动批准

## 📈 最佳实践

### 发布前检查

- [ ] 运行完整测试套件
- [ ] 更新版本号和文档
- [ ] 检查变更日志
- [ ] 验证构建过程

### 发布后验证

- [ ] 验证制品可下载
- [ ] 测试模板部署
- [ ] 检查容器镜像
- [ ] 监控用户反馈

### 版本管理

- 使用语义化版本号
- 维护详细的变更日志
- 及时处理安全更新
- 定期清理旧版本

## 🤝 贡献指南

### 提交发布相关更改

1. 创建功能分支
2. 进行必要更改
3. 更新测试和文档
4. 创建 Pull Request
5. 等待审查和合并

### 改进发布流程

欢迎提交以下改进：

- 工作流优化
- 新的测试用例
- 文档改进
- 工具增强

## 📞 支持

如果遇到发布相关问题：

1. 查看本文档和 [发布流程指南](release-process.md)
2. 检查 GitHub Actions 日志
3. 搜索现有 Issues
4. 创建新的 Issue 描述问题

## 🎯 总结

GitHub Actions 自动发布系统提供了：

- **完全自动化** - 从标签到发布的全自动流程
- **质量保证** - 自动测试和验证
- **安全可靠** - 校验和验证和权限控制
- **易于使用** - 简单的标签触发机制
- **灵活配置** - 支持多种发布场景
- **监控调试** - 完整的日志和状态跟踪

通过这套系统，你可以轻松地创建高质量、一致的 PVE LXC K3s 模板发布。