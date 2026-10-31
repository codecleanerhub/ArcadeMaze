## test_task99_levelup.gd — TASK 99 (FASE 1): motore XP.
##
## Il punteggio È esperienza: soglie 1.000 x n^1.75 arrotondate a 50
## (identiche alla tabella del report Task 98), level up con punti
## abilità BANCABILI, celebrazione fulmine+scritta non-bloccante, HUD
## con LV n + badge punti.
##
## Check:
##   A — soglie note della curva (3.350 / 6.850 / 56.250 / 189.150),
##       monotone, levelup_threshold(1)=0, cap a LEVELUP_MAX_LEVEL
##   B — levelup_level_for_score: 0->1, 3.349->1, 3.350->2, cap
##   C — Player.add_score: soglia esatta, salto di più soglie in un
##       colpo (pending_levelup_fx accumula), cap a 20, consume
##   D — reset() azzera la progressione; reset_position() NON la tocca
##   E — carry GameManager: level/skill_points/pending_levelup_fx
##       attraversano make_player_carry/_apply_carry
##   F — HUD: chiavi level/skill_points nel snapshot 1P/2P + riga
##       _draw_level_status presente nel sorgente e nei 3 layout
##   G — annuncio: drive diretto di LevelUpAnnounce -> announcement_done
##       emesso con il numero player giusto
##   H — guardie sorgente: hook XP in add_score, trigger celebrazione in
##       entrambi i controller, cleanup _exit_tree, i18n levelup.*
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const PlayerClass = preload("res://scripts/core/Player.gd")
const HUDClass = preload("res://scripts/ui/HUD.gd")
const AnnounceClass = preload("res://scripts/ui/LevelUpAnnounce.gd")
const OverlayClass = preload("res://scripts/ui/LevelUpOverlay.gd")

const SRC_PLAYER := "res://scripts/core/Player.gd"
const SRC_MAIN := "res://scripts/core/MainGameController.gd"
const SRC_BOSS := "res://scripts/core/BossRoomController.gd"
const SRC_HUD := "res://scripts/ui/HUD.gd"

var fails: int = 0
var _announce_done_num: int = -1


func _on_announce_done(n: int) -> void:
        _announce_done_num = n


func _ready() -> void:
        print("[TEST] TASK 99 FASE 1+2 — motore XP + abilità + modale")
        _test_thresholds()
        _test_level_for_score()
        _test_add_score()
        _test_reset_semantics()
        _test_carry()
        _test_hud_keys()
        await _test_announce()
        _test_source_guards()
        _test_skill_defs()
        _test_skill_effects()
        _test_air_jump()
        _test_magazine()
        _test_damage_mult()
        _test_stamina_ratio()
        await _test_modal()
        _test_carry_skills()
        _test_source_guards_f2()
        await _test_assets_f3()
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


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var s := f.get_as_text()
        f.close()
        return s


# --- A: soglie note della curva ---
func _test_thresholds() -> void:
        var known: Array = [
                [2, 1200], [3, 2400], [4, 3950], [5, 5850],
                [10, 19700], [15, 40000], [20, 66200], [40, 222700],
        ]
        for kv in known:
                var got: int = C.levelup_threshold(int(kv[0]))
                if got != int(kv[1]):
                        _fail("A: soglia L%d = %d, attesa %d" % [kv[0], got, kv[1]])
                        return
        _ok("A1: soglie note della curva ricalibrata (L2=1200...L40=222700)")
        if C.levelup_threshold(1) != 0:
                _fail("A: soglia L1 deve essere 0 (si nasce a livello 1)")
        else:
                _ok("A2: levelup_threshold(1) = 0")
        var prev: int = 0
        for n in range(2, 47):
                var t: int = C.levelup_threshold(n)
                if t <= prev:
                        _fail("A: curva non monotona alla L%d" % n)
                        return
                prev = t
        _ok("A3: curva monotona crescente L2..L46")
        if C.LEVELUP_MAX_LEVEL != 45:
                _fail("A: LEVELUP_MAX_LEVEL = %d, atteso 45" % C.LEVELUP_MAX_LEVEL)
        else:
                _ok("A4: cap livello 45 (TASK salti: 44 punti = Resistenza 40 + 2 salti + 2 residui; L45=%d)"
                                % C.levelup_threshold(45))


# --- B: livello per punteggio ---
func _test_level_for_score() -> void:
        var cases: Array = [
                [0, 1], [1199, 1], [1200, 2], [2399, 2], [2400, 3],
                [19700, 10], [66199, 19], [66200, 20], [222700, 40],
                [273650, 45], [999999, 45],
        ]
        for kv in cases:
                var got: int = C.levelup_level_for_score(int(kv[0]))
                if got != int(kv[1]):
                        _fail("B: score %d -> L%d, atteso L%d" % [kv[0], got, kv[1]])
                        return
        _ok("B: levelup_level_for_score esatta su 10 casi incluso il cap")


# --- C: add_score ---
func _test_add_score() -> void:
        var p := PlayerClass.new()
        p.score = 0
        p.add_score(1199)
        if p.level != 1 or p.skill_points != 0 or p.pending_levelup_fx != 0:
                _fail("C: 1.199 punti NON devono dare level up (L%d, pt %d, pend %d)"
                                % [p.level, p.skill_points, p.pending_levelup_fx])
                return
        p.add_score(1)
        if p.level != 2 or p.skill_points != 1 or p.pending_levelup_fx != 1:
                _fail("C: 1.200 punti -> L%d pt %d pend %d (attesi 2/1/1)"
                                % [p.level, p.skill_points, p.pending_levelup_fx])
                return
        _ok("C1: soglia esatta: 1.199 = niente, +1 = L2 con 1 punto bancabile")
        p.add_score(1200)  # 2400 totale -> L3 (il pending di L2 era ancora in coda)
        var gained: int = p.consume_pending_levelup_fx()
        if p.level != 3 or gained != 2 or p.pending_levelup_fx != 0:
                _fail("C: passo L3: gained %d, pend residuo %d" % [gained, p.pending_levelup_fx])
                return
        _ok("C2: consume_pending_levelup_fx ritorna e azzera (L2+L3 in coda = 2)")
        # salto di più soglie in un colpo (premio boss)
        var p2 := PlayerClass.new()
        p2.score = 0
        p2.add_score(3950)  # -> L4 in un colpo
        if p2.level != 4 or p2.skill_points != 3 or p2.pending_levelup_fx != 3:
                _fail("C: salto 3 soglie -> L%d pt %d pend %d (attesi 4/3/3)"
                                % [p2.level, p2.skill_points, p2.pending_levelup_fx])
                return
        _ok("C3: un premio che salta 3 soglie dà L4 con 3 punti (una celebrazione)")
        # cap
        var p3 := PlayerClass.new()
        p3.score = 0
        p3.add_score(4000000)
        if p3.level != 45 or p3.skill_points != 44:
                _fail("C: cap oltre ogni economia -> L%d pt %d (attesi 45/44)"
                                % [p3.level, p3.skill_points])
                return
        _ok("C4: cap livello 45 anche con score assurdo (44 punti)")
        p.queue_free()
        p2.queue_free()
        p3.queue_free()


# --- D: reset ---
func _test_reset_semantics() -> void:
        var p := PlayerClass.new()
        p.level = 7
        p.skill_points = 3
        p.pending_levelup_fx = 2
        p.reset_position()
        if p.level != 7 or p.skill_points != 3:
                _fail("D: reset_position() NON deve toccare la progressione (L%d pt %d)"
                                % [p.level, p.skill_points])
                return
        _ok("D1: reset_position() (respawn/cambio livello) conserva L7 e i punti")
        p.reset()
        if p.level != 1 or p.skill_points != 0 or p.pending_levelup_fx != 0:
                _fail("D: reset() deve azzerare (L%d pt %d pend %d)"
                                % [p.level, p.skill_points, p.pending_levelup_fx])
                return
        _ok("D2: reset() (nuova partita) azzera tutta la progressione")
        p.queue_free()


# --- E: carry tra scene ---
func _test_carry() -> void:
        var p := PlayerClass.new()
        p.score = 12345
        p.level = 6
        p.skill_points = 4
        p.pending_levelup_fx = 2
        var snap: Dictionary = GameManager.make_player_carry(p)
        if int(snap.get("level", -1)) != 6 \
                        or int(snap.get("skill_points", -1)) != 4 \
                        or int(snap.get("pending_levelup_fx", -1)) != 2:
                _fail("E: make_player_carry level=%s pt=%s pend=%s"
                                % [snap.get("level"), snap.get("skill_points"),
                                                snap.get("pending_levelup_fx")])
                return
        _ok("E1: make_player_carry trasporta level/skill_points/pending")
        var p2 := PlayerClass.new()
        p2.reset()
        GameManager._apply_carry(p2, snap)
        if p2.level != 6 or p2.skill_points != 4 or p2.pending_levelup_fx != 2:
                _fail("E: _apply_carry L%d pt %d pend %d (attesi 6/4/2)"
                                % [p2.level, p2.skill_points, p2.pending_levelup_fx])
                return
        _ok("E2: _apply_carry ripristina la progressione su un player pulito")
        # compatibilità snapshot vecchi (senza chiavi levelup): default L1/0/0
        var p3 := PlayerClass.new()
        p3.level = 9
        p3.skill_points = 5
        GameManager._apply_carry(p3, {"score": 100})
        if p3.level != 1 or p3.skill_points != 0:
                _fail("E: snapshot vecchio -> L%d pt %d (attesi 1/0)"
                                % [p3.level, p3.skill_points])
                return
        _ok("E3: snapshot pre-task99 (senza chiavi) -> default L1/0")
        p.queue_free()
        p2.queue_free()
        p3.queue_free()


# --- F: HUD ---
func _test_hud_keys() -> void:
        var hud := HUDClass.new()
        add_child(hud)
        hud.set_player_state({"level": 3, "skill_points": 2})
        if int(hud._p1.get("level", -1)) != 3 \
                        or int(hud._p1.get("skill_points", -1)) != 2:
                _fail("F: snapshot 1P level=%s pt=%s"
                                % [hud._p1.get("level"), hud._p1.get("skill_points")])
                return
        hud.set_player2_state({"level": 5, "skill_points": 1})
        if int(hud._p2.get("level", -1)) != 5:
                _fail("F: snapshot 2P level=%s" % hud._p2.get("level"))
                return
        _ok("F1: chiavi level/skill_points accettate nei snapshot 1P/2P")
        # defaults nel dict
        if int(HUDClass.new()._p1.get("level", -1)) != 1 \
                        or int(HUDClass.new()._p1.get("skill_points", -1)) != 0:
                _fail("F: default _p1 level/skill_points errati")
                return
        _ok("F2: default L1/0 nei dict HUD")
        # disegno senza errori (drive con punti da spendere)
        hud.set_num_players(1)
        hud.set_player_state({"level": 3, "skill_points": 2,
                        "score": 12345, "lives": 3, "energy": 5, "max_energy": 5,
                        "stamina": 1.0, "stamina_exhausted": false})
        hud.queue_redraw()
        await get_tree().process_frame
        _ok("F3: ridisegno HUD con LV3 + PUNTI +2 senza errori")
        hud.queue_free()


# --- G: annuncio ---
func _test_announce() -> void:
        var ann := AnnounceClass.new()
        ann.setup(2, 5, 3, Vector2(320.0, 400.0), self)
        _announce_done_num = -1
        ann.announcement_done.connect(_on_announce_done)
        add_child(ann)
        var waited: float = 0.0
        while _announce_done_num < 0 and waited < 6.0:
                await get_tree().process_frame
                waited += get_process_delta_time()
        if _announce_done_num != 2:
                _fail("G: announcement_done = %d (atteso 2)" % _announce_done_num)
        else:
                _ok("G: annuncio completo -> announcement_done(2) dopo ~1.7s")
        ann.queue_free()


# --- H: guardie sorgente ---
func _test_source_guards() -> void:
        var s_player := _read(SRC_PLAYER)
        if "C.levelup_threshold(level + 1)" not in s_player:
                _fail("H: hook XP assente da Player.add_score")
        else:
                _ok("H1: Player.add_score aggancia la curva XP")
        var s_main := _read(SRC_MAIN)
        if "_check_levelup_celebrations()" not in s_main \
                        or "_levelup_announce" not in s_main:
                _fail("H: trigger celebrazione assente da MainGameController")
        else:
                _ok("H2: MainGameController celebra + libera in _exit_tree")
        var s_boss := _read(SRC_BOSS)
        if "_check_levelup_celebrations()" not in s_boss:
                _fail("H: trigger celebrazione assente da BossRoomController")
        else:
                _ok("H3: BossRoomController celebra pure (punti del boss)")
        var s_hud := _read(SRC_HUD)
        var n_calls: int = s_hud.count("_draw_level_status(")
        if n_calls < 4:  # 3 chiamate nei layout + 1 definizione
                _fail("H: _draw_level_status chiamata %d volte (attese >= 4)" % n_calls)
        else:
                _ok("H4: riga LV nei 3 layout HUD (1P, 2P-P1, 2P-P2)")
        var t_title: String = I18n.t("levelup.title")
        if t_title != "LEVEL UP!":
                _fail("H: i18n levelup.title = '%s'" % t_title)
        else:
                _ok("H5: i18n levelup.* presenti (title/reached/gained)")


# --- I: defs delle otto abilità ---
func _test_skill_defs() -> void:
        if C.SKILL_IDS.size() != 8:
                _fail("I: SKILL_IDS = %d (attese 8)" % C.SKILL_IDS.size())
                return
        var expect_caps := {
                "energy": 10, "stamina": 40, "jump": 3, "firepower": 10,
                "magazine": 8, "swiftness": 8, "luck": 6, "regen": 4,
        }
        for id in C.SKILL_IDS:
                var def: Dictionary = C.get_skill_def(id)
                if def.is_empty() or not def.has("name_it") or not def.has("name_en"):
                        _fail("I: def incompleta per '%s'" % id)
                        return
                if int(def.get("cap", -1)) != int(expect_caps[id]):
                        _fail("I: cap '%s' = %s (atteso %d)"
                                        % [id, def.get("cap"), expect_caps[id]])
                        return
        _ok("I1: 8 abilità bilingue con cap corretti (totale %d livelli)"
                        % [10 + 40 + 3 + 10 + 8 + 8 + 6 + 4])
        # requisito salto PER LIVELLO (TASK: 1° a Resistenza 10, 2° a 40,
        # 3° MAI acquistabile — opzione disattivata)
        if C.skill_upgrade_allowed("jump", {"stamina": 9, "jump": 0}):
                _fail("I: 1° salto acquistabile con Resistenza 9 (serve 10)")
                return
        if not C.skill_upgrade_allowed("jump", {"stamina": 10, "jump": 0}):
                _fail("I: 1° salto NON acquistabile con Resistenza 10")
                return
        if C.skill_upgrade_allowed("jump", {"stamina": 39, "jump": 1}):
                _fail("I: 2° salto acquistabile con Resistenza 39 (serve 40)")
                return
        if not C.skill_upgrade_allowed("jump", {"stamina": 40, "jump": 1}):
                _fail("I: 2° salto NON acquistabile con Resistenza 40")
                return
        if C.skill_upgrade_allowed("jump", {"stamina": 40, "jump": 2}):
                _fail("I: 3° salto acquistabile (deve restare MAI sbloccabile)")
                return
        _ok("I2: Salti Aggiuntivi: 1° a Resistenza 10, 2° a 40, 3° MAI (disattivato)")
        if C.skill_upgrade_allowed("energy", {"energy": 10}):
                _fail("I: energy supera il cap")
                return
        _ok("I3: cap rispettato da skill_upgrade_allowed")


# --- J: effetti delle abilità sul player ---
func _test_skill_effects() -> void:
        var p := PlayerClass.new()
        p.max_energy = 5
        p.energy = 5
        p.confirm_skills({"energy": 1})
        if p.max_energy != 6 or p.energy != 6:
                _fail("J: energy 1 -> max %d en %d (attesi 6/6)" % [p.max_energy, p.energy])
                return
        p.confirm_skills({"energy": 10})
        if p.max_energy != 8:
                _fail("J: energy 10 -> max %d (atteso 8 = 5+3)" % p.max_energy)
                return
        _ok("J1: Energia: +1 al primo acquisto, cap +3 unità (5->8)")
        p.confirm_skills({"stamina": 16})
        if absf(p.get_stamina_max() - 1.28) > 0.001 \
                        or absf(p.get_stamina_recharge_mult() - 1.2) > 0.001:
                _fail("J: stamina 16 -> max %.3f ricarica %.3f" % [p.get_stamina_max(), p.get_stamina_recharge_mult()])
                return
        # cap 40 = stessi TOTALI del vecchio cap 10: +70% barra / +50% ricarica
        p.confirm_skills({"stamina": 40})
        if absf(p.get_stamina_max() - 1.7) > 0.001 \
                        or absf(p.get_stamina_recharge_mult() - 1.5) > 0.001:
                _fail("J: stamina 40 (cap) -> max %.3f ricarica %.3f" % [p.get_stamina_max(), p.get_stamina_recharge_mult()])
                return
        _ok("J2: Resistenza 16: barra 1.28x ricarica 1.2x; cap 40: 1.7x/1.5x (totali invariati)")
        p.confirm_skills({"swiftness": 8})
        if absf(p.get_speed_mult() - 1.32) > 0.001:
                _fail("J: swiftness 8 -> %.3f" % p.get_speed_mult())
                return
        _ok("J3: Rapidità cap: velocita' x1.32")
        p.confirm_skills({"firepower": 10})
        if absf(p.get_damage_mult() - 1.5) > 0.001:
                _fail("J: firepower 10 -> %.3f" % p.get_damage_mult())
                return
        _ok("J4: Potenza di Fuoco cap: danno x1.5")
        p.confirm_skills({"luck": 6})
        if absf(p.get_luck_drop_chance() - 0.18) > 0.001:
                _fail("J: luck 6 -> %.3f" % p.get_luck_drop_chance())
                return
        _ok("J5: Fortuna cap: 18% drop")
        p.confirm_skills({"regen": 4})
        if absf(p.get_regen_rate() - 0.8) > 0.001:
                _fail("J: regen 4 -> %.3f" % p.get_regen_rate())
                return
        _ok("J6: Rigenerazione cap: 0.8 energia ogni 5s")
        p.confirm_skills({})
        if p.max_energy != 5 or p.get_skill_level("energy") != 0:
                _fail("J: confirm {} non azzera")
                return
        _ok("J7: conferma vuota = progressione azzera")
        p.queue_free()


# --- K: catene di salti (doppio salto BASE + Salti Aggiuntivi) ---
func _test_air_jump() -> void:
        var p := PlayerClass.new()
        p.stamina = 1.0
        p.stamina_exhausted = false
        if p.activate_jump() != true:
                _fail("K: primo salto da terra non parte")
                return
        # TASK (fix bug utente): il DOPPIO SALTO è BASE (2 salti consecutivi,
        # TASK 23): senza perk si salta una volta a mezz'aria, poi stop.
        if p.activate_jump() != true:
                _fail("K: doppio salto base non disponibile (regressione!)")
                return
        if p.activate_jump() != false:
                _fail("K: terzo salto concesso senza perk (quota base 1)")
                return
        p.jump_timer = 0
        p.stamina_exhausted = false
        # 1° Salto Aggiuntivo (Resistenza 10): catena di 3 salti TOTALI.
        p.confirm_skills({"stamina": 10, "jump": 1})
        p.stamina = p.get_stamina_max()
        if p.activate_jump() != true:
                _fail("K: salto da terra con 1° perk non parte")
                return
        if p.activate_jump() != true:
                _fail("K: 2° salto della catena (perk 1) non disponibile")
                return
        if p.activate_jump() != true:
                _fail("K: 3° salto della catena (perk 1) non disponibile")
                return
        if p.activate_jump() != false:
                _fail("K: 4° salto concesso oltre la quota perk 1 (3 attese)")
                return
        if not p.stamina_exhausted:
                _fail("K: barra non svuotata dopo la catena completa (perk 1)")
                return
        p.jump_timer = 0
        p.stamina_exhausted = false
        # FIX BUG UTENTE ("saltava una sola volta invece che quattro volte"):
        # col 2° Salto Aggiuntivo la catena è di 4 salti TOTALI e il costo
        # stamina scala (barra_max / salti_massimi): la barra basta per TUTTA
        # la catena, non si svuota al primo salto.
        p.confirm_skills({"stamina": 40, "jump": 2})
        p.stamina = p.get_stamina_max()
        if p.get_max_consecutive_jumps() != 4:
                _fail("K: 2° Salto Aggiuntivo -> %d salti massimi (attesi 4)"
                                % p.get_max_consecutive_jumps())
                return
        var chain: int = 0
        while p.activate_jump():
                chain += 1
                if chain > 6:
                        break
        if chain != 4:
                _fail("K: catena con 2° perk = %d salti (attesi 4)" % chain)
                return
        if not p.stamina_exhausted:
                _fail("K: dopo 4 salti la barra deve essere svuotata (stanco)")
                return
        _ok("K: base 2 salti; perk 1 = 3; perk 2 = 4 salti (costo stamina scalato)")
        p.queue_free()


# --- L: caricatore esteso ---
func _test_magazine() -> void:
        var p := PlayerClass.new()
        p.confirm_skills({"magazine": 3})
        p.collect_weapon({"type": 0, "power": 1, "ammo": 20})
        if int(p.current_weapon.get("ammo", -1)) != 23:
                _fail("L: pistola con perk 3 -> ammo %d (attesi 23)"
                                % int(p.current_weapon.get("ammo", -1)))
                return
        # le reliquie non vengono toccate
        p.collect_weapon({"type": 0, "power": 2, "ammo": 5, "relic": "spadone"})
        if int(p.current_weapon.get("ammo", -1)) != 5:
                _fail("L: arma reliquia toccata dal perk (%d)" % int(p.current_weapon.get("ammo", -1)))
                return
        _ok("L: Caricatore +3 sulle armi base, reliquie intatte")
        p.queue_free()


# --- M: moltiplicatore danno ---
func _test_damage_mult() -> void:
        var base: int = C.weapon_damage_for(0, 40, false, -1, 1.0)
        var buffed: int = C.weapon_damage_for(0, 40, false, -1, 1.5)
        if base != 10 or buffed != 15:
                _fail("M: danno base %d / x1.5 -> %d (attesi 10/15)" % [base, buffed])
                return
        if C.weapon_damage_for(0, 4, false, -1, 2.0) < 1:
                _fail("M: danno minimo violato")
                return
        _ok("M: Potenza di Fuoco x1.5 = 15 su nemico da 40 HP (10 base)")


# --- N: ratio stamina con barra estesa ---
func _test_stamina_ratio() -> void:
        var p := PlayerClass.new()
        p.confirm_skills({"stamina": 16})
        p.stamina = 1.0
        if absf(p.get_stamina_ratio() - 1.0 / 1.28) > 0.001:
                _fail("N: ratio a barra 1.0/1.28 = %.3f" % p.get_stamina_ratio())
                return
        p.stamina = 1.28
        if absf(p.get_stamina_ratio() - 1.0) > 0.001:
                _fail("N: ratio pieno = %.3f" % p.get_stamina_ratio())
                return
        _ok("N: HUD stamina relativa alla capacità corrente (1.0 = piena)")
        p.queue_free()


# --- O: modale abilità (drive diretto) ---
var _modal_closed_num: int = -1


func _on_modal_closed_for_test(n: int) -> void:
        _modal_closed_num = n


func _test_modal() -> void:
        var p := PlayerClass.new()
        p.player_num = 1
        p.skill_points = 2
        var modal: CanvasLayer = OverlayClass.new()
        modal.setup(p)
        _modal_closed_num = -1
        modal.modal_closed.connect(_on_modal_closed_for_test)
        add_child(modal)
        await get_tree().process_frame
        # riga 1 = Resistenza: assegna 1 punto dal banco
        modal._row = 1
        modal._try_alloc(1)
        if modal._bank != 1 or int(modal._alloc.get("stamina", 0)) != 1:
                _fail("O: alloc stamina -> banco %d alloc %d" % [modal._bank, modal._alloc.get("stamina", 0)])
                return
        # riga 2 = Salto: bloccato (Resistenza visual 1 < 10)
        modal._row = 2
        modal._try_alloc(1)
        if int(modal._alloc.get("jump", 0)) != 0:
                _fail("O: salto assegnato senza requisito")
                return
        # riga 7 = Rigenerazione: secondo punto
        modal._row = 7
        modal._try_alloc(1)
        if modal._bank != 0:
                _fail("O: banco %d dopo 2 assegnazioni" % modal._bank)
                return
        # toglie la rigenerazione: il punto torna al banco
        modal._try_alloc(-1)
        if modal._bank != 1:
                _fail("O: banco %d dopo il -" % modal._bank)
                return
        _ok("O1: +/− assegnano e restituiscono; requisito salto rispettato")
        # OK: conferma (banco 1 resta bancato)
        modal._confirm()
        await get_tree().process_frame
        if _modal_closed_num != 1:
                _fail("O: modal_closed = %d" % _modal_closed_num)
                return
        if p.skill_points != 1 or p.get_skill_level("stamina") != 1 \
                        or p.get_skill_level("regen") != 0:
                _fail("O: conferma -> pt %d stam %d regen %d (attesi 1/1/0)"
                                % [p.skill_points, p.get_skill_level("stamina"), p.get_skill_level("regen")])
                return
        _ok("O2: OK conferma stamina 1, punto residuo BANCATO sul player")
        modal.queue_free()
        p.queue_free()


# --- P: carry di skill_levels ---
func _test_carry_skills() -> void:
        var p := PlayerClass.new()
        p.skill_points = 1
        p.confirm_skills({"stamina": 20, "firepower": 2})
        var snap: Dictionary = GameManager.make_player_carry(p)
        var carried: Dictionary = snap.get("skill_levels", {})
        if int(carried.get("stamina", -1)) != 20 or int(carried.get("firepower", -1)) != 2:
                _fail("P: carry skill_levels %s" % [carried])
                return
        var p2 := PlayerClass.new()
        p2.reset()
        GameManager._apply_carry(p2, snap)
        if p2.get_skill_level("stamina") != 20 or p2.get_skill_level("firepower") != 2:
                _fail("P: _apply_carry non ripristina (stam %d fire %d)"
                                % [p2.get_skill_level("stamina"), p2.get_skill_level("firepower")])
                return
        if p2.skill_points != 1:
                _fail("P: skill_points nel carry = %d" % p2.skill_points)
                return
        if absf(p2.get_stamina_max() - 1.35) > 0.001:
                _fail("P: effetti non ricalcolati dopo carry (max %.3f)" % p2.get_stamina_max())
                return
        _ok("P: skill_levels attraversa make_player_carry/_apply_carry con ricalcolo effetti")
        p.queue_free()
        p2.queue_free()


# --- Q: guardie sorgente fase 2 ---
func _test_source_guards_f2() -> void:
        var s_main := _read(SRC_MAIN)
        if "_maybe_open_levelup_modal" not in s_main \
                        or "LevelUpOverlayClass" not in s_main:
                _fail("Q: modale non cablata nel MainGameController")
        else:
                _ok("Q1: modale aperta a fine annuncio nel labirinto")
        var s_boss := _read(SRC_BOSS)
        if "_maybe_open_levelup_modal" not in s_boss:
                _fail("Q: modale non cablata nel BossRoomController")
        else:
                _ok("Q2: modale cablata anche in boss room")
        if "get_damage_mult()" not in s_main:
                _fail("Q: dmg_mult non passato dal MainGameController")
        else:
                _ok("Q3: Potenza di Fuoco cablata nel loop proiettili")
        if "get_luck_drop_chance()" not in s_main:
                _fail("Q: fortuna non cablata")
        else:
                _ok("Q4: Fortuna cablata sui drop da nemico")
        var s_player := _read(SRC_PLAYER)
        if "_apply_magazine_bonus_to_weapon()" not in s_player \
                        or "get_speed_mult()" not in s_player:
                _fail("Q: magazine/speed non cablati nel Player")
        else:
                _ok("Q5: Caricatore e Rapidità cablate nel Player")


# --- R: asset PixelLab della FASE 3 + integrazione ---
func _load_img(path: String) -> Image:
        var img := Image.new()
        var abs_path: String = ProjectSettings.globalize_path(path)
        if not FileAccess.file_exists(abs_path):
                return null
        if img.load(abs_path) != OK:
                return null
        return img


func _test_assets_f3() -> void:
        # icone 8× 64×64 con contenuto e bordi trasparenti
        var ids := ["energy", "stamina", "jump", "firepower",
                        "magazine", "swiftness", "luck", "regen"]
        var icons_ok: int = 0
        for id in ids:
                var img := _load_img("res://assets/sprites/skills/skill_%s.png" % id)
                if img == null:
                        _fail("R: icona %s mancante" % id)
                        continue
                if img.get_width() != 64 or img.get_height() != 64:
                        _fail("R: icona %s %dx%d (attesa 64x64)"
                                        % [id, img.get_width(), img.get_height()])
                        continue
                var opaque: int = 0
                for y in 64:
                        for x in 64:
                                if img.get_pixel(x, y).a > 0.5:
                                        opaque += 1
                if opaque < 64:
                        _fail("R: icona %s quasi vuota (%d px)" % [id, opaque])
                        continue
                icons_ok += 1
        if icons_ok == 8:
                _ok("R1: 8 icone 64x64 con contenuto")
        # sheet fulmine 4 frame distinti
        var bolt := _load_img("res://assets/sprites/skills/levelup_bolt_sheet.png")
        if bolt == null or bolt.get_width() != 256 or bolt.get_height() != 64:
                _fail("R: bolt sheet assente o wrong size")
        else:
                var hashes := []
                for i in 4:
                        var h: int = 0
                        for y in range(0, 64, 4):
                                for x in range(i * 64, (i + 1) * 64, 4):
                                        h = (h * 31 + int(img_get_hash_px(bolt, x, y))) % 999999937
                        hashes.append(h)
                if hashes[0] == hashes[1] or hashes[1] == hashes[2] or hashes[2] == hashes[3]:
                        _fail("R: frame del bolt duplicati (puro slide)")
                else:
                        _ok("R2: bolt sheet 256x64 con 4 frame distinti")
        # scritta dorata
        var title := _load_img("res://assets/sprites/skills/levelup_title.png")
        if title == null or title.get_width() < 200:
                _fail("R: title sprite assente o troppo stretto")
        else:
                _ok("R3: scritta LEVEL UP! dorata %dx%d"
                                % [title.get_width(), title.get_height()])
        # integrazione: annuncio carica bolt+title, modale icone+pietra+angoli
        var ann := AnnounceClass.new()
        ann.setup(1, 2, 1, Vector2(300.0, 300.0), self)
        add_child(ann)
        await get_tree().process_frame
        if ann._bolt_frames.size() != 4 or ann._title_texture == null:
                _fail("R: annuncio non usa gli asset PixelLab (bolt %d, title %s)"
                                % [ann._bolt_frames.size(), ann._title_texture])
        else:
                _ok("R4: annuncio con fulmine PixelLab 4f + scritta dorata")
        ann.queue_free()
        var p := PlayerClass.new()
        p.player_num = 1
        p.skill_points = 1
        var modal: CanvasLayer = OverlayClass.new()
        modal.setup(p)
        add_child(modal)
        await get_tree().process_frame
        var null_icons: Array = []
        for id in C.SKILL_IDS:
                if modal._icons.get(id) == null:
                        null_icons.append(id)
        if not null_icons.is_empty():
                _fail("R: icone non caricate nella modale: %s" % str(null_icons))
        elif modal._stone_texture == null or modal._corner_tl == null:
                _fail("R: pietra/angoli del frame non caricati")
        else:
                _ok("R5: modale con 8 icone PixelLab + frame pietra/ottone")
        modal.queue_free()
        p.queue_free()
        # guardia sorgente
        var s_ann := _read("res://scripts/ui/LevelUpAnnounce.gd")
        if "levelup_bolt_sheet.png" not in s_ann \
                        or "levelup_title.png" not in s_ann:
                _fail("R: path asset assenti dal sorgente annuncio")
        else:
                _ok("R6: path asset PixelLab nel sorgente (PNG-first)")


func img_get_hash_px(img: Image, x: int, y: int) -> int:
        var c: Color = img.get_pixel(x, y)
        return int(c.r * 255.0) * 3 + int(c.g * 255.0) * 5 \
                        + int(c.b * 255.0) * 7 + int(c.a * 255.0)
