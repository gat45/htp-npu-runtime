grep -an 'allocating new session' /data/local/tmp/hw7.log
echo '--- contexte autour 1ere tentative ---'
grep -aA4 -B2 'allocating new session' /data/local/tmp/hw7.log | head -20