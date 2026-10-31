## shot_task106.gd — harness screenshot TASK 106 (SALVA PARTITA).
## Fasi (movie-mode deterministica, 60fps; boot loading ~150 frame):
##   ~170  menu con 0 slot      -> CONTINUA grigia/disabilitata (shot A)
##   ~230  3 slot fake + refresh -> CONTINUA attiva (shot B)
##   ~290  card CONTINUA (LOAD)  -> righe slot con data/livelli/personaggio (C)
##   ~370  card DELETE 10 slot   -> "slot pieni" + conferma inline (D/E)
##   ~540  MainGame con flag     -> "Partita salvata..." sopra il labirinto (F)
## Le card sono pure-code: si aprono da codice, niente input simulato.
## ITALIANO per lo screenshot (testo utente) — la lingua persiste in
## config.ini: i test che presumono EN la forzano esplicitamente.
extends Node

const MainMenuScene = preload("res://scenes/MainMenu.tscn")
const MainGameScene = preload("res://scenes/MainGame.tscn")
const SaveSlotsCardClass = preload("res://scripts/ui/SaveSlotsCard.gd")

var _menu: Control = null
var _delete_card: CanvasLayer = null
var _main: Node = null
var _frames: int = 0


func _ready() -> void:
        # PROCESS_MODE_ALWAYS: le card di questo task METTONO IN PAUSA il
        # tree (SaveSlotsCard) — l'harness deve continuare a guidare le fasi
        # anche sotto pausa, e toglierla quando libera le card manualmente.
        process_mode = Node.PROCESS_MODE_ALWAYS
        GameManager.reset_run()
        if SaveSystem != null:
                SaveSystem.clear_all()
        I18n.set_language(I18n.Language.ITALIAN)
        _menu = MainMenuScene.instantiate()
        get_tree().root.add_child.call_deferred(_menu)
        print("[SHOT106] boot: menu con 0 slot (CONTINUA disabilitata)")


func _physics_process(_delta: float) -> void:
        _frames += 1
        if _frames == 200:
                print("[SHOT106] A: menu 0 slot")
        elif _frames == 230:
                _make_fake_slots(3)
                if _menu != null and is_instance_valid(_menu):
                        _menu.refresh_continue_state()
                print("[SHOT106] B: 3 slot creati, CONTINUA attiva")
        elif _frames == 290:
                if _menu != null and is_instance_valid(_menu):
                        _menu._open_continue_card()
                print("[SHOT106] C: card CONTINUA aperta")
        elif _frames == 370:
                if _menu != null and is_instance_valid(_menu) \
                                and _menu._save_card != null:
                        _menu._save_card.queue_free()
                        _menu._save_card = null
                get_tree().paused = false
                _make_fake_slots(10)
                _delete_card = SaveSlotsCardClass.new()
                _delete_card.setup(SaveSlotsCardClass.Mode.DELETE,
                                SaveSystem.all_summaries())
                get_tree().root.add_child(_delete_card)
                print("[SHOT106] D: card DELETE (10 slot pieni)")
        elif _frames == 450:
                if _delete_card != null and is_instance_valid(_delete_card):
                        _delete_card._delete_confirm = true
                        _delete_card._sel = 2
                print("[SHOT106] E: conferma inline di eliminazione")
        elif _frames == 540:
                if _delete_card != null and is_instance_valid(_delete_card):
                        _delete_card.queue_free()
                        _delete_card = null
                get_tree().paused = false
                if _menu != null and is_instance_valid(_menu):
                        _menu.queue_free()
                        _menu = null
                if SaveSystem != null:
                        SaveSystem.clear_all()
                GameManager.reset_run()
                GameManager.num_players = 1
                GameManager.game_mode = 0  # STORY
                GameManager.current_level = 2
                GameManager.player1_character = 4  # ELF
                GameManager.carry_p1 = {
                                "score": 5000, "lives": 3,
                                "next_life_threshold": 50000,
                                "level": 2, "skill_points": 0,
                                "pending_levelup_fx": 0, "skill_levels": {},
                }
                GameManager.save_announce_pending = true
                _main = MainGameScene.instantiate()
                get_tree().root.add_child.call_deferred(_main)
                print("[SHOT106] F: MainGame con annuncio 'Partita salvata...'")
        elif _frames == 680:
                print("[SHOT106] done")
                get_tree().quit(0)


## Slot finti con date differenziate (deterministiche per la QA visiva).
func _make_fake_slots(n: int) -> void:
        if SaveSystem == null:
                return
        SaveSystem.clear_all()
        var dates: Array = [
                        "01/11/2026 09:12", "31/10/2026 21:45", "29/10/2026 18:05",
                        "27/10/2026 22:30", "25/10/2026 11:20", "22/10/2026 16:40",
                        "19/10/2026 20:15", "15/10/2026 08:55", "11/10/2026 23:05",
                        "07/10/2026 14:25",
        ]
        var chars: Array = [4, 7, 3, 6, 1, 5, 0, 2, 4, 7]   # ELF, DRAGO, MAGO...
        for i in n:
                var two_p: bool = i == 1 or i == 6
                SaveSystem.save_run(i, {
                                "saved_at": str(dates[i % dates.size()]),
                                "num_players": 2 if two_p else 1,
                                "game_mode": 0,
                                "newgameplus_tier": 1 if i == 4 else 0,
                                "current_level": 5 + i * 3,
                                "char1": int(chars[i % chars.size()]),
                                "char2": 1,
                                "carry_p1": {
                                                "score": 12000 + i * 1000,
                                                "lives": 3,
                                                "level": 2 + i,
                                                "skill_points": i,
                                                "skill_levels": {},
                                },
                                "carry_p2": {},
                })
