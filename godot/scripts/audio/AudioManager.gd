# ============================================================================
# AudioManager.gd  (Autoload singleton -> name: AudioManager)
#
# Godot port of:
#   - AudioManager.h
#   - AudioManager.cpp
#
# All sound + music is generated PROCEDURALLY at runtime (chiptune NES/SNES/C64
# style), mirroring the original SFML game where every byte of audio was
# synthesized mathematically. No external .wav/.ogg files are loaded.
#
# Waveforms (mirror C++ static helpers):
#   * Pulse wave (square with duty cycle)  -> lead melodies, arpeggios
#   * Triangle wave                         -> bass lines
#   * Sawtooth wave                         -> pads, harmonics
#   * White noise                           -> percussion, impacts
#
# Content (mirrors AudioManager.h):
#   * 25 sound effects (SoundType enum).
#   * 9 music tracks:
#       0..3 = level music (dark/dramatic dungeon mood)
#       4    = boss (aggressive, 130 BPM)
#       5    = magic portal (slow, mystical)
#       6    = EPIC CHALICE jingle (golden hero fanfare)
#       7    = EPIC SCEPTER jingle (arcane, tense)
#       8    = main menu (choiral fantasy, loop)
#   The two epic jingles play on a SEPARATE channel (`epic_player`) so they
#   do NOT interrupt the background music.
#
# Synthesis notes (Godot 4):
#   * AudioStreamWAV (FORMAT_16_BITS, mono, 44100 Hz) is used for both SFX
#     and pre-rendered music tracks. Each buffer is built sample-by-sample
#     in GDScript and then handed to a pool of AudioStreamPlayer nodes for
#     polyphonic playback (30 voices, voice-stealing).
#   * `music_player` is a dedicated AudioStreamPlayer for the loop music.
#   * `epic_player` is a second dedicated AudioStreamPlayer for one-shot
#     epic jingles (chalice / scepter).
# ============================================================================
extends Node

# --- SoundType enum (mirrors AudioManager.h:SoundType) ----------------------
enum SoundType {
        # Weapons (4)
        PISTOL, SHOTGUN, ROCKET, LASER,
        # Gameplay (6)
        TREASURE, ENEMY_DEATH, LOSE_LIFE, WIN, BOSS_HIT, BOSS_DEATH,
        # Retro SFX (5)
        JUMP, DOOR_OPEN, TRAP, MENU_SELECT, MENU_CONFIRM,
        # Gameplay effects (10)
        PORTAL_OPEN, PORTAL_CLOSE, WEAPON_PICKUP, ENEMY_EXPLODE,
        BLOOD_SPLAT, MINE_BOUNCE, POTION_DRINK, LIGHTNING, SCEPTER_PICKUP,
        # FIX (pozione magica): deglutizione quando il player beve la pozione
        POTION_GULP,
        # FIX (mini boss immortale "Hurry Up!"): risata tenebrosa del
        # fantasma — si sente quando gli si spara addosso (non può morire)
        # e quando appare dal portale.
        DARK_LAUGH,
        # FIX (stamina salti): click secco "a vuoto" del tasto di salto
        # quando il player prova a saltare senza stamina (pulsante premuto
        # senza molla: non salta, si sente solo il click).
        STAMINA_CLICK,
        # FIX (martello di Thor — nuova meccanica): whoosh del lancio,
        # clang metallico dell'impatto su muro di bordo/nemico e crollo
        # sgretolamento del muro interno spezzato.
        HAMMER_THROW,
        HAMMER_CLANK,
        WALL_CRUMBLE,
        # FUOCO AMICO (Task 18 — trasferimento anima): l'anim del player
        # ucciso dal compagno si separa dal corpo e vola verso il vincitore;
        # all'assorbimento l'energia del vincitore si ricarica al massimo.
        # SOUL_RELEASE = whoosh etereo ascendente (separazione),
        # SOUL_ABSORB = scintillio arpeggiato (ricarica energia).
        SOUL_RELEASE,
        SOUL_ABSORB,
        # RELIC (Task 21 — reliquie delle schermate bonus): equipaggiamento
        # reliquia (campana cristallina), rottura reliquia/armatura (crepak
        # + frantumazione), fendente in mischia (whoosh lama), rimbalzo delle
        # Scaglie del Drago (ping metallico-eterico).
        RELIC_PICKUP,
        RELIC_BREAK,
        MELEE_SWING,
        REFLECT_BOLT,
        # TASK 30 — hazard ambientali del labirinto: scatto delle ganasce
        # sulla vittima (snap metallico), scatto a vuoto per disarmo (molla
        # che rilascia), rombo sordo della crepa (telegrafo voragine),
        # crollo dell'apertura (crack + frana), sfregamento delle lastre
        # di roccia (apertura/chiusura) e tonfo finale della chiusura.
        HAZARD_SNAP,
        HAZARD_DISARM,
        HAZARD_RUMBLE,
        HAZARD_COLLAPSE,
        HAZARD_GRIND,
        HAZARD_THUD,
        # TASK 31 — barile esplosivo: botto profondo con frana di legno e
        # metallo (piu' grande e piu' lungo del tonfo del muro).
        BARREL_EXPLODE,
        # TASK 32 — nube di pipistrelli: stridio (chittering di squittii acuti
        # in rapida successione) e battito d'ali (soffici soffiate d'aria).
        BAT_SCREECH,
        BAT_FLAP,
        # TASK 36 — apparizione delle pergamene evento: FULMINE che si
        # abbatte al suolo. Effetto audio LUNGO (~1.9s) e piu' pronunciato
        # del PORTAL_OPEN usato prima: carica elettrica discendente, crack
        # della saetta, sweep elettrico, boom dell'impatto e coda di tuono
        # rotolante che sfuma.
        SCROLL_LIGHTNING,
        # TASK 39 — L'ARENA DEL BOSS: SFX dedicati delle nuove meccaniche.
        # SIEGE_FIRE: sparo del Cannone d'Assedio — sibilo di miccia, botta
        #   profonda della carica e coda metallica della canna (~0.6s).
        # BARREL_TOSS: lancio del barile elementale — whoosh grave di oggetto
        #   pesante che ruota (~0.3s).
        # PILLAR_CRACK: colpo che fessura il pilastro — schiocco secco +
        #   trickle di detriti (~0.35s).
        # PILLAR_COLLAPSE: crollo del pilastro — scricchiolio, frana di
        #   pietra e tonfo finale (~1.1s).
        # WEAKNESS_HIT: colpo DEBOLE del boss con l'elemento giusto — campana
        #   critica ascendente che premia la lettura strategica (~0.7s).
        # BURST_FROST / BURST_LIGHTNING / BURST_POISON: deflagrazioni dei
        #   barili elementali (il FUOCO riusa BARREL_EXPLODE) — vetro in
        #   frantumi, scarica elettrica, sibilo di gas corrosivo.
        SIEGE_FIRE,
        BARREL_TOSS,
        PILLAR_CRACK,
        PILLAR_COLLAPSE,
        WEAKNESS_HIT,
        BURST_FROST,
        BURST_LIGHTNING,
        BURST_POISON,
        # TASK 50 (pergamena del GHIACCIO): FREEZE_RAY = sparo del raggio
        #   congelante — sweep discendente cristallino (il freddo "cala")
        #   con soffio di brina e coda di ghiaccio che si solidifica
        #   (~0.5s).
        # TASK 50b: FREEZE_HIT = COLPO del raggio sul nemico — il blocco di
        #   ghiaccio cristallizza attorno alla creatura: schiocco vetroso,
        #   crepitio di espansione con ping di cristalli che crescono e
        #   tonfo freddo della solidificazione (~0.55s).
        FREEZE_RAY,
        FREEZE_HIT,
        # TASK 87 — MORTE DEL PLAYER: gemito di sofferenza mentre il corpo
        #   si accascia al pavimento (due onde: urletto discendente +
        #   gemito grave morente con respiro, ~0.85s).
        PLAYER_SUFFER
}
# NB: fix off-by-one pre-esistente (il conteggio dichiarava una voce in piu'
# dell'enum reale: slot nullo mai generato, innocuo ma impreciso).
# 46 voci storiche (0..45) + 8 del Task 39 + 1 Task 50 + 1 Task 50b +
# 1 Task 87 = 57 (0..56).
const SOUND_TYPE_COUNT: int = 57

# --- Music track indices (mirrors AudioManager.h) ---------------------------
const TRACK_LEVEL_BASE:   int = 0    # tracks 0..3 = levels
const TRACK_BOSS:          int = 4
const TRACK_PORTAL:        int = 5
const TRACK_EPIC_CHALICE:  int = 6    # jingle (one-shot, separate channel)
const TRACK_EPIC_SCEPTER:  int = 7    # jingle (one-shot, separate channel)
const TRACK_MENU:          int = 8    # main-menu music (loop)
# FIX (pozione magica): tema fantasmagorico/suspense che accompagna tutto il
# periodo dell'effetto fantasma (canale dedicato _ghost_player, in loop).
const TRACK_GHOST:         int = 9
const MUSIC_TRACK_COUNT:   int = 10

# Sample rate (mono).
const SR: int = 44100

# TASK 26 — SFX DI SPARO DEI BOSS: numero di timbre (= BossProjKind di
# Projectile.gd: BP_NORMAL + 17 tematici). Indicizzati per kind, NON per
# SoundType (slot debounce separato 1000+kind).
const BOSS_SHOOT_KIND_COUNT: int = 18
var _boss_shoot_streams: Array[AudioStreamWAV] = []

# Master volumes (mirror C++ setVolume calls).
const VOLUME_SFX:     float = 0.9    # 90 / 100 (aumentato da 0.7)
const VOLUME_MUSIC:   float = 0.8    # 80 / 100 (aumentato da 0.45)
const VOLUME_EPIC:    float = 1.0    # 100 / 100 (aumentato da 0.8)

# --- State ------------------------------------------------------------------
# Pool of 30 SFX voices (polyphony with voice stealing).
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_streams: Array[AudioStreamWAV] = []   # one per SoundType

# Pre-rendered music tracks (one AudioStreamWAV per track index).
var _music_streams: Array[AudioStreamWAV] = []

# Two dedicated channels (mirror `music` and `epicSound` in C++).
var _music_player: AudioStreamPlayer = null
var _epic_player:  AudioStreamPlayer = null
# FIX (pozione magica): canale dedicato per il tema fantasma — separato dal
# canale epic (che può suonare il jingle del calice) così i due effetti
# possono coesistere senza interrompersi a vicenda.
var _ghost_player:  AudioStreamPlayer = null
var _ghost_music_playing: bool = false

# Current track index for the music channel (or -1 if stopped).
var _current_music_track: int = -1
# True if the epic channel is currently playing a jingle.
var _epic_playing: bool = false
# Track index currently on the epic channel (or -1 if stopped).
var _epic_track_idx: int = -1

# TASK 76 — sintesi progressiva in background thread.
var _synth_thread: Thread = null
var _synth_mutex: Mutex = Mutex.new()
var _synth_cancel: bool = false
var _synth_queue: Array = []  # [[kind:String, idx:int], ...] in ordine di priorita'
var _synth_started_ms: int = 0
var _synth_done_count: int = 0
# Traccia musicale richiesta mentre era ancora in sintesi (parte da sola
# appena il worker la rende disponibile).
var _pending_music_track: int = -1
var _pending_music_loop: bool = true

# Master switch (mirrors Game::musicEnabled).
# FIX (musica parte al boot anche se in off): default music_enabled = false
# per allinearsi con GameManager.music_enabled (default false). Prima era
# true di default, e al boot la musica partiva anche se l'utente l'aveva
# disattivata nella sessione precedente. Ora parte solo quando il GameManager
# chiama set_music_enabled(true) dopo aver letto la configurazione salvata.
var music_enabled: bool = false


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        # Build the node graph
        _music_player = AudioStreamPlayer.new()
        _music_player.name = "MusicPlayer"
        _music_player.volume_db = linear_to_db(VOLUME_MUSIC)
        _music_player.bus = "Master"
        add_child(_music_player)

        _epic_player = AudioStreamPlayer.new()
        _epic_player.name = "EpicPlayer"
        _epic_player.volume_db = linear_to_db(VOLUME_EPIC)
        _epic_player.bus = "Master"
        add_child(_epic_player)

        # FIX (pozione magica): canale del tema fantasma
        _ghost_player = AudioStreamPlayer.new()
        _ghost_player.name = "GhostPlayer"
        _ghost_player.volume_db = linear_to_db(VOLUME_EPIC)
        _ghost_player.bus = "Master"
        add_child(_ghost_player)

        # Ensure Master bus is not muted
        var master_idx: int = AudioServer.get_bus_index("Master")
        if master_idx >= 0:
                AudioServer.set_bus_mute(master_idx, false)
                AudioServer.set_bus_volume_db(master_idx, 0.0)
        print("[AudioManager] Ready - music_player=%s epic_player=%s" % [
                _music_player != null, _epic_player != null])

        # 30-voice SFX pool
        for i in 30:
                var p := AudioStreamPlayer.new()
                p.name = "SFX_%02d" % i
                p.volume_db = linear_to_db(VOLUME_SFX)
                p.bus = "Master"
                add_child(p)
                _sfx_pool.append(p)

        # TASK 76 (avvio lento — segnalazione utente: "il gioco ci mette
        # parecchio a partire, carica tutto in un colpo?"): la pre-sintesi
        # COMPLETA di 56 SFX + 18 spari boss + 10 tracce musicali bloccava
        # il boot per ~16s (misurato: SFX 1.4s + musica 14.5s). Ora la
        # sintesi corre in un THREAD IN BACKGROUND con ordine di priorita'
        # (menu -> SFX -> tracce livello -> boss/portale -> jingle -> spari
        # boss): il menu appare in ~0.3s e tutto il resto arriva mentre
        # l'utente naviga. Ogni play_* ha un fallback on-demand (sintesi
        # sincrona) se il suono non e' ancora pronto.
        _synth_started_ms = Time.get_ticks_msec()
        var _boot_t0: int = Time.get_ticks_msec()
        _sfx_streams.resize(SOUND_TYPE_COUNT)
        _boss_shoot_streams.resize(BOSS_SHOOT_KIND_COUNT)
        _music_streams.resize(MUSIC_TRACK_COUNT)
        _build_synth_queue()
        _synth_thread = Thread.new()
        _synth_thread.start(_synth_worker)
        print("[AudioManager] synth worker avviato (boot audio: %d ms)" % [Time.get_ticks_msec() - _boot_t0])


# Play a one-shot sound effect on the first free voice in the SFX pool.
# Anti-overlap: if the same sound type is already playing, skip (debounce).
var _last_sfx_type: int = -1
var _last_sfx_time_ms: int = 0
const SFX_DEBOUNCE_MS: int = 200  # min 200ms between same SFX (anti-overlap)

func play_sound(type: SoundType) -> void:
        var idx: int = int(type)
        if idx < 0 or idx >= _sfx_streams.size():
                return
        var stream: AudioStreamWAV = _sfx_streams[idx]
        if stream == null:
                # TASK 76: SFX non ancora sintetizzato dal worker (partita
                # iniziata nei primi secondi) -> sintesi on-demand (~25ms).
                stream = _generate_sfx(idx as SoundType)
                _sfx_streams[idx] = stream
        if stream == null:
                return
        # Debounce: skip if same sound was played < 200ms ago
        var now_ms: int = Time.get_ticks_msec()
        if idx == _last_sfx_type and (now_ms - _last_sfx_time_ms) < SFX_DEBOUNCE_MS:
                return
        _last_sfx_type = idx
        _last_sfx_time_ms = now_ms
        var voice := _find_free_voice()
        voice.stream = stream
        voice.play()


# TASK 26 — suona lo sparo del boss per TIPO DI MUNIZIONE (BossProjKind).
# Debounce SUO (slot 1000+kind, condivide la finestra SFX_DEBOUNCE_MS): il
# boss spara ogni 1-2.5s, il debounce evita solo i raddoppi accidentali.
func play_boss_shoot(kind: int) -> void:
        if _boss_shoot_streams.is_empty():
                return
        if kind < 0 or kind >= _boss_shoot_streams.size():
                kind = 0
        var stream: AudioStreamWAV = _boss_shoot_streams[kind]
        if stream == null:
                # TASK 76: fallback on-demand (sintesi progressiva).
                stream = _generate_boss_shoot(kind)
                _boss_shoot_streams[kind] = stream
        if stream == null:
                return
        var now_ms: int = Time.get_ticks_msec()
        var slot: int = 1000 + kind
        if slot == _last_sfx_type and (now_ms - _last_sfx_time_ms) < SFX_DEBOUNCE_MS:
                return
        _last_sfx_type = slot
        _last_sfx_time_ms = now_ms
        var voice := _find_free_voice()
        voice.stream = stream
        voice.play()


# Start the background music (only if it was stopped).
func start_music() -> void:
        if not music_enabled:
                return
        if not _music_player.playing:
                _music_player.play()


# Stop the background music.
func stop_music() -> void:
        _music_player.stop()
        _current_music_track = -1


# Switch to the appropriate level/boss/portal track.
# Mirrors playLevelMusic(level, isBoss):
#   * level == 0 and not isBoss  -> portal music (track 5)
#   * isBoss                     -> boss music (track 4)
#   * otherwise                  -> (level-1) % 4 (tracks 0..3)
func play_level_music(level: int, is_boss: bool) -> void:
        var track_idx: int
        if level == 0 and not is_boss:
                track_idx = TRACK_PORTAL
        elif is_boss:
                track_idx = TRACK_BOSS
        else:
                track_idx = (level - 1) % 4
        _play_music_track(track_idx, true)


# Play the menu music (track 8), looping.
func play_menu_music() -> void:
        print("[AudioManager] play_menu_music called - music_enabled=%s" % music_enabled)
        _play_music_track(TRACK_MENU, true)


# Play an epic jingle on the dedicated channel.
# track_idx must be TRACK_EPIC_CHALICE, TRACK_EPIC_SCEPTER or TRACK_MENU.
# FIX (musica calice): nuovo parametro `loop` - il jingle del calice suona
# in LOOP per tutta la durata dell'invincibilità (lo ferma il Game con
# stop_epic_music quando l'effetto scade). Scettro/victory restano one-shot
# come nel C++ originale (AudioManager.cpp:104 epicSound.setLoop(false)).
# FIX (gate rimosso): come nel C++ originale, il canale epic è un canale
# EFFETTO separato NON soggetto al flag musicEnabled (il gate impediva di
# sentire il jingle del calice con la musica disattivata).
# Un jingle DIVERSO da quello in riproduzione ha la priorità (es. calice
# raccolto mentre suona ancora lo scettro): il canale si riavvia.
func play_epic_music(track_idx: int, loop: bool = false) -> void:
        if track_idx < TRACK_EPIC_CHALICE or track_idx > TRACK_MENU:
                return
        if _epic_playing and _epic_player.playing and _epic_track_idx == track_idx:
                return  # stesso jingle già in riproduzione: no restart
        var stream: AudioStreamWAV = _music_streams[track_idx]
        if stream == null:
                # TASK 76: fallback on-demand (sintesi progressiva).
                stream = _generate_track(track_idx)
                _music_streams[track_idx] = stream
        if stream == null:
                return
        stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
        _epic_player.stream = stream
        _epic_player.play()
        _epic_playing = true
        _epic_track_idx = track_idx


# Stop the epic jingle (if playing).
func stop_epic_music() -> void:
        _epic_player.stop()
        _epic_playing = false
        _epic_track_idx = -1


# ============================================================================
# FIX (pozione magica): tema fantasmagorico — canale dedicato in loop per
# tutto il periodo dell'effetto fantasma. Come il canale epic, NON è soggetto
# al flag musicEnabled (è un effetto di gioco, non musica di sottofondo):
# lo senti anche con la musica disattivata, esattamente come il jingle del
# calice (AudioManager.cpp:98).
func play_ghost_music() -> void:
        if _ghost_music_playing and _ghost_player.playing:
                return  # già in riproduzione: no restart
        var stream: AudioStreamWAV = _music_streams[TRACK_GHOST]
        if stream == null:
                # TASK 76: fallback on-demand (sintesi progressiva).
                stream = _generate_track(TRACK_GHOST)
                _music_streams[TRACK_GHOST] = stream
        if stream == null:
                return
        stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
        _ghost_player.stream = stream
        _ghost_player.play()
        _ghost_music_playing = true


# Ferma il tema fantasma (chiamato dal Game quando l'effetto termina).
func stop_ghost_music() -> void:
        _ghost_player.stop()
        _ghost_music_playing = false


# True if the music channel is currently playing.
func is_music_playing() -> bool:
        return _music_player.playing


# Enable/disable music entirely (mirrors Game::musicEnabled flag toggling).
func set_music_enabled(enabled: bool) -> void:
        music_enabled = enabled
        if not enabled:
                stop_music()
                stop_epic_music()

# ============================================================================
# TASK 76 — Sintesi progressiva (background thread)
# ============================================================================

## Coda di sintesi in ordine di PRIORITA': menu subito (serve quando il
## menu principale appare), poi tutti gli SFX (economici, servono ovunque),
## poi le tracce dei livelli (il livello 1 e' il primo che si gioca), poi
## boss/portale/jingle/fantasma, infine gli spari dei boss (solo boss room).
func _build_synth_queue() -> void:
        _synth_queue.clear()
        _synth_queue.append(["music", TRACK_MENU])
        # TASK 91 (fix scatti distruzioni): gli SFX della BOSS ARENA
        # (crollo pilastri/rovine, esplosioni barili, burst elementali)
        # vanno in TESTA alla coda SFX: se una distruzione avviene nei
        # primi secondi di boot, lo stream e' gia' sintetizzato (niente
        # fallback on-demand SINCRONO nel frame del crollo, che congela
        # il main thread per ~25-50ms).
        var arena_first: Array = [
                        SoundType.PILLAR_CRACK, SoundType.PILLAR_COLLAPSE,
                        SoundType.BARREL_EXPLODE, SoundType.SIEGE_FIRE,
                        SoundType.BARREL_TOSS, SoundType.BURST_FROST,
                        SoundType.BURST_LIGHTNING, SoundType.BURST_POISON,
                        SoundType.WEAKNESS_HIT, SoundType.BOSS_HIT,
                        SoundType.BOSS_DEATH, SoundType.HAZARD_COLLAPSE]
        for i in arena_first:
                _synth_queue.append(["sfx", i])
        for i in SOUND_TYPE_COUNT:
                if arena_first.has(i):
                        continue
                _synth_queue.append(["sfx", i])
        for i in 4:
                _synth_queue.append(["music", i])  # tracce livello 0..3
        _synth_queue.append(["music", TRACK_BOSS])
        _synth_queue.append(["music", TRACK_PORTAL])
        _synth_queue.append(["music", TRACK_EPIC_CHALICE])
        _synth_queue.append(["music", TRACK_EPIC_SCEPTER])
        _synth_queue.append(["music", TRACK_GHOST])
        for i in BOSS_SHOOT_KIND_COUNT:
                _synth_queue.append(["boss", i])


## Corpo del thread: estrae un task alla volta, sintetizza e riconsegna il
## risultato al main thread con call_deferred (mai tocco il tree da qui).
func _synth_worker() -> void:
        while true:
                if _synth_cancel:
                        break
                var task: Array = []
                _synth_mutex.lock()
                if not _synth_queue.is_empty():
                        task = _synth_queue.pop_front()
                _synth_mutex.unlock()
                if task.is_empty():
                        break
                var stream: AudioStreamWAV = null
                if task[0] == "sfx":
                        stream = _generate_sfx(task[1] as SoundType)
                elif task[0] == "boss":
                        stream = _generate_boss_shoot(task[1])
                elif task[0] == "music":
                        stream = _generate_track(task[1])
                _apply_synth_result.call_deferred(task[0], int(task[1]), stream)
        _synth_finished.call_deferred()


## Main thread: archivia lo stream sintetizzato e, se c'e' una traccia
## musicale in attesa appena diventata pronta, la fa partire da sola.
func _apply_synth_result(kind: String, idx: int, stream: AudioStreamWAV) -> void:
        if stream == null:
                return
        if kind == "sfx" and idx < _sfx_streams.size():
                _sfx_streams[idx] = stream
        elif kind == "boss" and idx < _boss_shoot_streams.size():
                _boss_shoot_streams[idx] = stream
        elif kind == "music" and idx < _music_streams.size():
                _music_streams[idx] = stream
                if idx == _pending_music_track:
                        _pending_music_track = -1
                        _play_music_track(idx, _pending_music_loop)
        _synth_done_count += 1


## Main thread: worker esaurito — libera il thread e logga il totale.
func _synth_finished() -> void:
        if _synth_thread != null and _synth_thread.is_started():
                _synth_thread.wait_to_finish()
        print("[AudioManager] sintesi completa: %d suoni in %d ms (background)"
                        % [_synth_done_count, Time.get_ticks_msec() - _synth_started_ms])


## Arresto pulito del worker alla chiusura (l'autoload muore con l'app).
func _exit_tree() -> void:
        _synth_cancel = true
        if _synth_thread != null and _synth_thread.is_started():
                _synth_thread.wait_to_finish()


# ============================================================================
# Internal helpers
# ============================================================================

# Pick the first idle SFX voice; if all are busy, reuse voice 0 (voice stealing).
func _find_free_voice() -> AudioStreamPlayer:
        for v in _sfx_pool:
                if not v.playing:
                        return v
        return _sfx_pool[0]


func _play_music_track(track_idx: int, loop: bool) -> void:
        if not music_enabled:
                print("[AudioManager] _play_music_track SKIP - music disabled")
                return
        if track_idx < 0 or track_idx >= _music_streams.size():
                print("[AudioManager] _play_music_track SKIP - invalid track %d (size=%d)" % [track_idx, _music_streams.size()])
                return
        if _music_player == null:
                print("[AudioManager] _play_music_track SKIP - music_player is null")
                return
        _music_player.stop()
        var stream: AudioStreamWAV = _music_streams[track_idx]
        if stream == null:
                # TASK 76 (sintesi progressiva): traccia non ancora pronta —
                # se il worker sta ancora girando, la richiesta resta in
                # attesa e la musica parte DA SOLA appena sintetizzata.
                if _synth_thread != null and _synth_thread.is_started() \
                                and not _synth_queue.is_empty():
                        _pending_music_track = track_idx
                        _pending_music_loop = loop
                        print("[AudioManager] track %d in sintesi: partira' appena pronta" % track_idx)
                        return
                stream = _generate_track(track_idx)
                _music_streams[track_idx] = stream
        if stream == null:
                print("[AudioManager] _play_music_track SKIP - stream %d is null" % track_idx)
                return
        # Toggle loop mode on the cached stream (cheaper than rebuilding).
        stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
        _music_player.stream = stream
        _music_player.play()
        _current_music_track = track_idx
        print("[AudioManager] _play_music_track OK - track=%d loop=%s playing=%s" % [track_idx, loop, _music_player.playing])


# ----------------------------------------------------------------------------
# Waveform generators (port of the static methods in AudioManager.cpp)
# `phase` is in cycles (1.0 = one full period). We use cycles instead of
# radians so the call sites read naturally: phase = t * freq.
# ----------------------------------------------------------------------------
static func pulse_wave(phase: float, duty: float) -> float:
        var p: float = phase - floor(phase)
        return 1.0 if p < duty else -1.0

static func triangle_wave(phase: float) -> float:
        var p: float = phase - floor(phase)
        return (4.0 * p - 1.0) if p < 0.5 else (3.0 - 4.0 * p)

static func sawtooth_wave(phase: float) -> float:
        var p: float = phase - floor(phase)
        return 2.0 * p - 1.0

# FIX (pozione magica): onda sinusoidale pura, usata dal tema fantasma per
# i lamenti (wail) e i tritoni di tensione.
static func sine_wave(phase: float) -> float:
        return sin(TAU * (phase - floor(phase)))

# White noise in [-1, 1] (port of noiseGen()).
static func noise_gen() -> float:
        return randf_range(-1.0, 1.0)


# ----------------------------------------------------------------------------
# Convert a list of float samples (in [-1, 1]) to a mono 16-bit PCM
# AudioStreamWAV. Mirrors `loadFromSamples(samples, count, 1, SR)` in C++.
#
# IMPORTANT (fix bug audio #3 — sibilo continuo):
#   SFX one-shot MUST NOT loop. In C++ AudioManager, sf::Sound::setLoop(false)
#   was always applied to SFX voices. In the previous Godot port, every stream
#   (including SFX) was created with LOOP_FORWARD, so each SFX trigger laid
#   down a permanently looping blip. After ~30 menu moves, all 30 SFX voices
#   were looping the same 880 Hz pulse wave on top of the menu music,
#   producing the "continuous whistle" the user reported.
#   Now: SFX streams default to LOOP_DISABLED; only the music path passes
#   loop=true (and _play_music_track already toggles loop_mode correctly).
# ----------------------------------------------------------------------------
func _samples_to_stream(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
        var bytes := PackedByteArray()
        bytes.resize(samples.size() * 2)
        var i: int = 0
        # Find max amplitude for normalization
        var max_amp: float = 0.001  # avoid div by zero
        for s in samples:
                var abs_s: float = absf(s)
                if abs_s > max_amp:
                        max_amp = abs_s
        # Normalize to 0.9 (90% volume) and amplify
        var gain: float = 0.9 / max_amp
        for s in samples:
                # Soft clip to avoid harsh digital clipping
                var v: float = clampf(s * gain, -1.0, 1.0)
                var int16: int = int(round(v * 32767.0))
                # Little-endian Int16
                bytes.encode_s16(i, int16)
                i += 2
        var stream := AudioStreamWAV.new()
        stream.format = AudioStreamWAV.FORMAT_16_BITS
        stream.mix_rate = SR
        stream.stereo = false
        stream.data = bytes
        # SFX must be one-shot (loop=false). Music tracks set loop=true.
        stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
        stream.loop_begin = 0
        stream.loop_end = samples.size()
        return stream


# ----------------------------------------------------------------------------
# Soft clip (used by complex SFX like SCEPTER_PICKUP to avoid hard clipping).
# ----------------------------------------------------------------------------
static func _soft_clip(s: float) -> float:
        if s > 1.0:
                return 1.0 - 0.3 * (1.0 - 1.0 / s)
        if s < -1.0:
                return -1.0 + 0.3 * (1.0 + 1.0 / s)
        return s


# ============================================================================
# SFX synthesis (port of AudioManager::playSound for each SoundType)
# Each function builds a PackedFloat32Array of samples then converts.
# ============================================================================
func _generate_sfx(type: int) -> AudioStreamWAV:
        var s := PackedFloat32Array()
        match type:
                SoundType.PISTOL:        s = _sfx_pistol()
                SoundType.SHOTGUN:       s = _sfx_shotgun()
                SoundType.ROCKET:        s = _sfx_rocket()
                SoundType.LASER:         s = _sfx_laser()
                SoundType.TREASURE:      s = _sfx_treasure()
                SoundType.ENEMY_DEATH:   s = _sfx_enemy_death()
                SoundType.LOSE_LIFE:     s = _sfx_lose_life()
                SoundType.WIN:           s = _sfx_win()
                SoundType.BOSS_HIT:      s = _sfx_boss_hit()
                SoundType.BOSS_DEATH:    s = _sfx_boss_death()
                SoundType.JUMP:          s = _sfx_jump()           # "BOING" spring bounce
                SoundType.DOOR_OPEN:     s = _sfx_door_open()
                SoundType.TRAP:          s = _sfx_trap()
                SoundType.MENU_SELECT:   s = _sfx_menu_select()
                SoundType.MENU_CONFIRM:  s = _sfx_menu_confirm()
                SoundType.PORTAL_OPEN:   s = _sfx_portal_open()
                SoundType.PORTAL_CLOSE:  s = _sfx_portal_close()
                SoundType.WEAPON_PICKUP: s = _sfx_weapon_pickup()
                SoundType.ENEMY_EXPLODE: s = _sfx_enemy_explode()
                SoundType.BLOOD_SPLAT:   s = _sfx_blood_splat()
                SoundType.MINE_BOUNCE:   s = _sfx_mine_bounce()
                SoundType.POTION_DRINK:  s = _sfx_potion_drink()
                SoundType.LIGHTNING:     s = _sfx_lightning()
                SoundType.SCEPTER_PICKUP:s = _sfx_scepter_pickup()
                SoundType.POTION_GULP:   s = _sfx_potion_gulp()
                SoundType.DARK_LAUGH:    s = _sfx_dark_laugh()
                SoundType.STAMINA_CLICK: s = _sfx_stamina_click()
                SoundType.HAMMER_THROW:   s = _sfx_hammer_throw()
                SoundType.HAMMER_CLANK:   s = _sfx_hammer_clank()
                SoundType.WALL_CRUMBLE:   s = _sfx_wall_crumble()
                SoundType.SOUL_RELEASE:   s = _sfx_soul_release()
                SoundType.SOUL_ABSORB:    s = _sfx_soul_absorb()
                SoundType.RELIC_PICKUP:   s = _sfx_relic_pickup()
                SoundType.RELIC_BREAK:    s = _sfx_relic_break()
                SoundType.MELEE_SWING:    s = _sfx_melee_swing()
                SoundType.REFLECT_BOLT:   s = _sfx_reflect_bolt()
                SoundType.HAZARD_SNAP:     s = _sfx_hazard_snap()
                SoundType.HAZARD_DISARM:   s = _sfx_hazard_disarm()
                SoundType.HAZARD_RUMBLE:   s = _sfx_hazard_rumble()
                SoundType.HAZARD_COLLAPSE: s = _sfx_hazard_collapse()
                SoundType.HAZARD_GRIND:    s = _sfx_hazard_grind()
                SoundType.HAZARD_THUD:     s = _sfx_hazard_thud()
                SoundType.BARREL_EXPLODE:  s = _sfx_barrel_explode()
                SoundType.BAT_SCREECH:     s = _sfx_bat_screech()
                SoundType.BAT_FLAP:        s = _sfx_bat_flap()
                SoundType.SCROLL_LIGHTNING: s = _sfx_scroll_lightning()
                SoundType.SIEGE_FIRE:      s = _sfx_siege_fire()
                SoundType.BARREL_TOSS:     s = _sfx_barrel_toss()
                SoundType.PILLAR_CRACK:    s = _sfx_pillar_crack()
                SoundType.PILLAR_COLLAPSE: s = _sfx_pillar_collapse()
                SoundType.WEAKNESS_HIT:    s = _sfx_weakness_hit()
                SoundType.BURST_FROST:     s = _sfx_burst_frost()
                SoundType.BURST_LIGHTNING: s = _sfx_burst_lightning()
                SoundType.BURST_POISON:    s = _sfx_burst_poison()
                SoundType.FREEZE_RAY:      s = _sfx_freeze_ray()
                SoundType.FREEZE_HIT:      s = _sfx_freeze_hit()
                SoundType.PLAYER_SUFFER:   s = _sfx_player_suffer()
                _:
                        s = PackedFloat32Array()
        return _samples_to_stream(s)


# --- 0.08s noise burst + 80Hz pulse, fast decay -----------------------------
func _sfx_pistol() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.08)
        for i in n:
                var t: float = float(i) / SR
                var env: float = exp(-t * 35.0)
                var v: float = 0.5 * noise_gen() + 0.5 * pulse_wave(t * 80.0, 0.5)
                s.append(2500.0 / 32767.0 * v * env)
        return s


# --- 0.15s more noise + 60Hz, medium decay ----------------------------------
func _sfx_shotgun() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.15)
        for i in n:
                var t: float = float(i) / SR
                var env: float = exp(-t * 20.0)
                var v: float = 0.7 * noise_gen() + 0.3 * pulse_wave(t * 60.0, 0.5)
                s.append(2500.0 / 32767.0 * v * env)
        return s


# --- 0.25s rumble: 40Hz pulse (duty 0.3) + noise -----------------------------
func _sfx_rocket() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.25)
        for i in n:
                var t: float = float(i) / SR
                var env: float = exp(-t * 12.0)
                var v: float = 0.4 * noise_gen() + 0.6 * pulse_wave(t * 40.0, 0.3)
                s.append(2200.0 / 32767.0 * v * env)
        return s


# --- 0.15s descending frequency sweep (1200 -> 200 Hz) ----------------------
func _sfx_laser() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.15)
        for i in n:
                var t: float = float(i) / SR
                var freq: float = max(200.0, 1200.0 - t * 4000.0)
                var env: float = exp(-t * 15.0)
                var v: float = pulse_wave(t * freq, 0.25)
                s.append(2000.0 / 32767.0 * v * env)
        return s


# --- Arpeggio Do-Mi-Sol-Do, 4 ascending notes -------------------------------
func _sfx_treasure() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var notes := [523, 659, 784, 1047]
        for note in notes:
                var seg: int = int(SR * 0.06)
                for i in seg:
                        var t: float = float(i) / SR
                        var env: float = exp(-t * 20.0)
                        var v: float = 0.6 * pulse_wave(t * note, 0.5) + 0.4 * triangle_wave(t * note)
                        s.append(2200.0 / 32767.0 * v * env)
        return s


# --- 0.5s enemy death: shriek + noise + bass dissolve -----------------------
func _sfx_enemy_death() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.5)
        for i in n:
                var t: float = float(i) / SR
                var env: float = exp(-t * 5.0)
                var v: float = 0.0
                if t < 0.15:
                        var freq: float = 600.0 * exp(-t * 12.0) + 100.0
                        v = 0.5 * pulse_wave(t * freq, 0.25)
                elif t < 0.3:
                        v = 0.6 * noise_gen()
                else:
                        var freq: float = 150.0 * exp(-(t - 0.3) * 8.0) + 40.0
                        v = 0.4 * triangle_wave(t * freq)
                s.append(2500.0 / 32767.0 * v * env)
        return s


# --- 0.5s descending square wave (classic NES "lose life") -------------------
func _sfx_lose_life() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.5)
        for i in n:
                var t: float = float(i) / SR
                var freq: float = max(60.0, 300.0 - t * 400.0)
                var env: float = exp(-t * 4.0)
                var v: float = pulse_wave(t * freq, 0.5)
                s.append(2500.0 / 32767.0 * v * env)
        return s


# --- TASK 87: gemito di sofferenza del player (~0.85s) -----------------------
# Il player finisce l'energia e si accascia: prima un urletto discendente
# (185->110 Hz, sawtooth con vibrato ~5.5 Hz), poi un gemito grave che
# si spegne (95->65 Hz, pulse largo con wobble) con un soffio di respiro
# (rumore) di sottofondo. Timbro "umano sofferente" retro-arcade.
func _sfx_player_suffer() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.85)
        var cry_s: float = 0.28          # durata fase 1 (urletto)
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                var env: float = 0.0
                if t < cry_s:
                        # fase 1: urletto discendente con vibrato
                        var k: float = t / cry_s
                        var freq: float = 185.0 - 75.0 * k
                        var vib: float = 1.0 + 0.035 * sin(TAU * 5.5 * t)
                        v = sawtooth_wave(t * freq * vib) * 0.6 \
                                        + pulse_wave(t * freq * vib * 0.5, 0.5) * 0.4
                        env = 0.55 + 0.45 * k
                else:
                        # fase 2: gemito grave morente con wobble + respiro
                        var k2: float = (t - cry_s) / (0.85 - cry_s)
                        var freq2: float = 95.0 - 30.0 * k2
                        var wob: float = 1.0 + 0.05 * sin(TAU * 3.5 * t)
                        v = pulse_wave(t * freq2 * wob, 0.62) * 0.7 \
                                        + sawtooth_wave(t * freq2 * wob * 2.0) * 0.3
                        env = exp(-(t - cry_s) * 3.0) * 0.8
                        v += noise_gen() * 0.12
                s.append(2400.0 / 32767.0 * _soft_clip(v * env * 1.2))
        return s


# --- 5-note ascending victory fanfare ---------------------------------------
func _sfx_win() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var notes := [523, 659, 784, 1047, 1319]
        for note in notes:
                var seg: int = int(SR * 0.1)
                for i in seg:
                        var t: float = float(i) / SR
                        var env: float = exp(-t * 6.0)
                        var v: float = 0.5 * pulse_wave(t * note, 0.5) + 0.5 * triangle_wave(t * note * 2.0)
                        s.append(2200.0 / 32767.0 * v * env)
        return s


# --- 0.1s metallic clank (two high freqs + noise) ---------------------------
func _sfx_boss_hit() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.1)
        for i in n:
                var t: float = float(i) / SR
                var env: float = exp(-t * 25.0)
                var v: float = 0.3 * pulse_wave(t * 800.0, 0.5) \
                        + 0.3 * pulse_wave(t * 1100.0, 0.25) \
                        + 0.4 * noise_gen()
                s.append(2000.0 / 32767.0 * v * env)
        return s


# --- 1.5s long explosion (noise + descending bass) --------------------------
func _sfx_boss_death() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 1.5)
        for i in n:
                var t: float = float(i) / SR
                var env: float = exp(-t * 2.0)
                var freq: float = 100.0 * exp(-t * 1.5) + 30.0
                var v: float = 0.5 * noise_gen() + 0.5 * pulse_wave(t * freq, 0.3)
                s.append(2800.0 / 32767.0 * v * env)
        return s


# --- "BOING" spring bounce (0.25s): 600 -> 200 -> 500 -> 250 Hz --------------
# Mirror of SOUND_JUMP in AudioManager.cpp. The frequency first compresses
# (drops to 200 Hz), then bounces back up (500 Hz) and decays (250 Hz),
# imitating a metal spring being compressed and released.
func _sfx_jump() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.25)
        for i in n:
                var t: float = float(i) / SR
                var phase: float = t / 0.25  # 0..1 over the duration
                var freq: float
                if phase < 0.3:
                        # Compression: 600 -> 200 Hz
                        freq = 600.0 - (phase / 0.3) * 400.0
                elif phase < 0.5:
                        # Bounce up: 200 -> 500 Hz
                        freq = 200.0 + ((phase - 0.3) / 0.2) * 300.0
                else:
                        # Decay: 500 -> 250 Hz
                        freq = 500.0 - ((phase - 0.5) / 0.5) * 250.0
                # Quick attack, soft decay
                var env: float = exp(-t * 6.0) * (1.0 - exp(-t * 30.0))
                # Sawtooth + triangle for a metallic "spring" timbre
                var v: float = 0.6 * sawtooth_wave(t * freq) + 0.4 * triangle_wave(t * freq * 1.5)
                s.append(3000.0 / 32767.0 * v * env)
        return s


# --- 0.4s door creak (low pulse + vibrato + noise) --------------------------
func _sfx_door_open() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.4)
        for i in n:
                var t: float = float(i) / SR
                var freq: float = 60.0 + 20.0 * sin(t * 30.0)
                var env: float = exp(-t * 3.0) * (1.0 - exp(-t * 20.0))
                var v: float = pulse_wave(t * freq, 0.3) + 0.3 * noise_gen()
                s.append(1800.0 / 32767.0 * v * env)
        return s


# --- 0.2s trap snap (noise + 1500Hz click) -----------------------------------
func _sfx_trap() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.2)
        for i in n:
                var t: float = float(i) / SR
                var env: float = exp(-t * 15.0)
                var v: float = 0.6 * noise_gen() + 0.4 * pulse_wave(t * 1500.0, 0.1)
                s.append(2500.0 / 32767.0 * v * env)
        return s


# --- 0.05s short cursor blip (La5 = 880 Hz) ---------------------------------
func _sfx_menu_select() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.05)
        for i in n:
                var t: float = float(i) / SR
                var env: float = exp(-t * 40.0)
                var v: float = pulse_wave(t * 880.0, 0.5)
                s.append(2000.0 / 32767.0 * v * env)
        return s


# --- 0.15s two-tone confirm (La5 -> Mi6) ------------------------------------
func _sfx_menu_confirm() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var notes := [880, 1319]
        for note in notes:
                var seg: int = int(SR * 0.07)
                for i in seg:
                        var t: float = float(i) / SR
                        var env: float = exp(-t * 15.0)
                        var v: float = pulse_wave(t * note, 0.5)
                        s.append(2200.0 / 32767.0 * v * env)
        return s


# --- 0.8s ascending portal fanfare (Do-Mi-Sol-Do-Mi-Sol) + reverb tail ------
func _sfx_portal_open() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var notes := [262, 330, 392, 523, 659, 784]
        for note in notes:
                var seg: int = int(SR * 0.1)
                for i in seg:
                        var t: float = float(i) / SR
                        var env: float = exp(-t * 8.0) * (1.0 - exp(-t * 30.0))
                        var v: float = 0.4 * pulse_wave(t * note, 0.5) \
                                + 0.3 * triangle_wave(t * note * 2.0) \
                                + 0.3 * sawtooth_wave(t * note * 0.5)
                        s.append(2500.0 / 32767.0 * v * env)
        # Reverb tail
        var tail: int = int(SR * 0.2)
        for i in tail:
                var t: float = float(i) / SR
                var env: float = exp(-t * 5.0)
                var v: float = 0.3 * triangle_wave(t * 784.0) + 0.2 * noise_gen()
                s.append(1500.0 / 32767.0 * v * env)
        return s


# --- 0.6s descending portal close + final impact ----------------------------
func _sfx_portal_close() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.6)
        for i in n:
                var t: float = float(i) / SR
                var freq: float = 600.0 * exp(-t * 4.0) + 80.0
                var env: float = exp(-t * 3.0)
                var v: float = 0.4 * pulse_wave(t * freq, 0.3) \
                        + 0.3 * triangle_wave(t * freq * 0.5) \
                        + 0.3 * noise_gen()
                s.append(2200.0 / 32767.0 * v * env)
        # Final impact
        var imp: int = int(SR * 0.1)
        for i in imp:
                var t: float = float(i) / SR
                var env: float = exp(-t * 20.0)
                var v: float = 0.6 * noise_gen() + 0.4 * pulse_wave(t * 50.0, 0.5)
                s.append(3000.0 / 32767.0 * v * env)
        return s


# --- Weapon pickup: click-click-clack + low thud (loading a rifle) ----------
func _sfx_weapon_pickup() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Phase 1: dry click
        var p1: int = int(SR * 0.05)
        for i in p1:
                var t: float = float(i) / SR
                var env: float = exp(-t * 50.0)
                var v: float = 0.6 * noise_gen() + 0.4 * pulse_wave(t * 2000.0, 0.1)
                s.append(2500.0 / 32767.0 * v * env)
        # Silence
        for i in int(SR * 0.05): s.append(0.0)
        # Phase 2: second click
        for i in p1:
                var t: float = float(i) / SR
                var env: float = exp(-t * 50.0)
                var v: float = 0.5 * noise_gen() + 0.5 * pulse_wave(t * 1500.0, 0.1)
                s.append(2200.0 / 32767.0 * v * env)
        for i in int(SR * 0.05): s.append(0.0)
        # Phase 3: mechanical slide (sweep down)
        var p3: int = int(SR * 0.15)
        for i in p3:
                var t: float = float(i) / SR
                var freq: float = max(80.0, 300.0 - t * 800.0)
                var env: float = exp(-t * 12.0) * (1.0 - exp(-t * 30.0))
                var v: float = 0.4 * pulse_wave(t * freq, 0.3) \
                        + 0.3 * sawtooth_wave(t * freq * 0.5) \
                        + 0.3 * noise_gen()
                s.append(2500.0 / 32767.0 * v * env)
        # Phase 4: closing click
        var p4: int = int(SR * 0.05)
        for i in p4:
                var t: float = float(i) / SR
                var env: float = exp(-t * 40.0)
                var v: float = 0.7 * noise_gen() + 0.3 * pulse_wave(t * 1800.0, 0.1)
                s.append(2800.0 / 32767.0 * v * env)
        # Phase 5: low confirmation thud
        var p5: int = int(SR * 0.1)
        for i in p5:
                var t: float = float(i) / SR
                var env: float = exp(-t * 15.0)
                var v: float = 0.5 * triangle_wave(t * 100.0) + 0.3 * pulse_wave(t * 50.0, 0.5)
                s.append(2000.0 / 32767.0 * v * env)
        return s


# --- 0.4s explosion (noise + descending bass + debris) ----------------------
func _sfx_enemy_explode() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.4)
        for i in n:
                var t: float = float(i) / SR
                var env: float = exp(-t * 6.0)
                var freq: float = 120.0 * exp(-t * 5.0) + 30.0
                var v: float = 0.5 * noise_gen() \
                        + 0.3 * pulse_wave(t * freq, 0.3) \
                        + 0.2 * sawtooth_wave(t * freq * 2.0)
                s.append(2800.0 / 32767.0 * v * env)
        return s


# --- 0.5s blood splat: impact + liquid splash + drops + pool ----------------
func _sfx_blood_splat() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Phase 1: fleshy impact (0.05s)
        var p1: int = int(SR * 0.05)
        for i in p1:
                var t: float = float(i) / SR
                var env: float = exp(-t * 30.0)
                var v: float = 0.6 * noise_gen() + 0.4 * triangle_wave(t * 60.0)
                s.append(3000.0 / 32767.0 * v * env)
        # Phase 2: liquid splash (0.15s, modulated)
        var p2: int = int(SR * 0.15)
        for i in p2:
                var t: float = float(i) / SR
                var freq: float = 400.0 * exp(-t * 6.0) + 50.0
                var env: float = exp(-t * 8.0) * (1.0 - exp(-t * 50.0))
                var mod_: float = 1.0 + 0.4 * sin(t * 40.0)
                var v: float = 0.4 * sawtooth_wave(t * freq * mod_) \
                        + 0.3 * noise_gen() * exp(-t * 10.0) \
                        + 0.3 * triangle_wave(t * freq * 0.3)
                s.append(2800.0 / 32767.0 * v * env)
        # Phase 3: 3 drops descending
        for g in 3:
                var freq: float = 200.0 - g * 50.0
                var seg: int = int(SR * 0.03)
                for i in seg:
                        var t: float = float(i) / SR
                        var env: float = exp(-t * 40.0)
                        var v: float = 0.5 * triangle_wave(t * freq) + 0.3 * noise_gen() * exp(-t * 60.0)
                        s.append(1800.0 / 32767.0 * v * env)
                # Brief silence
                for i in int(SR * 0.015): s.append(0.0)
        # Phase 4: low fade (pool forming)
        var p4: int = int(SR * 0.05)
        for i in p4:
                var t: float = float(i) / SR
                var env: float = exp(-t * 15.0)
                var v: float = 0.4 * triangle_wave(t * 40.0) + 0.2 * noise_gen()
                s.append(1500.0 / 32767.0 * v * env)
        return s


# --- 0.12s metallic bounce (descending sweep + noise) ----------------------
func _sfx_mine_bounce() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.12)
        for i in n:
                var t: float = float(i) / SR
                var freq: float = 800.0 * exp(-t * 8.0) + 200.0
                var env: float = exp(-t * 18.0) * (1.0 - exp(-t * 50.0))
                var v: float = 0.5 * pulse_wave(t * freq, 0.3) \
                        + 0.3 * triangle_wave(t * freq * 1.5) \
                        + 0.2 * noise_gen()
                s.append(2200.0 / 32767.0 * v * env)
        return s


# --- 0.7s glug-glug-glug (drinking potion) ----------------------------------
func _sfx_potion_drink() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        for gulp in 3:
                var freq: float = 120.0 + gulp * 40.0
                var seg: int = int(SR * 0.12)
                for i in seg:
                        var t: float = float(i) / SR
                        var env: float = exp(-t * 10.0) * (1.0 - exp(-t * 40.0))
                        var mod_: float = 1.0 + 0.3 * sin(t * 30.0)
                        var v: float = 0.4 * triangle_wave(t * freq * mod_) \
                                + 0.3 * sawtooth_wave(t * freq * 0.7 * mod_) \
                                + 0.2 * noise_gen() * exp(-t * 15.0)
                        s.append(2200.0 / 32767.0 * v * env)
                # Silence between gulps
                for i in int(SR * 0.06): s.append(0.0)
        # Final swallow
        var fin: int = int(SR * 0.1)
        for i in fin:
                var t: float = float(i) / SR
                var env: float = exp(-t * 15.0)
                var v: float = 0.5 * triangle_wave(t * 90.0) + 0.3 * pulse_wave(t * 60.0, 0.5)
                s.append(1800.0 / 32767.0 * v * env)
        return s


# --- 0.4s lightning: crack + electric sweep + boom + thunder ----------------
func _sfx_lightning() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Phase 1: crack (0.02s)
        var p1: int = int(SR * 0.02)
        for i in p1:
                var t: float = float(i) / SR
                var env: float = exp(-t * 80.0)
                var v: float = noise_gen()
                s.append(3200.0 / 32767.0 * v * env)
        # Phase 2: electric sweep (0.1s)
        var p2: int = int(SR * 0.1)
        for i in p2:
                var t: float = float(i) / SR
                var freq: float = 3000.0 * exp(-t * 15.0) + 200.0
                var env: float = exp(-t * 12.0)
                var v: float = 0.4 * pulse_wave(t * freq, 0.1) \
                        + 0.3 * noise_gen() * exp(-t * 10.0) \
                        + 0.3 * sawtooth_wave(t * freq * 0.3)
                s.append(2800.0 / 32767.0 * v * env)
        # Phase 3: boom (0.15s)
        var p3: int = int(SR * 0.15)
        for i in p3:
                var t: float = float(i) / SR
                var freq: float = 100.0 * exp(-t * 5.0) + 30.0
                var env: float = exp(-t * 6.0)
                var v: float = 0.5 * triangle_wave(t * freq) \
                        + 0.3 * pulse_wave(t * freq, 0.3) \
                        + 0.2 * noise_gen()
                s.append(2500.0 / 32767.0 * v * env)
        # Phase 4: dying thunder (0.13s)
        var p4: int = int(SR * 0.13)
        for i in p4:
                var t: float = float(i) / SR
                var env: float = exp(-t * 8.0)
                var v: float = 0.4 * noise_gen() * (1.0 - t / 0.13) + 0.2 * triangle_wave(t * 50.0)
                s.append(1800.0 / 32767.0 * v * env)
        return s


# --- TASK 36 — ~1.9s FULMINE della pergamena (apparizione piu' evidente):
# --- carica elettrica discendente + crack della saetta + sweep elettrico +
# --- boom dell'impatto al suolo + lunga coda di tuono rotolante. ------------
# --- Molto piu' lungo del LIGHTNING (0.4s) e del PORTAL_OPEN usati prima. ----
func _sfx_scroll_lightning() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Phase 1: carica elettrica discendente (0.30s) — sfrigolio che
        # scende di tonalita' e cresce di volume (il cielo si carica)
        var c1: int = int(SR * 0.30)
        for i in c1:
                var t: float = float(i) / SR
                var k: float = t / 0.30
                var env: float = 0.15 + 0.85 * k * k
                var freq: float = 2400.0 * exp(-t * 6.0) + 500.0
                var v: float = 0.45 * pulse_wave(t * freq, 0.08) \
                                + 0.55 * noise_gen() * (0.4 + 0.6 * k)
                s.append(1500.0 / 32767.0 * v * env)
        # Phase 2: crack della saetta (0.05s) — schiocco secco fortissimo
        var c2: int = int(SR * 0.05)
        for i in c2:
                var t: float = float(i) / SR
                var env: float = exp(-t * 90.0)
                var v: float = noise_gen()
                s.append(3400.0 / 32767.0 * v * env)
        # Phase 3: sweep elettrico (0.18s) — la scarica attraversa l'aria
        var c3: int = int(SR * 0.18)
        for i in c3:
                var t: float = float(i) / SR
                var freq: float = 3200.0 * exp(-t * 16.0) + 180.0
                var env: float = exp(-t * 10.0)
                var v: float = 0.4 * pulse_wave(t * freq, 0.1) \
                                + 0.3 * noise_gen() * exp(-t * 9.0) \
                                + 0.3 * sawtooth_wave(t * freq * 0.3)
                s.append(3000.0 / 32767.0 * v * env)
        # Phase 4: boom dell'impatto al suolo (0.42s) — profondo e pieno
        var c4: int = int(SR * 0.42)
        for i in c4:
                var t: float = float(i) / SR
                var freq: float = 85.0 * exp(-t * 4.5) + 26.0
                var env: float = exp(-t * 5.0)
                var v: float = 0.55 * triangle_wave(t * freq) \
                                + 0.25 * pulse_wave(t * freq, 0.3) \
                                + 0.20 * noise_gen() * exp(-t * 7.0)
                s.append(2600.0 / 32767.0 * v * env)
        # Phase 5: tuono rotolante (0.95s) — coda lunga che sfuma, con
        # ondulazioni lente (il boato "rotola" via)
        var c5: int = int(SR * 0.95)
        for i in c5:
                var t: float = float(i) / SR
                var env: float = exp(-t * 2.6)
                var roll: float = 0.60 + 0.40 * sin(t * TAU * 2.5 \
                                + 1.3 * sin(t * TAU * 0.9))
                var v: float = noise_gen() * roll \
                                + 0.18 * triangle_wave(t * 47.0) \
                                + 0.12 * triangle_wave(t * 31.0)
                s.append(2200.0 / 32767.0 * v * env)
        return s


# ============================================================================
# TASK 39 — L'ARENA DEL BOSS: generatori dei nuovi SFX
# ============================================================================

# --- SIEGE_FIRE (~0.6s): miccia che sibila, BOTTA profonda della carica
# (55->28Hz) con blast di polvere, coda metallica della canna che vibra.
func _sfx_siege_fire() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Phase 1: sibilo della miccia (0.10s)
        var c1: int = int(SR * 0.10)
        for i in c1:
                var t: float = float(i) / SR
                var env: float = 0.25 + 0.75 * (t / 0.10)
                var v: float = noise_gen() * 0.7 + 0.3 * pulse_wave(t * 1900.0, 0.12)
                s.append(1600.0 / 32767.0 * v * env)
        # Phase 2: botta della carica (0.28s) — corpo grave + blast
        var c2: int = int(SR * 0.28)
        for i in c2:
                var t: float = float(i) / SR
                var freq: float = 55.0 * exp(-t * 5.0) + 28.0
                var env: float = exp(-t * 6.5)
                var v: float = 0.55 * triangle_wave(t * freq) \
                                + 0.20 * pulse_wave(t * freq * 0.5, 0.3) \
                                + 0.25 * noise_gen() * exp(-t * 10.0)
                s.append(3200.0 / 32767.0 * v * env)
        # Phase 3: canna che vibra (0.22s) — risonanza metallica discendente
        var c3: int = int(SR * 0.22)
        for i in c3:
                var t: float = float(i) / SR
                var env: float = exp(-t * 8.0)
                var freq: float = 420.0 * exp(-t * 3.0) + 130.0
                var v: float = 0.4 * triangle_wave(t * freq) \
                                + 0.25 * pulse_wave(t * freq * 1.5, 0.2) \
                                + 0.12 * noise_gen() * exp(-t * 12.0)
                s.append(1400.0 / 32767.0 * v * env)
        return s


# --- BARREL_TOSS (~0.3s): whoosh grave di oggetto pesante che rotea —
# rumble basso con aperture aerodinamiche (il barile "passa" vicino).
func _sfx_barrel_toss() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.30)
        for i in n:
                var t: float = float(i) / SR
                var k: float = t / 0.30
                var env: float = sin(PI * k)  # soffio a_monta_e_sfuma
                # rotazione del barile: 3 "passaggi" d'aria
                var spin: float = 0.55 + 0.45 * sin(t * TAU * 21.0)
                var freq: float = 130.0 + 60.0 * k
                var v: float = 0.45 * noise_gen() * spin \
                                + 0.35 * triangle_wave(t * freq) \
                                + 0.20 * sawtooth_wave(t * freq * 0.5)
                s.append(2100.0 / 32767.0 * _soft_clip(v * env))
        return s


# --- PILLAR_CRACK (~0.35s): schiocco secco della pietra che fessura +
# trickle di detriti che cadono.
func _sfx_pillar_crack() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Schiocco principale (0.08s)
        var c1: int = int(SR * 0.08)
        for i in c1:
                var t: float = float(i) / SR
                var env: float = exp(-t * 55.0)
                var v: float = 0.6 * noise_gen() + 0.4 * pulse_wave(t * 240.0, 0.2)
                s.append(3000.0 / 32767.0 * v * env)
        # Crepa che corre (0.12s) — click nervosi in sequenza
        var c2: int = int(SR * 0.12)
        for i in c2:
                var t: float = float(i) / SR
                var env: float = exp(-t * 14.0)
                var crack: float = 0.5 + 0.5 * sin(t * TAU * 46.0)
                var v: float = noise_gen() * crack
                s.append(1700.0 / 32767.0 * v * env)
        # Trickle di detriti (0.15s) — sassolini che rimbalzano
        var c3: int = int(SR * 0.15)
        for i in c3:
                var t: float = float(i) / SR
                var env: float = exp(-t * 9.0)
                var peb: float = 0.0
                if int(i % int(SR * 0.017)) < 90:
                        peb = noise_gen() * (1.0 - t / 0.15)
                var v: float = 0.8 * peb + 0.2 * noise_gen() * 0.3
                s.append(1200.0 / 32767.0 * v * env)
        return s


# --- PILLAR_COLLAPSE (~1.1s): scricchiolio di congedo, frana di pietra
# (impatti multipli che si accavallano) e tonfo finale nella polvere.
func _sfx_pillar_collapse() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Phase 1: scricchiolio (0.14s) — la pietra cede
        var c1: int = int(SR * 0.14)
        for i in c1:
                var t: float = float(i) / SR
                var env: float = 0.3 + 0.7 * (t / 0.14)
                var v: float = 0.5 * noise_gen() + 0.5 * sawtooth_wave(t * 90.0)
                s.append(1500.0 / 32767.0 * v * env)
        # Phase 2: frana (0.55s) — blocchi che si spezzano e cadono
        var c2: int = int(SR * 0.55)
        for i in c2:
                var t: float = float(i) / SR
                var env: float = exp(-t * 2.2)
                # impatti irregolari (il blocco si frantuma a gradini)
                var impacts: float = 0.55 + 0.45 * sin(t * TAU * 13.0 \
                                + 1.7 * sin(t * TAU * 4.3))
                var freq: float = 95.0 * exp(-t * 1.5) + 45.0
                var v: float = 0.45 * noise_gen() * impacts \
                                + 0.35 * triangle_wave(t * freq) \
                                + 0.20 * pulse_wave(t * freq * 2.0, 0.25)
                s.append(2800.0 / 32767.0 * _soft_clip(v * env))
        # Phase 3: tonfo finale + polvere (0.41s)
        var c3: int = int(SR * 0.41)
        for i in c3:
                var t: float = float(i) / SR
                var freq: float = 60.0 * exp(-t * 6.0) + 24.0
                var env: float = exp(-t * 4.5)
                var v: float = 0.55 * triangle_wave(t * freq) \
                                + 0.20 * pulse_wave(t * freq * 0.5, 0.3) \
                                + 0.25 * noise_gen() * exp(-t * 5.5)
                s.append(2400.0 / 32767.0 * _soft_clip(v * env))
        return s


# --- WEAKNESS_HIT (~0.7s): colpo CRITICO elementale — campana luminosa
# ascendente (Do#-Sol-Sol#-Do# alto) su scintillio: la ricompensa sonora
# della lettura giusta della debolezza del boss.
func _sfx_weakness_hit() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Impatto iniziale brillante (0.06s)
        var c0: int = int(SR * 0.06)
        for i in c0:
                var t: float = float(i) / SR
                var env: float = exp(-t * 40.0)
                var v: float = 0.5 * noise_gen() + 0.5 * triangle_wave(t * 1600.0)
                s.append(2200.0 / 32767.0 * v * env)
        # Arpeggio campanellante (4 note, ~0.64s)
        var notes := [1385.91, 2076.52, 2200.00, 2771.83]  # Do#6 Sol6 Sol#6 Do#7
        var seg: float = 0.155
        for k in notes.size():
                var start: float = 0.05 + float(k) * seg * 0.62
                var len: float = 0.40
                var i0: int = int(SR * start)
                var n: int = int(SR * len)
                for i in n:
                        var idx: int = i0 + i
                        if idx >= int(SR * 0.70):
                                break
                        while s.size() <= idx:
                                s.append(0.0)
                        var t: float = float(i) / SR
                        var env: float = exp(-t * 7.0)
                        var f: float = notes[k]
                        var v: float = 0.50 * sine_wave(t * f) \
                                        + 0.28 * sine_wave(t * f * 2.004) \
                                        + 0.14 * sine_wave(t * f * 3.01)
                        # shimmer di battimento sulle note alte
                        if k >= 2:
                                v += 0.10 * sine_wave(t * (f * 1.5)) \
                                                * sin(t * TAU * 9.0)
                        s[idx] += 2600.0 / 32767.0 * _soft_clip(v * env)
        return s


# --- BURST_FROST (~0.6s): vetro gelato che esplode — frantumazione acuta
# con ping cristallini discendenti e soffio ghiacciato.
func _sfx_burst_frost() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Shatter iniziale (0.10s)
        var c1: int = int(SR * 0.10)
        for i in c1:
                var t: float = float(i) / SR
                var env: float = exp(-t * 28.0)
                var v: float = noise_gen() * 0.8 + 0.2 * pulse_wave(t * 2600.0, 0.15)
                s.append(2900.0 / 32767.0 * v * env)
        # Ping cristallini (0.28s) — schegge di ghiaccio che tintinnano
        var c2: int = int(SR * 0.28)
        for i in c2:
                var t: float = float(i) / SR
                var env: float = exp(-t * 6.0)
                var ping: float = 0.0
                # 5 ping a intervalli irregolari, frequenza discendente
                for k in 5:
                        var tk: float = 0.012 + float(k) * 0.048 \
                                        + 0.01 * sin(float(k) * 2.3)
                        var dt: float = t - tk
                        if dt >= 0.0:
                                var fk: float = 3100.0 - float(k) * 380.0
                                ping += 0.22 * sine_wave(dt * fk) * exp(-dt * 26.0)
                var v: float = ping + 0.18 * noise_gen() * exp(-t * 8.0)
                s.append(2000.0 / 32767.0 * _soft_clip(v * env))
        # Soffio ghiacciato (0.22s)
        var c3: int = int(SR * 0.22)
        for i in c3:
                var t: float = float(i) / SR
                var env: float = (1.0 - exp(-t * 14.0)) * exp(-t * 7.0)
                var v: float = 0.55 * noise_gen() + 0.25 * sine_wave(t * 210.0)
                s.append(1500.0 / 32767.0 * v * env)
        return s


# --- BURST_LIGHTNING (~0.5s): scarica elettrica — zap ad alta frequenza
# con scariche secondarie e sfregamento finale dell'aria ionizzata.
func _sfx_burst_lightning() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Zap principale (0.12s) — scarica nervosa
        var c1: int = int(SR * 0.12)
        for i in c1:
                var t: float = float(i) / SR
                var env: float = exp(-t * 18.0)
                var freq: float = 2800.0 * exp(-t * 14.0) + 300.0
                var v: float = 0.5 * pulse_wave(t * freq, 0.08) \
                                + 0.5 * noise_gen() * (0.5 + 0.5 * sin(t * TAU * 160.0))
                s.append(3000.0 / 32767.0 * _soft_clip(v * env))
        # Scariche secondarie (0.24s) — archetti erratici
        var c2: int = int(SR * 0.24)
        for i in c2:
                var t: float = float(i) / SR
                var env: float = exp(-t * 7.0)
                var arc: float = 0.0
                if fmod(t, 0.031) < 0.011:
                        var f2: float = 1900.0 + 900.0 * sin(t * TAU * 37.0)
                        arc = pulse_wave(t * f2, 0.10)
                var v: float = 0.55 * arc + 0.30 * noise_gen() \
                                + 0.15 * sawtooth_wave(t * 140.0)
                s.append(1900.0 / 32767.0 * v * env)
        # Aria ionizzata (0.14s) — crepitio che sfuma
        var c3: int = int(SR * 0.14)
        for i in c3:
                var t: float = float(i) / SR
                var env: float = exp(-t * 10.0)
                var v: float = noise_gen() * (0.4 + 0.6 * sin(t * TAU * 23.0))
                s.append(1100.0 / 32767.0 * v * env)
        return s


# --- BURST_POISON (~0.7s): fiala corrosiva — sibilo di gas sotto pressione,
# gorgoglii ripugnanti e nebbia acida che si deposita.
func _sfx_burst_poison() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Rottura del contenitore (0.06s)
        var c1: int = int(SR * 0.06)
        for i in c1:
                var t: float = float(i) / SR
                var env: float = exp(-t * 60.0)
                var v: float = noise_gen()
                s.append(2200.0 / 32767.0 * v * env)
        # Sibilo del gas (0.30s) — pressione che si scarica
        var c2: int = int(SR * 0.30)
        for i in c2:
                var t: float = float(i) / SR
                var env: float = (1.0 - exp(-t * 30.0)) * exp(-t * 5.0)
                var hiss: float = 0.65 + 0.35 * sin(t * TAU * 31.0 \
                                + 0.8 * sin(t * TAU * 11.0))
                var v: float = 0.75 * noise_gen() * hiss \
                                + 0.25 * sine_wave(t * 340.0) * 0.5
                s.append(1700.0 / 32767.0 * _soft_clip(v * env))
        # Gorgoglii (0.34s) — bolle che scoppiano nel liquido
        var c3: int = int(SR * 0.34)
        for i in c3:
                var t: float = float(i) / SR
                var env: float = exp(-t * 4.0)
                var gurgle: float = 0.0
                for k in 4:
                        var tk: float = 0.03 + float(k) * 0.077
                        var dt: float = t - tk
                        if dt >= 0.0 and dt < 0.09:
                                var fb: float = 140.0 + float(k) * 55.0
                                gurgle += 0.45 * sine_wave(dt * fb \
                                                * (1.0 + 2.2 * dt / 0.09)) \
                                                * sin(PI * dt / 0.09)
                var v: float = gurgle + 0.22 * noise_gen() * exp(-t * 6.0)
                s.append(1600.0 / 32767.0 * _soft_clip(v * env))
        return s


# --- FREEZE_RAY (~0.5s) TASK 50: sparo del raggio congelante — sweep
# discendente cristallino (il freddo "cade"), soffio di brina e coda di
# ghiaccio che si solidifica.
func _sfx_freeze_ray() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Zap congelante discendente (0.14s): 2300 -> 750 Hz
        var c1: int = int(SR * 0.14)
        for i in c1:
                var t: float = float(i) / SR
                var env: float = exp(-t * 16.0)
                var f: float = 2300.0 - 1550.0 * (t / 0.14)
                var v: float = sine_wave(t * f) * 0.7 \
                                + 0.25 * pulse_wave(t * f * 2.0, 0.3)
                s.append(2400.0 / 32767.0 * _soft_clip(v * env))
        # Soffio di brina + shimmer cristallino (0.20s)
        var c2: int = int(SR * 0.20)
        for i in c2:
                var t: float = float(i) / SR
                var env: float = exp(-t * 9.0)
                var shimmer: float = 0.0
                # 4 ping di ghiaccio a scalare, sempre piu' gravi
                for k in 4:
                        var tk: float = 0.015 + float(k) * 0.042
                        var dt: float = t - tk
                        if dt >= 0.0:
                                var fk: float = 2900.0 - float(k) * 500.0
                                shimmer += 0.20 * sine_wave(dt * fk) * exp(-dt * 30.0)
                var v: float = shimmer + 0.30 * noise_gen() * exp(-t * 12.0)
                s.append(1900.0 / 32767.0 * _soft_clip(v * env))
        # Solidificazione (0.16s): tonfo freddo + micro-crepak del ghiaccio
        var c3: int = int(SR * 0.16)
        for i in c3:
                var t: float = float(i) / SR
                var env: float = (1.0 - exp(-t * 20.0)) * exp(-t * 10.0)
                var crackle: float = 0.0
                if int(i % int(SR * 0.031)) < 3:
                        crackle = noise_gen() * 0.5
                var v: float = 0.5 * sine_wave(t * 190.0) + crackle
                s.append(1500.0 / 32767.0 * _soft_clip(v * env))
        return s


# --- FREEZE_HIT (~0.55s) TASK 50b: COLPO del raggio congelante sul nemico —
# cristallizzazione istantanea del blocco di ghiaccio che lo ingloba:
# schiocco vetroso iniziale, crepitio di espansione con ping di cristalli
# che crescono verso l'alto e tonfo grave della solidificazione finale.
func _sfx_freeze_hit() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Schiocco vetroso (0.09s): crack secco ad alta frequenza, attacco
        # immediato (il freddo aggredisce la carne in un istante)
        var c1: int = int(SR * 0.09)
        for i in c1:
                var t: float = float(i) / SR
                var env: float = exp(-t * 26.0) * (1.0 - exp(-t * 90.0))
                var snap: float = 0.0
                if i < int(SR * 0.004):
                        snap = noise_gen() * 0.9
                var v: float = 0.55 * noise_gen() + snap \
                                + 0.20 * pulse_wave(t * 3400.0, 0.2)
                s.append(2600.0 / 32767.0 * _soft_clip(v * env))
        # Crescita dei cristalli (0.28s): crepitio che dirada + 5 ping
        # ascendenti sempre piu' acuti (il ghiaccio si espande)
        var c2: int = int(SR * 0.28)
        for i in c2:
                var t: float = float(i) / SR
                var env: float = exp(-t * 5.5)
                var shimmer: float = 0.0
                for k in 5:
                        var tk: float = 0.02 + float(k) * 0.045
                        var dt: float = t - tk
                        if dt >= 0.0:
                                var fk: float = 1500.0 + float(k) * 420.0
                                shimmer += 0.16 * sine_wave(dt * fk) * exp(-dt * 22.0)
                # crepitio: impulsi sparsi la cui densita' cala nel tempo
                var rate: float = 900.0 * exp(-t * 8.0) + 90.0
                if int(t * rate) != int((t - 1.0 / SR) * rate) and t > 0.0:
                        shimmer += 0.30 * noise_gen()
                var v: float = shimmer + 0.16 * noise_gen() * exp(-t * 9.0)
                s.append(2200.0 / 32767.0 * _soft_clip(v * env))
        # Tonfo della solidificazione (0.18s): battuta grave + ultima
        # scintilla di brina che si spegne
        var c3: int = int(SR * 0.18)
        for i in c3:
                var t: float = float(i) / SR
                var env: float = (1.0 - exp(-t * 26.0)) * exp(-t * 11.0)
                var v: float = 0.55 * sine_wave(t * 150.0) \
                                + 0.25 * sine_wave(t * 300.0) \
                                + 0.12 * noise_gen() * exp(-t * 14.0)
                s.append(1700.0 / 32767.0 * _soft_clip(v * env))
        return s


# --- ~1.7s "oh-oh-oh" magic scepter pickup (suspense) -----------------------
# Three descending "oh" exclamations (G4 -> F4 -> Eb4) over a tritone pad
# (C3 + F#3) and a magical shimmer layer. Mirror of SOUND_SCEPTER_PICKUP.
func _sfx_scepter_pickup() -> PackedFloat32Array:
        var total: int = int(SR * 1.7)
        var pad := PackedFloat32Array()
        pad.resize(total)
        for i in total:
                var t: float = float(i) / SR
                var env: float = (1.0 - exp(-t * 4.0)) * exp(-t * 1.4)
                var c3:   float = sawtooth_wave(t * 130.81)
                var fs3:  float = sawtooth_wave(t * 185.00)
                var trem: float = 0.85 + 0.15 * sin(t * TAU * 3.0)
                pad[i] = 0.18 * (c3 + 0.8 * fs3) * env * trem

        var oh_layer := PackedFloat32Array()
        oh_layer.resize(total)
        var oh_start := [0.0, 0.4, 0.8]
        var oh_dur   := [0.35, 0.35, 0.40]
        var oh_freq  := [392.0, 349.23, 311.13]  # G4, F4, Eb4
        for k in 3:
                var start: int = int(SR * oh_start[k])
                var len: int   = int(SR * oh_dur[k])
                for i in len:
                        if start + i >= total: break
                        var t: float = float(i) / SR
                        var attack: float = 1.0 - exp(-t * 30.0)
                        var release: float = exp(-t * 6.0)
                        var env: float = attack * release
                        var vib: float = 6.0 * sin(t * TAU * 5.5)
                        var f: float = oh_freq[k] + vib
                        var fund: float = 0.55 * triangle_wave(t * f)
                        var f1:   float = 0.20 * pulse_wave(t * f * 2.0, 0.35)
                        var f2:   float = 0.12 * pulse_wave(t * f * 3.0, 0.25)
                        var open: float = exp(-t * 4.0)
                        var v: float = fund + f1 * open + f2 * open
                        oh_layer[start + i] += 0.55 * v * env

        var shimmer := PackedFloat32Array()
        shimmer.resize(total)
        for i in total:
                var t: float = float(i) / SR
                var env: float = (1.0 - exp(-t * 8.0)) * exp(-t * 1.8)
                var freq: float = 1200.0 + 800.0 * (t / 1.7)
                var sh: float = 0.18 * pulse_wave(t * freq, 0.1)
                var sparkle: float = 0.08 * noise_gen() * (0.5 + 0.5 * sin(t * TAU * 7.0))
                shimmer[i] = (sh + sparkle) * env

        var out := PackedFloat32Array()
        out.resize(total)
        for i in total:
                var v: float = pad[i] + oh_layer[i] + shimmer[i]
                out[i] = 2600.0 / 32767.0 * _soft_clip(v)
        return out


# ============================================================================
# RELIC (Task 21) — SFX delle reliquie
# ============================================================================

# --- RELIC_PICKUP: campana cristallina (equip reliquia), ~0.5s ----------------
# Parziale armonica 660/1320/1980 Hz con decadimenti sfalsati + shimmer.
func _sfx_relic_pickup() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.5)
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                v += 0.40 * sin(TAU * 660.0 * t) * exp(-t * 5.0)
                v += 0.25 * sin(TAU * 1320.0 * t) * exp(-t * 7.0)
                v += 0.15 * sin(TAU * 1980.0 * t) * exp(-t * 10.0)
                # Shimmer lento (battimento tra le due parziali superiori)
                v += 0.10 * sin(TAU * 1316.0 * t) * exp(-t * 6.0)
                s.append(3000.0 / 32767.0 * _soft_clip(v))
        return s


# --- RELIC_BREAK: crepak + frantumazione (rotta reliquia/armatura), ~0.4s -----
# Crack iniziale (rumore + 2 click), poi gragnola di frammenti che cade.
func _sfx_relic_break() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.4)
        var rng := RandomNumberGenerator.new()
        rng.seed = 210321
        var shards_left: int = 14
        var next_shard_t: float = 0.02
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                # Crack iniziale secco
                v += 0.55 * noise_gen() * exp(-t * 300.0)
                v += 0.30 * sin(TAU * 900.0 * t) * exp(-t * 220.0)
                v += 0.25 * sin(TAU * 300.0 * t) * exp(-t * 90.0)
                # Gragnola di frammenti (click radi via via più distanziati)
                if shards_left > 0 and t >= next_shard_t:
                        v += 0.45 * (rng.randf() * 2.0 - 1.0)
                        shards_left -= 1
                        next_shard_t = t + rng.randf_range(0.006, 0.05) * (1.0 + t * 2.0)
                # Coda di polvere
                v += 0.18 * noise_gen() * exp(-t * 12.0) * float(shards_left) / 14.0
                s.append(3000.0 / 32767.0 * _soft_clip(v))
        return s


# --- MELEE_SWING: whoosh della lama (fendente reliquia), ~0.22s ---------------
# Rumore passa-banda con risonanza che scende (lama che fende l'aria).
func _sfx_melee_swing() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.22)
        var rng := RandomNumberGenerator.new()
        rng.seed = 421421
        var lp: float = 0.0
        var bp: float = 0.0
        var bp_prev: float = 0.0
        for i in n:
                var t: float = float(i) / SR
                var p: float = t / 0.22
                var env: float = sin(PI * p)  # attacco morbido e chiusura morbida
                # Risonanza che scivola da 1800 a 500 Hz
                var res_f: float = 1800.0 - 1300.0 * p
                var w: float = TAU * res_f / SR
                var noise: float = rng.randf() * 2.0 - 1.0
                lp += minf(1.0, TAU * (res_f * 0.6) / SR) * (noise - lp)
                bp_prev = bp
                bp += w * (lp - bp)
                var v: float = 1.6 * (bp - bp_prev * 0.6)
                # Soffio basso di accompagnamento
                v += 0.20 * sin(TAU * (220.0 - 120.0 * p) * t) * env
                s.append(2800.0 / 32767.0 * _soft_clip(v * env * 0.9))
        return s


# --- REFLECT_BOLT: ping metallico-eterico (rimbalzo Scaglie), ~0.3s -----------
# Impulso inarmonico (880/1245/1560 Hz) che sale di un'ottava e svanisce.
func _sfx_reflect_bolt() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.3)
        for i in n:
                var t: float = float(i) / SR
                var p: float = t / 0.3
                # Le parziali salgono di un'ottava nel primo quarto
                var lift: float = 1.0 + p * 0.5
                var v: float = 0.0
                v += 0.40 * sin(TAU * 880.0 * lift * t) * exp(-t * 9.0)
                v += 0.22 * sin(TAU * 1245.0 * lift * t) * exp(-t * 12.0)
                v += 0.14 * sin(TAU * 1560.0 * lift * t) * exp(-t * 16.0)
                # Transiente del rimbalzo (il colpo che "tocca" le scaglie)
                if t < 0.02:
                        v += 0.35 * noise_gen() * exp(-t * 400.0)
                s.append(3000.0 / 32767.0 * _soft_clip(v))
        return s


# ============================================================================
# TASK 30 — SFX DEGLI HAZARD AMBIENTALI
# ============================================================================
# _sfx_hazard_snap(): GANASCE che scattano sulla vittima — impatto
# metallico secco (le mascelle che si chiudono) + rattle della molla che
# vibra. Due fasi: crack iniziale (5ms) e oscillazione della lama che si
# spegne in ~150ms.
func _sfx_hazard_snap() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.22)
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                # Crack metallico: rumore filtrato alto con decadimento rapido
                if t < 0.03:
                        v += 0.85 * noise_gen() * exp(-t * 260.0)
                # Vibrazione della lama (quasi-ottava metallica ~520Hz con
                # leggero detune tra le due mascelle: battimento)
                v += 0.30 * sin(TAU * 520.0 * t) * exp(-t * 22.0)
                v += 0.22 * sin(TAU * 548.0 * t) * exp(-t * 26.0)
                v += 0.12 * sin(TAU * 1560.0 * t) * exp(-t * 40.0)
                # Rattle finale della molla
                if t > 0.06:
                        v += 0.10 * noise_gen() * exp(-(t - 0.06) * 30.0) \
                                        * sin(TAU * 90.0 * t)
                s.append(3200.0 / 32767.0 * _soft_clip(v))
        return s


# _sfx_hazard_disarm(): scatto a VUOTO (disarmo da proiettile) — molla che
# rilascia e lama che sbatte senza carico: piu' corto e piu' acuto dello
# snap sulla vittima, con "twang" elastico invece del rattle.
func _sfx_hazard_disarm() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.15)
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                # Click del meccanismo che rilascia
                if t < 0.015:
                        v += 0.7 * noise_gen() * exp(-t * 500.0)
                # Twang elastico della molla (pitch che scende)
                var freq: float = 700.0 - 240.0 * (t / 0.15)
                v += 0.35 * sin(TAU * freq * t) * exp(-t * 30.0)
                v += 0.10 * sin(TAU * freq * 2.7 * t) * exp(-t * 45.0)
                s.append(2400.0 / 32767.0 * _soft_clip(v))
        return s


# _sfx_hazard_rumble(): ROMBO della crepa (telegrafo della voragine, dura
# quanto il telegrafo: 1.2s circa, qui sintetizziamo ~0.7s percettibili) —
# sub-basso che pulsa + rumore di pietra che si sgretola in sottofondo,
# volume crescente (il pavimento sta per cedere).
func _sfx_hazard_rumble() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.7)
        for i in n:
                var t: float = float(i) / SR
                var p: float = t / 0.7
                # Crescita del volume: la crepa si allarga
                var swell: float = 0.25 + 0.75 * p
                var v: float = 0.0
                # Sub-borso pulsante (~36Hz con battimento a 43Hz)
                v += 0.55 * sin(TAU * 36.0 * t) * (0.6 + 0.4 * sin(TAU * 7.0 * t))
                v += 0.30 * sin(TAU * 43.0 * t)
                # Polvere che gratta (rumo basso-bandlimited via campionamento)
                v += 0.18 * noise_gen() * (0.5 + 0.5 * sin(TAU * 11.0 * t + 1.3))
                s.append(2800.0 / 32767.0 * _soft_clip(v * swell))
        return s


# _sfx_hazard_collapse(): CROLLO della voragine — crack iniziale secco,
# frana (rumore che scivola giu' con pitch discendente) e coda di rombo
# che si spegne. Curva di volume: IMPATTO -> frana -> silenzio.
func _sfx_hazard_collapse() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.9)
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                # Crack del pavimento che cede
                if t < 0.04:
                        v += 0.9 * noise_gen() * exp(-t * 180.0)
                # Frana: rumore con ampiezza decrescente e grain via via piu'
                # radi (i massi piu' grossi cadono piu' tardi)
                var grain: float = 0.55 + 0.45 * sin(TAU * 5.0 * t)
                v += 0.40 * noise_gen() * grain * exp(-t * 4.5)
                # Massi che rotolano (tonfi bassi via via piu' radi)
                var rock_t: float = fmod(t, 0.14)
                v += 0.30 * sin(TAU * 60.0 * rock_t) * exp(-rock_t * 45.0) \
                                * exp(-t * 3.0)
                # Coda di rombo
                v += 0.25 * sin(TAU * 40.0 * t) * exp(-t * 3.5)
                s.append(3200.0 / 32767.0 * _soft_clip(v))
        return s


# _sfx_hazard_grind(): SFREGAMENTO delle lastre di roccia (apertura e
# pre-chiusura) — rumore di pietra su pietra con "wobble" lento (la lastra
# gratta in modo irregolare) e qualche scricchiolio acuto sparso.
func _sfx_hazard_grind() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.5)
        for i in n:
                var t: float = float(i) / SR
                # Wobble: la pressione della lastra non e' costante
                var wobble: float = 0.55 + 0.45 * sin(TAU * 9.0 * t + 0.7)
                var v: float = 0.0
                # Grattare principale (rumo con modulazione)
                v += 0.45 * noise_gen() * wobble
                # Risonanza della pietra (~140Hz)
                v += 0.20 * sin(TAU * 140.0 * t) * wobble
                # Scricchioli acuti irregolari (3 eventi deterministici)
                for k in 3:
                        var start: float = 0.06 + 0.16 * k
                        if t >= start and t < start + 0.03:
                                v += 0.30 * noise_gen() * exp(-(t - start) * 200.0)
                # Fade in/out (la lastra parte e si ferma)
                var fade: float = minf(t / 0.06, 1.0) * minf((0.5 - t) / 0.08, 1.0)
                fade = clampf(fade, 0.0, 1.0)
                s.append(2600.0 / 32767.0 * _soft_clip(v * fade))
        return s


# _sfx_hazard_thud(): TONFO della chiusura — impatto sordo e profondo
# (le due lastre che si incastrano): sub-basso con attacco istantaneo e
# coda corta, piu' un tocco di polvere (rumo basso) subito dopo.
func _sfx_hazard_thud() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.4)
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                # Impatto: 55Hz che decade in ~120ms con pitch drop
                var freq: float = 55.0 * exp(-t * 6.0) + 28.0
                v += 0.85 * sin(TAU * freq * t) * exp(-t * 18.0)
                # Corpo del tonfo (2a armonica)
                v += 0.25 * sin(TAU * freq * 2.0 * t) * exp(-t * 26.0)
                # Polvere che ricade dopo l'impatto
                if t > 0.05:
                        v += 0.15 * noise_gen() * exp(-(t - 0.05) * 14.0)
                s.append(3400.0 / 32767.0 * _soft_clip(v))
        return s


# _sfx_barrel_explode(): TASK 31 — ESPLOSIONE del barile: detonazione
# profonda (sub-basso con pitch drop) + scoppio di schegge di legno e
# cerchi di metallo (rumo medio + tintinni sparsi) + coda di fumo.
func _sfx_barrel_explode() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.7)
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                # Detonazione: sub che decade con pitch drop (40Hz -> 22Hz)
                var freq: float = 40.0 * exp(-t * 5.0) + 22.0
                v += 0.90 * sin(TAU * freq * t) * exp(-t * 11.0)
                v += 0.30 * sin(TAU * freq * 2.0 * t) * exp(-t * 20.0)
                # Scoppio iniziale (rumo largo, il legno che cede)
                if t < 0.06:
                        v += 0.75 * noise_gen() * exp(-t * 90.0)
                # Schegge di legno (rumo medio con decadimento a 2 stadi)
                v += 0.30 * noise_gen() * (exp(-t * 26.0) + 0.5 * exp(-t * 7.0))
                # Tintinnio dei cerchi metallici (3 eventi deterministici)
                for k in 3:
                        var start: float = 0.05 + 0.09 * k
                        if t >= start and t < start + 0.06:
                                var ring_f: float = 1400.0 + 600.0 * k
                                v += 0.18 * sin(TAU * ring_f * (t - start)) \
                                                * exp(-(t - start) * 60.0)
                s.append(3600.0 / 32767.0 * _soft_clip(v))
        return s


# _sfx_bat_screech(): TASK 32 — STRIDIO dei pipistrelli: raffica di
# squittii acuti (chirp discendenti 5.2kHz -> 2.8kHz) con interlezioni
# irregolari, come uno sciame agitato. Breve (0.35s) per il debounce.
func _sfx_bat_screech() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.35)
        # 6 chirp a intervalli irregolari deterministici
        var starts: Array[float] = [0.0, 0.045, 0.10, 0.16, 0.235, 0.29]
        var freqs: Array[float] = [5200.0, 4600.0, 5000.0, 4200.0, 4900.0, 3900.0]
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                for k in starts.size():
                        var st: float = starts[k]
                        if t >= st and t < st + 0.03:
                                # chirp discendente con vibrato
                                var dt: float = t - st
                                var f: float = freqs[k] * (1.0 - 0.45 * dt / 0.03) \
                                                * (1.0 + 0.06 * sin(TAU * 130.0 * dt))
                                v += 0.65 * sin(TAU * f * dt) * (1.0 - dt / 0.03)
                # soffio d'aria dello sciame sotto gli squittii
                v += 0.10 * noise_gen() * (0.5 + 0.5 * sin(TAU * 23.0 * t))
                s.append(2600.0 / 32767.0 * _soft_clip(v))
        return s


# _sfx_bat_flap(): TASK 32 — BATTITO D'ALI: due/tre soffici soffiate
# d'aria a bassa frequenza (ali di cuoio che battono), cadenza da volo
# in picchiata (~11 battiti/s nel reale, qui 3 per one-shot).
func _sfx_bat_flap() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.3)
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                # 3 battiti: each = whoosh con attacco morbido
                for k in 3:
                        var st: float = 0.02 + 0.10 * k
                        var dt: float = t - st
                        if dt >= 0.0 and dt < 0.07:
                                # soffio: rumo modulato da un inviluppo
                                # a campana (giu'-su dell'ala)
                                var bell: float = sin(PI * dt / 0.07)
                                v += 0.45 * noise_gen() * bell
                                v += 0.15 * sin(TAU * 90.0 * dt) * bell
                s.append(2200.0 / 32767.0 * _soft_clip(v))
        return s


func _generate_track(track_idx: int) -> AudioStreamWAV:
        match track_idx:
                TRACK_EPIC_CHALICE: return _samples_to_stream(_gen_epic_chalice())
                TRACK_EPIC_SCEPTER: return _samples_to_stream(_gen_epic_scepter())
                TRACK_MENU:         return _samples_to_stream(_gen_menu_track())
                TRACK_GHOST:        return _samples_to_stream(_gen_ghost_track())
                _:                  return _samples_to_stream(_gen_level_track(track_idx))


# --- Level/boss/portal tracks (32 bars, minor scale, ~100 BPM) --------------
# Simplified port: builds the same scale + chord progression + drums pattern
# as the original AudioManager.cpp:generateTrack.
func _gen_level_track(track_idx: int) -> PackedFloat32Array:
        var tempo: float = 130.0 if track_idx == 4 else (100.0 + track_idx * 2.5)
        var root: float
        var harmonic: bool
        if track_idx == 0:
                root = 146.83; harmonic = false          # D minor natural
        elif track_idx == 1:
                root = 130.81; harmonic = true            # C harmonic minor
        elif track_idx == 2:
                root = 123.47; harmonic = false           # B minor natural
        elif track_idx == 3:
                root = 82.41;  harmonic = true            # E harmonic minor
        elif track_idx == 5:
                root = 110.0;  harmonic = true; tempo = 70.0  # A harmonic minor (portal)
        else:
                root = 87.31;  harmonic = true; tempo = 130.0  # F harmonic minor (boss)

        var nat := [0, 2, 3, 5, 7, 8, 10]
        var har := [0, 2, 3, 5, 7, 8, 11]
        var intervals: Array = har if harmonic else nat

        var scale := []
        for iv in intervals:
                scale.append(root * pow(2.0, float(iv) / 12.0))

        var beat_dur: float = 60.0 / tempo
        var sixteenth_dur: float = beat_dur / 4.0
        var samples_per_sixteenth: int = int(SR * sixteenth_dur)
        # FIX (lento avvio gioco): ridotto da 64 a 48 barre per velocizzare
        # la generazione procedurale delle musiche all'avvio (1.5 min invece
        # di 2.5 min, ancora sufficiente per non essere ripetitivo).
        var num_bars: int = 48
        var total: int = num_bars * 4 * samples_per_sixteenth

        # Due progressioni: A (principale) e B (bridge, modulata)
        var prog_a := [0, 5, 2, 6]   # i, VI, III, VII
        var prog_b := [3, 2, 5, 4]   # IV, III, VI, V (bridge, più luminoso)
        # Drum patterns (16 sixteenths per bar)
        var kick: Array  = [1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,0,0]
        var snare: Array = [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]
        var hihat: Array = [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]
        if track_idx == 4:
                # Boss: double-time
                kick[3] = 1; kick[7] = 1; kick[11] = 1; kick[15] = 1
                snare[6] = 1; snare[14] = 1
                for i in 16: hihat[i] = 1
        if track_idx == 5:
                # Portal: ethereal, sparse
                for i in 16: kick[i] = 0
                for i in 16: snare[i] = 0
                for i in 16: hihat[i] = 0
                kick[0] = 1
                hihat[0] = 1; hihat[8] = 1

        var out := PackedFloat32Array()
        out.resize(total)
        var write_idx: int = 0
        for bar in num_bars:
                # Determina quale progressione usare (AABA)
                var prog: Array
                var is_bridge: bool = (bar >= 32 and bar < 48)
                if is_bridge:
                        prog = prog_b
                else:
                        prog = prog_a
                var chord_root: float = scale[prog[bar % 4]]
                # Sezione coro: ogni 8 barre (es. 8-11, 24-27, 40-43) — più pieno
                var is_chorus: bool = ((bar >= 8 and bar <= 11) or
                                       (bar >= 24 and bar <= 27) or
                                       (bar >= 40 and bar <= 43))
                # Variazione melodica: il pattern del lead cambia ogni 16 barre
                # per evitare la sensazione di loop ripetitivo.
                var lead_pattern: int = (bar / 16) % 3  # 0, 1, 2
                # Fill di batteria sull'ultima barra di ogni sezione (7, 15, 31, 47)
                var is_fill_bar: bool = (bar == 7 or bar == 15 or bar == 31 or bar == 47)
                for beat in 4:
                        for s in 4:
                                # Lead: pattern arpeggio che varia per sezione
                                var note_idx: int
                                match lead_pattern:
                                        0: note_idx = (s + beat) % 4
                                        1: note_idx = (s * 2 + beat) % 4
                                        _: note_idx = (s + beat * 2) % 4
                                var lead_freq: float = chord_root * pow(2.0, float(note_idx) / 12.0)
                                # Bass: triangle one octave below chord root
                                var bass_freq: float = chord_root * 0.5
                                # Drums
                                var pat_idx: int = (beat * 4 + s) % 16
                                var k: bool = bool(kick[pat_idx])
                                var sn: bool = bool(snare[pat_idx])
                                var hh: bool = bool(hihat[pat_idx])
                                # Fill: sull'ultima barra, sostituisci pattern con roll di tom
                                if is_fill_bar and beat >= 2:
                                        k = (s == 0 or s == 2)
                                        sn = (s == 1 or s == 3)
                                # Generate the sixteenth
                                for i in samples_per_sixteenth:
                                        if write_idx >= total: break
                                        var t: float = float(i) / SR
                                        # Lead pulse (duty 0.25 per arpeggio brightness)
                                        var lead: float = 0.0
                                        if is_chorus or (s == 0) or is_bridge:
                                                lead = 0.30 * pulse_wave(t * lead_freq, 0.25)
                                        elif lead_pattern > 0 and (s == 2):
                                                lead = 0.20 * pulse_wave(t * lead_freq * 1.5, 0.25)
                                        # Bass triangle
                                        var bass: float = 0.30 * triangle_wave(t * bass_freq)
                                        # Sawtooth pad (only in chorus/bridge)
                                        var pad: float = 0.0
                                        if is_chorus or is_bridge:
                                                pad = 0.15 * sawtooth_wave(t * chord_root)
                                        # Drums
                                        var drum: float = 0.0
                                        if k:
                                                drum += 0.4 * (0.6 * triangle_wave(t * 60.0) + 0.4 * noise_gen()) * exp(-t * 30.0)
                                        if sn:
                                                drum += 0.3 * noise_gen() * exp(-t * 25.0)
                                        if hh:
                                                drum += 0.15 * noise_gen() * exp(-t * 50.0)
                                        var v: float = lead + bass + pad + drum
                                        out[write_idx] = v * 0.5
                                        write_idx += 1
        return out


# --- Musica del calice: tema dall'INTERMEZZO della "Cavalleria Rusticana"
# di Pietro Mascagni, ~9.5s (loop = durata esatta dell'effetto calice,
# 9500ms) -------------------------------------------------------------------
# FIX (musica calice = Cavalleria Rusticana, richiesta utente): sostituisce
# la fanfara "Trionfo d'Oro". Melodia fedele alle note e ai ritmi del tema
# (originale in Fa maggiore; la celebre salita FA5-LA5-DO6, il giro
# Sib5-LA5-SOL5, il salto RE6-FA5 e i LA5 tenuti), resa con:
#   * violini sintetici (doppio saw detunato + lowpass monopolo + vibrato
#     d'arco 5.5Hz + inviluppo ad arco con attacco morbido),
#   * raddoppio all'ottava al LA5 del culmine (shimmer),
#   * viole/violoncelli sulle note tenute degli accordi,
#   * contrabbasso (toniche) e il caratteristico accompagnamento "a culla"
#     in ottavi pizzicati (tonica-quinta-terza-quinta),
#   * crescendo dolce fino al culmine (swell gaussiano sul LA5 lungo),
#   * cadenza finale sul Do7 che risolve sul Fa alla ripartenza del loop,
#   * riverbero "da sala" con 2 tap CIRCOLARI: la coda dell'accordo finale
#     riaffiora all'inizio del loop → giunzione senza "taglio".
# Armonia: Fa | Sib | Solm7 | Fa | Do7 | Fa | Rem | Do7 → (loop) Fa.
# Struttura melodia (battuta = 0.65s, ~92 BPM):
#   b0-3    salita FA5-LA5-DO6 + DO6 puntata (il gesto piu' famoso)
#   b3-5    DO6 puntata, respiro Sib5-LA5
#   b5-7    giro SOL5 + salto RE6-FA5 (Sol minore7)
#   b7-9    LA5 tenuto sul Fa (prima culminazione)
#   b9-10   SOL5 sul Do7 (dominante)
#   b10-12.5 LA5 tenuto raddoppiato all'ottava (culmine con swell)
#   b12.5-14 cadenza FA5-MI5-RE5 + DO5 sospeso sul Do7 → riparte il Fa
func _gen_epic_chalice() -> PackedFloat32Array:
        const DUR: float = 9.5              # secondi (loop = durata calice)
        const BEAT: float = 0.65             # ~92 BPM
        var total: int = int(SR * DUR)
        var out := PackedFloat32Array()
        out.resize(total)

        # --- Melodia (violini): tema dell'Intermezzo, note fedeli ----------
        # [start_beat, dur_beats, freq, gain] (bilanciamento QA: la melodia
        # deve dominare chiaramente l'armonia di fondo — violini in prima
        # fila, viole di sostegno)
        const LEAD: Array = [
                # salita FA5-LA5-DO6 e DO6 puntata
                [0.0, 1.0, 698.46, 0.270], [1.0, 1.0, 880.00, 0.290],
                [2.0, 1.0, 1046.50, 0.320],
                [3.0, 1.5, 1046.50, 0.320], [4.5, 0.5, 939.89, 0.275],
                # respiro LA5-SOL5 e salto RE6-FA5
                [5.0, 0.5, 880.00, 0.265], [5.5, 0.5, 783.99, 0.260],
                [6.0, 0.5, 1174.66, 0.300], [6.5, 0.5, 698.46, 0.255],
                # LA5 tenuto (prima culminazione)
                [7.0, 2.0, 880.00, 0.340],
                # SOL5 sul Do7 (dominante)
                [9.0, 1.0, 783.99, 0.295],
                # LA5 tenuto lungo: culmine della frase
                [10.0, 2.5, 880.00, 0.385],
                # cadenza FA5-MI5-RE5 + DO5 sospeso (il Fa riparte in loop)
                [12.5, 0.5, 698.46, 0.230], [13.0, 0.5, 659.26, 0.210],
                [13.5, 0.5, 587.33, 0.195],
                [14.0, 0.55, 523.25, 0.190],
        ]
        # Raddoppio all'ottava (violini sopra + arpa): shimmer al culmine.
        const LEAD_OCT: Array = [
                [7.0, 2.0, 1760.00, 0.055],
                [10.0, 2.5, 1760.00, 0.100],
                # Arpa che raddoppia la salita iniziale (un'ottava sotto)
                [0.0, 0.9, 349.23, 0.050], [1.0, 0.9, 440.00, 0.050],
                [2.0, 0.9, 523.25, 0.055],
        ]
        # Armonia (viole/violoncelli): note tenute sugli accordi — di
        # SOSTEGNO (guadagni ridotti in QA: la melodia deve stare davanti).
        const HARMONY: Array = [
                [0.0, 4.5, 349.23, 0.070], [0.0, 4.5, 440.00, 0.060],  # Fa
                [4.5, 1.0, 293.66, 0.065], [4.5, 1.0, 349.23, 0.060],  # Sib
                [5.5, 1.5, 233.08, 0.068], [5.5, 1.5, 293.66, 0.058],  # Solm7
                [7.0, 2.0, 349.23, 0.075], [7.0, 2.0, 440.00, 0.064],  # Fa
                [9.0, 1.0, 329.63, 0.068], [9.0, 1.0, 392.00, 0.058],  # Do7
                [10.0, 2.5, 349.23, 0.085], [10.0, 2.5, 440.00, 0.072],
                [10.0, 2.5, 523.25, 0.046],                             # Fa (climax)
                [12.5, 0.5, 293.66, 0.060], [12.5, 0.5, 349.23, 0.056], # Rem
                [13.0, 1.6, 329.63, 0.068], [13.0, 1.6, 392.00, 0.058], # Do7
        ]
        # Basso (contrabbasso/violoncello): toniche sostenute.
        const BASS: Array = [
                [0.0, 4.5, 87.31, 0.170],    # Fa2
                [4.5, 1.0, 116.54, 0.165],   # Sib2
                [5.5, 1.5, 98.00, 0.165],    # Sol2
                [7.0, 2.0, 87.31, 0.170],    # Fa2
                [9.0, 1.0, 130.81, 0.165],   # Do3
                [10.0, 2.5, 87.31, 0.180],    # Fa2
                [12.5, 0.5, 146.83, 0.150],   # Re3 (Rem)
                [13.0, 1.6, 130.81, 0.165],  # Do3 (Do7) → risolve sul Fa in loop
        ]
        # Accompagnamento "a culla" (ottavi pizzicati): [inizio, fine,
        # [tonica, quinta, terza]] — il dondolio tipico dell'Intermezzo.
        const ACC_CHORDS: Array = [
                [0.0, 4.5, [174.61, 261.63, 220.00]],       # Fa: F3 C4 A3
                [4.5, 5.5, [233.08, 349.23, 293.66]],       # Sib: Bb3 F4 D4
                [5.5, 7.0, [196.00, 293.66, 233.08]],       # Solm7: G3 D4 Bb3
                [7.0, 9.0, [174.61, 261.63, 220.00]],       # Fa
                [9.0, 10.0, [261.63, 392.00, 329.63]],      # Do7: C4 G4 E4
                [10.0, 12.5, [174.61, 261.63, 220.00]],     # Fa (climax)
                [12.5, 13.0, [293.66, 440.00, 349.23]],    # Rem: D4 A4 F4
                [13.0, 14.5, [261.63, 392.00, 329.63]],    # Do7
        ]

        # --- Rendering: violini (doppio saw detunato + lowpass + vibrato) ---
        for note in LEAD + LEAD_OCT:
                var start_s: float = float(note[0]) * BEAT
                var dur_s: float = float(note[1]) * BEAT
                var freq: float = float(note[2])
                var gain: float = float(note[3])
                var n: int = int(dur_s * SR)
                var i0: int = int(start_s * SR)
                var phase1: float = 0.0
                var phase2: float = 0.0
                var lp: float = 0.0
                for i in n:
                        var idx: int = i0 + i
                        if idx >= total:
                                break
                        var t: float = float(i) / SR
                        # Arco d'arco: attacco morbido ~90ms, rilascio morbido
                        var env: float = (1.0 - exp(-t * 16.0)) \
                                        * (1.0 - exp(-(dur_s - t) * 14.0))
                        # Vibrato d'archi (5.5 Hz) che entra dopo 0.2s
                        var vib: float = 1.0 + 0.0045 * sin(TAU * 5.5 * t) \
                                        * clampf((t - 0.2) * 2.5, 0.0, 1.0)
                        phase1 += freq * vib / SR
                        phase2 += freq * vib * 1.0035 / SR
                        var raw: float = 0.55 * sawtooth_wave(phase1) \
                                        + 0.45 * sawtooth_wave(phase2)
                        # Filtro passa-basso monopolo: ammorbidisce i saw
                        lp += 0.25 * (raw - lp)
                        out[idx] += gain * lp * env

        # --- Armonia (viole): pad tenuti, pulse morbida + triangolare -------
        for note in HARMONY:
                var start_s: float = float(note[0]) * BEAT
                var dur_s: float = float(note[1]) * BEAT
                var freq: float = float(note[2])
                var gain: float = float(note[3])
                var n: int = int(dur_s * SR)
                var i0: int = int(start_s * SR)
                var phase: float = 0.0
                for i in n:
                        var idx: int = i0 + i
                        if idx >= total:
                                break
                        var t: float = float(i) / SR
                        var env: float = (1.0 - exp(-t * 8.0)) \
                                        * (1.0 - exp(-(dur_s - t) * 6.0))
                        phase += freq / SR
                        out[idx] += gain * (0.6 * pulse_wave(phase, 0.5) \
                                        + 0.4 * triangle_wave(phase)) * env

        # --- Basso: triangolare + pulse, attacco lento ----------------------
        for note in BASS:
                var start_s: float = float(note[0]) * BEAT
                var dur_s: float = float(note[1]) * BEAT
                var freq: float = float(note[2])
                var gain: float = float(note[3])
                var n: int = int(dur_s * SR)
                var i0: int = int(start_s * SR)
                var phase: float = 0.0
                for i in n:
                        var idx: int = i0 + i
                        if idx >= total:
                                break
                        var t: float = float(i) / SR
                        var env: float = (1.0 - exp(-t * 8.0)) \
                                        * (1.0 - exp(-(dur_s - t) * 5.0))
                        phase += freq / SR
                        out[idx] += gain * (0.7 * triangle_wave(phase) \
                                        + 0.3 * pulse_wave(phase, 0.5)) * env

        # --- Accompagnamento "a culla": pizzicati in ottavi -----------------
        # Pattern per ogni semibattuta: tonica-quinta-terza-quinta.
        for chord in ACC_CHORDS:
                var b_start: float = float(chord[0])
                var b_end: float = float(chord[1])
                var tones: Array = chord[2]
                var pluck_idx: int = 0
                var b: float = b_start
                while b < b_end - 0.001:
                        var tone_freq: float = float(tones[pluck_idx % 4 if pluck_idx % 4 != 3 else 1])
                        var start_s: float = b * BEAT
                        var dur_s: float = 0.5 * BEAT
                        var i0: int = int(start_s * SR)
                        # swell gaussiano centrato sul culmine (b≈11.2)
                        var d_swell: float = b - 11.2
                        var swell: float = 1.0 + 0.35 * exp(-d_swell * d_swell / 5.12)
                        var n_p: int = int(dur_s * 1.4 * SR)
                        var phase: float = 0.0
                        for i in n_p:
                                var idx: int = i0 + i
                                if idx >= total:
                                        break
                                var t: float = float(i) / SR
                                var env: float = (1.0 - exp(-t * 400.0)) * exp(-t * 6.5)
                                phase += tone_freq / SR
                                out[idx] += 0.085 * swell \
                                                * (0.7 * triangle_wave(phase) \
                                                + 0.3 * sawtooth_wave(phase)) * env
                        pluck_idx += 1
                        b += 0.5

        # --- Mix finale: riverbero "da sala" con 2 tap CIRCOLARI -------------
        # La coda dell'accordo finale riaffiora all'inizio del loop: la
        # giunzione del loop resta "bagnata" di sala, senza taglio secco.
        var wet := out.duplicate()
        for i in total:
                var v: float = out[i]
                wet[(i + int(0.097 * SR)) % total] += 0.20 * v
                wet[(i + int(0.211 * SR)) % total] += 0.11 * v
        for i in total:
                out[i] = 0.85 * _soft_clip(wet[i] * 1.15)
        return out


# --- FIX (stamina salti): click "a vuoto" del tasto di salto ------------------
# Pulsante meccanico premuto senza molla: doppio transiente secco ("tk-tk"),
# il secondo piu' smorzato (il ritorno del tasto), ~0.09s. Molto corto e
# asciutto per non confondersi con gli spari.
func _sfx_stamina_click() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.09)
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                # Primo transiente: "TK" secco (rumore + ping a 1.9kHz)
                v += 0.55 * noise_gen() * exp(-t * 500.0)
                v += 0.30 * sin(TAU * 1900.0 * t) * exp(-t * 350.0)
                v += 0.18 * sin(TAU * 430.0 * t) * exp(-t * 140.0)
                # Secondo transiente (ritorno del pulsante, piu' cupo)
                var t2: float = t - 0.030
                if t2 > 0.0:
                        v += 0.30 * noise_gen() * exp(-t2 * 550.0)
                        v += 0.18 * sin(TAU * 1250.0 * t2) * exp(-t2 * 320.0)
                s.append(3200.0 / 32767.0 * _soft_clip(v))
        return s

# ----------------------------------------------------------------------------
# FIX (martello di Thor): whoosh del lancio — rumore filtrato con sweep di
# risonanza (il "sibilo" di Mjolnir che rotea) + sub thump della botta in
# mano al lancio. 0.28s.
func _sfx_hammer_throw() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.28)
        var rng := RandomNumberGenerator.new()
        rng.seed = 777017
        var lp: float = 0.0  # stato filtro passa-basso a 1 polo
        for i in n:
                var t: float = float(i) / SR
                # Envelope: attacco secco e coda che svanisce
                var env: float = exp(-t * 14.0) * minf(t * 900.0, 1.0)
                # Rumore "whoosh": passa-basso con cutoff che SALE (300->2400Hz)
                var cutoff: float = 300.0 + 2100.0 * (t / 0.28)
                var alpha: float = minf(1.0, TAU * cutoff / SR)
                lp += alpha * ((rng.randf() * 2.0 - 1.0) - lp)
                var v: float = 1.35 * lp
                # Sibilo della rotazione (tono che sale, 420->900 Hz, leggero)
                v += 0.22 * sin(TAU * (420.0 + 480.0 * t / 0.28) * t) * env
                # Sub thump iniziale (la botta del lancio)
                v += 0.35 * sin(TAU * 70.0 * t) * exp(-t * 45.0)
                s.append(3000.0 / 32767.0 * _soft_clip(v * env))
        return s

# ----------------------------------------------------------------------------
# FIX (martello di Thor): clang metallico — l'impatto su un muro DI BORDO
# (indistruttibile) o su un nemico: colpo d'acciaio con parziali inarmoniche
# (1250/1980/2640 Hz) + rumore d'urto. 0.16s.
func _sfx_hammer_clank() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.16)
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                # Urto (rumore breve, ~30ms)
                v += 0.45 * noise_gen() * exp(-t * 260.0)
                # Parziali metalliche inarmoniche con decadimenti diversi
                v += 0.30 * sin(TAU * 1250.0 * t) * exp(-t * 55.0)
                v += 0.20 * sin(TAU * 1980.0 * t) * exp(-t * 80.0)
                v += 0.14 * sin(TAU * 2640.0 * t) * exp(-t * 110.0)
                # Leggero detune del parziale principale (battimento)
                v += 0.12 * sin(TAU * 1259.0 * t) * exp(-t * 55.0)
                # Body basso (thump)
                v += 0.25 * sin(TAU * 95.0 * t) * exp(-t * 60.0)
                s.append(3000.0 / 32767.0 * _soft_clip(v))
        return s

# ----------------------------------------------------------------------------
# FIX (martello di Thor): crollo del muro interno spezzato — sgretolamento
# della pietra: rombo basso che decade + "polvere" di rumore filtrato +
# raffica di grani di ghiaia (click casuali fitti all'inizio, radi dopo).
# 0.55s.
func _sfx_wall_crumble() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.55)
        var rng := RandomNumberGenerator.new()
        rng.seed = 424242
        var lp: float = 0.0
        var grains_left: int = 26  # grani di ghiaia rimanenti
        var next_grain_t: float = 0.0
        for i in n:
                var t: float = float(i) / SR
                var v: float = 0.0
                # Rombo basso del cedimento strutturale (55Hz + detune)
                v += 0.40 * sin(TAU * 55.0 * t) * exp(-t * 6.0)
                v += 0.18 * sin(TAU * 71.0 * t) * exp(-t * 7.0)
                # Polvere: rumore passa-basso con cutoff che scende
                var cutoff: float = 900.0 * exp(-t * 5.0) + 120.0
                var alpha: float = minf(1.0, TAU * cutoff / SR)
                lp += alpha * ((rng.randf() * 2.0 - 1.0) - lp)
                v += 0.55 * lp * exp(-t * 4.5)
                # Grani di ghiaia: click casuali (cumulo che si assesta)
                if grains_left > 0 and t >= next_grain_t:
                        v += 0.65 * (rng.randf() * 2.0 - 1.0)
                        grains_left -= 1
                        next_grain_t = t + rng.randf_range(0.004, 0.05) * (1.0 + t)
                s.append(3200.0 / 32767.0 * _soft_clip(v))
        return s


# --- FUOCO AMICO (Task 18): whoosh etereo ascendente ~0.65s -----------------
# L'anima si separa dal corpo del player ucciso: sweep 220 -> 880 Hz con
# vibrato lento, strato triangle + sine detunata, attacco morbido (swell)
# e coda shimmer che svanisce. Volume moderato: e' un evento "mistico",
# non un'esplosione.
func _sfx_soul_release() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var n: int = int(SR * 0.65)
        for i in n:
                var t: float = float(i) / SR
                var p: float = t / 0.65  # progresso 0..1
                # Sweep di frequenza ascendente (l'anima sale)
                var freq: float = 220.0 + 660.0 * p * p
                # Vibrato etereo lento (onde del ectoplasma)
                var vib: float = 1.0 + 0.015 * sin(TAU * 5.5 * t)
                var f: float = freq * vib
                # Envelope: swell morbido in entrata, decadimento in uscita
                var env: float = (1.0 - exp(-t * 18.0)) * exp(-t * 3.2)
                var v: float = 0.45 * triangle_wave(t * f) \
                                + 0.35 * sin(TAU * f * 1.005 * t) \
                                + 0.20 * sin(TAU * f * 0.5 * t)
                # Shimmer: soffio armonico alto che appare a meta' volo
                var shimmer: float = 0.0
                if p > 0.25:
                        shimmer = 0.18 * sin(TAU * f * 2.0 * t) \
                                        * exp(-(t - 0.16) * 2.0) * (p - 0.25) / 0.75
                s.append(2400.0 / 32767.0 * (v + shimmer) * env)
        # Coda riverbero: ultima armonica che svanisce
        var tail: int = int(SR * 0.3)
        for i in tail:
                var t: float = float(i) / SR
                var env: float = exp(-t * 6.0)
                var v: float = 0.3 * sin(TAU * 880.0 * t) + 0.15 * triangle_wave(t * 440.0)
                s.append(1200.0 / 32767.0 * v * env)
        return s


# --- FUOCO AMICO (Task 18): assorbimento anima, arpeggio scintillante ~0.5s --
# L'anima raggiunge il vincitore e la sua energia si ricarica: 5 note
# ascendenti (C5-E5-G5-C6-E6) sine+triangle con detune, tipo campanelline
# magiche. Chiude con un accordo breve (energia piena!).
func _sfx_soul_absorb() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        var notes := [523.0, 659.0, 784.0, 1047.0, 1319.0]
        for k in notes.size():
                var note: float = notes[k]
                var seg: int = int(SR * 0.07)
                for i in seg:
                        var t: float = float(i) / SR
                        var env: float = (1.0 - exp(-t * 60.0)) * exp(-t * 9.0)
                        var v: float = 0.5 * sin(TAU * note * t) \
                                        + 0.3 * triangle_wave(t * note * 1.003) \
                                        + 0.2 * sin(TAU * note * 2.0 * t)
                        s.append(2600.0 / 32767.0 * v * env)
        # Accordo finale: energia completamente ricaricata
        var chord: int = int(SR * 0.22)
        for i in chord:
                var t: float = float(i) / SR
                var env: float = (1.0 - exp(-t * 25.0)) * exp(-t * 4.0)
                var v: float = 0.30 * sin(TAU * 1047.0 * t) \
                                + 0.25 * sin(TAU * 1319.0 * t) \
                                + 0.20 * sin(TAU * 1568.0 * t) \
                                + 0.25 * triangle_wave(t * 523.0)
                s.append(2400.0 / 32767.0 * v * env)
        return s


# --- Epic scepter jingle: arcane, ~7s, tritone C-F# ------------------------
# Pad saw (C3 + F#3), 3 "oh" exclamations (G4, F4, Eb4), shimmer sweep,
# ending on the unresolved tritone.
func _gen_epic_scepter() -> PackedFloat32Array:
        var total: int = int(SR * 7.0)
        var out := PackedFloat32Array()
        out.resize(total)
        # Pad: C3 + F#3 tritone (sawtooth tremolo)
        for i in total:
                var t: float = float(i) / SR
                var env: float = (1.0 - exp(-t * 3.0)) * exp(-t * 0.5)
                var c3: float = sawtooth_wave(t * 130.81)
                var fs3: float = sawtooth_wave(t * 185.00)
                var trem: float = 0.85 + 0.15 * sin(t * TAU * 3.0)
                out[i] = 0.18 * (c3 + 0.8 * fs3) * env * trem
        # 3 descending "oh" (G4, F4, Eb4)
        var oh_start := [0.0, 0.8, 1.6]
        var oh_dur   := [0.7, 0.7, 0.8]
        var oh_freq  := [392.0, 349.23, 311.13]
        for k in 3:
                var start: int = int(SR * oh_start[k])
                var len: int   = int(SR * oh_dur[k])
                for i in len:
                        if start + i >= total: break
                        var t: float = float(i) / SR
                        var env: float = (1.0 - exp(-t * 30.0)) * exp(-t * 6.0)
                        var vib: float = 6.0 * sin(t * TAU * 5.5)
                        var f: float = oh_freq[k] + vib
                        var fund: float = 0.45 * triangle_wave(t * f)
                        var f1:   float = 0.18 * pulse_wave(t * f * 2.0, 0.35)
                        var open: float = exp(-t * 4.0)
                        out[start + i] += 0.35 * (fund + f1 * open) * env
        # Shimmer sweep
        for i in total:
                var t: float = float(i) / SR
                var env: float = (1.0 - exp(-t * 6.0)) * exp(-t * 1.4)
                var freq: float = 1200.0 + 800.0 * (t / 7.0)
                var sh: float = 0.15 * pulse_wave(t * freq, 0.1)
                out[i] += sh * env
        # Normalize / soft clip
        for i in total:
                out[i] = _soft_clip(out[i]) * 0.6
        return out


# --- Menu music: choiral fantasy, loop, ~80 BPM, harmonic minor ------------
# FIX (musiche troppo brevi): esteso da 16 a 48 barre (~3 min a 80 BPM).
# Struttura AABA con bridge modulato + variazione melodica.
func _gen_menu_track() -> PackedFloat32Array:
        var tempo: float = 80.0
        var beat_dur: float = 60.0 / tempo
        var sixteenth_dur: float = beat_dur / 4.0
        var samples_per_sixteenth: int = int(SR * sixteenth_dur)
        # FIX: esteso da 16 a 48 barre (~3 min). Struttura AABA:
        #   barre 0-15:  Verse A
        #   barre 16-31: Verse A' (variazione)
        #   barre 32-47: Bridge B (modulazione + arpeggio più veloce)
        var num_bars: int = 48
        var total: int = num_bars * 4 * samples_per_sixteenth

        # A harmonic minor scale (root A2 = 110 Hz)
        var root: float = 110.0
        var intervals := [0, 2, 3, 5, 7, 8, 11]
        var scale := []
        for iv in intervals:
                scale.append(root * pow(2.0, float(iv) / 12.0))
        var prog_a := [0, 5, 2, 6]   # i, VI, III, VII (principale)
        var prog_b := [3, 4, 5, 2]   # IV, V, VI, III (bridge, più luminoso)

        var out := PackedFloat32Array()
        out.resize(total)
        var write_idx: int = 0
        for bar in num_bars:
                var is_bridge: bool = (bar >= 32 and bar < 48)
                var prog: Array = prog_b if is_bridge else prog_a
                var chord_root: float = scale[prog[bar % 4]]
                # Variazione melodica: pattern arpeggio cambia ogni 16 barre
                var arp_pattern: int = (bar / 16) % 2
                for beat in 4:
                        for s in 4:
                                var bass_freq: float = chord_root * 0.5
                                var arp_idx: int
                                match arp_pattern:
                                        0: arp_idx = (s + beat * 2) % 7
                                        _: arp_idx = (s * 3 + beat) % 7
                                var arp_freq: float = scale[arp_idx] * 2.0
                                for i in samples_per_sixteenth:
                                        if write_idx >= total: break
                                        var t: float = float(i) / SR
                                        var env: float = exp(-t * 4.0) * (1.0 - exp(-t * 30.0))
                                        var pad: float = 0.20 * sawtooth_wave(t * chord_root)
                                        var lead: float = 0.0
                                        if s == 0 or (is_bridge and s == 2):
                                                lead = 0.25 * pulse_wave(t * arp_freq * 2.0, 0.5)
                                        var arp: float = 0.15 * pulse_wave(t * arp_freq, 0.25)
                                        # Bridge: doppio arp più veloce
                                        if is_bridge:
                                                arp *= 1.3
                                        var bass: float = 0.25 * triangle_wave(t * bass_freq)
                                        out[write_idx] = (pad + lead + arp + bass) * env * 0.5
                                        write_idx += 1
        return out


# ============================================================================
# FIX (pozione magica): SFX deglutizione — "glu-glu" singolo secco (0.35s).
# Due deglutizioni discendenti (340Hz -> 220Hz) con rumore liquido, più un
# piccolo "aaah" finale discendente. Più corto e netto del POTION_DRINK
# (che è il glug-glug del medikit).
# ============================================================================
func _sfx_potion_gulp() -> PackedFloat32Array:
        var s := PackedFloat32Array()
        # Due deglutizioni
        for gulp in 2:
                var freq: float = 340.0 - float(gulp) * 60.0
                var seg: int = int(SR * 0.13)
                for i in seg:
                        var t: float = float(i) / SR
                        var env: float = exp(-t * 12.0) * (1.0 - exp(-t * 60.0))
                        # Modulazione "gorgoglio": la frequenza scende dentro il gulp
                        var f: float = freq * (1.0 - 0.35 * t / 0.13)
                        var mod_: float = 1.0 + 0.25 * sin(t * 26.0)
                        var v: float = 0.45 * triangle_wave(t * f * mod_) \
                                + 0.25 * sawtooth_wave(t * f * 0.6 * mod_) \
                                + 0.30 * noise_gen() * exp(-t * 22.0)
                        s.append(2600.0 / 32767.0 * v * env)
                # Pausa tra i gulp
                for i in int(SR * 0.05):
                        s.append(0.0)
        # "Aaah" finale discendente (0.12s)
        var fin: int = int(SR * 0.12)
        for i in fin:
                var t: float = float(i) / SR
                var env: float = exp(-t * 14.0) * (1.0 - exp(-t * 50.0))
                var f: float = 260.0 * exp(-t * 6.0) + 90.0
                var v: float = 0.4 * triangle_wave(t * f) + 0.2 * pulse_wave(t * f * 0.5, 0.5)
                s.append(2000.0 / 32767.0 * v * env)
        return s


# --- FIX (mini boss immortale): risata tenebrosa ~1.65s ---------------------
# "HEH-HEH-HEH-HEH... HAAA-aa": 4 sillabe con pitch discendente (voce
# raspy sawtooth + corpo triangolare), vibrato 6Hz, modulazione gutturale
# ~28Hz, eco cupo a 3 ritardi (sala oscura) e drone basso 55Hz. La caduta
# finale del pitch dà la sensazione "non puoi uccidermi, scappa...".
func _sfx_dark_laugh() -> PackedFloat32Array:
        var base := PackedFloat32Array()
        var syll_freqs: Array[float] = [210.0, 184.0, 162.0, 132.0]
        var syll_dur: float = 0.22
        var gap_dur: float = 0.085
        var total_dur: float = syll_freqs.size() * (syll_dur + gap_dur) + 0.42
        var n_total: int = int(SR * total_dur)
        base.resize(n_total)
        for i in n_total:
                base[i] = 0.0
        # Quattro sillabe "HEH"
        for k in syll_freqs.size():
                var f0: float = syll_freqs[k]
                var seg: int = int(SR * syll_dur)
                var offset: int = int(SR * (syll_dur + gap_dur) * float(k))
                for i in seg:
                        var t: float = float(i) / SR
                        # inviluppo: attacco 8ms, rilascio esponenziale
                        var env: float = (1.0 - exp(-t * 90.0)) * exp(-t * 9.0)
                        # pitch che cala dentro la sillaba + vibrato
                        var f: float = f0 * (1.0 - 0.22 * (t / syll_dur)) \
                                        * (1.0 + 0.035 * sin(TAU * 6.0 * t + float(k)))
                        var phase: float = f * t
                        # gutturale: AM veloce che dà il timbro "cattivo"
                        var gutt: float = 1.0 - 0.35 * (0.5 + 0.5 * sin(TAU * 28.0 * t))
                        var v: float = 0.55 * sawtooth_wave(phase) \
                                        + 0.45 * triangle_wave(phase * 0.5)
                        var idx: int = offset + i
                        if idx < n_total:
                                base[idx] = 3000.0 / 32767.0 * v * env * gutt
        # Coda "HAAA" discendente (0.35s)
        var tail: int = int(SR * 0.35)
        var tail_off: int = int(SR * (syll_dur + gap_dur) * float(syll_freqs.size()))
        for i in tail:
                var t2: float = float(i) / SR
                var env2: float = (1.0 - exp(-t2 * 40.0)) * exp(-t2 * 5.5)
                var f2: float = 118.0 * (1.0 - 0.4 * (t2 / 0.35))
                var phase2: float = f2 * t2
                var v2: float = 0.5 * sawtooth_wave(phase2) + 0.5 * triangle_wave(phase2 * 0.5)
                var idx2: int = tail_off + i
                if idx2 < n_total:
                        base[idx2] += 2800.0 / 32767.0 * v2 * env2
        # Drone basso 55Hz sotto tutto (pesantezza "tenebrosa")
        for i in n_total:
                var t3: float = float(i) / SR
                base[i] += 700.0 / 32767.0 * triangle_wave(55.0 * t3) \
                                * exp(-t3 * 1.2) * (1.0 - exp(-t3 * 30.0))
        # Eco cupo: 3 copie ritardate (sala di pietra)
        var out := PackedFloat32Array()
        out.resize(n_total)
        for i in n_total:
                out[i] = base[i]
        var echo_taps: Array[float] = [0.14, 0.28, 0.42]
        var echo_gains: Array[float] = [0.45, 0.25, 0.12]
        for tap in echo_taps.size():
                var d: int = int(SR * echo_taps[tap])
                var g: float = echo_gains[tap]
                for i in range(d, n_total):
                        out[i] += base[i - d] * g
        # Soft-clip finale (guarantisce assenza di clipping)
        for i in n_total:
                out[i] = tanh(out[i] * 1.4) * 0.9
        return out


# ============================================================================
# FIX (pozione magica): TEMA FANTASMA — musica fantasmagorica/suspense in loop
# (~12.6s) che accompagna tutto il periodo dell'effetto fantasma del player.
#
# Caratteristiche (horror ambient a 60 BPM):
#   * Basso drone D2 (73.42 Hz) triangolare con tremolo lento
#   * Battito "cuore" sordo: due colpi profondi per battuta (kick 55 Hz)
#   * Arpeggio diminuito D-F-Bb-Db (D dim7) campanellato e rarefatto
#   * Lamento fantasma: sirena alta (D5) con vibrato lento e detuning
#   * Vento: rumore filtrato con onde lente (swell ogni 2 battute)
#   * Tritono Db5-Ab4 che si alterna al lamento per la tensione
# Loop-friendly: le code degli elementi decadono prima della fine.
# ============================================================================
func _gen_ghost_track() -> PackedFloat32Array:
        var tempo: float = 60.0
        var beat_dur: float = 60.0 / tempo        # 1.0s
        var bar_dur: float = beat_dur * 4.0       # 4.0s
        var num_bars: int = 3                    # ~12.6s totali
        var total: int = int(SR * (bar_dur * float(num_bars) + 0.6))
        var out := PackedFloat32Array()
        out.resize(total)

        # --- Drone basso D2 + tremolo (tutto il brano) ---
        for i in total:
                var t: float = float(i) / SR
                var trem: float = 0.80 + 0.20 * sin(t * TAU * 0.55)
                var drone: float = 0.30 * triangle_wave(t * 73.42) \
                                + 0.12 * triangle_wave(t * 73.42 * 2.0)
                out[i] += drone * trem * 0.55

        # --- Battito di cuore: due colpi per battuta ---
        var thump_dur: float = 0.22
        var n_thump: int = int(SR * thump_dur)
        for bar in num_bars:
                for beat in 4:
                        # Primo colpo sul beat, secondo colpo 0.28s dopo (lub-dub)
                        var base_t: float = bar * bar_dur + float(beat) * beat_dur
                        for rep in 2:
                                var start: int = int(SR * (base_t + float(rep) * 0.28))
                                if rep == 1 and beat % 2 == 1:
                                        continue  # "dub" solo sui beat pari: più raro
                                for i in n_thump:
                                        var idx: int = start + i
                                        if idx >= total:
                                                break
                                        var t: float = float(i) / SR
                                        var env: float = exp(-t * 14.0) * (1.0 - exp(-t * 80.0))
                                        var f: float = 58.0 * exp(-t * 3.0) + 30.0
                                        var v: float = 0.55 * triangle_wave(t * f) \
                                                        + 0.20 * pulse_wave(t * f * 0.5, 0.4)
                                        out[idx] += v * env * 0.5

        # --- Arpeggio diminuito D4-F4-Bb4-Db5 (una nota ogni 2 beat) ---
        var dim_notes := [293.66, 349.23, 466.16, 554.37]
        var note_dur: float = 1.9
        var n_note: int = int(SR * note_dur)
        var note_i: int = 0
        var t_next: float = 0.5
        while t_next < bar_dur * float(num_bars) - note_dur:
                var start: int = int(SR * t_next)
                var freq: float = dim_notes[note_i % dim_notes.size()]
                for i in n_note:
                        var idx: int = start + i
                        if idx >= total:
                                break
                        var t: float = float(i) / SR
                        var env: float = exp(-t * 2.2) * (1.0 - exp(-t * 25.0))
                        # Campanellato: fondamentale + ottava, decay lento
                        var v: float = 0.22 * triangle_wave(t * freq) \
                                        + 0.10 * sine_wave(t * freq * 2.0)
                        out[idx] += v * env
                note_i += 1
                t_next += 2.0 * beat_dur * 0.75

        # --- Lamento fantasma: D5 con vibrato + detuning, swell lenti ---
        for wail in 3:
                var w_start_f: float = 0.8 + float(wail) * 4.1
                var w_dur: float = 3.2
                var start: int = int(SR * w_start_f)
                var n_wail: int = int(SR * w_dur)
                for i in n_wail:
                        var idx: int = start + i
                        if idx >= total:
                                break
                        var t: float = float(i) / SR
                        # Envelope: fade-in lento + fade-out
                        var env: float = minf(t / 0.9, 1.0) * exp(-maxf(t - 0.9, 0.0) * 1.1)
                        # Vibrato lento e profondo
                        var vib: float = 5.5 * sin(t * TAU * 1.6)
                        var f: float = 587.33 + vib
                        # Detuning: due sine quasi uguali (battimenti)
                        var v: float = 0.16 * sine_wave(t * f) \
                                        + 0.16 * sine_wave(t * f * 1.0045)
                        out[idx] += v * env

        # --- Tritono di tensione Db5 + Ab4 (nei bar 2 e 3) ---
        for chord_i in 2:
                var c_start: float = 4.2 + float(chord_i) * 4.0
                var c_dur: float = 3.4
                var start: int = int(SR * c_start)
                var n_ch: int = int(SR * c_dur)
                for i in n_ch:
                        var idx: int = start + i
                        if idx >= total:
                                break
                        var t: float = float(i) / SR
                        var env: float = minf(t / 1.2, 1.0) * exp(-maxf(t - 1.2, 0.0) * 1.3)
                        var v: float = 0.10 * sine_wave(t * 554.37) \
                                        + 0.10 * sine_wave(t * 415.30)
                        out[idx] += v * env

        # --- Vento: rumore con onde lente ---
        for i in total:
                var t: float = float(i) / SR
                var swell: float = 0.5 + 0.5 * sin(t * TAU * 0.24)
                var wind: float = noise_gen() * (0.10 + 0.14 * swell)
                # Filtro passa-basso grezzo: media mobile approssimata
                if i > 0:
                        wind = 0.6 * wind + 0.4 * (out[i - 1] * 0.0 + noise_gen() * 0.1)
                out[i] += wind * (0.5 + 0.5 * swell)

        # --- Normalizzazione + soft clip ---
        var peak: float = 0.0001
        for i in total:
                var a: float = absf(out[i])
                if a > peak:
                        peak = a
        var gain: float = 0.78 / peak
        for i in total:
                out[i] = _soft_clip(out[i] * gain)
        return out


# ============================================================================
# TASK 26 — SFX DI SPARO DEI BOSS: un timbro per ogni tipo di "munizione".
# ============================================================================
# Coerenza col proiettile visibile (Task 22, Projectile._draw_themed):
#   0  BP_NORMAL         -> zap scuro generico (fallback)
#   1  BP_BOULDER        -> TONFO di pietra: grave 90->45Hz + rumble frantumato
#   2  BP_NECRO_BOLT     -> shimmer necro: sine detune 900->280 + coda eterea
#   3  BP_FIREBALL       -> WHOOSH di fiamma: soffio filtrato + crepitio
#   4  BP_WEBSHOT        -> fruscio di seta: doppi burst gate + sibilo corto
#   5  BP_FLESH_CHUNK    -> squelch carne: wobble 95Hz + pops umidi
#   6  BP_INK_SPRAY      -> spruzzo inchiostro: sibilo + bolle in salita
#   7  BP_DRAGON_BREATH  -> soffio del drago: ruggito LP lungo + braci
#   8  BP_GHOST_BOLT     -> bolt etereo: tremolo 440->660->330 con pseudo-echo
#   9  BP_BLOOD_BOLT     -> bolt sangue: sweep 700->200 + gocciolio
#  10  BP_EYE_RAY        -> raggio oculare: zap ascendente 180->1400 + hum
#  11  BP_GHOUL_CLAW     -> raschiata ossea: 3 click + scrape 2kHz
#  12  BP_SPECTRAL_FANG  -> morso spettrale: sibilo + doppio snap
#  13  BP_CULT_ORB       -> orbo del culto: campana oscura 150Hz + armonici
#  14  BP_MIMIC_GOO      -> goo appiccicoso: pop bagnato + coda gocciolante
#  15  BP_RAT_SWARM      -> squittii: 5 chirp 1.8-2.6KHz scaglionati
#  16  BP_WITCH_HEX      -> hex della strega: warble 300->800 vibrato 8Hz
#  17  BP_TWILIGHT_BLADE -> shing metallico: inarmonici 2.1K/3.2K + frusta
# Tutte deterministiche (rng seedato), 0.18-0.45s, peak <= 3000/32767.
func _generate_boss_shoot(kind: int) -> AudioStreamWAV:
        var s := PackedFloat32Array()
        var rng := RandomNumberGenerator.new()
        match kind:
                1:
                        # BP_BOULDER — masso del Golem.
                        rng.seed = 26001
                        var n: int = int(SR * 0.30)
                        var ph: float = 0.0
                        var lp: float = 0.0
                        for i in n:
                                var t: float = float(i) / SR
                                var p: float = t / 0.30
                                var env: float = exp(-t * 9.0)
                                var f: float = 90.0 - 45.0 * p
                                ph += TAU * f / SR
                                var v: float = 0.85 * sin(ph)
                                lp += 0.05 * (rng.randf() * 2.0 - 1.0 - lp)
                                v += 0.85 * lp
                                if i < 110:
                                        v += 0.8 * (rng.randf() * 2.0 - 1.0) \
                                                        * (1.0 - float(i) / 110.0)
                                s.append(2900.0 / 32767.0 * _soft_clip(v * env))
                2:
                        # BP_NECRO_BOLT — bolt necro verde del Lich.
                        rng.seed = 26002
                        var n2: int = int(SR * 0.28)
                        var ph1: float = 0.0
                        var ph2: float = 0.0
                        for i in n2:
                                var t: float = float(i) / SR
                                var p: float = t / 0.28
                                var env: float = sin(PI * minf(p * 1.4, 1.0)) * exp(-t * 5.0)
                                var f: float = 900.0 - 620.0 * p
                                ph1 += TAU * f / SR
                                ph2 += TAU * (f * 1.007 + 3.0 * sin(TAU * 6.0 * t)) / SR
                                var v: float = 0.5 * sin(ph1) + 0.35 * sin(ph2)
                                v += 0.18 * (rng.randf() * 2.0 - 1.0) * exp(-t * 10.0)
                                s.append(2600.0 / 32767.0 * _soft_clip(v * env))
                3:
                        # BP_FIREBALL — palla di fuoco del Demone.
                        rng.seed = 26003
                        var n3: int = int(SR * 0.32)
                        var lp3: float = 0.0
                        var bp3: float = 0.0
                        var bp3p: float = 0.0
                        for i in n3:
                                var t: float = float(i) / SR
                                var p: float = t / 0.32
                                var env: float = sin(PI * minf(p * 1.15, 1.0))
                                var res_f: float = 900.0 - 500.0 * p
                                var w: float = TAU * res_f / SR
                                lp3 += 0.08 * (rng.randf() * 2.0 - 1.0 - lp3)
                                bp3p = bp3
                                bp3 += w * (lp3 - bp3)
                                var v: float = 1.5 * (bp3 - bp3p * 0.55)
                                v += 0.35 * sin(TAU * (110.0 - 50.0 * p) * t)
                                if rng.randf() < 0.02:
                                        v += 0.5 * (rng.randf() * 2.0 - 1.0)
                                s.append(2700.0 / 32767.0 * _soft_clip(v * env))
                4:
                        # BP_WEBSHOT — sputo di ragnatela del Ragno.
                        rng.seed = 26004
                        var n4: int = int(SR * 0.18)
                        var lp4: float = 0.0
                        for i in n4:
                                var t: float = float(i) / SR
                                var p: float = t / 0.18
                                # due burst "gate" (flick-flick) + sibilo di seta
                                var gate: float = exp(-pow(maxf(p - 0.05, 0.0) * 9.0, 2.0)) \
                                                + 0.8 * exp(-pow(maxf(p - 0.45, 0.0) * 9.0, 2.0))
                                lp4 += 0.22 * (rng.randf() * 2.0 - 1.0 - lp4)
                                var hiss: float = 1.8 * lp4
                                var v: float = hiss * gate + 0.25 * sin(TAU * 2600.0 * t) * gate * 0.4
                                s.append(2400.0 / 32767.0 * _soft_clip(v))
                5:
                        # BP_FLESH_CHUNK — brandello dell'Abominione.
                        rng.seed = 26005
                        var n5: int = int(SR * 0.25)
                        var ph5: float = 0.0
                        var lp5: float = 0.0
                        for i in n5:
                                var t: float = float(i) / SR
                                var p: float = t / 0.25
                                var env: float = exp(-t * 7.0)
                                var f5: float = 95.0 + 28.0 * sin(TAU * 13.0 * t)
                                ph5 += TAU * f5 / SR
                                var v: float = 0.9 * sin(ph5)
                                lp5 += 0.12 * (rng.randf() * 2.0 - 1.0 - lp5)
                                v += 1.1 * lp5
                                if rng.randf() < 0.012:
                                        v += 0.9 * (rng.randf() * 2.0 - 1.0)
                                s.append(2500.0 / 32767.0 * _soft_clip(v * env))
                6:
                        # BP_INK_SPRAY — spruzzo d'inchiostro del Kraken.
                        rng.seed = 26006
                        var n6: int = int(SR * 0.30)
                        var lp6: float = 0.0
                        var bub_t: float = -1.0
                        var bub_f: float = 0.0
                        for i in n6:
                                var t: float = float(i) / SR
                                var p: float = t / 0.30
                                var env: float = sin(PI * minf(p * 1.2, 1.0))
                                lp6 += 0.16 * (rng.randf() * 2.0 - 1.0 - lp6)
                                var v: float = 1.2 * lp6
                                if bub_t < 0.0 and rng.randf() < 0.004:
                                        bub_t = t
                                        bub_f = 300.0 + 500.0 * rng.randf()
                                if bub_t >= 0.0:
                                        var bt: float = t - bub_t
                                        if bt < 0.05:
                                                v += 0.6 * sin(TAU * bub_f * bt) \
                                                                * exp(-bt * 60.0)
                                        else:
                                                bub_t = -1.0
                                s.append(2400.0 / 32767.0 * _soft_clip(v * env))
                7:
                        # BP_DRAGON_BREATH — soffio del Drago.
                        rng.seed = 26007
                        var n7: int = int(SR * 0.45)
                        var lp7: float = 0.0
                        for i in n7:
                                var t: float = float(i) / SR
                                var p: float = t / 0.45
                                var env: float = pow(sin(PI * p), 0.6)
                                lp7 += 0.06 * (rng.randf() * 2.0 - 1.0 - lp7)
                                var v: float = 1.6 * lp7
                                v += 0.5 * sin(TAU * 70.0 * t) * (0.6 + 0.4 * sin(TAU * 11.0 * t))
                                if rng.randf() < 0.015:
                                        v += 0.6 * (rng.randf() * 2.0 - 1.0)
                                s.append(2800.0 / 32767.0 * _soft_clip(v * env))
                8:
                        # BP_GHOST_BOLT — bolt etereo del Signore Spettrale.
                        rng.seed = 26008
                        var n8: int = int(SR * 0.30)
                        var ph8: float = 0.0
                        for i in n8:
                                var t: float = float(i) / SR
                                var p: float = t / 0.30
                                var env: float = sin(PI * p)
                                var f8: float = 440.0 + 220.0 * sin(PI * p * 2.0) - 110.0 * p
                                ph8 += TAU * f8 / SR
                                var trem: float = 0.55 + 0.45 * sin(TAU * 9.0 * t)
                                var v: float = 0.85 * sin(ph8) * trem
                                # pseudo-echo etereo (coda ritardata)
                                if i > 2205:
                                        var v8e: float = s[i - 2205] * 0.28
                                        v += v8e
                                s.append(2300.0 / 32767.0 * _soft_clip(v * env))
                9:
                        # BP_BLOOD_BOLT — bolt di sangue del Vampiro.
                        rng.seed = 26009
                        var n9: int = int(SR * 0.20)
                        var ph9: float = 0.0
                        var lp9: float = 0.0
                        for i in n9:
                                var t: float = float(i) / SR
                                var p: float = t / 0.20
                                var env: float = exp(-t * 11.0)
                                var f9: float = 700.0 - 500.0 * p
                                ph9 += TAU * f9 / SR
                                var v: float = 0.9 * sin(ph9) + 0.3 * sin(ph9 * 2.0)
                                lp9 += 0.30 * (rng.randf() * 2.0 - 1.0 - lp9)
                                if p > 0.55:
                                        v += 0.8 * lp9 * exp(-(p - 0.55) * 6.0)
                                s.append(2500.0 / 32767.0 * _soft_clip(v * env))
                10:
                        # BP_EYE_RAY — raggio oculare del Beholder.
                        rng.seed = 26010
                        var n10: int = int(SR * 0.25)
                        var ph10: float = 0.0
                        for i in n10:
                                var t: float = float(i) / SR
                                var p: float = t / 0.25
                                var env: float = minf(t / 0.015, 1.0) * exp(-t * 7.0)
                                var f10: float = 180.0 + 1220.0 * pow(p, 0.65)
                                ph10 += TAU * f10 / SR
                                var v: float = 0.8 * sawtooth_wave(ph10) + 0.25 * sin(ph10 * 2.0)
                                s.append(2400.0 / 32767.0 * _soft_clip(v * env))
                11:
                        # BP_GHOUL_CLAW — artigli ossei del Signore Ghoul.
                        rng.seed = 26011
                        var n11: int = int(SR * 0.20)
                        var lp11: float = 0.0
                        var bp11: float = 0.0
                        var bp11p: float = 0.0
                        for i in n11:
                                var t: float = float(i) / SR
                                var p: float = t / 0.20
                                var env: float = exp(-t * 12.0)
                                var w11: float = TAU * 2100.0 / SR
                                lp11 += 0.30 * (rng.randf() * 2.0 - 1.0 - lp11)
                                bp11p = bp11
                                bp11 += w11 * (lp11 - bp11)
                                var v: float = 1.3 * (bp11 - bp11p * 0.5)
                                # tre click d'artiglio scaglionati
                                for k in 3:
                                        var tk: float = 0.012 + 0.055 * float(k)
                                        if t >= tk and t < tk + 0.010:
                                                v += 0.9 * (1.0 - (t - tk) / 0.010) \
                                                                * sin(TAU * 1400.0 * (t - tk))
                                s.append(2400.0 / 32767.0 * _soft_clip(v * env))
                12:
                        # BP_SPECTRAL_FANG — zanna dello Spettrale Alfa.
                        rng.seed = 26012
                        var n12: int = int(SR * 0.20)
                        var lp12: float = 0.0
                        for i in n12:
                                var t: float = float(i) / SR
                                var p: float = t / 0.20
                                var env: float = sin(PI * p)
                                lp12 += 0.24 * (rng.randf() * 2.0 - 1.0 - lp12)
                                var v: float = 1.2 * lp12 * (0.4 + 0.6 * p)
                                # doppio snap del morso
                                for k in 2:
                                        var tk: float = 0.06 + 0.06 * float(k)
                                        if t >= tk and t < tk + 0.008:
                                                v += 1.1 * (1.0 - (t - tk) / 0.008)
                                s.append(2400.0 / 32767.0 * _soft_clip(v * env))
                13:
                        # BP_CULT_ORB — orbo oscuro dell'Araldo del Culto.
                        rng.seed = 26013
                        var n13: int = int(SR * 0.38)
                        for i in n13:
                                var t: float = float(i) / SR
                                var p: float = t / 0.38
                                var env: float = minf(t / 0.02, 1.0) * exp(-t * 4.5)
                                # campana oscura: fondamentale + inarmonici
                                var v: float = 0.7 * sin(TAU * 150.0 * t) \
                                                + 0.35 * sin(TAU * 414.0 * t) \
                                                + 0.22 * sin(TAU * 590.0 * t)
                                # hum corale sotto (quinte)
                                v += 0.25 * sin(TAU * 225.0 * t) * (0.5 + 0.5 * sin(TAU * 0.8 * t))
                                s.append(2500.0 / 32767.0 * _soft_clip(v * env))
                14:
                        # BP_MIMIC_GOO — melma del Mimic Colossale.
                        rng.seed = 26014
                        var n14: int = int(SR * 0.30)
                        var lp14: float = 0.0
                        var ph14: float = 0.0
                        for i in n14:
                                var t: float = float(i) / SR
                                var p: float = t / 0.30
                                var env: float = exp(-t * 6.0)
                                # pop bagnato d'attacco (bolla che scoppia)
                                var f14: float = 260.0 * exp(-t * 18.0) + 60.0
                                ph14 += TAU * f14 / SR
                                var v: float = 0.9 * sin(ph14) * exp(-t * 14.0)
                                lp14 += 0.10 * (rng.randf() * 2.0 - 1.0 - lp14)
                                v += 0.9 * lp14 * (0.3 + 0.7 * p)
                                # coda gocciolante
                                if p > 0.5 and rng.randf() < 0.006:
                                        v += 0.7
                                s.append(2300.0 / 32767.0 * _soft_clip(v * env))
                15:
                        # BP_RAT_SWARM — topi del Re dei Ratti.
                        rng.seed = 26015
                        var n15: int = int(SR * 0.30)
                        var chirp_t: float = -1.0
                        var chirp_f: float = 0.0
                        for i in n15:
                                var t: float = float(i) / SR
                                var v: float = 0.0
                                if chirp_t < 0.0 and rng.randf() < 0.0035 * (0.4 + t):
                                        chirp_t = t
                                        chirp_f = 1800.0 + 800.0 * rng.randf()
                                if chirp_t >= 0.0:
                                        var ct: float = t - chirp_t
                                        if ct < 0.045:
                                                var f15: float = chirp_f * (1.0 + 0.35 * sin(TAU * 60.0 * ct))
                                                v += 0.8 * sin(TAU * f15 * ct) * exp(-ct * 70.0)
                                        else:
                                                chirp_t = -1.0
                                s.append(2200.0 / 32767.0 * _soft_clip(v))
                16:
                        # BP_WITCH_HEX — hex della Strega Suprema.
                        rng.seed = 26016
                        var n16: int = int(SR * 0.35)
                        var ph16: float = 0.0
                        var ph16b: float = 0.0
                        for i in n16:
                                var t: float = float(i) / SR
                                var p: float = t / 0.35
                                var env: float = sin(PI * minf(p * 1.1, 1.0))
                                var f16: float = 300.0 + 500.0 * p
                                ph16 += TAU * (f16 + 26.0 * sin(TAU * 8.0 * t)) / SR
                                ph16b += TAU * (f16 * 1.5) / SR
                                var v: float = 0.55 * sin(ph16) + 0.30 * sin(ph16b)
                                s.append(2300.0 / 32767.0 * _soft_clip(v * env))
                17:
                        # BP_TWILIGHT_BLADE — lama d'ombra del Cavaliere Crepuscolare.
                        rng.seed = 26017
                        var n17: int = int(SR * 0.22)
                        var lp17: float = 0.0
                        for i in n17:
                                var t: float = float(i) / SR
                                var p: float = t / 0.22
                                var env: float = minf(t / 0.008, 1.0) * exp(-t * 14.0)
                                # shing: inarmonici metallici che svaniscono
                                var v: float = 0.5 * sin(TAU * 2100.0 * t) \
                                                + 0.35 * sin(TAU * 3160.0 * t) \
                                                + 0.20 * sin(TAU * 4230.0 * t)
                                # frusta d'aria (rumore che scende)
                                lp17 += 0.34 * (rng.randf() * 2.0 - 1.0 - lp17)
                                v += 0.7 * lp17 * (1.0 - p)
                                s.append(2400.0 / 32767.0 * _soft_clip(v * env))
                _:
                        # 0 / BP_NORMAL — zap scuro generico.
                        rng.seed = 26000
                        var n0: int = int(SR * 0.16)
                        var ph0: float = 0.0
                        for i in n0:
                                var t: float = float(i) / SR
                                var p: float = t / 0.16
                                var env: float = exp(-t * 16.0)
                                var f0: float = 520.0 - 300.0 * p
                                ph0 += TAU * f0 / SR
                                var v: float = 0.8 * sawtooth_wave(ph0)
                                s.append(2400.0 / 32767.0 * _soft_clip(v * env))
        return _samples_to_stream(s)
