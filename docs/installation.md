# 安装指南

本指南将帮助您在 Proxmox VE 环境中安装和使用 PVE LXC K3s 模板。

## 前置要求

### 系统要求

- **Proxmox VE**: 版本 7.0 或更高
- **CPU**: 支持虚拟化的 x86_64 处理器
- **内存**: 至少 2GB 可用内存
- **存储**: 至少 10GB 可用存储空间
- **网络**: 互联网连接用于下载依赖

### 权限要求

- PVE 管理员权限或具有以下权限的用户：
  - VM.Allocate
  - VM.Config.Disk
  - VM.Config.Memory
  - VM.Config.Network
  - VM.Config.Options

## 下载模板

### 方法一：从 GitHub Releases 下载

1. 访问项目的 [GitHub Releases 页面](../../releases)
2. 下载最新版本的模板文件（通常以 `.tar.gz` 结尾）
3. 将文件保存到您的本地计算机

### 方法二：使用 wget 直接下载

```bash
# 下载最新版本（替换 VERSION 为实际版本号）
wget https://github.com/your-username/pve-lxc-k3s-template/releases/download/v1.0.0/alpine-k3s-template-v1.0.0.tar.gz

# 验证下载完整性（可选）
wget https://github.com/your-username/pve-lxc-k3s-template/releases/download/v1.0.0/alpine-k3s-template-v1.0.0.tar.gz.sha256
sha256sum -c alpine-k3s-template-v1.0.0.tar.gz.sha256
```

## 导入模板到 PVE

### 使用 Web 界面

1. 登录 PVE Web 管理界面
2. 选择目标节点
3. 点击 "本地 (节点名)" 存储
4. 选择 "CT 模板" 选项卡
5. 点击 "上传" 按钮
6. 选择下载的模板文件并上传

### 使用命令行

```bash
# 将模板文件复制到 PVE 节点
scp alpine-k3s-template-v1.0.0.tar.gz root@pve-node:/var/lib/vz/template/cache/

# 或者直接在 PVE 节点上下载
wget -O /var/lib/vz/template/cache/alpine-k3s-template-v1.0.0.tar.gz \
  https://github.com/your-username/pve-lxc-k3s-template/releases/download/v1.0.0/alpine-k3s-template-v1.0.0.tar.gz
```

## 创建容器

### 使用 Web 界面创建

1. 在 PVE Web 界面中，点击 "创建 CT"
2. 填写基本信息：
   - **CT ID**: 选择一个未使用的 ID（如 100）
   - **主机名**: 为容器设置主机名（如 k3s-master）
   - **密码**: 设置 root 密码（建议使用强密码）

3. 选择模板：
   - **存储**: 选择包含模板的存储
   - **模板**: 选择 `alpine-k3s-template-v1.0.0.tar.gz`

4. 配置资源：
   - **内存**: 建议至少 2048 MB
   - **交换**: 建议 512 MB
   - **CPU 核心**: 建议至少 2 核

5. 配置网络：
   - **网桥**: 选择合适的网桥（通常是 vmbr0）
   - **IPv4**: 选择 DHCP 或配置静态 IP
   - **IPv6**: 根据需要配置

6. 配置存储：
   - **根磁盘**: 建议至少 8 GB
   - **存储**: 选择合适的存储后端

7. 点击 "创建" 完成容器创建

### 使用命令行创建

```bash
# 创建基本容器
pct create 100 /var/lib/vz/template/cache/alpine-k3s-template-v1.0.0.tar.gz \
  --hostname k3s-master \
  --memory 2048 \
  --swap 512 \
  --cores 2 \
  --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --password

# 创建具有静态 IP 的容器
pct create 101 /var/lib/vz/template/cache/alpine-k3s-template-v1.0.0.tar.gz \
  --hostname k3s-worker \
  --memory 2048 \
  --swap 512 \
  --cores 2 \
  --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.100/24,gw=192.168.1.1 \
  --nameserver 8.8.8.8 \
  --password
```

## 启动和配置

### 启动容器

```bash
# 启动容器
pct start 100

# 查看容器状态
pct status 100

# 查看容器日志
pct logs 100
```

### 首次配置

1. **等待 K3s 启动**：
   容器启动后，K3s 服务会自动启动。首次启动可能需要几分钟时间下载镜像。

2. **检查 K3s 状态**：
   ```bash
   # 进入容器
   pct enter 100
   
   # 检查 K3s 服务状态
   systemctl status k3s
   
   # 检查节点状态
   k3s kubectl get nodes
   
   # 检查 Pod 状态
   k3s kubectl get pods -A
   ```

3. **获取 kubeconfig**：
   ```bash
   # 在容器内
   cat /etc/rancher/k3s/k3s.yaml
   
   # 或者从 PVE 主机复制
   pct exec 100 -- cat /etc/rancher/k3s/k3s.yaml > k3s-config.yaml
   ```

## 验证安装

### 基本功能测试

```bash
# 进入容器
pct enter 100

# 检查 K3s 版本
k3s --version

# 检查集群信���
k3s kubectl cluster-info

# 部署测试应用
k3s kubectl create deployment nginx --image=nginx
k3s kubectl expose deployment nginx --port=80 --type=NodePort

# 检查部署状态
k3s kubectl get deployments
k3s kubectl get services
```

### 网络连通性测试

```bash
# 测试 DNS 解析
nslookup kubernetes.default.svc.cluster.local

# 测试 Pod 网络
k3s kubectl run test-pod --image=busybox --rm -it -- /bin/sh
# 在 Pod 内执行：
# ping 10.43.0.1  # 测试服务网络
# nslookup kubernetes  # 测试 DNS
```

### 性能测试

```bash
# 检查资源使用情况
k3s kubectl top nodes
k3s kubectl top pods -A

# 检查系统资源
free -h
df -h
top
```

## 常见问题

### K3s 服务无法启动

**症状**: `systemctl status k3s` 显示服务失败

**解决方案**:
1. 检查系统日志：`journalctl -u k3s -f`
2. 检查网络配置：确保容器有网络连接
3. 检查内存：确保至少有 1GB 可用内存
4. 重启服务：`systemctl restart k3s`

### 无法访问 Kubernetes API

**症状**: `k3s kubectl` 命令超时或连接被拒绝

**解决方案**:
1. 检查 K3s 服务状态：`systemctl status k3s`
2. 检查端口监听：`netstat -tlnp | grep 6443`
3. 检查防火墙设置
4. 重新生成证书：`systemctl stop k3s && rm -rf /var/lib/rancher/k3s/server/tls && systemctl start k3s`

### 容器启动缓慢

**症状**: 容器启动时间超过 5 分钟

**解决方案**:
1. 检查存储性能：使用 SSD 存储
2. 增加内存分配：至少 2GB
3. 检查网络连接：确保能访问互联网
4. 查看启动日志：`pct logs 100`

### Pod 无法调度

**症状**: Pod 一直处于 Pending 状态

**解决方案**:
1. 检查节点状态：`k3s kubectl get nodes`
2. 检查资源限制：`k3s kubectl describe pod <pod-name>`
3. 检查污点和容忍度设置
4. 增加节点资源或添加更多节点

## 下一步

安装完成后，您可以：

1. [配置自定义选项](configuration.md)
2. [扩展为多节点集群](clustering.md)
3. [部署应用程序](applications.md)
4. [设置监控和日志](monitoring.md)

如果遇到问题，请参考 [故障排查指南](troubleshooting.md)。