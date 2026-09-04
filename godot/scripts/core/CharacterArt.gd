## CharacterArt.gd - Autoload per enhancement grafico personaggi.
##
## Fornisce shader material che migliorano la qualita' visiva degli
## sprite AI esistenti (player, enemy, boss, miniboss) senza rigenerarli:
##   - Sharpening (unsharp masking)
##   - Contrast + saturation boost
##   - Fake normal map per profondita' 3D
##   - Rim light sul contorno
##
## Vantaggio Godot-native: applica enhancement GPU a tutti gli sprite
## senza modificare i file PNG originali.
extends Node

const CHARACTER_SHADER = preload("res://shaders/character_enhanced.gdshader")
const RIM_SHADER = preload("res://shaders/rim_light.gdshader")
const FIRE_SHADER = preload("res://shaders/fire.gdshader")
const LIGHTNING_SHADER = preload("res://shaders/lightning.gdshader")

# Cache dei materiali shader (uno per tipo di enhancement)
var _enhanced_material: ShaderMaterial = null
var _rim_material: ShaderMaterial = null
var _enhanced_strong: ShaderMaterial = null  # per boss (piu' intenso)


func _ready() -> void:
        # Materiale enhancement standard (per player e enemy)
        _enhanced_material = ShaderMaterial.new()
        _enhanced_material.shader = CHARACTER_SHADER
        _enhanced_material.set_shader_parameter("sharpness", 0.6)
        _enhanced_material.set_shader_parameter("contrast", 1.12)
        _enhanced_material.set_shader_parameter("saturation", 1.18)
        _enhanced_material.set_shader_parameter("rim_intensity", 0.5)
        _enhanced_material.set_shader_parameter("depth_strength", 0.5)

        # Materiale enhancement forte (per boss e miniboss)
        _enhanced_strong = ShaderMaterial.new()
        _enhanced_strong.shader = CHARACTER_SHADER
        _enhanced_strong.set_shader_parameter("sharpness", 0.8)
        _enhanced_strong.set_shader_parameter("contrast", 1.2)
        _enhanced_strong.set_shader_parameter("saturation", 1.3)
        _enhanced_strong.set_shader_parameter("rim_intensity", 0.7)
        _enhanced_strong.set_shader_parameter("depth_strength", 0.7)


# Materiale enhancement standard (per player e enemy normali)
func get_enhanced_material() -> ShaderMaterial:
        return _enhanced_material


# Materiale enhancement forte (per boss e miniboss)
func get_enhanced_material_strong() -> ShaderMaterial:
        return _enhanced_strong


# Applica lo shader enhancement a uno Sprite2D.
# `strong` = true per boss/miniboss, false per player/enemy.
func apply_enhancement(sprite: Sprite2D, strong: bool = false) -> void:
        if sprite == null:
                return
        # Non sovrascrivere se c'e' gia' un fire/lightning shader attivo
        if sprite.material is ShaderMaterial:
                var current_shader: Shader = (sprite.material as ShaderMaterial).shader
                if current_shader == FIRE_SHADER or current_shader == LIGHTNING_SHADER:
                        return  # stato burning/electrified ha priorita'
        sprite.material = _enhanced_strong if strong else _enhanced_material


# Rimuovi lo shader enhancement da uno Sprite2D.
func remove_enhancement(sprite: Sprite2D) -> void:
        if sprite == null:
                return
        if sprite.material is ShaderMaterial:
                var current_shader: Shader = (sprite.material as ShaderMaterial).shader
                if current_shader == CHARACTER_SHADER:
                        sprite.material = null


# Applica lo shader enhancement a un CanvasItem generico (Node2D, Control, etc.).
# Usato per MiniBoss e Boss che renderizzano via draw_texture_rect invece di
# avere un nodo Sprite2D figlio.
func apply_enhancement_to_canvas_item(item: CanvasItem, strong: bool = false) -> void:
        if item == null:
                return
        # Non sovrascrivere se c'e' gia' un fire/lightning shader attivo
        if item.material is ShaderMaterial:
                var current_shader: Shader = (item.material as ShaderMaterial).shader
                if current_shader == FIRE_SHADER or current_shader == LIGHTNING_SHADER:
                        return
        item.material = _enhanced_strong if strong else _enhanced_material


# Rimuovi enhancement da CanvasItem generico.
func remove_enhancement_from_canvas_item(item: CanvasItem) -> void:
        if item == null:
                return
        if item.material is ShaderMaterial:
                var current_shader: Shader = (item.material as ShaderMaterial).shader
                if current_shader == CHARACTER_SHADER:
                        item.material = null
