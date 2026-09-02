#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

echo "=== TEST 2: FFN->OpenCL, Attn+Norm->HTP0 ==="
./llama-bench -m /data/local/tmp/Qwen3-8B-Q4_K_M.gguf -ngl 99 -p 16 -n 16 -t 8 \
  -ot "blk.*.ffn_*=OpenCL;blk.*.attn_*=HTP0;blk.*.norm*=HTP0" \
  > /data/local/tmp/bench_8b_fn_split.log 2>&1
echo "DONE_FFN_GPU"

echo "=== TEST 4: Norm+Attn->HTP0, FFN->OpenCL (inverse positions) ==="
./llama-bench -m /data/local/tmp/Qwen3-8B-Q4_K_M.gguf -ngl 99 -p 16 -n 16 -t 8 \
  -ot "blk.*.ffn_*=OpenCL;blk.*.attn_*=HTP0;blk.*.norm*=HTP0" \
  > /data/local/tmp/bench_8b_fn_split2.log 2>&1
echo "DONE_2"