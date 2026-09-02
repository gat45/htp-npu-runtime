#!/system/bin/sh
echo "=== APP htp_backend_ext_config ==="
cat /data/data/com.op15.opencoderoot/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507/htp_backend_ext_config.json
echo
echo "=== TMP htp_backend_ext_config ==="
cat /data/local/tmp/models/Qwen3-4B-Instruct-2507/htp_backend_ext_config.json
echo
echo "=== APP genie_config QnnHtp section ==="
grep -A22 '"QnnHtp"' /data/data/com.op15.opencoderoot/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507/genie_config.json
echo
echo "=== APP genie_config engine/backend type ==="
grep -E '"type"|ctx-bins|n-threads|use-mmap' /data/data/com.op15.opencoderoot/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507/genie_config.json | head -8
