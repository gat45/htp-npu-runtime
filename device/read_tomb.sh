#!/system/bin/sh
ls -t /data/tombstones/ 2>/dev/null | head -3
TB=$(ls -t /data/tombstones/ 2>/dev/null | head -1)
echo "tombstone: $TB"
if [ -n "$TB" ]; then
  grep -aE "signal|backtrace|#0[0-9] pc|libQnnHtp|shim|qnn_optrace|abort message|SIGSEGV|SIGABRT" "/data/tombstones/$TB" | head -30
fi