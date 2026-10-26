## test_medikit_reach.gd — VERIFICA UTENTE: "medikit sopra un muro,
## quindi irraggiungibile" visto negli screenshot in-game.
##
## Verifica EMPIRICA su 48 combinazioni (seed x livello):
##   A. OGNI collectible a terra (medikit, mine, calice, scettro, stivali,
##      statua, dinamite, pozione, martello + pergamere/hazard scroll se
##      presenti) sta su una cella CellType.EMPTY del maze (non WALL,
##      non TREASURE, non WEAPON).
##   B. Il MEDICIT in particolare e' RAGGIUNGIBILE: BFS dallo spawn P1
##      (cella 1,1) alla cella del medikit deve trovare un percorso.
##   C. Stessa verifica BFS per TUTTI i collectible a terra.
##   D. Statistiche extra: distanza BFS min/max, celle EMPTY totali.
##
## Esecuzione headless:
##   godot --headless --path . --quit-after N res://tests/test_medikit_reach.tscn
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const BFS = preload("res://scripts/core/BFS.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

const KIND_MEDIKIT: int = CollectiblesClass.Kind.MEDIKIT

var fails: int = 0
var main: Node2D = null
var checked: int = 0
var medikits_seen: int = 0
var levels_done: int = 0

const SEEDS: Array[int] = [11, 22, 33, 44, 55, 66, 77, 88]
const LEVELS: Array[int] = [1, 2, 3, 4, 5, 6]


func ok(cond: bool, label: String) -> void:
        if cond:
                print("[MEDR] OK: ", label)
        else:
                fails += 1
                print("[MEDR] FAIL: ", label)


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        add_child.call_deferred(main)
        set_process(true)


var _stage: int = 0
var _seed_idx: int = 0
var _level_idx: int = 0


func _process(_delta: float) -> void:
        if _stage == 0:
                if main == null or not main.is_node_ready():
                        return
                _stage = 1
        elif _stage == 1:
                if _seed_idx >= SEEDS.size():
                        _finish()
                        _stage = 2
                        return
                seed(SEEDS[_seed_idx])
                var lvl: int = LEVELS[_level_idx]
                main.start_level(lvl)
                _check_level(lvl, SEEDS[_seed_idx])
                _level_idx += 1
                if _level_idx >= LEVELS.size():
                        _level_idx = 0
                        _seed_idx += 1


func _check_level(lvl: int, s: int) -> void:
        var maze: Object = main.maze
        var found_medikit: bool = false
        var items: Array = main.collectibles_node.get_children()
        for item in items:
                if not (item is Node2D) or not is_instance_valid(item):
                        continue
                if item.is_queued_for_deletion():
                        continue  # item del livello PRECEDENTE: queue_free differita
                if item.get("kind") == null:
                        continue
                var active_val: Variant = item.get("active")
                if active_val != null and not bool(active_val):
                        continue  # raccolto/inattivo: ignorato
                var p: Vector2 = item.position
                var cell := Vector2i(
                        int(p.x / C.TILE_SIZE),
                        int((p.y - C.UI_HEIGHT) / C.TILE_SIZE))
                checked += 1
                var kind_name: String = str(item.get("kind"))
                if int(item.get("kind")) == CollectiblesClass.Kind.EXIT_DOOR \
                                or int(item.get("kind")) == CollectiblesClass.Kind.MAGIC_PORTAL:
                        continue  # porta/portale: NON devono stare su EMPTY
                # A. cella EMPTY (non muro!)
                var ctype: int = maze.get_cell_type(cell.x, cell.y)
                if ctype != C.CellType.EMPTY:
                        fails += 1
                        print("[MEDR] FAIL: seed=", s, " lvl=", lvl,
                                        " kind=", kind_name, " @", cell,
                                        " cell_type=", ctype, " (NON EMPTY!)")
                # B/C. raggiungibilita' BFS dallo spawn (1,1)
                var path: Array[Vector2i] = BFS.find_path_cells(
                                maze, Vector2i(1, 1), cell)
                if path.is_empty():
                        fails += 1
                        print("[MEDR] FAIL: seed=", s, " lvl=", lvl,
                                        " kind=", kind_name, " @", cell,
                                        " IRAGGIUNGIBILE da (1,1)")
                if int(item.get("kind")) == KIND_MEDIKIT:
                        found_medikit = true
                        medikits_seen += 1
                        print("[MEDR] seed=", s, " lvl=", lvl,
                                        " medikit @", cell,
                                        " type=", ctype,
                                        " BFS_path=", path.size(), " celle")
        if not found_medikit:
                fails += 1
                print("[MEDR] FAIL: seed=", s, " lvl=", lvl,
                                " NESSUN medikit a terra")
        levels_done += 1


func _finish() -> void:
        # D. statistiche aggregate
        var empty_total: int = 0
        var maze: Object = main.maze
        for r in range(C.MAZE_ROWS):
                for c in range(C.MAZE_COLS):
                        if maze.get_cell_type(c, r) == C.CellType.EMPTY:
                                empty_total += 1
        print("[MEDR] --- STATISTICHE: livelli=", levels_done,
                        " collectible controllati=", checked,
                        " medikit=", medikits_seen,
                        " celle EMPTY ultimo maze=", empty_total, " ---")
        ok(medikits_seen == levels_done, "1 medikit per livello ("
                        + str(medikits_seen) + "/" + str(levels_done) + ")")
        print("[MEDR] --- RISULTATO: ",
                        "TUTTI PASS" if fails == 0 else str(fails) + " FAIL",
                        " ---")
        get_tree().quit(1 if fails > 0 else 0)
