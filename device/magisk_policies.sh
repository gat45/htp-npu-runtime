#!/system/bin/sh
su -c 'magisk --sqlite "SELECT name FROM sqlite_master WHERE type=''table''"' > /data/local/tmp/mg.out 2>&1
cat /data/local/tmp/mg.out