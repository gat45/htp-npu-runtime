#!/system/bin/sh
echo "=== PORTS LLM ==="
ss -tlnp 2>/dev/null | grep -E "1234|8080|18181|5000|8000" | head
echo "=== PROCESS LLM ==="
ps -A 2>/dev/null | grep -iE "llama|geniex|server|llm" | head
echo "=== NETSTAT ==="
cat /proc/net/tcp 2>/dev/null | head -5
echo "=== TEST 1234 ==="
echo -e "GET /v1/models HTTP/1.0\r\n\r" | nc 127.0.0.1 1234 2>/dev/null | head -5
