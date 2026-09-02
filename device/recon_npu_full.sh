#!/system/bin/sh
# recon_npu_full.sh — Carte d'accès NPU complète (OnePlus 15 SM8850 / Android 16)
#
# Objectif : passer de la simple détection du NPU à une preuve expérimentale de
# toute la chaîne logicielle : app → FastRPC → qcom_glink → remoteproc-cdsp →
# firmware CDSP → NSP/Hexagon HTP v81 → QNN/HTP service → exécution HTP.
#
# Sortie : $OUT_DIR/npu_recon/ avec 12 fichiers + FINAL_NPU_MAP.md
#
# Usage : su -c 'sh /data/local/tmp/recon_npu_full.sh'
#         (ou : adb shell su -c 'sh /data/local/tmp/recon_npu_full.sh')
#
# Règles de formulation (doc 2026-08-19) :
#   - « chemin logiciel vers le sous-système NSP/HTP via CDSP/FastRPC », PAS
#     « le CDSP héberge le NPU » (partition matérielle interne non établie).
#   - 8 zones thermiques nsphvx/nsphmx ≠ 8 unités de calcul indépendantes.
#   - « Can't find service: nn » ≠ « NNAPI absent », mais « non enregistré
#     sous ce nom sur ce build ».

set -u
OUT=/data/local/tmp/npu_recon
mkdir -p "$OUT"

say()  { echo "[recon] $*"; }
sec()  { echo; echo "===== $1 ====="; }

# ---------------------------------------------------------------- identity
sec "IDENTITY"
{
  echo "ro.soc.model      = $(getprop ro.soc.model)"
  echo "ro.board.platform = $(getprop ro.board.platform)"
  echo "ro.hardware       = $(getprop ro.hardware)"
  echo "ro.build.version.release = $(getprop ro.build.version.release)"
  echo "ro.build.version.sdk     = $(getprop ro.build.version.sdk)"
  echo "--- getprop filtre soc/board/hardware/platform/qcom ---"
  getprop | grep -Ei 'soc|board|hardware|platform|qcom'
  echo "--- /proc/cpuinfo ---"
  grep -Ei 'Hardware|model name|processor' /proc/cpuinfo | head -8
  echo "--- soc0 ---"
  for f in machine soc_id revision; do
    echo "soc0/$f = $(cat /sys/devices/soc0/$f 2>/dev/null)"
  done
} > "$OUT/identity.txt" 2>&1
say "identity.txt OK"

# ---------------------------------------------------------------- devices
sec "DEVICES FastRPC"
{
  ls -l /dev/fastrpc* 2>/dev/null
  ls -l /dev/glink_pkt_*cdsp 2>/dev/null
  echo "--- /proc/misc ---"
  grep -i fastrpc /proc/misc
} > "$OUT/devices.txt" 2>&1
say "devices.txt OK"

# ---------------------------------------------------------------- selinux
sec "SELINUX"
{
  ls -lZ /dev/fastrpc-nsp1000 2>/dev/null
  ls -lZ /dev/fastrpc-cdsp 2>/dev/null
  ls -lZ /dev/fastrpc-cdsp-secure 2>/dev/null
  echo "--- contexte untrusted_app de référence ---"
  id -Z 2>/dev/null
  echo "--- denials AVC récents ---"
  dmesg 2>/dev/null | grep -Ei 'avc:.*denied' | grep -Ei 'fastrpc|cdsp' | tail -20
} > "$OUT/selinux.txt" 2>&1
say "selinux.txt OK"

# ---------------------------------------------------------------- fastrpc
sec "KERNEL FastRPC/glink/smem/rproc"
{
  echo "--- lsmod ---"
  lsmod 2>/dev/null | grep -Ei 'fastrpc|glink|smem|rproc'
  echo "--- /sys/module ---"
  find /sys/module -maxdepth 1 -type d 2>/dev/null | grep -Ei 'fastrpc|glink|rproc'
  echo "--- dmesg fastrpc/remoteproc ---"
  dmesg 2>/dev/null | grep -Ei 'fastrpc|remoteproc|glink-edge' | tail -30
} > "$OUT/fastrpc.txt" 2>&1
say "fastrpc.txt OK"

# ---------------------------------------------------------------- remoteproc
sec "REMOTEPROC"
{
  for r in /sys/class/remoteproc/remoteproc*; do
    printf "%s : %s / %s\n" "$(basename "$r")" \
      "$(cat "$r/name" 2>/dev/null)" "$(cat "$r/state" 2>/dev/null)"
  done
  echo "--- firmware référencé par le driver cdsp ---"
  ls -lh /vendor/firmware_mnt/image/cdsp.mdt 2>/dev/null
  ls -lh /vendor/firmware_mnt/image/adsp.mdt 2>/dev/null
  echo "--- /vendor/dsp ---"
  ls -la /vendor/dsp/ 2>/dev/null
} > "$OUT/remoteproc.txt" 2>&1
say "remoteproc.txt OK"

# ---------------------------------------------------------------- libraries
sec "LIBRARIES NPU/QNN/HTP"
{
  echo "--- find /vendor/lib64 /vendor/lib ---"
  find /vendor/lib64 /vendor/lib -type f 2>/dev/null | \
    grep -Ei 'qnn|htp|hexagon|nsp|cdsprpc|rpc'
  echo "--- readelf NEEDED libnspextensiongenericqnnservice.so ---"
  readelf -d /vendor/lib64/libnspextensiongenericqnnservice.so 2>/dev/null | grep -i needed
  echo "--- readelf NEEDED libcdsprpc.so ---"
  readelf -d /vendor/lib64/libcdsprpc.so 2>/dev/null | grep -i needed
  echo "--- symboles qnn/htp/nsp/rpc (libnspextension) ---"
  readelf -Ws /vendor/lib64/libnspextensiongenericqnnservice.so 2>/dev/null | \
    grep -Ei 'qnn|htp|nsp|rpc' | head -15
  echo "--- recherche libggml-htp / libggml-hexagon (backend llama.cpp) ---"
  find / -type f \( -name 'libggml-htp*' -o -name 'libggml-hexagon*' \) 2>/dev/null
} > "$OUT/libraries.txt" 2>&1
say "libraries.txt OK"

# ---------------------------------------------------------------- processes
sec "PROCESSES"
{
  ps -A 2>/dev/null | grep -Ei 'rpc|dsp|qnn|nsp|hexagon|genie'
  echo "--- threads kernel glink ---"
  ps -A -T 2>/dev/null | grep -Ei 'glink' | head -20
} > "$OUT/processes.txt" 2>&1
say "processes.txt OK"

# ---------------------------------------------------------------- thermal
sec "THERMAL NSP/HTP + GPU"
{
  for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat "$z/type" 2>/dev/null)
    case "$t" in
      nsphvx*|nsphmx*) echo "$t: $(cat "$z/temp" 2>/dev/null) mC";;
    esac
  done
  echo "--- GPU ---"
  for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat "$z/type" 2>/dev/null)
    case "$t" in
      gpuss*) echo "$t: $(cat "$z/temp" 2>/dev/null) mC";;
    esac
  done
} > "$OUT/thermal.txt" 2>&1
say "thermal.txt OK"

# ---------------------------------------------------------------- qnn
sec "QNN"
{
  echo "--- libs QNN présentes dans /vendor/lib64 ---"
  ls /vendor/lib64/ 2>/dev/null | grep -Ei 'qnn|htp|nsp' 
  echo "--- extension NSP vendor : libnspextension* ---"
  ls -l /vendor/lib64/libnspextension* 2>/dev/null
  echo "--- libQnnHtp* : $(ls /vendor/lib64/libQnnHtp*.so 2>/dev/null | wc -l) trouvée(s) ---"
  echo "(absence = libs QNN HTP du SDK non exposées comme libs vendor publiques)"
} > "$OUT/qnn.txt" 2>&1
say "qnn.txt OK"

# ---------------------------------------------------------------- nnapi
sec "NNAPI"
{
  echo "--- service list ---"
  service list 2>/dev/null | grep -Ei 'dsp|npu|nn|qnn|hexagon'
  echo "--- dumpsys ---"
  dumpsys 2>/dev/null | grep -Ei 'dsp|npu|qnn|hexagon|htp' | head -10
  echo "--- service nn : $(service check nn 2>&1) ---"
  echo "(interprétation : service non enregistré sous ce nom sur ce build)"
} > "$OUT/nnapi.txt" 2>&1
say "nnapi.txt OK"

# ---------------------------------------------------------------- interconnect
sec "INTERCONNECT (BW)"
{
  echo "--- fichiers bw_hwmon_meas / dcvs ---"
  find /sys -type f 2>/dev/null | grep -Ei 'bw_hwmon_meas|hwmon.*bw|dcvs' | head -20
} > "$OUT/interconnect.txt" 2>&1
say "interconnect.txt OK"

# ---------------------------------------------------------------- FINAL_NPU_MAP
sec "FINAL_NPU_MAP"
cat > "$OUT/FINAL_NPU_MAP.md" <<'MAPEOF'
# FINAL_NPU_MAP — Carte d'accès NPU (SM8850 / OP15 / Android 16)

> Générée par recon_npu_full.sh — timestamp :
MAPEOF
date >> "$OUT/FINAL_NPU_MAP.md"
cat >> "$OUT/FINAL_NPU_MAP.md" <<'MAPEOF'

## Chaîne logicielle vers le sous-système NSP/HTP (via CDSP/FastRPC)

```
Application
   └── llama.cpp / autre runtime
         └── libcdsprpc.so
               └── /dev/fastrpc-nsp1000, /dev/fastrpc-cdsp
                     └── FastRPC kernel driver
                           └── qcom_glink
                                 └── fastrpcglink-apps-dsp
                                       └── remoteproc CDSP (running)
                                             └── firmware /vendor/firmware_mnt/image/cdsp.mdt
                                                   └── NSP / Hexagon HTP v81
                                                         └── QNN / HTP service
                                                               └── exécution HTP
```

## Constats bruts (à compléter par les fichiers de cette cartouche)

- Identité SoC : voir `identity.txt` (attendu : SM8850 / canoe / qcom / Android 16).
- Portes FastRPC : voir `devices.txt` (attendu : fastrpc-nsp1000, fastrpc-cdsp,
  fastrpc-cdsp-secure, fastrpc-adsp-secure, fastrpc-lpass2000).
- SELinux : voir `selinux.txt` — les denials `untrusted_app` sur
  /dev/fastrpc-cdsp(-secure) prouvent une restriction de politique, pas
  l'absence du périphérique.
- Kernel : voir `fastrpc.txt` — qcom_glink + remoteproc-cdsp + glink-edge
  fastrpcglink-apps-dsp (poll mode 3, timeout 9999).
- Remoteproc : voir `remoteproc.txt` — cdsp expected `running`, firmware
  cdsp.mdt présent, /vendor/dsp/ avec cdsp/.
- Librairies : voir `libraries.txt` — libcdsprpc.so,
  libnspextensiongenericqnnservice.so ; NOTA : libQnnHtp*.so absentes de
  /vendor/lib64 (le système expose une extension QNN NSP vendor, pas les
  libs QNN HTP usuelles du SDK).
- Processus : voir `processes.txt` — cdsprpcd + glink-fastrpcglink-apps-dsp
  + remoteproc-cdsp.
- Thermique : voir `thermal.txt` — zones nsphvx-0..3 / nsphmx-0..3 (8 zones =
  domaines thermiques, PAS 8 unités de calcul) + gpuss-*.
- QNN : voir `qnn.txt` — extension NSP vendor présente ; services QNN via
  `service list`/`dumpsys` (voir nnapi.txt).
- NNAPI : voir `nnapi.txt` — service `nn` non enregistré sous ce nom sur ce
  build (≠ « NNAPI absent »).
- Interconnect : voir `interconnect.txt` — bw_hwmon_meas si exposé.

## Niveaux de preuve atteints (à cocher après lecture des fichiers)

- [ ] Niveau 1 — backend chargé (libggml-htp-v81.so / libggml-hexagon.so
      présent ou chargé par llama.cpp)
- [ ] Niveau 2 — backend initialise QNN/FastRPC (sessions HTP visibles)
- [ ] Niveau 3 — opération tensorielle exécutée sur HTP (mesure : tokens
      générés NPU, température NSP qui monte sous charge, BW, logcat)
MAPEOF
say "FINAL_NPU_MAP.md OK"

echo
echo "===== RECON TERMINÉE ====="
ls -la "$OUT"
