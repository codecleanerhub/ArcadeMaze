## shot_task51_phase2.gd — TASK 51: screenshot della FASE 2 del boss.
## Due catture: fase 1 (normale) e fase 2 (aura + dimensione + barra HP
## pulsante + colonne dal'alto in volo + buca aperta + proiettile
## potenziato a inseguimento).
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const C = preload("res://scripts/core/GameConstants.gd")

var boss_room: Node2D = null
var t: float = 0.0
var stage: int = 0
var ctrl: Node2D = null
var boss: Node2D = null


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.current_level = 4  # LICH — SKY_STRIKE
        boss_room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(boss_room)
        print("[SHOT] boot BossRoom")


func _process(delta: float) -> void:
        t += delta
        match stage:
                0:
                        if boss_room != null and boss_room.is_node_ready():
                                ctrl = boss_room
                                boss = ctrl.boss
                                if boss == null:
                                        return
                                stage = 1
                                t = 0.0
                1:
                        # fase 1: attesa breve per il rendering completo
                        if t > 0.8:
                                _capture("task51_phase2_before.png")
                                # entra in fase 2
                                boss.health = int(float(boss.max_health) * 0.5)
                                boss.update_step(960.0, 600.0, 16, [])
                                # buca aperta dal boss (lato controller)
                                ctrl._on_boss_spawn_pit(Vector2(620.0, 700.0),
                                                Color(0.2, 1.0, 0.3))
                                stage = 2
                                t = 0.0
                2:
                        # flash in dissolvenza + crepa che si apre
                        if t > 1.0:
                                # special: colonne dall'alto + stormo di
                                # proiettili potenziati
                                boss.special_timer_ms = C.BOSS_PHASE2_SPECIAL_CD_MS
                                var out: Array = []
                                boss.update_step(1200.0, 800.0, 16, out)
                                for proj in out:
                                        if proj is Projectile:
                                                proj.position = proj.pos
                                                proj.visible = true
                                                proj.bounds = Rect2(0.0, C.UI_HEIGHT,
                                                                1920.0, 1000.0)
                                                ctrl.boss_projectiles_node.add_child(proj)
                                stage = 3
                                t = 0.0
                3:
                        # le colonne cadono verso il player: cattura a meta' volo
                        if t > 0.12:
                                for pr in ctrl.boss_projectiles_node.get_children():
                                        if pr is Projectile:
                                                print("[SHOT] proj kind=", pr.bp_kind,
                                                                " var=", pr.variant,
                                                                " active=", pr.active,
                                                                " pos=", pr.position,
                                                                " dir=", pr.dir)
                                _capture("task51_phase2_after.png")
                                get_tree().quit(0)


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)
