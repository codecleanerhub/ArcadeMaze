## shot_task65_game.gd — TASK 65: verifica IN-GIOCO delle rigenerazioni
## PixelLab richieste dall'utente (screenshot di riferimento):
##   1. PORTALE (65a): nuovo sheet vortice, renderizzato come fa
##      MainGameController (aura viola + sprite 84px + pulse, 4 frame)
##   2. NEMICO CONGELATO (65b): nuovo effect_iceblock rotondo senza bordo
##      sticker (modulate 0.45 + velo + sparkles come Enemy.gd)
##   3. TESORI (65c): i 5 tesori del maze — corona, oro, forziere,
##      GEMMA rigenerata (ex "palla blue") e NUOVO RUBINO (ex coppa)
##
## Screenshot via get_image() con renderer reale (pattern Task 64):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task65_game.tscn
extends Node2D

const EnemyScript = preload("res://scripts/enemies/Enemy.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

var t: float = 0.0
var enemy: Node2D = null
var treasures: Array = []
var captured: int = 0
var _portal_sheet: Texture2D = null


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        # cache della texture del portale UNA volta (pattern MainGameController:
        # creare ImageTexture dentro _draw ogni frame rende quadrati bianchi)
        _portal_sheet = _load_portal_sheet()
        var bg := ColorRect.new()
        bg.color = Color(0.09, 0.08, 0.12)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)

        _label(Vector2(960, 60),
                        "TASK 65 — PORTALE + NEMICO CONGELATO + TESORI (rigenerati PixelLab)",
                        34, true, Color(0.94, 0.88, 0.72))

        # --- 1. Portale (rendering fedele a MainGameController) -----------
        _label(Vector2(320, 200), "MAGIC PORTAL (nuovo vortice)", 24, true,
                        Color(0.7, 0.5, 1.0))

        # --- 2. Nemico congelato (stato reale Enemy.gd) --------------------
        _label(Vector2(960, 200), "NEMICO CONGELATO (nuovo ghiaccio)",
                        24, true, Color(0.55, 0.8, 1.0))
        enemy = EnemyScript.new()
        enemy.init(EnemyScript.EnemyType.ZOMBIE, 3, 3)
        enemy.position = Vector2(960, 380)
        enemy.last_pos = enemy.position
        enemy.frozen = true
        add_child(enemy)

        # --- 3. Tesori (Collectibles reali, ciclo bob) ----------------------
        _label(Vector2(1500, 200), "TESORI (gem + ruby nuovi)", 24, true,
                        Color(1.0, 0.85, 0.3))
        var tx := 1210.0
        for tt in [CollectiblesClass.TreasureType.TRES_CROWN,
                        CollectiblesClass.TreasureType.TRES_GOLD,
                        CollectiblesClass.TreasureType.TRES_CHEST,
                        CollectiblesClass.TreasureType.TRES_GEM,
                        CollectiblesClass.TreasureType.TRES_RUBY]:
                var c: Collectibles = CollectiblesClass.make_treasure(
                                int(tt), Vector2(tx, 360))
                add_child(c)
                treasures.append(c)
                tx += 145.0


func _portal_center() -> Vector2:
        return Vector2(320.0, 400.0)


func _label(at: Vector2, text: String, size: int, bold: bool, col: Color) -> void:
        var l := Label.new()
        l.text = text
        l.position = at - Vector2(0, size)
        l.add_theme_font_size_override("font_size", size)
        l.add_theme_color_override("font_color", col)
        if bold:
                l.add_theme_font_override("font", ThemeDB.fallback_font)
        add_child(l)


func _load_portal_sheet() -> Texture2D:
        var abs_p := ProjectSettings.globalize_path(
                        "res://assets/sprites/env/portal_sheet.png")
        if FileAccess.file_exists(abs_p):
                var img := Image.new()
                if img.load(abs_p) == OK:
                        return ImageTexture.create_from_image(img)
        return null


func _draw() -> void:
        # Portale: replica del rendering di MainGameController (aura +
        # frame del sheet + pulse) per la verifica visiva. NB: la texture
        # e' caricata UNA volta in _ready (cache statica come nel gioco:
        # ricrearla ogni frame in _draw produce quadrati bianchi su
        # llvmpipe — lezione Task 65).
        var sheet := _portal_sheet
        if sheet == null:
                return
        var ppos := _portal_center()
        var rot := t * 1.2
        var glow := t * 2.0
        var aura_r: float = 40.0 + sin(glow * 2.0) * 6.0
        draw_circle(ppos, aura_r, Color(0.5, 0.2, 0.8, 0.2))
        var frame_idx: int = int(rot * 2.2 + glow * 3.0) % 4
        if frame_idx < 0:
                frame_idx += 4
        var pulse: float = 1.0 + sin(glow * 2.0) * 0.06
        var w := 84.0 * pulse
        var src := Rect2(float(frame_idx) * 64.0, 0.0, 64.0, 64.0)
        var dst := Rect2(ppos.x - w * 0.5, ppos.y - w * 0.5, w, w)
        draw_texture_rect_region(sheet, dst, src, Color.WHITE, false)


func _process(delta: float) -> void:
        t += delta
        var ms := int(delta * 1000.0)
        if enemy != null:
                enemy.anim_time += float(ms)
                enemy.queue_redraw()
        for c in treasures:
                c.update_step(ms, Vector2.ZERO)
        queue_redraw()
        # 2 catture a tempi diversi: frame anim A (1.2s) e B (2.0s)
        if captured == 0 and t > 1.2:
                _snap("task65_game_a.png")
                captured = 1
        elif captured == 1 and t > 2.0:
                _snap("task65_game_b.png")
                captured = 2
                get_tree().quit(0)


func _snap(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)
