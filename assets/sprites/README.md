# Sprites generati per il bestiary fantasy horror

Questa cartella contiene gli spritesheet PNG 384x256 (6x4 frame a 64x64)
per le creature del gioco, generati tramite `z-ai-web-dev-sdk` (skill
`image-generation`) e poi ridimensionati + palette 16 colori applicata.

## Contenuto (22 creature)

19 mostri + 3 boss. Mancano all'appello:
- `monster_014` (Vampiro Minore): non e' mappato nel codice C++.
- 7 boss (GOLEM, LICH, DEMON, ABOMINATION, DRAGON, WRAITH_LORD, BEHOLDER):
  non hanno controparte nel file `prompt_game_reference.txt` e usano
  il fallback a primitive SFML.

## File per creatura

- `<id>_sheet.png` - spritesheet 384x256 RGBA (6 colonne x 4 righe)
- `<id>_meta.json` - metadata (dimensioni, anchor, animazioni)

## Animazioni

Ogni spritesheet ha 4 righe:

| Riga | Animazione | Frame | Durata (ms) |
|------|------------|-------|-------------|
| 0    | idle       | 4     | 200         |
| 1    | walk       | 6     | 100         |
| 2    | attack     | 6     | 100         |
| 3    | death      | 6     | 120         |

Ancora dei piedi: (32, 56) su frame 64x64.

## Rigenerazione

Per rigenerare gli sprite usa gli script in `../scripts/`:

```bash
# Genera tutti gli sprite (22 creature, ~10-15 min con rate limit)
python3 ../scripts/generate_sprites.py

# Riprova solo quelli falliti
python3 ../scripts/generate_sprites_retry.py

# Genera una singola creatura
python3 ../scripts/generate_sprites.py --only monster_001
```

Richiede `z-ai-web-dev-sdk` (CLI `z-ai`) e Python con Pillow + numpy.
