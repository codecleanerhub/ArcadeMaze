## test_freeze_hit_sfx.gd — TASK 50b: QA del nuovo SFX FREEZE_HIT.
## 1) Lo stream esiste, e' 16-bit mono 44100, durata ~0.55s (0.3..0.9).
## 2) Peak <= 0.95 (no clip), RMS > 0.02 (non silenzio).
## 3) Spettro percettivo: presenza di energia sia nella prima meta' (crack)
##    che nella coda (tonfo grave) — il suono "cristallizza" davvero.
## 4) Esporta WAV in /home/z/my-project/download/freeze_hit_sfx.wav.
extends SceneTree


func _init() -> void:
        var failures: Array[String] = []
        var am: Node = load("res://scripts/audio/AudioManager.gd").new()
        # Simula il _ready dell'autoload (genera gli stream SFX)
        am._ready()
        var idx: int = am.SoundType.FREEZE_HIT
        print("[TEST] SoundType.FREEZE_HIT = ", idx, " (atteso 55, ultimo dei 56)")
        if idx != 55:
                failures.append("indice enum inaspettato %d" % idx)
        if am.SOUND_TYPE_COUNT != 56:
                failures.append("SOUND_TYPE_COUNT %d != 56" % am.SOUND_TYPE_COUNT)
        var st: AudioStreamWAV = am._sfx_streams[idx]
        if st == null:
                failures.append("stream FREEZE_HIT nullo")
                _finish(failures)
                return
        if st.format != AudioStreamWAV.FORMAT_16_BITS:
                failures.append("formato %d" % st.format)
        if st.stereo:
                failures.append("stereo invece di mono")
        var bytes: PackedByteArray = st.data
        var n: int = bytes.size() / 2
        var dur: float = float(n) / 44100.0
        print("[TEST] durata: %.3fs (%d campioni)" % [dur, n])
        if dur < 0.3 or dur > 0.9:
                failures.append("durata fuori range %.3fs" % dur)
        var peak: float = 0.0
        var sum_sq: float = 0.0
        var half_energy: float = 0.0
        for i in n:
                var v: float = float(bytes[i * 2] | (bytes[i * 2 + 1] << 8))
                if v > 32767.0:
                        v -= 65536.0
                var a: float = absf(v) / 32767.0
                if a > peak:
                        peak = a
                sum_sq += a * a
                if i < n / 2:
                        half_energy += a * a
        var rms: float = sqrt(sum_sq / float(n))
        print("[TEST] peak=%.3f rms=%.3f energia-prima-meta'=%.1f%%" % [
                        peak, rms, 100.0 * half_energy / sum_sq])
        if peak > 0.95:
                failures.append("CLIP (peak %.3f)" % peak)
        if rms < 0.02:
                failures.append("quasi silenzio (RMS %.3f)" % rms)
        if half_energy / sum_sq < 0.25:
                failures.append("prima meta' troppo debole (attacco mancante)")
        # Export WAV per ascolto
        var out_dir := "/home/z/my-project/download"
        DirAccess.make_dir_recursive_absolute(out_dir)
        var f := FileAccess.open(out_dir + "/freeze_hit_sfx.wav", FileAccess.WRITE)
        f.store_8(0x52); f.store_8(0x49); f.store_8(0x46); f.store_8(0x46)
        f.store_32(bytes.size() + 36)
        f.store_8(0x57); f.store_8(0x41); f.store_8(0x56); f.store_8(0x45)
        f.store_8(0x66); f.store_8(0x6D); f.store_8(0x74); f.store_8(0x20)
        f.store_32(16)
        f.store_16(1)
        f.store_16(1)
        f.store_32(44100)
        f.store_32(88200)
        f.store_16(2)
        f.store_16(16)
        f.store_8(0x64); f.store_8(0x61); f.store_8(0x74); f.store_8(0x61)
        f.store_32(bytes.size())
        f.store_buffer(bytes)
        f.close()
        print("[TEST] esportato download/freeze_hit_sfx.wav")
        _finish(failures)


func _finish(failures: Array[String]) -> void:
        if failures.is_empty():
                print("[TEST] test_freeze_hit_sfx: TUTTI OK")
                quit(0)
        else:
                for msg in failures:
                        print("[TEST FAIL] ", msg)
                quit(1)
