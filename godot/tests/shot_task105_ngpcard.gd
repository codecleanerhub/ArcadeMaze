## shot_task105_ngpcard.gd — harness screenshot della card NEW GAME PLUS
## (Task 105) sui credits. Due situazioni:
##   ~frame 170-260 -> card NG+ (tier 1) sopra lo "THANK YOU FOR PLAYING!"
##   ~frame 260-330 -> card NG++ (tier 2, accento brace) per confronto visivo
## Pipeline movie-mode deterministica (lezione Task 92: mai get_image()
## interattivo sotto llvmpipe): --write-movie PNG sequence.
## NOTA timing: l'autoload LoadingScreen copre il BOOT (~2.5s = ~150 frame
## a 60fps): le fasi partono DOPO, quando il overlay si è ritirato.
extends Node

const CreditsScene = preload("res://scenes/CreditsScreen.tscn")

var _credits: Control = null
var _frames: int = 0


func _ready() -> void:
        GameManager.reset_run()
        GameManager.carry_p1 = {
                        "score": 0, "lives": 3,
                        "next_life_threshold": 50000,
                        "level": 14, "skill_points": 2, "pending_levelup_fx": 0,
                        "skill_levels": {"firepower": 5, "stamina": 3},
        }
        GameManager.newgameplus_offer_pending = true
        _credits = CreditsScene.instantiate()
        # call_deferred: add_child diretto in _ready fallisce ("Parent node
        # is busy setting up children") e la scena non entra mai nel tree.
        get_tree().root.add_child.call_deferred(_credits)
        # lingua italiana per lo screenshot (testo utente)
        I18n.set_language(I18n.Language.ITALIAN)
        print("[SHOT] credits pronti (deferred), offer pending, carry livello 14")


func _physics_process(_delta: float) -> void:
        _frames += 1
        if _frames == 170:
                if _credits == null or not is_instance_valid(_credits):
                        print("[SHOT] ERRORE: credits non in tree")
                        get_tree().quit(1)
                        return
                # salta lo scroll e mostra la card subito (percorso ESC reale)
                _credits.skip_to_end()
                _credits._show_ngp_card()
                print("[SHOT] card NG+ (tier 1) mostrata")
        if _frames == 260:
                # seconda situazione: offerta NG++ (tier corrente 1)
                if _credits._ngp_card != null and is_instance_valid(_credits._ngp_card):
                        _credits._ngp_card.queue_free()
                        _credits._ngp_card = null
                GameManager.newgameplus_tier = 1
                GameManager.newgameplus_offer_pending = true
                _credits._show_ngp_card()
                print("[SHOT] card NG++ (tier 2) mostrata")
        if _frames >= 330:
                print("[SHOT] done")
                get_tree().quit(0)
