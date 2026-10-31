## test_task107_hearts.gd — TASK 107/108 (CUORI): energia persistente tra
## scene, cuore nascosto nel labirinto, economia dello SHOP del mago.
##
## Check:
##   A — regola di spawn del cuore nascosto (ogni 3 labirinti, mai sui
##       boss) e indice labirinto
##   B — TASK 108: prezzi shop ordinati (voodoo > cuore > medikit) e
##       soglia di nascita dello shop (>= costo del cuore, mai sui boss);
##       la vecchia escalation del riscatto in bonus screen NON esiste piu'
##   C — Player.spend_score: punteggio scende (mai sotto 0), livello =
##       high watermark (non scende)
##   D — ENERGIA NEL CARRY: carry->restore NON rifila piu' l'energia piena
##       (era il refill a ogni cambio scena), clamp al max; NG+ NON la
##       conserva; la bambola voodoo attraversa le scene nel carry
##   E — restore_relic_armor NON cura piu' (solo clamp); equip (scelta in
##       bonus) cura ancora piena (reward design)
##   F — Collectibles: Kind.HEART + factory make_heart attiva
##   G — TASK 108: la BonusScreen NON contiene piu' la riga riscatto
##       (rimossa: il cuore si compra nello SHOP)
##   H — guardie sorgente (spawn, pickup, snapshot, shop, i18n)
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const PlayerScript = preload("res://scripts/core/Player.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

var fails: int = 0


func _ready() -> void:
        print("[TEST] === TASK 107/108: CUORI + SHOP ===")
        _test_spawn_rule()
        _test_shop_economy()
        _test_spend_score()
        _test_energy_carry()
        _test_armor_restore_no_heal()
        _test_collectible_heart()
        _test_bonus_no_redeem()
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


# --- B: economia dello SHOP (Task 108) ----------------------------------------
func _test_shop_economy() -> void:
        # ordine dei prezzi richiesto dall'utente: voodoo > cuore > medikit
        if not (C.SHOP_COST_VOODOO > C.SHOP_COST_HEART
                        and C.SHOP_COST_HEART > C.SHOP_COST_MEDICIT):
                _fail("B: ordine prezzi sbagliato (v%d h%d m%d)" % [
                                C.SHOP_COST_VOODOO, C.SHOP_COST_HEART,
                                C.SHOP_COST_MEDICIT])
                return
        # il cuore costa circa un boss (2500..4100)
        var boss_min: int = C.BOSS_KILL_POINTS_BASE
        var boss_max: int = C.BOSS_KILL_POINTS_BASE + 16 * C.BOSS_KILL_POINTS_PER_INDEX
        if C.SHOP_COST_HEART < boss_min or C.SHOP_COST_HEART > boss_max * 1.6:
                _fail("B: cuore %d fuori range boss %d..%d" % [
                                C.SHOP_COST_HEART, boss_min, boss_max])
                return
        # shop: nasce dal primo livello con punti >= costo del cuore, MAI sui boss
        if C.shop_spawns_at(3, C.SHOP_COST_HEART) != true:
                _fail("B: shop deve nascere con score = costo cuore")
                return
        if C.shop_spawns_at(3, C.SHOP_COST_HEART - 1) != false:
                _fail("B: shop NON deve nascere sotto il costo del cuore")
                return
        if C.shop_spawns_at(4, 999999) != false:
                _fail("B: shop MAI sui livelli boss (4)")
                return
        # la vecchia escalation del riscatto e' stata RIMOSSA da GameConstants
        var src: String = _read("res://scripts/core/GameConstants.gd")
        if src.contains("heart_redeem_cost") or src.contains("HEART_REDEEM_BASE_COST"):
                _fail("B: resti dell'escalazione heart_redeem in GameConstants")
                return
        _ok("B: shop = voodoo %d > cuore %d (~1 boss) > medikit %d; soglia spawn = costo cuore, mai sui boss" % [
                        C.SHOP_COST_VOODOO, C.SHOP_COST_HEART, C.SHOP_COST_MEDICIT])


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
        # la bambola si azzera a reset (run nuova)
        p.voodoo_equipped = true
        p.possession_active = true
        p.reset()
        if p.voodoo_equipped or p.possession_active:
                _fail("C: reset() non azzera voodoo/possessione")
                return
        p.queue_free()
        _ok("C: spend_score clampa a 0; livello = high watermark; reset azzera voodoo/possessione")


# --- D: ENERGIA NEL CARRY (niente refill tra scene) ----------------------------
func _test_energy_carry() -> void:
        var p1 := PlayerScript.new()
        add_child(p1)
        p1.reset()
        p1.energy = 2           # cuore corrente parzialmente sgretolato
        p1.lives = 4
        p1.score = 5000
        p1.voodoo_equipped = true
        GameManager.save_player_carry(p1)
        var carry: Dictionary = GameManager.carry_p1
        if int(carry.get("energy", -1)) != 2:
                _fail("D: carry senza energia (%s)" % str(carry.keys()))
                return
        if not bool(carry.get("voodoo_equipped", false)):
                _fail("D: carry senza bambola voodoo")
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
        if not p2.voodoo_equipped:
                _fail("D: restore_player_carry deve trasportare la bambola")
                return
        # clamp al max (energia salvata oltre il massimo corrente)
        p1.energy = 9
        GameManager.save_player_carry(p1)
        GameManager.restore_player_carry(p2)
        if p2.energy != p2.max_energy:
                _fail("D: energia trasportata non clampata al max (%d/%d)" % [
                                p2.energy, p2.max_energy])
                return
        # possession-aware: mentre e' posseduto il carry porta l'energia REALE
        p1.reset()
        p1.energy = 3
        p1.begin_possession(null, 12, 40)
        if p1.energy != 12:
                _fail("D: setup possessione fallito (%d)" % p1.energy)
                return
        GameManager.save_player_carry(p1)
        if int(GameManager.carry_p1.get("energy", -1)) != 3:
                _fail("D: il carry durante la possessione deve portare l'energia REALE (%s)" % str(GameManager.carry_p1.get("energy")))
                return
        p1.handle_possession_death()
        # NG+: la progressione conservata NON include energia ne' bambola
        GameManager.save_player_carry(p1)
        p1.voodoo_equipped = true
        GameManager.save_player_carry(p1)
        var kept: Dictionary = GameManager._ngp_kept_progression(GameManager.carry_p1)
        if kept.has("energy") or kept.has("voodoo_equipped"):
                _fail("D: NG+ NON deve conservare energia/bambola (%s)" % str(kept.keys()))
                return
        p1.queue_free()
        p2.queue_free()
        GameManager.carry_p1 = {}
        _ok("D: l'energia attraversa le scene (NO refill), possession-aware, bambola nel carry, NG+ pulito")


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


# --- G: BonusScreen senza riga riscatto ------------------------------------------
func _test_bonus_no_redeem() -> void:
        var bonus_src: String = _read("res://scripts/ui/BonusScreen.gd")
        for needle in ["_draw_redeem_row", "_apply_redeem", "_redeem_focus",
                        "bonus.redeem"]:
                if bonus_src.contains(str(needle)):
                        _fail("G: BonusScreen contiene ancora '%s' (riscatto rimosso dal Task 108)" % str(needle))
                        return
        _ok("G: BonusScreen NON ha piu' la riga riscatto (il cuore si compra nello SHOP)")


# --- H: guardie sorgente ---------------------------------------------------------
func _test_source_guards() -> void:
        var guards := {
                        "GameConstants (Task 107/108)": [
                                        "res://scripts/core/GameConstants.gd",
                                        ["HIDDEN_HEART_EVERY_LEVELS", "SHOP_COST_VOODOO",
                                                        "SHOP_COST_HEART", "SHOP_COST_MEDICIT",
                                                        "hidden_heart_spawns_at",
                                                        "shop_spawns_at"]],
                        "MainGame (spawn + pickup + snapshot cuore/shop/voodoo)": [
                                        "res://scripts/core/MainGameController.gd",
                                        ["_pop_hidden_heart_cell",
                                                        "Kind.HEART",
                                                        "items[\"hiddenheart\"]",
                                                        "\"hiddenheart\": CollectiblesClass.Kind.HEART",
                                                        "_try_spawn_shop",
                                                        "_update_shop_entry",
                                                        "_throw_voodoo_doll",
                                                        "_update_thrown_voodoo",
                                                        "_apply_voodoo_possession",
                                                        "_finish_possession_death",
                                                        "snap[\"shop\"]"]],
                        "GameManager (energia + voodoo nel carry)": [
                                        "res://scripts/core/GameManager.gd",
                                        ["\"energy\": int(p.get_real_energy())",
                                                        "\"voodoo_equipped\": bool(p.get(\"voodoo_equipped\"))",
                                                        "snap.has(\"energy\")"]],
                        "Player (spend_score + possessione)": [
                                        "res://scripts/core/Player.gd",
                                        ["func spend_score", "var voodoo_equipped",
                                                        "func begin_possession",
                                                        "func handle_possession_death",
                                                        "func update_possession_puppet",
                                                        "possession_death_pending = true"]],
                        "BonusScreen (riscatto rimosso)": [
                                        "res://scripts/ui/BonusScreen.gd",
                                        ["_apply_choice", "HOLD_CONFIRM_MS"]],
                        "ShopScreen (negozio del mago)": [
                                        "res://scripts/ui/ShopScreen.gd",
                                        ["_item_defs", "_buy_item", "_lock_reason",
                                                        "shop_exited", "_exit_shop",
                                                        "shop.item.voodoo",
                                                        "shop.buy"]],
                        "ShopStall (casa strega)": [
                                        "res://scripts/items/ShopStall.gd",
                                        ["shop_witch_hut.png", "shop_sign_closed.png",
                                                        "shop.closed", "entry_rect"]],
                        "VoodooDoll (bambola in volo)": [
                                        "res://scripts/items/VoodooDoll.gd",
                                        ["item_voodoo.png", "MAX_TRAVEL_PX",
                                                        "push_trail_point"]],
                        "I18n (testi shop)": [
                                        "res://scripts/core/I18nManager.gd",
                                        ["shop.title", "shop.item.voodoo",
                                                        "shop.buy", "shop.exit",
                                                        "shop.closed"]],
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
        _ok("H: guardie sorgente (spawn/pickup/carry/shop/voodoo/UI/i18n wired)")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var content := f.get_as_text()
        f.close()
        return content
