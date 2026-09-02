#!/system/bin/sh
echo "=== LOGCAT APP (geniex/npu/op15) ==="
logcat -d -t 300 2>/dev/null | grep -iE "geniex|npu|qairt|op15|snapnpu|error|exception" | tail -40
echo "=== PROCESS APP ==="
pidof com.op15.toolkit
