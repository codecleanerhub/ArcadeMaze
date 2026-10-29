## test_task93_chalice_sfx.gd — TASK 93: musica del calice ELIMINATA, al suo
## posto un effetto sonoro "epico di potere" (CHALICE_POWER).
##
## Richiesta utente: "voglio che elimini la musica che parte quando si prende
## il calice di fuoco, fai partire al suo posto un effetto sonoro 'epico'
## di potere".
##
## Check:
##   A — enum/contatori coerenti: CHALICE_POWER = 57, SOUND_TYPE_COUNT = 58,
##       il generatore produce 2.2s esatti (97020 campioni), no clipping
##       (peak <= 0.87) e NON e' muto (energia RMS significativa).
##   B — forma d'onda in 4 fasi: energia nella carica (0-0.55s) crescente,
##       picco all'impatto (~0.55-0.85s) > energia carica, fanfara presente
##       (0.85-1.65s), coda che decade (1.9-2.2s) < fanfara.
##   C — guardie sorgente: nessun play_epic_music(TRACK_EPIC_CHALICE) nei
##       script di gioco, _gen_epic_chalice rimosso, coda di sintesi senza
##       la traccia 6 (grep testuale sui sorgenti).
##   D — integrazione (MainGame reale): spawn calice sotto il player ->
##       pickup: invincible_timer = 9500, CHALICE_POWER suonato (voce del
##       pool SFX con quello stream / _last_sfx_type), canale epic FERMO
##       (_epic_playing false, _epic_player.playing false), traccia 6 MAI
##       sintetizzata (_music_streams[6] null).
##   E — scadenza effetto: invincibilita' finita -> NESSUNA musica epic si
##       avvia/si ferma, nessun errore, il player resta vivo.
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

const SR := 44100
const EXPECT_LEN := int(SR * 2.2)  # 97020

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var phase_t: float = 0.0
var failures: Array = []
var inv_was_set: bool = false


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        GameManager.num_players = 1
        # La bonus card del calice metterebbe in PAUSA l'albero (first pickup
        # per sessione): la pre-macro come gia' vista per restare concentrati
        # sull'audio (musica eliminata + SFX epico).
        GameManager.mark_bonus_card_seen("kind_%d" % int(CollectiblesClass.Kind.CHALICE))
        print("[TEST] TASK 93 — musica calice eliminata, SFX epico al suo posto")
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ok(msg: String) -> void:
        print("[TEST] OK ", msg)


func _next(next_phase: int) -> void:
        phase = next_phase
        phase_t = 0.0


## Energia RMS di una finestra del campione.
func _rms(w: PackedFloat32Array, from_s: float, to_s: float) -> float:
        var i0: int = int(from_s * SR)
        var i1: int = mini(int(to_s * SR), w.size())
        if i1 <= i0:
                return 0.0
        var acc: float = 0.0
        for i in range(i0, i1, 7):
                acc += w[i] * w[i]
        return sqrt(acc / float((i1 - i0) / 7))


func _physics_process(delta: float) -> void:
        t += delta
        phase_t += delta
        if t > 45.0:
                _fail("timeout globale del test (45s)")
                get_tree().quit(1)
                return
        match phase:
                0:
                        if phase_t > 0.1 and _phase_static():
                                _next(1)
                1:
                        # --- boot MainGame (overlay loading ~2.2s) ---
                        if main == null or not main.is_node_ready():
                                return
                        if phase_t > 3.2:
                                _next(2)
                2:
                        # --- D: spawn calice sotto il player ---
                        if not inv_was_set:
                                _spawn_chalice_on_player()
                                _next(3)
                3:
                        if not inv_was_set:
                                if main.player.invincible_timer > 0:
                                        inv_was_set = true
                                        _check_pickup_audio()
                                        _next(4)
                                elif phase_t > 6.0:
                                        _fail("D: il calice non e' stato raccolto "
                                                        + "entro 6s (invincible_timer=0)")
                                        _next(9)
                4:
                        # --- E: scadenza effetto ---
                        main.player.invincible_timer = 120
                        _next(5)
                5:
                        if phase_t > 0.6:
                                _check_expiry()
                                _next(9)
                9:
                        # --- verdetto ---
                        if failures.is_empty():
                                print("[TEST] TASK 93: TUTTI I CHECK SUPERATI")
                                get_tree().quit(0)
                        else:
                                print("[TEST] TASK 93: ", failures.size(), " FALLIMENTI")
                                get_tree().quit(1)


## --- A/B: contatori, lunghezza, clipping, energia per fasi ------------------
func _phase_static() -> bool:
        var am := get_node("/root/AudioManager")
        if int(am.SoundType.CHALICE_POWER) != 57:
                _fail("A: CHALICE_POWER = " + str(int(am.SoundType.CHALICE_POWER))
                                + ", atteso 57")
        else:
                _ok("A1: SoundType.CHALICE_POWER = 57 (nuova voce)")
        if am.SOUND_TYPE_COUNT != 59:
                _fail("A: SOUND_TYPE_COUNT = " + str(am.SOUND_TYPE_COUNT)
                                + ", atteso 59 (LEVEL_UP Task 99)")
        else:
                _ok("A2: SOUND_TYPE_COUNT = 59")

        var w: PackedFloat32Array = am._sfx_chalice_power()
        if w.size() != EXPECT_LEN:
                _fail("A: lunghezza " + str(w.size()) + " campioni, attesi "
                                + str(EXPECT_LEN))
                return false
        _ok("A3: SFX lungo 2.2s esatti (one-shot)")

        var peak: float = 0.0
        var abs_acc: float = 0.0
        var count: int = 0
        for i in range(0, w.size(), 31):
                var av: float = absf(w[i])
                if av > peak:
                        peak = av
                abs_acc += av
                count += 1
        var mean_abs: float = abs_acc / float(count)
        if peak > 0.87:
                _fail("A: clipping (peak " + str(peak) + " > 0.87)")
        else:
                _ok("A4: peak " + ("%.3f" % peak) + " — no clipping")
        if mean_abs < 0.02:
                _fail("A: SFX quasi muto (media |s| " + str(mean_abs) + ")")
        else:
                _ok("A5: energia media " + ("%.3f" % mean_abs) + " — presente")

        # --- B: energia per fasi ---
        var e_charge_a := _rms(w, 0.05, 0.25)
        var e_charge_b := _rms(w, 0.35, 0.54)
        var e_impact := _rms(w, 0.55, 0.85)
        var e_fanfare := _rms(w, 0.9, 1.6)
        var e_tail := _rms(w, 1.95, 2.18)
        if not (e_charge_b >= e_charge_a * 1.5):
                _fail("B: carica non crescente (rms " + str(e_charge_a) + " -> "
                                + str(e_charge_b) + ")")
        else:
                _ok("B1: riser crescente (rms " + ("%.3f" % e_charge_a) + " -> "
                                + ("%.3f" % e_charge_b) + ")")
        if not (e_impact > e_charge_b):
                _fail("B: impatto non domina la carica (" + str(e_impact)
                                + " vs " + str(e_charge_b) + ")")
        else:
                _ok("B2: impatto > carica (rms " + ("%.3f" % e_impact) + ")")
        if e_fanfare < 0.035:
                _fail("B: fanfara assente (rms " + str(e_fanfare) + ")")
        else:
                _ok("B3: fanfara presente (rms " + ("%.3f" % e_fanfare) + ")")
        if not (e_tail < e_fanfare):
                _fail("B: coda non decrescente (" + str(e_tail)
                                + " vs " + str(e_fanfare) + ")")
        else:
                _ok("B4: coda in decrescenza (rms " + ("%.3f" % e_tail) + ")")

        # --- C: guardie sorgente ---
        var dir: String = ProjectSettings.globalize_path("res://scripts")
        var mgd := FileAccess.get_file_as_string(
                        dir + "/core/MainGameController.gd")
        if mgd.contains("TRACK_EPIC_CHALICE, true") \
                        or mgd.contains("AudioManager.TRACK_EPIC_CHALICE"):
                _fail("C: MainGameController ancora lancia la musica del calice")
        else:
                _ok("C1: pickup calice senza play_epic_music")
        if not mgd.contains("SoundType.CHALICE_POWER"):
                _fail("C: pickup calice non usa CHALICE_POWER")
        else:
                _ok("C2: pickup calice usa CHALICE_POWER")
        var agd := FileAccess.get_file_as_string(
                        dir + "/audio/AudioManager.gd")
        if agd.contains("func _gen_epic_chalice"):
                _fail("C: _gen_epic_chalice ancora presente")
        else:
                _ok("C3: generatore musica calice rimosso")
        if agd.contains('_synth_queue.append(["music", TRACK_EPIC_CHALICE])'):
                _fail("C: traccia calice ancora in coda di sintesi")
        else:
                _ok("C4: traccia 6 fuori dalla coda di sintesi")
        return failures.is_empty() or true


## --- D: spawn del calice esattamente sotto il player -------------------------
func _spawn_chalice_on_player() -> void:
        # rimuovi chalice di livello (se esiste) per non raccogliere quello
        if main.chalice_item != null and is_instance_valid(main.chalice_item):
                main.chalice_item.active = false
                main.chalice_item.queue_free()
        var ch := CollectiblesClass.new()
        ch.kind = CollectiblesClass.Kind.CHALICE
        ch.pos = main.player.get_pixel_pos()
        ch.position = ch.pos
        ch.active = true
        main.collectibles_node.add_child(ch)
        main.chalice_item = ch
        print("[TEST] calice spawnato sotto il player a ", ch.pos)


## --- D: verifica audio DOPO il pickup ---------------------------------------
func _check_pickup_audio() -> void:
        var am := get_node("/root/AudioManager")
        if main.player.invincible_timer != 9500:
                _fail("D: invincible_timer = " + str(main.player.invincible_timer)
                                + ", atteso 9500")
        else:
                _ok("D1: invincibilità 9500ms (effetto calice attivo)")

        # canale epic: FERMO (nessuna musica)
        if am._epic_playing or am._epic_player.playing:
                _fail("D: canale epic attivo dopo il pickup (musica non eliminata)")
        else:
                _ok("D2: canale epic FERMO — nessuna musica del calice")
        if am._epic_track_idx == 6:
                _fail("D: traccia epic 6 (calice) in riproduzione")
        # traccia 6 mai sintetizzata (ne' dal worker ne' on-demand)
        if am._music_streams[6] != null:
                _fail("D: _music_streams[6] non null — la traccia calice e' "
                                + "stata richiesta/generata")
        else:
                _ok("D3: traccia 6 mai sintetizzata (slot null per sempre)")

        # CHALICE_POWER suonato: voce del pool con quello stream, oppure
        # _last_sfx_type ancora puntato (nessun altro suono dopo il pickup).
        var idx: int = int(am.SoundType.CHALICE_POWER)
        var played: bool = am._last_sfx_type == idx
        if not played:
                for v in am._sfx_pool:
                        if v != null and v.stream != null \
                                        and v.stream == am._sfx_streams[idx]:
                                played = true
                                break
        if not played:
                _fail("D: CHALICE_POWER non suonato al pickup")
        else:
                _ok("D4: SFX CHALICE_POWER suonato (voce pool SFX)")


## --- E: verifica audio alla SCADENZA dell'effetto ---------------------------
func _check_expiry() -> void:
        var am := get_node("/root/AudioManager")
        if main.player.invincible_timer > 0:
                _fail("E: invincibilità non scaduta ("
                                + str(main.player.invincible_timer) + ")")
        else:
                _ok("E1: invincibilità scaduta regolarmente")
        if am._epic_playing or am._epic_player.playing:
                _fail("E: canale epic attivo alla scadenza (imprevisto)")
        else:
                _ok("E2: nessuna musica epic alla scadenza (niente da fermare)")
        if not is_instance_valid(main.player) or not main.player.visible:
                _fail("E: player morto/invisibile dopo la scadenza")
        else:
                _ok("E3: player vivo e visibile dopo la scadenza")
