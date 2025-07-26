# 故障排查指南

本指南帮助您诊断和解决使用 PVE LXC K3s 模板时可能遇到的常见问题。

## 快速诊断

### 系统健康检查

```bash
# 运行自动诊断脚本
./scripts/system-diagnostics.sh

# 检查 K3s 健康状态
./scripts/k3s-health-check.sh

# 查看系统资源使用情况
./scripts/monitoring.sh --status
```

### 日志查看

```bash
# 查看构建日志
tail -f logs/build.log

# 查看 K3s 服务日志
journalctl -u k3s -f

# 查看系统日志
journalctl -f
```

## 构建阶段问题

### 问题：模板构建失败

**症状**:
- GitHub Actions 构建失败
- 本地构建脚本报错
- 构建过程中断

**诊断步骤**:

1. **检查构建日志**:
   ```bash
   # 查看详细构建日志
   cat logs/build.log | grep -i error
   
   # 查看最近的构建错误
   tail -100 logs/build.log
   ```

2. **验证配置文件**:
   ```bash
   # 验证配置语法
   ./scripts/config-validator.sh config/template.yaml
   
   # 检查配置完整性
   yamllint config/template.yaml
   ```

3. **检查网络连接**:
   ```bash
   # 测试网络连通性
   curl -I https://get.k3s.io
   curl -I https://dl-cdn.alpinelinux.org
   ```

**常见解决方案**:

- **网络超时**: 增加重试次数或使用镜像源
  ```yaml
  build:
    retry_count: 5
    timeout: 300
  ```

- **磁盘空间不足**: 清理构建缓存
  ```bash
  make clean
  docker system prune -a
  ```

- **权限问题**: 检查文件权限
  ```bash
  chmod +x scripts/*.sh
  ```

### 问题：基础镜像下载失败

**症状**:
- Alpine 镜像下载超时
- 镜像校验失败
- 网络连接错误

**解决方案**:

1. **使用镜像源**:
   ```yaml
   # config/template.yaml
   template:
     base_image: "alpine:3.18"
     mirror: "mirrors.aliyun.com"  # 使用阿里云镜像
   ```

2. **手动下载镜像**:
   ```bash
   # 预先下载镜像
   docker pull alpine:3.18
   
   # 导出镜像
   docker save alpine:3.18 > alpine-3.18.tar
   ```

3. **验证镜像完整性**:
   ```bash
   # 检查镜像 SHA256
   docker images --digests alpine:3.18
   ```

### 问题：K3s 安装失败

**症状**:
- K3s 下载失败
- 安装脚本报错
- 版本不兼容

**诊断步骤**:

1. **检查 K3s 版本**:
   ```bash
   # 验证版本格式
   echo "v1.28.4+k3s1" | grep -E "^v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+$"
   
   # 检查版本可用性
   curl -I https://github.com/k3s-io/k3s/releases/tag/v1.28.4+k3s1
   ```

2. **检查系统兼容性**:
   ```bash
   # 检查内核版本
   uname -r
   
   # 检查 cgroup 支持
   cat /proc/cgroups
   
   # 检查容器运行时支持
   which containerd
   ```

**解决方案**:

- **使用稳定版本**: 选择经过测试的 K3s 版本
- **启用兼容模式**: 添加兼容性选项
  ```yaml
  k3s:
    install_options:
      - "--disable=traefik"
      - "--container-runtime-endpoint=unix:///run/containerd/containerd.sock"
  ```

## 部署阶段问题

### 问题：容器创建失败

**症状**:
- PVE 无法创建容器
- 模板导入失败
- 资源分配错误

**诊断步骤**:

1. **检查模板文件**:
   ```bash
   # 验证模板文件完整性
   tar -tzf alpine-k3s-template-v1.0.0.tar.gz
   
   # 检查文件大小
   ls -lh alpine-k3s-template-v1.0.0.tar.gz
   ```

2. **检查 PVE 资源**:
   ```bash
   # 检查存储空间
   pvesm status
   
   # 检查内存使用
   free -h
   
   # 检查 CPU 负载
   uptime
   ```

3. **查看 PVE 日志**:
   ```bash
   # 查看系统日志
   journalctl -u pvedaemon -f
   
   # 查看容器日志
   journalctl -u pve-container@100 -f
   ```

**解决方案**:

- **增加资源限制**:
  ```bash
  # 创建容器时分配更多资源
  pct create 100 template.tar.gz \
    --memory 4096 \
    --cores 4 \
    --rootfs local-lvm:16
  ```

- **检查网络配置**:
  ```bash
  # 验证网桥配置
  ip link show vmbr0
  
  # 检查网络连通性
  ping -c 3 8.8.8.8
  ```

### 问题：容器启动失败

**症状**:
- 容器无法启动
- 启动过程卡住
- 服务启动失败

**诊断步骤**:

1. **检查容器状态**:
   ```bash
   # 查看容器状态
   pct status 100
   
   # 查看容器配置
   pct config 100
   
   # 查看启动日志
   pct logs 100
   ```

2. **进入容器调试**:
   ```bash
   # 进入容器
   pct enter 100
   
   # 检查系统服务
   systemctl status
   
   # 检查网络配置
   ip addr show
   ```

**解决方案**:

- **重启容器**:
  ```bash
  pct stop 100
  pct start 100
  ```

- **重置网络配置**:
  ```bash
  # 在容器内重置网络
  systemctl restart networking
  ```

- **检查启动脚本**:
  ```bash
  # 查看启动脚本
  cat /etc/init.d/k3s
  
  # 手动启动服务
  systemctl start k3s
  ```

## 运行时问题

### 问题：K3s 服务无法启动

**症状**:
- `systemctl status k3s` 显示失败
- K3s API 不可访问
- 节点状态异常

**诊断步骤**:

1. **检查服务状态**:
   ```bash
   # 查看服务详细状态
   systemctl status k3s -l
   
   # 查看服务日志
   journalctl -u k3s -n 50
   
   # 检查进程
   ps aux | grep k3s
   ```

2. **检查配置文件**:
   ```bash
   # 验证 K3s 配置
   cat /etc/rancher/k3s/config.yaml
   
   # 检查权限
   ls -la /etc/rancher/k3s/
   ```

3. **检查网络和端口**:
   ```bash
   # 检查端口监听
   netstat -tlnp | grep 6443
   
   # 测试 API 连接
   curl -k https://localhost:6443/version
   ```

**解决方案**:

- **重启服务**:
  ```bash
  systemctl stop k3s
  systemctl start k3s
  ```

- **重置 K3s 数据**:
  ```bash
  systemctl stop k3s
  rm -rf /var/lib/rancher/k3s/server/db
  systemctl start k3s
  ```

- **检查防火墙**:
  ```bash
  # 临时关闭防火墙测试
  systemctl stop firewalld
  systemctl start k3s
  ```

### 问题：Pod 无法启动

**症状**:
- Pod 处于 Pending 状态
- 镜像拉取失败
- 资源不足

**诊断步骤**:

1. **检查 Pod 状态**:
   ```bash
   # 查看 Pod 详情
   k3s kubectl describe pod <pod-name>
   
   # 查看事件
   k3s kubectl get events --sort-by=.metadata.creationTimestamp
   
   # 检查节点资源
   k3s kubectl top nodes
   ```

2. **检查镜像**:
   ```bash
   # 查看镜像列表
   k3s crictl images
   
   # 手动拉取镜像
   k3s crictl pull nginx:latest
   ```

**解决方案**:

- **增加节点资源**:
  ```bash
  # 修改容器资源限制
  pct set 100 --memory 4096 --cores 4
  ```

- **配置镜像仓库**:
  ```yaml
  # /etc/rancher/k3s/registries.yaml
  mirrors:
    docker.io:
      endpoint:
        - "https://registry.cn-hangzhou.aliyuncs.com"
  ```

- **清理无用资源**:
  ```bash
  # 清理未使用的镜像
  k3s crictl rmi --prune
  
  # 清理已完成的 Pod
  k3s kubectl delete pods --field-selector=status.phase=Succeeded
  ```

### 问题：网络连通性问题

**症状**:
- Pod 之间无法通信
- 服务无法访问
- DNS 解析失败

**诊断步骤**:

1. **检查网络配置**:
   ```bash
   # 查看网络接口
   ip addr show
   
   # 查看路由表
   ip route show
   
   # 检查 CNI 配置
   cat /var/lib/rancher/k3s/server/manifests/flannel.yaml
   ```

2. **测试网络连通性**:
   ```bash
   # 测试 Pod 网络
   k3s kubectl run test-pod --image=busybox --rm -it -- /bin/sh
   
   # 在 Pod 内测试
   ping 10.43.0.1  # 服务网络
   nslookup kubernetes.default.svc.cluster.local
   ```

**解决方案**:

- **重启网络服务**:
  ```bash
  systemctl restart k3s
  ```

- **重置网络配置**:
  ```bash
  # 删除网络配置
  rm -rf /var/lib/rancher/k3s/server/manifests/flannel.yaml
  systemctl restart k3s
  ```

- **检查防火墙规则**:
  ```bash
  # 查看 iptables 规则
  iptables -L -n
  
  # 临时清空规则测试
  iptables -F
  ```

## 性能问题

### 问题：系统响应缓慢

**症状**:
- 命令执行缓慢
- API 响应超时
- 资源使用率高

**诊断步骤**:

1. **检查系统资源**:
   ```bash
   # CPU 使用情况
   top
   htop
   
   # 内存使用情况
   free -h
   cat /proc/meminfo
   
   # 磁盘 I/O
   iotop
   iostat -x 1
   
   # 网络使用情况
   nethogs
   iftop
   ```

2. **检查 K3s 资源使用**:
   ```bash
   # 查看 K3s 进程资源使用
   ps aux | grep k3s
   
   # 查看容器资源使用
   k3s crictl stats
   
   # 查看 Pod 资源使用
   k3s kubectl top pods -A
   ```

**解决方案**:

- **优化资源配置**:
  ```bash
  # 增加容器资源
  pct set 100 --memory 8192 --cores 8
  ```

- **调整 K3s 配置**:
  ```yaml
  # 减少资源使用
  k3s:
    install_options:
      - "--disable=traefik"
      - "--disable=servicelb"
      - "--disable=metrics-server"
  ```

- **清理系统**:
  ```bash
  # 清理日志
  journalctl --vacuum-time=7d
  
  # 清理缓存
  sync && echo 3 > /proc/sys/vm/drop_caches
  ```

### 问题：存储空间不足

**症状**:
- 磁盘空间满
- 无法创建新 Pod
- 日志写入失败

**诊断步骤**:

```bash
# 检查磁盘使用情况
df -h

# 查找大文件
du -sh /* | sort -hr | head -10

# 检查日志大小
du -sh /var/log/*

# 检查容器镜像大小
k3s crictl images | awk '{print $3}' | tail -n +2 | xargs -I {} k3s crictl inspecti {} | grep size
```

**解决方案**:

- **清理日志**:
  ```bash
  # 清理系统日志
  journalctl --vacuum-size=100M
  
  # 清理 K3s 日志
  truncate -s 0 /var/log/k3s.log
  ```

- **清理镜像**:
  ```bash
  # 删除未使用的镜像
  k3s crictl rmi --prune
  
  # 删除已停止的容器
  k3s crictl rm $(k3s crictl ps -a -q)
  ```

- **扩展存储**:
  ```bash
  # 扩展容器磁盘
  pct resize 100 rootfs +10G
  ```

## 集群问题

### 问题：节点无法加入集群

**症状**:
- 新节点无法连接到集群
- 节点状态显示 NotReady
- 集群令牌错误

**诊断步骤**:

1. **检查集群状态**:
   ```bash
   # 在主节点检查集群状态
   k3s kubectl get nodes -o wide
   
   # 查看节点详情
   k3s kubectl describe node <node-name>
   ```

2. **检查网络连通性**:
   ```bash
   # 测试节点间连通性
   ping <master-node-ip>
   
   # 测试 API 端口
   telnet <master-node-ip> 6443
   ```

3. **检查令牌**:
   ```bash
   # 在主节点获取令牌
   cat /var/lib/rancher/k3s/server/node-token
   
   # 检查令牌配置
   cat /etc/rancher/k3s/config.yaml
   ```

**解决方案**:

- **重新生成令牌**:
  ```bash
  # 在主节点重新生成令牌
  systemctl stop k3s
  rm /var/lib/rancher/k3s/server/node-token
  systemctl start k3s
  ```

- **配置正确的加入参数**:
  ```bash
  # 在工作节点配置
  curl -sfL https://get.k3s.io | K3S_URL=https://<master-ip>:6443 K3S_TOKEN=<token> sh -
  ```

## 常见错误代码

### K3s 错误代码

| 错误代码 | 描述 | 解决方案 |
|----------|------|----------|
| `exit code 1` | 一般性错误 | 查看详细日志 |
| `exit code 125` | 容器运行时错误 | 检查容器配置 |
| `exit code 126` | 权限错误 | 检查文件权限 |
| `exit code 127` | 命令未找到 | 检查 PATH 环境变量 |

### 网络错误

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| `connection refused` | 服务未启动 | 启动相关服务 |
| `no route to host` | 网络不通 | 检查路由配置 |
| `timeout` | 网络延迟 | 增加超时时间 |

## 获取帮助

### 收集诊断信息

```bash
# 生成诊断报告
./scripts/system-diagnostics.sh --full > diagnostic-report.txt

# 收集日志
tar -czf logs.tar.gz logs/

# 导出配置
cp config/template.yaml config-backup.yaml
```

### 提交问题

在提交 Issue 时，请包含：

1. **系统信息**:
   - PVE 版本
   - 容器配置
   - 网络设置

2. **错误信息**:
   - 完整的错误日志
   - 相关的系统日志
   - 配置文件

3. **重现步骤**:
   - 详细的操作步骤
   - 预期结果
   - 实际结果

### 社区支持

- [GitHub Issues](../../issues) - 报告问题和获取帮助
- [GitHub Discussions](../../discussions) - 社区讨论
- [Wiki](../../wiki) - 详细文档和教程

## 预防措施

### 定期维护

```bash
# 创建维护脚本
cat > /etc/cron.daily/k3s-maintenance << 'EOF'
#!/bin/bash
# 清理日志
journalctl --vacuum-time=7d
# 清理镜像
k3s crictl rmi --prune
# 检查磁盘空间
df -h | grep -E '9[0-9]%|100%' && echo "Warning: Disk space low"
EOF

chmod +x /etc/cron.daily/k3s-maintenance
```

### 监控设置

```bash
# 设置基本监控
./scripts/monitoring.sh --enable
./scripts/k3s-health-check.sh --cron
```

### 备份策略

```bash
# 备份 K3s 配置
tar -czf k3s-backup-$(date +%Y%m%d).tar.gz /etc/rancher/k3s /var/lib/rancher/k3s/server/manifests

# 备份容器配置
pct backup 100 --compress gzip
```

通过遵循这些故障排查步骤和预防措施，您可以有效地诊断和解决大多数常见问题。如果问题仍然存在，请不要犹豫寻求社区帮助。