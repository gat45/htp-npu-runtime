echo '=== PARTITIONS suite ==='
ls /dev/block/by-name/ | tail -50
echo '=== TAILLES cles (octets) ==='
for p in boot_a init_boot_a dsp_a super vendor_boot_a dtbo_a vbmeta_a modem_a; do printf '%s: ' $p; blockdev --getsize64 /dev/block/by-name/$p 2>/dev/null || echo n/a; done
echo '=== REMOTEPROC ==='
for r in /sys/class/remoteproc/remoteproc*; do echo '$(basename $r): '$(cat $r/name 2>/dev/null) [${lf}$(cat $r/state 2>/dev/null)]'; done
echo '=== CMA / reservee ==='
dmesg 2>/dev/null | grep -iE 'cma|reserved' | head -12
grep -i cma /proc/iomem 2>/dev/null | head -6