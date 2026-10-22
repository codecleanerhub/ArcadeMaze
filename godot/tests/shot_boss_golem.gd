## shot_boss_golem.gd — TASK 48: screenshot del GOLEM (boss_031, lvl 68) PixelLab v2.
##
## Verifica visiva del nuovo asset 3-righe (idle/attack/walk, 6x3):
##   1. il boss USA il nuovo sheet (cols=6 rows=3 attesi);
##   2. cycling attivo in idle (o walk, se insegue) e riga attack dedicata;
##   3. grafica PixelLab integra a scala schermo (granito, muschio, rune
##      d'ambra) e coerente con l'arena gotica.
##
## Catture (in /home/z/my-project/download/):
##   golem_v2_overview — arena completa col GOLEM
##   golem_v2_f0..f3   — 4 istanti del ciclo (frame cycling)
##   golem_v2_crop     — crop ravvicinato (QA dettagli)
##   golem_v2_atk0..2  — ciclo ATTACK (riga 1)
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")

var boss_room: Node2D = null
var stage: int = 0
var t: float = 0.0


func _ready() -> void:
        GameManager.current_level = 68
        boss_room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(boss_room)
        print("[SHOT-GOLEM] boot BossRoom lvl 68 (GOLEM PixelLab v2)...")


func _capture(tag: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + tag + ".png")
        print("[SHOT-GOLEM] salvato ", tag, ".png")


func _boss_center() -> Vector2:
        var b: Node2D = boss_room.boss
        return Vector2(b.position.x, b.position.y) if b != null else Vector2.ZERO


func _physics_process(delta: float) -> void:
        t += delta
        if boss_room == null or not boss_room.is_node_ready():
                return
        match stage:
                0:
                        if t > 1.6:
                                # ambiente deterministico: il boss non spara
                                boss_room.boss.shoot_timer_ms = -10000000
                                if boss_room.mine_item != null \
                                                and is_instance_valid(boss_room.mine_item):
                                        boss_room.mine_item.queue_free()
                                        boss_room.mine_item = null
                                print("[SHOT-GOLEM] sheet rilevato: cols=",
                                        boss_room.boss._frame_cols, " rows=",
                                        boss_room.boss._frame_rows)
                                stage = 1
                                t = 0.0
                1:
                        if t > 0.4:
                                _capture("golem_v2_overview")
                                stage = 2
                                t = 0.0
                2, 3, 4, 5:
                        # 4 catture del ciclo a ~250ms: frame diversi
                        if t > 0.25:
                                _capture("golem_v2_f%d" % (stage - 2))
                                stage += 1
                                t = 0.0
                6:
                        if t > 0.25:
                                var c := _boss_center()
                                var r := Rect2i(int(c.x) - 200, int(c.y) - 260,
                                        400, 480)
                                var img: Image = get_viewport().get_texture().get_image()
                                var crop: Image = img.get_region(r)
                                crop.save_png(
                                        "/home/z/my-project/download/golem_v2_crop.png")
                                print("[SHOT-GOLEM] salvato golem_v2_crop.png")
                                # forza la finestra d'attacco: riga 1
                                boss_room.boss.attacking_timer_ms = 500
                                stage = 7
                                t = 0.0
                7:
                        if t > 0.12:
                                print("[SHOT-GOLEM] atk0 timer=",
                                        boss_room.boss.attacking_timer_ms,
                                        " (mode ATTACK se >0)")
                                _capture("golem_v2_atk0")
                                stage = 8
                                t = 0.0
                8:
                        if t > 0.13:
                                print("[SHOT-GOLEM] atk1 timer=",
                                        boss_room.boss.attacking_timer_ms)
                                _capture("golem_v2_atk1")
                                stage = 9
                                t = 0.0
                9:
                        if t > 0.13:
                                print("[SHOT-GOLEM] atk2 timer=",
                                        boss_room.boss.attacking_timer_ms)
                                _capture("golem_v2_atk2")
                                stage = 10
                                t = 0.0
                10:
                        print("[SHOT-GOLEM] completato.")
                        get_tree().quit(0)
