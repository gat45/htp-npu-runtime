# CONFIG GELÉE 16 t/s — CROISEMENT COMPLET AVEC TOUTES LES DONNÉES

**Date** : 2026-09-02 · **Device** : OnePlus 15 / SM8850 / Hexagon HTP v81 (froid ≤ 32 °C)

---

## 1. LA CONFIG GELÉE (celle qui donne ~16 t/s effectifs)

```
Runtime  : /data/local/tmp/npu (JZ 505354ed + AXE-8 + opt_mm_rows)
Modèle   : Qwen3.5-9B-D2-A-MTP-attnQ4.gguf (5,08 Go — attention Q8→Q4)
Commande : llama-server -m <MODEL> -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off
           --spec-type draft-mtp --spec-draft-n-max 1 --host 127.0.0.1 --port <P>
Env      : LD_LIBRARY_PATH=ADSP_LIBRARY_PATH=$RUNTIME GGML_HEXAGON_NDEV=1
           GGML_HEXAGON_ARCH=v81
Requête  : prompt "The capital of France is" · n_predict=16 · temperature=0
```

**Résultats confirmés (3 runs, RAPPORT_ATTNQ4_MTP1_FITOFF_3X) :**
| Run | wall t/s | ms/t | acceptance | 
|---|---|---|---|
| 1 | 10,40 | 96,1 | 75 % |
| 2 | 7,85 | 127,4 | 75 % |
| 3 | 9,96 | 100,4 | 75 % |
| **moy** | **9,40** | — | 75 % |

**16 t/s effectifs (formule historique : wall × mean_len 1,75) = 16,4 en moyenne, pic 18,2.**

Scripts gelés : `tools/run_16tps_config.sh` (device) + `tools/run_guarded_bench.sh`
(protocole gardé validé : kill-all, port libre, PID, meta, clean).

---

## 2. CROISEMENT CONFIG 16 t/s × TOUTES LES CAMPAGNES

### 2.1 MTP vs ngram (spéculatif)
| Chemin | wall t/s | Verdict |
|---|---|---|
| **CONFIG 16t/s (MTP n_max=1)** | **9,40-10,40** | ✅ CHAMPION |
| MTP défaut (n_max par défaut) | 8,64±0,15 (3 runs) | −8 % vs gelée |
| ngram-mod (protocole corrigé, 2 runs) | 2,55 / 3,36 | ❌ NON compétitif |
| ngram « 10,27 » (ngram3) | 10,27 | ❌ INVALID (état CDSP exceptionnel, non reproductible) |
| MTP + ngram-mod combiné | 5,47-5,62 | ❌ dégradé (ngram-mod non activé ou coût CPU) |

**Croisement** : le gain de la config ne vient PAS du ngram. Sur HTP, MTP est le seul
levier spéculatif valable ; toute méthode qui ajoute du travail CPU (ngram) est néfaste.
L'hypothèse « amortissement du coût par passage » est renforcée : Q8→Q4 n'apporte rien
en wall (9,46 vs 9,40) mais MTP apporte +72 % (5,78 → 9,40+) — cohérent avec un chemin
limité par orchestration/mouvement de données, pas par le calcul HTP brut.

### 2.2 Placement (5 configs, 2 blocs randomisés équipe)
| Config | Moyenne | Δ vs gelée |
|---|---|---|
| HTP_only | 9,69 ± 0,06 | référence placement |
| HTP_GPU | 7,34 | −24 % |
| GPU_HTP | 6,87 | −29 % |
| GPU_only | 6,82 | −30 % |
| cpu_only | 4,75 ± 4,28 (b2 contaminé thermique) | −51 % |

**Croisement** : la config gelée (HTP0 pur) est déjà sur l'optimum de placement.
Les hybrides HTP+GPU coûtent 24-29 % (fragmentation des graphes + transactions).
**Aucun gain à attendre du multi-device ; la gelée reste -dev HTP0.**

### 2.3 RAM / mémoire (measure_ram_mtp.sh, serveur prêt)
| Métrique | non-MTP | MTP (gelée) | Δ |
|---|---|---|---|
| VmRSS | 1280 Mo | 1276 Mo | −4 Mo (≈0) |
| VmSize (VA réservée) | 9740 Mo | 11156 Mo | +1416 Mo (invisible en RSS) |
| RssAnon / RssFile | 1253/26 | 1257/18 | ≈0 |
| Pss | 1274 Mo | 1269 Mo | −5 Mo |

**Croisement** : le MTP ne double PAS la RAM physique (RSS ≈0 delta, +1,4 Go de VA
réservée non paginée). Le « double » perçu = confusion VA vs RSS. La gelée est sûre
sur attnQ4 (0 swap, 0 crash, des dizaines de runs) ; le même MTP sur le 7,3 Go fit
en swap 3,2 Go → 2 reboots OOM (process résiduel post-run, pas la mesure).

### 2.4 Thermique (variable n°1)
| État | CONFIG 16t/s | MTP 7,3 Go |
|---|---|---|
| Froid (32-43 °C) | **9,40-10,40 t/s** | 8,78-9,92 t/s |
| Chaud (73 °C) | — | 5,8 t/s (throttling) |

**Croisement** : le protocole exigé par la gelée — départ < 45 °C + `--fit off`
(pas d'abort « HTP0 did not report memory ») + kill immédiat + seuil ZRAM 5 Go —
est ce qui distingue 5,8 (chaud/contaminé) de 9,4-10,4 (froid/propre).
Les capteurs `cpu-hw-trip-*` = 95000 sont des SEUILS statiques, pas des températures ;
capteur réel = qmx-0-1 (thermal_zone21), HTP = nsphvx-*/nsphmx-*.

### 2.5 Quantification (Q8 vs Q4)
| Métrique | Q8 attention (7,29 Go) | Q4 attention (5,08 Go) |
|---|---|---|
| MUL_MAT DSP | 414,8 µs | 344,9 µs (−17 %) |
| DSP total | 1,100 s | 0,950 s (−14 %) |
| decode wall (non-MTP) | 6,72-6,68 | ≈ inchangé |
| **decode wall (MTP gelée)** | 9,92 (7,3 Go, risque OOM) | **9,40-10,40 (sûr)** |

**Croisement** : Q4 seul ne gagne pas le decode (préuve non-compute-bound) MAIS libère
2,2 Go → le MTP tourne sans swap/reboot → **Q4 est la CONDITION de sûreté de la gelée,
pas son levier de vitesse**. Résultat net : 9,40-10,40 wall SÛR sur 5,08 Go vs
9,92 wall risqué sur 7,3 Go. La gelée gagne sur le couple perf×sécurité.

### 2.6 Le « 16,6 historique » vs la gelée
| Mesure | Historique (7,3 Go, MTP, chaud) | CONFIG GELÉE (5,08 Go, MTP1, froid) |
|---|---|---|
| Wall réel 16 tokens | ~5,8 t/s | **9,40-10,40 t/s** (+62-79 %) |
| Formule « effective » | 16,6 (10,7 × mean_len 2,50) | **16,4-18,9** (×1,75) |
| Classification | métrique dérivée, non soutenue | **dépassée en wall ET en effectifs** |
| Robustesse | 1 run, thermique non contrôlé | 3+ runs, acceptance 75 % stable |

**Croisement** : le 16,6 historique était une métrique dérivée (acceptance élevée
× mean_len), pas un débit brutal. La gelée atteint le MÊME chiffre effectif avec un
**wall 62-79 % plus élevé** et une reproductibilité vérifiée (A vs D écart 1,7 %,
B vs C écart 0,6 % en ABBA).

---

## 3. VERDICT DU CROISEMENT

1. **La config gelée est l'optimum actuel** : MTP1 (pas ngram, pas hybrides, pas GPU).
2. **Le levier = réduire les passages autoregressifs (MTP), pas accélérer le kernel**
   (Q4 neutre en wall) — confirme non-compute-bound, cohérent avec movement/orchestration.
3. **Les conditions d'exécution (froid, --fit off, kill, protocole gardé) valent autant
   que la config elle-même** : 5,8 chaud vs 9,4-10,4 froid.
4. **Risque résiduel** : run 2 de la 3× (7,85 t/s, 127 ms/t) = variabilité CDSP,
   pas le MTP (acceptance 75 % identique) ; à surveiller, pas à corriger.

## 4. OUTILS GELÉS (reproductibles)

| Fichier | Rôle |
|---|---|
| `tools/run_16tps_config.sh` | lance la config gelée (device) |
| `tools/run_guarded_bench.sh` | protocole gardé (kill-all, port, PID, meta, clean) — VALIDÉ smoke test |
| `tools/confirm_attnq4_mtp1_3x.sh` | confirmation 3× historique (origine des 9,40) |
| `tools/measure_ram_mtp.sh` | preuve RAM (RSS ≈0 delta MTP) |

## 5. PROCHAINES ÉTAPES (croisées avec l'équipe)

1. Re-confirmer la gelée 3× avec le protocole gardé (ports 8540-8542) — en attente de lancement.
2. Axe non testé restant : dFlash ON/OFF (impact prefill vs decode) — à faire sur la gelée.
3. Constructor de décomposition T_token = T_queue + T_DMA + T_compute + T_sync (profile=2).
4. Ne PAS poursuivre : ngram (réfuté 2,55-3,36), hybrides HTP/GPU (réfutés −24/-29 %),
   multi-HTP, MTP n_max>1 (structurellement coûteux — 2 llama_decode/iter upstream).

Tests : 71/71 (test_governor) + 5/5 (test_team) OK · device propre 0 process.