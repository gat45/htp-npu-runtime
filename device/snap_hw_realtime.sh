#!/system/bin/sh
# Snap HW realtime detect - GPU, NPU, RAM BW, CPU per component
echo "=== GPU Adreno (kgsl) ==="
GPUCLK=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null)
MAXGPU=$(cat /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null)
echo "gpuclk: ${GPUCLK:-N/A} Hz | max: ${MAXGPU:-N/A} Hz"
echo "gpubusy (busy idle): $(cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null)"
echo "gpu_available_freqs: $(cat /sys/class/kgsl/kgsl-3d0/gpu_available_frequencies 2>/dev/null)"
echo "current_freq: $(cat /sys/class/kgsl/kgsl-3d0/current_frequency 2>/dev/null)"
echo "dyn_freq: $(cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq 2>/dev/null)"
echo "governor: $(cat /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>/dev/null)"

echo ""
echo "=== NPU / Hexagon (CDSP/DSP) ==="
echo "htp_freq: $(cat /sys/kernel/debug/adsprpc/htp_domains 2>/dev/null)"
echo "cdsp_freq: $(cat /sys/class/devfreq/*cdsp*/cur_freq 2>/dev/null)"
echo "cdsp_max: $(cat /sys/class/devfreq/*cdsp*/max_freq 2>/dev/null)"
echo "cdsp_governor: $(cat /sys/class/devfreq/*cdsp*/governor 2>/dev/null)"
echo "cdsp_avail: $(cat /sys/class/devfreq/*cdsp*/available_frequencies 2>/dev/null)"
echo "npumpu_freq: $(cat /sys/class/devfreq/*npu*/cur_freq 2>/dev/null)"
echo "aoss_mbox: $(ls /sys/kernel/debug/mbox 2>/dev/null)"

echo ""
echo "=== RAM BW / DDR ==="
echo "ddr_cur: $(cat /sys/class/devfreq/*ddr*/cur_freq 2>/dev/null)"
echo "ddr_max: $(cat /sys/class/devfreq/*ddr*/max_freq 2>/dev/null)"
echo "ddr_avail: $(cat /sys/class/devfreq/*ddr*/available_frequencies 2>/dev/null)"
echo "ddr_bw_ports: $(ls /sys/kernel/debug/ddr_bw 2>/dev/null)"
echo "mem_bw: $(cat /sys/kernel/debug/ddr_bw/*/bw 2>/dev/null)"

echo ""
echo "=== RAM meminfo ==="
grep -E "MemTotal|MemFree|MemAvailable|Cached|SwapTotal|SwapFree|Active|Inactive" /proc/meminfo

echo ""
echo "=== CPU per core (current / min / max) ==="
for c in 0 1 2 3 4 5 6 7; do
  cur=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null)
  mn=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_min_freq 2>/dev/null)
  mx=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq 2>/dev/null)
  gov=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor 2>/dev/null)
  echo "cpu$c: ${cur:-N/A} / min ${mn:-N/A} / max ${mx:-N/A} Hz | gov=$gov"
done

echo ""
echo "=== Thermique (zones) ==="
for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat $z/temp 2>/dev/null)
  ty=$(cat $z/type 2>/dev/null)
  [ -n "$t" ] && echo "$ty: $t"
done
