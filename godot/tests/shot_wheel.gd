## shot_wheel.gd — cattura screenshot REALE della ruota (xvfb + --write-movie).
## Pattern showcase (verificato funzionante): root Node2D, SelectPlayer figlio
## con size esplicita + dump diagnostico delle texture caricate.
extends Node2D

const DBG := "/tmp/wheel_dbg_info.txt"
var t := 0.0
var sp: Control = null


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        # A/B: WHEEL_SD=1 forza lo sheet SD legacy (per confronto prima/dopo)
        if OS.get_environment("WHEEL_SD") == "1":
                GameConstants.SPRITE_XHD_ENABLED = false
        var scene := load("res://scenes/SelectPlayer.tscn") as PackedScene
        sp = scene.instantiate()
        add_child(sp)
        sp.position = Vector2.ZERO
        sp.size = Vector2(1920, 1080)


func _process(delta: float) -> void:
        t += delta
        if t > 1.0 and not FileAccess.file_exists(DBG):
                var widths: Array = []
                for i in range(sp._char_textures.size()):
                        var tt: Texture2D = sp._char_textures[i]
                        widths.append(tt.get_width() if tt != null else -1)
                var f := FileAccess.open(DBG, FileAccess.WRITE)
                if f:
                        f.store_string("frame t=%.2f sp.size=%s tex_widths=%s\n"
                                        % [t, str(sp.size), str(widths)])
                        f.close()
