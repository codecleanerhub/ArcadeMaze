## shot_boss79d.gd — TASK 79d: screenshot boss fight FASE 2 con proiettili
## in volo (LICH, livello 4 = primo boss che incontra il giocatore).
## Serve per il confronto A/B prima/dopo la rimozione del doppio draw dei
## proiettili in BossRoomController._draw.
## Avvio: scripts/xvfb_shot.sh 1920x1080 res://tests/shot_boss79d.tscn 60
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const C = preload("res://scripts/core/GameConstants.gd")

var t: float = 0.0
var stage: int = 0
var room: Node2D = null


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        GameManager.current_level = 4  # primo boss del gioco (LICH)
        room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(room)
        print("[SHOT] boot BossRoom LICH (livello 4)")


func _process(delta: float) -> void:
        t += delta
        if room == null or not room.is_node_ready() or room.boss == null:
                return
        match stage:
                0:
                        var b = room.boss
                        b.health = int(float(b.max_health) * C.BOSS_PHASE2_TRIGGER_RATIO) - 5
                        room.player.spawn_guard_ms = 600000.0
                        room.player.energy = 999.0
                        stage = 1
                        t = 0.0
                        print("[SHOT] fase 2 forzata")
                1:
                        room.player.spawn_guard_ms = 600000.0
                        room.player.energy = 999.0
                        if t > 3.5:
                                _capture("task79d_boss_p2_after.png")
                                get_tree().quit(0)


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)
