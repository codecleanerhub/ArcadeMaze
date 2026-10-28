## shot_task82_gems.gd — TASK 82 (richiesta utente: "Rimpiccioliamo le gemme
## (rubino rosso, blu) del 30%").
##
## Harness QA: un MAZE REALE (Maze.generate + Maze._draw, il vero percorso
## di rendering delle celle-tesoro) con i 5 tipi di tesoro piazzati in 5 celle
## libere adiacenti: GEM e RUBY devono risultare ~30% più piccoli di
## corona/oro/forziere (73.6px -> 51.5px). Sotto: le versioni COLLECTIBLE
## da raccogliere (48px -> 33.6px) tramite il vero Collectibles._draw().
##
## Avvio (Xvfb):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task82_gems.tscn
extends Node2D

const MazeClass = preload("res://scripts/core/Maze.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")
const C = preload("res://scripts/core/GameConstants.gd")

const KIND_TREASURE := 4  # Collectibles.Kind.TREASURE (MINE=0, CHALICE=1, SCEPTER=2, BOOTS=3, TREASURE=4)

var t: float = 0.0
var maze: Node2D = null
var collectibles: Array = []
var captured: bool = false
var placed_cells: Array = []


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var bg := ColorRect.new()
        bg.color = Color(0.06, 0.05, 0.08)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)

        _label(Vector2(960, 30),
                        "TASK 82 — GEMME E RUBINO -30% (corona/oro/forziere invariati)",
                        30, true, Color(0.94, 0.88, 0.72))
        _label(Vector2(960, 70),
                        "Riga maze (cella 64px): tesori 'padre' 73.6px; GEM e RUBY attesi a ~51.5px. Riga sotto: collectible 48px; GEM/RUBY attesi a ~33.6px",
                        20, true, Color(0.7, 0.8, 0.9))

        # ---- MAZE reale con 5 tesori forzati in celle adiacenti ------------
        maze = MazeClass.new()
        maze.level = 1
        add_child(maze)
        maze.generate(1)
        placed_cells = _force_treasure_row()
        print("[GEMS] celle tesoro forzate: ", placed_cells)
        maze.position = Vector2(64.0, 110.0)
        maze.needs_redraw = true
        maze.queue_redraw()

        # ---- Collectibles (versione da raccogliere) ------------------------
        var names := ["CORONA", "ORO", "FORZIERE", "GEMMA (blu)", "RUBINO (rosso)"]
        var types := [C.TreasureType.CROWN, C.TreasureType.GOLD, C.TreasureType.CHEST,
                        C.TreasureType.GEM, C.TreasureType.RUBY]
        for i in 5:
                var col := CollectiblesClass.new()
                col.kind = KIND_TREASURE
                col.treasure_type = int(types[i])
                col.active = true
                col.pos = Vector2(280.0 + i * 340.0, 880.0)
                add_child(col)
                collectibles.append(col)
                _label(Vector2(280.0 + i * 340.0, 960.0), names[i], 20, true,
                                Color(0.85, 0.82, 0.75))


## Trova 5 celle EMPTY adiacenti nella stessa riga e forza i 5 tipi tesoro.
## Fallback: 5 celle EMPTY qualsiasi (sparse).
func _force_treasure_row() -> Array:
        var cols: int = C.MAZE_COLS
        var rows: int = C.MAZE_ROWS
        var cells_used: Array = []
        # cerca 5 celle libere consecutive
        for r in range(1, rows - 1):
                var run_start: int = -1
                var run_len: int = 0
                for c_ in range(1, cols - 1):
                        if maze._get_cell_type(c_, r) != C.CellType.WALL:
                                if run_len == 0:
                                        run_start = c_
                                run_len += 1
                                if run_len >= 5:
                                        cells_used = [
                                                Vector2i(run_start, r),
                                                Vector2i(run_start + 1, r),
                                                Vector2i(run_start + 2, r),
                                                Vector2i(run_start + 3, r),
                                                Vector2i(run_start + 4, r),
                                        ]
                                        break
                        else:
                                run_len = 0
                if not cells_used.is_empty():
                        break
        if cells_used.is_empty():
                # fallback: 5 celle libere sparse
                for r in range(1, rows - 1):
                        for c_ in range(1, cols - 1):
                                if maze._get_cell_type(c_, r) != C.CellType.WALL:
                                        cells_used.append(Vector2i(c_, r))
                                        if cells_used.size() >= 5:
                                                break
                        if cells_used.size() >= 5:
                                break
        var types := [C.TreasureType.CROWN, C.TreasureType.GOLD, C.TreasureType.CHEST,
                        C.TreasureType.GEM, C.TreasureType.RUBY]
        for i in cells_used.size():
                maze._grid[maze._idx(cells_used[i].x, cells_used[i].y)]["treasure"] = int(types[i])
                maze._grid[maze._idx(cells_used[i].x, cells_used[i].y)]["weapon"] = {}
        return cells_used


func _label(at: Vector2, text: String, size: int, bold: bool, col: Color) -> void:
        var l := Label.new()
        l.text = text
        l.position = at - Vector2(0, size)
        l.add_theme_font_size_override("font_size", size)
        l.add_theme_color_override("font_color", col)
        if bold:
                l.add_theme_font_override("font", ThemeDB.fallback_font)
        add_child(l)


func _process(delta: float) -> void:
        t += delta
        maze._anim_time += delta * 1000.0
        maze.queue_redraw()
        for col in collectibles:
                col.anim_time += delta * 1000.0
                col.queue_redraw()
        if t > 1.6 and not captured:
                captured = true
                var img := get_viewport().get_texture().get_image()
                img.save_png("/home/z/my-project/download/task82_gems.png")
                print("[SHOT] salvato task82_gems.png")
                get_tree().quit(0)
