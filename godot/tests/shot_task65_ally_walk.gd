## shot_task65_ally_walk.gd — TASK 65d (feedback utente: l'unicorno in
## movimento sembrava "una pedina del Monopoly" perche' la fase ACTIVE
## disegnava la statua col piedistallo). Ora ACTIVE usa lo sheet walk
## PixelLab animato. Harness: alleato ACTIVE IN MOVIMENTO (walk cycle,
## flip di direzione) + statua STONE per confronto, entrambe le varianti.
##
## Avvio (Xvfb, NON headless — get_image() richiede un renderer reale):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task65_ally_walk.tscn
extends Node2D

const KnightAllyClass = preload("res://scripts/entities/KnightAlly.gd")

var t: float = 0.0
var allies: Array = []
var captured: bool = false
var frames_saved: int = 0


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var bg := ColorRect.new()
        bg.color = Color(0.09, 0.08, 0.12)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)

        _label(Vector2(960, 60),
                        "TASK 65d — ALLEATO ATTIVO: SHEET WALK ANIMATO (no piedistallo)",
                        34, true, Color(0.94, 0.88, 0.72))
        _label(Vector2(480, 140), "UNICORNO (livelli dispari)",
                        28, true, Color(0.6, 0.85, 1.0))
        _label(Vector2(1440, 140), "CAVALLIERE (livelli pari)",
                        28, true, Color(0.6, 0.85, 1.0))
        _label(Vector2(960, 1010),
                        "Sinistra: statua di pietra (STONE, base OK) — centro: ACTIVE in cammino verso destra — destra: ACTIVE verso sinistra (flip)",
                        22, false, Color(0.72, 0.66, 0.52))

        _group(Vector2(480, 460), "unicorn")
        _group(Vector2(1440, 460), "knight")


func _group(center: Vector2, variant: String) -> void:
        _label(center + Vector2(-220, -140), "STONE (statua)", 20, false,
                        Color(0.72, 0.66, 0.52))
        _label(center + Vector2(0, -140), "ACTIVE → destra", 20, false,
                        Color(0.72, 0.66, 0.52))
        _label(center + Vector2(220, -140), "ACTIVE ← sinistra", 20, false,
                        Color(0.72, 0.66, 0.52))
        # statua di pietra (fase STONE: qui il piedistallo e' appropriato)
        var stone := KnightAllyClass.new()
        stone.ally_variant = variant
        stone.pos = center + Vector2(-220, 60)
        add_child(stone)
        stone.state = KnightAlly.State.STONE
        allies.append(stone)
        # ACTIVE in cammino verso destra
        var walk_r := KnightAllyClass.new()
        walk_r.ally_variant = variant
        walk_r.pos = center + Vector2(0, 60)
        add_child(walk_r)
        walk_r.state = KnightAlly.State.ACTIVE
        walk_r.dx = 1
        walk_r.last_dx = 1
        allies.append(walk_r)
        # ACTIVE verso sinistra (flip orizzontale)
        var walk_l := KnightAllyClass.new()
        walk_l.ally_variant = variant
        walk_l.pos = center + Vector2(220, 60)
        add_child(walk_l)
        walk_l.state = KnightAlly.State.ACTIVE
        walk_l.dx = -1
        walk_l.last_dx = -1
        allies.append(walk_l)


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
        # cattura 3 frame a distanza di ~150ms per vedere il walk cycle avanzare
        if t > 1.0 and frames_saved < 3:
                var img := get_viewport().get_texture().get_image()
                img.save_png("/home/z/my-project/download/task65_ally_walk_%d.png"
                                % frames_saved)
                print("[SHOT] frame %d salvato" % frames_saved)
                frames_saved += 1
                if frames_saved >= 3:
                        get_tree().quit(0)
