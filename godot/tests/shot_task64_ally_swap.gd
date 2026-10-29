## shot_task64_ally_swap.gd — TASK 64 (richiesta utente): screenshot
## dell'alleato della statuetta alternato per livello — UNICORNO nei livelli
## dispari (1,3,5..), CAVALLIERE nei livelli pari (2,4,6..).
##
## Cattura le due varianti rese ESATTAMENTE come in gioco:
##   - statuetta a terra (Collectibles._draw_knight_statue: aura blu/ciano
##     pulsante + bob, PNG PixelLab item_unicorn/item_knight_statue);
##   - alleato evocato ACTIVE (KnightAlly._draw_statue_unified: statua
##     60px + aura celeste, bob di movimento).
##
## Avvio (Xvfb, NON headless — get_image() richiede un renderer reale):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task64_ally_swap.tscn
extends Node2D

const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")
const KnightAllyClass = preload("res://scripts/entities/KnightAlly.gd")

var t: float = 0.0
var statues: Array = []
var allies: Array = []
var captured: bool = false


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var bg := ColorRect.new()
        bg.color = Color(0.09, 0.08, 0.12)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)

        _label(Vector2(960, 60),
                        "TASK 64 — ALLEATO DELLA STATUETTA ALTERNATO PER LIVELLO",
                        34, true, Color(0.94, 0.88, 0.72))
        _label(Vector2(480, 140), "LIVELLI DISPARI (1, 3, 5...) = UNICORNO",
                        28, true, Color(0.6, 0.85, 1.0))
        _label(Vector2(1440, 140), "LIVELLI PARI (2, 4, 6...) = CAVALLIERE",
                        28, true, Color(0.6, 0.85, 1.0))
        _label(Vector2(960, 1010),
                        "Sinistra: statuetta a terra nel labirinto — destra: alleato evocato (stato ACTIVE)",
                        22, false, Color(0.72, 0.66, 0.52))

        _group(Vector2(480, 420), "unicorn")
        _group(Vector2(1440, 420), "knight")


func _group(center: Vector2, variant: String) -> void:
        _label(center + Vector2(-170, -120), "statuetta a terra", 20, false,
                        Color(0.72, 0.66, 0.52))
        _label(center + Vector2(170, -120), "alleato evocato", 20, false,
                        Color(0.72, 0.66, 0.52))
        # statuetta a terra (come spawna nel labirinto: active, bob/aura)
        var st: Collectibles = CollectiblesClass.make_knight_statue(
                        center + Vector2(-170, 40))
        st.statue_variant = variant
        add_child(st)
        statues.append(st)
        # alleato ACTIVE (come appare dopo la trasformazione)
        var ka := KnightAllyClass.new()
        ka.ally_variant = variant
        ka.pos = center + Vector2(170, 40)
        add_child(ka)
        ka.state = KnightAlly.State.ACTIVE
        allies.append(ka)


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
        for st in statues:
                st.update_step(ms, Vector2.ZERO)
        for ka in allies:
                ka.anim_time += float(ms)
                ka.queue_redraw()
        # cattura dopo 1.6s: bob + aura pulsante visibili, frame animati
        if not captured and t > 1.6:
                captured = true
                var img := get_viewport().get_texture().get_image()
                img.save_png("/home/z/my-project/download/task64_ally_swap.png")
                print("[SHOT] salvato task64_ally_swap.png")
                get_tree().quit(0)
