magisk --sqlite "INSERT OR REPLACE INTO settings (key,value) VALUES ('denylist',1)"
echo --- settings ---
magisk --sqlite "SELECT * FROM settings"