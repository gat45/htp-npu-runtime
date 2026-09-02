#!/system/bin/sh
# switch_model.sh {npu|9b|9b-dark|05b}
# Bascule l'agent opencode entre les modèles LOCAUX déjà présents sur le téléphone.
#   npu      -> Qwen3-4B QAIRT (NPU, rapide, défaut) — arrête llama-server CPU
#   9b       -> Qwen3.5 9B Q4_0 (officiel, CPU)
#   9b-dark  -> Qwen3.5 9B Q4_K_M « Dark Roast » (uncensored, CPU)
#   05b      -> Qwen2.5 0.5B Instruct (CPU, très rapide, test)
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin
CFG=/data/local/tmp/oc-home/.config/opencode/opencode.json

case "${1:-npu}" in
  npu)     MODEL="qairt/qwen3-4b-npu";        GGUF=""; NEED_GB=2 ;;
  9b)      MODEL="llamacpp/qwen3.5-9b";       GGUF="/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf"; NEED_GB=7 ;;
  9b-dark) MODEL="llamacpp/qwen3.5-9b-dark";  GGUF="/data/local/tmp/qwen3.5-9b-pocketpal/qwen3.5-9b-pocketpal.Q4_K_M.gguf"; NEED_GB=7 ;;
  05b)     MODEL="llamacpp/qwen2.5-05b";      GGUF="/data/local/tmp/qwen05b.gguf"; NEED_GB=1 ;;
  *) echo "usage: switch_model.sh {npu|9b|9b-dark|05b}"; exit 1 ;;
esac

# Garde-fou RAM : refuse de charger un gros modèle si la mémoire libre est insuffisante
# (MemAvailable en kB -> Go, arithmétique entière). Évite le kill LOWMEM_WATCHER OnePlus.
avail_gb=$(cat /proc/meminfo 2>/dev/null | grep MemAvailable | awk '{print $2}')
if [ -n "$avail_gb" ]; then
  avail_gb=$((avail_gb / 1048576))
  echo "=== RAM libre : ${avail_gb} Go (besoin ≈${NEED_GB} Go) ==="
  if [ "$avail_gb" -lt "$NEED_GB" ]; then
    echo "RAM INSUFFISANTE (${avail_gb} Go libres < ${NEED_GB} Go requis) : bascule annulée. Ferme d'autres apps puis réessaie."
    exit 2
  fi
fi

echo "=== modèle sélectionné : $MODEL ==="

# Mémorise le modèle choisi pour que start_all.sh le reprenne après un reboot
# (écrit APRÈS le garde-fou RAM : le state ne doit refléter que le modèle réellement actif).
echo "${1:-npu}" > /data/local/tmp/oc-model.state

# 1. llama-server CPU
pkill -f llama-server 2>/dev/null
# Attendre que le port 8080 soit réellement libéré (le pkill est asynchrone ; sans
# cette attente le nouveau llama-server échoue avec "couldn't bind HTTP server socket").
i=0
while [ $i -lt 15 ]; do
  if ! (ss -tln 2>/dev/null | grep -q ':8080' || netstat -tln 2>/dev/null | grep -q ':8080'); then
    break
  fi
  i=$((i + 1))
  sleep 1
done
if [ -n "$GGUF" ]; then
  # -c 8192 : opencode envoie un prompt système d'environ 7800 tokens (agent + outils) ;
  # un contexte de 2048 le fait rejeter (request exceeds context size). 8192 couvre le
  # prompt agent complet avec de la marge pour la réponse.
  # -np 1 : un seul slot → le KV cache n'est PAS multiplié par 4 (défaut n_slots=4 = 32K
  # tokens de KV ≈ plusieurs Go) → sans ça le OOM killer tue llama-server + opencode.
  nohup /data/local/tmp/llama-server -m "$GGUF" --host 127.0.0.1 --port 8080 \
    -c 8192 -np 1 -t 8 --no-webui > /data/local/tmp/llama-server.log 2>&1 &
  echo "llama-server démarré : $GGUF (pid $!)"
else
  echo "llama-server arrêté (modèle NPU, pas de CPU)"
fi

# 2. Réécrire opencode.json (modèle par défaut + tous les modèles enregistrés)
mkdir -p /data/local/tmp/oc-home/.config/opencode
cat > "$CFG" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "$MODEL",
  "provider": {
    "qairt": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Qwen3-4B NPU (QAIRT GenieX)",
      "options": { "baseURL": "http://127.0.0.1:8933/v1", "apiKey": "local" },
      "models": {
        "qwen3-4b-npu": { "name": "Qwen3-4B NPU QAIRT" },
        "qwen3-4b-npu-12k": { "name": "Qwen3-4B Genie 12K NPU (SM8750)" },
        "qwen3-8b-npu": { "name": "Qwen3-8B NPU QAIRT" }
      }
    },
    "llamacpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama.cpp local (CPU)",
      "options": { "baseURL": "http://127.0.0.1:8080/v1", "apiKey": "local" },
      "models": {
        "qwen3.5-9b": { "name": "Qwen3.5 9B Q4_0 (officiel)" },
        "qwen3.5-9b-dark": { "name": "Qwen3.5 9B Q4_K_M Dark Roast (uncensored)" },
        "qwen2.5-05b": { "name": "Qwen2.5 0.5B Instruct (rapide)" }
      }
    }
  }
}
EOF

# 3. Redémarrer opencode serve
pkill -f "opencode serve" 2>/dev/null
sleep 1
export HOME=/data/local/tmp/oc-home
nohup /data/data/com.termux/files/usr/bin/glibc-runner /data/local/tmp/oc/opencode serve \
  --port 4096 --hostname 127.0.0.1 > /data/local/tmp/opencode-serve.log 2>&1 &
echo "opencode redémarré (pid $!)"
sleep 6

# 4. Vérification
echo "=== opencode health ==="
curl -s http://127.0.0.1:4096/global/health; echo ""
if [ -n "$GGUF" ]; then
  echo "=== llama-server health ==="
  curl -s http://127.0.0.1:8080/health; echo ""
fi
echo "=== fin ==="
