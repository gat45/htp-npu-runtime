#!/system/bin/sh
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin
export HOME=/data/local/tmp/oc-home
mkdir -p "$HOME/.config/opencode"

LOG=/data/local/tmp/opencode-serve.log
pkill -f "opencode serve" 2>/dev/null
sleep 1
nohup /data/data/com.termux/files/usr/bin/glibc-runner /data/local/tmp/oc/opencode serve --port 4096 --hostname 127.0.0.1 > "$LOG" 2>&1 &
echo "started pid $!"
