## test_task85_walls.gd — TASK 85: test runtime della correzione "blocchi
## muro con angolo scuro" (feedback utente: "tutti i blocchi come quelli col
## segno blu, senza pezzi con sfumatura d'angolo").
##
## Root cause: _render_wall_cell selezionava la finestra 64x64 della texture
## rock_texture.png (128x128, UN masso centrato con giunzioni scure ai bordi)
## su una griglia {0,32,64}²: 8 finestre su 9 tagliavano le giunzioni scure
## → blocchi con porzione scura "a sfumatura d'angolo" (83% delle celle muro).
## Fix: selezione ristretta a _ROCK_CLEAN_WINDOWS (finestre "masso completo",
## quadranti uniformi, luminanza ~61 = look dei blocchi OK).
##
## Check:
##   A — la costante _ROCK_CLEAN_WINDOWS esiste, non vuota, finestre in-bounds
##   B — ogni finestra pulita ha quadranti UNIFORMI (qRange tinted <= 8)
##       e luminanza media 60-61 (±3): il look dei blocchi "segno blu"
##   C — sanity texture: sulla VECCHIA griglia {0,32,64}² almeno 6 finestre
##       su 9 hanno qRange >= 12 (il problema esisteva davvero su QUESTA
##       texture — se la texture cambia, il test fallisce e va riscansionato)
##   D — il sorgente Maze.gd non contiene più la vecchia formula griglia
##       e usa la lista delle finestre pulite (guardia di regressione)
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MazeScript = preload("res://scripts/core/Maze.gd")

const ROCK_PATH := "res://assets/sprites/env/rock_texture.png"
const MAZE_SRC := "res://scripts/core/Maze.gd"
# luminanza del wall_color palette 0 (grey cavern 0.294,0.275,0.255)
const BASE_LUM := 0.275
const TEX_SIZE := 128
const WIN := 64


func _ready() -> void:
        var fails: int = 0

        # --- A: costante finestre pulite ---
        var wins: Array = MazeScript._ROCK_CLEAN_WINDOWS
        if wins.is_empty():
                print("[TEST] FALLITO A: _ROCK_CLEAN_WINDOWS vuota")
                fails += 1
        for w in wins:
                if w.x < 0 or w.y < 0 or w.x + WIN > TEX_SIZE or w.y + WIN > TEX_SIZE:
                        print("[TEST] FALLITO A: finestra fuori bounds ", w)
                        fails += 1
        if fails == 0:
                print("[TEST] OK A: %d finestre pulite, tutte in-bounds 128x128" % wins.size())

        # --- B/C: analisi texture (stessa pipeline del gioco) ---
        var img := Image.new()
        var abs_path: String = ProjectSettings.globalize_path(ROCK_PATH)
        if img.load(abs_path) != OK:
                print("[TEST] FALLITO B: impossibile caricare rock_texture.png")
                get_tree().quit(1)
                return
        if img.get_width() != TEX_SIZE or img.get_height() != TEX_SIZE:
                print("[TEST] FALLITO B: texture %dx%d attesa 128x128" % [
                                img.get_width(), img.get_height()])
                get_tree().quit(1)
                return

        var q_range := func(ox: int, oy: int) -> float:
                # media luminanza tinteggiata per quadrante (palette 0)
                var quads: Array[float] = [0.0, 0.0, 0.0, 0.0]
                var counts: Array[int] = [0, 0, 0, 0]
                for y in range(oy, oy + WIN):
                        for x in range(ox, ox + WIN):
                                var col: Color = img.get_pixel(x, y)
                                var lum: float = col.r * 0.299 + col.g * 0.587 + col.b * 0.114
                                var t: float = 0.25 + lum * 1.20
                                var final_lum: float = BASE_LUM * 255.0 * t
                                var qi: int = int(y >= oy + 32) * 2 + int(x >= ox + 32)
                                quads[qi] += final_lum
                                counts[qi] += 1
                var means: Array[float] = []
                for qi in range(4):
                        means.append(quads[qi] / float(maxi(counts[qi], 1)))
                return means.max() - means.min()

        var mean_lum := func(ox: int, oy: int) -> float:
                var tot: float = 0.0
                for y in range(oy, oy + WIN):
                        for x in range(ox, ox + WIN):
                                var col: Color = img.get_pixel(x, y)
                                var lum: float = col.r * 0.299 + col.g * 0.587 + col.b * 0.114
                                tot += 0.25 + lum * 1.20
                return BASE_LUM * 255.0 * (tot / float(WIN * WIN))

        # B: uniformita' + luminanza delle finestre pulite
        for w in wins:
                var qr: float = q_range.call(w.x, w.y)
                var ml: float = mean_lum.call(w.x, w.y)
                if qr > 8.0:
                        print("[TEST] FALLITO B: finestra (%d,%d) qRange=%.1f > 8" % [w.x, w.y, qr])
                        fails += 1
                if absf(ml - 60.5) > 3.0:
                        print("[TEST] FALLITO B: finestra (%d,%d) luminanza %.1f fuori 57.5-63.5" % [
                                        w.x, w.y, ml])
                        fails += 1
        if fails == 0:
                print("[TEST] OK B: tutte le finestre pulite hanno quadranti uniformi (qRange<=8) e luminanza ~61")

        # C: sanity — la vecchia griglia aveva davvero il problema
        var dirty_count: int = 0
        for oy in [0, 32, 64]:
                for ox in [0, 32, 64]:
                        if q_range.call(ox, oy) >= 12.0:
                                dirty_count += 1
        if dirty_count < 6:
                print("[TEST] FALLITO C: solo %d/9 finestre sporche sulla vecchia griglia (texture cambiata? riscansionare gli offset)" % dirty_count)
                fails += 1
        else:
                print("[TEST] OK C: vecchia griglia {0,32,64}² aveva %d/9 finestre con angolo scuro (root cause confermata)" % dirty_count)

        # --- D: guardia di regressione sul sorgente ---
        var src_file := FileAccess.open(MAZE_SRC, FileAccess.READ)
        if src_file == null:
                print("[TEST] FALLITO D: impossibile leggere Maze.gd")
                fails += 1
        else:
                var src: String = src_file.get_as_text()
                if src.contains("(h % 3) * 32"):
                        print("[TEST] FALLITO D: vecchia formula griglia {0,32,64}² ancora presente")
                        fails += 1
                if not src.contains("_ROCK_CLEAN_WINDOWS[h % _ROCK_CLEAN_WINDOWS.size()]"):
                        print("[TEST] FALLITO D: selezione da _ROCK_CLEAN_WINDOWS assente")
                        fails += 1
                if fails == 0:
                        print("[TEST] OK D: Maze.gd seleziona SOLO da _ROCK_CLEAN_WINDOWS")

        if fails > 0:
                print("[TEST] ==== TEST TASK 85 FALLITO (%d) ====" % fails)
                get_tree().quit(1)
                return
        print("[TEST] ==== TEST TASK 85 WALLS SUPERATO ====")
        get_tree().quit(0)
