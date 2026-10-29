## EffectsManager.gd - Autoload per effetti visivi Godot-native.
##
## Fornisce:
##   - PointLight2D dinamici (torce, aura player, glow tesori)
##   - GPUParticles2D per esplosioni/fulmini/pickup
##   - Screen shake su danno/boss death
##   - Post-processing vignette via shader
##
## Questo e' il layer che usa DAVVERO Godot per migliorare la grafica
## rispetto al C++/SFML originale (che era tutto flat).
extends Node

const C = preload("res://scripts/core/GameConstants.gd")

# Shader pre-caricati
const GLOW_SHADER = preload("res://shaders/glow.gdshader")
const FIRE_SHADER = preload("res://shaders/fire.gdshader")
const LIGHTNING_SHADER = preload("res://shaders/lightning.gdshader")
const VIGNETTE_SHADER = preload("res://shaders/vignette.gdshader")
const WALK_CYCLE_SHADER = preload("res://shaders/walk_cycle.gdshader")

# Cache dei materiali shader (per non ricrearli ogni volta)
var _glow_materials: Dictionary = {}
var _fire_material: ShaderMaterial = null
var _lightning_material: ShaderMaterial = null
# Walk cycle material: one shared material, params updated each frame.
# Each CanvasItem that wants the effect gets its own instance so we can set
# per-enemy accent colors; the shader itself is shared via preload.
var _walk_cycle_materials: Dictionary = {}  # key: accent_color_str -> ShaderMaterial

# Screen shake state
var _shake_amount: float = 0.0
var _shake_timer: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO

# Camera target (se presente) per applicare lo shake
var _camera: Camera2D = null

# TASK 79d (performance boss fase 2 — segnalazione utente: "il gioco andava
# a scatti"): ogni spawn_explosion/spawn_sparks/spawn_blast_smoke ricreava
# GRADIENTTEXTURE1D + GRADIENT + texture 8x8 + PARTICLEPROCESSMATERIAL da
# zero, con upload GPU a ogni esplosione. Le scintille in fase 2 spawano
# di continuo (proiettili bloccati dalle rovine, slam, buche) -> churn di
# allocazioni/upload = micro-stutter. Ora TUTTE le risorse ripetute sono
# CACHEATE: un solo upload a vita per texture/ramp, un material per chiave
# colore (i colori d'esplosione sono pochi e distinti). Zero differenze visive.
var _particle_dot_tex: Texture2D = null          # pallino 8x8 condiviso
var _fade_ramp_1d: GradientTexture1D = null      # bianco->trasparente (explosion/lightning)
var _smoke_ramp_1d: GradientTexture1D = null    # rampa fumo (3 punti)
var _dust_ramp_2d: GradientTexture2D = null     # rampa dust (verticale)
var _explosion_materials: Dictionary = {}       # key: html colore -> ParticleProcessMaterial
var _dust_materials: Dictionary = {}             # key: html accent -> ParticleProcessMaterial
var _light_gradient_cache: Dictionary = {}       # key: size -> ImageTexture (create_light)


func _get_particle_dot_tex() -> Texture2D:
        if _particle_dot_tex == null:
                _particle_dot_tex = _make_radial_gradient_texture(8)
        return _particle_dot_tex


func _get_fade_ramp_1d() -> GradientTexture1D:
        if _fade_ramp_1d == null:
                var grad := Gradient.new()
                grad.set_color(0, Color(1, 1, 1, 1))
                grad.set_color(1, Color(1, 1, 1, 0))
                var tex := GradientTexture1D.new()
                tex.gradient = grad
                _fade_ramp_1d = tex
        return _fade_ramp_1d


func _get_smoke_ramp_1d() -> GradientTexture1D:
        if _smoke_ramp_1d == null:
                var grad := Gradient.new()
                grad.set_color(0, Color(1, 1, 1, 1))
                grad.add_point(0.25, Color(1, 1, 1, 0.85))
                grad.set_color(1, Color(1, 1, 1, 0))
                var tex := GradientTexture1D.new()
                tex.gradient = grad
                _smoke_ramp_1d = tex
        return _smoke_ramp_1d


func _get_explosion_material(color: Color) -> ParticleProcessMaterial:
        # Parametri FISSI di spawn_explosion: l'unica variabile e' il colore.
        var key: String = color.to_html()
        if _explosion_materials.has(key):
                return _explosion_materials[key]
        var mat := ParticleProcessMaterial.new()
        mat.direction = Vector3(0, 0, 0)
        mat.spread = 180.0
        mat.initial_velocity_min = 50.0
        mat.initial_velocity_max = 200.0
        mat.gravity = Vector3(0, 200, 0)
        mat.scale_min = 2.0
        mat.scale_max = 5.0
        mat.color = color
        mat.emission_sphere_radius = 4.0
        mat.color_ramp = _get_fade_ramp_1d()
        _explosion_materials[key] = mat
        return mat


func _get_dust_material(accent_color: Color) -> ParticleProcessMaterial:
        var key: String = accent_color.to_html()
        if _dust_materials.has(key):
                return _dust_materials[key]
        var mat := ParticleProcessMaterial.new()
        mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
        mat.emission_sphere_radius = 3.0
        mat.direction = Vector3(0, -1, 0)
        mat.spread = 35.0
        mat.initial_velocity_min = 8.0
        mat.initial_velocity_max = 18.0
        mat.gravity = Vector3(0, 30, 0)
        mat.scale_min = 0.6
        mat.scale_max = 1.4
        mat.color = accent_color
        mat.color_ramp = _get_dust_ramp_2d()
        _dust_materials[key] = mat
        return mat


func _get_dust_ramp_2d() -> GradientTexture2D:
        if _dust_ramp_2d == null:
                var ramp_tex := GradientTexture2D.new()
                ramp_tex.gradient = _make_dust_ramp()
                ramp_tex.fill = 0  # FILL_LINEAR (verticale)
                ramp_tex.fill_from = Vector2(0.5, 0.0)
                ramp_tex.fill_to = Vector2(0.5, 1.0)
                _dust_ramp_2d = ramp_tex
        return _dust_ramp_2d


func _ready() -> void:
        # Crea il materiale fire shader (con time animato)
        _fire_material = ShaderMaterial.new()
        _fire_material.shader = FIRE_SHADER
        # Crea il materiale lightning shader
        _lightning_material = ShaderMaterial.new()
        _lightning_material.shader = LIGHTNING_SHADER


func _process(delta: float) -> void:
        # Aggiorna il time degli shader animati
        if _fire_material:
                _fire_material.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
        if _lightning_material:
                _lightning_material.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
        # Screen shake: decresce gradualmente
        if _shake_timer > 0.0:
                _shake_timer -= delta
                var intensity: float = _shake_amount * (_shake_timer / 0.3)
                _shake_offset = Vector2(
                        randf() * 2.0 - 1.0,
                        randf() * 2.0 - 1.0
                ) * intensity
                if _camera:
                        _camera.offset = _shake_offset
        else:
                if _camera:
                        _camera.offset = Vector2.ZERO


# ============================================================================
# Glow shader material (per sprite che devono brillare)
# ============================================================================
func get_glow_material(color: Color = Color(1.0, 0.84, 0.0, 1.0),
                intensity: float = 0.5, radius: float = 8.0) -> ShaderMaterial:
        var key: String = "%s_%.2f_%.1f" % [str(color), intensity, radius]
        if _glow_materials.has(key):
                return _glow_materials[key]
        var mat := ShaderMaterial.new()
        mat.shader = GLOW_SHADER
        mat.set_shader_parameter("glow_color", color)
        mat.set_shader_parameter("glow_intensity", intensity)
        mat.set_shader_parameter("glow_radius", radius)
        _glow_materials[key] = mat
        return mat


# ============================================================================
# Fire shader material (per nemici che bruciano)
# ============================================================================
func get_fire_material() -> ShaderMaterial:
        return _fire_material


func set_burn_effect(sprite: Sprite2D, burning: bool) -> void:
        if burning:
                if not (sprite.material is ShaderMaterial and \
                   sprite.material.shader == FIRE_SHADER):
                        sprite.material = _fire_material
        else:
                if sprite.material is ShaderMaterial and \
                   sprite.material.shader == FIRE_SHADER:
                        sprite.material = null


# ============================================================================
# Lightning shader material (per nemici elettrificati)
# ============================================================================
func get_lightning_material() -> ShaderMaterial:
        return _lightning_material


func set_electrified_effect(sprite: Sprite2D, electrified: bool) -> void:
        if electrified:
                if not (sprite.material is ShaderMaterial and \
                   sprite.material.shader == LIGHTNING_SHADER):
                        sprite.material = _lightning_material
        else:
                if sprite.material is ShaderMaterial and \
                   sprite.material.shader == LIGHTNING_SHADER:
                        sprite.material = null


# ============================================================================
# PointLight2D - illuminazione dinamica 2D (vantaggio Godot)
# ============================================================================
func create_light(pos: Vector2, color: Color = Color(1.0, 0.84, 0.0, 1.0),
                energy: float = 1.0, radius: float = 128.0,
                texture_scale: float = 1.0) -> PointLight2D:
        var light := PointLight2D.new()
        light.position = pos
        light.color = color
        light.energy = energy
        light.texture_scale = texture_scale
        light.range_z_min = -10
        light.range_z_max = 10
        # TASK 79d: texture di luce procedurale CACHEATA per dimensione
        # (era un Image + upload GPU per OGNI luce creata).
        var tex := _get_light_texture(int(radius * 2))
        light.texture = tex
        return light


## Crea/riusa una texture di gradiente radiale per le luci (TASK 79d cache).
func _get_light_texture(size: int) -> ImageTexture:
        if _light_gradient_cache.has(size):
                return _light_gradient_cache[size]
        var tex := _make_radial_gradient_texture(size)
        _light_gradient_cache[size] = tex
        return tex


# Crea una texture di gradiente radiale per le luci
func _make_radial_gradient_texture(size: int) -> ImageTexture:
        var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
        var center := Vector2(size / 2.0, size / 2.0)
        var max_dist: float = size / 2.0
        for y in size:
                for x in size:
                        var d: float = Vector2(x, y).distance_to(center) / max_dist
                        var alpha: float = clamp(1.0 - d, 0.0, 1.0)
                        alpha = alpha * alpha  # falloff quadratico
                        img.set_pixel(x, y, Color(1, 1, 1, alpha))
        var tex := ImageTexture.create_from_image(img)
        return tex


# ============================================================================
# GPUParticles2D - sistema particellare hardware (vantaggio Godot)
# ============================================================================
## TASK 56: sprite fireball pixel-art one-shot da sheet 4 frame 64x64.
class ExplosionSprite extends Node2D:
        var sheet: Texture2D = null
        var frame_ms: float = 100.0
        var display_px: float = 96.0
        var _elapsed: float = 0.0

        func _ready() -> void:
                set_process(true)

        func _process(delta: float) -> void:
                _elapsed += delta * 1000.0
                queue_redraw()
                if _elapsed > 4.0 * frame_ms + 40.0:
                        queue_free()

        func _draw() -> void:
                if sheet == null:
                        return
                var fi := int(_elapsed / frame_ms)
                fi = clampi(fi, 0, 3)
                var src := Rect2(float(fi) * 64.0, 0.0, 64.0, 64.0)
                var dst := Rect2(-display_px * 0.5, -display_px * 0.5,
                        display_px, display_px)
                draw_texture_rect_region(sheet, dst, src)

# Cache sheet esplosione PixelLab (TASK 56).
var _explosion_sheet_cache: Texture2D = null
var _explosion_sheet_tried: bool = false

# TASK 91 — prewarm dei contenuti lazy usati alla DISTRUZIONE degli
# elementi ambientali (boss room e labirinto): sheet esplosione, texture
# puntino e materiali fumo/esplosione per le tinte della polvere dei
# crolli. Da chiamare all'avvio della stanza: elimina i first-use hitch
# (Image.load da disco + upload GPU + creazione materiali) dal frame del
# crollo, che e' esattamente quando il player nota lo scatto.
func prewarm() -> void:
        _get_explosion_sheet()
        _get_particle_dot_tex()
        # tinte della polvere dei crolli (BossArenaRuin/Pillar/barili)
        _get_smoke_material(Color(0.45, 0.40, 0.34))
        _get_smoke_material(Color(0.42, 0.38, 0.34))
        _get_explosion_material(Color(1.0, 0.4, 0.1))
        _get_explosion_material(Color(1.0, 0.9, 0.3))
        _get_explosion_material(Color(0.42, 0.38, 0.34))

func _get_explosion_sheet() -> Texture2D:
        if _explosion_sheet_tried:
                return _explosion_sheet_cache
        _explosion_sheet_tried = true
        var path := "res://assets/sprites/effect_explosion_sheet.png"
        var abs_path: String = ProjectSettings.globalize_path(path)
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        _explosion_sheet_cache = ImageTexture.create_from_image(img)
        return _explosion_sheet_cache

func spawn_explosion(pos: Vector2, color: Color = Color(1.0, 0.4, 0.1),
                count: int = 30, lifetime: float = 0.8) -> Node2D:
        # TASK 56: contenitore con fireball pixel-art + particelle detriti.
        # I chiamanti fanno solo add_child(): il tipo di ritorno e' trasparente.
        var root := Node2D.new()
        root.position = pos
        # TASK 57: gruppo che identifica i container FX (fireball +
        # particelle) nei loop dei nodi proiettili (lezione Task 39:
        # gli effetti aggiunti ai nodi proiettili NON sono proiettili)
        root.add_to_group("fx_effect")
        if C.EXPLOSION_SPRITE_ENABLED:
                var spr := ExplosionSprite.new()
                spr.sheet = _get_explosion_sheet()
                # scala visiva con la potenza dell'esplosione (lifetime)
                spr.display_px = 72.0 + 48.0 * clampf(lifetime, 0.4, 1.0)
                root.add_child(spr)
        var particles := GPUParticles2D.new()
        particles.amount = count
        particles.lifetime = lifetime
        particles.one_shot = true
        particles.emitting = true
        # TASK 79d: materiale CACHATO per colore (niente ParticleProcessMaterial
        # + GradientTexture1D + texture 8x8 ricreati e ri-uploaded per spawn).
        particles.process_material = _get_explosion_material(color)
        particles.texture = _get_particle_dot_tex()
        # TASK 56: particelle dentro il contenitore; auto-remove del
        # contenitore quando le particelle terminano (la fireball si e'
        # gia' auto-liberata dopo i 4 frame)
        root.add_child(particles)
        particles.finished.connect(root.queue_free)
        return root


func spawn_blood(pos: Vector2, count: int = 15) -> Node2D:
        return spawn_explosion(pos, Color(0.7, 0.05, 0.05), count, 0.5)


## TASK 50 (pallini arancioni in boss room): nube d'esplosione MORBIDA.
## spawn_explosion fa 30 palline tonde piccole (scale 2-5 su texture 8px):
## a distanza sembrano "pallini" fluttuanti. Qui invece poche volute GRANDI
## (scale 7-16) con gravita' leggera e fade graduale: si legge come fumo
## d'esplosione, non come punti. `ember_tint` al 25% dà solo un accenno
## caldo in testa alla nube.
func spawn_blast_smoke(pos: Vector2, ember_tint: Color = Color(1.0, 0.45, 0.15),
                count: int = 9) -> GPUParticles2D:
        var particles := GPUParticles2D.new()
        particles.position = pos
        particles.amount = count
        particles.lifetime = 0.75
        particles.one_shot = true
        particles.emitting = true
        particles.explosiveness = 0.65
        # TASK 79d: materiale CACHATO per tinta (i parametri sono fissi).
        particles.process_material = _get_smoke_material(ember_tint)
        particles.texture = _get_particle_dot_tex()
        particles.finished.connect(particles.queue_free)
        # scintille calde in testa alla nube (poche e brevi)
        return particles


## TASK 79d — materiale del fumo, cachato per tinta della brace.
func _get_smoke_material(ember_tint: Color) -> ParticleProcessMaterial:
        var key: String = ember_tint.to_html()
        if _explosion_materials.has("smoke_" + key):
                return _explosion_materials["smoke_" + key]
        var mat := ParticleProcessMaterial.new()
        mat.direction = Vector3(0, -1, 0)
        mat.spread = 80.0
        mat.initial_velocity_min = 26.0
        mat.initial_velocity_max = 74.0
        mat.gravity = Vector3(0, -14, 0)  # il fumo SALE
        mat.scale_min = 7.0
        mat.scale_max = 16.0
        # fumo scuro con un accenno caldo (25% verso la tinta brace)
        mat.color = Color(0.26, 0.24, 0.22, 0.82).lerp(
                        Color(ember_tint.r, ember_tint.g, ember_tint.b, 0.82), 0.25)
        mat.color_ramp = _get_smoke_ramp_1d()
        _explosion_materials["smoke_" + key] = mat
        return mat


func spawn_sparks(pos: Vector2, count: int = 12) -> Node2D:
        return spawn_explosion(pos, Color(1.0, 0.9, 0.3), count, 0.4)


func spawn_pickup_burst(pos: Vector2, color: Color = Color(1.0, 0.84, 0.0)) -> Node2D:
        return spawn_explosion(pos, color, 20, 0.6)


func spawn_lightning_bolt(from: Vector2, to: Vector2) -> GPUParticles2D:
        # Particelle lungo la linea del fulmine
        var mid := (from + to) / 2.0
        var particles := GPUParticles2D.new()
        particles.position = mid
        particles.amount = 40
        particles.lifetime = 0.3
        particles.one_shot = true
        particles.emitting = true
        # TASK 79d: materiale CACHATO (parametri fissi).
        particles.process_material = _get_lightning_material()
        particles.texture = _get_particle_dot_tex()
        particles.finished.connect(particles.queue_free)
        return particles


## TASK 79d — materiale particellare del fulmine, cachato (parametri fissi).
func _get_lightning_material() -> ParticleProcessMaterial:
        if _explosion_materials.has("lightning"):
                return _explosion_materials["lightning"]
        var mat := ParticleProcessMaterial.new()
        mat.direction = Vector3(0, -1, 0)
        mat.spread = 30.0
        mat.initial_velocity_min = 100.0
        mat.initial_velocity_max = 300.0
        mat.gravity = Vector3(0, 0, 0)
        mat.scale_min = 1.0
        mat.scale_max = 3.0
        mat.color = Color(0.5, 0.8, 1.0)
        mat.color_ramp = _get_fade_ramp_1d()
        _explosion_materials["lightning"] = mat
        return mat


# (gradient helper removed - inlined into spawn_explosion and spawn_lightning_bolt)


# ============================================================================
# Screen shake - effetto camera su impatti
# ============================================================================
func set_camera(cam: Camera2D) -> void:
        _camera = cam


func screen_shake(amount: float = 8.0, duration: float = 0.3) -> void:
        _shake_amount = max(_shake_amount, amount)
        _shake_timer = max(_shake_timer, duration)


# ============================================================================
# Vignette post-processing - applica a un CanvasLayer/ColorRect
# ============================================================================
func create_vignette_rect() -> ColorRect:
        var rect := ColorRect.new()
        rect.set_anchors_preset(Control.PRESET_FULL_RECT)
        rect.color = Color(1, 1, 1, 1)
        var mat := ShaderMaterial.new()
        mat.shader = VIGNETTE_SHADER
        mat.set_shader_parameter("vignette_intensity", 0.6)
        mat.set_shader_parameter("vignette_color", Vector3(0, 0, 0))
        rect.material = mat
        rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
        return rect


# ============================================================================
# Walk cycle light/shadow shader (complements DeformableSprite).
# ============================================================================
# Returns a cached ShaderMaterial for the given accent color. Each unique
# accent color gets its own material instance so multiple enemies with
# different accents can coexist without stepping on each other's uniforms.
func get_walk_cycle_material(accent_color: Color = Color(1.0, 0.5, 0.2, 1.0)) -> ShaderMaterial:
        var key: String = "walk_%s" % str(accent_color.to_html())
        if _walk_cycle_materials.has(key):
                return _walk_cycle_materials[key]
        var mat := ShaderMaterial.new()
        mat.shader = WALK_CYCLE_SHADER
        mat.set_shader_parameter("accent_color", accent_color)
        mat.set_shader_parameter("walk_phase", 0.0)
        mat.set_shader_parameter("walk_speed", 8.0)
        mat.set_shader_parameter("facing_right", 1.0)
        mat.set_shader_parameter("time", 0.0)
        mat.set_shader_parameter("shadow_strength", 0.35)
        mat.set_shader_parameter("saturation_boost", 1.12)
        _walk_cycle_materials[key] = mat
        return mat


# Update the walk-cycle shader uniforms on a CanvasItem's material.
# Call this every frame from the Enemy/MiniBoss update method.
func update_walk_cycle(canvas_item: CanvasItem, walk_phase: float,
                facing_right: bool, time_sec: float,
                walk_speed: float = 8.0) -> void:
        if canvas_item == null or canvas_item.material == null:
                return
        var mat: ShaderMaterial = canvas_item.material as ShaderMaterial
        if mat == null:
                return
        mat.set_shader_parameter("walk_phase", walk_phase)
        mat.set_shader_parameter("walk_speed", walk_speed)
        mat.set_shader_parameter("facing_right", 1.0 if facing_right else 0.0)
        mat.set_shader_parameter("time", time_sec)


# Attach the walk-cycle shader to a CanvasItem. The accent color is used to
# tint the warm pulse (per-enemy-type variation).
func apply_walk_cycle(canvas_item: CanvasItem,
                accent_color: Color = Color(1.0, 0.5, 0.2, 1.0)) -> void:
        if canvas_item == null:
                return
        canvas_item.material = get_walk_cycle_material(accent_color)


# ============================================================================
# Dust particles under feet (for walking enemies/minibosses).
# ============================================================================
# Spawns a small puff of dust at the given world position. The puff is a
# GPUParticles2D with ~8 particles that fade quickly. Caller should add the
# returned node to the scene tree (e.g. as a child of the main game node)
# and the puff will auto-free after its lifetime.
var _dust_puffs_active: int = 0  # cap to avoid runaway particle counts
const MAX_DUST_PUFFS: int = 64

func spawn_dust_puff(world_pos: Vector2,
                accent_color: Color = Color(0.6, 0.55, 0.45, 1.0)) -> GPUParticles2D:
        if _dust_puffs_active >= MAX_DUST_PUFFS:
                return null
        var p := GPUParticles2D.new()
        p.position = world_pos
        p.emitting = true
        p.one_shot = true
        p.amount = 8
        p.lifetime = 0.4
        p.explosiveness = 0.8
        p.fixed_fps = 30
        # TASK 79d: materiale CACHATO per accent (niente material +
        # GradientTexture2D ricreati per ogni puff di polvere).
        p.process_material = _get_dust_material(accent_color)
        _dust_puffs_active += 1
        return p


# Build a gradient for the dust ramp (white -> transparent).
# Cached after first call.
var _dust_ramp: Gradient = null
func _make_dust_ramp() -> Gradient:
        if _dust_ramp != null:
                return _dust_ramp
        _dust_ramp = Gradient.new()
        _dust_ramp.set_color(0, Color(1, 1, 1, 0.9))
        _dust_ramp.set_offset(0, 0.0)
        _dust_ramp.set_color(1, Color(1, 1, 1, 0.0))
        _dust_ramp.set_offset(1, 1.0)
        # Intermediate point for smoother fade
        _dust_ramp.add_point(0.5, Color(1, 1, 1, 0.5))
        return _dust_ramp


# Called by the scene tree when a dust puff node is freed.
func notify_dust_puff_freed() -> void:
        if _dust_puffs_active > 0:
                _dust_puffs_active -= 1
