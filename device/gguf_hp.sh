#!/system/bin/sh
M=/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf
dd if=$M bs=1 count=1200000 2>/dev/null | strings | grep -iE "ssm_d_inner|ssm_d_state|ssm_dt_rank|ssm_n_group|kda|head_dim|num_attention|num_key_value|n_head|d_inner|dt_rank|state_size|n_embd_head" | sort -u | head -40
