#!/system/bin/sh
echo '=== private dns ==='
settings get global private_dns_mode
settings get global private_dns_specifier
echo '=== verified boot ==='
getprop ro.boot.verifiedbootstate
getprop ro.boot.vbmeta.device_state
getprop ro.boot.warranty_bit
getprop ro.boot.flash.locked
echo '=== adb ==='
settings get global adb_enabled
echo '=== modules ==='
ls /data/adb/modules 2>/dev/null
echo '=== apk installed ==='
pm path com.op15.toolkit 2>/dev/null
echo '=== done ==='
