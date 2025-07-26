# Release Process Guide

## Overview

This document describes the release process for the PVE LXC K3s Template project. The project uses GitHub Actions for automated building and publishing of releases to GitHub Releases.

## Release Workflow

### Automated Release (Recommended)

The project includes comprehensive GitHub Actions workflows that automatically handle the entire release process:

1. **Tag-based Release**: Push a version tag to trigger automatic build and release
2. **Manual Workflow**: Use GitHub Actions workflow dispatch for manual releases
3. **Automated Publishing**: Artifacts are automatically published to GitHub Releases

### Manual Release (Alternative)

For local testing or when GitHub Actions is not available, manual release tools are provided.

## Automated Release Process

### 1. Tag-based Release (Recommended)

This is the simplest and most reliable method:

```bash
# Create and push a version tag
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

The GitHub Actions workflow will automatically:
- Build the template
- Run tests
- Generate checksums
- Create GitHub Release
- Upload artifacts
- Publish to container registry

### 2. Using the Release Trigger Script

The project includes a helper script for managing releases:

```bash
# Create tag and trigger release
scripts/trigger-release.sh create-tag v1.0.0

# Create pre-release
scripts/trigger-release.sh create-tag v1.0.0-beta --prerelease

# Manual workflow dispatch
scripts/trigger-release.sh dispatch v1.0.0

# Check workflow status
scripts/trigger-release.sh status

# List all releases
scripts/trigger-release.sh list-releases
```

### 3. GitHub Web Interface

You can also trigger releases through the GitHub web interface:

1. Go to **Actions** tab in your repository
2. Select **Publish Artifacts to Release** workflow
3. Click **Run workflow**
4. Enter the version tag and options
5. Click **Run workflow**

## Manual Release Process

### Prerequisites

For manual releases, ensure you have:

- Build environment set up (see [Development Guide](development.md))
- GitHub CLI (`gh`) installed and authenticated
- Proper permissions to create releases

### Using Make Targets

The project includes convenient Make targets for releases:

```bash
# Build release artifacts
make release-build

# Package release files
make release-package

# Create complete release (interactive)
make release-create

# Upload to GitHub Releases (interactive)
make release-upload

# Create pre-release (interactive)
make release-prerelease

# Create draft release (interactive)
make release-draft
```

### Using Release Scripts Directly

For more control, use the release scripts directly:

```bash
# Build artifacts
scripts/create-release.sh build

# Package release
scripts/create-release.sh package v1.0.0

# Create complete release
scripts/create-release.sh create v1.0.0

# Upload to GitHub
scripts/create-release.sh upload v1.0.0 \
  --github-repo owner/repo \
  --github-token ghp_xxx

# Create pre-release
scripts/create-release.sh create v1.0.0-beta --prerelease

# Create draft release
scripts/create-release.sh create v1.0.0 --draft
```

## Version Numbering

The project follows [Semantic Versioning](https://semver.org/):

### Version Format

- **Stable Release**: `v1.0.0`, `v1.2.3`
- **Pre-release**: `v1.0.0-alpha`, `v1.0.0-beta`, `v1.0.0-rc1`
- **Development**: `v1.0.0-dev`, `v1.0.0-snapshot`

### Version Components

- **Major** (X): Breaking changes, incompatible API changes
- **Minor** (Y): New features, backward compatible
- **Patch** (Z): Bug fixes, backward compatible

### Examples

```bash
# Major release (breaking changes)
v1.0.0 → v2.0.0

# Minor release (new features)
v1.0.0 → v1.1.0

# Patch release (bug fixes)
v1.0.0 → v1.0.1

# Pre-release versions
v1.0.0-alpha    # Alpha version
v1.0.0-beta     # Beta version
v1.0.0-rc1      # Release candidate
```

## Release Checklist

### Pre-Release

- [ ] Update version in `config/template.yaml`
- [ ] Update documentation with new version references
- [ ] Run full test suite: `make test`
- [ ] Test build process: `make build`
- [ ] Review and update `CHANGELOG.md`
- [ ] Ensure all issues for the milestone are closed

### Release

- [ ] Create and push version tag
- [ ] Verify GitHub Actions workflow completes successfully
- [ ] Check that release is created on GitHub
- [ ] Verify all artifacts are uploaded correctly
- [ ] Test download and installation of release artifacts

### Post-Release

- [ ] Verify release assets are accessible
- [ ] Test template deployment in PVE environment
- [ ] Update any dependent projects or documentation
- [ ] Announce release (if needed)
- [ ] Close release milestone
- [ ] Create next milestone (if applicable)

## GitHub Actions Workflows

### Build Template Workflow

**File**: `.github/workflows/build-template.yml`

**Triggers**:
- Push to `main` or `develop` branches
- Pull requests to `main`
- Version tags (`v*`)
- Manual workflow dispatch

**Jobs**:
1. **Validate Configuration** - Validates config files
2. **Code Quality** - Runs shellcheck and other quality checks
3. **Unit Tests** - Runs unit test suite
4. **Build Template** - Builds the LXC template
5. **Integration Tests** - Runs integration tests
6. **Security Scan** - Scans for vulnerabilities
7. **Release** - Creates GitHub Release (for tags only)

### Publish Artifacts Workflow

**File**: `.github/workflows/publish-artifacts.yml`

**Triggers**:
- Version tags (`v*`)
- Manual workflow dispatch

**Jobs**:
1. **Build Artifacts** - Builds release artifacts
2. **Create Release** - Creates GitHub Release
3. **Publish Container** - Publishes to container registry
4. **Notify Success** - Creates success notifications

### Release Workflow

**File**: `.github/workflows/release.yml`

**Triggers**:
- Release published
- Manual workflow dispatch

**Jobs**:
1. **Validate Release** - Validates release information
2. **Build Release** - Builds release artifacts
3. **Publish GitHub Release** - Publishes to GitHub
4. **Update Release Assets** - Updates existing releases
5. **Publish Container Registry** - Publishes to container registry
6. **Update Documentation** - Updates version references
7. **Post-Release** - Post-release tasks and notifications

## Release Artifacts

Each release includes the following artifacts:

### Template Files

- **`alpine-k3s-{version}.tar.gz`** - Main LXC template file
- **`alpine-k3s-{version}.tar.gz.sha256`** - SHA256 checksum
- **`alpine-k3s-{version}.tar.gz.sha512`** - SHA512 checksum
- **`alpine-k3s-{version}.tar.gz.md5`** - MD5 checksum

### Documentation

- **Release Notes** - Comprehensive release information
- **Installation Instructions** - Step-by-step installation guide
- **Changelog** - List of changes since previous version
- **Technical Details** - Build information and specifications

### Container Image

- **GitHub Container Registry**: `ghcr.io/owner/repo:version`
- **Tags**: `latest`, `v1.0.0`, `1.0`, `1`

## Security Considerations

### Release Security

- All releases are signed and include checksums
- GitHub Actions uses secure secrets management
- Container images are scanned for vulnerabilities
- Release artifacts are immutable once published

### Access Control

- Only maintainers can create releases
- GitHub Actions requires appropriate permissions
- Release workflows use least-privilege principles
- Sensitive operations require manual approval

## Troubleshooting

### Common Issues

#### Build Failures

```bash
# Check build logs
gh run list --workflow="build-template.yml"
gh run view <run-id> --log

# Test build locally
make build
make test
```

#### Release Upload Failures

```bash
# Check GitHub CLI authentication
gh auth status

# Verify repository permissions
gh repo view

# Check release workflow logs
gh run list --workflow="publish-artifacts.yml"
```

#### Version Tag Issues

```bash
# List existing tags
git tag -l

# Delete local tag
git tag -d v1.0.0

# Delete remote tag
git push origin :refs/tags/v1.0.0

# Recreate tag
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### Debug Mode

Enable debug mode for detailed logging:

```bash
# GitHub Actions
# Set DEBUG=true in workflow inputs

# Local scripts
export DEBUG=true
export LOG_LEVEL=DEBUG
scripts/create-release.sh build
```

### Manual Recovery

If automated release fails, you can recover manually:

```bash
# Build artifacts locally
make release-build

# Upload to existing release
gh release upload v1.0.0 output/*.tar.gz output/*.sha256

# Create release manually
gh release create v1.0.0 output/*.tar.gz \
  --title "PVE LXC K3s Template v1.0.0" \
  --notes-file release-notes.md
```

## Best Practices

### Release Planning

1. **Plan releases** around milestones and feature completion
2. **Test thoroughly** before creating releases
3. **Document changes** in changelog and release notes
4. **Coordinate timing** with dependent projects
5. **Communicate** releases to users and stakeholders

### Version Management

1. **Follow semantic versioning** strictly
2. **Use pre-releases** for testing and feedback
3. **Tag consistently** with proper messages
4. **Maintain changelog** with each release
5. **Archive old versions** appropriately

### Quality Assurance

1. **Run full test suite** before releases
2. **Verify artifacts** after upload
3. **Test installation** in clean environment
4. **Monitor feedback** after release
5. **Address issues** promptly

## Integration with CI/CD

### GitHub Actions Integration

The release process is fully integrated with GitHub Actions:

- **Automated Testing** - All tests run before release
- **Security Scanning** - Vulnerabilities are detected
- **Quality Gates** - Releases blocked if quality checks fail
- **Notifications** - Team notified of release status
- **Rollback** - Failed releases can be rolled back

### External Integrations

The release process can integrate with:

- **Slack/Discord** - Release notifications
- **Jira/GitHub Issues** - Automatic issue closure
- **Documentation Sites** - Automatic doc updates
- **Package Registries** - Multi-registry publishing
- **Monitoring Systems** - Release tracking

## Conclusion

The PVE LXC K3s Template project provides a comprehensive, automated release process that ensures consistent, high-quality releases. The combination of GitHub Actions workflows and manual tools provides flexibility for different release scenarios while maintaining security and reliability.

For questions or issues with the release process, please:

1. Check this documentation
2. Review GitHub Actions logs
3. Test with manual tools
4. Create an issue if problems persist

The release process is continuously improved based on feedback and experience. Contributions to improve the release workflow are welcome!