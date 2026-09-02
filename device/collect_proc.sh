#!/system/bin/sh
# collect_proc.sh — dump structuré complet d'un processus pour comparaison
# Usage : su -c 'sh /data/local/tmp/collect_proc.sh <pid> <label>'
# Produit : /data/local/tmp/procdump_<label>/ avec maps, fd, fdinfo, cmdline, status
set -u
PID="$1"
LABEL="$2"
OUT=/data/local/tmp/procdump_$LABEL
mkdir -p "$OUT"

# cmdline
tr '\0' ' ' < /proc/$PID/cmdline > "$OUT/cmdline.txt" 2>/dev/null

# maps complet
cat /proc/$PID/maps > "$OUT/maps.txt" 2>/dev/null

# fd : liens symboliques (devices, fichiers, dmabuf, binder)
ls -l /proc/$PID/fd > "$OUT/fd.txt" 2>/dev/null

# fdinfo : taille des dma-buf par fd
for f in /proc/$PID/fdinfo/*; do
  fd=$(basename "$f")
  s=$(grep -E '^size:' "$f" 2>/dev/null | awk '{print $2}')
  if [ -n "$s" ]; then echo "fd=$fd size=$s"; fi
done > "$OUT/fdinfo_dmabuf.txt" 2>/dev/null

# binder transactions
grep -E 'binder' /proc/$PID/status 2>/dev/null > "$OUT/binder.txt" || true

# cgroup/uid pour contexte
grep -E '^(Uid|Gid)' /proc/$PID/status 2>/dev/null > "$OUT/status_uid.txt" || true

echo "[collect] $LABEL (pid $PID) -> $OUT"
wc -l "$OUT"/* 2>/dev/null | tail -1
