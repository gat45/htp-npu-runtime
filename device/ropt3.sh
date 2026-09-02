#!/system/bin/sh
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp
export ADSP_LIBRARY_PATH=/data/local/tmp/gxlibs
part="$1"
shift
./qnn_optrace "/data/local/tmp/qwen3-8b-w4a16/$part" "$@"