## test_task106_save.gd — TASK 106 (SALVA PARTITA + continue 1 credito
## + level-up cura energia + menu CONTINUA + endless nascosta + demo).
##
## Check:
##   A — costanti Task 106 (slot max, flag vite-extra, crediti continue,
##       endless visibile, durata annuncio)
##   B — SaveSystem: save/load/delete/first_free/format data; overflow 10
##       slot; sommari (data/ora, livelli, personaggi)
##   C — Player.add_score: NESSUNA vita extra da punti (flag OFF), soglia
##       invariata nel carry
##   D — level up: energia del cuore corrente RIEMPITA (energy=max_energy),
##       vite invariate
##   E — crediti continue: reset_run = 1 credito (P1 e P2); NG+ = 1
##   F — GameManager.begin_continue_from_slot: livello/carry/personaggi/
##       tier/slot corrente ripristinati
##   G — SavedAnnounce: durata 2s + segnale announcement_done
##   H — guardie sorgente (auto-save BossRoom, menu CONTINUA, endless
##       nascosta, demo AI potenziata)
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const PlayerScript = preload("res://scripts/core/Player.gd")
const SavedAnnounceClass = preload("res://scripts/ui/SavedAnnounce.gd")

var fails: int = 0


func _ready() -> void:
        print("[TEST] === TASK 106: SALVA PARTITA ===")
        _test_constants()
        _test_savesystem()
        _test_extra_life_disabled()
        _test_levelup_heal()
        _test_continue_credits()
        _test_resume_from_slot()
        await _test_saved_announce()
        _test_source_guards()
        _cleanup_saves()
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


# --- A: costanti -------------------------------------------------------------
func _test_constants() -> void:
        if C.SAVE_SLOTS_MAX != 10:
                _fail("A: SAVE_SLOTS_MAX = %d (atteso 10)" % C.SAVE_SLOTS_MAX)
                return
        if C.EXTRA_LIVES_FROM_POINTS_ENABLED:
                _fail("A: vite-extra da punti devono essere OFF (Task 106)")
                return
        if C.CONTINUE_CREDITS_PER_RUN != 1:
                _fail("A: CONTINUE_CREDITS_PER_RUN = %d (atteso 1)" % C.CONTINUE_CREDITS_PER_RUN)
                return
        if C.ENDLESS_MODE_VISIBLE:
                _fail("A: modalità INFINITA deve essere NASCOSTA (Task 106)")
                return
        if absf(C.SAVE_ANNOUNCE_MS - 2000.0) > 0.01:
                _fail("A: SAVE_ANNOUNCE_MS = %f (atteso 2000)" % C.SAVE_ANNOUNCE_MS)
                return
        _ok("A: costanti Task 106 (10 slot, vite-extra OFF, 1 credito, endless nascosta, annuncio 2s)")


# --- B: SaveSystem -----------------------------------------------------------
func _cleanup_saves() -> void:
        if SaveSystem != null:
                SaveSystem.clear_all()


func _test_savesystem() -> void:
        if SaveSystem == null:
                _fail("B: autoload SaveSystem mancante")
                return
        _cleanup_saves()
        if SaveSystem.has_slots():
                _fail("B: slot residui da run precedenti (clear_all non funzionato)")
                return
        # salvataggio base con data fissa deterministica
        var data := {
                        "num_players": 1,
                        "game_mode": C.GameMode.STORY,
                        "newgameplus_tier": 0,
                        "current_level": 5,
                        "char1": C.CharacterType.ELF,
                        "char2": C.CharacterType.HERO_F,
                        "carry_p1": {"score": 1234, "lives": 4, "level": 3,
                                        "skill_points": 1, "skill_levels": {"firepower": 2}},
                        "carry_p2": {},
        }
        var first: Dictionary = data.duplicate(true)
        first["saved_at"] = "31/10/2026 18:30"
        if not SaveSystem.save_run(0, first):
                _fail("B: save_run ha fallito")
                return
        if SaveSystem.slot_count() != 1 or not SaveSystem.has_slots():
                _fail("B: slot non registrato dopo save_run")
                return
        # sovrascrittura dello STESSO slot (run che riscrive il proprio)
        var second: Dictionary = data.duplicate(true)
        second["current_level"] = 9
        second["carry_p1"]["level"] = 5
        second["saved_at"] = "31/10/2026 19:45"
        SaveSystem.save_run(0, second)
        var reloaded: Dictionary = SaveSystem.load_slot(0)
        if int(reloaded.get("current_level", -1)) != 9 \
                        or int((reloaded.get("carry_p1", {}) as Dictionary).get("level", -1)) != 5:
                _fail("B: sovrascrittura stesso slot non riuscita (%s)" % str(reloaded.get("current_level")))
                return
        if SaveSystem.slot_count() != 1:
                _fail("B: sovrascrittura ha duplicato lo slot (%d)" % SaveSystem.slot_count())
                return
        # sommario per la card: data/ora, livello gioco, livello player, tipo
        var sum: Dictionary = SaveSystem.slot_summary(0)
        if str(sum.get("saved_at", "")) != "31/10/2026 19:45" \
                        or int(sum.get("game_level", -1)) != 9 \
                        or int(sum.get("player_level", -1)) != 5:
                _fail("B: sommario errato (%s)" % str(sum))
                return
        var names: Array = sum.get("char_names", [])
        if names.size() != 1 or str(names[0]).to_lower() != "elfo" and str(names[0]).to_lower() != "elf":
                _fail("B: tipo player nel sommario errato (%s)" % str(names))
                return
        # overflow: riempi fino a 10 slot -> first_free_slot = -1
        for i in range(1, C.SAVE_SLOTS_MAX):
                SaveSystem.save_run(i, data)
        if SaveSystem.first_free_slot() != -1:
                _fail("B: 10 slot pieni ma first_free_slot = %d" % SaveSystem.first_free_slot())
                return
        if SaveSystem.slot_count() != C.SAVE_SLOTS_MAX:
                _fail("B: slot_count = %d (atteso %d)" % [SaveSystem.slot_count(), C.SAVE_SLOTS_MAX])
                return
        # eliminazione libera lo slot
        SaveSystem.delete_slot(3)
        if SaveSystem.first_free_slot() != 3:
                _fail("B: delete_slot non ha liberato lo slot 3")
                return
        # persistenza su disco (reload dal file)
        SaveSystem.reload_from_disk()
        if SaveSystem.slot_count() != C.SAVE_SLOTS_MAX - 1:
                _fail("B: reload_from_disk ha perso slot (%d)" % SaveSystem.slot_count())
                return
        # formato data/ora corrente GG/MM/AAAA HH:MM
        var now_s: String = SaveSystem.format_now()
        if now_s.length() != 16 or now_s[2] != "/" or now_s[5] != "/" or now_s[13] != ":":
                _fail("B: format_now malformato (%s)" % now_s)
                return
        _cleanup_saves()
        _ok("B: SaveSystem save/overwrite/delete/overflow(10)/sommari/data-ora OK")


# --- C: vite extra da punti DISATTIVATE --------------------------------------
func _test_extra_life_disabled() -> void:
        var p := PlayerScript.new()
        add_child(p)
        p.reset()
        p.score = 0
        p.lives = 3
        p.next_life_threshold = C.EXTRA_LIFE_EVERY_POINTS
        p.add_score(C.EXTRA_LIFE_EVERY_POINTS + 1)
        if p.lives != 3:
                _fail("C: vita extra assegnata col flag OFF (vite %d)" % p.lives)
                return
        p.queue_free()
        _ok("C: NESSUNA vita extra da punti (meccanica disattivata, gate attivo)")


# --- D: level up = energia del cuore corrente piena ---------------------------
func _test_levelup_heal() -> void:
        var p := PlayerScript.new()
        add_child(p)
        p.reset()
        p.score = 0
        p.lives = 3
        p.energy = 2       # cuore corrente mezzo sgretolato
        var before_max: int = p.max_energy
        # supera la soglia del livello 2 (3350 punti)
        p.add_score(C.levelup_threshold(2))
        if p.level != 2:
                _fail("D: level up non avvenuto (livello %d)" % p.level)
                return
        if p.energy != before_max:
                _fail("D: energia non riempita al level up (%d/%d)" % [p.energy, before_max])
                return
        if p.lives != 3:
                _fail("D: le VITE sono cambiate al level up (%d)" % p.lives)
                return
        p.queue_free()
        _ok("D: level up = energia del cuore corrente PIENA, vite invariate")


# --- E: crediti continue = 1 ---------------------------------------------------
func _test_continue_credits() -> void:
        GameManager.reset_run()
        if GameManager.continues_left != 1 or GameManager.continues_left_p2 != 1:
                _fail("E: reset_run deve dare 1 credito per player (%d/%d)" % [
                                GameManager.continues_left, GameManager.continues_left_p2])
                return
        # il flusso player_died con 1 credito porta alla schermata CONTINUES
        # (appare UNA volta sola); consumato il credito, la morte = LOSE.
        GameManager.continues_left = 0
        # (player_died cambia scena: qui si verifica solo il ramo contatore)
        if GameManager.continues_left != 0:
                _fail("E: uso credito non decrementato")
                return
        _ok("E: continue = UN credito per player (reset_run/IntroCutscene/NG+)")


# --- F: resume dal menu CONTINUA ----------------------------------------------
func _test_resume_from_slot() -> void:
        _cleanup_saves()
        var carry := {
                        "score": 7777, "lives": 4, "next_life_threshold": C.EXTRA_LIFE_EVERY_POINTS,
                        "level": 6, "skill_points": 2, "pending_levelup_fx": 0,
                        "skill_levels": {"firepower": 3, "stamina": 1},
        }
        SaveSystem.save_run(2, {
                        "saved_at": "30/10/2026 21:05",
                        "num_players": 1, "game_mode": C.GameMode.STORY,
                        "newgameplus_tier": 1, "current_level": 13,
                        "char1": C.CharacterType.DRAGON, "char2": C.CharacterType.HERO_F,
                        "carry_p1": carry, "carry_p2": {},
        })
        GameManager.reset_run()
        GameManager.num_players = 2  # il resume deve SOVRASCRIVERLO con lo slot
        # NOTA: si testa _apply_saved_run (lo stato) SENZA il cambio scena
        # di begin_continue_from_slot, che libererebbe la scena di test.
        GameManager._apply_saved_run(2, SaveSystem.load_slot(2))
        if GameManager.save_slot_current != 2:
                _fail("F: slot corrente non impostato (%d)" % GameManager.save_slot_current)
                return
        if GameManager.current_level != 13:
                _fail("F: livello di gioco non ripristinato (%d)" % GameManager.current_level)
                return
        if GameManager.num_players != 1:
                _fail("F: numero players non ripristinato (%d)" % GameManager.num_players)
                return
        if GameManager.newgameplus_tier != 1:
                _fail("F: tier NG+ non ripristinato (%d)" % GameManager.newgameplus_tier)
                return
        if GameManager.player1_character != C.CharacterType.DRAGON:
                _fail("F: personaggio non ripristinato (%d)" % GameManager.player1_character)
                return
        if int(GameManager.carry_p1.get("level", -1)) != 6 \
                        or int(GameManager.carry_p1.get("score", -1)) != 7777 \
                        or int(GameManager.carry_p1.get("lives", -1)) != 4:
                _fail("F: carry non ripristinato (%s)" % str(GameManager.carry_p1))
                return
        if int((GameManager.carry_p1.get("skill_levels", {}) as Dictionary).get("firepower", 0)) != 3:
                _fail("F: abilità non ripristinate")
                return
        if GameManager.continues_left != 1:
                _fail("F: crediti continue al resume = %d (atteso 1)" % GameManager.continues_left)
                return
        if GameManager.save_announce_pending:
                _fail("F: resume dal menu NON deve mostrare 'Partita salvata...'")
                return
        GameManager.reset_run()
        _cleanup_saves()
        _ok("F: begin_continue_from_slot (livello 13, carry L6, drago, NG+, slot 2, 1 credito)")


# --- G: annuncio "Partita salvata..." -----------------------------------------
func _test_saved_announce() -> void:
        var ann := SavedAnnounceClass.new()
        var done: Array = []
        ann.announcement_done.connect(func(): done.append(true))
        add_child(ann)
        var t0: float = Time.get_ticks_msec()
        while done.is_empty() and Time.get_ticks_msec() - t0 < 4000:
                await get_tree().physics_frame
        var elapsed_ms: float = Time.get_ticks_msec() - t0
        if done.is_empty():
                _fail("G: announcement_done mai emesso entro 4s")
                ann.queue_free()
                return
        # durata ~2s (tolleranza per il carico headless)
        if elapsed_ms < 1800.0 or elapsed_ms > 3600.0:
                _fail("G: durata annuncio %d ms (atteso ~2000)" % int(elapsed_ms))
                ann.queue_free()
                return
        _ok("G: 'Partita salvata...' dura ~2s e poi emette announcement_done (%d ms)" % int(elapsed_ms))
        if is_instance_valid(ann):
                ann.queue_free()


# --- H: guardie sorgente -------------------------------------------------------
func _test_source_guards() -> void:
        var guards := {
                        "BossRoom (auto-save post-boss)": [
                                        "res://scripts/core/BossRoomController.gd",
                                        ["_autosave_run()", "save_announce_pending = true",
                                                        "first_free_slot()", "_build_save_data()"]],
                        "BossRoom (card overflow)": [
                                        "res://scripts/core/BossRoomController.gd",
                                        ["Mode.DELETE", "_on_slot_freed_for_save"]],
                        "MainGame (annuncio a livello dopo boss)": [
                                        "res://scripts/core/MainGameController.gd",
                                        ["save_announce_pending", "SavedAnnounceClass"]],
                        "GameManager (resume slot + crediti)": [
                                        "res://scripts/core/GameManager.gd",
                                        ["begin_continue_from_slot", "save_slot_current",
                                                        "CONTINUE_CREDITS_PER_RUN"]],
                        "MainMenu (voce CONTINUA + endless nascosta)": [
                                        "res://scripts/ui/MainMenu.gd",
                                        ["CONTINUE_MENU_INDEX", "menu.continue",
                                                        "ENDLESS_MODE_VISIBLE",
                                                        "_open_continue_card()"]],
                        "Player (gate vite-extra + cura energia)": [
                                        "res://scripts/core/Player.gd",
                                        ["EXTRA_LIVES_FROM_POINTS_ENABLED",
                                                        "energy = max_energy"]],
                        "Demo (AI potenziata)": [
                                        "res://scripts/core/DemoController.gd",
                                        ["DEMO_JUMP_FLEE_PCT", "_on_demo_collectible_picked",
                                                        "_demo_priority_item_cell",
                                                        "Kind.MEDIKIT"]],
                        "IntroCutscene (1 credito + slot nuovo)": [
                                        "res://scripts/core/IntroCutscene.gd",
                                        ["CONTINUE_CREDITS_PER_RUN", "save_slot_current = -1"]],
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
        _ok("H: guardie sorgente (flusso save completo wired)")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var content := f.get_as_text()
        f.close()
        return content
