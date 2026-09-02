#!/system/bin/sh
# Ajoute registry.npmjs.org au hosts bind-mounté puis installe opencode-ai.
if ! grep -q "registry.npmjs.org" /data/local/tmp/hosts 2>/dev/null; then
  echo "104.16.1.34 registry.npmjs.org" >> /data/local/tmp/hosts
fi

LOG=/data/local/tmp/npm_opencode.log
echo "=== npm i -g opencode-ai ===" > $LOG
su 10391 -c 'PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin; HOME=/data/data/com.termux/files/home; PREFIX=/data/data/com.termux/files/usr; TMPDIR=/data/data/com.termux/files/usr/tmp; export PATH HOME PREFIX TMPDIR; cd /data/data/com.termux/files/home; npm i -g opencode-ai' >> $LOG 2>&1
echo "=== EXIT ===" >> $LOG
