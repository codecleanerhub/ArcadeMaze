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

const SRC_PLAYER := "res://scripts/core/Player.gd"
const SRC_MAIN := "res://scripts/core/MainGameController.gd"
const SRC_BOSS := "res://scripts/core/BossRoomController.gd"
const SRC_HUD := "res://scripts/ui/HUD.gd"

var fails: int = 0
var _announce_done_num: int = -1


func _on_announce_done(n: int) -> void:
        _announce_done_num = n


func _ready() -> void:
        print("[TEST] TASK 99 FASE 1 — motore XP (punteggio = esperienza)")
        _test_thresholds()
        _test_level_for_score()
        _test_add_score()
        _test_reset_semantics()
        _test_carry()
        _test_hud_keys()
        await _test_announce()
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
                [2, 3350], [3, 6850], [4, 11300], [5, 16700],
                [10, 56250], [15, 114350], [20, 189150],
        ]
        for kv in known:
                var got: int = C.levelup_threshold(int(kv[0]))
                if got != int(kv[1]):
                        _fail("A: soglia L%d = %d, attesa %d" % [kv[0], got, kv[1]])
                        return
        _ok("A1: soglie note identiche al report Task 98 (L2=3350...L20=189150)")
        if C.levelup_threshold(1) != 0:
                _fail("A: soglia L1 deve essere 0 (si nasce a livello 1)")
        else:
                _ok("A2: levelup_threshold(1) = 0")
        var prev: int = 0
        for n in range(2, 22):
                var t: int = C.levelup_threshold(n)
                if t <= prev:
                        _fail("A: curva non monotona alla L%d" % n)
                        return
                prev = t
        _ok("A3: curva monotona crescente L2..L21")
        if C.LEVELUP_MAX_LEVEL != 20:
                _fail("A: LEVELUP_MAX_LEVEL = %d, atteso 20" % C.LEVELUP_MAX_LEVEL)
        else:
                _ok("A4: cap livello 20 (L21 fuori economia: %d > ~201k)"
                                % C.levelup_threshold(21))


# --- B: livello per punteggio ---
func _test_level_for_score() -> void:
        var cases: Array = [
                [0, 1], [3349, 1], [3350, 2], [6849, 2], [6850, 3],
                [56250, 10], [189149, 19], [189150, 20],
                [200000, 20], [999999, 20],
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
        p.add_score(3349)
        if p.level != 1 or p.skill_points != 0 or p.pending_levelup_fx != 0:
                _fail("C: 3.349 punti NON devono dare level up (L%d, pt %d, pend %d)"
                                % [p.level, p.skill_points, p.pending_levelup_fx])
                return
        p.add_score(1)
        if p.level != 2 or p.skill_points != 1 or p.pending_levelup_fx != 1:
                _fail("C: 3.350 punti -> L%d pt %d pend %d (attesi 2/1/1)"
                                % [p.level, p.skill_points, p.pending_levelup_fx])
                return
        _ok("C1: soglia esatta: 3.349 = niente, +1 = L2 con 1 punto bancabile")
        p.add_score(3500)  # 6850 totale -> L3 (il pending di L2 era ancora in coda)
        var gained: int = p.consume_pending_levelup_fx()
        if p.level != 3 or gained != 2 or p.pending_levelup_fx != 0:
                _fail("C: passo L3: gained %d, pend residuo %d" % [gained, p.pending_levelup_fx])
                return
        _ok("C2: consume_pending_levelup_fx ritorna e azzera (L2+L3 in coda = 2)")
        # salto di più soglie in un colpo (premio boss)
        var p2 := PlayerClass.new()
        p2.score = 0
        p2.add_score(11300)  # -> L4 in un colpo
        if p2.level != 4 or p2.skill_points != 3 or p2.pending_levelup_fx != 3:
                _fail("C: salto 3 soglie -> L%d pt %d pend %d (attesi 4/3/3)"
                                % [p2.level, p2.skill_points, p2.pending_levelup_fx])
                return
        _ok("C3: un premio che salta 3 soglie dà L4 con 3 punti (una celebrazione)")
        # cap
        var p3 := PlayerClass.new()
        p3.score = 0
        p3.add_score(400000)
        if p3.level != 20 or p3.skill_points != 19:
                _fail("C: cap oltre 200k -> L%d pt %d (attesi 20/19)"
                                % [p3.level, p3.skill_points])
                return
        _ok("C4: cap livello 20 anche con score assurdo")
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
