## shot_task86_bossdeath.gd — TASK 86: screenshot della sequenza di morte
## del boss (PNG sequence via --write-movie). Livello selezionabile con la
## variabile d'ambiente T86_LEVEL (default 8 = DEMON / famiglia hell).
##
## Catture consigliate (get_boss_index = (livello/4) % 17):
##   T86_LEVEL=8   DEMON    hell    — voragine fiamme + vortice (richiesta)
##   T86_LEVEL=68  GOLEM    rock    — sgretolamento in sassolini (richiesta)
##   T86_LEVEL=32  VAMPIRE  bat     — pipistrello + lampo (richiesta)
##   T86_LEVEL=4   LICH     soul    — anime verdi + ossa
##   T86_LEVEL=28  KRAKEN   ink     — pozza d'inchiostro
##
## Avvio (fps reali: --fixed-fps 30 > clamp 50ms del controller):
##   T86_LEVEL=8 bash scripts/xvfb_shot.sh res://tests/shot_task86_bossdeath.tscn \
##       /home/z/my-project/download/task86_hell 30 110
extends Node

const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const C = preload("res://scripts/core/GameConstants.gd")

var t: float = 0.0
var stage: int = 0
var room: Node2D = null
var level: int = 8


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        var env_lvl: String = OS.get_environment("T86_LEVEL")
        if env_lvl != "" and env_lvl.is_valid_int():
                level = int(env_lvl)
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        GameManager.current_level = level
        room = BossRoomScene.instantiate()
        get_tree().root.add_child.call_deferred(room)
        print("[SHOT] boot BossRoom livello %d" % level)


func _process(delta: float) -> void:
        t += delta
        if room == null or not room.is_node_ready() or room.boss == null:
                return
        match stage:
                0:
                        # morte immediata: la sequenza parte al primo tick
                        room.boss.health = 0
                        room.player.spawn_guard_ms = 600000.0
                        room.player.energy = 999.0
                        if room.player2 != null:
                                room.player2.spawn_guard_ms = 600000.0
                        stage = 1
                        t = 0.0
                        print("[SHOT] morte forzata (livello %d) — sequenza in corso" % level)
                1:
                        room.player.spawn_guard_ms = 600000.0
                        room.player.energy = 999.0
                        if t > 5.0:
                                get_tree().quit(0)
