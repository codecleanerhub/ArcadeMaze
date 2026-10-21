## shot_parchments.gd — TASK 35 + TASK 36 + TASK 38: screenshot delle
## pergamene evento.
## 1) pergamena TERREMOTO a terra vicino al player (glow arancio);
## 2) pergamena VORAGINI + ondata di 4 voragini magiche viola in scena;
## 3) TASK 36: FULMINE che si abbatte al suolo all'apparizione (spawn
##    reale: saetta + onda d'urto + bagliore d'impatto + flash schermo);
## 4) TASK 38: ONDA DI LUCE in corsa nel labirinto (fronte ad anello +
##    scia di bagliore additivo che si diffonde su tutto il labirinto).
extends Node2D

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0


func _ready() -> void:
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
                        # pergamena terremoto a 2 celle dal player
                        if t > 0.2:
                                var cell: Vector2i = Vector2i(3, 2)
                                main.scroll_quake_phase = main.ScrollPhase.GROUND
                                main.scroll_quake_item = main._create_collectible(
                                                main.CollectiblesClass.Kind.QUAKE_SCROLL,
                                                main._cell_to_pixel(cell))
                                main.scroll_quake_item.scroll_lifetime_ms = 9000.0
                                main.collectibles_node.add_child(main.scroll_quake_item)
                                print("[SHOTP] pergamena terremoto @ ", cell)
                                stage = 2
                                t = 0.0
                2:
                        if t > 0.3:
                                var img: Image = get_viewport().get_texture().get_image()
                                img.save_png("/home/z/my-project/download/parchment_quake.png")
                                # crop sul raccoglibile
                                var c: Vector2 = main.scroll_quake_item.position
                                var crop: Image = img.get_region(Rect2i(
                                                int(c.x) - 96, int(c.y) - 96, 192, 192))
                                crop.resize(576, 576, Image.INTERPOLATE_NEAREST)
                                crop.save_png("/home/z/my-project/download/parchment_quake_crop.png")
                                print("[SHOTP] salvato parchment_quake.png + crop")
                                stage = 3
                                t = 0.0
                3:
                        # pergamena voragini + ondata attiva
                        if t > 0.2:
                                main.scroll_quake_item.scroll_lifetime_ms = 0.0
                                main.scroll_quake_item.active = false
                                main._update_parchments(16.0)
                                var cell: Vector2i = Vector2i(3, 2)
                                main.scroll_chasm_phase = main.ScrollPhase.GROUND
                                main.scroll_chasm_item = main._create_collectible(
                                                main.CollectiblesClass.Kind.CHASM_SCROLL,
                                                main._cell_to_pixel(cell))
                                main.scroll_chasm_item.scroll_lifetime_ms = 9000.0
                                main.collectibles_node.add_child(main.scroll_chasm_item)
                                # attiva le voragini magiche (ondata 1)
                                main.hazards.start_scroll_chasms(main.player)
                                print("[SHOTP] voragini: ",
                                                main.hazards.scroll_chasm_cells())
                                stage = 4
                                t = 0.0
                4:
                        # avanza un attimo il fade-in delle voragini
                        if t > 0.2:
                                for _i in 12:
                                        main.hazards.update_hazards(16.0, main.maze)
                                var img2: Image = get_viewport().get_texture().get_image()
                                img2.save_png("/home/z/my-project/download/parchment_chasms.png")
                                print("[SHOTP] salvato parchment_chasms.png")
                                stage = 5
                                t = 0.0
                5:
                        # TASK 36: FULMINE all'apparizione — spawn REALE della
                        # pergamena terremoto (saetta + flash + shake + suono)
                        if t > 0.2:
                                main.set_meta("scroll_quake_cell", Vector2i(3, 2))
                                main._spawn_scroll_item(true)
                                print("[SHOTP] fulmine scatenato sulla cella (3,2)")
                                stage = 6
                                t = 0.0
                6:
                        # cattura a meta' colpo (~0.25s: flicker + anello).
                        # Il flash schermo (110ms) si sarebbe gia' spento
                        # in gioco; con is_paused il timer e' congelato,
                        # quindi lo si azzera a mano prima della cattura.
                        if t > 0.25:
                                main.screen_flash_timer_ms = 0
                                var img3: Image = get_viewport().get_texture().get_image()
                                img3.save_png("/home/z/my-project/download/parchment_lightning.png")
                                var c3: Vector2 = main.scroll_quake_item.position
                                var crop3: Image = img3.get_region(Rect2i(
                                                int(c3.x) - 96, 0, 192,
                                                int(c3.y) + 96))
                                crop3.resize(384, int(crop3.get_height()) * 2,
                                                Image.INTERPOLATE_NEAREST)
                                crop3.save_png(
                                        "/home/z/my-project/download/parchment_lightning_crop.png")
                                print("[SHOTP] salvato parchment_lightning.png + crop")
                                stage = 7
                                t = 0.0
                7:
                        # TASK 38: ONDA DI LUCE in corsa — cattura a ~0.45s
                        # dallo spawn (fronte a meta' espansione nel
                        # labirinto: anello + scia di bagliore additivo).
                        if t > 0.2:
                                main.screen_flash_timer_ms = 0
                                var img4: Image = get_viewport().get_texture().get_image()
                                img4.save_png("/home/z/my-project/download/parchment_lightwave.png")
                                var c4: Vector2 = main.scroll_quake_item.position
                                var crop4: Image = img4.get_region(Rect2i(
                                                int(c4.x) - 240, int(c4.y) - 240,
                                                480, 480))
                                crop4.resize(960, 960, Image.INTERPOLATE_NEAREST)
                                crop4.save_png(
                                        "/home/z/my-project/download/parchment_lightwave_crop.png")
                                print("[SHOTP] salvato parchment_lightwave.png + crop")
                                get_tree().quit(0)
