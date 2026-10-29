## dump_task93_sfx.gd — strumento di QA: esporta l'SFX CHALICE_POWER
## (Task 93, calice di fuoco) come WAV per analisi/ ascolto offline.
extends Node


func _ready() -> void:
        var am := get_node("/root/AudioManager")
        var stream: AudioStreamWAV = am._generate_sfx(am.SoundType.CHALICE_POWER)
        if stream == null or stream.data.is_empty():
                push_error("dump: stream CHALICE_POWER nullo")
                get_tree().quit(1)
                return
        var pcm: PackedByteArray = stream.data
        var out_path: String = "/home/z/my-project/download/task93_chalice_power.wav"
        var f := FileAccess.open(out_path, FileAccess.WRITE)
        # header WAV RIFF: PCM16 mono 44100
        var byte_rate: int = 44100 * 2
        var data_size: int = pcm.size()
        f.store_32(0x46464952)                      # "RIFF" (LE)
        f.store_32(36 + data_size)                  # chunk size
        f.store_32(0x45564157)                      # "WAVE"
        f.store_32(0x20746d66)                      # "fmt "
        f.store_32(16)                              # fmt size
        f.store_16(1)                               # PCM
        f.store_16(1)                               # mono
        f.store_32(44100)                           # sample rate
        f.store_32(byte_rate)
        f.store_16(2)                               # block align
        f.store_16(16)                              # bits
        f.store_32(0x61746164)                      # "data"
        f.store_32(data_size)
        f.store_buffer(pcm)
        f.close()
        print("[DUMP] WAV salvato: ", out_path, " (", data_size, " bytes, ",
                        float(data_size) / 2.0 / 44100.0, "s)")
        get_tree().quit(0)
