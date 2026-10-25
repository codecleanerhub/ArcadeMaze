## shot_freeze_scroll.gd — TASK 50: screenshot della PERGAMENA DEL GHIACCIO.
## 1) pergamena GHIACCIO a terra vicino al player (glow celeste);
## 2) player che la EQUIPAGGIA (pergamena in spalla);
## 3) RAGGIO CONGELANTE in volo dal player lungo il corridoio;
## 4) nemici CONGELATI nei blocchi di ghiaccio trasparente (beam esaurito).
extends Node2D

const MainGameScene = preload("res://scenes/MainGame.tscn")
const C = preload("res://scripts/core/GameConstants.gd")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0
var corridor_cells: Array = []
var corridor_dir: Vector2i = Vector2i(1, 0)
var targets: Array = []


func _ready() -> void:
        # TASK 51: le card bonus non devono mettere in pausa i test automatici
        GameManager.mark_all_bonus_cards_seen()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)


func _center(c: int, r: int) -> Vector2:
        return Vector2(c * 64.0 + 32.0, r * 64.0 + 32.0 + 80.0)


func _process(delta: float) -> void:
        t += delta
        match stage:
                0:
                        if main != null and main.is_node_ready() and t > 1.0:
                                main.start_level(10)
                                main.is_paused = true
                                stage = 1
                                t = 0.0
                1:
                        # pergamena ghiaccio a 2 celle dal player
                        if t > 0.2:
                                var cell: Vector2i = Vector2i(3, 2)
                                main.scroll_freeze_phase = main.ScrollPhase.GROUND
                                main.scroll_freeze_item = main._create_collectible(
                                                main.CollectiblesClass.Kind.FREEZE_SCROLL,
                                                main._cell_to_pixel(cell))
                                main.scroll_freeze_item.scroll_lifetime_ms = 9000.0
                                main.collectibles_node.add_child(main.scroll_freeze_item)
                                print("[SHOTF] pergamena ghiaccio @ ", cell)
                                stage = 2
                                t = 0.0
                2:
                        if t > 0.3:
                                var img: Image = get_viewport().get_texture().get_image()
                                img.save_png("/home/z/my-project/download/freeze_scroll_ground.png")
                                var c: Vector2 = main.scroll_freeze_item.position
                                var crop: Image = img.get_region(Rect2i(
                                                int(c.x) - 96, int(c.y) - 96, 192, 192))
                                crop.resize(576, 576, Image.INTERPOLATE_NEAREST)
                                crop.save_png("/home/z/my-project/download/freeze_scroll_ground_crop.png")
                                print("[SHOTF] salvato freeze_scroll_ground.png + crop")
                                # raccoglila: player sull'item
                                main.player.position = main.scroll_freeze_item.position
                                main._update_collectibles(16.0)
                                print("[SHOTF] equip: player=", main.freeze_scroll_player,
                                                " colpi=", main.freeze_charges_left)
                                stage = 3
                                t = 0.0
                3:
                        # trova il corridoio piu' lungo di TUTTO il labirinto,
                        # teleporta il player a un estremo e piazza 3 nemici
                        if t > 0.4:
                                var best: Array = []
                                var best_dir: Vector2i = Vector2i(1, 0)
                                var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0),
                                                Vector2i(0, 1), Vector2i(0, -1)]
                                for r in range(1, C.MAZE_ROWS - 1):
                                        for c in range(1, C.MAZE_COLS - 1):
                                                if main.maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                                        continue
                                                for d in dirs:
                                                        var cells: Array = []
                                                        var cc: int = c
                                                        var rr: int = r
                                                        while cells.size() < 4 \
                                                                        and cc >= 0 and cc < C.MAZE_COLS \
                                                                        and rr >= 0 and rr < C.MAZE_ROWS \
                                                                        and main.maze.get_cell_type(cc, rr) == C.CellType.EMPTY:
                                                                cells.append(Vector2i(cc, rr))
                                                                cc += d.x
                                                                rr += d.y
                                                        if cells.size() > best.size():
                                                                best = cells
                                                                best_dir = d
                                corridor_cells = best
                                corridor_dir = best_dir
                                # player all'INIZIO del corridoio (fuori dalla
                                # lista: una cella prima), guardando lungo la dir
                                var start: Vector2i = best[0] - best_dir
                                if start.x < 0 or start.x >= C.MAZE_COLS \
                                                or start.y < 0 or start.y >= C.MAZE_ROWS \
                                                or main.maze.get_cell_type(start.x, start.y) != C.CellType.EMPTY:
                                        start = best[0]  # gia' dentro: parte da qui
                                main.player.position = _center(start.x, start.y)
                                print("[SHOTF] corridoio: ", best, " dir=", best_dir,
                                                " player@", start)
                                var idx: int = 0
                                for e in main.spawner.enemies:
                                        if idx >= mini(3, corridor_cells.size()):
                                                break
                                        if e == null or not is_instance_valid(e) or e.is_dead():
                                                continue
                                        var cell: Vector2i = corridor_cells[idx]
                                        e.position = _center(cell.x, cell.y)
                                        e.last_pos = e.position
                                        targets.append(e)
                                        idx += 1
                                main.player.dx = 0
                                main.player.dy = 0
                                main.player.last_dx = corridor_dir.x
                                main.player.last_dy = corridor_dir.y
                                # screenshot "prima": player equipaggiato + nemici
                                _snap("/home/z/my-project/download/freeze_before.png")
                                stage = 4
                                t = 0.0
                4:
                        # FUOCO il raggio congelante e inquadra il beam in volo
                        if t > 0.3:
                                main._fire_freeze_ray(main.player)
                                print("[SHOTF] raggio sparato, congelati=",
                                                _frozen_count(), " colpi=",
                                                main.freeze_charges_left)
                                stage = 5
                                t = 0.0
                5:
                        if t > 0.12:
                                _snap("/home/z/my-project/download/freeze_beam.png")
                                stage = 6
                                t = 0.0
                6:
                        # beam esaurito: statue di ghiaccio sul labirinto
                        if t > 0.7:
                                _snap("/home/z/my-project/download/freeze_after.png")
                                # crop ravvicinato su un nemico congelato
                                # (posizione SCHERMO via canvas transform: la
                                # scena ha camera + stretch, non offset fisso)
                                if targets.size() > 0:
                                        var xf: Transform2D = targets[0].get_global_transform_with_canvas()
                                        var screen: Vector2 = get_viewport().get_canvas_transform() * xf.origin
                                        var img: Image = get_viewport().get_texture().get_image()
                                        var crop: Image = img.get_region(Rect2i(
                                                        int(screen.x) - 80, int(screen.y) - 80, 160, 160))
                                        crop.resize(480, 480, Image.INTERPOLATE_NEAREST)
                                        crop.save_png("/home/z/my-project/download/freeze_enemy_crop.png")
                                        print("[SHOTF] crop nemico congelato @ screen ", screen)
                                print("[SHOTF] statue ferme=", _frozen_count(),
                                                " vivi=", main.spawner.alive_count(),
                                                " nel pool=", main.spawner.enemies.size())
                                get_tree().quit(0)


func _snap(path: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png(path)
        print("[SHOTF] salvato ", path)


func _frozen_count() -> int:
        var n: int = 0
        for e in main.spawner.enemies:
                if e != null and is_instance_valid(e) and e.is_frozen():
                        n += 1
        return n
