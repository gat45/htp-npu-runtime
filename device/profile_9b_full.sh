#!/bin/bash
# profile_9b_full.sh — Profilage complet du Qwen3.8-9B sur OnePlus 15
# Usage: bash profile_9b_full.sh [quick|full|compare]
#
# Teste: GenieX CPU, GenieX NPU, JZ (si libs officielles), CPU pur
# Mesure: tok/s, prefill, TTFT, mémoire, température
#
# Prérequis: téléphone branché (USB ou WiFi ADB)

set -e
ADB="C:/Users/videl/Desktop/geniex_harness/tools/platform-tools/adb.exe"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-quick}"
MODEL="/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf"
GXLIBS="/data/local/tmp/gxlibs/libgeniex.so"
JZDIR="/data/local/tmp/jz"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; }
step() { echo -e "\n${CYAN}═══ $1 ═══${NC}"; }

# ── Check device ──
step "1. CHECK DEVICE"
DEVS=$($ADB devices 2>/dev/null | grep -w "device" | head -1)
if [ -z "$DEVS" ]; then
    err "No device. Connect OnePlus 15 and enable USB debugging."
    exit 1
fi
MODEL_NAME=$($ADB shell getprop ro.product.model 2>/dev/null | tr -d '\r')
SOC=$($ADB shell getprop ro.board.platform 2>/dev/null | tr -d '\r')
ANDROID=$($ADB shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
RAM=$($ADB shell cat /proc/meminfo 2>/dev/null | head -1 | awk '{print int($2/1024)}')
info "Device: $MODEL_NAME ($SOC) Android $ANDROID ${RAM}MB RAM"

# ── Check temperature before test ──
step "2. THERMAL BASELINE"
CPU_TEMP=$($ADB shell "cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null" | tr -d '\r')
echo "CPU temp: ${CPU_TEMP}0 millidegrees (~$((CPU_TEMP/10))°C)"
$ADB shell "cat /sys/class/thermal/thermal_zone*/type 2>/dev/null" | head -5
NPU_TEMP=$($ADB shell "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null" | head -1 | tr -d '\r')
echo "NPU temp: ${NPU_TEMP}"

# ── Free memory ──
step "3. MEMORY CHECK"
FREE_MB=$($ADB shell "cat /proc/meminfo | grep MemFree" 2>/dev/null | awk '{print int($2/1024)}' | tr -d '\r')
AVAIL_MB=$($ADB shell "cat /proc/meminfo | grep MemAvailable" 2>/dev/null | awk '{print int($2/1024)}' | tr -d '\r')
info "Free: ${FREE_MB}MB  Available: ${AVAIL_MB}MB"

# ── Check model ──
step "4. MODEL CHECK"
$ADB shell "ls -lh $MODEL 2>/dev/null" || warn "Model not found at $MODEL"
$ADB shell "ls -lh $GXLIBS 2>/dev/null" || warn "GenieX SDK not found"
$ADB shell "ls -lh $JZDIR/bin/llama-cli 2>/dev/null" || warn "llama-cli not found"
$ADB shell "ls -lh $JZDIR/lib/libllama-cli-impl.so 2>/dev/null" || warn "libllama-cli-impl.so NOT FOUND"

# ── Push geniex_ctypes.py ──
step "5. PUSH PROFILING TOOLS"
$ADB push "$SCRIPT_DIR/../geniex_ctypes.py" /data/local/tmp/geniex_ctypes.py 2>/dev/null && \
    info "geniex_ctypes.py pushed" || warn "push failed"

# ══════════════════════════════════════════════════════════════════════════
# TEST A: GenieX CPU (baseline, always works)
# ══════════════════════════════════════════════════════════════════════════
step "6. TEST A: GenieX CPU"
$ADB shell "cd /data/local/tmp && python3 -c \"
import sys, time
sys.path.insert(0, '.')
from geniex_ctypes import GenieX
gx = GenieX(lib_path='$GXLIBS')
print('GenieX version:', gx.version())
print('Plugins:', gx.plugins())
import os
models = [f for f in os.listdir('.') if f.endswith('.gguf') and '9b' in f.lower()]
if not models:
    print('ERROR: No 9B model found')
    gx.close()
    sys.exit(1)
m = models[0]
print(f'Testing: {m}')
try:
    t0 = time.time()
    llm = gx.create_llm(model_path=f'/data/local/tmp/{m}', plugin_id='llama_cpp', device_id='CPU', n_ctx=2048, n_threads=6)
    print(f'Created in {time.time()-t0:.1f}s')
    
    # Warmup
    llm.generate('Hello', max_tokens=5, temperature=0.7)
    
    # Benchmark: 3 runs
    times = []
    for i in range(3):
        t1 = time.time()
        text, prof = llm.generate('Explain what a neural network is in exactly 50 words.', max_tokens=128, temperature=0.7)
        elapsed = time.time() - t1
        words = len(text.split())
        tps = 128 / elapsed if elapsed > 0 else 0
        times.append(tps)
        print(f'  Run {i+1}: {elapsed:.2f}s, {tps:.1f} tok/s, {len(text)} chars')
    
    avg = sum(times) / len(times)
    print(f'CPU AVG: {avg:.1f} tok/s')
    llm.close()
except Exception as e:
    print(f'Error: {type(e).__name__}: {e}')
gx.close()
\" 2>&1" || warn "GenieX CPU test failed"

# ══════════════════════════════════════════════════════════════════════════
# TEST B: GenieX NPU (HTP0) — may fail for 9B SSM
# ══════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "full" ] || [ "$MODE" = "compare" ]; then
    step "7. TEST B: GenieX NPU (HTP0)"
    $ADB shell "cd /data/local/tmp && python3 -c \"
import sys, time
sys.path.insert(0, '.')
from geniex_ctypes import GenieX
gx = GenieX(lib_path='$GXLIBS')
import os
models = [f for f in os.listdir('.') if f.endswith('.gguf') and '9b' in f.lower()]
if not models:
    print('ERROR: No 9B model found')
    gx.close()
    sys.exit(1)
m = models[0]
print(f'Testing NPU: {m}')
try:
    t0 = time.time()
    llm = gx.create_llm(model_path=f'/data/local/tmp/{m}', plugin_id='llama_cpp', device_id='HTP0', n_ctx=2048)
    print(f'Created in {time.time()-t0:.1f}s')
    
    # Warmup
    llm.generate('Hello', max_tokens=5, temperature=0.7)
    
    # Benchmark
    times = []
    for i in range(3):
        t1 = time.time()
        text, prof = llm.generate('Explain what a neural network is in exactly 50 words.', max_tokens=128, temperature=0.7)
        elapsed = time.time() - t1
        tps = 128 / elapsed if elapsed > 0 else 0
        times.append(tps)
        print(f'  Run {i+1}: {elapsed:.2f}s, {tps:.1f} tok/s')
    
    avg = sum(times) / len(times)
    print(f'NPU HTP0 AVG: {avg:.1f} tok/s')
    llm.close()
except Exception as e:
    print(f'Error: {type(e).__name__}: {e}')
    print('Expected: Qwen3.5/3.8 SSM may fail on NPU (QAIRT limitation)')
gx.close()
\" 2>&1" || warn "GenieX NPU test failed (expected for SSM models)"
fi

# ══════════════════════════════════════════════════════════════════════════
# TEST C: JZ backend (if llama-cli works)
# ══════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "full" ] || [ "$MODE" = "compare" ]; then
    step "8. TEST C: JZ backend (if available)"
    if $ADB shell "test -x $JZDIR/bin/llama-cli && test -f $JZDIR/lib/libllama-cli-impl.so" 2>/dev/null; then
        info "JZ backend available, testing..."
        $ADB shell "cd $JZDIR && \
            export LD_LIBRARY_PATH=$JZDIR/lib:$JZDIR/bin:/vendor/lib64 && \
            export ADSP_LIBRARY_PATH=/data/local/tmp && \
            export GGML_HEXAGON_MBUF=3200 && \
            export GGML_HEXAGON_NDEV=1 && \
            bin/llama-cli \
                -m $MODEL \
                -ngl 60 \
                -t 6 \
                -n 128 \
                --ctx-size 2048 \
                --ubatch-size 31 \
                --no-warmup \
                --no-mmap \
                -fa on \
                -p 'Explain what a neural network is in exactly 50 words.'" 2>&1 | tail -20 || warn "JZ test failed"
    else
        warn "JZ backend not available (missing llama-cli or libllama-cli-impl.so)"
        warn "Run deploy_official_fastrpc.sh first"
    fi
fi

# ══════════════════════════════════════════════════════════════════════════
# TEST D: Memory breakdown
# ══════════════════════════════════════════════════════════════════════════
step "9. MEMORY BREAKDOWN"
$ADB shell "cat /proc/meminfo | head -5" 2>/dev/null
echo "---"
$ADB shell "cat /proc/meminfo | grep -E 'MemTotal|MemFree|MemAvailable|Buffers|Cached'" 2>/dev/null

# ══════════════════════════════════════════════════════════════════════════
# TEST E: Thermal after test
# ══════════════════════════════════════════════════════════════════════════
step "10. THERMAL AFTER TEST"
CPU_TEMP2=$($ADB shell "cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null" | tr -d '\r')
echo "CPU temp: ${CPU_TEMP2}0 millidegrees (~$((CPU_TEMP2/10))°C)"
echo "Delta: $(( (CPU_TEMP2 - CPU_TEMP) / 10 ))°C"

# ══════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════
step "PROFILING COMPLETE"
echo ""
echo "Expected results for Qwen3.8-9B Q4_0 on OnePlus 15:"
echo "  GenieX CPU:     ~8-10 tok/s"
echo "  GenieX NPU:     FAIL (SSM not supported by QAIRT)"
echo "  JZ ngl=60:      ~10-12 tok/s (if libs available)"
echo "  JZ ngl=99:      CRASH (5.45GB > 3.5GB PD limit)"
echo "  GenieX 4B NPU:  ~30 tok/s (reference)"
echo "  GenieX 8B NPU:  ~17 tok/s (reference)"
echo ""
echo "Model: Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0"
echo "Size: 5.45 GB"
echo "Architecture: SSM (Gated Delta Net) — NOT attention-only"
