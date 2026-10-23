## test_task51_gameplay.gd — Test funzionale runtime (headless) delle
## modifiche gameplay del TASK 51:
##   P1 — BonusScreen: conferma TENENDO PREMUTO il fuoco (450ms) con barra
##        di riempimento; il tap singolo non conferma piu'.
##   P2 — Pergamena delle Voragini: ondata 5600ms (+40% durata effetto).
##   P3 — Knockback visivo: spinta 24px con decadimento assoluto quadratico
##        in 200ms (offset puramente grafico, griglia intatta).
##   P4 — Spadone buffato: arco 150 gradi, raggio 150px, cd 260ms,
##        max 4 nemici per fendente (def + geometria settore).
extends Node


const C = preload("res://scripts/core/GameConstants.gd")

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
        _test_p2_chasm_constants()
        _test_p4_spadone_def()
        _test_p4_spadone_geometry()
        _test_p3_knockback_decay()
        await get_tree().process_frame
        _test_p1_hold_confirm()
        _report()
        get_tree().quit(1 if _fails > 0 else 0)


func _ok(msg: String) -> void:
        _checks += 1
        print("[TEST-51] OK: %s" % msg)


func _fail(msg: String) -> void:
        _checks += 1
        _fails += 1
        print("[TEST-51] FAIL: %s" % msg)


# ===========================================================================
# P2 — costanti voragini (+40% durata)
# ===========================================================================
func _test_p2_chasm_constants() -> void:
        if C.SCROLL_CHASM_WAVE_MS == 5600 and C.SCROLL_CHASM_WAVES == 3:
                _ok("P2: ondata voragini 5600ms (+40%% da 4000ms, 3 ondate)")
        else:
                _fail("P2: ondata voragini %d ms (attesa 5600)"
                                % C.SCROLL_CHASM_WAVE_MS)


# ===========================================================================
# P4 — definizione Spadone + geometria settore
# ===========================================================================
func _test_p4_spadone_def() -> void:
        var def: Dictionary = {}
        for d in C.RELIC_MELEE:
                if int(d.get("type", -1)) == C.RelicType.SWORD:
                        def = d
                        break
        if def.is_empty():
                _fail("P4: Spadone non trovato in RELIC_MELEE")
                return
        if absf(float(def.get("arc_deg", 0)) - 150.0) < 0.01 \
                        and absf(float(def.get("radius_px", 0)) - 150.0) < 0.01 \
                        and int(def.get("fire_cd", 0)) == 260 \
                        and int(def.get("max_targets", 0)) == 4 \
                        and int(def.get("hits", 0)) == 2:
                _ok("P4: Spadone arc=150, raggio=150, cd=260, max_targets=4, 2 colpi-kill")
        else:
                _fail("P4: Spadone arc=%s r=%s cd=%s max=%s hits=%s (attesi 150/150/260/4/2)"
                                % [str(def.get("arc_deg")), str(def.get("radius_px")),
                                   str(def.get("fire_cd")), str(def.get("max_targets")),
                                   str(def.get("hits"))])


func _test_p4_spadone_geometry() -> void:
        var def: Dictionary = C.get_relic_def(C.RelicType.SWORD)
        var from: Vector2 = Vector2.ZERO
        var aim: Vector2 = Vector2.RIGHT
        # Nemico a 140px quasi sul bordo dell'arco a 150 gradi (75 gradi
        # per lato): angolo 70 gradi = dentro, angolo 80 gradi = fuori.
        var in_pos: Vector2 = Vector2(140.0 * cos(deg_to_rad(70.0)),
                        140.0 * sin(deg_to_rad(70.0)))
        var out_pos: Vector2 = Vector2(140.0 * cos(deg_to_rad(80.0)),
                        140.0 * sin(deg_to_rad(80.0)))
        var far_pos: Vector2 = Vector2(151.0, 0.0)
        var near_pos: Vector2 = Vector2(149.0, 0.0)
        if C.relic_melee_in_shape(def, aim, from, in_pos) \
                        and not C.relic_melee_in_shape(def, aim, from, out_pos):
                _ok("P4: arco 150 gradi — dentro a 70 gradi, fuori a 80 gradi")
        else:
                _fail("P4: geometria arco 150 errata (70/80 gradi)")
        if C.relic_melee_in_shape(def, aim, from, near_pos) \
                        and not C.relic_melee_in_shape(def, aim, from, far_pos):
                _ok("P4: raggio 150px — dentro a 149, fuori a 151")
        else:
                _fail("P4: raggio 150 errato (149/151)")


# ===========================================================================
# P3 — decadimento knockback (assoluto, quadratico, 200ms)
# ===========================================================================
func _test_p3_knockback_decay() -> void:
        var EnemyScript: GDScript = load("res://scripts/enemies/Enemy.gd")
        var e: Node2D = EnemyScript.new()
        var dir: Vector2 = Vector2(1.0, 0.0)
        e.apply_knockback(dir, 24.0)
        var v0: Vector2 = e.knockback_visual_offset()
        if absf(v0.length() - 24.0) < 0.01 and absf(v0.angle() - dir.angle()) < 0.001:
                _ok("P3: spinta iniziale 24px nella direzione del colpo")
        else:
                _fail("P3: spinta iniziale %s (attesa 24px dir colpo)" % str(v0))
        # decadimento a meta' vita: 100ms rimanenti -> 24 * 0.5^2 = 6px
        e._tick_knockback(100.0)
        var v1: Vector2 = e.knockback_visual_offset()
        if absf(v1.length() - 6.0) < 0.01:
                _ok("P3: decadimento quadratico — 6px residui a meta' vita")
        else:
                _fail("P3: residuo a meta' vita %s px (atteso 6)" % str(v1.length()))
        # a fine vita: 0
        e._tick_knockback(100.0)
        var v2: Vector2 = e.knockback_visual_offset()
        if v2.length() < 0.01:
                _ok("P3: spinta esaurita a 200ms (offset 0, griglia intatta)")
        else:
                _fail("P3: spinta non esaurita: %s" % str(v2))
        # nuova spinta dopo l'esaurimento riparte piena
        e.apply_knockback(dir, 24.0)
        if absf(e.knockback_visual_offset().length() - 24.0) < 0.01:
                _ok("P3: riapplicazione = spinta piena (24px)")
        else:
                _fail("P3: riapplicazione non riparte piena")
        e.free()


# ===========================================================================
# P1 — BonusScreen: conferma tenendo premuto il fuoco
# =========================================================================##
func _test_p1_hold_confirm() -> void:
        var BonusScript: GDScript = load("res://scripts/ui/BonusScreen.gd")
        var screen: CanvasLayer = BonusScript.new()
        get_tree().root.add_child(screen)
        # Giocatore finto con cio' che serve a _apply_choice
        var PlayerScript: GDScript = load("res://scripts/core/Player.gd")
        var fake: CharacterBody2D = PlayerScript.new()
        fake.player_num = 1
        get_tree().root.add_child(fake)
        screen.setup(4, [fake])
        if screen.offerings.is_empty():
                _fail("P1: nessuna offerta al livello 4")
                screen.queue_free()
                fake.queue_free()
                return
        screen.selection = 0
        screen._wait_ms = 0.0

        # --- tap breve (150ms): NON conferma ---
        Input.action_press("shoot")
        for _i in 3:
                screen._physics_process(0.05)  # 150ms totali
        if screen.chooser_idx == 0 and screen.completed == false:
                _ok("P1: tap breve 150ms NON conferma (il fuoco va tenuto)")
        else:
                _fail("P1: tap breve ha confermato (atteso: solo hold prolungato)")
        Input.action_release("shoot")
        screen._physics_process(0.05)
        # rilascio: la barra si svuota
        if screen._hold_frac < 0.01:
                _ok("P1: rilascio del fuoco = barra di riempimento azzerata")
        else:
                _fail("P1: barra non azzerata dopo il rilascio (frac=%s)"
                                % str(screen._hold_frac))

        # --- hold completo (500ms): conferma ---
        Input.action_press("shoot")
        for _i in 10:
                screen._physics_process(0.05)  # 500ms totali
        Input.action_release("shoot")
        var chose: bool = screen.chooser_idx != 0 or screen.completed
        if chose:
                _ok("P1: hold 450ms+ conferma la reliquia (chooser avanzato)")
        else:
                _fail("P1: hold 450ms NON ha confermato")
        # la scelta e' arrivata al player (arma reliquia o armatura)
        var equipped: bool = fake.current_weapon.has("relic") \
                        or fake.has_relic_armor()
        if equipped:
                _ok("P1: la scelta e' stata applicata al player")
        else:
                _fail("P1: la scelta non risulta applicata")
        screen.queue_free()
        fake.queue_free()


func _report() -> void:
        if _fails == 0:
                print("[TEST-51] ==== TEST TASK 51 GAMEPLAY SUPERATO (%d check) ====" % _checks)
        else:
                print("[TEST-51] ==== TEST TASK 51 FALLITO: %d/%d ====" % [_fails, _checks])
