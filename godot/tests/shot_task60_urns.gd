## shot_task60_urns.gd — TASK 60a: screenshot URNE PixelLab in-game.
##
## Verifica visiva delle 3 varianti (pietra/bronzo/marmo scuro) che
## sostituiscono il disegno procedurale _draw_urn di Maze.gd.
##
## Screenshot via --write-movie (lezione worklog: get_image() deadlcca
## sotto llvmpipe, MAI usarlo):
##   Xvfb :99 & DISPLAY=:99 godot --path . --resolution 1920x1080 \
##     --write-movie /home/z/my-project/scripts/task60_movie/f.png \
##     --fixed-fps 10 --quit-after 140 res://tests/shot_task60_urns.tscn
## Ogni variante occupa 2.5s (25 frame a 10fps): il frame usato per la
## verifica e' ~20 frame dopo l'inizio stage (camera assestata).
extends Node2D

const VARIANTS: Array[String] = ["stone", "bronze", "marble"]
const STAGE_T: float = 2.5

var main: Node2D = null
var stage: int = -1
var t: float = 0.0
var urn_cells: Dictionary = {}   # idx -> Vector2i (una cella per variante)
var urn_total: int = 0
var stage_frames: Dictionary = {} # idx -> frame iniziale dello stage


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        var scene := load("res://scenes/MainGame.tscn") as PackedScene
        main = scene.instantiate()
        add_child.call_deferred(main)


func _process(delta: float) -> void:
        if main == null or not main.is_node_ready():
                return
        # sicurezza: niente nemici durante lo shot.
        for e in main.spawner.enemies.duplicate():
                if is_instance_valid(e):
                        e.queue_free()
        main.spawner.enemies.clear()
        if stage < 0:
                _scan_urns()
                stage = 0
                t = 0.0
                stage_frames[0] = Engine.get_frames_drawn()
                print("[URN60] STAGE 0 (", VARIANTS[0], ") frame ",
                                Engine.get_frames_drawn())
                _pin_player(0)
                return
        t += delta
        if stage < 3:
                _pin_player(stage)
                if t >= STAGE_T:
                        stage += 1
                        t = 0.0
                        if stage < 3:
                                if urn_cells.has(stage):
                                        stage_frames[stage] = Engine.get_frames_drawn()
                                        print("[URN60] STAGE ", stage, " (",
                                                        VARIANTS[stage], ") frame ",
                                                        Engine.get_frames_drawn())
                                else:
                                        print("[URN60] variante ", VARIANTS[stage],
                                                        " ASSENTE nel livello")
                        else:
                                print("[URN60] FINE urne=", urn_total,
                                                " varianti=", urn_cells.keys())
                                get_tree().quit(0)


func _pin_player(idx: int) -> void:
        if not urn_cells.has(idx):
                return
        var cell: Vector2i = urn_cells[idx]
        var spot := _open_neighbor(cell)
        main.player.set_position_abs(spot.x * 64.0 + 32.0,
                        80.0 + spot.y * 64.0 + 32.0)


func _scan_urns() -> void:
        ## Stessa selezione di Maze._render_wall_decorations: celle EMPTY,
        ## non tunnel, hash(c,r,5000) <= 0.025; variante = hash(c,r,333).
        for r in range(GameConstants.MAZE_ROWS):
                for c in range(GameConstants.MAZE_COLS):
                        if main.maze._get_cell_type(c, r) != GameConstants.CellType.EMPTY:
                                continue
                        if (c <= 2 and r <= 2) or GameConstants.is_tunnel_cell(c, r):
                                continue
                        if main.maze._cell_hash(c, r, 5000) > 0.025:
                                continue
                        urn_total += 1
                        var v: float = main.maze._cell_hash(c, r, 333)
                        var idx: int = 2
                        if v < 0.33:
                                idx = 0
                        elif v < 0.66:
                                idx = 1
                        if not urn_cells.has(idx):
                                urn_cells[idx] = Vector2i(c, r)
        print("[URN60] scan: ", urn_total, " urne, varianti ", urn_cells.keys())


func _open_neighbor(cell: Vector2i) -> Vector2i:
        ## Cella libera adiacente (o quasi) da cui il player guarda l'urna.
        var deltas: Array[Vector2i] = [Vector2i(2, 0), Vector2i(-2, 0),
                        Vector2i(0, 2), Vector2i(0, -2), Vector2i(1, 0),
                        Vector2i(0, 1)]
        for d in deltas:
                var cand := cell + d
                if cand.x >= 0 and cand.x < GameConstants.MAZE_COLS \
                                and cand.y >= 0 and cand.y < GameConstants.MAZE_ROWS \
                                and not main.maze.is_wall(cand.x, cand.y):
                        return cand
        return cell
