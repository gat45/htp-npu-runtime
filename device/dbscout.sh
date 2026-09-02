#!/system/bin/sh
echo "=== DB SCOUT ==="
ls -la /data/user/0/com.op15.toolkit.scout/databases/ 2>/dev/null
echo "=== TABLES ==="
sqlite3 /data/user/0/com.op15.toolkit.scout/databases/op15_rag.db ".tables" 2>/dev/null || echo "sqlite3 absent"
echo "=== ROW COUNTS ==="
sqlite3 /data/user/0/com.op15.toolkit.scout/databases/op15_rag.db "SELECT 'sources',count(*) FROM sources; SELECT 'entities',count(*) FROM entities;" 2>/dev/null || echo "n/a"
echo "=== LOG SCOUT RAG ==="
logcat -d -t 200 2>/dev/null | grep -iE "rag|preuve|evidence|memory|scout" | tail -15
