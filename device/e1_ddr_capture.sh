#!/system/bin/sh
# e1_ddr_capture.sh — capture tracefs (icc_set_bw + fastrpc + arm_smmu)
# autour d'un bench LLM, pour l'analyse E1 (voie DDR demandée).
#
# Usage (sur device) :
#   sh e1_ddr_capture.sh <runtime> <bench_cmd...>
# ex.
#   sh e1_ddr_capture.sh ggml-htp /data/local/tmp/npu/llama-bench -m Qwen3-8B-Q4_K_M.gguf -p 0 -n 16 -ngl 60
#   sh e1_ddr_capture.sh qairt    /data/local/tmp/geniex-bench --plugin qairt --device npu -m /data/local/tmp/qwen3-8b-w4a16 -n 32
#
# Produit dans /data/local/tmp/e1_<runtime>_results.txt :
#   - comptes fastrpc/SMMU
#   - icc_set_bw agrégé par node (avg/peak demandés, occurrences)
#   - tail du bench brut (pour decode t/s)

T=/sys/kernel/tracing
RT="$1"; shift
OUT=/data/local/tmp/e1_${RT}_results.txt
RAW=/data/local/tmp/e1_${RT}_raw.log
INTER=/data/local/tmp/e1_${RT}_interconnect.txt

# reset trace + buffer
echo 0 > $T/tracing_on 2>/dev/null
echo 65536 > $T/buffer_size_kb 2>/dev/null

# désactive les events qu'on va ré-encapsuler (idempotence)
echo 0 > $T/events/interconnect/icc_set_bw/enable 2>/dev/null
echo 0 > $T/events/interconnect_qcom/bcm_voter_commit/enable 2>/dev/null
echo 0 > $T/events/fastrpc/enable 2>/dev/null
echo 0 > $T/events/arm_smmu/enable 2>/dev/null

# active
echo 1 > $T/events/interconnect/icc_set_bw/enable 2>/dev/null
echo 1 > $T/events/interconnect_qcom/bcm_voter_commit/enable 2>/dev/null
echo 1 > $T/events/fastrpc/fastrpc_context_complete/enable 2>/dev/null
echo 1 > $T/events/arm_smmu/enable 2>/dev/null

> $T/trace

echo "# === run $RT ===" > "$OUT"
echo "cmd: $@ " >> "$OUT"
date >> "$OUT"

echo 1 > $T/tracing_on
"$@" > "$RAW" 2>&1
echo 0 > $T/tracing_on

date >> "$OUT"
cp $T/trace /data/local/tmp/e1_${RT}_ftrace_full.txt 2>/dev/null

# --- comptes fastrpc / SMMU ---
echo "=== fastrpc counts ===" >> "$OUT"
grep -aoE "fastrpc[a-z_]*:[a-z_]+" $T/trace 2>/dev/null | sort | uniq -c | sort -rn >> "$OUT"
echo "=== arm_smmu counts ===" >> "$OUT"
grep -aoE "arm_smmu[a-z_]*:[a-z_]+" $T/trace 2>/dev/null | sort | uniq -c | sort -rn >> "$OUT"

# --- icc_set_bw : extraire printeven + agréger par node ---
grep -aoE "icc_set_bw: path=[^ ]+ dev=[^ ]+ node=[^ ]+ avg_bw=[0-9]+ peak_bw=[0-9]+ agg_avg=[0-9]+ agg_peak=[0-9]+" $T/trace 2>/dev/null > "$INTER"
echo "=== icc_set_bw events: $(wc -l < "$INTER") ===" >> "$OUT"
# agrégation par node : avg_bw moyen + max + occurrences
awk '{
  node=""; avg=""; peak="";
  if (match($0, /node=[^ ]+/)) node=substr($0, RSTART, RLENGTH);
  if (match($0, /avg_bw=[0-9]+/)) avg=substr($0, RSTART+7, RLENGTH-7);
  if (match($0, /peak_bw=[0-9]+/)) peak=substr($0, RSTART+9, RLENGTH-9);
  key=(node!=""?node:"undef");
  n[key]++; s[key]+=avg; p[key]=peak;
  if (avg> amax[key]) amax[key]=avg;
  if (peak> pmax[key]) pmax[key]=peak;
}
END{
  printf "%-22s %8s %14s %14s %14s %14s\n","node","events","avg_avg","avg_max","peak","node_peaks";
  for (k in n) printf "%-22s %8d %14.0f %14d %14s %14s\n", k, n[k], s[k]/n[k], amax[k], p[k], pmax[k];
}' "$INTER" >> "$OUT"

# --- tail du bench brut ---
echo "=== bench raw tail ===" >> "$OUT"
tail -25 "$RAW" >> "$OUT"
echo "# done $RT" >> "$OUT"