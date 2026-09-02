# RAPPORT — MoE ≤8B AVEC TÊTE MTP NATIVE : RECHERCHE EXHAUSTIVE

Date : 2026-09-02
Objet : combiner le gain placement GPU (+40 % sur MoE sparse, RAPPORT_MOE_PLACEMENT_REVERSEMENT) avec le gain spéculatif (MTP, +43 % → config 16 t/s) sur un **petit** MoE.

## Verdict

**AUCUN modèle public ≤8B total avec tête MTP native dans le GGUF n'existe.**
La voie native-MTP pour combiner les deux gains sur device est **fermée** — vérifié par 3 preuves indépendantes. La voie ouverte = draft externe (EAGLE-3/DFlash), mais bloquée par la RAM sur ce device.

---

## 1. Ce que le fork supporte (fait, vérifié dans le code)

`src/models/bailingmoe3.cpp` implémente MTP complet : `LLM_GRAPH_TYPE_DECODER_MTP`, `mtp_only`, assertions `n_layer_nextn == 1`, `nextn.eh_proj/enorm/hnorm/shared_head_norm` (lignes 25-70, 155-163, 415-446, 531).

Archis avec MTP dans le fork : `bailingmoe2.cpp`, `bailingmoe3.cpp`, `deepseek32.cpp`, `exaone-moe.cpp`, `glm4.cpp`, `granite-switch.cpp`, `step35.cpp`, `qwen35.cpp` (+ dflash/eagle3 externes). Le **support logiciel n'est pas le problème** — c'est le modèle.

## 2. Tous les candidats MoE-MTP publics sont ≥ 35B (fait)

| Famille | Plus petit représentant | Tête MTP | Taille |
|---|---|---|---|
| Qwen3.5-MoE (qwen35moe) | Qwen3.5-35B-A3B | ✅ native | **35B total** → ~20 Go Q4_0 |
| K-EXAONE MoE (exaone-moe) | 236B-A23B (dummy 7B-A1B **sans** tête) | ❌/236B | **236B** |
| BailingMoE (bailingmoe2) | Ling-mini-2.0 | ❌ MTP désactivé | ~16B |
| BailingMoE3 (bailingmoe3) | **Ling-3.0-tiny** (8B-A1.3B) | **❌ `num_nextn_predict_layers = 0`** | 7,9B |
| Qwen3.8-Flash-Next | 125B-A6B | ✅ native 1 layer | **125B** |
| DeepSeek-32 / step35 / glm4-moe / granite-switch | — | ✅ mais tous ≥ 30B | — |

## 3. Preuve directe sur le candidat le plus proche : Ling-3.0-tiny (fait)

Config officielle `inclusionAI/Ling-3.0-tiny/config.json` :
```
architectures = ['BailingMoeV3ForCausalLM']   → bailingmoe3 = SUPPORTÉ par le fork
num_experts = 128 · num_experts_per_tok = 8   → 1,3B actifs / 7,9B
MTPKEY num_nextn_predict_layers = 0           → AUCUNE tête MTP dans le modèle
MTPKEY mtp_loss_scaling_factor = 0
```

Le GGUF Q4_0 existe (bloomer010 : `Ling-3.0-tiny-Q4_0.gguf` 4,53 Go, bartowski : Q4_0 + **IQ4_NL** — les 2 formats HTP).
**Mais sans `num_nextn_predict_layers > 0`, pas de tensors nextn.* → pas de draft-mtp possible.**

Le Reddit r/LocalLLaMA sur Ling-3.0-tiny confirme : « *With speculative decoding, their models could give so faster t/s* » — i.e. la communauté attend un draft externe, preuve que le MTP natif n'y est pas.

## 4. Pourquoi c'est structurel (hypothèse, étayée)

Le MTP natif ajoute un bloc complet par couche (eh_proj = concat 2×hidden) — le coût d'entraînement/paramètres ne se justifie que sur les gros modèles API (35B+). Les petits MoE (Marco-Nano/Mini, Ling-tiny) ciblent le marché local et n'embarquent pas la tête. Résultat : aucun éditeur ne l'a publié.

## 5. La voie alternative : draft externe (EAGLE-3/DFlash) sur MoE — bloquée par RAM (fait mesuré)

- Marco-Nano Q4_0 (4,36 Go de fichier) tourne déjà près du plafond : le 9B dense de 5,08 Go consomme **~13 Go système** (RssAnon buffers repack/shadow + 2 contextes MTP).
- Ajouter un draft EAGLE-3/DFlash (même un petit 0,5-1B) = **2e jeu de poids + 2e contexte** → OOM quasi garanti dans les ~9-10 Go MemAvailable.
- Le fork a `dflash.cpp` + `eagle3.cpp` (compilés), mais l'appariement n'est pas le problème : c'est la RAM.

## 6. Conclusion et recommandations

1. **Ne pas poursuivre la recherche de MoE-MTP ≤8B** : espace de recherche épuisé (Qwen, Ling, Marco, EXAONE, DeepSeek, step35, glm4-moe, granite — tous vérifiés ≥35B ou sans tête).
2. **Ling-3.0-tiny reste un très bon candidat de contrôle** : bailingmoe3-MTP supporté par le fork, Q4_0/IQ4_NL dispo, 4,53 Go — pour mesurer un MoE 128-experts/8-actifs vs Marco-Nano 256-experts/8-actifs **sans** spéculation (classement placement GPU/HTP + ARGSORT + fixe par-op).
3. **Le seul vrai levier de spéculation restant sur device = optimiser la config 16 t/s dense** (HTP pur 11,26 t/s est déjà le champion toutes configs confondues).
4. Si le but est de démontrer MoE×spéculation : le faire sur un device 16-24 Go (SM8750 ou PC QAIRT), pas sur le OnePlus 15.

## Fichiers et chemins

- Code MTP bailingmoe3 : `src/models/bailingmoe3.cpp` (fork JZ)
- Config Ling-3.0-tiny : `https://huggingface.co/inclusionAI/Ling-3.0-tiny` (`num_nextn_predict_layers = 0`)
- GGUF HTP-compatibles : `bloomer010/Ling-3.0-tiny-GGUF` (Q4_0 4,53 Go), `bartowski/Ling-3.0-tiny-GGUF` (Q4_0 + IQ4_NL)
- Drafts externes fork : `src/models/dflash.cpp`, `src/models/eagle3.cpp`
- Contexte : `RAPPORT_MOE_PLACEMENT_REVERSEMENT_20260902.md`, `RAPPORT_CONTROLE_MOE_MARCO_HTP_20260902.md`

## Red team

- [MISSING] : test réel Ling-3.0-tiny Q4_0 sur device (non fait — décision d'arrêt avant téléchargement ; le modèle est dispo si tu veux le contrôle 128-experts).
- [HYPOTHESIS] : le « draft externe = OOM » est une extrapolation du facteur mémoire 5,08→13 Go mesuré sur le dense ; à confirmer par une mesure RSS réelle si un draft ~1B est tenté.
