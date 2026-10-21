## shot_boss_shader_lab.gd — TASK 26 (diagnosi "boss sbiaditi"):
## confronto controllato di 4 modi di renderizzare lo STESSO frame XHD
## (boss_031 Golem, frame 0, 256px, sheet 1024x256) su sfondo grigio medio:
##   REF  (x=200)  : Sprite2D + ImageTexture runtime  = pipeline identica ai
##                    player (ground truth dei colori sorgente).
##   A    (x=600)  : DeformableSprite + load_subrect() con StandardMaterial3D
##                    sulla superficie = COMPORTAMENTO ATTUALE dei boss.
##   B    (x=1000) : DeformableSprite + ImageTexture + canvas_item shader con
##                    uniform src_tex (boss_deform.gdshader in passthrough:
##                    contrast/sat/sharp/rim/depth neutri) = proposta fix.
##   C    (x=1400) : DeformableSprite + canvas_item character_enhanced con
##                    TEXTURE built-in e parametri neutri = verifica se il
##                    binding built-in funziona sui MeshInstance2D.
##   D    (x=1800) : come B ma con i parametri enhancement "strong" del boss
##                    (il look finale voluto: contrasto/saturazione/rim).
## Output: --write-movie shot_lab -> analisi numerica Python (media RGB dei
## pixel opachi di ogni variante vs la media del PNG sorgente).
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")
const BOSS_SHADER = preload("res://shaders/boss_deform.gdshader")
const CHARACTER_SHADER = preload("res://shaders/character_enhanced.gdshader")

var _refs: Array = []
var _labels: Array[String] = ["REF", "A", "B", "C", "D"]


func _ready() -> void:
        # Sfondo grigio medio uniforme: neutro per il confronto colori.
        queue_redraw()

        var sheet_path := "res://assets/sprites/xhd/boss_031_xhd_sheet.png"
        var abs_path: String = ProjectSettings.globalize_path(sheet_path)

        # --- REF: Sprite2D + ImageTexture runtime (pipeline dei player) ---
        var img := Image.new()
        if img.load(abs_path) != OK:
                push_error("[LAB] impossibile caricare %s" % abs_path)
                get_tree().quit(1)
                return
        var imgtex := ImageTexture.create_from_image(img)
        var ref := Sprite2D.new()
        ref.texture = imgtex
        ref.region_enabled = true
        ref.region_rect = Rect2(0, 0, 256, 256)
        ref.position = Vector2(200, 300)
        add_child(ref)
        _refs.append(ref)

        # --- A: percorso ATTUALE (load_subrect + StandardMaterial3D) ---
        var a := DeformableSprite.new()
        a.load_subrect(sheet_path, 0, 0, 256, 256)
        a.set_grid_size(12, 12)
        a.position = Vector2(600, 300 - 128.0)
        add_child(a)
        a.update(0.0, DeformableSprite.AnimMode.IDLE, 1.0, false)
        _refs.append(a)

        # --- B: proposta fix (canvas_item shader, uniform esplicita,
        #     parametri passthrough per il confronto colore 1:1) ---
        var b := DeformableSprite.new()
        b.assign_texture(imgtex, Rect2(0, 0, 256, 256))
        b.set_grid_size(12, 12)
        b.position = Vector2(1000, 300 - 128.0)
        b.material = _make_boss_material(imgtex, 0.0, 1.0, 1.0, 0.0, 0.0)
        b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        add_child(b)
        b.update(0.0, DeformableSprite.AnimMode.IDLE, 1.0, false)
        _refs.append(b)

        # --- C: canvas_item character_enhanced con TEXTURE built-in ---
        var c := DeformableSprite.new()
        c.assign_texture(imgtex, Rect2(0, 0, 256, 256))
        c.set_grid_size(12, 12)
        c.position = Vector2(1400, 300 - 128.0)
        var mat_c := ShaderMaterial.new()
        mat_c.shader = CHARACTER_SHADER
        mat_c.set_shader_parameter("sharpness", 0.0)
        mat_c.set_shader_parameter("contrast", 1.0)
        mat_c.set_shader_parameter("saturation", 1.0)
        mat_c.set_shader_parameter("rim_intensity", 0.0)
        mat_c.set_shader_parameter("depth_strength", 0.0)
        c.material = mat_c
        c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        add_child(c)
        c.update(0.0, DeformableSprite.AnimMode.IDLE, 1.0, false)
        _refs.append(c)

        # --- D: look finale (parametri strong del boss) ---
        var d := DeformableSprite.new()
        d.assign_texture(imgtex, Rect2(0, 0, 256, 256))
        d.set_grid_size(12, 12)
        d.position = Vector2(1650, 300 - 128.0)
        d.material = _make_boss_material(imgtex, 0.8, 1.2, 1.3, 0.7, 0.7)
        d.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        add_child(d)
        d.update(0.0, DeformableSprite.AnimMode.IDLE, 1.0, false)
        _refs.append(d)

        # ---- RIGA 2 (y=700): isolamento della causa dello scurimento ----
        # E: canvas shader passthrough + texture IMPORTATA (load()) ->
        #    isola la differenza ImageTexture-runtime vs CompressedTexture2D.
        var e := DeformableSprite.new()
        var tex_imported := load(sheet_path) as Texture2D
        e.assign_texture(tex_imported, Rect2(0, 0, 256, 256))
        e.set_grid_size(12, 12)
        e.position = Vector2(200, 700 - 128.0)
        e.material = _make_boss_material(tex_imported, 0.0, 1.0, 1.0, 0.0, 0.0)
        e.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        add_child(e)
        e.update(0.0, DeformableSprite.AnimMode.IDLE, 1.0, false)

        # F: mesh + StandardMaterial3D (percorso attuale) + ImageTexture runtime
        #    -> isola la fonte della texture sul percorso A.
        var f := DeformableSprite.new()
        f.assign_texture(imgtex, Rect2(0, 0, 256, 256))
        f.set_grid_size(12, 12)
        f.position = Vector2(600, 700 - 128.0)
        f.material = null
        add_child(f)
        f.update(0.0, DeformableSprite.AnimMode.IDLE, 1.0, false)

        # G: esatto percorso dei PLAYER: Sprite2D + ImageTexture runtime +
        #    character_enhanced NEUTRO su CanvasItem.material.
        var g := Sprite2D.new()
        g.texture = imgtex
        g.region_enabled = true
        g.region_rect = Rect2(0, 0, 256, 256)
        g.position = Vector2(1000, 700)
        var mat_g := ShaderMaterial.new()
        mat_g.shader = CHARACTER_SHADER
        mat_g.set_shader_parameter("sharpness", 0.0)
        mat_g.set_shader_parameter("contrast", 1.0)
        mat_g.set_shader_parameter("saturation", 1.0)
        mat_g.set_shader_parameter("rim_intensity", 0.0)
        mat_g.set_shader_parameter("depth_strength", 0.0)
        g.material = mat_g
        add_child(g)

        print("[LAB] 8 varianti pronte: REF/A/B/C/D (riga 1) + E/F/G (riga 2)")


func _make_boss_material(tex: Texture2D, sharp: float, contrast: float,
                saturation: float, rim: float, depth: float) -> ShaderMaterial:
        var mat := ShaderMaterial.new()
        mat.shader = BOSS_SHADER
        mat.set_shader_parameter("src_tex", tex)
        mat.set_shader_parameter("texel_size",
                Vector2(1.0 / 1024.0, 1.0 / 256.0))
        mat.set_shader_parameter("sharpness", sharp)
        mat.set_shader_parameter("contrast", contrast)
        mat.set_shader_parameter("saturation", saturation)
        mat.set_shader_parameter("rim_intensity", rim)
        mat.set_shader_parameter("depth_strength", depth)
        return mat


func _draw() -> void:
        draw_rect(Rect2(0, 0, 1920, 1080), Color(0.5, 0.5, 0.5))
        # tacche di riferimento sotto ogni variante
        var font: Font = ThemeDB.fallback_font
        for i in _labels.size():
                var x: float = 200.0 + i * 400.0
                draw_rect(Rect2(x - 128.0, 480.0, 256.0, 4.0), Color(0.1, 0.1, 0.1))
                draw_string(font, Vector2(x - 40.0, 520.0), _labels[i],
                        HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.05, 0.05, 0.05))
