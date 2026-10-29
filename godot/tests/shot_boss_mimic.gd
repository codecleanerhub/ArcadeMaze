## shot_boss_mimic.gd — TASK 49: screenshot del MIMICO COLOSSALE (lvl 52).
##
## QA visiva in-game dei due fix Task 49:
##   1. MACCHIA GRIGIA ALLA BASE: crop ravvicinati del boss in idle devono
##      mostrare le zampe che toccano il suolo SENZA l'ombra grigia (blob
##      rimosso dallo sheet boss_025 riga idle);
##   2. SYNC POSA/PROIETTILE/SUONO: attacco innescato manualmente ->
##      cattura durante il wind-up (~110ms: posa di carica, NESSUN
##      proiettile) e al rilascio (~330ms: frame bocca spalancata + goo
##      stream partiti nello stesso frame).
##
## Catture (in /home/z/my-project/download/):
##   boss_mimic49_overview — arena completa
##   boss_mimic49_idle0..2 — 3 istanti idle (base pulita + respirazione)
##   boss_mimic49_windup   — posa di carica, proiettili = 0
##   boss_mimic49_release  — frame 3 + proiettili > 0 (sync)
##   boss_mimic49_crop     — crop ravvicinato al rilascio
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")

var boss_room: Node2D = null
var stage: int = 0
var t: float = 0.0


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.current_level = 52
        boss_room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(boss_room)
        print("[SHOT-MIMIC] boot BossRoom lvl 52 (Mimico Colossale)...")


func _capture(tag: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + tag + ".png")
        print("[SHOT-MIMIC] salvato ", tag, ".png")


func _boss_center() -> Vector2:
        var b: Node2D = boss_room.boss
        return Vector2(b.position.x, b.position.y) if b != null else Vector2.ZERO


func _state_line(tag: String) -> void:
        var b = boss_room.boss
        var col := -1
        var row := -1
        if b.deform_sprite != null and b.deform_sprite.sub_rect.size.x > 0.0:
                col = int(b.deform_sprite.sub_rect.position.x
                                / b.deform_sprite.sub_rect.size.x)
                row = int(b.deform_sprite.sub_rect.position.y
                                / b.deform_sprite.sub_rect.size.y)
        var nproj: int = boss_room.boss_projectiles_node.get_child_count()
        print("[SHOT-MIMIC] ", tag, ": frame=(col ", col, ", row ", row,
                        ") attacking=", b.attacking_timer_ms,
                        " pending=", b.pending_shot_ms,
                        " proiettili=", nproj)


func _physics_process(delta: float) -> void:
        t += delta
        if boss_room == null or not boss_room.is_node_ready():
                return
        match stage:
                0:
                        if t > 1.6:
                                # ambiente deterministico: niente mina, il
                                # boss NON spara da solo (trigger manuale dopo)
                                boss_room.boss.shoot_timer_ms = -10000000
                                if boss_room.mine_item != null \
                                                and is_instance_valid(boss_room.mine_item):
                                        boss_room.mine_item.queue_free()
                                        boss_room.mine_item = null
                                print("[SHOT-MIMIC] sheet rilevato: cols=",
                                        boss_room.boss._frame_cols, " rows=",
                                        boss_room.boss._frame_rows)
                                stage = 1
                                t = 0.0
                1:
                        if t > 0.4:
                                _capture("boss_mimic49_overview")
                                _state_line("overview(idle)")
                                stage = 2
                                t = 0.0
                2, 3, 4:
                        # 3 istanti del ciclo idle (~250ms): base pulita
                        if t > 0.25:
                                _capture("boss_mimic49_idle%d" % (stage - 2))
                                _state_line("idle%d" % (stage - 2))
                                stage += 1
                                t = 0.0
                5:
                        # trigger manuale dell'attacco: al prossimo update
                        # parte il wind-up (posa) col colpo differito.
                        boss_room.boss.shoot_timer_ms = 99999
                        print("[SHOT-MIMIC] attacco innescato: wind-up 280ms...")
                        stage = 6
                        t = 0.0
                6:
                        # ~110ms: posa di carica, NESSUN proiettile
                        if t > 0.11:
                                _capture("boss_mimic49_windup")
                                _state_line("windup")
                                stage = 7
                                t = 0.0
                7:
                        # ~330ms: frame di rilascio (3) + proiettili partiti
                        if t > 0.22:
                                _capture("boss_mimic49_release")
                                _state_line("release")
                                var c := _boss_center()
                                var r := Rect2i(int(c.x) - 200, int(c.y) - 240,
                                        400, 440)
                                var img: Image = get_viewport().get_texture().get_image()
                                var crop: Image = img.get_region(r)
                                crop.save_png(
                                        "/home/z/my-project/download/boss_mimic49_crop.png")
                                print("[SHOT-MIMIC] salvato boss_mimic49_crop.png")
                                stage = 8
                                t = 0.0
                8:
                        print("[SHOT-MIMIC] completato.")
                        get_tree().quit(0)
