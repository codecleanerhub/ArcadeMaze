## shot_armor51.gd — TASK 51 (P8): verifica visiva dell'ARMATURA INTEGRATA
## NELLO SPRITE del player.
##
## Check:
##   1. player1 normale (baseline);
##   2. player1 con armatura reliquia equipaggiata -> sprite CORAZZATO
##      (sheet XHD _armored) con tinta dell'armatura;
##   3. frame di camminata corazzati (0..3 del ciclo);
##   4. armatura spezzata -> torna lo sprite NORMALE.
extends Node

const PlayerScript = preload("res://scripts/core/Player.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var player: CharacterBody2D = null
var stage: int = 0
var t: float = 0.0


func _ready() -> void:
        player = PlayerScript.new()
        # il Player si aspetta un figlio "Sprite2D" (in gioco arriva dalla
        # scena MainGame.tscn): creato qui prima di entrare nell'albero.
        var sp := Sprite2D.new()
        sp.name = "Sprite2D"
        player.add_child(sp)
        get_tree().root.add_child.call_deferred(player)
        print("[SHOT-ARM] boot player...")


func _capture(tag: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/%s.png" % tag)
        print("[SHOT-ARM] salvato ", tag, ".png")


func _physics_process(delta: float) -> void:
        t += delta
        if player == null or not player.is_node_ready():
                return
        match stage:
                0:
                        if t > 0.8:
                                # reset() in _ready ha messo il player in
                                # cella (1,1): riportalo al centro schermo.
                                player.position = Vector2(960, 560)
                                player.set_character(0, 1)  # HERO_M
                                stage = 1
                                t = 0.0
                1:
                        if t > 0.4:
                                _capture("armor51_normal")
                                stage = 2
                                t = 0.0
                2:
                        # equip: cerca la Corazza d'Oro tra le armature
                        var def: Dictionary = {}
                        for a in C.RELIC_ARMORS:
                                if str(a.get("kind", "")) == "absorb":
                                        def = a
                                        break
                        if not def.is_empty():
                                player.equip_relic_armor(def)
                                print("[SHOT-ARM] equip ", def.get("id"),
                                                " armored_sheet=",
                                                str(player._armored_sheet_on))
                        stage = 3
                        t = 0.0
                3:
                        if t > 0.4:
                                _capture("armor51_armored_f0")
                                player._apply_character_frame(2)
                                stage = 4
                                t = 0.0
                4:
                        if t > 0.2:
                                _capture("armor51_armored_f2")
                                player._apply_character_frame(0)
                                # rompi l'armatura: 0 cariche + assorbi un colpo
                                player.armor_relic["charges"] = 0
                                player._break_relic_armor()
                                print("[SHOT-ARM] break -> armored_sheet=",
                                                str(player._armored_sheet_on))
                                stage = 5
                                t = 0.0
                5:
                        if t > 0.4:
                                _capture("armor51_broken_back_normal")
                                stage = 6
                                t = 0.0
                6:
                        if t > 0.2:
                                print("[SHOT-ARM] completato.")
                                get_tree().quit(0)
