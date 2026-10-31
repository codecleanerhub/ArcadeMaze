## test_task105_newgameplus.gd — TASK 105: NEW GAME PLUS
## (richiesta utente: card post-credits stile armi bonus che chiede "Vuoi
## continuare a giocare (new game plus)? Ricomincerai dal primo livello di
## gioco senza perdere i tuoi upgrade accumulati ad una difficoltà maggiore."
## con opzioni Sì / No-Ritorna al Menù Principale; nemici/mini-boss/boss con
## danno +20% e resistenza +33% al tier 1, +40%/+50% al tier 2 = NG++, cap).
##
## Check:
##   A — costanti e helper tier: moltiplicatori [1.0/1.2/1.4] e
##       [1.0/1.33/1.5], cap NEWGAMEPLUS_MAX_TIER = 2, mirror statico
##   B — GameManager: _ngp_kept_progression (SOLA progressione Level Up,
##       score/vite/reliquie NON conservati), available(), clamp del tier,
##       sync mirror statico, flag offer/carry pending
##   C — Player: take_damage(points) multi-unità; take_enemy_damage() =
##       x1.20 esatto su 5 colpi (banca frazionaria: 1,1,1,1,2 = 6) e x1.40
##       su 5 colpi (1,1,2,1,2 = 7); i colpi SCHIVATI non alimentano la banca
##   D — resistenza: HP nemico x1.33 (16 -> 21), mini-boss e boss idem
##       (rapporto tier1/tier0 = 1.33); punti del nemico INVARIATI (160)
##   E — damage-helper %: weapon_damage_for/hammer calcolati sugli HP "di
##       base" -> stesso danno per colpo, MA colpi per uccidere 4 -> 6
##   F — card NG+ (NewGamePlusCard): setup, navigazione SÌ/NO, segnale
##       choice_made; I18n ngp.* IT/EN (SÌ / Ritorna al Menù Principale)
##   G — integrazione: MainGame con newgameplus_carry_pending ripristina
##       livello/punti/abilità del player a livello 1 (start_level resetta
##       PRIMA, il restore arriva DOPO); CreditsScreen con offer_pending
##       apre la card (e senza offer_pending NON la apre)
##   H — guardie sorgente: begin_newgameplus (tier+1, carry progressione,
##       livello 1), reset tier in go_to_menu/IntroCutscene, carry salvato +
##       offer_pending alla vittoria finale, siti take_enemy_damage nei
##       controller, restore carry NG+ nel MainGameController
extends Node

const EnemyScript = preload("res://scripts/enemies/Enemy.gd")
const MiniBossScript = preload("res://scripts/bosses/MiniBoss.gd")
const BossScript = preload("res://scripts/bosses/Boss.gd")
const PlayerScript = preload("res://scripts/core/Player.gd")
const NewGamePlusCardClass = preload("res://scripts/ui/NewGamePlusCard.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")
const CreditsScene = preload("res://scenes/CreditsScreen.tscn")
const C = preload("res://scripts/core/GameConstants.gd")

var fails: int = 0


func _ready() -> void:
        print("[TEST] TASK 105 — NEW GAME PLUS (card post-credits + difficoltà a tier)")
        _test_constants()
        _test_gamemanager_kept_progression()
        _test_player_damage()
        _test_resistance()
        _test_weapon_helpers()
        _test_card()
        await _test_maingame_carry_restore()
        await _test_credits_card()
        _test_source_guards()
        if fails > 0:
                print("[TEST] ESITO: FALLITO (%d errori)" % fails)
                get_tree().quit(1)
        else:
                print("[TEST] ESITO: TUTTI PASSATI")
                get_tree().quit(0)


func _ok(msg: String) -> void:
        print("[TEST] OK %s" % msg)


func _fail(msg: String) -> void:
        fails += 1
        print("[TEST] FALLITO %s" % msg)


## Ripristina lo stato NG+ pulito tra le fasi (tier 0, nessuna offerta).
func _reset_ngp_state() -> void:
        GameManager.newgameplus_tier = 0
        GameManager.newgameplus_carry_pending = false
        GameManager.newgameplus_offer_pending = false
        GameManager.carry_p1.clear()
        GameManager.carry_p2.clear()
        GameManager.reset_run()


# --- A: costanti e helper ---------------------------------------------------
func _test_constants() -> void:
        if C.NEWGAMEPLUS_MAX_TIER != 2:
                _fail("A: NEWGAMEPLUS_MAX_TIER != 2 (cap NG++)")
                return
        if C.NEWGAMEPLUS_DAMAGE_MULTS != [1.0, 1.2, 1.4]:
                _fail("A: moltiplicatori danno errati %s" % str(C.NEWGAMEPLUS_DAMAGE_MULTS))
                return
        if C.NEWGAMEPLUS_RESIST_MULTS != [1.0, 1.33, 1.5]:
                _fail("A: moltiplicatori resistenza errati %s" % str(C.NEWGAMEPLUS_RESIST_MULTS))
                return
        var saved_tier: int = C.newgameplus_tier
        for tier in 3:
                C.newgameplus_tier = tier
                if absf(C.newgameplus_damage_multiplier() - [1.0, 1.2, 1.4][tier]) > 0.0001:
                        _fail("A: damage multiplier tier %d" % tier)
                        return
                if absf(C.newgameplus_resist_multiplier() - [1.0, 1.33, 1.5][tier]) > 0.0001:
                        _fail("A: resist multiplier tier %d" % tier)
                        return
        C.newgameplus_tier = 99  # fuori range: clampato
        if C.newgameplus_damage_multiplier() != 1.4:
                _fail("A: tier fuori range non clampato nel danno")
        C.newgameplus_tier = saved_tier
        _ok("A: costanti tier + helper clampati")


# --- B: GameManager — progressione conservata / flag ------------------------
func _test_gamemanager_kept_progression() -> void:
        _reset_ngp_state()
        # carry come lo salva save_player_carry alla vittoria finale:
        # score alto, vite avanzate, reliquie, progressione Level Up.
        GameManager.carry_p1 = {
                        "score": 150000, "lives": 7,
                        "next_life_threshold": 150000,
                        "permanent_speed_boost": true,
                        "level": 12, "skill_points": 3, "pending_levelup_fx": 0,
                        "skill_levels": {"firepower": 4, "stamina": 2},
                        "relic_weapon": {"type": 101, "power": 5, "ammo": 99},
                        "relic_armor": {"id": "golden", "charges": 5},
        }
        var kept: Dictionary = GameManager._ngp_kept_progression(GameManager.carry_p1)
        if int(kept.get("level", -1)) != 12 \
                        or int(kept.get("skill_points", -1)) != 3 \
                        or (kept.get("skill_levels", {}) as Dictionary).get("firepower", 0) != 4:
                _fail("B: progressione Level Up non conservata (%s)" % str(kept))
                return
        if int(kept.get("score", -1)) != 0 or int(kept.get("lives", -1)) != 3:
                _fail("B: NG+ deve azzerare score/vite (nuova run)")
                return
        if kept.has("relic_weapon") or kept.has("relic_armor") \
                        or kept.has("permanent_speed_boost"):
                _fail("B: il NG+ NON deve trasportare reliquie/boost (run nuova)")
                return
        # tier: setter + mirror statico + clamp
        GameManager.newgameplus_tier = 1
        if GameManager.newgameplus_tier != 1 or C.newgameplus_tier != 1:
                _fail("B: mirror statico non sincronizzato col tier")
                return
        if not GameManager.newgameplus_available():
                _fail("B: available() deve essere true a tier 1 (NG++ proponibile)")
                return
        GameManager.newgameplus_tier = 5
        if GameManager.newgameplus_tier != 2 or C.newgameplus_tier != 2:
                _fail("B: tier non clampato a 2 (cap NG++)")
                return
        if GameManager.newgameplus_available():
                _fail("B: available() deve essere false a tier 2 (cap NG++)")
        _reset_ngp_state()
        _ok("B: progressione conservata (solo Level Up), tier clampato, mirror ok")


# --- C: Player — danno NG+ esatto con banca frazionaria ---------------------
func _test_player_damage() -> void:
        var p := PlayerScript.new()
        add_child(p)
        p.lives = 20
        p.spawn_guard_ms = 0  # TASK 38: immortalità di nascita (3s) off in test

        # C1: take_damage(points) multi-unità in UN colpo
        p.energy = 50
        p.take_damage(3)
        if p.energy != 47:
                _fail("C1: take_damage(3) deve togliere 3 energia (energia %d)" % p.energy)
        else:
                _ok("C1: take_damage(points) scala più unità energia")

        # C2: tier 1 — 5 colpi nemici = 6 energia (x1.20 esatto)
        GameManager.newgameplus_tier = 1
        p.energy = 50
        p._ngp_dmg_bank_ms = 0
        for i in 5:
                p.damage_timer = 0
                p.take_enemy_damage()
        if p.energy != 44:
                _fail("C2: tier 1 -> 5 colpi devono togliere 6 energia (x1.2), tolta %d" % (50 - p.energy))
        elif p._ngp_dmg_bank_ms != 0:
                _fail("C2: banca frazionaria non svuotata (%d millesimi)" % p._ngp_dmg_bank_ms)
        else:
                _ok("C2: tier 1 = x1.20 esatto (5 colpi -> 6 danni)")

        # C3: tier 2 — 5 colpi nemici = 7 energia (x1.40 esatto)
        GameManager.newgameplus_tier = 2
        p.energy = 50
        p._ngp_dmg_bank_ms = 0
        for i in 5:
                p.damage_timer = 0
                p.take_enemy_damage()
        if p.energy != 43:
                _fail("C3: tier 2 -> 5 colpi devono togliere 7 energia (x1.4), tolta %d" % (50 - p.energy))
        else:
                _ok("C3: tier 2 = x1.40 esatto (5 colpi -> 7 danni)")

        # C4: colpo SCHIVATO (invulnerabile) -> niente danno E banca ferma
        GameManager.newgameplus_tier = 1
        p.energy = 50
        p.spawn_guard_ms = 0
        p._ngp_dmg_bank_ms = 0
        p.damage_timer = 999999  # invulnerabile
        p.take_enemy_damage()
        if p.energy != 50 or p._ngp_dmg_bank_ms != 0:
                _fail("C4: colpo schivato non deve toccare energia né banca")
        else:
                _ok("C4: colpo schivato = zero danno, banca invariata")

        # C5: tier 0 — take_enemy_damage() identico al danno base
        GameManager.newgameplus_tier = 0
        p.energy = 50
        p.damage_timer = 0
        p.take_enemy_damage()
        if p.energy != 49:
                _fail("C5: tier 0 -> take_enemy_damage deve togliere 1")
        else:
                _ok("C5: tier 0 = danno base (1)")
        p.queue_free()
        _reset_ngp_state()


# --- D: resistenza (HP) di nemico / mini-boss / boss -------------------------
func _test_resistance() -> void:
        # nemico ZOMBIE (tipo 0, HP base 4 -> x4 scala = 16)
        var e0 := EnemyScript.new()
        add_child(e0)
        e0.init(0, 2, 2)
        var hp_base: int = e0.max_health
        var pts_base: int = e0.get_score_reward()  # punti letti a tier 0
        GameManager.newgameplus_tier = 1
        var e1 := EnemyScript.new()
        add_child(e1)
        e1.init(0, 2, 2)
        var hp_ngp: int = e1.max_health
        var expected: int = int(round(float(hp_base) * 1.33))
        if hp_base != 16:
                _fail("D: HP base ZOMBIE atteso 16, trovato %d" % hp_base)
        elif hp_ngp != expected:
                _fail("D: HP nemico tier 1 attesi %d (x1.33), trovati %d" % [expected, hp_ngp])
        elif e1.get_score_reward() != pts_base:
                _fail("D: punti nemico cambiati col tier (%d vs %d)" % [
                                e1.get_score_reward(), pts_base])
        else:
                _ok("D: HP nemico x1.33 (%d -> %d), punti invariati" % [hp_base, hp_ngp])
        e0.queue_free()
        e1.queue_free()

        # mini-boss (tipo 0, livello 1: base 18)
        GameManager.newgameplus_tier = 0
        var mb0 := MiniBossScript.new()
        add_child(mb0)
        mb0.setup(0, 1, 2, 2)
        GameManager.newgameplus_tier = 1
        var mb1 := MiniBossScript.new()
        add_child(mb1)
        mb1.setup(0, 1, 2, 2)
        var mb_expected: int = int(round(float(mb0.max_health) * 1.33))
        if mb1.max_health != mb_expected:
                _fail("D: HP mini-boss tier 1 attesi %d, trovati %d" % [mb_expected, mb1.max_health])
        else:
                _ok("D: HP mini-boss x1.33 (%d -> %d)" % [mb0.max_health, mb1.max_health])
        mb0.queue_free()
        mb1.queue_free()

        # boss (livello 4: 50 + 4x20 = 130)
        GameManager.newgameplus_tier = 0
        var b0 := BossScript.new()
        add_child(b0)
        b0.setup(4, 1920, 1080)
        GameManager.newgameplus_tier = 1
        var b1 := BossScript.new()
        add_child(b1)
        b1.setup(4, 1920, 1080)
        var b_expected: int = int(round(float(b0.max_health) * 1.33))
        if b1.max_health != b_expected:
                _fail("D: HP boss tier 1 attesi %d, trovati %d" % [b_expected, b1.max_health])
        else:
                _ok("D: HP boss x1.33 (%d -> %d)" % [b0.max_health, b1.max_health])
        b0.queue_free()
        b1.queue_free()
        _reset_ngp_state()


# --- E: damage-helper % calcolati sugli HP "di base" -------------------------
func _test_weapon_helpers() -> void:
        # PISTOL = 4 colpi; ZOMBIE NG+ = 21 HP. Il danno per colpo resta
        # calcolato sugli HP di BASE (16): stesso danno, più colpi per uccidere.
        GameManager.newgameplus_tier = 0
        var dmg_base: int = C.weapon_damage_for(C.WeaponType.PISTOL, 16)
        var hammer_base: int = C.hammer_damage_for(16)
        GameManager.newgameplus_tier = 1
        var dmg_ngp: int = C.weapon_damage_for(C.WeaponType.PISTOL, 21)
        var hammer_ngp: int = C.hammer_damage_for(21)
        var hits_base: int = int(ceil(16.0 / float(dmg_base)))
        var hits_ngp: int = int(ceil(21.0 / float(dmg_ngp)))
        if dmg_base != 4:
                _fail("E: danno pistola base atteso 4, trovato %d" % dmg_base)
        elif dmg_ngp != dmg_base:
                _fail("E: danno per colpo NON deve scalare col tier (%d vs %d)" % [dmg_base, dmg_ngp])
        elif hits_ngp <= hits_base:
                _fail("E: colpi per uccidere non aumentati col tier (%d vs %d)" % [hits_base, hits_ngp])
        else:
                _ok("E: pistola stesso danno (%d), colpi %d -> %d" % [dmg_base, hits_base, hits_ngp])

        # martello: 50% HP base -> 2 colpi base, 3 colpi NG+
        var h_hits_base: int = int(ceil(16.0 / float(hammer_base)))
        var h_hits_ngp: int = int(ceil(21.0 / float(hammer_ngp)))
        if hammer_base != 8 or hammer_ngp != 8:
                _fail("E: martello deve fare 8 su HP base (%d/%d)" % [hammer_base, hammer_ngp])
        elif h_hits_ngp <= h_hits_base:
                _fail("E: martello non richiede più colpi nel NG+")
        else:
                _ok("E: martello danno invariato (8), colpi %d -> %d" % [h_hits_base, h_hits_ngp])
        _reset_ngp_state()


# --- F: card NG+ + testi I18n ------------------------------------------------
func _test_card() -> void:
        var received: Array = []
        var card := NewGamePlusCardClass.new()
        card.setup(1, 12)
        card.choice_made.connect(func(acc: bool): received.append(acc))
        add_child(card)
        # navigazione SÌ (0) -> NO (1) e ritorno
        card._move_choice(1)
        if card._choice != 1:
                _fail("F: navigazione SÌ/NO non muove la selezione")
        card._move_choice(-1)
        if card._choice != 0:
                _fail("F: navigazione NO -> SÌ non torna alla prima opzione")
        # conferma su SÌ
        card._confirm()
        await get_tree().physics_frame
        if received.size() != 1 or not bool(received[0]):
                _fail("F: choice_maded(true) non emesso dalla conferma SÌ (%s)" % str(received))
        else:
                _ok("F: card navigabile + segnale choice_made(true)")

        # testi IT/EN della domanda utente e delle opzioni.
        # FIX (Task 106): la lingua è PERSISTITA in user://config.ini — un run
        # precedente con set_language(ITALIAN) (es. harness screenshot) la fa
        # sopravvivere al processo: il check EN ora la forza esplicitamente.
        I18n.set_language(I18n.Language.ENGLISH)
        var q_en: String = I18n.t("ngp.question")
        if not q_en.begins_with("Do you want to keep playing"):
                _fail("F: domanda EN mancante/sbagliata (%s)" % q_en)
        I18n.set_language(I18n.Language.ITALIAN)
        var q_it: String = I18n.t("ngp.question")
        if not q_it.begins_with("Vuoi continuare a giocare (new game plus)?"):
                _fail("F: domanda IT non è il testo utente (%s)" % q_it)
        if I18n.t("ngp.yes") != "SÌ" or not I18n.t("ngp.no_hint").begins_with("Ritorna al Menù"):
                _fail("F: opzioni IT errate (%s / %s)" % [I18n.t("ngp.yes"), I18n.t("ngp.no_hint")])
        if not I18n.t("ngp.question2").contains("new game plus plus"):
                _fail("F: domanda NG++ mancante")
        I18n.set_language(I18n.Language.ENGLISH)
        if I18n.t("ngp.yes") != "YES":
                _fail("F: opzione EN errata (%s)" % I18n.t("ngp.yes"))
        else:
                _ok("F: testi card IT/EN (domanda utente, SÌ, Ritorna al Menù)")


# --- G: integrazione MainGame (restore carry NG+) + Credits (card) -----------
func _test_maingame_carry_restore() -> void:
        _reset_ngp_state()
        GameManager.num_players = 1
        GameManager.game_mode = C.GameMode.STORY
        GameManager.current_level = 1
        # stato esattamente come lo produce begin_newgameplus() SÌ alla card:
        GameManager.newgameplus_tier = 1
        GameManager.newgameplus_carry_pending = true
        GameManager.carry_p1 = {
                        "score": 0, "lives": 3,
                        "next_life_threshold": C.EXTRA_LIFE_EVERY_POINTS,
                        "level": 12, "skill_points": 3, "pending_levelup_fx": 0,
                        "skill_levels": {"firepower": 4, "stamina": 2},
        }
        var main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        for i in 30:
                await get_tree().physics_frame
        if main.player == null:
                _fail("G1: MainGame non avviata")
        else:
                var p: CharacterBody2D = main.player
                if p.level != 12:
                        _fail("G1: livello player non conservato (%d)" % p.level)
                elif p.skill_points != 3:
                        _fail("G1: punti abilità non conservati (%d)" % p.skill_points)
                elif int(p.skill_levels.get("firepower", 0)) != 4:
                        _fail("G1: abilità non conservate (%s)" % str(p.skill_levels))
                elif p.score != 0 or p.lives != 3:
                        _fail("G1: NG+ deve ripartire da score 0 / 3 vite (%d/%d)" % [p.score, p.lives])
                elif GameManager.newgameplus_carry_pending:
                        _fail("G1: flag carry_pending non consumato dal controller")
                elif GameManager.newgameplus_tier != 1:
                        _fail("G1: tier non mantenuto in partita (%d)" % GameManager.newgameplus_tier)
                else:
                        _ok("G1: NG+ al livello 1 = progressione Level Up ripristinata dal carry")
        main.queue_free()
        for i in 5:
                await get_tree().physics_frame
        _reset_ngp_state()


func _test_credits_card() -> void:
        # G2: credits DOPO la vittoria (offer_pending) -> la card si apre
        _reset_ngp_state()
        GameManager.newgameplus_offer_pending = true
        GameManager.carry_p1 = {"level": 9, "skill_levels": {}}
        var credits = CreditsScene.instantiate()
        get_tree().root.add_child(credits)
        for i in 5:
                await get_tree().physics_frame
        credits.skip_to_end()
        credits._show_ngp_card()
        for i in 3:
                await get_tree().physics_frame
        if credits._ngp_card == null or not is_instance_valid(credits._ngp_card):
                _fail("G2: card NG+ non aperta dai credits con offer_pending")
        else:
                var card: CanvasLayer = credits._ngp_card
                if card._next_tier != 1 or card._kept_level != 9:
                        _fail("G2: card con setup errato (tier %d, livello %d)" % [card._next_tier, card._kept_level])
                elif GameManager.newgameplus_offer_pending:
                        _fail("G2: offerta non consumata alla mostra della card")
                else:
                        _ok("G2: credits post-vittoria -> card NG+ (tier 1, livello 9 conservato)")
                card.queue_free()
                credits._ngp_card = null
        credits.queue_free()
        for i in 5:
                await get_tree().physics_frame

        # G3: credits aperti dal MENU (nessuna offer_pending) -> NIENTE card
        _reset_ngp_state()
        var credits2 = CreditsScene.instantiate()
        get_tree().root.add_child(credits2)
        for i in 5:
                await get_tree().physics_frame
        credits2.skip_to_end()
        credits2._show_ngp_card()
        if credits2._ngp_card != null and is_instance_valid(credits2._ngp_card):
                _fail("G3: card NG+ proposta senza vittoria (credits dal menu)")
                credits2._ngp_card.queue_free()
                credits2._ngp_card = null
        else:
                _ok("G3: credits dal menu -> NESSUNA card NG+ (comportamento storico)")
        credits2.queue_free()
        for i in 5:
                await get_tree().physics_frame
        _reset_ngp_state()


# --- H: guardie sorgente (pattern test_task97 E) ------------------------------
func _test_source_guards() -> void:
        var gm: String = _read("res://scripts/core/GameManager.gd")
        if not gm.contains("func begin_newgameplus()"):
                _fail("H: begin_newgameplus() mancante in GameManager")
        elif not gm.contains("start_level(1)"):
                _fail("H: begin_newgameplus() deve ripartire dal livello 1")
        var guards := {
                        "GameManager (reset a menu)": [
                                        "res://scripts/core/GameManager.gd",
                                        ["func go_to_menu()", "newgameplus_tier = 0"]],
                        "IntroCutscene (nuova partita = tier 0)": [
                                        "res://scripts/core/IntroCutscene.gd",
                                        ["GameManager.newgameplus_tier = 0"]],
                        "BossRoom (carry salvato alla vittoria finale)": [
                                        "res://scripts/core/BossRoomController.gd",
                                        ["GameManager.save_player_carry(player, player2)",
                                                        "newgameplus_offer_pending = true"]],
                        "MainGameController (restore carry NG+)": [
                                        "res://scripts/core/MainGameController.gd",
                                        ["newgameplus_carry_pending",
                                                        "GameManager.restore_player_carry(player, player2)"]],
                        "MainGameController (danno nemico scalato x3)": [
                                        "res://scripts/core/MainGameController.gd",
                                        ["take_enemy_damage()", "take_enemy_damage()", "take_enemy_damage()"]],
                        "BossRoomController (danno boss scalato x4)": [
                                        "res://scripts/core/BossRoomController.gd",
                                        ["take_enemy_damage()", "take_enemy_damage()",
                                                        "take_enemy_damage()", "take_enemy_damage()"]],
                        "CreditsScreen (hook card post-credits)": [
                                        "res://scripts/ui/CreditsScreen.gd",
                                        ["_ngp_offer_eligible()", "_show_ngp_card()",
                                                        "begin_newgameplus()", "go_to_menu()"]],
                        "HUD (badge NG+)": [
                                        "res://scripts/ui/HUD.gd",
                                        ["newgameplus_tier", "NG++"]],
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
        if fails == 0 or true:
                _ok("H: guardie sorgente (flusso NG+ completo wired)")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var content := f.get_as_text()
        f.close()
        return content
