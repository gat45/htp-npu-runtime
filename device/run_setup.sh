#!/system/bin/sh
# Lance setup_phone.sh dans l'environnement Termux (utilisateur 10391, DNS fixé)
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
su 10391 -c 'export PATH=/data/data/com.termux/files/usr/bin:$PATH HOME=/data/data/com.termux/files/home PREFIX=/data/data/com.termux/files/usr LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib; bash /data/data/com.termux/files/home/geniex_harness/setup_phone.sh'
echo "WRAPPER_DONE"
