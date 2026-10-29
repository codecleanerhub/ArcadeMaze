## shot_task82_facing_muzzle.gd — TASK 82c (v3 del harness facing).
##
## CORREZIONE RADICALE del harness task82b: le vecchie etichette erano SBAGLIATE.
##   * nemici:   label 'm%03d'%type_value ma lo sprite mostrato era
##               SPRITE_ID[type] (enum Enemy.gd 0..43 SENZA gap: type 9=ORC
##               -> monster_027; il tipo 14=CULTIST esisteva ma veniva saltato;
##               i tipi 44/45 NON esistono -> pallino procedurale fantasma).
##   * miniboss: get_sprite_id(t) = miniboss_%02d % (t+1) -> offset +1: la
##               label 'mb10' mostrava miniboss_11; 'mb23' mostrava
##               miniboss_24; 'mb51' mostrava miniboss_52 INESISTENTE.
##               Inoltre le file 2-3 dei miniboss cadevano a y>=1118 (fuori
##               dallo 1080): l'utente vedeva solo mb01..mb24.
## Rimappa del feedback utente (verita' di fondo) -> fix meta facesLeft:
##   monster_027/031/045 + miniboss_16: facesLeft=true AGGIUNTO
##   (native guardano a sinistra: m009/m029/m043/mb15 nel vecchio sheet)
##   miniboss_11/24: facesLeft RIMOSSO (native guardano a destra: con il
##   flag dell'audit venivano specchiati al contrario: mb10/mb23)
##
## Harness v3 (questa versione):
##   SEZIONE A — HERO_M facing: marcia -> destra e <- sinistra.
##   SEZIONE B — MUZZLE FLASH: 11 armi col VERO Player.shoot().
##   SEZIONE C — TUTTI i 44 tipi nemico reali (0..43, ZOMBIE e CULTIST
##   inclusi) e i 51 miniboss reali (mb01..mb51) in marcia verso DESTRA,
##   ETICHETTATI CON L'ID SPRITE REALE (m0xx = monster_0xx, mbxx =
##   miniboss_xx): label = sprite mostrato, 1:1 verificabile.
##   Etichette AMBRA = i 6 fix di questo task; CIANO = sprite frontali
##   (rivolti allo schermo: il flip non cambia la percezione, da decidere
##   se rigenerarli in vista laterale).
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

## I 6 fix di questo task (id sprite): etichetta AMBRA.
const FIXED_THIS_TASK := {
        "monster_027": true, "monster_031": true, "monster_045": true,
        "miniboss_11": true, "miniboss_16": true, "miniboss_24": true,
}
## Sprite frontali segnalati dall'utente (tramite rimappa): etichetta CIANO.
const FRONT_FACING := {
        "monster_002": true, "monster_017": true, "monster_022": true,
        "monster_025": true, "monster_036": true, "monster_037": true,
        "monster_039": true, "monster_040": true, "monster_042": true,
        "miniboss_25": true,
}

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
                        "TASK 82c — FACING: label = ID SPRITE REALE (fix harness) + 6 fix facesLeft + eroe + MUZZLE FLASH",
                        30, true, Color(0.94, 0.88, 0.72))

        # ---------------- SEZIONE A: HERO_M facing fix --------------------
        _label(Vector2(960, 74),
                        "A) EROE (HERO_M, sheet v2): marcia → DESTRA   |   marcia ← SINISTRA",
                        21, true, Color(0.5, 0.9, 0.6))
        _spawn_player(760.0, 146.0, C.CharacterType.HERO_M, 1, -1)
        _spawn_player(1160.0, 146.0, C.CharacterType.HERO_M, -1, -1)

        # ---------------- SEZIONE B: muzzle flash per arma -----------------
        _label(Vector2(960, 210),
                        "B) MUZZLE FLASH alla punta dell'arma (sparo reale verso →): 5 armi da fuoco + 6 elementali",
                        21, true, Color(0.55, 0.85, 1.0))
        for i in FLASH_WEAPONS.size():
                var col_i: int = i % 6
                var row_i: int = i / 6
                var wx: float = 180.0 + col_i * 320.0
                var wy: float = 276.0 + row_i * 122.0
                var wtype: int = int(FLASH_WEAPONS[i][0])
                _spawn_player(wx, wy, C.CharacterType.HERO_M, 1, wtype)
                _label(Vector2(wx, wy + 58), FLASH_WEAPONS[i][1], 15, false,
                                Color(0.80, 0.78, 0.72))

        # ---------------- SEZIONE C: nemici + miniboss → destra ------------
        _label(Vector2(960, 490),
                        "C) TUTTI i 44 nemici (m001..m045, manca solo m014) + 51 miniboss (mb01..mb51) in marcia → DESTRA — label = sprite reale",
                        20, true, Color(0.9, 0.7, 0.5))
        _label(Vector2(960, 512),
                        "etichetta AMBRA = 6 fix di questo task   |   etichetta CIANO = sprite frontale (verso schermo)   |   muso deve puntare a destra",
                        15, false, Color(0.65, 0.63, 0.58))

        # Griglia: 24 creature per riga, 5 righe totali (44 nemici = 2 righe,
        # 51 miniboss = 3 righe). Pitch Y=110 (NON piu' stretto: con 100 le
        # label della riga N toccavano la cima degli sprite della riga N+1
        # e l'associazione label->sprite diventava ambigua). Righe: 556, 666
        # (nemici), 776, 886, 996 (miniboss) — ultima label a y~1056 < 1080.
        var per_row: int = 24
        var pitch_x: float = 78.0
        var pitch_y: float = 110.0
        var id_x: float = 30.0
        var idx: int = 0
        # ---- nemici: TUTTI i tipi reali dell'enum (0..43), ZOMBIE e
        # CULTIST inclusi. Label = id sprite (m0xx), NON il type value.
        for ty in range(0, EnemyClass.ENEMY_TYPE_COUNT):
                var sid: String = EnemyClass.get_sprite_id(ty)
                if sid.is_empty():
                        continue  # tipi senza sprite: non devono esistere
                var e := EnemyClass.new()
                e.init(ty, 0, 0)
                e.position = Vector2(id_x + (idx % per_row) * pitch_x,
                                556.0 + (idx / per_row) * pitch_y)
                e.dx = 1
                e.last_dx = 1
                e.anim_time = 160
                add_child(e)
                e.queue_redraw()
                walkers.append(e)
                _creature_label(e.position, sid)
                idx += 1
        print("[HARNESS] nemici mostrati: %d (attesi 44)" % idx)
        # ---- miniboss: tipi 0..50 -> sprite miniboss_01..miniboss_51.
        # Label = id sprite (mbxx), NON il type value (offset +1!).
        # Le file partono dalla riga 2 della griglia (y=776) e restano
        # tutte dentro lo schermo: 776, 886, 996 (sprite fino a y=1037).
        var mb_idx: int = 0
        for ty in range(0, 51):
                var sid: String = MiniBossClass.get_sprite_id(ty)
                var mb := MiniBossClass.new()
                mb.setup(ty, 1, 0, 0)
                mb.pos = Vector2(id_x + (mb_idx % per_row) * pitch_x,
                                776.0 + (mb_idx / per_row) * pitch_y)
                mb.dx = 1
                mb.last_dx = 1
                mb.anim_time = 160.0
                add_child(mb)
                mb.queue_redraw()
                walkers.append(mb)
                _creature_label(mb.pos, sid)
                mb_idx += 1
        print("[HARNESS] miniboss mostrati: %d (attesi 51)" % mb_idx)


# Etichetta di creatura: testo = id sprite reale (m0xx / mbxx), colore per
# categoria (fix di questo task in AMBRA, frontali in CIANO, resto grigio).
func _creature_label(at: Vector2, sid: String) -> void:
        var txt: String = sid.replace("monster_", "m").replace("miniboss_", "mb")
        var col := Color(0.62, 0.62, 0.58)
        if FIXED_THIS_TASK.has(sid):
                col = Color(0.95, 0.75, 0.25)   # AMBRA: fix di questo task
        elif FRONT_FACING.has(sid):
                col = Color(0.35, 0.85, 0.95)   # CIANO: frontale
        _label(Vector2(at.x + 34.0, at.y + 60.0), txt, 13, false, col)


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
