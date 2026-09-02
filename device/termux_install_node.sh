#!/system/bin/sh
LOG=/data/local/tmp/pkg_node.log
echo "=== pkg install nodejs-lts ===" > $LOG
su 10391 -c 'PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin; HOME=/data/data/com.termux/files/home; PREFIX=/data/data/com.termux/files/usr; TMPDIR=/data/data/com.termux/files/usr/tmp; export PATH HOME PREFIX TMPDIR; cd /data/data/com.termux/files/home; pkg install nodejs-lts -y' >> $LOG 2>&1
echo "=== EXIT ===" >> $LOG
