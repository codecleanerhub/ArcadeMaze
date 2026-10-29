## shot_hazards.gd — TASK 30: screenshot REALI di validazione degli hazard
## ambientali. Boot del MainGame, salto diretto al livello 12 (3 hazard per
## tipo: 1 + int((12-4)/3)), attesa di ~7s simulati (telegrafi delle
## voragini scattati, muri di roccia in fasi diverse del ciclo) e cattura
## di DUE fotogrammi: uno presto (crepe/ganasce armate/muri aperti) e uno
## tardi (voragini aperte, almeno un muro chiuso).
extends Node2D

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0
var shot_count: int = 0
const OUT_DIR: String = "/home/z/my-project/download"


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)


func _process(delta: float) -> void:
        t += delta
        match stage:
                0:
                        if main != null and main.is_node_ready() and t > 1.0:
                                main.start_level(12)
                                print("[SHOT] livello 12 avviato, hazard: ",
                                                main.hazards.hazard_list.size())
                                stage = 1
                                t = 0.0
                1:
                        # attesa 2.2s: telegrafo crepe visibile, muri aperti
                        if t > 2.2:
                                _capture("hazards_lvl12_early.png")
                                stage = 2
                                t = 0.0
                2:
                        # attesa fino a 7s: voragini aperte, ciclo muri girato
                        if t > 4.8:
                                _capture("hazards_lvl12_late.png")
                                stage = 3
                                t = 0.0
                3:
                        # report e uscita
                        var hz = main.hazards
                        var open_chasms: int = 0
                        var cracked: int = 0
                        for h in hz.hazard_list:
                                var kind: String = ["QUICKSAND", "TRAP", "CHASM", "WALL", "BARREL"][h["type"]]
                                var extra: String = ""
                                if h["type"] == 2:
                                        if h["state"] == 2:
                                                open_chasms += 1
                                                extra = " OPEN"
                                        elif h["state"] == 1:
                                                cracked += 1
                                                extra = " CRACK"
                                elif h["type"] == 3:
                                        extra = " phase=%d axis=%s" % [h["phase"], h["axis"]]
                                print("[SHOT] %s @ %s%s" % [kind, str(h["cell"]), extra])
                        print("[SHOT] report: %d hazard totali, voragini aperte=%d crepe=%d"
                                        % [hz.hazard_list.size(), open_chasms, cracked])
                        get_tree().quit(0)


func _capture(fname: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        var path: String = OUT_DIR + "/" + fname
        var err: int = img.save_png(path)
        print("[SHOT] salvato ", path, " err=", err)
        shot_count += 1
