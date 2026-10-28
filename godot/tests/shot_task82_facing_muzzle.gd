## shot_task82_facing_muzzle.gd — TASK 82b (feedback utente: "nemico che va
## verso il player a destra ma è girato a sinistra" + verifica del Task 82
## ripristinato: eroe facing + lampo di volata per arma/elemento).
##
## Harness QA in UNA schermata 1920x1080:
##   SEZIONE A — HERO_M facing fix: marcia → destra e ← sinistra attraverso
##   il percorso reale (load_character_sprite + _update_sprite + flag v2).
##   SEZIONE B — MUZZLE FLASH: 11 armi (5 da fuoco + 6 elementali) con il
##   lampo ATTIVO alla punta dell'arma, tramite il VERO Player.shoot() (le
##   stesse _begin_muzzle_flash di gameplay: stile per arma/elemento). Il
##   timer non viene scalato nel harness (update_player non gira) quindi il
##   lampo resta a intensità piena per lo scatto.
##   SEZIONE C — TUTTI i 44 nemici + 51 miniboss in marcia verso DESTRA
##   (dx=last_dx=+1) col reale Enemy._draw()/MiniBoss._draw() e i nuovi
##   flag facesLeft dell'audit task82b: il muso di OGNI creatura deve
##   puntare a destra.
##
## Avvio (Xvfb, NON headless — get_image() richiede un renderer reale):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task82_facing_muzzle.tscn
extends Node2D

const PlayerClass = preload("res://scripts/core/Player.gd")
const EnemyClass = preload("res://scripts/enemies/Enemy.gd")
const MiniBossClass = preload("res://scripts/bosses/MiniBoss.gd")
const C = preload("res://scripts/core/GameConstants.gd")

## [tipo-arma, etichetta]: 5 armi da fuoco + 6 elementali (reliquie).
const FLASH_WEAPONS := [
        [C.WeaponType.PISTOL, "PISTOL (scintilla)"],
        [C.WeaponType.SHOTGUN, "SHOTGUN (cono)"],
        [C.WeaponType.ROCKET, "ROCKET (vampata)"],
        [C.WeaponType.LASER, "LASER (energia)"],
        [C.WeaponType.SIEGE, "SIEGE (cannone)"],
        [C.RelicType.FIRE_STAFF, "B. FUOCO (fiamma)"],
        [C.RelicType.ICE_LANCE, "L. GHIACCIO (brina)"],
        [C.RelicType.STORM_ROD, "VERGA (arcano)"],
        [C.RelicType.ARCANE_ORB, "BASTONE (arcano)"],
        [C.RelicType.ALCHEMIST_BOMBS, "BOMBE (arcano)"],
        [C.RelicType.BLOOD_DART, "DARDO (arcano)"],
]

var t: float = 0.0
var players: Array = []
var walkers: Array = []   # nemici+miniboss (per anim_time)
var captured: bool = false


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var bg := ColorRect.new()
        bg.color = Color(0.13, 0.12, 0.16)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)

        _label(Vector2(960, 34),
                        "TASK 82b — FACING nemici/miniboss (audit A/B) + eroe + MUZZLE FLASH per arma/elemento",
                        30, true, Color(0.94, 0.88, 0.72))

        # ---------------- SEZIONE A: HERO_M facing fix --------------------
        _label(Vector2(960, 78),
                        "A) EROE (HERO_M, sheet v2): marcia → DESTRA   |   marcia ← SINISTRA",
                        22, true, Color(0.5, 0.9, 0.6))
        _spawn_player(760.0, 150.0, C.CharacterType.HERO_M, 1, -1)
        _spawn_player(1160.0, 150.0, C.CharacterType.HERO_M, -1, -1)

        # ---------------- SEZIONE B: muzzle flash per arma -----------------
        _label(Vector2(960, 232),
                        "B) MUZZLE FLASH alla punta dell'arma (sparo reale verso →): 5 armi da fuoco + 6 elementali",
                        22, true, Color(0.55, 0.85, 1.0))
        for i in FLASH_WEAPONS.size():
                var col_i: int = i % 6
                var row_i: int = i / 6
                var wx: float = 180.0 + col_i * 320.0
                var wy: float = 300.0 + row_i * 130.0
                var wtype: int = int(FLASH_WEAPONS[i][0])
                _spawn_player(wx, wy, C.CharacterType.HERO_M, 1, wtype)
                _label(Vector2(wx, wy + 62), FLASH_WEAPONS[i][1], 15, false,
                                Color(0.80, 0.78, 0.72))

        # ---------------- SEZIONE C: nemici + miniboss → destra ------------
        _label(Vector2(960, 552),
                        "C) TUTTI i nemici (m001-m045) e miniboss (mb01-mb51) in marcia verso → DESTRA: muso/naso deve puntare a destra",
                        20, true, Color(0.9, 0.7, 0.5))

        var id_x: float = 60.0
        var id_y: float = 620.0
        var per_row: int = 24
        var idx: int = 0
        # mostri: 1..13, 15..45 (il 14 non esiste)
        for i in range(1, 46):
                if i == 14:
                        continue
                var e := EnemyClass.new()
                e.init(i, 0, 0)
                e.position = Vector2(id_x + (idx % per_row) * 78.0,
                                id_y + (idx / per_row) * 118.0)
                e.dx = 1
                e.last_dx = 1
                e.anim_time = 160
                add_child(e)
                e.queue_redraw()
                walkers.append(e)
                _label(Vector2(e.position.x + 34.0, e.position.y + 44.0),
                                "m%03d" % i, 13, false, Color(0.62, 0.62, 0.58))
                idx += 1
        # miniboss: tipi 1..51
        var mb_idx: int = 0
        for i in range(1, 52):
                var mb := MiniBossClass.new()
                mb.setup(i, 1, 0, 0)
                mb.pos = Vector2(id_x + (mb_idx % per_row) * 78.0,
                                id_y + 380.0 + (mb_idx / per_row) * 118.0)
                mb.dx = 1
                mb.last_dx = 1
                mb.anim_time = 160.0
                add_child(mb)
                mb.queue_redraw()
                walkers.append(mb)
                _label(Vector2(mb.pos.x + 34.0, mb.pos.y + 44.0),
                                "mb%02d" % i, 13, false, Color(0.62, 0.62, 0.58))
                mb_idx += 1


func _spawn_player(at_x: float, at_y: float, ctype: int, mv_dx: int,
                wtype: int) -> void:
        var p := PlayerClass.new()
        var spr := Sprite2D.new()
        spr.name = "Sprite2D"
        p.add_child(spr)
        add_child(p)
        p.character_type = ctype
        p.load_character_sprite()
        p.last_dx = mv_dx
        p.dx = mv_dx  # walk cycle attivo
        p.anim_time = 160.0
        p.position = Vector2(at_x, at_y)
        if wtype >= 0:
                # Arma equipaggiata + SPARO REALE (registra il flash con lo
                # stile/colore giusto per arma/elemento, come in gameplay).
                p.current_weapon = {"type": wtype, "power": 2, "ammo": 30}
                p.shoot()
        p._update_sprite()
        p.queue_redraw()
        players.append(p)


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
        var ms := int(delta * 1000.0)
        for p in players:
                p.anim_time += float(ms)
                p._update_sprite()
                p.queue_redraw()
        for w in walkers:
                if w is EnemyClass:
                        w.anim_time += ms
                else:
                        w.anim_time += float(ms)
                w.queue_redraw()
        if t > 1.6 and not captured:
                captured = true
                var img := get_viewport().get_texture().get_image()
                img.save_png("/home/z/my-project/download/task82_facing_muzzle.png")
                print("[SHOT] salvato task82_facing_muzzle.png")
                get_tree().quit(0)
