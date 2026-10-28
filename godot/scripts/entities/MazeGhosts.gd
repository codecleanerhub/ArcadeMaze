## MazeGhosts.gd - TASK 81.1: FANTASMI LENZUOLO del labirinto.
## ============================================================
## Meccanica (richiesta utente):
##   * Fantasmi di colore BIANCO, ROSSO e VERDE trasparente, in stile
##     classico lenzuolo con occhi e bocca, che fluttuano a mezz'aria.
##   * Escono da un muro del labirinto in tempi casuali, attraversano e
##     arrivano all'estremita' successiva del muro, compenstrandosi nella
##     roccia e sparendo.
##   * Sono IMMORTALI e INNOCUI: il player li attraversa senza subire
##     danno ("li puo' saltare"), i proiettili passano attraverso. Non
##     collidono con nulla: sono pura atmosfera da dungeon.
##   * La volta successiva respawnano da un ALTRO muro: ogni fantasma ha
##     un budget di 3 apparizioni su 3 MURI DIVERSI, poi non appare piu'.
##   * Fino a 4 fantasmi simultanei; la probabilita' che siano 4 in
##     schermo aumenta col livello (GameConstants.ghost_allowed_simultaneous).
##
## Rendering: sheet PixelLab 256x64 (4 frame di float) per colore,
## env/ghost_sheet_{white,red,green}.png — bianco nativo + rosso/verde
## tint per-canale (pattern 61b, task81_integrate.py). Un solo nodo con
## _draw() unico per tutti i fantasmi attivi (1 canvas item, costo minimo);
## il nodo sta DOPO Collectibles in MainGame.tscn cosi' i lenzuoli
## fluttuano SOPRA muri, player e nemici ("a mezz'aria").
##
## Movimento: il fantasma percorre la mezzeria del segmento WALL scelto
## (run orizzontale o verticale di 2..8 celle), da un'estremita' all'altra.
## Emergere/affondare = ramp di alpha sui primi/ultimi 28px, cosi' il
## lenzuolo "spunta" dalla roccia e ci si ricompentra dentro.
## ============================================================
extends Node2D
class_name MazeGhosts

const C = preload("res://scripts/core/GameConstants.gd")

# Dimensione rendering del lenzuolo: sotto i nemici (78px, gerarchia
# sprite: player 83 > miniboss 82 > nemici 78 > tesori 73.6) per non
# coprire il gameplay, sopra i muri che attraversa.
const GHOST_DRAW_SIZE: float = 72.0
# Lunghezza (px) dei ramp di comparsa/sparizione nel muro.
const EMERGE_LEN_PX: float = 28.0
# Durata frame dello sheet di float (4 frame).
const FRAME_MS: int = 150

# --- Sheet PixelLab (cache static: 3 upload GPU a vita) ---
static var _sheet_cache: Dictionary = {}  # color key -> Texture2D
static var _sheet_tried: bool = false

const COLORS: Array = ["white", "red", "green"]

# --- Stato del sistema ---
var _level: int = 1
var _time_ms: float = 0.0
var _ghosts: Array = []  # dizionari-stato per fantasma
var _runs: Array = []  # segmenti WALL attraversabili
var _rng := RandomNumberGenerator.new()


## Carica (una volta) gli sheet dei 3 colori. Null = fallback: il fantasma
## non disegna lo sprite (ma la logica continua: e' atmosfera, non gameplay).
static func _get_sheet(color: String) -> Texture2D:
        if _sheet_cache.has(color):
                return _sheet_cache[color]
        if not _sheet_tried:
                _sheet_tried = true
                for col in ["white", "red", "green"]:
                        var path := "res://assets/sprites/env/ghost_sheet_%s.png" % col
                        if FileAccess.file_exists(path):
                                var img := Image.load_from_file(path)
                                if img != null:
                                        _sheet_cache[col] = ImageTexture.create_from_image(img)
        return _sheet_cache.get(color)


## Genera il pool fantasmi per il livello. Chiamato da
## MainGameController.start_level() dopo maze.generate(). RNG seedato sul
## livello (gli orari degli spawn si ripetono al continue, pattern hazards).
func generate(lvl: int, maze: Node) -> void:
        _ghosts.clear()
        _runs.clear()
        _level = lvl
        _time_ms = 0.0
        if not C.GHOSTS_ENABLED:
                queue_redraw()
                return
        _rng.seed = hash("mghosts_v1_%d" % lvl)
        _collect_wall_runs(maze)
        if _runs.is_empty():
                queue_redraw()
                return
        # Pool: bianco, rosso, verde + un quarto colore random (richiesta:
        # "fino a 4 fantasmi contemporaneamente" = pool di 4 lenzuoli).
        var pool_colors: Array = ["white", "red", "green"]
        pool_colors.append(COLORS[_rng.randi() % COLORS.size()])
        for i in range(mini(C.GHOST_POOL_SIZE, pool_colors.size())):
                _ghosts.append({
                        "color": pool_colors[i],
                        "appearances_left": C.GHOST_MAX_APPEARANCES,
                        "used_run_keys": [],
                        # prima uscita scaglionata: 1.5-4s dall'avvio livello
                        "next_spawn_ms": _rng.randf_range(
                                        C.GHOST_FIRST_SPAWN_MIN_MS, C.GHOST_FIRST_SPAWN_MAX_MS),
                        # stato attraversamento (valido solo se active)
                        "active": false,
                        "pos": Vector2.ZERO,
                        "dir": Vector2.RIGHT,
                        "travel_left": 0.0,
                        "travel_total": 0.0,
                        "phase": _rng.randf() * TAU,  # fase bob indipendente
                })
        queue_redraw()


## Scansione dei segmenti WALL contiguous (orizzontali e verticali) di
## lunghezza GHOST_RUN_MIN..MAX_CELLS. I muri di bordo (15-30 celle) restano
## fuori dal cap; le lastre mobili del Task 30 spezzano i segmenti; le
## celle con la torcia (hash [14,19) in Maze._spawn_torch_lights) restano
## valide — il lenzuolo fluttua SOPRA la fiamma, non la tocca.
func _collect_wall_runs(maze: Node) -> void:
        if maze == null:
                return
        # orizzontali
        for r in range(C.MAZE_ROWS):
                var run_start: int = -1
                for c in range(C.MAZE_COLS + 1):
                        var is_wall_cell: bool = c < C.MAZE_COLS \
                                        and maze.is_wall(c, r) \
                                        and not maze.dynamic_walls.has("%d,%d" % [c, r])
                        if is_wall_cell and run_start < 0:
                                run_start = c
                        elif not is_wall_cell and run_start >= 0:
                                _push_run(maze, run_start, c - 1, r, true)
                                run_start = -1
        # verticali
        for c in range(C.MAZE_COLS):
                var run_start: int = -1
                for r in range(C.MAZE_ROWS + 1):
                        var is_wall_cell: bool = r < C.MAZE_ROWS \
                                        and maze.is_wall(c, r) \
                                        and not maze.dynamic_walls.has("%d,%d" % [c, r])
                        if is_wall_cell and run_start < 0:
                                run_start = r
                        elif not is_wall_cell and run_start >= 0:
                                _push_run(maze, c, run_start, r - 1, false)
                                run_start = -1


func _push_run(_maze: Node, c0: int, c1: int, r: int, horizontal: bool) -> void:
        var len_cells: int = (c1 - c0) + 1
        if len_cells < C.GHOST_RUN_MIN_CELLS or len_cells > C.GHOST_RUN_MAX_CELLS:
                return
        var key: String = ("h%d,%d-%d" % [r, c0, c1]) if horizontal \
                        else ("v%d,%d-%d" % [c0, r, c1])
        var cells: Array = []
        for i in range(len_cells):
                cells.append(Vector2i(c0 + i, r) if horizontal else Vector2i(c0, r + i))
        _runs.append({
                "key": key,
                "cells": cells,
                "horizontal": horizontal,
        })


## Update del sistema (chiamato da MainGameController._update_playing).
func update_ghosts(delta_ms: float) -> void:
        _time_ms += float(delta_ms)
        if _ghosts.is_empty():
                return
        var active_count: int = _count_active()
        var step_px: float = C.GHOST_SPEED_PX_S * float(delta_ms) * 0.001
        for g in _ghosts:
                if g["active"]:
                        _advance_crossing(g, step_px)
                        continue
                # IDLE: budget esaurito -> ritirato per sempre
                if g["appearances_left"] <= 0:
                        continue
                g["next_spawn_ms"] -= float(delta_ms)
                if g["next_spawn_ms"] > 0.0:
                        continue
                # cap simultaneo probabilistico (sale col livello)
                if active_count >= 1 \
                                and active_count >= C.ghost_allowed_simultaneous(_level):
                        # spawn rimandato: riprova tra poco
                        g["next_spawn_ms"] = _rng.randf_range(1200.0, 2500.0)
                        continue
                if _launch_crossing(g):
                        active_count += 1
        queue_redraw()


func _count_active() -> int:
        var n: int = 0
        for g in _ghosts:
                if g["active"]:
                        n += 1
        return n


## Sceglie un segmento NON ancora usato da questo fantasma e lancia
## l'attraversamento in una delle due direzioni (random). Ritorna false se
## non ci sono segmenti nuovi (fantasma ritirato in anticipo, caso limite).
func _launch_crossing(g: Dictionary) -> bool:
        var candidates: Array = []
        for run in _runs:
                if not (g["used_run_keys"] as Array).has(run["key"]):
                        candidates.append(run)
        if candidates.is_empty():
                g["appearances_left"] = 0
                return false
        var run: Dictionary = candidates[_rng.randi() % candidates.size()]
        var cells: Array = run["cells"]
        var from_a: bool = _rng.randi() % 2 == 0
        var first: Vector2i = cells[0] if from_a else cells[cells.size() - 1]
        var last: Vector2i = cells[cells.size() - 1] if from_a else cells[0]
        var start: Vector2 = Vector2(
                        first.x * C.TILE_SIZE + C.TILE_SIZE * 0.5,
                        C.UI_HEIGHT + first.y * C.TILE_SIZE + C.TILE_SIZE * 0.5)
        var end: Vector2 = Vector2(
                        last.x * C.TILE_SIZE + C.TILE_SIZE * 0.5,
                        C.UI_HEIGHT + last.y * C.TILE_SIZE + C.TILE_SIZE * 0.5)
        var travel: float = start.distance_to(end)
        if travel < 1.0:
                return false
        g["active"] = true
        g["pos"] = start
        g["dir"] = (end - start).normalized()
        g["travel_total"] = travel
        g["travel_left"] = travel
        g["run_key"] = run["key"]
        return true


## Avanza l'attraversamento; alla fine consuma un'apparizione e segna il
## muro come usato ("la volta successiva respawnano da un altro muro").
func _advance_crossing(g: Dictionary, step_px: float) -> void:
        g["travel_left"] = maxf(0.0, g["travel_left"] - step_px)
        g["pos"] = g["pos"] + g["dir"] * step_px
        var traveled: float = g["travel_total"] - g["travel_left"]
        if traveled >= g["travel_total"]:
                g["active"] = false
                g["appearances_left"] -= 1
                (g["used_run_keys"] as Array).append(g["run_key"])
                if g["appearances_left"] > 0:
                        g["next_spawn_ms"] = C.ghost_spawn_interval_ms(_level)
                g["pos"] = Vector2.ZERO


func _draw() -> void:
        if _ghosts.is_empty():
                return
        var t: float = _time_ms * 0.001
        for g in _ghosts:
                if not g["active"]:
                        continue
                var tex: Texture2D = _get_sheet(g["color"])
                if tex == null:
                        continue
                var traveled: float = g["travel_total"] - g["travel_left"]
                # alpha: ramp di comparsa/sparizione nel muro (i primi/ultimi
                # 28px), al centro pulsazione spettrale attorno a 0.72.
                var alpha: float
                if traveled < EMERGE_LEN_PX:
                        alpha = traveled / EMERGE_LEN_PX
                elif g["travel_left"] < EMERGE_LEN_PX:
                        alpha = g["travel_left"] / EMERGE_LEN_PX
                else:
                        alpha = 1.0
                alpha *= 0.72 + 0.06 * sin(t * 2.6 + g["phase"])
                alpha = clampf(alpha, 0.0, 1.0)
                # fluttuazione a mezz'aria
                var bob_y: float = sin(t * 2.2 + g["phase"]) * 4.0
                var sway_x: float = sin(t * 1.5 + g["phase"] * 0.7) * 2.0
                var frame: int = (int(_time_ms) / FRAME_MS) % 4
                var src := Rect2(float(frame) * 64.0, 0.0, 64.0, 64.0)
                var dst := Rect2(
                                g["pos"].x - GHOST_DRAW_SIZE * 0.5 + sway_x,
                                g["pos"].y - GHOST_DRAW_SIZE * 0.5 + bob_y,
                                GHOST_DRAW_SIZE, GHOST_DRAW_SIZE)
                draw_texture_rect_region(tex, dst, src, Color(1.0, 1.0, 1.0, alpha), false, false)


# ============================================================================
# API di introspezione (per i test headless tests/test_maze81.gd)
# ============================================================================
func ghost_count() -> int:
        return _ghosts.size()


func active_count() -> int:
        return _count_active()


func appearances_left(color: String) -> int:
        for g in _ghosts:
                if g["color"] == color:
                        return int(g["appearances_left"])
        return -1


func total_appearances_left() -> int:
        var n: int = 0
        for g in _ghosts:
                n += int(g["appearances_left"])
        return n


func used_run_keys_of(color: String) -> Array:
        for g in _ghosts:
                if g["color"] == color:
                        return g["used_run_keys"]
        return []


func run_count() -> int:
        return _runs.size()
