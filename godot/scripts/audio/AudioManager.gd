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
        BLOOD_SPLAT, MINE_BOUNCE, POTION_DRINK, LIGHTNING, SCEPTER_PICKUP
}
const SOUND_TYPE_COUNT: int = 25

# --- Music track indices (mirrors AudioManager.h) ---------------------------
const TRACK_LEVEL_BASE:   int = 0    # tracks 0..3 = levels
const TRACK_BOSS:          int = 4
const TRACK_PORTAL:        int = 5
const TRACK_EPIC_CHALICE:  int = 6    # jingle (one-shot, separate channel)
const TRACK_EPIC_SCEPTER:  int = 7    # jingle (one-shot, separate channel)
const TRACK_MENU:          int = 8    # main-menu music (loop)
const MUSIC_TRACK_COUNT:   int = 9

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

# Current track index for the music channel (or -1 if stopped).
var _current_music_track: int = -1
# True if the epic channel is currently playing a jingle.
var _epic_playing: bool = false

# Master switch (mirrors Game::musicEnabled).
var music_enabled: bool = true


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


# Play a one-shot epic jingle on the dedicated channel.
# track_idx must be TRACK_EPIC_CHALICE, TRACK_EPIC_SCEPTER or TRACK_MENU.
func play_epic_music(track_idx: int) -> void:
        if track_idx < TRACK_EPIC_CHALICE or track_idx > TRACK_MENU:
                return
        if _epic_playing and _epic_player.playing:
                return
        _epic_player.stream = _music_streams[track_idx]
        _epic_player.play()
        _epic_playing = true


# Stop the epic jingle (if playing).
func stop_epic_music() -> void:
        _epic_player.stop()
        _epic_playing = false


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
        # FIX (musiche troppo brevi e ripetitive): estese da 32 a 64 barre
        # (~2.5 min per traccia a 100 BPM). Struttura AABA:
        #   barre 0-15:  Verse A (progressione i-VI-III-VII)
        #   barre 16-31: Verse A' (stessa progressione, variazione melodica)
        #   barre 32-47: Bridge B (progressione IV-III-VI-V, modulazione)
        #   barre 48-63: Verse A'' (ritorno, con fill di batteria finale)
        var num_bars: int = 64
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
                # Sezione coro: ogni 8 barre (es. 8-11, 24-27, 56-59) — più pieno
                var is_chorus: bool = ((bar >= 8 and bar <= 11) or
                                       (bar >= 24 and bar <= 27) or
                                       (bar >= 56 and bar <= 59))
                # Variazione melodica: il pattern del lead cambia ogni 16 barre
                # per evitare la sensazione di loop ripetitivo.
                var lead_pattern: int = (bar / 16) % 3  # 0, 1, 2
                # Fill di batteria sull'ultima barra di ogni sezione (7, 15, 31, 47, 63)
                var is_fill_bar: bool = (bar == 7 or bar == 15 or bar == 31 or bar == 47 or bar == 63)
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


# --- Epic chalice jingle: golden hero fanfare, ~6s ---------------------------
# Bright major chords (C maj -> G maj), 3-voice orchestration:
# lead pulse + pad saw + triangle bass.
func _gen_epic_chalice() -> PackedFloat32Array:
        var total: int = int(SR * 6.0)
        var out := PackedFloat32Array()
        out.resize(total)
        # Two chords: C major (C4-E4-G4) and G major (G3-B3-D4)
        var chords := [
                [261.63, 329.63, 392.00],   # C maj
                [196.00, 246.94, 293.66],   # G maj
        ]
        var chord_dur: float = 3.0  # 3 seconds each
        var n_per_chord: int = int(SR * chord_dur)
        for c_idx in chords.size():
                var chord: Array = chords[c_idx]
                for i in n_per_chord:
                        var t: float = float(i) / SR
                        # Slow attack + long decay
                        var env: float = (1.0 - exp(-t * 4.0)) * exp(-t * 0.6)
                        var lead: float = 0.0
                        var pad: float = 0.0
                        var bass: float = 0.0
                        # Lead: top note pulse, melody-like
                        lead = 0.30 * pulse_wave(t * chord[2], 0.5)
                        # Pad: mid note saw (warm)
                        pad = 0.20 * sawtooth_wave(t * chord[1])
                        # Bass: root note triangle one octave down
                        bass = 0.25 * triangle_wave(t * chord[0] * 0.5)
                        var v: float = (lead + pad + bass) * env
                        out[c_idx * n_per_chord + i] = v * 0.5
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
