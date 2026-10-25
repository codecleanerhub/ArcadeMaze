## shot_weapon_sizes.gd — TASK 50: screenshot con TUTTE le armi pickup
## a terra (pistol/shotgun/rocket/laser) + collectibles (hammer/mine/dynamite)
## in celle note, per misurare le dimensioni reali renderizzate a confronto.
extends Node2D

const MainGameScene = preload("res://scenes/MainGame.tscn")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")
const C = preload("res://scripts/core/GameConstants.gd")

const COLS: Array[int] = [8, 10, 12, 14]    # colonne armi
const ROW: int = 7
const OUT_DIR: String = "/home/z/my-project/download"

var main: Node2D = null
var t: float = 0.0
var stage: int = 0


func _ready() -> void:
        # TASK 51: le card bonus non devono mettere in pausa i test automatici
        GameManager.mark_all_bonus_cards_seen()
        LoadingScreen.skip_boot_hold()
        print("[SHOT] _ready chiamato")
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT] main istanziato")


func _process(delta: float) -> void:
        t += delta
        if t < 3.0 and int(t * 10) % 10 == 0 and stage == 0:
                print("[SHOT] _process t=", t, " main=", main != null,
                                " ready=", main != null and main.is_node_ready())
        match stage:
                0:
                        if main != null and main.is_node_ready() and t > 1.0:
                                _place_weapons()
                                stage = 1
                                t = 0.0
                1:
                        if t > 1.0:
                                _capture("weapons_sizes.png")
                                get_tree().quit(0)


func _place_weapons() -> void:
        var maze = main.maze
        # pulizia nemici per shot pulito
        for e in main.spawner.enemies.duplicate():
                if is_instance_valid(e):
                        e.queue_free()
        main.spawner.enemies.clear()
        # arma a terra per tipo (riga ROW, colonne 8..14)
        var types: Array[int] = [
                C.WeaponType.PISTOL, C.WeaponType.SHOTGUN,
                C.WeaponType.ROCKET, C.WeaponType.LASER,
        ]
        for i in range(types.size()):
                var w: Dictionary = C.make_random_weapon()
                w["type"] = types[i]
                maze._set_cell_type(COLS[i], ROW, C.CellType.WEAPON)
                maze._set_cell_weapon(COLS[i], ROW, w)
        maze.needs_redraw = true
        maze.queue_redraw()
        # collectibles due righe sotto: hammer, mine, dinamite
        var kinds: Array[int] = [
                CollectiblesClass.Kind.HAMMER,
                CollectiblesClass.Kind.MINE,
                CollectiblesClass.Kind.DYNAMITE,
        ]
        for i in range(kinds.size()):
                var col: int = 10 + i * 2
                var cpos: Vector2 = Vector2((col + 0.5) * C.TILE_SIZE,
                                C.UI_HEIGHT + (ROW + 2 + 0.5) * C.TILE_SIZE)
                var node: Node2D = main._create_collectible(kinds[i], cpos)
                main.collectibles_node.add_child(node)
        print("[SHOT] armi piazzate riga ", ROW, " collectibles riga ", ROW + 2)


func _capture(fname: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        var path: String = OUT_DIR + "/" + fname
        var err: int = img.save_png(path)
        print("[SHOT] salvato ", path, " err=", err)
