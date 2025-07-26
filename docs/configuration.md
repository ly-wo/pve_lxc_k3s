# 配置指南

本指南详细说明了如何自定义 PVE LXC K3s 模板的各种配置选项。

## 配置文件概述

模板使用 YAML 格式的配置文件来定义构建参数。主配置文件位于 `config/template.yaml`。

### 配置文件结构

```yaml
template:      # 模板基本信息
k3s:          # K3s 相关配置
system:       # 系统级配置
security:     # 安全相关配置
network:      # 网络配置
storage:      # 存储配置
build:        # 构建选项
```

## 模板基本配置

### template 部分

```yaml
template:
  name: "alpine-k3s"                    # 模板名称
  version: "1.0.0"                      # 版本号（语义化版本）
  description: "Alpine Linux LXC template with pre-installed K3s"
  author: "Your Name"                   # 作者信息
  base_image: "alpine:3.18"             # 基础镜像
  architecture: "amd64"                 # 目标架构
```

**配置说明**:
- `name`: 模板名称，只能包含小写字母、数字和连字符
- `version`: 遵循语义化版本规范 (major.minor.patch)
- `base_image`: 支持的 Alpine 版本：3.16, 3.17, 3.18
- `architecture`: 支持 amd64, arm64, armv7

## K3s 配置

### 基本 K3s 配置

```yaml
k3s:
  version: "v1.28.4+k3s1"               # K3s 版本
  cluster_init: true                    # 是否初始化为集群服务器
  install_options:                      # 安装选项
    - "--disable=traefik"               # 禁用 Traefik
    - "--disable=servicelb"             # 禁用 ServiceLB
    - "--write-kubeconfig-mode=644"     # kubeconfig 文件权限
  server_options: []                    # 服务器额外选项
  agent_options: []                     # 代理额外选项
```

### 常用 K3s 安装选项

| 选项 | 说明 | 示例 |
|------|------|------|
| `--disable` | 禁用内置组件 | `--disable=traefik,servicelb` |
| `--write-kubeconfig-mode` | kubeconfig 权限 | `--write-kubeconfig-mode=644` |
| `--cluster-cidr` | Pod 网络 CIDR | `--cluster-cidr=10.42.0.0/16` |
| `--service-cidr` | 服务网络 CIDR | `--service-cidr=10.43.0.0/16` |
| `--cluster-dns` | 集群 DNS 地址 | `--cluster-dns=10.43.0.10` |
| `--node-taint` | 节点污点 | `--node-taint=key=value:NoSchedule` |

### 高可用配置

```yaml
k3s:
  version: "v1.28.4+k3s1"
  cluster_init: true
  install_options:
    - "--disable=traefik"
    - "--disable=servicelb"
    - "--cluster-init"                  # 启用集群初始化
    - "--datastore-endpoint=etcd"       # 使用外部数据存储
  server_options:
    - "--etcd-expose-metrics=true"      # 暴露 etcd 指标
```

## 系统配置

### 基本系统设置

```yaml
system:
  timezone: "Asia/Shanghai"             # 时区设置
  locale: "zh_CN.UTF-8"                # 语言环境
  packages:                            # 要安装的包
    - curl
    - wget
    - ca-certificates
    - openssl
    - bash
    - coreutils
    - htop                             # 系统监控工具
    - nano                             # 文本编辑器
  remove_packages:                     # 要移除的包
    - apk-tools-doc
    - man-pages
    - docs
  services:
    enable:                            # 启用的服务
      - k3s
      - chronyd                        # 时间同步
    disable:                           # 禁用的服务
      - sshd                           # 如果不需要 SSH
```

### 时区配置

支持的时区格式：
- `UTC` - 协调世界时
- `Asia/Shanghai` - 中国标准时间
- `Europe/London` - 英国时间
- `America/New_York` - 美国东部时间

### 包管理

**推荐安装的包**:
```yaml
packages:
  # 基础工具
  - curl
  - wget
  - ca-certificates
  - openssl
  
  # 系统工具
  - bash
  - coreutils
  - util-linux
  
  # 监控工具
  - htop
  - iotop
  - nethogs
  
  # 网络工具
  - bind-tools
  - tcpdump
  - netcat-openbsd
  
  # 编辑器
  - nano
  - vim
```

**建议移除的包**:
```yaml
remove_packages:
  # 文档和手册
  - apk-tools-doc
  - man-pages
  - docs
  
  # 开发工具（生产环境）
  - gcc
  - make
  - libc-dev
  
  # 不必要的服务
  - chronyd  # 如果使用容器时间同步
```

## 安全配置

### 用户和权限

```yaml
security:
  disable_root_login: true              # 禁用 root 登录
  create_k3s_user: true                # 创建专用 K3s 用户
  k3s_user: "k3s"                     # K3s 用户名
  k3s_uid: 1000                       # 用户 ID
  k3s_gid: 1000                       # 组 ID
```

### 防火墙配置

```yaml
security:
  firewall_rules:
    - port: "6443"                     # K3s API 服务器
      protocol: "tcp"
      description: "K3s API Server"
    - port: "10250"                    # Kubelet API
      protocol: "tcp"
      description: "Kubelet API"
    - port: "8472"                     # Flannel VXLAN
      protocol: "udp"
      description: "Flannel VXLAN"
    - port: "2379-2380"                # etcd（高可用模式）
      protocol: "tcp"
      description: "etcd client/peer"
```

### 安全加固选项

```yaml
security:
  remove_packages:                     # 移除安全风险包
    - apk-tools                        # 包管理工具
    - alpine-keys                      # 签名密钥
  
  # 额外安全选项
  harden_kernel: true                  # 内核加固
  disable_unused_filesystems: true     # 禁用未使用的文件系统
  secure_mount_options: true           # 安全挂载选项
```

## 网络配置

### 基本网络设置

```yaml
network:
  dns_servers:                         # DNS 服务器
    - "8.8.8.8"
    - "8.8.4.4"
    - "1.1.1.1"                       # Cloudflare DNS
  search_domains:                      # 搜索域
    - "local"
    - "cluster.local"
  cluster_cidr: "10.42.0.0/16"        # Pod 网络
  service_cidr: "10.43.0.0/16"        # 服务网络
  cluster_dns: "10.43.0.10"           # 集群 DNS
```

### 高级网络配置

```yaml
network:
  interfaces:                          # 网络接口配置
    - name: "eth0"
      type: "bridge"
      bridge: "vmbr0"
      ip: "dhcp"                       # 或静态 IP
    - name: "eth1"                     # 额外网络接口
      type: "bridge"
      bridge: "vmbr1"
      ip: "192.168.100.10/24"
      gateway: "192.168.100.1"
  
  # CNI 配置
  cni_plugin: "flannel"                # 或 "calico", "cilium"
  cni_options:
    - "--flannel-backend=vxlan"
```

## 存储配置

### 基本存储设置

```yaml
storage:
  cleanup_paths:                       # 构建时清理的路径
    - "/tmp/*"
    - "/var/cache/apk/*"
    - "/var/log/*"
    - "/root/.cache/*"
```

### 持久化存储

```yaml
storage:
  volumes:                             # 存储卷配置
    - name: "k3s-data"
      path: "/var/lib/rancher/k3s"
      size: "10G"
      type: "local"
    - name: "container-data"
      path: "/var/lib/containerd"
      size: "20G"
      type: "local"
  
  mounts:                              # 挂载点配置
    - source: "/host/data"
      target: "/data"
      type: "bind"
      options: "rw,bind"
```

## 构建配置

### 构建优化

```yaml
build:
  cleanup_after_install: true          # 安装后清理
  optimize_size: true                  # 优化模板大小
  include_docs: false                  # 不包含文档
  parallel_jobs: 2                     # 并行构建任务数
  
  # 高级选项
  strip_binaries: true                 # 剥离二进制文件
  compress_layers: true                # 压缩层
  remove_build_deps: true              # 移除构建依赖
```

### 构建缓存

```yaml
build:
  cache:
    enabled: true                      # 启用构建缓存
    ttl: "24h"                        # 缓存生存时间
    size: "1G"                        # 缓存大小限制
```

## 环境特定配置

### 开发环境

```yaml
# config/dev.yaml
template:
  name: "alpine-k3s-dev"
  
k3s:
  install_options:
    - "--disable=traefik"
    - "--write-kubeconfig-mode=644"
    
system:
  packages:
    - curl
    - wget
    - bash
    - htop
    - nano
    - git                              # 开发工具
    - docker                           # 容器工具
    
build:
  include_docs: true                   # 包含文档
  optimize_size: false                 # 不优化大小
```

### 生产环境

```yaml
# config/prod.yaml
template:
  name: "alpine-k3s-prod"
  
security:
  disable_root_login: true
  harden_kernel: true
  
system:
  packages:
    - curl
    - wget
    - ca-certificates
    # 最小化包集合
    
build:
  cleanup_after_install: true
  optimize_size: true
  strip_binaries: true
```

## 配置验证

### 使用配置验证工具

```bash
# 验证配置文件语法
./scripts/config-validator.sh config/template.yaml

# 验证配置完整性
./scripts/config-validator.sh --strict config/template.yaml

# 生成配置文档
./scripts/config-validator.sh --docs config/template.yaml
```

### 常见配置错误

1. **版本格式错误**:
   ```yaml
   # 错误
   version: "1.0"
   
   # 正确
   version: "1.0.0"
   ```

2. **网络 CIDR 冲突**:
   ```yaml
   # 确保不同网络不重叠
   cluster_cidr: "10.42.0.0/16"
   service_cidr: "10.43.0.0/16"  # 不能与 cluster_cidr 重叠
   ```

3. **端口冲突**:
   ```yaml
   # 检查防火墙规则中的端口不冲突
   firewall_rules:
     - port: "6443"
       protocol: "tcp"
   ```

## 配置模板示例

### 最小配置

```yaml
template:
  name: "alpine-k3s-minimal"
  version: "1.0.0"
  base_image: "alpine:3.18"

k3s:
  version: "v1.28.4+k3s1"

system:
  packages:
    - curl
    - ca-certificates
```

### 完整配置

参考 `config/template.yaml` 文件获取完整的配置示例。

## 下一步

配置完成后，您可以：

1. [构建自定义模板](building.md)
2. [部署和测试](installation.md)
3. [故障排查](troubleshooting.md)

如需更多帮助，请参考 [API 文档](api.md) 或提交 [Issue](../../issues)。