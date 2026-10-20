## shot_task27.gd — TASK 27 DIAGNOSI "boss grafica glitchata/confusa":
## renderizza i 4 boss segnalati (SPIDER/GHOUL_LORD/SPECTRAL_ALPHA/
## CULT_HERALD) su sfondo piatto scuro in 3 configurazioni temporali:
##   t in [0,3)   A) config CORRENTE (shader ON + limb anim ON, gain 2.6)
##   t in [3,6)   B) limb anim OFF (shader ON)  -> isola la deformazione
##   t in [6,7]   C) shader OFF + mesh fermo (t=0) -> riferimento asset
## Posizioni FISSE (ri-pinnate ogni frame). Screenshot via --write-movie
## (lezione worklog: get_image() può deadlockare sotto llvmpipe):
##   Xvfb :99 & DISPLAY=:99 godot --path . --resolution 1920x1080 \
##     --write-movie /home/z/my-project/scripts/task27_movie/f.png \
##     --fixed-fps 10 --quit-after 70 res://tests/shot_task27.tscn
## Frame usati: 25 = A, 55 = B, 65 = C.
extends Node2D

const BossScript = preload("res://scripts/bosses/Boss.gd")

## (boss_type, level che lo seleziona, x fisso) — y comune.
const SPECS := [
        {"type": 3,  "level": 12, "x": 320.0,  "name": "SPIDER"},
        {"type": 10, "level": 40, "x": 780.0,  "name": "GHOUL_LORD"},
        {"type": 11, "level": 44, "x": 1240.0, "name": "SPECTRAL_ALPHA"},
        {"type": 12, "level": 48, "x": 1700.0, "name": "CULT_HERALD"},
]
const BASE_Y := 560.0

var t := 0.0
var phase := 0
var bosses: Array = []
var fixed_pos := {}


func _ready() -> void:
        var bg := ColorRect.new()
        bg.color = Color(0.09, 0.08, 0.12)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)
        for s in SPECS:
                var b := BossScript.new()
                add_child(b)
                b.setup(int(s.level), 1920, 1080)
                var p := Vector2(float(s.x), BASE_Y)
                b.pos = p
                b.position = p
                b._draw()   # lazy-load XHD + enhancement (config corrente)
                fixed_pos[b] = p
                bosses.append(b)
        print("[SHOT27] setup 4 boss: shader=%s limb=%s gain=%.1f" % [
                str(GameConstants.BOSS_CANVAS_SHADER_ENABLED),
                str(GameConstants.BOSS_LIMB_ANIM_ENABLED),
                GameConstants.BOSS_LIMB_ANIM_GAIN])


func _process(delta: float) -> void:
        t += delta
        if phase == 0 and t >= 3.0:
                phase = 1
                GameConstants.BOSS_LIMB_ANIM_ENABLED = false
                print("[SHOT27] t=%.1f -> fase B (limb anim OFF)" % t)
        elif phase == 1 and t >= 6.0:
                phase = 2
                GameConstants.BOSS_CANVAS_SHADER_ENABLED = false
                for b in bosses:
                        if is_instance_valid(b) and b.deform_sprite != null:
                                b.deform_sprite.disable_canvas_enhancement()
                print("[SHOT27] t=%.1f -> fase C (shader OFF + mesh fermo)" % t)
        # anima: update_step avanza anim_time e applica il profilo arti
        for b in bosses:
                if not is_instance_valid(b):
                        continue
                var out: Array = []
                b.update_step(960.0, BASE_Y, int(delta * 1000.0), out)
                # niente proiettili né attacchi nel confronto
                b.shoot_timer_ms = 0
                b.attacking_timer_ms = 0
                # posizione FISSA (update_step muove pos): ri-pinna
                var p: Vector2 = fixed_pos[b]
                b.pos = p
                b.position = p
                # fase C: mesh fermo al tempo 0 (respirazione sin(0)=0)
                if phase == 2 and b.deform_sprite != null:
                        b.deform_sprite.update(0.0, 0, b.size / 256.0, false)
