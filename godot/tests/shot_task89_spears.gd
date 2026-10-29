## shot_task89_spears.gd — TASK 89: screenshot dei blocchi di lance
## (livello 36 = 3 lance). Stati forzati per la verifica visiva: una UP
## (lance infisse), una HIDDEN (solo punte), una RISING (emersione).
## Avvio: bash scripts/xvfb_shot.sh res://tests/shot_task89_spears.tscn \
##            /home/z/my-project/download/task89_spears 30 40
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const C = preload("res://scripts/core/GameConstants.gd")

var main: Node2D = null
var forced: bool = false


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        GameManager.current_level = 36
        GameManager.game_mode = C.GameMode.STORY
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT] boot MainGame livello 36 (3 blocchi di lance)")


func _physics_process(_delta: float) -> void:
        if main == null or not main.is_node_ready() or forced:
                return
        if main.hazards == null:
                return
        var spears: Array = []
        for h in main.hazards.hazard_list:
                if int(h["type"]) == 6:  # HazardType.SPEAR
                        spears.append(h)
        if spears.is_empty():
                return
        # stati forzati per la verifica della grafica
        if spears.size() >= 1:
                spears[0]["state"] = 3  # UP (lance infisse)
                spears[0]["timer_ms"] = 9000.0
        if spears.size() >= 2:
                spears[1]["state"] = 0  # HIDDEN (solo punte)
                spears[1]["timer_ms"] = 9000.0
        if spears.size() >= 3:
                spears[2]["state"] = 2  # RISING (emersione a meta')
                spears[2]["timer_ms"] = 190.0
        forced = true
        for i in spears.size():
                print("[SHOT] lancia%d cella=%s cc=%s" % [i + 1,
                                spears[i]["cell"], spears[i]["cc"]])
        print("[SHOT] stati lance forzati: UP / HIDDEN / RISING")
