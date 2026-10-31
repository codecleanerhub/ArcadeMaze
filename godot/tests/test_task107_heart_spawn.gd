## test_task107_heart_spawn.gd — TASK 107: verifica RUNTIME della nascita
## del cuore nascosto nel labirinto reale (MainGame istanziato).
##
## Check:
##   A. Livelli cuore (3, 7, 11): hidden_heart_item ESISTE, attivo, kind
##      HEART, ed e' L'UNICO collectible HEART del livello.
##   B. Livelli senza cuore (1, 2, 4-boss, 5): hidden_heart_item == null.
##   C. La cella del cuore e' CellType.EMPTY e BFS-raggiungibile dallo
##      spawn P1 (1,1) su piu' seed.
##   D. Statistiche: distanza Manhattan minima del cuore dallo spawn
##      (deve stare nel quartile lontano: >= 60% della max).
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const BFS = preload("res://scripts/core/BFS.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

const SEEDS: Array[int] = [11, 22, 33, 44]
const HEART_LEVELS: Array[int] = [3, 7, 11]
const NO_HEART_LEVELS: Array[int] = [1, 2, 4, 5]

var fails: int = 0
var main: Node2D = null
var hearts_seen: int = 0
var min_dist_ratio: float = 1.0


func ok(cond: bool, label: String) -> void:
        if cond:
                print("[HRSP] OK: ", label)
        else:
                fails += 1
                print("[HRSP] FAIL: ", label)


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        add_child.call_deferred(main)
        set_process(true)


var _stage: int = 0
var _plan: Array = []
var _i: int = 0


func _process(_delta: float) -> void:
        if _stage == 0:
                if main == null or not main.is_node_ready():
                        return
                for s in SEEDS:
                        for lvl in HEART_LEVELS:
                                _plan.append([s, lvl, true])
                        for lvl in NO_HEART_LEVELS:
                                _plan.append([s, lvl, false])
                _stage = 1
        elif _stage == 1:
                if _i >= _plan.size():
                        _finish()
                        _stage = 2
                        return
                var entry: Array = _plan[_i]
                _i += 1
                seed(int(entry[0]))
                var lvl: int = int(entry[1])
                main.start_level(lvl)
                _check(lvl, int(entry[0]), bool(entry[2]))


func _check(lvl: int, s: int, want_heart: bool) -> void:
        var item: Node2D = main.hidden_heart_item
        var count_hearts: int = 0
        for child in main.collectibles_node.get_children():
                if is_instance_valid(child) and not child.is_queued_for_deletion() \
                                and int(child.get("kind")) == CollectiblesClass.Kind.HEART:
                        count_hearts += 1
        if want_heart:
                if item == null or not is_instance_valid(item):
                        ok(false, "livello %d seed %d: cuore nascosto ASSENTE" % [lvl, s])
                        return
                if not item.active or int(item.kind) != CollectiblesClass.Kind.HEART:
                        ok(false, "livello %d seed %d: cuore non attivo/kind errato" % [lvl, s])
                        return
                if count_hearts != 1:
                        ok(false, "livello %d seed %d: %d cuori a terra (atteso 1)" % [
                                        lvl, s, count_hearts])
                        return
                hearts_seen += 1
                # cella EMPTY + BFS raggiungibile + lontananza
                var cell := Vector2i(
                                int(item.position.x / C.TILE_SIZE),
                                int((item.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                if main.maze.get_cell_type(cell.x, cell.y) != C.CellType.EMPTY:
                        ok(false, "livello %d seed %d: cuore su cella non EMPTY (%s)" % [
                                        lvl, s, str(cell)])
                        return
                var next := BFS.find_path(main.maze, Vector2i(1, 1), cell)
                if next == Vector2i(-1, -1) and cell != Vector2i(1, 1):
                        ok(false, "livello %d seed %d: cuore non BFS-raggiungibile" % [lvl, s])
                        return
                # distanza dallo spawn rispetto al massimo teorico (quartile)
                var dist: int = absi(cell.x - 1) + absi(cell.y - 1)
                var max_d: int = (C.MAZE_COLS - 2) + (C.MAZE_ROWS - 2)
                min_dist_ratio = minf(min_dist_ratio, float(dist) / float(max_d))
                if float(dist) / float(max_d) < 0.55:
                        ok(false, "livello %d seed %d: cuore troppo vicino allo spawn (%d/%d)" % [
                                        lvl, s, dist, max_d])
                        return
        else:
                if item != null and is_instance_valid(item):
                        ok(false, "livello %d seed %d: cuore presente ma NON atteso" % [lvl, s])
                        return
                if count_hearts != 0:
                        ok(false, "livello %d seed %d: %d cuori a terra (atteso 0)" % [
                                        lvl, s, count_hearts])
                        return


func _finish() -> void:
        if hearts_seen != SEEDS.size() * HEART_LEVELS.size():
                ok(false, "cuori visti %d (attesi %d)" % [
                                hearts_seen, SEEDS.size() * HEART_LEVELS.size()])
        ok(true, "cuore nascosto: nasce sui livelli 3/7/11 (%d casi), assente altrove, EMPTY+BFS" % hearts_seen)
        ok(min_dist_ratio >= 0.55, "distanza minima dallo spawn: %d%% del massimo (quartile lontano)" % int(min_dist_ratio * 100.0))
        if fails == 0:
                print("[HRSP] ESITO: TUTTI PASSATI")
        else:
                print("[HRSP] ESITO: %d FALLITI" % fails)
        get_tree().quit(0 if fails == 0 else 1)
