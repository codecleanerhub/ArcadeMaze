## shot_task82_muzzle.gd — TASK 82: (1) fix facing EROE (HERO_M si girava
## dal lato opposto al movimento: sheet v2 guarda a sinistra, flag corretto);
## (2) LAMPO DI VOLATA: piccolo effetto grafico ALLA PUNTA dell'arma quando
## spara, con stile/colore DEDICATO per arma o elemento elementale.
##
## Harness QA in UNA schermata 1920x1080:
##   Riga A — HERO_M in cammino verso destra e verso sinistra (facing fix);
##   Riga B — armi da fuoco che sparano a destra: PISTOL, SHOTGUN, ROCKET,
##            LASER (PNG PixelLab in mano, flash alla volata);
##   Riga C — armi elementali che sparano: Bastone Fuoco (fiamma), Lancia
##            Ghiaccio (brina), Spade Lanciate (arcano), Dardo Sanguigno
##            (arcano rosso);
##   Riga D — PISTOL che spara VERTICALE in su + CANNONE D'ASSEDIO (vampa
##            oro + polvere).
##
## Il timer del lampo NON viene fatto scalare (nessun update_player): il
## flash resta al valore pieno (t=1) per la cattura, come appena sparato.
## La LUCE di sparo viene invece attivata esplicitamente (_update_muzzle_light)
## per verificare nel renderer reale anche il percorso PointLight2D.
##
## Avvio (Xvfb, NON headless — get_image() richiede un renderer reale):
##   Xvfb :66 & DISPLAY=:66 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task82_muzzle.tscn
extends Node2D

const PlayerClass = preload("res://scripts/core/Player.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var t: float = 0.0
var players: Array = []
var captured: bool = false


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var bg := ColorRect.new()
        bg.color = Color(0.07, 0.06, 0.10)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)

        _label(Vector2(960, 42),
                        "TASK 82 — FACING EROE + LAMPO DI VOLATA (muzzle flash per arma/elemento)",
                        30, true, Color(0.94, 0.88, 0.72))

        # --- Riga A: fix facing dell'EROE -----------------------------------
        _label(Vector2(960, 108),
                        "A — EROE (HERO_M): cammina → DESTRA  |  cammina ← SINISTRA",
                        24, true, Color(0.5, 0.9, 0.6))
        _spawn_walk(560.0, 190.0, 1)
        _spawn_walk(1360.0, 190.0, -1)

        # --- Riga B: armi da fuoco, sparo verso destra ----------------------
        _label(Vector2(960, 300),
                        "B — ARMI DA FUOCO (sparo →): volata = punta dell'arma",
                        24, true, Color(0.9, 0.75, 0.5))
        _spawn_gun(340.0, 400.0, C.WeaponType.PISTOL, "PISTOL — scintilla")
        _spawn_gun(800.0, 400.0, C.WeaponType.SHOTGUN, "SHOTGUN — cono ampio")
        _spawn_gun(1260.0, 400.0, C.WeaponType.ROCKET, "ROCKET — vampata+fumo")
        _spawn_gun(1680.0, 400.0, C.WeaponType.LASER, "LASER — energia")

        # --- Riga C: armi elementali, sparo verso destra --------------------
        _label(Vector2(960, 520),
                        "C — ARMI ELEMENTALI (sparo →): fiamma / brina / arcano",
                        24, true, Color(0.55, 0.8, 1.0))
        _spawn_elemental(340.0, 620.0, "fire_staff", "B. FUOCO — fiamma")
        _spawn_elemental(800.0, 620.0, "ice_lance", "L. GHIACCIO — brina")
        _spawn_elemental(1260.0, 620.0, "throwing_sword", "SPADE — arcano")
        _spawn_elemental(1680.0, 620.0, "blood_dart", "DARDO — arcano rosso")

        # --- Riga D: verticale + cannone ------------------------------------
        _label(Vector2(960, 740),
                        "D — VERTICALE (pistol ↑) + CANNONE D'ASSEDIO (→)",
                        24, true, Color(0.9, 0.6, 0.5))
        _spawn_vertical(560.0, 900.0, C.WeaponType.PISTOL)
        _spawn_gun(1360.0, 900.0, C.WeaponType.SIEGE, "SIEGE — vampa oro")


func _spawn_walk(at_x: float, at_y: float, dx: int) -> void:
        var p := _make_player(at_x, at_y)
        p.character_type = C.CharacterType.HERO_M
        p.load_character_sprite()
        p.last_dx = dx
        p.dx = dx  # walk cycle attivo (frame selection usa dx/dy)
        p.dy = 0
        p.anim_time = 160.0
        p._update_sprite()
        p.queue_redraw()


func _spawn_gun(at_x: float, at_y: float, wtype: int, tag: String) -> void:
        var p := _make_player(at_x, at_y)
        p.character_type = C.CharacterType.HERO_M
        p.load_character_sprite()
        p.current_weapon = C.make_weapon(wtype)
        p.last_dx = 1
        p.dx = 1
        p.dy = 0
        p.anim_time = 160.0
        p._update_sprite()
        p.shoot()
        p._update_muzzle_light()  # attiva anche la luce di sparo (Xvfb reale)
        p.queue_redraw()
        _label(Vector2(at_x, at_y + 58.0), tag, 17, false, Color(0.82, 0.80, 0.74))


func _spawn_elemental(at_x: float, at_y: float, weapon_id: String, tag: String) -> void:
        var p := _make_player(at_x, at_y)
        p.character_type = C.CharacterType.MAGE
        p.load_character_sprite()
        var def: Dictionary = C.get_elemental_by_id(weapon_id)
        p.current_weapon = C.make_relic_weapon(def)
        p.last_dx = 1
        p.dx = 1
        p.dy = 0
        p.anim_time = 160.0
        p._update_sprite()
        p.shoot()
        p._update_muzzle_light()
        p.queue_redraw()
        _label(Vector2(at_x, at_y + 58.0), tag, 17, false, Color(0.82, 0.80, 0.74))


func _spawn_vertical(at_x: float, at_y: float, wtype: int) -> void:
        var p := _make_player(at_x, at_y)
        p.character_type = C.CharacterType.HERO_M
        p.load_character_sprite()
        p.current_weapon = C.make_weapon(wtype)
        p.last_dy = -1
        p.dy = -1
        p.dx = 0
        p.anim_time = 160.0
        p._update_sprite()
        p.shoot()
        p._update_muzzle_light()
        p.queue_redraw()
        _label(Vector2(at_x, at_y + 58.0), "PISTOL — verticale ↑", 17, false,
                        Color(0.82, 0.80, 0.74))


func _make_player(at_x: float, at_y: float) -> CharacterBody2D:
        var p := PlayerClass.new()
        var spr := Sprite2D.new()
        spr.name = "Sprite2D"
        p.add_child(spr)
        add_child(p)
        p.position = Vector2(at_x, at_y)
        players.append(p)
        return p


func _label(at: Vector2, text: String, size: int, bold: bool, col: Color) -> void:
        var l := Label.new()
        l.text = text
        l.position = at - Vector2(0, size)
        l.add_theme_font_size_override("font_size", size)
        l.add_theme_color_override("font_color", col)
        if bold:
                l.add_theme_font_override("font", ThemeDB.fallback_font)
        add_child(l)


func _process(delta: float) -> void:
        t += delta
        # anima il ciclo di camminata degli EROI della riga A (come il gioco)
        var ms := int(delta * 1000.0)
        for p in players:
                if p.dx != 0 or p.dy != 0:
                        p.anim_time += float(ms)
                        p._update_sprite()
                        p.queue_redraw()
        if t > 1.2 and not captured:
                captured = true
                var img := get_viewport().get_texture().get_image()
                img.save_png("/home/z/my-project/download/task82_muzzle_flash.png")
                print("[SHOT] salvato task82_muzzle_flash.png")
                print("[T82] muzzle_timers ",
                                players.map(func(p): return p._muzzle_timer_ms))
                print("[T82] luci di sparo attive ",
                                players.filter(func(p): return p._muzzle_light != null).size(),
                                "/10")
                get_tree().quit(0)
