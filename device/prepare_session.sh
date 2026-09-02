#!/system/bin/sh
# ===========================================================================
# PREPARE SESSION — libère la RAM avant une grosse session d'inférence 9B.
#
# Fait (ordre) :
#   1. Tue les apps en arrière-plan (am kill-all + force-stop des gros)
#   2. Vide les caches (drop_caches si root, sinon best-effort)
#   3. Affiche la RAM avant/après (mémoire + swap + top RSS)
#
# Usage :  su -c 'sh /data/local/tmp/prepare_session.sh'
#          (ou depuis adb : adb shell su -c ...)
# ===========================================================================

echo "=== AVANT ==="
awk '/MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree/ {printf "%s = %.2f Go\n", $1, $2/1048576}' /proc/meminfo

echo ""
echo "[1/3] Fermeture des apps en arrière-plan..."
# Toutes les apps de l'utilisateur courant (sauf le système)
am kill-all 2>/dev/null
# Gros consommateurs typiques (à adapter) — force-stop pour libérer vraiment
for pkg in \
  com.android.chrome com.google.android.youtube com.google.android.apps.maps \
  com.google.android.gm com.oneplus.gallery com.oplus.gallery com.oplus.camera \
  com.facebook.katana com.instagram.android com.whatsapp com.tencent.mm \
  com.op15.toolkit.scout io.github.rabehx.securify com.pocketpalai; do
  pm path "$pkg" >/dev/null 2>&1 && { am force-stop "$pkg" 2>/dev/null && echo "  fermé: $pkg"; }
done

echo ""
echo "[2/3] Vidage des caches..."
# Best-effort : drop_caches (nécessite root + kernel qui l'autorise)
sync 2>/dev/null
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null && echo "  drop_caches OK (root)" || echo "  drop_caches refusé (kernel) — cache page se libérera seul"
# Réduire la pression swap : force le kernel à récupérer les pages (best-effort)
echo 100 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null

echo ""
echo "[3/3] État final — attente 2 s pour la stabilisation..."
sleep 2
echo "=== APRÈS ==="
awk '/MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree/ {printf "%s = %.2f Go\n", $1, $2/1048576}' /proc/meminfo
echo ""
echo "Top RSS (apps restantes) :"
ps -eo rss,comm --sort=-rss 2>/dev/null | head -8
echo ""
echo "OK — session prête. RAM disponible : $(awk '/MemAvailable/ {printf "%.2f", $2/1048576}' /proc/meminfo) Go"
