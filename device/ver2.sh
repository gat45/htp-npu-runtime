#!/system/bin/sh
echo "=== QAIRT VERSION DANS LES .so ==="
for so in libgeniex_core.so libQnnHtpV81.so libQnnHtp.so libcdsprpc.so; do
  P=$(find /data/app -path "*com.op15.toolkit*" -name "$so" 2>/dev/null | head -1)
  if [ -n "$P" ]; then
    V=$(strings "$P" 2>/dev/null | grep -oE "2\.4[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    echo "$so: $V ($P)"
  fi
done
echo "=== GENIEX VERSION ==="
strings /data/local/tmp/gxlibs/libgeniex.so 2>/dev/null | grep -oE "0\.[0-9]+\.[0-9]+|GENIEX_VERSION[^ ]*" | head -5
echo "=== HTP SKEL VERSIONS ==="
strings /data/local/tmp/gxlibs/libggml-htp-v81.so 2>/dev/null | grep -iE "version|v81" | head -5
