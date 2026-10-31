## test_task107_hearts.gd — TASK 107 (CUORI): energia persistente tra scene,
## cuore nascosto nel labirinto, riscatto cuori a punti nella bonus screen.
##
## Check:
##   A — costanti + regola di spawn del cuore nascosto (ogni 3 labirinti,
##       mai sui boss) e indice labirinto
##   B — economia del riscatto: costo base*k, max riscattabile, costo totale
##       (coerenza walk), primo cuore = 4000 (circa un boss)
##   C — Player.spend_score: punteggio scende (mai sotto 0), livello =
##       high watermark (non scende), hearts_redeemed/reset
##   D — ENERGIA NEL CARRY: carry->restore NON rifila piu' l'energia piena
##       (era il refill a ogni cambio scena), clamp al max, contatore
##       cuori riscattati nel carry, NG+ NON li conserva
##   E — restore_relic_armor NON cura piu' (solo clamp); equip (scelta in
##       bonus) cura ancora piena (reward design)
##   F — Collectibles: Kind.HEART + factory make_heart attiva
##   G — BonusScreen: _redeem_max dal punteggio, _apply_redeem applica
##       vite/score/contatore e ricalcola il massimo
##   H — guardie sorgente (spawn, pickup, snapshot, i18n, UI)
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const PlayerScript = preload("res://scripts/core/Player.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")
const BonusScreenClass = preload("res://scripts/ui/BonusScreen.gd")

var fails: int = 0


func _ready() -> void:
        print("[TEST] === TASK 107: CUORI ===")
        _test_spawn_rule()
        _test_redeem_economy()
        _test_spend_score()
        _test_energy_carry()
        _test_armor_restore_no_heal()
        _test_collectible_heart()
        _test_bonus_redeem()
        _test_source_guards()
        if fails == 0:
                print("[TEST] ESITO: TUTTI PASSATI")
        else:
                print("[TEST] ESITO: %d FALLITI" % fails)
        get_tree().quit(0 if fails == 0 else 1)


func _ok(msg: String) -> void:
        print("[TEST] OK ", msg)


func _fail(msg: String) -> void:
        fails += 1
        print("[TEST] FALLITO ", msg)


# --- A: regola di spawn del cuore nascosto -----------------------------------
func _test_spawn_rule() -> void:
        if C.HIDDEN_HEART_EVERY_LEVELS != 3:
                _fail("A: HIDDEN_HEART_EVERY_LEVELS = %d (atteso 3)" % C.HIDDEN_HEART_EVERY_LEVELS)
                return
        # indice labirinto: 1-3 = labirinti 1-3, 4 e' boss, 5-7 = 4-6, 8 boss
        var want_idx := {1: 1, 2: 2, 3: 3, 4: 3, 5: 4, 6: 5, 7: 6, 8: 6, 9: 7}
        for lvl in want_idx.keys():
                if C.maze_index_for_level(lvl) != int(want_idx[lvl]):
                        _fail("A: maze_index_for_level(%d) = %d (atteso %d)" % [
                                        lvl, C.maze_index_for_level(lvl), int(want_idx[lvl])])
                        return
        # il cuore nasce sul 3o, 6o, 9o... labirinto; MAI sui boss
        # (labirinto 3 = livello 3, labirinto 6 = livello 7, labirinto 9 = 11)
        var want_spawn := {1: false, 2: false, 3: true, 4: false, 5: false,
                        6: false, 7: true, 8: false, 9: false, 10: false,
                        11: true, 12: false, 13: false}
        for lvl in want_spawn.keys():
                if C.hidden_heart_spawns_at(lvl) != bool(want_spawn[lvl]):
                        _fail("A: hidden_heart_spawns_at(%d) = %s (atteso %s)" % [
                                        lvl, str(C.hidden_heart_spawns_at(lvl)),
                                        str(want_spawn[lvl])])
                        return
        _ok("A: cuore nascosto = 1 ogni 3 labirinti, mai sui livelli boss (17/run su 51 labirinti)")


# --- B: economia del riscatto --------------------------------------------------
func _test_redeem_economy() -> void:
        if C.HEART_REDEEM_BASE_COST != 4000:
                _fail("B: HEART_REDEEM_BASE_COST = %d (atteso 4000)" % C.HEART_REDEEM_BASE_COST)
                return
        if C.heart_redeem_cost(1) != 4000 or C.heart_redeem_cost(2) != 8000 \
                        or C.heart_redeem_cost(5) != 20000:
                _fail("B: heart_redeem_cost escalation errata (%d/%d/%d)" % [
                                C.heart_redeem_cost(1), C.heart_redeem_cost(2),
                                C.heart_redeem_cost(5)])
                return
        if C.heart_redeem_cost(0) != 4000 or C.heart_redeem_cost(-3) != 4000:
                _fail("B: heart_redeem_cost deve clampare k<=0 a base")
                return
        # max riscattabile
        if C.heart_redeem_max_count(12000, 0) != 2:
                _fail("B: max_count(12000,0) = %d (atteso 2 esatto)" % C.heart_redeem_max_count(12000, 0))
                return
        if C.heart_redeem_max_count(11999, 0) != 1:
                _fail("B: max_count(11999,0) = %d (atteso 1)" % C.heart_redeem_max_count(11999, 0))
                return
        if C.heart_redeem_max_count(3999, 0) != 0:
                _fail("B: max_count(3999,0) = %d (atteso 0)" % C.heart_redeem_max_count(3999, 0))
                return
        if C.heart_redeem_max_count(30000, 0) != 3:
                _fail("B: max_count(30000,0) = %d (atteso 3)" % C.heart_redeem_max_count(30000, 0))
                return
        if C.heart_redeem_max_count(30000, 1) != 2:
                _fail("B: max_count(30000,1) = %d (atteso 2 con escalation)" % C.heart_redeem_max_count(30000, 1))
                return
        # costo totale coerente con max_count
        if C.heart_redeem_total_cost(3, 0) != 24000 or C.heart_redeem_total_cost(2, 1) != 20000:
                _fail("B: total_cost errato (%d / %d)" % [
                                C.heart_redeem_total_cost(3, 0), C.heart_redeem_total_cost(2, 1)])
                return
        for s in [5000, 12345, 30000, 99999, 4000, 3999]:
                for a in [0, 1, 4]:
                        var n: int = C.heart_redeem_max_count(s, a)
                        var tot: int = C.heart_redeem_total_cost(n, a)
                        if tot > s:
                                _fail("B: total_cost(%d cuori, gia %d) = %d > score %d" % [n, a, tot, s])
                                return
                        if n < 99 and tot + C.heart_redeem_cost(a + n + 1) <= s:
                                _fail("B: max_count sottostima con score %d gia %d" % [s, a])
                                return
        # il primo cuore costa quanto circa un boss (2500..4100 x 1.0..1.6)
        var boss_min: int = C.BOSS_KILL_POINTS_BASE
        var boss_max: int = C.BOSS_KILL_POINTS_BASE + 16 * C.BOSS_KILL_POINTS_PER_INDEX
        var ratio: float = float(C.heart_redeem_cost(1)) / float(boss_max)
        if ratio < 0.8 or ratio > 1.6:
                _fail("B: 1o cuore %d fuori dal range boss %d..%d" % [
                                C.heart_redeem_cost(1), boss_min, boss_max])
                return
        _ok("B: riscatto = 4000 x k (1o cuore ~ 1 boss), max/costo coerenti, auto-limitante")


# --- C: spend_score + high watermark ------------------------------------------
func _test_spend_score() -> void:
        var p := PlayerScript.new()
        add_child(p)
        p.reset()
        p.score = 10000
        p.spend_score(4000)
        if p.score != 6000:
                _fail("C: spend_score(4000) da 10000 = %d (atteso 6000)" % p.score)
                return
        p.spend_score(999999)
        if p.score != 0:
                _fail("C: spend_score oltre lo zero = %d (atteso 0)" % p.score)
                return
        # high watermark: livello raggiunto, poi punti spesi sotto soglia
        p.reset()
        p.score = 0
        p.add_score(C.levelup_threshold(2))   # level 2
        if p.level != 2:
                _fail("C: setup level 2 fallito (%d)" % p.level)
                return
        p.spend_score(2000)
        if p.level != 2:
                _fail("C: il livello e' SCESO dopo la spesa (%d)" % p.level)
                return
        if p.skill_points != 1:
                _fail("C: skill points persi dopo la spesa (%d)" % p.skill_points)
                return
        # ri-raggiunto il punteggio di prima: ancora SOTTO la soglia del 3
        # (6850), quindi nessun level up — la spesa ha solo ritardato il 3
        p.add_score(2000)
        if p.score >= C.levelup_threshold(3):
                _fail("C: setup incoerente (score %d >= soglia L3 %d)" % [
                                p.score, C.levelup_threshold(3)])
                return
        if p.level != 2:
                _fail("C: level up gratuito sotto soglia (%d con %d punti)" % [
                                p.level, p.score])
                return
        # reset azzera l'escalation
        p.hearts_redeemed = 5
        p.reset()
        if p.hearts_redeemed != 0:
                _fail("C: reset() non azzera hearts_redeemed (%d)" % p.hearts_redeemed)
                return
        p.queue_free()
        _ok("C: spend_score clampa a 0; livello = high watermark; reset azzera il contatore")


# --- D: ENERGIA NEL CARRY (niente refill tra scene) ----------------------------
func _test_energy_carry() -> void:
        var p1 := PlayerScript.new()
        add_child(p1)
        p1.reset()
        p1.energy = 2           # cuore corrente parzialmente sgretolato
        p1.lives = 4
        p1.score = 5000
        p1.hearts_redeemed = 1
        GameManager.save_player_carry(p1)
        var carry: Dictionary = GameManager.carry_p1
        if int(carry.get("energy", -1)) != 2:
                _fail("D: carry senza energia (%s)" % str(carry.keys()))
                return
        if int(carry.get("hearts_redeemed", -1)) != 1:
                _fail("D: carry senza contatore cuori riscattati")
                return
        # il player della scena nuova e' appena passato da reset() (energia 5)
        var p2 := PlayerScript.new()
        add_child(p2)
        p2.reset()
        if p2.energy != p2.max_energy:
                _fail("D: setup: il player nuovo deve partire pieno")
                return
        GameManager.restore_player_carry(p2)
        if p2.energy != 2:
                _fail("D: restore_player_carry deve applicare l'energia trasportata (%d, atteso 2)" % p2.energy)
                return
        if p2.hearts_redeemed != 1:
                _fail("D: restore_player_carry deve applicare il contatore (%d)" % p2.hearts_redeemed)
                return
        # clamp al max (energia salvata oltre il massimo corrente)
        p1.energy = 9
        GameManager.save_player_carry(p1)
        GameManager.restore_player_carry(p2)
        if p2.energy != p2.max_energy:
                _fail("D: energia trasportata non clampata al max (%d/%d)" % [
                                p2.energy, p2.max_energy])
                return
        # NG+: la progressione conservata NON include energia ne' contatore
        var kept: Dictionary = GameManager._ngp_kept_progression(GameManager.carry_p1)
        if kept.has("energy") or kept.has("hearts_redeemed"):
                _fail("D: NG+ NON deve conservare energia/contatore (%s)" % str(kept.keys()))
                return
        p1.queue_free()
        p2.queue_free()
        GameManager.carry_p1 = {}
        _ok("D: l'energia del cuore corrente attraversa le scene (NO refill), NG+ riparte pulito")


# --- E: armatura: il restore non cura, l'equip sì -------------------------------
func _test_armor_restore_no_heal() -> void:
        var p := PlayerScript.new()
        add_child(p)
        p.reset()
        p.energy = 1
        # restore (carry tra scene): energia resta 1, max sale (+2 armatura)
        p.restore_relic_armor({"kind": "regen", "charges": 5, "max_charges": 5,
                        "color": Color.WHITE, "name_it": "x", "name_en": "x"})
        if p.energy != 1:
                _fail("E: restore_relic_armor cura ancora l'energia (%d, attesa 1)" % p.energy)
                return
        if p.max_energy != 7:
                _fail("E: restore_relic_armor max_energy = %d (atteso 7)" % p.max_energy)
                return
        # equip (scelta nella schermata bonus): ricompensa = cura piena
        p.energy = 1
        p.equip_relic_armor({"kind": "regen", "charges": 5, "max_charges": 5,
                        "color": Color.WHITE, "name_it": "x", "name_en": "x"})
        if p.energy != p.max_energy:
                _fail("E: equip_relic_armor deve curare pieno (%d/%d)" % [
                                p.energy, p.max_energy])
                return
        p.queue_free()
        _ok("E: armatura — restore tra scene NON cura (solo clamp), equip in bonus SI'")


# --- F: collectible cuore -------------------------------------------------------
func _test_collectible_heart() -> void:
        if not CollectiblesClass.Kind.has("HEART"):
                _fail("F: Kind.HEART mancante nell'enum")
                return
        var h := CollectiblesClass.make_heart(Vector2(100, 100))
        if h.kind != CollectiblesClass.Kind.HEART or not h.active:
                _fail("F: make_heart non crea un cuore attivo")
                return
        h.queue_free()
        _ok("F: Collectibles.Kind.HEART + make_heart (icona ui_heart.png + fallback)")


# --- G: BonusScreen — riga riscatto ---------------------------------------------
func _test_bonus_redeem() -> void:
        var p := PlayerScript.new()
        add_child(p)
        p.reset()
        p.score = 30000
        p.lives = 3
        p.hearts_redeemed = 0
        var bonus := BonusScreenClass.new()
        add_child(bonus)
        bonus.setup(4, [p])
        if bonus._redeem_max != 3:
                _fail("G: _redeem_max = %d (atteso 3 con 30000 punti)" % bonus._redeem_max)
                return
        # focus + 2 cuori -> applica: 4000+8000 = 12000 punti, +2 vite
        bonus._redeem_focus = true
        bonus._redeem_count = 2
        bonus._apply_redeem()
        if p.score != 18000:
                _fail("G: score dopo riscatto = %d (atteso 18000)" % p.score)
                return
        if p.lives != 5:
                _fail("G: vite dopo riscatto = %d (atteso 5)" % p.lives)
                return
        if p.hearts_redeemed != 2:
                _fail("G: contatore dopo riscatto = %d (atteso 2)" % p.hearts_redeemed)
                return
        if bonus._redeem_count != 0:
                _fail("G: il conteggio a schermo non si azzera dopo l'applicazione")
                return
        # escalation: con 18000 e 2 gia' riscattati resta 1 cuore (12000)
        if bonus._redeem_max != 1:
                _fail("G: _redeem_max dopo = %d (atteso 1)" % bonus._redeem_max)
                return
        if bonus._redeem_feedback == "":
                _fail("G: feedback riscatto vuoto")
                return
        # il chooser NON avanza: la reliquia va ancora scelta
        if bonus.chooser_idx != 0 or bonus.completed:
                _fail("G: il riscatto non deve completare la schermata")
                return
        bonus.queue_free()
        p.queue_free()
        _ok("G: riga riscatto — 2 cuori = 12000 punti, +2 vite, escalation, chooser intatto")


# --- H: guardie sorgente ---------------------------------------------------------
func _test_source_guards() -> void:
        var guards := {
                        "GameConstants (Task 107)": [
                                        "res://scripts/core/GameConstants.gd",
                                        ["HIDDEN_HEART_EVERY_LEVELS", "HEART_REDEEM_BASE_COST",
                                                        "hidden_heart_spawns_at",
                                                        "heart_redeem_cost",
                                                        "heart_redeem_max_count",
                                                        "heart_redeem_total_cost"]],
                        "MainGame (spawn + pickup + snapshot cuore)": [
                                        "res://scripts/core/MainGameController.gd",
                                        ["_pop_hidden_heart_cell",
                                                        "Kind.HEART",
                                                        "items[\"hiddenheart\"]",
                                                        "\"hiddenheart\": CollectiblesClass.Kind.HEART",
                                                        "\"hearts_redeemed\": player.hearts_redeemed"]],
                        "GameManager (energia nel carry)": [
                                        "res://scripts/core/GameManager.gd",
                                        ["\"energy\": int(p.get(\"energy\"))",
                                                        "\"hearts_redeemed\": int(p.get(\"hearts_redeemed\"))",
                                                        "snap.has(\"energy\")"]],
                        "Player (spend_score + contatore)": [
                                        "res://scripts/core/Player.gd",
                                        ["func spend_score", "var hearts_redeemed",
                                                        "hearts_redeemed = 0"]],
                        "BonusScreen (riga riscatto)": [
                                        "res://scripts/ui/BonusScreen.gd",
                                        ["_draw_redeem_row", "_apply_redeem",
                                                        "_refresh_redeem_max",
                                                        "bonus.redeem_title",
                                                        "hearts_redeemed"]],
                        "I18n (testi riscatto)": [
                                        "res://scripts/core/I18nManager.gd",
                                        ["bonus.redeem_title", "bonus.redeem_score",
                                                        "bonus.redeem_insufficient",
                                                        "bonus.redeem_hint"]],
                        "Collectibles (cuore)": [
                                        "res://scripts/items/Collectibles.gd",
                                        ["HEART,", "make_heart", "_draw_heart"]],
        }
        for label in guards.keys():
                var spec: Array = guards[label]
                var src: String = _read(str(spec[0]))
                var missing: Array = []
                for needle in spec[1]:
                        if not src.contains(str(needle)):
                                missing.append(needle)
                if not missing.is_empty():
                        _fail("H: %s senza: %s" % [label, ", ".join(missing)])
        _ok("H: guardie sorgente (spawn/pickup/carry/UI/i18n wired)")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var content := f.get_as_text()
        f.close()
        return content
