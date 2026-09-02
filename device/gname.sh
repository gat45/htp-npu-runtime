#!/system/bin/sh
strings /data/local/tmp/qwen3-8b-w4a16/part1_of_5.bin 2>/dev/null \
  | grep -aiE "graph|geniex|qwen|context|session" | grep -av "libc\|libm\|\.so\|reserved" | head -24