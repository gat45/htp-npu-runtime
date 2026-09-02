#!/system/bin/sh
echo "=== LANCEMENT APP ==="
am force-stop com.op15.toolkit
sleep 1
am start -n com.op15.toolkit/.NpuChatActivity
sleep 8
PID=$(pidof com.op15.toolkit)
echo "APP PID=$PID"
echo "=== MAPS LIBs (genie/qnn/hexagon/htp/cdsp/fastrpc/llama) ==="
grep -Ei "genie|qnn|qairt|hexagon|htp|cdsp|fastrpc|llama|npu" /proc/$PID/maps 2>/dev/null | grep -oE "/[^ ]+\.so" | sort -u
echo "=== ENVIRON ==="
tr "\0" "\n" < /proc/$PID/environ 2>/dev/null | grep -iE "ANDROID|LD_|GENIEX|ADSP|CDSP|PATH" | sort
