## shot_task71_ally_cycle.gd — TASK 71: verifica del WALK CYCLE REALE degli
## alleati rigenerati (unicorn_ally/knight_ally, PixelLab 4f a pose reali).
## Harness: alleato ACTIVE in cammino (dx=1) per entrambe le varianti;
## catture a intervalli di ~86ms (> 80ms/frame = 1 passo di animazione a
## 12.5 fps) per mostrare la PROGRESSIONE del ciclo invece di scatti
## consecutivi identici (il vecchio shot_task65_ally_walk catturava a tick
## di _process adiacenti -> frame ripetuti).
##
## Avvio (Xvfb, NON headless — get_image() richiede un renderer reale):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task71_ally_cycle.tscn
extends Node2D

const KnightAllyClass = preload("res://scripts/entities/KnightAlly.gd")

var t: float = 0.0
var allies: Array = []
var captured: int = 0
var last_capture: float = -100.0
const CAPTURE_INTERVAL: float = 0.12  # 120ms = 1.5 frame anim a 12.5 fps
                                       # (86ms aliava col tick ~30fps di Xvfb:
                                       # due catture sullo stesso frame anim)


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var bg := ColorRect.new()
        bg.color = Color(0.09, 0.08, 0.12)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)

        _label(Vector2(960, 60),
                        "TASK 71 — ALLEATI RIGENERATI: WALK CYCLE A POSE REALI (12.5 fps)",
                        34, true, Color(0.94, 0.88, 0.72))
        _label(Vector2(480, 140), "UNICORNO (livelli dispari)",
                        28, true, Color(0.6, 0.85, 1.0))
        _label(Vector2(1440, 140), "CAVALLIERE (livelli pari)",
                        28, true, Color(0.6, 0.85, 1.0))
        _label(Vector2(960, 1010),
                        "6 catture ogni ~86ms: il ciclo di camminata deve PROGREDIRE a ogni cattura (gambe alternate, nessuna pedina che traslava)",
                        22, false, Color(0.72, 0.66, 0.52))

        _group(Vector2(480, 460), "unicorn")
        _group(Vector2(1440, 460), "knight")


func _group(center: Vector2, variant: String) -> void:
        # tre copie ACTIVE in cammino con fase di animazione SCALATA
        # (offset anim_time di 20ms * i) cosi' una sola cattura mostra
        # anche la variazione di pose tra i tre soggetti
        for i in 3:
                var a := KnightAllyClass.new()
                a.ally_variant = variant
                a.pos = center + Vector2(-160.0 + 160.0 * i, 60)
                add_child(a)
                a.state = KnightAlly.State.ACTIVE
                a.dx = 1
                a.last_dx = 1
                a.anim_time = 20.0 * i
                allies.append(a)


func _label(at: Vector2, text: String, size: int, bold: bool, col: Color) -> void:
        var l := Label.new()
        l.text = text
        l.position = at - Vector2(0, size)
        l.add_theme_font_size_override("font_size", size)
        l.add_theme_color_override("font_color", col)
        if bold:
                l.add_theme_font_override("font",
                                ThemeDB.fallback_font)
        add_child(l)


func _process(delta: float) -> void:
        t += delta
        var ms := int(delta * 1000.0)
        for ka in allies:
                ka.anim_time += float(ms)
                ka.queue_redraw()
        if t > 1.0 and captured < 6 and t - last_capture >= CAPTURE_INTERVAL:
                last_capture = t
                var img := get_viewport().get_texture().get_image()
                img.save_png("/home/z/my-project/download/task71_ally_cycle_%d.png"
                                % captured)
                print("[SHOT] cattura %d salvata" % captured)
                captured += 1
                if captured >= 6:
                        get_tree().quit(0)
