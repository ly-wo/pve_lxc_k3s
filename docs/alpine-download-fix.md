# Alpine Image Download Fix

## 🔍 Problem Identified
The Alpine image download was failing with 404 errors due to incorrect URL format and architecture naming:

```
curl: (22) The requested URL returned error: 404
Error: Alpine 镜像下载失败，已重试 3 次
```

## 🎯 Root Causes
1. **Incorrect Architecture Mapping**: Using `amd64` instead of Alpine's `x86_64`
2. **Incomplete Version Numbers**: Using `3.18` instead of full version like `3.18.12`
3. **Wrong URL Structure**: Not following Alpine's actual download URL pattern

## ✅ Solutions Applied

### 1. Architecture Mapping Function
```bash
get_alpine_arch() {
    local arch="$1"
    case "$arch" in
        "amd64") echo "x86_64" ;;
        "arm64") echo "aarch64" ;;
        "armv7") echo "armv7" ;;
        *) echo "$arch" ;;
    esac
}
```

### 2. Latest Version Detection
```bash
get_latest_alpine_version() {
    local major_minor="$1"  # e.g., "3.18"
    local arch="$2"
    local alpine_arch=$(get_alpine_arch "$arch")
    
    local base_url="https://dl-cdn.alpinelinux.org/alpine/v${major_minor}/releases/${alpine_arch}/"
    
    # Get latest patch version
    local latest_version=$(curl -s "$base_url" | \
        grep -o "alpine-minirootfs-${major_minor}\.[0-9]*-${alpine_arch}\.tar\.gz" | \
        sed "s/alpine-minirootfs-\(${major_minor}\.[0-9]*\)-${alpine_arch}\.tar\.gz/\1/" | \
        sort -V | tail -1)
    
    echo "${latest_version:-${major_minor}.0}"
}
```

### 3. Corrected URL Format
**Before (404 Error):**
```
https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/amd64/alpine-minirootfs-3.18-amd64.tar.gz
```

**After (Working):**
```
https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/x86_64/alpine-minirootfs-3.18.12-x86_64.tar.gz
```

### 4. Updated Download Function
- Automatically detects latest patch version for major.minor versions
- Maps architecture names correctly
- Uses proper Alpine URL structure
- Maintains retry logic and error handling

## 🧪 Validation Results

### URL Accessibility Test
```bash
✅ Latest Alpine  version: 3.18.12
✅ Alpine architecture for amd64: x86_64
✅ Download URL: https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/x86_64/alpine-minirootfs-3.18.12-x86_64.tar.gz
✅ URL is accessible
```

### HTTP Response Test
```bash
$ curl -I "https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/x86_64/alpine-minirootfs-3.18.12-x86_64.tar.gz"
HTTP/2 200 
content-type: application/octet-stream
content-length: 3294132
```

## 📋 Files Modified
- ✅ `scripts/base-image-manager.sh` - Fixed Alpine download logic
- ✅ Added architecture mapping function
- ✅ Added latest version detection
- ✅ Updated checksum URL generation
- ✅ Maintained backward compatibility

## 🚀 Impact
- ✅ Alpine images can now be downloaded successfully
- ✅ Automatic latest patch version detection
- ✅ Support for multiple architectures (amd64, arm64, armv7)
- ✅ Proper checksum validation
- ✅ Build process can proceed without 404 errors

## 🎯 Next Steps
The Alpine download issue is resolved. The build process should now be able to:
1. ✅ Download Alpine base images successfully
2. ✅ Validate checksums properly
3. ✅ Proceed with K3s installation
4. ✅ Generate LXC templates

The 404 errors should no longer occur, and the build process can continue normally.