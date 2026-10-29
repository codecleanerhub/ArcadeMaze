## shot_boss_sync49b.gd — TASK 49b: screenshot sync per-boss (DRAGO/BEHOLDER).
##
## QA visiva in-game dei wind-up per-boss Task 49b:
##   - DRAGO ANTICO (lvl 24, boss_035): la fiamma eruppe dalle fauci a F4
##     (372ms). Catture: wind-up ~150ms (F1: fuoco che si raccoglie in gola,
##     NESSUN proiettile), pre-rilascio ~300ms (F3: fauci aperte ma fuoco
##     ancora in gola — il frame dove il VECCHIO timing 280ms sparava
##     sbagliato), rilascio ~400ms (F4: fiamma esplosa + 5 proiettili).
##   - BEHOLDER (lvl 36, boss_037): il raggio spara a F2 (190ms). Catture:
##     wind-up ~100ms (F1: flare dell'occhio, NESSUN raggio), rilascio
##     ~210ms (F2: raggio + 4-5 proiettili).
##
## Catture (in /home/z/my-project/download/):
##   <prefix>_windup  — posa di carica, proiettili = 0
##   <prefix>_pre      — (solo drago) F3: il vecchio frame sbagliato
##   <prefix>_release  — frame di rilascio per-boss + proiettili > 0 (sync)
##   <prefix>_crop     — crop ravvicinato al rilascio
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")

@export var boss_level: int = 24          # 24 = Drago (idx 6), 36 = Beholder (idx 9)
@export var prefix: String = "boss_dragon49b"
@export var windup_ms: float = 150.0      # cattura wind-up (prima del rilascio)
@export var mid_ms: float = 300.0         # cattura pre-rilascio (-1 = salta)
@export var release_ms: float = 400.0     # cattura rilascio (dopo il frame F4/F2)
@export var release_col: int = 4          # frame sheet atteso al rilascio

var boss_room: Node2D = null
var stage: int = 0
var t: float = 0.0


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.current_level = boss_level
        boss_room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(boss_room)
        print("[SHOT-49B] boot BossRoom lvl ", boss_level, " (", prefix, ")...")


func _capture(tag: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + tag + ".png")
        print("[SHOT-49B] salvato ", tag, ".png")


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
        print("[SHOT-49B] ", tag, ": frame=(col ", col, ", row ", row,
                        ") attacking=", b.attacking_timer_ms,
                        " pending=", b.pending_shot_ms,
                        " proiettili=", nproj,
                        " [atteso col=", release_col, " al rilascio]")


func _physics_process(delta: float) -> void:
        t += delta
        if boss_room == null or not boss_room.is_node_ready():
                return
        match stage:
                0:
                        if t > 1.6:
                                # ambiente deterministico: il boss NON spara
                                # da solo (trigger manuale), niente mina.
                                boss_room.boss.shoot_timer_ms = -10000000
                                if boss_room.mine_item != null \
                                                and is_instance_valid(boss_room.mine_item):
                                        boss_room.mine_item.queue_free()
                                        boss_room.mine_item = null
                                print("[SHOT-49B] sheet rilevato: cols=",
                                        boss_room.boss._frame_cols, " rows=",
                                        boss_room.boss._frame_rows)
                                stage = 1
                                t = 0.0
                1:
                        # trigger manuale dell'attacco: al prossimo update
                        # parte il wind-up (posa) col colpo differito.
                        # (pulizia dei proiettili residui dello sparo di boot
                        # per contatori puliti: delta = solo proiettili nuovi)
                        for p in boss_room.boss_projectiles_node.get_children():
                                p.queue_free()
                        boss_room.boss.shoot_timer_ms = 99999
                        print("[SHOT-49B] attacco innescato: wind-up ",
                                        boss_room.boss._attack_windup_ms(), "ms...")
                        stage = 2
                        t = 0.0
                2:
                        # wind-up: posa di carica, NESSUN proiettile
                        if t * 1000.0 > windup_ms:
                                _capture(prefix + "_windup")
                                _state_line("windup")
                                stage = 3
                                t = 0.0
                3:
                        # pre-rilascio (solo drago): il frame del VECCHIO
                        # timing (280ms = F3) — fuoco ancora in gola.
                        if mid_ms < 0.0:
                                stage = 4
                        elif t * 1000.0 > mid_ms - windup_ms:
                                _capture(prefix + "_pre")
                                _state_line("pre-rilascio (vecchio timing F3)")
                                stage = 4
                                t = 0.0
                4:
                        # rilascio: frame per-boss (F4 drago / F2 beholder) +
                        # proiettili partiti nello stesso frame
                        if t * 1000.0 > release_ms - (mid_ms if mid_ms >= 0.0 else windup_ms):
                                _capture(prefix + "_release")
                                _state_line("release")
                                var c: Vector2 = Vector2(boss_room.boss.position.x,
                                                boss_room.boss.position.y)
                                var r := Rect2i(int(c.x) - 220, int(c.y) - 260,
                                        440, 480)
                                var img: Image = get_viewport().get_texture().get_image()
                                var crop: Image = img.get_region(r)
                                crop.save_png(
                                        "/home/z/my-project/download/" + prefix + "_crop.png")
                                print("[SHOT-49B] salvato ", prefix, "_crop.png")
                                stage = 5
                                t = 0.0
                5:
                        print("[SHOT-49B] completato.")
                        get_tree().quit(0)
