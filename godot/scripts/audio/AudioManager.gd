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
        POTION_GULP
}
const SOUND_TYPE_COUNT: int = 26

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

        # Pre-synthesize every SFX and every music track (avoid runtime hitches).
        _sfx_streams.resize(SOUND_TYPE_COUNT)
        for i in SOUND_TYPE_COUNT:
                _sfx_streams[i] = _generate_sfx(i as SoundType)

        _music_streams.resize(MUSIC_TRACK_COUNT)
        for i in MUSIC_TRACK_COUNT:
                _music_streams[i] = _generate_track(i)


# ============================================================================
# PUBLIC API  (mirrors the public methods of AudioManager)
# ============================================================================

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
# Music track synthesis (port of generateTrack(int) and its dispatchers)
# ============================================================================
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


# --- Epic chalice theme: "Trionfo d'Oro", ~9.5s (loop = durata esatta del
# calice, 9500ms) ------------------------------------------------------------
# FIX (musica calice più epica): la vecchia versione erano solo 2 accordi
# sostenuti (C maj -> G maj, 3s ciascuno) senza ritmo né melodia. Nuova
# fanfara eroica completa, sintetizzata per strati:
#   0.0-1.0s  INTRO   - rullo di timpani crescente + drone C che si apre
#   1.0-3.0s  TEMA A  - fanfara di ottoni (G-G-DO... arco trionfale)
#                       basso C-Am-G, timpani sui beat, rullante
#   3.0-5.0s  TEMA A' - variazione discendente F-G, semi-cadenza sul finale
#   5.0-6.5s  BUILD   - scala ascendente C4->G5 in ottavi + crescendo
#   6.5-9.5s  CLIMAX  - tema un'ottava sopra, armonia a 3 voci (C-E-G),
#                       basso in ottavi, batteria completa, accordo finale
#                       con crash che sfuma nel riavvio del loop.
# Voci: lead "ottoni" (pulse 0.32 + saw detune), armonia (pulse 0.5 -6dB),
# basso (triangle + sub), timpani (60Hz thump + rumore), rullante, hi-hat,
# crash (rumore con decadimento lungo).
func _gen_epic_chalice() -> PackedFloat32Array:
        const DUR: float = 9.5            # secondi (loop = durata calice)
        const BPM: float = 120.0
        const BEAT: float = 60.0 / BPM    # 0.5s
        var total: int = int(SR * DUR)
        var out := PackedFloat32Array()
        out.resize(total)

        # --- Note: [start_beat, dur_beats, freq, gain] -----------------------
        # Lead (ottoni): tema trionfale.
        const LEAD: Array = [
                # TEMA A (b2-6): pickup G-G, arco C5, risposta E5-D5
                [2.0, 0.5, 392.00, 0.30], [2.5, 0.5, 392.00, 0.30],
                [3.0, 0.75, 523.25, 0.32], [3.75, 0.25, 493.88, 0.28],
                [4.0, 1.0, 523.25, 0.32],
                [5.0, 0.5, 659.25, 0.30], [5.5, 0.5, 587.33, 0.28],
                # TEMA A' (b6-10): F5-E5, discesa D5-C5, giro G4
                [6.0, 0.75, 698.46, 0.30], [6.75, 0.25, 659.25, 0.28],
                [7.0, 1.0, 587.33, 0.30],
                [8.0, 0.5, 523.25, 0.28], [8.5, 0.5, 587.33, 0.28],
                [9.0, 1.0, 392.00, 0.30],
                # BUILD (b10-13): scala ascendente in ottavi (12 x 0.25 beat)
                [10.00, 0.25, 261.63, 0.26], [10.25, 0.25, 293.66, 0.26],
                [10.50, 0.25, 329.63, 0.26], [10.75, 0.25, 349.23, 0.26],
                [11.00, 0.25, 392.00, 0.26], [11.25, 0.25, 440.00, 0.26],
                [11.50, 0.25, 493.88, 0.26], [11.75, 0.25, 523.25, 0.26],
                [12.00, 0.25, 587.33, 0.27], [12.25, 0.25, 659.25, 0.27],
                [12.50, 0.25, 698.46, 0.27], [12.75, 0.25, 783.99, 0.28],
                # CLIMAX (b13-19): tema un'ottava sopra
                [13.0, 0.75, 1046.50, 0.32], [13.75, 0.25, 987.77, 0.28],
                [14.0, 1.0, 1046.50, 0.32],
                [15.0, 0.5, 880.00, 0.30], [15.5, 0.5, 987.77, 0.30],
                [16.0, 1.5, 1046.50, 0.34],
        ]
        # Armonia (3 voci sotto il lead nel climax + accodi sezione A).
        const HARMONY: Array = [
                # TEMA A: accordi tenuti C (E4+G4), Am (C4+E4), G (B3+D4)
                [3.0, 2.0, 329.63, 0.14], [3.0, 2.0, 392.00, 0.12],
                [5.0, 1.0, 261.63, 0.13], [5.0, 1.0, 329.63, 0.11],
                # TEMA A': F (A3+C4), G (B3+D4)
                [6.0, 2.0, 220.00, 0.13], [6.0, 2.0, 261.63, 0.11],
                [8.0, 2.0, 246.94, 0.13], [8.0, 2.0, 293.66, 0.11],
                # CLIMAX: triade completa C-E-G sotto il tema
                [13.0, 2.0, 523.25, 0.15], [13.0, 2.0, 659.25, 0.13],
                [13.0, 2.0, 783.99, 0.11],
                [15.0, 1.0, 523.25, 0.13], [15.0, 1.0, 698.46, 0.12],
                [16.0, 1.5, 523.25, 0.15], [16.0, 1.5, 659.25, 0.13],
                # Accordo finale C maggiore largo (b17.5-19)
                [17.5, 1.5, 523.25, 0.16], [17.5, 1.5, 659.25, 0.14],
                [17.5, 1.5, 783.99, 0.12],
        ]
        # Basso (progressione per beat: C-C-Am-G | F-F-G-G | pedale C | climax).
        const BASS: Array = [
                [2.0, 0.9, 65.41, 0.20], [3.0, 0.9, 65.41, 0.20],
                [4.0, 0.9, 55.00, 0.19], [5.0, 0.9, 49.00, 0.19],
                [6.0, 0.9, 43.65, 0.20], [7.0, 0.9, 43.65, 0.20],
                [8.0, 0.9, 49.00, 0.20], [9.0, 0.9, 49.00, 0.20],
                # pedale di bordone sotto la scala
                [10.0, 3.0, 65.41, 0.20],
                # climax: ottavi root-ottava (pompa marziale)
                [13.0, 0.45, 65.41, 0.22], [13.5, 0.45, 130.81, 0.18],
                [14.0, 0.45, 65.41, 0.22], [14.5, 0.45, 130.81, 0.18],
                [15.0, 0.45, 43.65, 0.21], [15.5, 0.45, 87.31, 0.17],
                [16.0, 0.45, 49.00, 0.21], [16.5, 0.45, 98.00, 0.17],
                [17.0, 0.45, 65.41, 0.22],
                # finale: C tenuto
                [17.5, 1.5, 65.41, 0.22],
        ]
        # Timpani: [beat, accent] — beat marcati = accenti forti.
        const TIMPANI: Array = [
                [2.0, 1.0], [3.0, 0.6], [4.0, 0.6], [5.0, 0.6],
                [6.0, 1.0], [7.0, 0.6], [8.0, 0.6], [9.0, 0.6],
                [10.0, 0.8], [11.0, 0.8], [12.0, 0.9],
                [13.0, 1.0], [13.5, 0.5], [14.0, 0.7], [14.5, 0.5],
                [15.0, 0.8], [15.5, 0.5], [16.0, 0.8], [16.5, 0.5],
                [17.0, 0.9], [17.5, 1.0],
        ]
        # Rullante: backbeat (beat 3 e 5 di ogni misura da 4).
        const SNARE: Array = [
                [3.0, 0.7], [5.0, 0.7], [7.0, 0.7], [9.0, 0.7],
                [11.0, 0.6], [12.5, 0.8],
                [13.5, 0.8], [14.5, 0.8], [15.5, 0.8], [16.5, 0.8],
        ]
        # Crash/piatto: inizio tema, inizio climax, accordo finale.
        const CRASH: Array = [[2.0, 0.30], [13.0, 0.34], [17.5, 0.38]]

        # --- Rendering --------------------------------------------------------
        # Strumento "ottoni": pulse 0.32 + saw detune +2 cent, attacco 12ms,
        # rilascio 45ms, vibrato 5.5Hz sulle note lunghe.
        for note in LEAD:
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
                        var env: float = (1.0 - exp(-t * 180.0)) \
                                        * (1.0 - exp(-(dur_s - t) * 90.0))
                        var vib: float = 1.0 + 0.0035 * sin(TAU * 5.5 * t)
                        phase += freq * vib / SR
                        var brass: float = 0.62 * pulse_wave(phase, 0.32) \
                                        + 0.38 * sawtooth_wave(phase * 1.0012)
                        out[idx] += gain * brass * env
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
                        var env: float = (1.0 - exp(-t * 120.0)) \
                                        * (1.0 - exp(-(dur_s - t) * 60.0))
                        phase += freq / SR
                        out[idx] += gain * pulse_wave(phase, 0.5) * env
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
                        var env: float = (1.0 - exp(-t * 60.0)) \
                                        * (1.0 - exp(-(dur_s - t) * 25.0))
                        phase += freq / SR
                        out[idx] += gain * (0.7 * triangle_wave(phase) \
                                        + 0.3 * pulse_wave(phase, 0.5)) * env
        # Intro: rullo di timpani crescente (b0-b2) + drone C che si apre.
        for i in int(1.0 * SR):
                var t: float = float(i) / SR
                var prog: float = t / 1.0
                var roll_rate: float = 6.0 + 18.0 * prog
                var roll: float = (1.0 if fmod(t * roll_rate, 1.0) < 0.25 else 0.0)
                var thump: float = roll * triangle_wave(t * 55.0) \
                                * exp(-fmod(t * roll_rate, 1.0) * 14.0)
                var drone: float = 0.16 * prog * sawtooth_wave(t * 130.81) \
                                * (0.6 + 0.4 * prog)
                out[i] += (0.5 * prog * thump + drone)
        for hit in TIMPANI:
                var start_s: float = float(hit[0]) * BEAT
                var accent: float = float(hit[1])
                var i0: int = int(start_s * SR)
                for i in int(0.16 * SR):
                        var idx: int = i0 + i
                        if idx >= total:
                                break
                        var t: float = float(i) / SR
                        var thump: float = 0.5 * triangle_wave(t * 62.0) \
                                        * exp(-t * 26.0)
                        var skin: float = 0.12 * noise_gen() * exp(-t * 60.0)
                        out[idx] += accent * (thump + skin)
        for hit in SNARE:
                var start_s: float = float(hit[0]) * BEAT
                var accent: float = float(hit[1])
                var i0: int = int(start_s * SR)
                for i in int(0.10 * SR):
                        var idx: int = i0 + i
                        if idx >= total:
                                break
                        var t: float = float(i) / SR
                        out[idx] += accent * 0.20 * noise_gen() * exp(-t * 34.0)
        # Hi-hat in ottavi nel climax (b13-b17.5).
        var hh_beat: float = 13.0
        while hh_beat < 17.5:
                var i0: int = int(hh_beat * BEAT * SR)
                for i in int(0.05 * SR):
                        var idx: int = i0 + i
                        if idx >= total:
                                break
                        var t: float = float(i) / SR
                        out[idx] += 0.07 * noise_gen() * exp(-t * 90.0)
                hh_beat += 0.5
        # Crash di piatto (rumore con lunga coda).
        for hit in CRASH:
                var start_s: float = float(hit[0]) * BEAT
                var gain: float = float(hit[1])
                var i0: int = int(start_s * SR)
                for i in int(1.2 * SR):
                        var idx: int = i0 + i
                        if idx >= total:
                                break
                        var t: float = float(i) / SR
                        # shimmer: rumore modulato ~6kHz (campionamento radente)
                        var ring: float = 0.6 + 0.4 * sin(TAU * 4730.0 * t)
                        out[idx] += gain * noise_gen() * ring * exp(-t * 3.2)

        # Mix finale: soft clip + guadagno globale.
        for i in total:
                out[i] = 0.85 * _soft_clip(out[i] * 0.9)
        return out


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
