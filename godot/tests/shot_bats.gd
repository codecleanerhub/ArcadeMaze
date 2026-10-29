## shot_bats.gd — TASK 32: screenshot della nube di pipistrelli che
## insegue il player. Boot livello 10, spawn forzato, 2.5s di caccia,
## cattura full-screen + crop ingrandito sullo sciame.
extends Node2D

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0

func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)

func _process(delta: float) -> void:
        t += delta
        match stage:
                0:
                        if main != null and main.is_node_ready() and t > 1.0:
                                main.start_level(10)
                                main.is_paused = true
                                main.bat_event_timer_ms = 1.0
                                main._update_bat_cloud(16.0)
                                if main.bat_cloud == null:
                                        print("[SHOTB] FAIL: nessuno sciame")
                                        get_tree().quit(1)
                                        return
                                print("[SHOTB] sciame @ ", main.bat_cloud.position)
                                stage = 1
                                t = 0.0
                1:
                        # caccia pilotata: il player sta fermo, lo sciame si avvicina
                        if t > 0.2:
                                var players: Array = main._alive_players()
                                for _i in 150:
                                        main.bat_cloud.update_cloud(16.0, players)
                                print("[SHOTB] sciame ora @ ", main.bat_cloud.position,
                                                " player @ ", main.player.position)
                                stage = 2
                                t = 0.0
                2:
                        if t > 0.2:
                                var img: Image = get_viewport().get_texture().get_image()
                                img.save_png("/home/z/my-project/download/bats_chasing.png")
                                # crop centrato sullo sciame (256x256 -> 512)
                                var c: Vector2 = main.bat_cloud.position
                                var crop: Image = img.get_region(Rect2i(
                                                int(c.x) - 128, int(c.y) - 128, 256, 256))
                                crop.resize(512, 512, Image.INTERPOLATE_NEAREST)
                                crop.save_png("/home/z/my-project/download/bats_crop.png")
                                print("[SHOTB] salvato bats_chasing.png + bats_crop.png")
                                get_tree().quit(0)
