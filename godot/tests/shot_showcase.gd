## shot_showcase.gd — cattura screenshot REALE del potenziamento Task 22:
## 3 boss XHD con animazioni arti + proiettili tematici in volo + player XHD.
## Uso: xvfb-run -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 res://tests/shot_showcase.tscn
extends Node2D

const OUT := "/home/z/my-project/download/shot_boss_showcase.png"
const BossScript = preload("res://scripts/bosses/Boss.gd")
const ProjectileScript = preload("res://scripts/items/Projectile.gd")
const PlayerScript = preload("res://scripts/core/Player.gd")

var t := 0.0
var bosses: Array = []
var projs: Array = []


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        # A/B: SHOWCASE_SD=1 forza sheet SD legacy (confronto prima/dopo)
        if OS.get_environment("SHOWCASE_SD") == "1":
                GameConstants.SPRITE_XHD_ENABLED = false
        # sfondo scuro da boss room
        var bg := ColorRect.new()
        bg.color = Color(0.09, 0.08, 0.12)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)

        # --- 3 boss rappresentativi: GOLEM (braccia), KRAKEN (tentacoli), DRAGON (ali) ---
        # type = (level/4)%17: GOLEM=0 -> liv 68, KRAKEN=5 -> liv 20, DRAGON=6 -> liv 24
        var specs := [
                {"level": 68, "x": 400.0, "label": "STONE GOLEM - LP_ARMS"},
                {"level": 20, "x": 960.0, "label": "KRAKEN - LP_TENTACLES"},
                {"level": 24, "x": 1520.0, "label": "DRAGON - LP_WINGS"},
        ]
        for s in specs:
                var b := BossScript.new()
                add_child(b)
                b.setup(int(s.level), 1920, 1080)
                b.pos = Vector2(float(s.x), 420.0)
                b.position = b.pos
                b._draw()   # lazy-load XHD
                bosses.append(b)

        # --- proiettili tematici in volo (uno per boss mostrato + altri) ---
        _spawn_proj(ProjectileScript.BossProjKind.BP_BOULDER, Vector2(400, 700), Vector2(2.4, -0.6))
        _spawn_proj(ProjectileScript.BossProjKind.BP_NECRO_BOLT, Vector2(960, 700), Vector2(-2.6, -0.4))
        _spawn_proj(ProjectileScript.BossProjKind.BP_WEBSHOT, Vector2(960, 760), Vector2(2.2, 0.8))
        _spawn_proj(ProjectileScript.BossProjKind.BP_DRAGON_BREATH, Vector2(1520, 700), Vector2(-2.8, -0.7))
        _spawn_proj(ProjectileScript.BossProjKind.BP_WITCH_HEX, Vector2(1520, 780), Vector2(-1.8, 1.0))
        _spawn_proj(ProjectileScript.BossProjKind.BP_TWILIGHT_BLADE, Vector2(240, 860), Vector2(2.6, 0.5))
        _spawn_proj(ProjectileScript.BossProjKind.BP_BLOOD_BOLT, Vector2(720, 880), Vector2(2.4, -0.9))
        _spawn_proj(ProjectileScript.BossProjKind.BP_GHOST_BOLT, Vector2(1200, 900), Vector2(-2.3, -0.8))
        _spawn_proj(ProjectileScript.BossProjKind.BP_EYE_RAY, Vector2(1700, 880), Vector2(-3.0, -0.6), 2)
        _spawn_proj(ProjectileScript.BossProjKind.BP_RAT_SWARM, Vector2(500, 950), Vector2(2.0, 0.3))
        _spawn_proj(ProjectileScript.BossProjKind.BP_MIMIC_GOO, Vector2(1100, 980), Vector2(-1.8, 0.6))
        _spawn_proj(ProjectileScript.BossProjKind.BP_CULT_ORB, Vector2(1650, 980), Vector2(-2.0, 0.4))

        # --- player XHD in basso a sinistra ---
        var p := PlayerScript.new()
        var s2 := Sprite2D.new()
        s2.name = "Sprite2D"
        p.add_child(s2)
        add_child(p)
        p.set_character(0, 1)   # HERO
        p.position = Vector2(180, 950)
        p.set_direction(0, 0)


func _spawn_proj(kind: int, from: Vector2, vel: Vector2, variant_val: int = 0) -> void:
        var pr := ProjectileScript.new()
        pr.bp_kind = kind
        pr.variant = variant_val
        pr.dir = vel
        pr.pos = from
        pr.age_ms = 400
        pr.active = true
        add_child(pr)
        projs.append(pr)


func _process(delta: float) -> void:
        t += delta
        # anima i boss (arti + idle)
        for b in bosses:
                b.anim_time += delta
                b.update_step(960.0, 420.0, int(delta * 1000.0), [])
        # muovi i proiettili
        for pr in projs:
                pr.age_ms += int(delta * 1000.0)
                pr.pos += pr.dir * 60.0 * delta
                pr.sync_position()
                pr.queue_redraw()
        if t > 3.0:
                var img := get_viewport().get_texture().get_image()
                img.save_png(OUT)
                print("[SHOT] saved ", OUT, " ", img.get_size())
                get_tree().quit(0)
