#!/system/bin/sh
# Test Genie w4a16 Qwen3-8B sur HTP v81
export LD_LIBRARY_PATH=/data/local/tmp/genie_bundle/model/aarch64-android:/data/local/tmp/genie_bundle/model:$LD_LIBRARY_PATH
export ADSP_LIBRARY_PATH="/data/local/tmp/genie_bundle/model/hexagon-v81/unsigned;/data/local/tmp/genie_bundle/model"
cd /data/local/tmp/genie_bundle/model
./genie-t2t-run \
    --config genie_config.json \
    --prompt "Explique en detail comment fonctionne un NPU Snapdragon." \
    --max-tokens 192 2>&1
