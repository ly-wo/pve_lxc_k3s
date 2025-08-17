# System Testing Guide

## Overview

This document describes the system testing environment for the PVE LXC K3s Template project. The system tests validate the complete deployment and functionality of K3s templates in Proxmox VE environments.

## Test Architecture

### Test Levels

1. **Unit Tests** - Test individual script functions and components
2. **Integration Tests** - Test component interactions and workflows
3. **System Tests** - Test complete deployment in PVE environment

### System Test Components

- **PVE Environment Setup** - Validates PVE infrastructure
- **Template Deployment** - Tests template creation and deployment
- **K3s Functionality** - Verifies K3s cluster operations
- **Network Connectivity** - Tests cluster networking
- **Performance Benchmarks** - Measures system performance
- **Compatibility Tests** - Validates cross-version compatibility

## Running System Tests

### Prerequisites

For real PVE environment testing:
- Proxmox VE 7.4+ or 8.0+
- Access to PVE node with `pct` and `pvesm` commands
- Available storage (local-lvm, local-zfs, etc.)
- Network bridge configured (vmbr0)

For mock testing (development):
- No special requirements - uses simulated PVE environment

### Test Execution

#### Run All System Tests
```bash
# Real PVE environment
make test-system

# Mock environment (for development)
make test-system-mock
```

#### Run Individual Test Components
```bash
# Using the system test runner
tests/run-system-tests.sh --help

# Run with specific options
tests/run-system-tests.sh --mock --verbose

# Run with custom PVE configuration
tests/run-system-tests.sh --pve-node pve1 --storage local-zfs
```

#### Run BATS System Tests
```bash
# Run BATS-based system tests
bats tests/test-system-environment.bats

# Run specific test
bats tests/test-system-environment.bats -f "PVE environment"
```

## Test Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PVE_NODE` | PVE node name | `pve-test-node` |
| `PVE_STORAGE` | Storage name | `local-lvm` |
| `NETWORK_BRIDGE` | Network bridge | `vmbr0` |
| `CONTAINER_ID_START` | Starting container ID | `9000` |
| `MEMORY_MB` | Container memory | `2048` |
| `CPU_CORES` | Container CPU cores | `2` |
| `DISK_SIZE_GB` | Container disk size | `20` |

### Test Configuration File

System tests use a YAML configuration file:

```yaml
template:
  name: "system-test-alpine-k3s"
  version: "1.0.0-system"
  description: "System test K3s template"

k3s:
  version: "v1.28.4+k3s1"
  install_options:
    - "--disable=traefik"
    - "--disable=servicelb"
  cluster_init: true

system:
  timezone: "UTC"
  packages:
    - curl
    - wget
    - ca-certificates

security:
  disable_root_login: true
  create_k3s_user: true
  firewall_rules:
    - "6443/tcp"
    - "10250/tcp"

pve:
  test_node: "pve-test-node"
  storage: "local-lvm"
  network_bridge: "vmbr0"
  container_id_start: 9000
  memory_mb: 2048
  cpu_cores: 2
  disk_size_gb: 20

performance:
  startup_timeout: 300
  api_ready_timeout: 180
  pod_ready_timeout: 120
```

## Test Scenarios

### 1. PVE Environment Validation

Tests PVE infrastructure readiness:
- PVE commands availability (`pct`, `pvesm`)
- Node connectivity
- Storage availability
- Network bridge configuration

### 2. Template Deployment

Tests template deployment process:
- Template upload to PVE storage
- Container creation from template
- Container startup and initialization
- Service availability verification

### 3. K3s Functionality

Validates K3s cluster operations:
- K3s ervice status
- API server health
- Node readiness
- System pods status
- Cluster information

### 4. Network Connectivity

Tests cluster networking:
- External connectivity
- Cluster DNS resolution
- Pod-to-pod communication
- Service discovery
- Network policies

### 5. Multi-node Cluster

Tests cluster scaling:
- Master node configuration
- Worker node joining
- Cluster token management
- Node discovery
- Workload distribution

### 6. Performance Benchmarks

Measures system performance:
- Container startup time
- API response time
- Resource usage (CPU, memory, disk)
- Pod creation time
- Network latency

### 7. Compatibility Tests

Validates cross-version compatibility:
- Alpine Linux versions
- K3s ersions
- PVE versions
- Container configurations
- Network configurations

## Mock Testing Environment

For development and CI/CD, the system tests can run in mock mode:

### Mock Components

- **Mock PVE Commands** - Simulated `pct` and `pvesm` commands
- **Mock Containers** - Simulated container lifecycle
- **Mock K3s** - Simulated K3s responses
- **Mock Network** - Simulated network connectivity

### Mock Mode Benefits

- No PVE infrastructure required
- Fast execution
- Consistent results
- CI/CD friendly
- Safe for development

## Deployment Automation

### PVE Deployment Script

The system includes automated deployment capabilities:

```bash
# Deploy single-node cluster
scripts/pve-deployment-automation.sh single-node template.tar.gz

# Deploy multi-node cluster
scripts/pve-deployment-automation.sh multi-node template.tar.gz \
  --master-count 3 --worker-count 5

# Check deployment status
scripts/pve-deployment-automation.sh status

# Clean up deployments
scripts/pve-deployment-automation.sh cleanup
```

### Deployment Features

- **Automated Template Upload** - Uploads templates to PVE storage
- **Container Creation** - Creates LXC containers with proper configuration
- **Cluster Configuration** - Configures multi-node K3s clusters
- **Health Monitoring** - Monitors deployment health
- **Cleanup Management** - Manages deployment lifecycle

## Performance Metrics

### Startup Performance

- **Container Startup**: < 300 seconds
- **K3s Ready**: < 180 seconds
- **API Available**: < 5 seconds
- **Pods Ready**: < 120 seconds

### Resource Usage

- **Memory Usage**: < 1.5GB for basic setup
- **CPU Usage**: < 50% average
- **Disk Usage**: < 5GB for base system
- **Network Latency**: < 10ms cluster internal

### Scalability

- **Single Node**: 1-100 pods
- **Multi-node**: 3-1000 pods
- **Cluster Size**: 1-10 nodes
- **Storage**: 20GB-1TB per node

## Troubleshooting

### Common Issues

#### PVE Connection Issues
```bash
# Check PVE node connectivity
pvesh get /nodes/pve-node/status

# Verify storage availability
pvesm status

# Check network bridge
ip link show vmbr0
```

#### Container Creation Issues
```bash
# Check available container IDs
pct list

# Verify storage space
pvesm list local-lvm

# Check template availability
pvesm list local | grep vztmpl
```

#### K3s Issues
```bash
# Check K3s ervice status
pct exec 9000 -- systemctl status k3s

# Check K3s logs
pct exec 9000 -- journalctl -u k3s -f

# Verify API health
pct exec 9000 -- curl -k https://localhost:6443/healthz
```

### Debug Mode

Enable debug logging:
```bash
export DEBUG=true
export LOG_LEVEL=DEBUG
tests/run-system-tests.sh --verbose
```

### Log Files

System test logs are stored in:
- `logs/system-test-report.md` - Test report
- `logs/pve-deployment.log` - Deployment log
- `.system-test/logs/` - Detailed test logs

## CI/CD Integration

### GitHub Actions

System tests can be integrated into CI/CD pipelines:

```yaml
name: System Tests
on: [push, pull_request]

jobs:
  system-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run System Tests
        run: make test-system-mock
      - name: Upload Test Reports
        uses: actions/upload-artifact@v3
        with:
          name: system-test-reports
          path: logs/
```

### Test Reports

System tests generate comprehensive reports:
- Test execution summary
- Performance metrics
- Compatibility matrix
- Failure analysis
- Recommendations

## Best Practices

### Test Development

1. **Use Mock Mode** for development and CI/CD
2. **Test Real Environment** before production deployment
3. **Monitor Performance** metrics over time
4. **Validate Compatibility** across supported versions
5. **Document Issues** and resolutions

### Production Deployment

1. **Run Full Test Suite** before deployment
2. **Validate Performance** meets requirements
3. **Test Backup/Recovery** procedures
4. **Monitor Resource Usage** in production
5. **Plan Capacity** based on test results

### Maintenance

1. **Update Test Cases** with new features
2. **Refresh Mock Data** regularly
3. **Review Performance** baselines
4. **Update Documentation** with changes
5. **Archive Test Results** for analysis

## Future Enhancements

### Planned Features

- **Automated Performance Regression Testing**
- **Cross-Platform Compatibility Testing**
- **Security Vulnerability Scanning**
- **Load Testing Framework**
- **Disaster Recovery Testing**

### Integration Opportunities

- **Monitoring Integration** (Prometheus, Grafana)
- **Alerting Integration** (Slack, Email)
- **Reporting Integration** (Confluence, Jira)
- **Deployment Integration** (Ansible, Terraform)
- **Security Integration** (Vault, RBAC)

## Conclusion

The system testing framework provides comprehensive validation of the PVE LXC K3s Template project. It ensures reliable deployment, optimal performance, and broad compatibility across supported environments.

For questions or issues, please refer to the troubleshooting section or create an issue in the project repository.