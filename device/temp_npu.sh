#!/system/bin/sh
for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat $z/type 2>/dev/null)
    case "$t" in
        nsphvx*|nsphmx*|gpuss*)
            temp=$(cat $z/temp 2>/dev/null)
            echo "$t: $((temp/1000)) C"
            ;;
    esac
done
echo "---"
echo "freq CPU:"
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null
echo "LMh:"
cat /sys/kernel/lmh_stats_*/dcvsh_freq_limit 2>/dev/null
