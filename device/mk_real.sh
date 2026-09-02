#!/system/bin/sh
mkdir -p /data/local/tmp/real_libs
chmod 755 /data/local/tmp/real_libs
cp /data/local/tmp/gxlibs/libQnnHtp_real.so /data/local/tmp/real_libs/libQnnHtp.so
chmod 755 /data/local/tmp/real_libs/libQnnHtp.so
ls -la /data/local/tmp/real_libs/libQnnHtp.so
rm -f /data/local/tmp/qnn_shim.log