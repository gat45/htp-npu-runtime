#!/system/bin/sh
# Crée un hosts modifié dans /data/local/tmp et le bind-mount sur /system/etc/hosts
cp /system/etc/hosts /data/local/tmp/hosts
if ! grep -q "packages.termux.dev" /data/local/tmp/hosts 2>/dev/null; then
  echo "5.75.242.194 packages.termux.dev" >> /data/local/tmp/hosts
  echo "188.114.97.2 packages-cf.termux.dev" >> /data/local/tmp/hosts
fi
mount --bind /data/local/tmp/hosts /system/etc/hosts 2>&1
echo "=== hosts après bind ==="
cat /system/etc/hosts
