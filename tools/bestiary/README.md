# Fantasy Horror Bestiary - Asset Tooling

Questa cartella contiene gli script Python per generare gli sprite PNG delle
30 creature (20 mostri + 10 boss) usate dal gioco `ArcadeMazeFantasy`.

## File

| File | Scopo |
|------|-------|
| `prompt_game_reference.txt` | Specifica originale (prompts + descrizioni creature) |
| `generate_and_assemble.py`  | Genera i prompt testuali, (opzionale) chiama API immagini, applica palette 16 colori, assembla spritesheet 6x4 |
| `build_bestiary_package.py` | Versione piu' completa: 660 prompt + manifest JSON + cartelle + `fantasy_horror_bestiary.zip` |

## Workflow

1. **Genera i prompt** (nessuna dipendenza oltre a Python stdlib):
   ```bash
   python3 generate_and_assemble.py
   ```
   Questo crea `prompts/*.txt` (660 file) e `output/<creature_id>/*` (vuoto).

2. **(Opzionale) Genera i PNG tramite API AI**:
   - Implementa la funzione `call_image_api(prompt_path, out_png_path)` in uno dei due script per integrare il tuo servizio (Stable Diffusion, Midjourney, ...).
   - Lancia `python3 generate_and_assemble.py` con `generate_images=True` in `main()`.

3. **Applica la palette 16 colori**:
   - Avviene automaticamente dentro `verify_and_apply_palette()` se `generate_images=True`.
   - Per applicarla a PNG gia' esistenti, usa `apply_palette.py` (vedi `../../scripts/`).

4. **Assembla spritesheet**:
   - Avviene automaticamente. Lo script produce `<creature_id>_sheet.png` (6x4 frame) e `<creature_id>_meta.json`.

## Animazioni

Ogni creatura ha 4 animazioni, ciascuna su una riga dello spritesheet 6x4:

| Animazione | Riga | Frame | Durata (ms) |
|------------|------|-------|-------------|
| idle       | 0    | 4     | 200         |
| walk       | 1    | 6     | 100         |
| attack     | 2    | 6     | 100         |
| death      | 3    | 6     | 120         |

Totale: 22 frame per creatura × 30 creature = **660 PNG**.

## Palette 16 colori

```
#0C0C0C  #302824  #605048  #A08070
#C8B4A0  #788CA0  #507864  #28503C
#A02828  #C85050  #DCA028  #C8C850
#78C8C8  #50A0DC  #A078C8  #F0F0F0
```

Tono dominante: grigi/marroni scuri per interni dungeon; accenti rossi/oro per
carne/sangue; ciano/blu per spiriti/magia. Coerente con il mood fantasy horror.

## Integrazione nel gioco C++

Lo sprite sheet generato viene caricato da `SpriteSheet` (vedi
`../../src/SpriteSheet.h`). Il mapping creature->enum e' in
`../../src/Enemy.cpp` e `../../src/Boss.cpp`.

Quando un PNG non esiste, il gioco fa fallback al disegno a primitive SFML
(rettangoli/cerchi) gia' presente nel codice: il gioco e' sempre giocabile
anche senza asset.

## Note

- Lo script originale del file `prompt game.txt` e' stato adattato: rimosse
  le virgolette italiane nel nome del boss_030 ("Profondità" -> "Profondita'")
  per evitare problemi di encoding.
- `call_image_api()` e' un placeholder: solleva `NotImplementedError`. Per
  generare le immagini automaticamente usa `../../scripts/generate_sprites.py`
  che sfrutta `z-ai-web-dev-sdk`.
