## shot_task96_hearts.gd — TASK 96: screenshot dell'HUD con i cuori
## sgretolabili al posto della barra vita (stati: pieno / colpito / quasi
## morto / >5 vite / effetto colpo con detriti / 2P). HUD standalone
## alimentato con snapshot diretti (pattern test_2p_hud).
extends Node

const HUDClass = preload("res://scripts/ui/HUD.gd")

var hud: Control = null
var t: float = 0.0
var stage: int = 0


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        hud = HUDClass.new()
        add_child(hud)
        hud.set_remaining_treasures(4)


func _snap(e: float, lives: int, stamina: float = 1.0) -> void:
        hud.set_player_state({"lives": lives, "energy": e, "max_energy": 5.0,
                        "stamina": stamina, "stamina_exhausted": false,
                        "score": 4820, "weapon_ammo": 12})


func _capture(tag: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        # crop della fascia HUD (1920x80) -> 2x per leggibilità VLM
        var crop := img.get_region(Rect2i(0, 0, 980, 80))
        crop.resize(1960, 160, Image.INTERPOLATE_NEAREST)
        crop.save_png("/home/z/my-project/download/" + tag + ".png")
        print("[SHOT96] salvato ", tag, ".png")


func _process(delta: float) -> void:
        t += delta
        match stage:
                0:
                        if hud.is_node_ready() and t > 0.4:
                                _snap(5.0, 3)
                                stage = 1
                                t = 0.0
                1:
                        if t > 0.25:
                                _capture("task96_hud_full")
                                _snap(3.0, 3)      # 2 colpi: cuore corrente stadio 2
                                stage = 2
                                t = 0.0
                2:
                        if t > 0.25:
                                _capture("task96_hud_hit2")
                                _snap(1.0, 3)      # 4 colpi: cuore quasi distrutto
                                stage = 3
                                t = 0.0
                3:
                        if t > 0.25:
                                _capture("task96_hud_near_death")
                                _snap(5.0, 8)      # >5 vite: formato "8x" + cuore
                                stage = 4
                                t = 0.0
                4:
                        if t > 0.25:
                                _capture("task96_hud_8lives")
                                _snap(0.5, 3, 0.5)  # + colpo fresco + stamina mezza
                                stage = 5
                                t = 0.0
                5:
                        # frame a metà effetto colpo (scossa + detriti)
                        if t > 0.12:
                                _capture("task96_hud_hit_fx")
                                # 2P: P1 colpito, P2 pieno
                                hud.set_num_players(2)
                                hud.set_player_state({"lives": 2, "energy": 2.0,
                                                "max_energy": 5.0, "score": 3110,
                                                "weapon_ammo": 7})
                                hud.set_player2_state({"lives": 4, "energy": 5.0,
                                                "max_energy": 5.0, "score": 5230,
                                                "weapon_ammo": 9})
                                stage = 6
                                t = 0.0
                6:
                        if t > 0.3:
                                var img: Image = get_viewport().get_texture().get_image()
                                img.save_png("/home/z/my-project/download/task96_hud_2p.png")
                                print("[SHOT96] salvato task96_hud_2p.png (intero)")
                                get_tree().quit(0)
