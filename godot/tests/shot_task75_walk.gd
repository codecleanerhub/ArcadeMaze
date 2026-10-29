## shot_task75_walk.gd — TASK 75: verifica ANIMAZIONI WALK dei player.
##
## MAGE e VAMPIRE (i due sheet prima STATICI, ora rigenerati con ciclo
## [fermo, passo, fermo, passo opposto] via animate-v3 dal frame originale)
## camminano sul posto nel maze REALE:
##   - idle prima della pressione (frame 0 = posa naturale)
##   - 4 catture a ~95ms mentre cammina (il ciclo a 12.5 fps deve cambiare
##     frame: gambe alternate leggibili)
##
## Cattura un crop 176x176 centrato sul player (lo sprite e' ~83px) piu'
## una vista piena di contesto per personaggio.
##
## Avvio (Xvfb, NON headless): scripts/xvfb_shot.sh 1280x720 \
##   res://tests/shot_task75_walk.tscn
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0
var shots: int = 0
var char_name: String = ""

# CharacterType: HERO_M=0 HERO_F=1 MAGE=2 ORC=3 ELF=4 KNIGHT=5 GOLEM=6
# DRAGON=7 VAMPIRE=8
const MAGE_CT: int = 2
const VAMPIRE_CT: int = 8


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT] boot MainGame")


func _process(delta: float) -> void:
        t += delta
        if main == null or not is_node_ready():
                return
        match stage:
                0:
                        if t > 1.2:
                                _set_char(MAGE_CT, "mage", 1)
                1:
                        # idle: frame 0 (posa ferma naturale)
                        if t > 0.5:
                                _capture_player("task75_walk_mage_idle.png")
                                Input.action_press("move_right")
                                stage = 2
                                t = 0.0
                                shots = 0
                2:
                        if t > 0.095 * (shots + 1):
                                shots += 1
                                _capture_player("task75_walk_mage_%d.png" % shots)
                                if shots >= 4:
                                        Input.action_release("move_right")
                                        _set_char(VAMPIRE_CT, "vampire", 3)
                3:
                        if t > 0.5:
                                _capture_player("task75_walk_vampire_idle.png")
                                Input.action_press("move_left")
                                stage = 4
                                t = 0.0
                                shots = 0
                4:
                        if t > 0.095 * (shots + 1):
                                shots += 1
                                _capture_player("task75_walk_vampire_%d.png" % shots)
                                if shots >= 4:
                                        Input.action_release("move_left")
                                        stage = 5
                5:
                        get_tree().quit(0)


func _set_char(ct: int, nm: String, next_stage: int) -> void:
        char_name = nm
        main.player.set_character(ct, 1)
        stage = next_stage
        t = 0.0
        print("[SHOT] personaggio -> ", nm)


func _capture_player(fname: String) -> void:
        var full := get_viewport().get_texture().get_image()
        var sp: Node2D = main.player.sprite
        var origin: Vector2 = sp.get_global_transform_with_canvas().origin
        var crop := Rect2i(int(origin.x) - 88, int(origin.y) - 110, 176, 176)
        crop = crop.intersection(Rect2i(0, 0, full.get_width(), full.get_height()))
        if crop.has_area():
                full.get_region(crop).save_png(
                                "/home/z/my-project/download/" + fname)
                print("[SHOT] salvato ", fname)
        else:
                full.save_png("/home/z/my-project/download/" + fname)
                print("[SHOT] crop vuoto, salvata vista piena ", fname)
