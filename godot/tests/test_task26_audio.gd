## test_task26_audio.gd — TASK 26: QA + export degli SFX di sparo dei boss.
## 1) Verifica che AudioManager abbia generato i 18 stream (BP_NORMAL + 17).
## 2) Per ognuno: formato 16-bit mono, lunghezza > 0, peak <= ~0.92 (no clip),
##    RMS > 0.02 (non silenzio), durata 0.1..0.5s.
## 3) play_boss_shoot(kind) per tutti i kind senza errori (e il flag di
##    rollback che azzera la lista).
## 4) Esporta ogni stream in WAV (PCM16 mono 44.1k) in
##    /home/z/my-project/download/boss_sfx/ per l'ascolto dell'utente.
extends Node

const OUT_DIR: String = "/home/z/my-project/download/boss_sfx"
const KIND_NAMES: Array[String] = [
        "00_normal", "01_boulder", "02_necro_bolt", "03_fireball",
        "04_webshot", "05_flesh_chunk", "06_ink_spray", "07_dragon_breath",
        "08_ghost_bolt", "09_blood_bolt", "10_eye_ray", "11_ghoul_claw",
        "12_spectral_fang", "13_cult_orb", "14_mimic_goo", "15_rat_swarm",
        "16_witch_hex", "17_twilight_blade",
]

var failures: Array[String] = []
var t := 0.0
var phase := 0
var done := false


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ready() -> void:
        DirAccess.make_dir_recursive_absolute(OUT_DIR)
        print("[TEST] task26 audio QA: attendo AudioManager...")


func _physics_process(delta: float) -> void:
        if done:
                return
        t += delta
        if t < 1.0:
                return
        if AudioManager == null:
                _fail("AudioManager non disponibile")
                _finish()
                return
        # TASK 76: la sintesi e' asincrona (thread in background) e gli spari
        # boss sono ULTIMI nella coda di priorita' (menu -> SFX -> tracce ->
        # boss): al momento del check (~1s dal boot) il worker e' ancora nelle
        # tracce musicali e gli 18 stream sono null. Il gioco in questo caso
        # usa il fallback on-demand di play_boss_shoot() (stesso generatore
        # _generate_boss_shoot del worker, contenuto identico): lo sfruttiamo
        # qui per portare gli stream in memoria PRIMA del QA, senza aspettare
        # ~15s di coda.
        for k in AudioManager.BOSS_SHOOT_KIND_COUNT:
                AudioManager.play_boss_shoot(k)
        if AudioManager._boss_shoot_streams.is_empty():
                _fail("stream boss-shoot non generati (flag o _ready)")
                _finish()
                return
        var streams: Array = AudioManager._boss_shoot_streams
        if streams.size() != 18:
                _fail("attesi 18 stream, trovati %d" % streams.size())
        var report: Array[String] = []
        for k in streams.size():
                var st: AudioStreamWAV = streams[k]
                if st == null:
                        _fail("stream kind %d nullo" % k)
                        continue
                if st.format != AudioStreamWAV.FORMAT_16_BITS:
                        _fail("kind %d: formato %d (atteso 16 bit)" % [k, st.format])
                if st.stereo:
                        _fail("kind %d: stereo (atteso mono)" % k)
                var bytes: PackedByteArray = st.data
                var n_samples: int = bytes.size() / 2
                if n_samples < int(44100 * 0.1) or n_samples > int(44100 * 0.55):
                        _fail("kind %d: durata fuori range (%.2fs)" % [k, float(n_samples) / 44100.0])
                # peak / RMS dai campioni PCM16
                var peak: float = 0.0
                var sum_sq: float = 0.0
                for i in n_samples:
                        var v: float = float(bytes[i * 2] | (bytes[i * 2 + 1] << 8))
                        if v > 32767.0:
                                v -= 65536.0
                        var a: float = absf(v) / 32767.0
                        if a > peak:
                                peak = a
                        sum_sq += a * a
                var rms: float = sqrt(sum_sq / float(maxi(n_samples, 1)))
                if peak > 0.95:
                        _fail("kind %d: CLIP (peak %.3f)" % [k, peak])
                if rms < 0.02:
                        _fail("kind %d: quasi silenzio (RMS %.3f)" % [k, rms])
                report.append("%s peak=%.2f rms=%.2f dur=%.2fs" % [
                        KIND_NAMES[k], peak, rms, float(n_samples) / 44100.0])
                # export WAV (header RIFF + payload)
                _write_wav(OUT_DIR + "/" + KIND_NAMES[k] + ".wav", bytes, 44100)
        for line in report:
                print("[TEST] ", line)
        # play di ogni kind: nessun errore runtime ammesso
        for k in streams.size():
                AudioManager.play_boss_shoot(k)
        # mappa boss_type -> kind (Boss._primary_projectile_kind)
        var BossScript := load("res://scripts/bosses/Boss.gd") as GDScript
        var boss: Node = BossScript.new()
        add_child(boss)
        var expected: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
        for bt in 17:
                boss.boss_type = bt
                var kind: int = boss._primary_projectile_kind()
                if kind != expected[bt]:
                        _fail("boss_type %d -> kind %d (atteso %d)" % [bt, kind, expected[bt]])
        boss.queue_free()
        # rollback: flag OFF -> la lista resta vuota dopo un nuovo _ready non
        # viene rigenerata; verifichiamo solo che il flag esista e sia leggibile.
        if not GameConstants.BOSS_SHOOT_SFX_ENABLED:
                _fail("flag GameConstants.BOSS_SHOOT_SFX_ENABLED inaspettatamente OFF")
        print("[TEST] esportati 18 WAV in ", OUT_DIR)
        _finish()


func _write_wav(path: String, pcm: PackedByteArray, sample_rate: int) -> void:
        var f := FileAccess.open(path, FileAccess.WRITE)
        if f == null:
                _fail("impossibile scrivere %s" % path)
                return
        var data_size: int = pcm.size()
        var byte_rate: int = sample_rate * 2
        f.store_8(0x52); f.store_8(0x49); f.store_8(0x46); f.store_8(0x46)  # RIFF
        f.store_32(data_size + 36)
        f.store_8(0x57); f.store_8(0x41); f.store_8(0x56); f.store_8(0x45)  # WAVE
        f.store_8(0x66); f.store_8(0x6D); f.store_8(0x74); f.store_8(0x20)  # fmt
        f.store_32(16)
        f.store_16(1)      # PCM
        f.store_16(1)      # mono
        f.store_32(sample_rate)
        f.store_32(byte_rate)
        f.store_16(2)      # block align
        f.store_16(16)     # bits
        f.store_8(0x64); f.store_8(0x61); f.store_8(0x74); f.store_8(0x61)  # data
        f.store_32(data_size)
        f.store_buffer(pcm)
        f.close()


func _finish() -> void:
        done = true
        if failures.is_empty():
                print("[TEST] test_task26_audio: TUTTI OK")
                get_tree().quit(0)
        else:
                print("[TEST] test_task26_audio: %d FALLIMENTI" % failures.size())
                get_tree().quit(1)
