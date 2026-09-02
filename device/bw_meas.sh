#!/system/bin/sh
# Mesure de bande passante indirecte : compteurs /proc/<pid>/io + chrono
# autour d'une inférence QAIRT (pont 127.0.0.1:8933).
# Usage : su -c 'sh /data/local/tmp/bw_meas.sh <pid_app>'
PID="$1"
if [ -z "$PID" ]; then echo "usage: $0 <pid>"; exit 1; fi

snapshot() {
  grep -E '^(rchar|wchar|read_bytes|write_bytes|cancelled_write_bytes)' /proc/$PID/io 2>/dev/null
}

echo "=== AVANT inference (idle) ==="
snapshot
T0=$(date +%s%3N)

echo "=== inference QAIRT (7*8=?) ==="
curl -s -m 60 -X POST http://127.0.0.1:8933/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-4b-npu","messages":[{"role":"user","content":"7*8=? reponds juste le nombre"}],"max_tokens":8,"stream":false}' \
  | head -c 200
echo

T1=$(date +%s%3N)
echo "=== APRES inference ==="
snapshot
echo "duree: $((T1 - T0)) ms"
