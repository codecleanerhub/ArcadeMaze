## shot_boss_pixellab.gd — TASK 46: screenshot del primo boss (LICH, lvl 4) rigenerato PixelLab.
##
## Verifica visiva del nuovo asset (boss_032):
##   1. il boss USA il nuovo sheet 6-frame (1536x256 XHD / 384x64 SD);
##   2. il cycling dei frame è ATTIVO: 4 catture ravvicinate a ~250ms di
##      distanza devono mostrare FRAME DIVERSI del ciclo walk;
##   3. la grafica PixelLab è integra a schermo (palette, contorni, muschio,
##      crepe d'ambra) e coerente con l'arena gotica.
##
## Catture (in /home/z/my-project/download/):
##   boss_pixellab_overview  — arena completa col nuovo Golem
##   boss_pixellab_f0..f3    — 4 istanti del ciclo (frame cycling)
##   boss_pixellab_crop      — crop ravvicinato del boss (QA dettagli)
##
## Ambiente: BossRoom lvl 4 (GOLEM = primo boss della story), sparo boss
## disattivato per stati deterministici.
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")

var boss_room: Node2D = null
var stage: int = 0
var t: float = 0.0


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.current_level = 4
        boss_room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(boss_room)
        print("[SHOT-BOSS] boot BossRoom lvl 4 (LICH PixelLab)...")


func _capture(tag: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + tag + ".png")
        print("[SHOT-BOSS] salvato ", tag, ".png")


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
                                print("[SHOT-BOSS] sheet rilevato: cols=",
                                        boss_room.boss._frame_cols, " rows=",
                                        boss_room.boss._frame_rows)
                                stage = 1
                                t = 0.0
                1:
                        if t > 0.4:
                                _capture("boss_pixellab_overview")
                                stage = 2
                                t = 0.0
                2, 3, 4, 5:
                        # 4 catture del ciclo walk a ~250ms: frame diversi
                        if t > 0.25:
                                _capture("boss_pixellab_f%d" % (stage - 2))
                                stage += 1
                                t = 0.0
                6:
                        if t > 0.25:
                                # crop ravvicinato attorno al boss
                                var c := _boss_center()
                                var r := Rect2i(int(c.x) - 160, int(c.y) - 210,
                                        320, 380)
                                var img: Image = get_viewport().get_texture().get_image()
                                var crop: Image = img.get_region(r)
                                crop.save_png(
                                        "/home/z/my-project/download/boss_pixellab_crop.png")
                                print("[SHOT-BOSS] salvato boss_pixellab_crop.png")
                                # forza la finestra d'attacco: cattura il
                                # ciclo FIREBALL (riga 1 dello sheet 2-righe)
                                boss_room.boss.attacking_timer_ms = 500
                                stage = 7
                                t = 0.0
                7:
                        if t > 0.12:
                                _capture("boss_pixellab_atk0")
                                stage = 8
                                t = 0.0
                8:
                        if t > 0.13:
                                _capture("boss_pixellab_atk1")
                                stage = 9
                                t = 0.0
                9:
                        if t > 0.13:
                                _capture("boss_pixellab_atk2")
                                stage = 10
                                t = 0.0
                10:
                        print("[SHOT-BOSS] completato.")
                        get_tree().quit(0)
