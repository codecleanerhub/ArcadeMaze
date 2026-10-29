## test_task51_bonuscard.gd — TASK 51 (richiesta utente): CARD BONUS alla
## prima raccolta.
##
##   A — memoria per-run: has/mark_bonus_card_seen + reset_run la azzera.
##   B — integrazione MainGame: _maybe_show_bonus_card apre la card (tree
##       in pausa, overlay attivo); il secondo bonus con card aperta NON
##       viene scartato silenziosamente (resta da vedere); lo stesso bonus
##       gia' visto NON riapre la card.
##   C — chiusura: TENENDO PREMUTO il fuoco (Input.action_press) per 1s la
##       card si chiude e il gioco riprende (paused = false).
##   D — testi i18n: per tutti gli 11 bonus coperti nome/effetto/usi/danno
##       non vuoti (setup risolve le chiavi).
##   E — reset run: dopo reset_run la card del martello riappare.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")
const BonusCardOverlayClass = preload("res://scripts/ui/BonusCardOverlay.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []
var checks: int = 0
var hold_frames: int = 0


func _ready() -> void:
        # la card mette in PAUSA il tree: il test deve continuare a girare
        # per simulare l'hold del fuoco (process_mode ALWAYS come gli overlay).
        process_mode = Node.PROCESS_MODE_ALWAYS
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[TEST-51C] boot MainGame...")


func _ok(cond: bool, msg: String) -> void:
        checks += 1
        if cond:
                print("[TEST-51C] OK: ", msg)
        else:
                failures.append(msg)
                print("[TEST-51C] FAIL: ", msg)


func _finish() -> void:
        if get_tree():
                get_tree().paused = false
        if failures.is_empty():
                print("[TEST-51C] ==== TEST CARD BONUS SUPERATO (",
                                checks, " check) ====")
                get_tree().quit(0)
        else:
                for f in failures:
                        print("[TEST-51C] FAIL: ", f)
                print("[TEST-51C] ==== TEST CARD BONUS FALLITO (",
                                failures.size(), "/", checks, ") ====")
                get_tree().quit(1)


func _physics_process(delta: float) -> void:
        t += delta
        match phase:
                0:
                        if main != null and main.is_node_ready() and t > 1.0:
                                phase = 1
                                _run_a_memory()
                                _run_b_open()
                1:
                        # hold fire simulato per 1s (61 frame da 16.7ms)
                        hold_frames += 1
                        if hold_frames == 5:
                                Input.action_press("shoot")
                        if hold_frames >= 70:
                                Input.action_release("shoot")
                                phase = 2
                2:
                        _run_c_closed()
                        _run_d_texts()
                        _run_e_reset()
                        _finish()


# A — memoria per-run (GameManager)
func _run_a_memory() -> void:
        _ok(not GameManager.has_seen_bonus_card("kind_99"),
                        "A: bonus mai visto = false")
        GameManager.mark_bonus_card_seen("kind_99")
        _ok(GameManager.has_seen_bonus_card("kind_99"),
                        "A: bonus segnato = true")


# B — apertura card + dedup + secondo bonus non scartato
func _run_b_open() -> void:
        main._maybe_show_bonus_card(CollectiblesClass.Kind.HAMMER, 1)
        _ok(main._bonus_card != null and get_tree().paused,
                        "B: prima raccolta martello -> card aperta + gioco in pausa")
        var hammer_card: CanvasLayer = main._bonus_card
        # stesso bonus: gia' visto, nessuna nuova card
        main._maybe_show_bonus_card(CollectiblesClass.Kind.HAMMER, 1)
        _ok(main._bonus_card == hammer_card,
                        "B: stesso bonus gia' visto -> nessuna riapertura")
        # altro bonus con card APERTA: non sostituisce e non si perde
        main._maybe_show_bonus_card(CollectiblesClass.Kind.DYNAMITE, 1)
        _ok(main._bonus_card == hammer_card
                        and not GameManager.has_seen_bonus_card("kind_%d"
                                        % CollectiblesClass.Kind.DYNAMITE),
                        "B: secondo bonus con card aperta resta da vedere (non scartato)")


# C — chiusura con hold fire 1s
func _run_c_closed() -> void:
        _ok(main._bonus_card == null and not get_tree().paused,
                        "C: fuoco tenuto 1s -> card chiusa e gioco ripreso")
        # dopo la chiusura lo stesso bonus NON riapre
        main._maybe_show_bonus_card(CollectiblesClass.Kind.HAMMER, 1)
        _ok(main._bonus_card == null,
                        "C: ripresa dello stesso bonus -> card NON riappare")
        # il secondo bonus (dinamite) ora puo' mostrarsi... e si chiude subito
        main._maybe_show_bonus_card(CollectiblesClass.Kind.DYNAMITE, 1)
        _ok(main._bonus_card != null and get_tree().paused,
                        "C: il secondo bonus in sospeso si mostra ora")
        if main._bonus_card != null:
                main._bonus_card.queue_free()
                main._bonus_card = null
                get_tree().paused = false


# D — testi i18n per tutti gli 11 bonus
func _run_d_texts() -> void:
        var kinds: Array = [
                CollectiblesClass.Kind.HAMMER,
                CollectiblesClass.Kind.DYNAMITE,
                CollectiblesClass.Kind.SCEPTER,
                CollectiblesClass.Kind.SPEED_BOOTS,
                CollectiblesClass.Kind.POTION,
                CollectiblesClass.Kind.FREEZE_SCROLL,
                CollectiblesClass.Kind.QUAKE_SCROLL,
                CollectiblesClass.Kind.CHASM_SCROLL,
                CollectiblesClass.Kind.MINE,
                CollectiblesClass.Kind.CHALICE,
                CollectiblesClass.Kind.KNIGHT_STATUE,
        ]
        var all_ok := true
        for k in kinds:
                var card: CanvasLayer = BonusCardOverlayClass.new()
                card.setup(k, 1)
                add_child(card)
                # un frame di vita (animazione demo avviata senza crash)
                card.set_physics_process(false)
                if card._title == "" or card._fx_text == "" \
                                or card._uses_text == "" or card._dmg_text == "":
                        all_ok = false
                        print("[TEST-51C] testi mancanti per kind ", k)
                card.queue_free()
        _ok(all_ok, "D: nome/effetto/usi/danno non vuoti per tutti gli 11 bonus")


# E — nuova run: la memoria si azzera
func _run_e_reset() -> void:
        GameManager.reset_run()
        _ok(not GameManager.has_seen_bonus_card("kind_%d"
                        % CollectiblesClass.Kind.HAMMER),
                        "E: reset_run azzera la memoria (card riappare a nuova partita)")
