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

- Proxmox VE 环境
- 支持 LXC 容器的系统
- 网络连接用于下载依赖

### 使用方法

1. 从 GitHub Releases 下载最新的模板文件
2. 在 PVE 中导入 LXC 模板
3. 创建容器并启动
4. K3s 集群将自动启动并可用

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