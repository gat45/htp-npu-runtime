echo '=== ANR: quel package ? ==='
for f in /data/system/dropbox/system_app_anr@*.txt.gz; do zcat $f 2>/dev/null | head -5 | grep -aE 'Process|Subject|package' ; echo '---'; done | head -20
echo '=== LIBS du scout APK ==='
pm path com.op15.toolkit.scout
echo '=== Taille donnees scout ==='
du -sh /data/data/com.op15.toolkit.scout 2>/dev/null
du -sh /data/data/com.op15.toolkit.scout/* 2>/dev/null | sort -rh | head -8
echo '=== Limites ION device ==='
getprop | grep -iE 'ion|abnormal|mem.*limit' | head -8