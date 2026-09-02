#!/system/bin/sh
# =========================================================================
# SONDE TELEMETRIE COMPLETE — SM8850 (adaptee aux zones reelles)
#
# Zones SM8850 verifiees sur OnePlus 15 / Android 16 :
#   CPU   : cpu-1-0-0, cpu-1-1-0, cpu-0-* (cluster big/little), cpullc-*
#   SoC   : qmx-0-1, qmx-1-2..4
#   DDR   : ddr
#   GPU   : gpuss-0..10
#   HTP   : nsphvx-0..3 (HVX) + nsphmx-0..3 (HMX)  <- capteurs NPU reels !
#   CPU freq : /sys/devices/system/cpu/cpufreq/policy{0,6}/scaling_cur_freq
#   GPU freq : n/a sans root (/sys/kernel/gpu/gpu_clock vide)
#   GPU busy : n/a sans root (pas de kgsl lisible)
#   Mem    : /proc/meminfo
#   ZRAM   : /sys/block/zram0/mm_stat (orig_data_size)
#   RSS    : /proc/<PID>/status (VmRSS + RssAnon + RssFile + RssShmem)
#   Cur    : /sys/class/power_supply/battery/current_now
#
# Usage : sh telemetry_full_sm8850.sh <interval_s> <pid> [out_file]
# Sortie : timestamp|cpu%|gpu%|f_big|f_lit|t_cpu|t_soc|t_gpu|t_ddr|t_htp|
#          mem_total|mem_free|mem_avail|swap_total|swap_free|zram_mb|
#          rss_mb|anon_mb|file_mb|shmem_mb|cur_ua
# =========================================================================
INTERVAL="${1:-0.5}"
PID="${2:-}"
OUT="${3:-}"

find_temp() {
    name="$1"
    for z in /sys/class/thermal/thermal_zone*; do
        [ -f "$z/type" ] || continue
        t=$(cat "$z/type" 2>/dev/null)
        case "$t" in
            *"$name"*)
                v=$(cat "$z/temp" 2>/dev/null)
                case "$v" in
                    ''|*[!0-9-]*) ;;
                    *) awk "BEGIN {printf \"%.1f\", $v/1000}"; return ;;
                esac ;;
        esac
    done
    echo "NA"
}

get_htp_temp() {
    # HTP = plus chaude des zones nsphvx/nsphmx
    m=0
    for z in /sys/class/thermal/thermal_zone*; do
        t=$(cat "$z/type" 2>/dev/null)
        case "$t" in
            nsphvx-*|nsphmx-*)
                v=$(cat "$z/temp" 2>/dev/null)
                case "$v" in
                    ''|*[!0-9]*) ;;
                    *) [ "$v" -gt "$m" ] && m=$v ;;
                esac ;;
        esac
    done
    if [ "$m" -gt 0 ]; then awk "BEGIN {printf \"%.1f\", $m/1000}"; else echo "NA"; fi
}

get_cpu_pct() {
    a=$(cat /proc/stat 2>/dev/null | awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5+$6}')
    sleep 0.1
    b=$(cat /proc/stat 2>/dev/null | awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5+$6}')
    awk -v a="$a" -v b="$b" 'BEGIN {
        split(a,x," "); split(b,y," ")
        dt=y[1]-x[1]; di=y[2]-x[2]
        if(dt>0) printf "%.1f", 100*(dt-di)/dt; else print "NA"
    }'
}

get_freq() {
    f="$1"
    if [ -f "$f" ]; then v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9]*) echo 0;; *) echo "$v";; esac; else echo 0; fi
}

get_mem() {
    awk '
    /^MemTotal:/     {t=$2}
    /^MemFree:/      {f=$2}
    /^MemAvailable:/ {a=$2}
    /^SwapTotal:/    {st=$2}
    /^SwapFree:/     {sf=$2}
    END {printf "%.0f %.0f %.0f %.0f %.0f", t/1024, f/1024, a/1024, st/1024, sf/1024}
    ' /proc/meminfo 2>/dev/null
}

get_zram() {
    # Pas de /sys/block/zram* sur ce firmware — on derive de /proc/swaps + meminfo
    # (SwapTotal - SwapFree) est la seule source fiable ici
    awk '
    /^SwapTotal:/ {t=$2}
    /^SwapFree:/  {f=$2}
    END { if(t>0) printf "%.1f", (t-f)/1024; else print "0" }
    ' /proc/meminfo 2>/dev/null
}

get_proc_mem() {
    if [ -n "$PID" ] && [ -r "/proc/$PID/status" ]; then
        awk '/^VmRSS:/ {r=$2} /^RssAnon:/ {a=$2} /^RssFile:/ {f=$2} /^RssShmem:/ {s=$2}
        END {printf "%.1f %.1f %.1f %.1f", r/1024, a/1024, f/1024, s/1024}' "/proc/$PID/status"
    else echo "NA NA NA NA"; fi
}

get_cur() {
    for f in /sys/class/power_supply/battery/current_now /sys/class/power_supply/bms/current_now; do
        if [ -f "$f" ]; then v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9-]*) ;; *) echo "$v"; return;; esac; fi
    done
    echo "NA"
}

log() { echo "$1"; [ -n "$OUT" ] && echo "$1" >> "$OUT"; }

while true; do
    ts=$(date +%s.%3N 2>/dev/null); [ -n "$ts" ] || ts=$(date +%s)
    cpu=$(get_cpu_pct)
    fbig=$(get_freq /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq)
    flit=$(get_freq /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)
    tcpu=$(find_temp cpu-1)
    tsoc=$(find_temp qmx)
    tgpu=$(find_temp gpuss)
    tddr=$(find_temp ddr)
    thtp=$(get_htp_temp)
    mem=$(get_mem)
    zram=$(get_zram)
    pmem=$(get_proc_mem)
    cur=$(get_cur)
    log "$ts|cpu=$cpu|f_big=$fbig|f_lit=$flit|t_cpu=$tcpu|t_soc=$tsoc|t_gpu=$tgpu|t_ddr=$tddr|t_htp=$thtp|$mem|zram_mb=$zram|rss_anon_file_shm=$pmem|cur_ua=$cur"
    sleep "$INTERVAL"
done