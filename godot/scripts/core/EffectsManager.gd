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

# Cache dei materiali shader (per non ricrearli ogni volta)
var _glow_materials: Dictionary = {}
var _fire_material: ShaderMaterial = null
var _lightning_material: ShaderMaterial = null

# Screen shake state
var _shake_amount: float = 0.0
var _shake_timer: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO

# Camera target (se presente) per applicare lo shake
var _camera: Camera2D = null


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
        # Usa una texture di luce procedurale (cerchio sfumato)
        # In Godot 4 si puo' lasciare null e usa il default
        var tex := _make_radial_gradient_texture(int(radius * 2))
        light.texture = tex
        return light


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
func spawn_explosion(pos: Vector2, color: Color = Color(1.0, 0.4, 0.1),
                count: int = 30, lifetime: float = 0.8) -> GPUParticles2D:
        var particles := GPUParticles2D.new()
        particles.position = pos
        particles.amount = count
        particles.lifetime = lifetime
        particles.one_shot = true
        particles.emitting = true
        # Process material per particelle
        var mat := ParticleProcessMaterial.new()
        mat.direction = Vector3(0, 0, 0)
        mat.spread = 180.0
        mat.initial_velocity_min = 50.0
        mat.initial_velocity_max = 200.0
        mat.gravity = Vector3(0, 200, 0)  # gravita' verso il basso
        mat.scale_min = 2.0
        mat.scale_max = 5.0
        mat.color = color
        mat.emission_sphere_radius = 4.0
        # Fade out (Godot 4.7 color_ramp expects GradientTexture1D, not raw Gradient)
        var fade_tex := GradientTexture1D.new()
        var grad := Gradient.new()
        grad.set_color(0, Color(1, 1, 1, 1))
        grad.set_color(1, Color(1, 1, 1, 0))
        fade_tex.gradient = grad
        mat.color_ramp = fade_tex
        particles.process_material = mat
        # Texture della particella (cerchio piccolo)
        var tex := _make_radial_gradient_texture(8)
        particles.texture = tex
        # Auto-remove dopo la lifetime
        particles.finished.connect(particles.queue_free)
        return particles


func spawn_blood(pos: Vector2, count: int = 15) -> GPUParticles2D:
        return spawn_explosion(pos, Color(0.7, 0.05, 0.05), count, 0.5)


func spawn_sparks(pos: Vector2, count: int = 12) -> GPUParticles2D:
        return spawn_explosion(pos, Color(1.0, 0.9, 0.3), count, 0.4)


func spawn_pickup_burst(pos: Vector2, color: Color = Color(1.0, 0.84, 0.0)) -> GPUParticles2D:
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
        var mat := ParticleProcessMaterial.new()
        mat.direction = Vector3(0, -1, 0)
        mat.spread = 30.0
        mat.initial_velocity_min = 100.0
        mat.initial_velocity_max = 300.0
        mat.gravity = Vector3(0, 0, 0)
        mat.scale_min = 1.0
        mat.scale_max = 3.0
        mat.color = Color(0.5, 0.8, 1.0)
        var fade_tex2 := GradientTexture1D.new()
        var grad2 := Gradient.new()
        grad2.set_color(0, Color(1, 1, 1, 1))
        grad2.set_color(1, Color(1, 1, 1, 0))
        fade_tex2.gradient = grad2
        mat.color_ramp = fade_tex2
        particles.process_material = mat
        var tex := _make_radial_gradient_texture(8)
        particles.texture = tex
        particles.finished.connect(particles.queue_free)
        return particles


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
