# PVE LXC K3s Template Generator

一个自动化工具，用于生成适用于 Proxmox VE (PVE) 的 LXC 容器模板。该模板基于 Alpine Linux，预装并配置 K3s Kubernetes 集群，实现一键启动即可使用的轻量级 Kubernetes 环境。

## 功能特性

- 🚀 基于 Alpine Linux 的轻量级 LXC 模板
- ⚡ 预装 K3s Kubernetes 集群
- 🔧 支持自定义配置和参数
- 🔒 内置安全加固和最佳实践
- 📦 GitHub Actions 自动构建和发布
- 🔄 支持多节点集群扩展
- 📊 完整的日志记录和监控

## 快速开始

### 前置要求

- Proxmox VE 7.4+ 或 8.0+
- 支持 LXC 容器的系统
- 网络连接用于下载依赖

### 使用预构建模板

1. **下载模板**：
   ```bash
   wget https://github.com/your-username/pve-lxc-k3s-template/releases/latest/download/alpine-k3s-latest.tar.gz
   ```

2. **上传到 PVE**：
   ```bash
   pveam upload local alpine-k3s-latest.tar.gz
   ```

3. **创建容器**：
   ```bash
   pct create 100 local:vztmpl/alpine-k3s-latest.tar.gz \
     --hostname k3s-master \
     --memory 2048 \
     --cores 2 \
     --rootfs local-lvm:20 \
     --net0 name=eth0,bridge=vmbr0,ip=dhcp \
     --unprivileged 1
   ```

4. **启动并验证**：
   ```bash
   pct start 100
   pct exec 100 -- k3s kubectl get nodes
   ```

### 自动化发布

项目使用 GitHub Actions 自动构建和发布：

- **自动发布**：推送版本标签即可触发自动构建和发布
- **手动发布**：通过 GitHub Actions 界面手动触发
- **测试构建**：每次 PR 都会自动测试构建

详细说明请参考 [GitHub Actions 使用指南](docs/github-actions-usage.md)。

## 项目结构

```
├── config/          # 配置文件和模板
├── scripts/         # 构建和安装脚本
├── tests/           # 测试文件
├── docs/            # 文档
├── .github/         # GitHub Actions 工作流
└── README.md        # 项目说明
```

## 配置

模板支持通过配置文件自定义各种参数：

- K3s 版本和安装选项
- 系统包和服务配置
- 网络和安全设置
- 资源限制和优化

详细配置说明请参考 [配置文档](docs/configuration.md)。

## GitHub Actions 自动化

### 🚀 快速发布

创建版本标签即可自动发布：

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### 📋 可用工作流

- **主构建工作流**: 完整的构建、测试和发布流程
- **手动发布工作流**: 可控的手动发布流程
- **测试构建工作流**: 快速验证构建系统
- **依赖更新工作流**: 自动更新 K3s 和 Alpine 版本

### 📚 相关文档

- [GitHub Actions 使用指南](docs/github-actions-usage.md)
- [快速开始指南](docs/quick-start-actions.md)
- [发布流程文档](docs/release-process.md)

## 开发

### 构建模板

```bash
# 构建模板
make build

# 运行测试
make test

# 清理构建文件
make clean
```

### 贡献

欢迎提交 Issue 和 Pull Request！请参考 [贡献指南](docs/contributing.md)。

## 许可证

本项目采用 MIT 许可证。详情请参考 [LICENSE](LICENSE) 文件。

## 支持

如有问题或建议，请：

1. 查看 [文档](docs/)
2. 搜索现有的 [Issues](../../issues)
3. 创建新的 [Issue](../../issues/new)

## 致谢

感谢以下项目和社区：

- [K3s](https://k3s.io/) - 轻量级 Kubernetes
- [Alpine Linux](https://alpinelinux.org/) - 安全、简单的 Linux 发行版
- [Proxmox VE](https://www.proxmox.com/en/proxmox-ve) - 开源虚拟化平台