#!/system/bin/sh
echo "=== LIBS SCOUT (npu_jni) ==="
ls /data/app/*/com.op15.toolkit.scout*/lib/arm64/libnpu_jni.so 2>/dev/null
ls /data/app/*/com.op15.toolkit.scout*/lib/arm64/ 2>/dev/null | grep -iE "npu_jni|geniex|llama" | head
echo "=== GENIEX SDK init charge quoi ? ==="
echo "=== LOGCAT GenieXSdk init ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk|loadLibrary|npu_jni|UnsatisfiedLink" | tail -15
