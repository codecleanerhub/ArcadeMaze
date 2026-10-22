# Rollback Plan — PixelLab v2 (boss + player + arena regeneration)

## Scope
Sostituzione asset sprite (XHD 256px + SD 64px + meta json) di:
- 17 boss (boss_021..boss_037)
- 9 personaggi giocanti (player1, player2, char_mage/orc/elf/knight/golem/dragon/vampire)
- Elementi architettonici della boss room (solo se credito residuo)

Il codice runtime cambia SOTO in modo backward-compatible (vedi §4).

## Restore points (3 livelli)

### L1 — Tag git (rollback TUTTO)
Tag `pixellab-v2-start` sul commit `6b0dba9` (stato pre-operazione).
```bash
git fetch origin
git reset --hard pixellab-v2-start   # WARNING: buttare via TUTTO il lavoro v2
git push origin +engine/godot-engine
```

### L2 — Commit per milestone (rollback SELETTIVO)
Ogni integrazione è un commit separato con prefisso `feat(pixellab-v2)`:
- `feat(pixellab-v2): lich attack`        — solo LICH
- `feat(pixellab-v2): golem completo`     — solo GOLEM
- `feat(pixellab-v2): boss batch 1..N`    — gruppi di boss
- `feat(pixellab-v2): players`            — i 9 player
- `feat(pixellab-v2): arena architecture` — elementi architettonici
```bash
git revert <commit>                       # inverte SOLO quel milestone
```

### L3 — Backup file (rollback SINGOLO asset, senza git)
Prima di toccare un asset, l'integratore crea `<file>.bak-pre-pixellab-v2`.
I boss già ritoccati nel Task 46/47 hanno anche `.bak-pre-pixellab` (originali 2024).
```bash
cp assets/sprites/boss_033_sheet.png.bak-pre-pixellab-v2  assets/sprites/boss_033_sheet.png
# XHD, SD, meta: stesso schema (godot/ e legacy/)
```
I backup NON vengono mai cancellati dall'integratore.

## Flag runtime (rollback istantaneo senza toccare file)
- `BOSS_FRAME_ANIM_ENABLED = false` in `godot/scripts/core/GameConstants.gd`
  → tutti i boss tornano al cycling legacy / frame 0 statico.
- I meta json tornano a columns/rows coerenti coi backup ripristinati.

## Procedura di verifica post-rollback
1. `godot --headless --import --path godot` (exit 0)
2. `godot --headless --quit --path godot` (boot pulito)
3. `tests/test_boss_arena.tscn` (59 check) + `tests/test_2p_bossroom.tscn`
4. Screenshot `tests/shot_boss_pixellab.tscn` — verificare sheet cols/rows nel log

## Cosa NON cambia (sicurezza intrinseca)
- Hitbox, anchor (32,56), dimensioni frame SD 64px: invariati.
- Nomi file e struttura meta: stessi campi, solo values aggiornati.
- Le cartelle `scripts/pixellab_v2/` (pipeline + state) restano nel workspace,
  fuori dal repo: nessun impatto sul gioco.

## Costi già sostenuti (non recuperabili)
Le generazioni PixelLab consumate per produrre gli asset v2. Il rollback
ripristina solo gli asset del gioco, non i crediti.
