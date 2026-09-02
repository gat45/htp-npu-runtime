#!/system/bin/sh
# ============================================================================
# claude_local_boot.sh — Auto-launch Claude Local (server + app) au boot
#
# Placé dans /data/adb/service.d/ (Magisk) → exécuté à chaque démarrage
# avec les droits root. Le serveur tourne en background, l'app est lancée
# après un délai pour laisser le système se stabiliser.
#
# Install : sh /data/local/tmp/claude_local_boot.sh install
# Uninstall : sh /data/local/tmp/claude_local_boot.sh uninstall
# Test : sh /data/local/tmp/claude_local_boot.sh start
# Stop : sh /data/local/tmp/claude_local_boot.sh stop
# ============================================================================

HARNESS="/data/local/tmp/harness"
SERVER_PID_FILE="/data/local/tmp/claude_server.pid"
LOG="/data/local/tmp/claude_local_boot.log"
PYTHON="/data/data/com.termux/files/usr/bin/python3"
HOST="0.0.0.0"
PORT="8765"
BOOT_DELAY=15  # secondes avant de lancer le serveur (laisser le système se stabiliser)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

stop_server() {
    if [ -f "$SERVER_PID_FILE" ]; then
        PID=$(cat "$SERVER_PID_FILE")
        kill "$PID" 2>/dev/null
        rm -f "$SERVER_PID_FILE"
        log "Serveur arrêté (PID $PID)"
    fi
    # Kill any remaining server processes
    killall python3 2>/dev/null
    sleep 1
}

start_server() {
    stop_server

    log "Démarrage du serveur Claude Local..."
    log "  HARNESS: $HARNESS"
    log "  Backend: JZ (ngl=99, MBUF=3200)"

    cd "$HARNESS" || { log "ERREUR: $HARNESS introuvable"; exit 1; }

    # Environnement JZ (PAS de gxlibs)
    export LD_LIBRARY_PATH="$HARNESS/../jz/lib:$HARNESS/../jz/bin:/vendor/lib64:/data/data/com.termux/files/usr/lib"
    export ADSP_LIBRARY_PATH="/data/local/tmp"
    export CDSP_LIBRARY_PATH="/data/local/tmp"
    export GGML_HEXAGON_NDEV=1
    export GGML_HEXAGON_OPBATCH=1024
    export GGML_HEXAGON_OPQUEUE=16
    export GGML_HEXAGON_MBUF=3200

    # Lancer le serveur en background
    "$PYTHON" server.py --host "$HOST" --port "$PORT" >> "$LOG" 2>&1 &
    echo $! > "$SERVER_PID_FILE"
    log "Serveur lancé (PID $(cat $SERVER_PID_FILE))"

    # Attendre que le serveur soit prêt
    for i in $(seq 1 30); do
        if curl -sf "http://127.0.0.1:$PORT/health" > /dev/null 2>&1; then
            log "Serveur prêt sur http://127.0.0.1:$PORT"
            return 0
        fi
        sleep 1
    done

    log "ATTENTION: serveur non prêt après 30s"
    return 1
}

start_app() {
    log "Lancement de l'app Claude Local..."
    am start -n com.local.claudeweb/.MainActivity 2>> "$LOG"
    log "App lancée"
}

install() {
    log "=== Installation du script de boot ==="

    # Créer le dossier Magisk service.d s'il n'existe pas
    mkdir -p /data/adb/service.d

    # Copier ce script dans service.d
    cp "$0" /data/adb/service.d/claude_local_boot.sh
    chmod 755 /data/adb/service.d/claude_local_boot.sh

    log "Script installé dans /data/adb/service.d/claude_local_boot.sh"
    log "Il sera exécuté automatiquement à chaque boot"
    log ""
    log "Pour tester maintenant: sh $0 start"
    log "Pour désinstaller: sh $0 uninstall"
}

uninstall() {
    log "=== Désinstallation ==="
    rm -f /data/adb/service.d/claude_local_boot.sh
    stop_server
    log "Script supprimé de /data/adb/service.d/"
    log "Le serveur ne démarrera plus automatiquement au boot"
}

start() {
    log "=== Démarrage manuel ==="
    start_server
    sleep 2
    start_app
    log "=== Prêt ==="
    log "  UI: http://127.0.0.1:$PORT"
    log "  App: Claude Local"
    log "  Backend: JZ (MBUF=3200)"
}

# --- Point d'entrée Magisk (service.d) ---
# Quand Magisk exécute ce script au boot, il lance le serveur + app
# avec un délai pour laisser le système se stabiliser.

case "${1:-boot}" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    start)
        start
        ;;
    stop)
        stop_server
        ;;
    boot)
        # Mode Magisk service.d : délai puis démarrage
        sleep "$BOOT_DELAY"
        start_server
        sleep 3
        start_app
        ;;
    *)
        echo "Usage: $0 {install|uninstall|start|stop|boot}"
        echo "  install   - Installer le script de boot (Magisk service.d)"
        echo "  uninstall - Supprimer le script de boot"
        echo "  start     - Démarrer le serveur + app maintenant"
        echo "  stop      - Arrêter le serveur"
        echo "  boot      - Mode Magisk (auto au boot)"
        ;;
esac
