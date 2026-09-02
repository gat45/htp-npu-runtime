#!/system/bin/sh
# Hosts complet bind-monté : repos Termux + PyPI (DNS du téléphone ne les résout pas)
umount /system/etc/hosts 2>/dev/null
cp /system/etc/hosts /data/local/tmp/hosts
add() {
  host="$1"
  if ! grep -qw "$host" /data/local/tmp/hosts 2>/dev/null; then
    echo "$2 $host" >> /data/local/tmp/hosts
  fi
}
add packages.termux.dev 5.75.242.194
add packages-cf.termux.dev 188.114.97.2
add pypi.org 151.101.0.223
add files.pythonhosted.org 151.101.0.223
mount --bind /data/local/tmp/hosts /system/etc/hosts
echo "=== hosts après bind ==="
cat /system/etc/hosts
