#!/system/bin/sh
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
su 10391 -c 'export PATH=/data/data/com.termux/files/usr/bin:$PATH HOME=/data/data/com.termux/files/home PREFIX=/data/data/com.termux/files/usr LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib; GENIEX_LIB_PATH=/data/local/tmp/gxlibs python - <<EOF
import geniex
print("API:", [x for x in dir(geniex) if not x.startswith("_")][:20])
try:
    from geniex import AutoModelForCausalLM
    print("AutoModelForCausalLM OK")
    m = AutoModelForCausalLM.from_pretrained("/data/local/tmp/qwen05b.gguf", device_map="cpu")
    print("modele charge OK")
    out = m.generate("1+1=", max_new_tokens=16)
    print("GEN:", out.text[:80])
    m.close()
except Exception as e:
    import traceback; traceback.print_exc()
EOF'
