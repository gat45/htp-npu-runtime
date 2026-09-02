#!/system/bin/sh
cd /data/local/tmp
curl -sL -A "Mozilla/5.0" -o qwen05b.gguf "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
echo "EXIT_CODE=$?"
ls -l qwen05b.gguf
