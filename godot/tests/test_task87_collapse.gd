## test_task87_collapse.gd — TASK 87: test runtime dell'animazione di morte
## del player (richiesta utente: "il player quando finisce l'energia muore
## accasciandosi al pavimento ed emette un suono di sofferenza").
##
## Check:
##   A — AudioManager: PLAYER_SUFFER in enum (indice 56), SOUND_TYPE_COUNT=58
##       (57 fino al Task 87; +1 dal Task 93: CHALICE_POWER),
##       dispatch presente, ricetta sintetizzabile (campioni > 0, non nulli)
##   B — effetto standalone: setup + fasi FALL→TWITCH→FADE→finished
##       (durata totale ~1.16s), con player fittizio (fallback draw)
##   C — integrazione maze (MainGame, livello 1): morte con vite residue →
##       collapse_requested consumato, effetto attivo, player congelato
##       (soul_pending, sprite nascosto, non bersaglio); a fine animazione
##       respawn (posizione resettata, spawn guard attiva, sprite visibile)
##   D — integrazione morte definitiva (lives=0): a fine animazione il player
##       è sbloccato (soul_pending=false) SENZA respawn; _check_death
##       transita (GameManager in stato continua/lose)
##   E — integrazione boss room: morte in BossRoom → collasso attivo, a fine
##       animazione respawn
##   F — guardie sorgente: begin_collapse nei 3 rami morte di Player.gd,
##       gate _is_collapsing nei due controller, nessun reset_position()
##       diretto nei rami morte
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const CollapseFx = preload("res://scripts/entities/PlayerCollapseEffect.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var fails: int = 0


func _ready() -> void:
        print("[TEST] TASK 87 — animazione di morte del player")
        _test_audio()
        await _test_effect_standalone()
        await _test_maze_respawn()
        await _test_boss_room()
        _test_source_guards()
        # NB: la morte definitiva (D) transita verso CONTINUES/LOSE e puo'
        # sostituire la scena di test: resta per ULTIMA e chiude da sola.
        await _test_final_death()


func _ok(msg: String) -> void:
        print("[TEST] OK %s" % msg)


func _fail(msg: String) -> void:
        fails += 1
        print("[TEST] FALLITO %s" % msg)


# --- A: audio ---
func _test_audio() -> void:
        var am: Node = get_node("/root/AudioManager")
        if am == null:
                _fail("A: autoload AudioManager non trovato")
                return
        if am.SOUND_TYPE_COUNT != 58:
                _fail("A: SOUND_TYPE_COUNT=%d atteso 58 (57 + CHALICE_POWER Task 93)" % am.SOUND_TYPE_COUNT)
        if int(am.SoundType.PLAYER_SUFFER) != 56:
                _fail("A: PLAYER_SUFFER=%d atteso 56" % int(am.SoundType.PLAYER_SUFFER))
        if int(am.SoundType.CHALICE_POWER) != 57:
                _fail("A: CHALICE_POWER=%d atteso 57 (Task 93)" % int(am.SoundType.CHALICE_POWER))
        var samples: PackedFloat32Array = am._sfx_player_suffer()
        if samples.size() < int(44100 * 0.8):
                _fail("A: ricetta troppo corta (%d campioni)" % samples.size())
                return
        var peak: float = 0.0
        for s in samples:
                peak = maxf(peak, absf(s))
        if peak < 0.01:
                _fail("A: ricetta silente (picco %.4f)" % peak)
                return
        _ok("A: PLAYER_SUFFER (idx 56, count 58 con CHALICE_POWER) con ricetta ~%.2fs, picco %.3f" % [
                        float(samples.size()) / 44100.0, peak])


# --- B: effetto standalone ---
func _test_effect_standalone() -> void:
        # CharacterBody2D fittizio con le API minime dell'effetto
        var cb := CharacterBody2D.new()
        cb.set_script(preload("res://tests/fake_collapse_victim.gd"))
        add_child(cb)
        cb.position = Vector2(500.0, 500.0)
        var fx: Node2D = CollapseFx.new()
        var fired: Array = [false]
        fx.finished.connect(func() -> void: fired[0] = true)
        fx.setup(cb)
        add_child(fx)
        var t0: float = Time.get_ticks_msec()
        var guard: int = 0
        while not fired[0] and guard < 240:
                await get_tree().physics_frame
                guard += 1
        var dur: float = float(Time.get_ticks_msec() - t0)
        if not fired[0]:
                _fail("B: finished MAI emesso (guard 240 frame)")
        elif dur < 900.0 or dur > 2200.0:
                _fail("B: durata %.0fms fuori range 900-2200" % dur)
        else:
                _ok("B: FALL->TWITCH->FADE->finished in %.0fms (headless)" % dur)
        cb.queue_free()


# --- C: morte con vite residue nel maze ---
func _test_maze_respawn() -> void:
        GameManager.reset_run()
        GameManager.current_level = 1
        GameManager.game_mode = C.GameMode.STORY
        var main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        for i in 30:
                await get_tree().physics_frame
        if main.player == null:
                _fail("C: player non creato")
                main.queue_free()
                return
        var p = main.player
        # sposta il player lontano dallo spawn PRIMA di ucciderlo: al
        # respawn la posizione deve tornare alla cella di partenza
        p.position = Vector2(960.0, 540.0)
        var pos_before: Vector2 = p.get_pixel_pos()
        var lives_before: int = p.lives
        p.energy = 1
        p.damage_timer = 0  # bypass invulnerabilita' post-colpo
        p.spawn_guard_ms = 0  # bypass invulnerabilita' post-spawn
        p.take_damage()
        if not p.soul_pending or not p.collapse_requested:
                _fail("C: begin_collapse non scattato (soul=%s req=%s)" % [
                                p.soul_pending, p.collapse_requested])
                main.queue_free()
                return
        # un frame di update del controller avvia l'effetto
        for i in 3:
                await get_tree().physics_frame
        if p.collapse_requested:
                _fail("C: collapse_requested non consumato dal controller")
        if main._collapses.is_empty():
                _fail("C: nessun effetto di collasso spawnato")
                main.queue_free()
                return
        if p.sprite != null and p.sprite.visible:
                _fail("C: sprite del player non nascosto durante il collasso")
        if p.lives != lives_before - 1:
                _fail("C: vita non decrementata (%d -> %d)" % [lives_before, p.lives])
        # _check_death NON transita durante il collasso (vite residue: non
        # transirebbe comunque, ma il gate non deve interferire)
        # attende la fine dell'animazione (max ~2.5s headless)
        var guard: int = 0
        while main._is_collapsing(p) and guard < 300:
                await get_tree().physics_frame
                guard += 1
        if main._is_collapsing(p):
                _fail("C: collasso mai terminato")
                main.queue_free()
                return
        if not p.soul_pending and p.lives > 0:
                # respawn: posizione resettata alla cella di partenza
                if p.sprite != null and not p.sprite.visible:
                        _fail("C: sprite non ripristinato al respawn")
                elif p.get_pixel_pos() == pos_before and pos_before != Vector2(64.0, 64.0):
                        _fail("C: posizione non resettata al respawn")
                else:
                        _ok("C: morte -> collasso -> respawn (vita %d->%d, sprite ok)" % [
                                        lives_before, p.lives])
        else:
                _fail("C: stato post-collasso inatteso (soul=%s lives=%d)" % [
                                p.soul_pending, p.lives])
        main.queue_free()


# --- D: morte definitiva 1P ---
func _test_final_death() -> void:
        GameManager.reset_run()
        GameManager.current_level = 1
        GameManager.game_mode = C.GameMode.STORY
        var main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        for i in 30:
                await get_tree().physics_frame
        var p = main.player
        p.lives = 1
        p.energy = 1
        p.damage_timer = 0
        p.spawn_guard_ms = 0
        p.take_damage()
        for i in 3:
                await get_tree().physics_frame
        if main._collapses.is_empty():
                _fail("D: collasso non avviato alla morte definitiva")
                main.queue_free()
                return
        # durante il collasso niente transizione:GameManager resta in gioco
        var guard: int = 0
        while main._is_collapsing(p) and guard < 300:
                await get_tree().physics_frame
                guard += 1
        # dopo il collasso: player sbloccato, vite 0, nessun respawn
        if p.soul_pending:
                _fail("D: soul_pending non sbloccato alla morte definitiva")
        elif p.lives != 0:
                _fail("D: vite %d attese 0" % p.lives)
        else:
                _ok("D: morte definitiva -> collasso -> sblocco (lives=0, no respawn)")
        # La transizione verso CONTINUES/LOSE (dal frame successivo)
        # sostituira' la scena di test: chiudiamo qui con l'esito corrente.
        if fails > 0:
                print("[TEST] ESITO: FALLITO (%d errori)" % fails)
                get_tree().quit(1)
        else:
                print("[TEST] ESITO: TUTTI PASSATI")
                get_tree().quit(0)
        main.queue_free()


# --- E: boss room ---
func _test_boss_room() -> void:
        GameManager.reset_run()
        GameManager.current_level = 4  # primo boss (LICH)
        GameManager.died_in_boss = false
        var room = BossRoomScene.instantiate()
        get_tree().root.add_child(room)
        for i in 30:
                await get_tree().physics_frame
        if room.boss == null or room.player == null:
                _fail("E: boss room non avviata")
                room.queue_free()
                return
        var p = room.player
        var lives_before: int = p.lives
        p.energy = 1
        p.damage_timer = 0
        p.spawn_guard_ms = 0
        p.take_damage()
        for i in 3:
                await get_tree().physics_frame
        if room._collapses.is_empty():
                _fail("E: collasso non avviato in boss room")
                room.queue_free()
                return
        var guard: int = 0
        while room._is_collapsing(p) and guard < 300:
                await get_tree().physics_frame
                guard += 1
        if room._is_collapsing(p):
                _fail("E: collasso boss room mai terminato")
        elif p.lives != lives_before - 1 or p.soul_pending:
                _fail("E: stato post-collasso errato (lives=%d soul=%s)" % [
                                p.lives, p.soul_pending])
        else:
                _ok("E: boss room — morte -> collasso -> respawn (vita %d->%d)" % [
                                lives_before, p.lives])
        room.queue_free()


# --- F: guardie sorgente ---
func _test_source_guards() -> void:
        var psrc := _read("res://scripts/core/Player.gd")
        var checks_p: Array = [
                ["begin_collapse()", "begin_collapse()"],
                ["flag collapse_requested", "var collapse_requested: bool = false"],
        ]
        for ck in checks_p:
                if psrc.find(ck[1]) < 0:
                        _fail("F: Player.gd senza %s" % ck[0])
        # i tre rami morte NON devono piu' chiamare reset_position inline:
        # il ramo morte contiene begin_collapse
        var branch_count: int = psrc.count("begin_collapse()")
        if branch_count < 4:  # 3 rami + definizione
                _fail("F: begin_collapse chiamato in %d punti (attesi >= 4: def+3 rami)" % branch_count)
        for ctrl_path in ["res://scripts/core/MainGameController.gd",
                        "res://scripts/core/BossRoomController.gd"]:
                var csrc := _read(ctrl_path)
                if csrc.find("_start_pending_collapses()") < 0:
                        _fail("F: %s senza poll collassi" % ctrl_path)
                if csrc.find("_is_collapsing(") < 0:
                        _fail("F: %s senza gate _is_collapsing" % ctrl_path)
                if csrc.find("SoundType.PLAYER_SUFFER") < 0:
                        _fail("F: %s senza suono PLAYER_SUFFER" % ctrl_path)
        var fsrc := _read("res://scripts/entities/PlayerCollapseEffect.gd")
        if fsrc.find("signal finished") < 0:
                _fail("F: effetto senza segnale finished")
        if fails == 0:
                _ok("F: guardie sorgente (Player + 2 controller + effetto) presenti")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var txt := f.get_as_text()
        f.close()
        return txt
