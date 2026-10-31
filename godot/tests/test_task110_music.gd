## test_task110_music.gd — TASK 110: musica composta (MusicComposer) +
## integrazione AudioManager (dispatch, mix_rate, coda, cache su disco).
##
## L'utente: "la musica esistente è troppo semplice, monotona, breve e
## ripetitiva" — le tracce menu/livelli/boss/portale/vittoria passano dal
## compositore (melodie scritte a mano + leitmotiv + strumenti estesi);
## il tema del fantasma resta procedurale.
##
## Check:
##   A — MusicComposer.compose_victory: buffer sano (durata 8..40s,
##       picco <= 1.0, rms >= 0.02, bordi ~0 = loop senza click) e
##       DETERMINISMO (due render identici: seed fisso per traccia)
##   B — Cache su disco: round-trip _save_cached_track -> file esiste ->
##       _try_load_cached_track ricarica stessi dati + loop/endpoint;
##       input corrotto/garbage -> null (fallback sintesi); file assente
##       -> null
##   C — Dispatch AudioManager: _generate_track(SCETTRO) = composta a
##       MUSIC_SR con loop DISABILITATO (one-shot); _generate_track(GHOST)
##       = vecchia sintesi a 44100 (SR) con loop ABILITATO
##   D — Coda di sintesi: SFX menu in testa (feedback UI), traccia MENU'
##       subito dopo, 86 task totali, NESSUN sfx duplicato
extends Node

const AMScript := preload("res://scripts/audio/AudioManager.gd")
const ComposerScript := preload("res://scripts/audio/MusicComposer.gd")

var fails: int = 0


func _ready() -> void:
        print("[TEST] TASK 110 — musica composta + cache + coda sintesi")
        _test_composer_victory()
        _test_cache_roundtrip()
        await _test_dispatch()
        _test_queue_order()
        var verdict: String = "TUTTI I TEST SUPERATI" if fails == 0 \
                        else "FALLITO: %d check" % fails
        print("[TEST] TASK 110 — ESITO: %s" % verdict)
        get_tree().quit(0 if fails == 0 else 1)


func _check(cond: bool, label: String) -> void:
        if cond:
                print("[TEST]   OK  %s" % label)
        else:
                fails += 1
                print("[TEST]   FAIL %s" % label)


# --- A: il compositore produce audio sano e deterministico ------------------
func _test_composer_victory() -> void:
        print("[TEST] A — MusicComposer.compose_victory (sanita' + determinismo)")
        var t0 := Time.get_ticks_msec()
        var c := ComposerScript.new(22050)
        var buf: PackedFloat32Array = c.compose_victory()
        var ms := Time.get_ticks_msec() - t0
        _check(!buf.is_empty(), "victory: buffer non vuoto (sintesi %d ms)" % ms)
        var dur: float = float(buf.size()) / 22050.0
        _check(dur > 8.0 and dur < 40.0,
                        "victory: durata %s in [8,40]s (one-shot epico)" % "%.1f" % dur)
        var peak := 0.0
        var rms := 0.0
        for v in buf:
                var a: float = absf(v)
                if a > peak:
                        peak = a
                rms += v * v
        rms = sqrt(rms / float(buf.size()))
        _check(peak <= 1.0, "victory: picco %.3f <= 1.0 (no clip)" % peak)
        _check(rms >= 0.02, "victory: rms %.4f >= 0.02 (non silente)" % rms)
        _check(absf(buf[0]) < 0.02 and absf(buf[buf.size() - 1]) < 0.02,
                        "victory: bordi ~0 (attacco/loop senza click)")
        var buf2: PackedFloat32Array = c.compose_victory()
        _check(buf == buf2, "victory: due render IDENTICI (seed deterministico)")


# --- B: cache su disco (round-trip su file temporaneo dedicato) -------------
func _test_cache_roundtrip() -> void:
        print("[TEST] B — cache su disco: scrittura/lettura/robustezza")
        var am := AMScript.new()
        var c := ComposerScript.new(am.MUSIC_SR)
        var stream: AudioStreamWAV = am._samples_to_stream(c.compose_victory(),
                        false, am.MUSIC_SR)
        var tmp: String = am._music_cache_dir() + "_test_roundtrip.wav"
        DirAccess.make_dir_recursive_absolute(am._music_cache_dir())
        DirAccess.remove_absolute(tmp)  # eventuale residuo di run precedenti
        am._save_cached_track(tmp, stream)
        _check(FileAccess.file_exists(tmp), "salvataggio: il WAV esiste su disco")
        var loaded: AudioStreamWAV = am._try_load_cached_track(tmp, false)
        _check(loaded != null and not loaded.data.is_empty(),
                        "caricamento: stream valido dal file")
        if loaded != null:
                _check(loaded.mix_rate == am.MUSIC_SR,
                                "caricamento: mix_rate %d == MUSIC_SR" % loaded.mix_rate)
                _check(loaded.format == AudioStreamWAV.FORMAT_16_BITS,
                                "caricamento: formato 16 bit")
                _check(loaded.loop_mode == AudioStreamWAV.LOOP_DISABLED,
                                "caricamento: loop DISABILITATO (one-shot)")
                _check(loaded.loop_end == loaded.data.size() / 2,
                                "caricamento: loop_end = fine dati (mono 16 bit)")
                _check(loaded.data.size() == stream.data.size(),
                                "round-trip: stessi dati (%d byte)" % loaded.data.size())
        var missing: AudioStreamWAV = am._try_load_cached_track(
                        am._music_cache_dir() + "_inesistente.wav", true)
        _check(missing == null, "file assente -> null (fallback sintesi)")
        var garbage := PackedByteArray()
        garbage.resize(64)
        for i in 64:
                garbage[i] = i
        _check(am._parse_wav(garbage) == null,
                        "WAV corrotto/garbage -> null (fallback sintesi)")
        var looped_probe: AudioStreamWAV = am._try_load_cached_track(tmp, true)
        _check(looped_probe != null and looped_probe.loop_mode \
                        == AudioStreamWAV.LOOP_FORWARD,
                        "loop=TRUE richiesto -> LOOP_FORWARD riapplicato al load")
        DirAccess.remove_absolute(tmp)
        _check(not FileAccess.file_exists(tmp), "pulizia: file temporaneo rimosso")


# --- C: dispatch delle tracce (nuova musica vs vecchio fantasma) ------------
# NOTA: _test_dispatch e' ASINCRONA — aggiunge un AudioManager al tree per
# verificare che play_ghost_music (loop imposto A RUNTIME sullo stream
# cached, non alla sintesi) suoni davvero in LOOP_FORWARD sul canale dedicato.
func _test_dispatch() -> void:
        print("[TEST] C — dispatch _generate_track (compositore vs vecchie tracce)")
        var am := AMScript.new()
        var scepter: AudioStreamWAV = am._generate_track(am.TRACK_EPIC_SCEPTER)
        _check(scepter != null and not scepter.data.is_empty(),
                        "scettro/vittoria: stream composto valido")
        if scepter != null:
                _check(scepter.mix_rate == am.MUSIC_SR,
                                "scettro: mix_rate %d == MUSIC_SR (22050)" % scepter.mix_rate)
                _check(scepter.loop_mode == AudioStreamWAV.LOOP_DISABLED,
                                "scettro: one-shot (loop disabilitato)")
                var dur: float = float(scepter.data.size() / 2) / float(am.MUSIC_SR)
                _check(dur > 8.0,
                                "scettro: durata %.1fs > 8s (composizione, non arpeggio)" % dur)
        # Il tema del fantasma resta la VECCHIA sintesi (44100); il loop viene
        # applicato da play_ghost_music a runtime (come _play_music_track).
        var ghost_stream: AudioStreamWAV = am._generate_track(am.TRACK_GHOST)
        _check(ghost_stream != null and not ghost_stream.data.is_empty(),
                        "fantasma: stream valido (resta vecchia sintesi)")
        if ghost_stream != null:
                _check(ghost_stream.mix_rate == am.SR,
                                "fantasma: mix_rate %d == SR (44100, path originale)" % ghost_stream.mix_rate)
        add_child(am)
        await get_tree().process_frame   # _ready: crea i player audio
        am.play_ghost_music()
        var played: AudioStreamWAV = am._music_streams[am.TRACK_GHOST]
        _check(played != null and played.loop_mode == AudioStreamWAV.LOOP_FORWARD,
                        "fantasma: play_ghost_music -> LOOP_FORWARD a runtime")
        _check(am._ghost_player.playing,
                        "fantasma: canale dedicato in riproduzione")
        am.stop_ghost_music()


# --- D: ordine della coda di sintesi al boot ---------------------------------
func _test_queue_order() -> void:
        print("[TEST] D — coda di sintesi: priorita' e assenza duplicati")
        var am := AMScript.new()
        am._build_synth_queue()
        var q: Array = am._synth_queue
        _check(q.size() == 86,
                        "coda: 86 task (59 sfx + 18 spari boss + 9 tracce), trovati %d" \
                        % q.size())
        if q.size() >= 3:
                _check(q[0] == ["sfx", am.SoundType.MENU_SELECT],
                                "posizione 0: SFX MENU_SELECT (feedback UI immediato)")
                _check(q[1] == ["sfx", am.SoundType.MENU_CONFIRM],
                                "posizione 1: SFX MENU_CONFIRM")
                _check(q[2] == ["music", am.TRACK_MENU],
                                "posizione 2: traccia MENU' (musica appena avviato)")
        var sfx_seen := {}
        var dup := false
        var music_count := 0
        for task in q:
                if task[0] == "sfx":
                        if sfx_seen.has(task[1]):
                                dup = true
                        sfx_seen[task[1]] = true
                elif task[0] == "music":
                        music_count += 1
        _check(not dup, "coda: nessun SFX duplicato (%d sfx unici)" % sfx_seen.size())
        _check(sfx_seen.size() == am.SOUND_TYPE_COUNT,
                        "coda: tutti i %d SoundType presenti" % am.SOUND_TYPE_COUNT)
        _check(music_count == 9, "coda: 9 tracce musicali (4 liv+boss+portale+"
                        + "scettro+menu+fantasma)")
