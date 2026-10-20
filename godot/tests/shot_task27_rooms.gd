## shot_task27_rooms.gd — TASK 28 verifica finale: i 4 boss segnalati
## (SPIDER/GHOUL_LORD/SPECTRAL_ALPHA/CULT_HERALD) animati col rendering FIXATO
## sopra i rispettivi sfondi boss room NUOVI (rigenerati senza mostri in
## scena). Una fase da 2s per stanza, cover-fit + overlay scuro come
## BossRoomController. Screenshot via --write-movie:
##   Xvfb :99 & DISPLAY=:99 godot --path . --resolution 1920x1080 \
##     --write-movie <dir>/f.png --fixed-fps 10 --quit-after 80 \
##     res://tests/shot_task27_rooms.tscn
## Frame usati: 10=spider, 30=ghoul, 50=spectral, 70=cult.
extends Node2D

const BossScript = preload("res://scripts/bosses/Boss.gd")

## (boss_type, level, bg_path) — boss centrato (960, 560).
const ROOMS := [
        {"type": 3,  "level": 12, "bg": "res://assets/backgrounds/boss_rooms/bg_boss_spider.jpg"},
        {"type": 10, "level": 40, "bg": "res://assets/backgrounds/boss_rooms/bg_boss_ghoul_lord.jpg"},
        {"type": 11, "level": 44, "bg": "res://assets/backgrounds/boss_rooms/bg_boss_spectral_alpha.jpg"},
        {"type": 12, "level": 48, "bg": "res://assets/backgrounds/boss_rooms/bg_boss_cult_herald.jpg"},
]
const CENTER := Vector2(960.0, 560.0)
const UI_H := 80.0

var t := 0.0
var phase := -1
var boss: Node = null
var bg_tex: Texture2D = null
var bgs: Array = []


func _ready() -> void:
        for r in ROOMS:
                var img := Image.new()
                var abs_p: String = ProjectSettings.globalize_path(r.bg)
                var err := img.load(abs_p)
                if err == OK:
                        bgs.append(ImageTexture.create_from_image(img))
                else:
                        bgs.append(null)
                        push_error("[SHOT27R] bg non caricabile: " + r.bg)
        _enter_phase(0)


func _enter_phase(p: int) -> void:
        phase = p
        if boss != null:
                remove_child(boss)
                boss.queue_free()
                boss = null
        var r: Dictionary = ROOMS[p]
        bg_tex = bgs[p]
        var b := BossScript.new()
        add_child(b)
        b.setup(int(r.level), 1920, 1080)
        b.pos = CENTER
        b.position = CENTER
        b._draw()
        boss = b
        print("[SHOT27R] fase %d: boss tipo %d su %s" % [p, r.type, r.bg])


func _process(delta: float) -> void:
        t += delta
        var dur := 2.0
        var want := int(t / dur)
        if want != phase and want < ROOMS.size():
                _enter_phase(want)
        if boss != null and is_instance_valid(boss):
                var out: Array = []
                boss.update_step(CENTER.x + 200.0, CENTER.y, int(delta * 1000.0), out)
                boss.shoot_timer_ms = 0
                boss.attacking_timer_ms = 0
                boss.pos = CENTER
                boss.position = CENTER
        queue_redraw()


func _draw() -> void:
        var vp := get_viewport_rect().size
        if bg_tex != null:
                var ts: Vector2 = bg_tex.get_size()
                var sc: float = maxf(vp.x / ts.x, vp.y / ts.y)
                var ds: Vector2 = ts * sc
                var dp: Vector2 = (vp - ds) * 0.5
                draw_texture_rect(bg_tex, Rect2(dp, ds), false)
        draw_rect(Rect2(0, UI_H, vp.x, vp.y - UI_H), Color(0, 0, 0, 0.25), true)
