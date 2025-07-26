# GitHub Actions 快速开始

## 🚀 5分钟快速发布

### 步骤 1: 准备代码

确保你的代码已经提交到主分支：

```bash
git add .
git commit -m "feat: ready for first release"
git push origin main
```

### 步骤 2: 创建发布

选择以下任一方式：

#### 方式 A: 标签自动发布（最简单）

```bash
# 创建版本标签
git tag -a v1.0.0 -m "First release"
git push origin v1.0.0
```

✅ **完成！** GitHub Actions 将自动：
- 构建模板
- 运行测试
- 创建 Release
- 上传制品文件

#### 方式 B: 手动触发发布

1. 访问 GitHub 仓库页面
2. 点击 **Actions** 标签
3. 选择 **Manual Release** 工作流
4. 点击 **Run workflow**
5. 输入版本号：`v1.0.0`
6. 选择发布类型：`release`
7. 点击 **Run workflow**

### 步骤 3: 监控进度

- 在 **Actions** 页面查看构建进度
- 大约 5-10 分钟后完成
- 检查 **Releases** 页面确认发布成功

## 📋 发布检查清单

在创建发布前，确保：

- [ ] 代码已提交到主分支
- [ ] 版本号格式正确 (`v1.0.0`)
- [ ] 配置文件 `config/template.yaml` 存在
- [ ] 构建脚本有执行权限

## 🔧 常用命令

### 查看工作流状态

```bash
# 使用 GitHub CLI
gh run list --limit 5

# 查看特定运行
gh run view <run-id>

# 实时监控
gh run watch <run-id>
```

### 管理发布

```bash
# 列出所有发布
gh release list

# 查看发布详情
gh release view v1.0.0

# 下载发布文件
gh release download v1.0.0
```

## 🎯 发布类型

### 正式发布

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### 预发布版本

```bash
git tag -a v1.0.0-beta -m "Beta release v1.0.0"
git push origin v1.0.0-beta
```

### 修复版本

```bash
git tag -a v1.0.1 -m "Hotfix v1.0.1"
git push origin v1.0.1
```

## 🐛 快速故障排除

### 构建失败

1. 检查 Actions 页面的错误日志
2. 确认所有脚本文件有执行权限：
   ```bash
   chmod +x scripts/*.sh
   git add scripts/
   git commit -m "fix: script permissions"
   git push
   ```

### 发布失败

1. 检查版本标签格式是否正确
2. 确认没有重复的标签：
   ```bash
   git tag -d v1.0.0  # 删除本地标签
   git push origin :refs/tags/v1.0.0  # 删除远程标签
   ```

### 权限问题

确保仓库设置中启用了：
- Actions 权限
- 写入权限
- 包发布权限

## 📊 成功指标

发布成功后，你应该看到：

- ✅ GitHub Release 页面有新发布
- ✅ 制品文件已上传（.tar.gz 和校验和文件）
- ✅ 发布说明自动生成
- ✅ 容器镜像发布到 GitHub Container Registry

## 🎉 下一步

发布成功后：

1. **测试部署**: 下载模板文件并在 PVE 中测试
2. **更新文档**: 更新 README 中的版本信息
3. **宣布发布**: 在相关社区宣布新版本
4. **收集反馈**: 监控 Issues 和用户反馈

## 💡 提示

- 使用语义化版本号 (v1.0.0, v1.1.0, v2.0.0)
- 预发布版本用于测试 (v1.0.0-beta, v1.0.0-rc1)
- 每次发布前运行本地测试
- 保持发布说明简洁明了

---

**就是这么简单！** 🚀 现在你可以轻松地发布 PVE LXC K3s 模板了。