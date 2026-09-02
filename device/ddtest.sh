#!/system/bin/sh
echo "=== test dd+base64 ==="
dd if=/data/local/tmp/qwen05b.gguf bs=8388608 count=1 2>/dev/null | base64 -w0 | wc -c
echo "=== test dd 32B header ==="
dd if=/data/local/tmp/qwen05b.gguf bs=32 count=1 2>/dev/null | od -An -tx1 | head -2
echo "=== which base64 ==="
which base64