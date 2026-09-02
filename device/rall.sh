#!/system/bin/sh
su -c "sh /data/local/tmp/ropt.sh" > /data/local/tmp/optrace_all.txt 2>&1
echo "EXIT=$?"
wc -c /data/local/tmp/optrace_all.txt