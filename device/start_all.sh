#!/system/bin/sh
# start_all.sh — relance TOUT le stack local après un reboot, en une commande.
#
#   sh /data/local/tmp/start_all.sh [npu|9b|9b-dark|05b]
#
# Sans argument : reprend le dernier modèle choisi (état mémorisé par switch_model.sh,
# fichier /data/local/tmp/oc-model.state). Défaut si rien : npu (Qwen3-4B NPU).
#
# Ce que fait le script :
#   1. re-bind du /etc/hosts (DNS, perdu au reboot) si besoin
#   2. démarre llama-server si le modèle actif est CPU (9B Q4_0 / 9B Q4_K_M / 0.5B)
#   3. démarre opencode serve (127.0.0.1:4096)
#   4. lance l'app « OpenCode Root » (pont NPU qairt sur 127.0.0.1:8933)
#   5. vérifie la santé de chaque brique (log dans /data/local/tmp/start-all.log)
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin
export HOME=/data/local/tmp/oc-home
LOG=/data/local/tmp/start-all.log

log() { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }

log "================= START_ALL ================="

# 1. DNS : le bind-mount hosts est perdu au reboot — on le refait si besoin
if ! grep -q packages.termux.dev /system/etc/hosts 2>/dev/null; then
  log "fix DNS (bind-mount hosts)"
  sh /data/local/tmp/fix_dns.sh >> "$LOG" 2>&1
else
  log "DNS déjà en place"
fi

# 2. Modèle actif : argument explicite sinon état mémorisé
MODEL="${1:-$(cat /data/local/tmp/oc-model.state 2>/dev/null || echo npu)}"
log "modèle actif : $MODEL"

# 3. llama-server (seulement si le modèle actif est un GGUF CPU)
GGUF=""
case "$MODEL" in
  9b)      GGUF=/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf ;;
  9b-dark) GGUF=/data/local/tmp/qwen3.5-9b-pocketpal/qwen3.5-9b-pocketpal.Q4_K_M.gguf ;;
  05b)     GGUF=/data/local/tmp/qwen05b.gguf ;;
  npu)     GGUF="" ;;
  *)       log "modèle inconnu ($MODEL) — on repart sur npu"; GGUF="" ;;
esac
pkill -f llama-server 2>/dev/null
sleep 1
if [ -n "$GGUF" ]; then
  nohup /data/local/tmp/llama-server -m "$GGUF" --host 127.0.0.1 --port 8080 \
    -c 2048 -t 8 --no-webui > /data/local/tmp/llama-server.log 2>&1 &
  log "llama-server démarré : $GGUF (pid $!)"
else
  log "llama-server non requis (modèle $MODEL)"
fi

# 4. opencode serve
pkill -f "opencode serve" 2>/dev/null
sleep 1
nohup /data/data/com.termux/files/usr/bin/glibc-runner /data/local/tmp/oc/opencode serve \
  --port 4096 --hostname 127.0.0.1 > /data/local/tmp/opencode-serve.log 2>&1 &
log "opencode serve démarré (pid $!)"

# 5. App « OpenCode Root » : pont NPU qairt (127.0.0.1:8933) dans le process de l'app
am start -n com.op15.opencoderoot/ai.opencode.mobile.MainActivity >/dev/null 2>&1
log "app lancée (pont NPU)"

# 6. Vérifications
sleep 8
log "opencode health : $(curl -s http://127.0.0.1:4096/global/health)"
if [ -n "$GGUF" ]; then
  log "attente chargement du modèle (9B ~10-30 s)…"
  for i in 1 2 3 4 5 6; do
    sleep 5
    H=$(curl -s http://127.0.0.1:8080/health)
    if echo "$H" | grep -q '"ok"'; then
      log "llama health : $H"
      break
    fi
  done
fi
log "================= START_ALL TERMINÉ ================="
