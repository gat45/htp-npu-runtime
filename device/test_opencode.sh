#!/system/bin/sh
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin
export HOME=/data/local/tmp/oc-home
mkdir -p "$HOME" /data/local/tmp/oc
[ -f /data/local/tmp/opencode ] && mv /data/local/tmp/opencode /data/local/tmp/oc/opencode
chmod +x /data/local/tmp/oc/opencode
echo "=== opencode --version ==="
/data/data/com.termux/files/usr/bin/glibc-runner /data/local/tmp/oc/opencode --version 2>&1 | head -20
echo "=== EXIT ==="
