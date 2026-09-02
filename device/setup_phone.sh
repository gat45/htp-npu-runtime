#!/data/data/com.termux/files/usr/bin/bash
# Installé et exécuté dans Termux (RunCommandService) — ne rien taper.
exec > "$HOME/geniex_harness/setup.log" 2>&1
echo "START $(date)"

echo "== [1/5] Fix DNS (bind-mount hosts) =="
su -c 'sh /data/local/tmp/fix_dns.sh' 2>&1 | tail -3 || echo "(dns fix ignoré)"

echo "== [2/5] pkg update + python =="
pkg update -y 2>&1 | tail -3
pkg install -y python 2>&1 | tail -4
python --version 2>&1

echo "== [3/5] pip install geniex (NPU/GPU/CPU) =="
pip install geniex 2>&1 | tail -4

echo "== [4/5] Rapport matériel (root) =="
python "$HOME/geniex_harness/harness_hw.py" 2>&1 | head -25

echo "== [5/5] Appareils NPU =="
geniex-py devices 2>/dev/null || python -c "from geniex import get_plugin_list, get_device_list; print([(p, get_device_list(p)) for p in get_plugin_list()])" 2>&1 | head -5

echo "DONE $(date)"
