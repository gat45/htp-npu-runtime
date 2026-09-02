#!/system/bin/sh
# Action 1 — bundle QAIRT v81 : patch htp_backend_ext_config + bench
B=/data/local/tmp/qwen3-8b-w4a16
cp $B/htp_backend_ext_config.json $B/htp_backend_ext_config.json.bak
cat > $B/htp_backend_ext_config.json <<'EOF'
{"devices": [{"soc_model": 87, "dsp_arch": "v81", "cores": [{"core_id": 0, "perf_profile": "burst", "rpc_control_latency": 100}]}], "memory": {"mem_type": "shared_buffer"}, "context": {"weight_sharing_enabled": true}}
EOF
echo "=== config patchee: $(cat $B/htp_backend_ext_config.json | head -c 200) ..."
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export CDSP_LIBRARY_PATH=/data/local/tmp
echo "=== bench v81 (2 runs) ==="
./geniex-bench --plugin qairt --device npu -m $B -n 32 2>&1 | grep -E "decode=|\[ok"
./geniex-bench --plugin qairt --device npu -m $B -n 32 2>&1 | grep -E "decode=|\[ok"
cp $B/htp_backend_ext_config.json.bak $B/htp_backend_ext_config.json
echo "=== config restauree ==="