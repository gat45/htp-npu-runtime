#!/system/bin/sh
echo "=== graph/context dans qairt.log ==="
grep -aiE "graph|retrieve|context|binary" /data/local/tmp/qairt.log 2>/dev/null | head -6
echo "=== strings courts type identifiant dans part1 ==="
strings -n 2 /data/local/tmp/qwen3-8b-w4a16/part1_of_5.bin 2>/dev/null \
  | grep -E "^[a-zA-Z_][a-zA-Z0-9_]{2,26}$" \
  | grep -viE "lib|config|enable|disable|mode|size|type|graphviz|freq|debug|verbose|seq|op_|tcm|hmx|hvx|hlx|dma|nsp|tile|alloc|sched|cost|threshold|ratio|factor|early|exit|list|run|bin|cal|plugin|weight|mem|corner|nsps|thread|tile|cnoc|gemnoc|ddr|noc|slc|scid|test|csv|log|init|queue|offset|supertile|verbose|final|group|branch|layer|dims|tensor|kernel" \
  | sort -u | head -25