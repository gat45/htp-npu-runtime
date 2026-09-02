#!/system/bin/sh
# 1) Ajoute le repo glibc aux sources apt de Termux.
mkdir -p /data/data/com.termux/files/usr/etc/apt/sources.list.d
echo "deb https://packages-cf.termux.dev/apt/termux-glibc/ glibc stable" > /data/data/com.termux/files/usr/etc/apt/sources.list.d/glibc.list
chown 10391:10391 /data/data/com.termux/files/usr/etc/apt/sources.list.d/glibc.list
chmod 644 /data/data/com.termux/files/usr/etc/apt/sources.list.d/glibc.list

# 2) Installe glibc + proot comme uid Termux.
LOG=/data/local/tmp/glibc.log
echo "=== pkg update + install glibc proot ===" > $LOG
su 10391 -c 'PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin; HOME=/data/data/com.termux/files/home; PREFIX=/data/data/com.termux/files/usr; TMPDIR=/data/data/com.termux/files/usr/tmp; export PATH HOME PREFIX TMPDIR; cd /data/data/com.termux/files/home; pkg update -y; pkg install glibc proot -y' >> $LOG 2>&1
echo "=== EXIT ===" >> $LOG
