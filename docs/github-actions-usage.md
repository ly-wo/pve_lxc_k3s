# GitHub Actions 使用指南

## 概述

本项目提供了多个 GitHub Actions 工作流来自动化构建、测试和发布 PVE LXC K3s 模板。

## 🚀 可用的工作流

### 1. 主构建工作流 (build-template.yml)

**用途**: 主要的构建和测试工作流，支持自动发布

**触发方式**:
- 推送到 `main` 或 `develop` 分支
- 创建 Pull Request 到 `main`
- 推送版本标签 (`v*`)
- 手动触发

**功能**:
- ✅ 配置验证
- ✅ 代码质量检查
- ✅ 单元测试
- ✅ 模板构建
- ✅ 集成测试
- ✅ 安全扫描
- ✅ 自动发布（仅标签触发）

### 2. 发布制品工作流 (publish-artifacts.yml)

**用途**: 专门用于构建和发布制品到 GitHub Releases

**触发方式**:
- 推送版本标签 (`v*`)
- 手动触发

**功能**:
- ✅ 构建发布制品
- ✅ 生成校验和
- ✅ 创建 GitHub Release
- ✅ 发布到容器注册表

### 3. 手动发布工作流 (manual-release.yml)

**用途**: 提供完全可控的手动发布流程

**触发方式**:
- 仅手动触发

**功能**:
- ✅ 版本验证
- ✅ 自定义发布类型（正式版/预发布/草稿）
- ✅ 自定义发布说明
- ✅ 自动创建验证任务

### 4. 测试构建工作流 (test-build.yml)

**用途**: 快速测试构建系统是否正常工作

**触发方式**:
- 手动触发
- 推送到 `test-*` 分支

**功能**:
- ✅ 快速验证
- ✅ 构建测试
- ✅ 发布测试

## 📋 使用方法

### 方法 1: 标签自动发布（推荐）

这是最简单的发布方式：

```bash
# 1. 确保代码已提交到主分支
git checkout main
git pull origin main

# 2. 创建版本标签
git tag -a v1.0.0 -m "Release v1.0.0"

# 3. 推送标签触发自动发布
git push origin v1.0.0
```

**结果**: 
- 自动触发 `build-template.yml` 工作流
- 自动构建、测试、打包
- 自动创建 GitHub Release
- 自动上传制品文件

### 方法 2: 手动工作流触发

通过 GitHub 网页界面手动触发：

#### 2.1 使用主构建工作流

1. 访问仓库的 **Actions** 标签页
2. 选择 **Build PVE LXC K3s Template** 工作流
3. 点击 **Run workflow**
4. 选择分支和选项：
   - `debug_enabled`: 启用调试模式
   - `skip_tests`: 跳过测试
5. 点击 **Run workflow**

#### 2.2 使用发布制品工作流

1. 访问仓库的 **Actions** 标签页
2. 选择 **Publish Artifacts to Release** 工作流
3. 点击 **Run workflow**
4. 输入参数：
   - `tag`: 版本标签（如 `v1.0.0`）
   - `prerelease`: 是否为预发布版本
   - `skip_tests`: 是否跳过测试
5. 点击 **Run workflow**

#### 2.3 使用手动发布工作流

1. 访问仓库的 **Actions** 标签页
2. 选择 **Manual Release** 工作流
3. 点击 **Run workflow**
4. 输入参数：
   - `version`: 版本号（如 `v1.0.0`）
   - `release_type`: 发布类型（release/prerelease/draft）
   - `release_notes`: 自定义发布说明（可选）
5. 点击 **Run workflow**

### 方法 3: 使用脚本工具

项目提供了便捷的脚本工具：

```bash
# 创建标签并触发发布
scripts/trigger-release.sh create-tag v1.0.0

# 创建预发布版本
scripts/trigger-release.sh create-tag v1.0.0-beta --prerelease

# 查看工作流状态
scripts/trigger-release.sh status

# 列出所有发布
scripts/trigger-release.sh list-releases
```

## 🔧 工作流配置

### 环境变量

所有工作流使用以下环境变量：

```yaml
env:
  TEMPLATE_NAME: alpine-k3s
  BUILD_CACHE_KEY: build-cache-v1
  REGISTRY: ghcr.io
```

### 权限要求

工作流需要以下权限：

```yaml
permissions:
  contents: write      # 创建发布和标签
  packages: write      # 发布到容器注册表
  pull-requests: write # 创建和更新 PR
  issues: write        # 创建问题和通知
```

### Secrets 配置

工作流使用以下 Secrets：

- `GITHUB_TOKEN`: 自动提供，用于 GitHub API 操作

## 📊 工作流监控

### 查看工作流状态

#### 使用 GitHub 网页界面

1. 访问仓库的 **Actions** 标签页
2. 查看最近的工作流运行
3. 点击特定运行查看详细日志

#### 使用 GitHub CLI

```bash
# 列出工作流运行
gh run list

# 查看特定运行
gh run view <run-id>

# 实时监控运行
gh run watch <run-id>

# 下载运行日志
gh run download <run-id>
```

#### 使用项目脚本

```bash
# 查看最新状态
scripts/trigger-release.sh status

# 查看特定运行状态
scripts/trigger-release.sh status <run-id>
```

### 工作流通知

工作流会自动创建以下通知：

- **构建摘要**: 在工作流完成后显示
- **PR 评论**: 在 Pull Request 中显示构建状态
- **Issue 创建**: 发布后创建验证任务
- **失败通知**: 构建失败时创建问题

## 🐛 故障排除

### 常见问题

#### 1. 构建失败

**症状**: 构建作业失败
**解决方案**:
```bash
# 检查构建日志
gh run view <run-id> --log

# 本地测试构建
make build
make test

# 检查脚本权限
find scripts/ -name "*.sh" -not -executable
```

#### 2. 发布创建失败

**症状**: 发布作业失败
**可能原因**:
- 标签格式不正确
- 权限不足
- 网络问题

**解决方案**:
```bash
# 检查标签格式
git tag -l | grep v1.0.0

# 验证权限
gh auth status

# 重新运行工作流
gh run rerun <run-id>
```

#### 3. 制品上传失败

**症状**: 制品上传到 Release 失败
**解决方案**:
```bash
# 检查制品是否存在
ls -la output/

# 手动上传制品
gh release upload v1.0.0 output/*.tar.gz

# 检查存储空间
gh api repos/:owner/:repo | jq '.size'
```

### 调试模式

启用调试模式获取详细日志：

1. **手动触发时**: 设置 `debug_enabled: true`
2. **仓库级别**: 在 Settings > Secrets 中添加 `ACTIONS_STEP_DEBUG=true`
3. **本地测试**: 设置 `export DEBUG=true`

### 日志分析

工作流日志包含以下信息：

- **构建时间**: 每个步骤的执行时间
- **文件大小**: 生成的制品文件大小
- **错误信息**: 详细的错误堆栈
- **环境信息**: 构建环境的详细信息

## 📈 最佳实践

### 发布流程

1. **开发阶段**:
   - 在功能分支上开发
   - 创建 PR 触发测试
   - 合并到主分支

2. **测试阶段**:
   - 使用 `test-build.yml` 验证构建
   - 在测试分支上验证功能
   - 运行完整测试套件

3. **发布阶段**:
   - 更新版本号和文档
   - 创建版本标签
   - 验证发布制品
   - 测试部署

### 版本管理

- 使用语义化版本号 (`v1.0.0`)
- 预发布版本使用后缀 (`v1.0.0-beta`)
- 及时清理旧的预发布版本
- 维护详细的发布说明

### 安全考虑

- 定期更新 Actions 版本
- 使用最小权限原则
- 验证制品校验和
- 监控安全扫描结果

## 🤝 贡献指南

### 改进工作流

欢迎提交以下改进：

1. **性能优化**: 减少构建时间
2. **功能增强**: 添加新的测试或检查
3. **错误处理**: 改进错误处理和恢复
4. **文档更新**: 完善使用说明

### 提交流程

1. Fork 仓库
2. 创建功能分支
3. 修改工作流文件
4. 测试工作流
5. 创建 Pull Request

## 📞 支持

如果遇到问题：

1. 查看本文档和相关日志
2. 搜索现有 Issues
3. 创建新的 Issue 描述问题
4. 联系项目维护者

## 🎯 总结

GitHub Actions 工作流提供了完整的自动化解决方案：

- **自动化构建**: 从代码到制品的全自动流程
- **质量保证**: 自动测试和验证
- **灵活发布**: 支持多种发布场景
- **监控调试**: 完整的日志和状态跟踪
- **安全可靠**: 权限控制和安全扫描

通过这些工作流，你可以轻松地管理 PVE LXC K3s 模板的整个生命周期。