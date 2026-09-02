#!/system/bin/sh
echo "=== POSITIONS ==="
grep -oE 'resource-id="com.op15.toolkit:id/etInput"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/ui2.xml 2>/dev/null
grep -oE 'resource-id="com.op15.toolkit:id/btnSend"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/ui2.xml 2>/dev/null
echo "=== RAW ETINPUT ==="
grep -oE '<node[^>]*etInput[^>]*>' /data/local/tmp/ui2.xml 2>/dev/null | head -1
echo "=== RAW BTNSEND ==="
grep -oE '<node[^>]*btnSend[^>]*>' /data/local/tmp/ui2.xml 2>/dev/null | head -1
