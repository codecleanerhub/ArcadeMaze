## Weapon.gd - Resource holding weapon stats and rendering helpers.
## ============================================================
## Godot port of `src/Weapon.{h,cpp}` (struct Weapon).
##
## Four weapon types matching the C++ enum:
##   * WPN_PISTOL  (ammo=15, power=1)
##   * WPN_SHOTGUN (ammo=8,  power=3)
##   * WPN_LASER   (ammo=20, power=2)
##   * WPN_ROCKET  (ammo=4,  power=5)
##
## Usage:
##   var w := Weapon.new()
##   w.generate(Weapon.WPN_SHOTGUN)
##   var name := w.get_name()
##   var color := w.get_color()
extends Resource
class_name Weapon

# ---- Weapon types (mirrors C++ enum WeaponType) ----
enum Type { WPN_PISTOL, WPN_SHOTGUN, WPN_ROCKET, WPN_LASER }

@export var type: int = Type.WPN_PISTOL:
	set(v):
		type = v
		_apply_defaults()

@export var power: int = 1
@export var ammo: int = 15


func _init() -> void:
	_apply_defaults()


# ---- Factory methods (mirror C++ Weapon::generate / generateRandom) ----

## Configure this instance for a specific weapon type.
func generate(t: int) -> void:
	type = t
	_apply_defaults()


## Pick a random weapon type and configure this instance.
func generate_random() -> void:
	type = randi() % 4
	_apply_defaults()


func get_weapon_name() -> String:
	match type:
		Type.WPN_PISTOL:  return "PISTOL"
		Type.WPN_SHOTGUN: return "SHOTGUN"
		Type.WPN_LASER:   return "LASER"
		Type.WPN_ROCKET:  return "ROCKET"
	return "?"


func get_color() -> Color:
	match type:
		Type.WPN_PISTOL:  return Color(0.78, 0.78, 0.20)
		Type.WPN_SHOTGUN: return Color(0.78, 0.39, 0.20)
		Type.WPN_LASER:   return Color(0.31, 0.78, 1.00)
		Type.WPN_ROCKET:  return Color(0.78, 0.20, 0.20)
	return Color.WHITE


# ---- Rendering helpers ----
# In C++ these were `render(target, x, y)` and `renderEquipped(...)`.
# In Godot we let the caller (an item node) draw a Sprite2D / Polygon2D using
# the data here. The helper functions below build the visual primitives.

## Build a list of (Rect2, Color) entries describing the weapon's shape on the
## ground (large, with shadow). Used by the maze renderer when a CELL_WEAPON
## is drawn.
func build_ground_primitives(x: float, y: float) -> Array:
	var out := []
	var col := get_color()
	# Shadow
	out.append({"rect": Rect2(x - 10, y + 6, 20, 4), "color": Color(0, 0, 0, 0.4)})
	match type:
		Type.WPN_PISTOL:
			out.append({"rect": Rect2(x - 2, y - 6, 4, 12), "color": col})
			out.append({"rect": Rect2(x - 4, y + 4, 8, 3), "color": Color(0.2, 0.2, 0.2)})
		Type.WPN_SHOTGUN:
			out.append({"rect": Rect2(x - 3, y - 8, 6, 14), "color": col})
			out.append({"rect": Rect2(x - 5, y + 4, 10, 3), "color": Color(0.2, 0.2, 0.2)})
		Type.WPN_LASER:
			out.append({"rect": Rect2(x - 2, y - 10, 4, 16), "color": col})
			out.append({"rect": Rect2(x - 4, y + 5, 8, 3), "color": Color(0.2, 0.2, 0.2)})
		Type.WPN_ROCKET:
			out.append({"rect": Rect2(x - 3, y - 6, 6, 12), "color": col})
			# Triangular tip
			out.append({"tri": [Vector2(x - 3, y - 6), Vector2(x + 3, y - 6), Vector2(x, y - 12)], "color": col})
	return out


## Build equipped-in-hand primitives (smaller, optionally flipped).
func build_equipped_primitives(x: float, y: float, facing_right: bool = true) -> Array:
	var out := []
	var col := get_color()
	var dir := 1.0 if facing_right else -1.0
	match type:
		Type.WPN_PISTOL:
			out.append({"rect": Rect2(x, y - 3, 8 * dir, 4), "color": col})
		Type.WPN_SHOTGUN:
			out.append({"rect": Rect2(x, y - 4, 12 * dir, 5), "color": col})
		Type.WPN_LASER:
			out.append({"rect": Rect2(x, y - 2, 14 * dir, 3), "color": col})
		Type.WPN_ROCKET:
			out.append({"rect": Rect2(x, y - 3, 10 * dir, 6), "color": col})
			out.append({"tri": [Vector2(x + 10 * dir, y - 3), Vector2(x + 10 * dir, y + 3), Vector2(x + 16 * dir, y)], "color": col})
	return out


# ---- Internals ----

func _apply_defaults() -> void:
	match type:
		Type.WPN_PISTOL:
			power = 1
			ammo = 15
		Type.WPN_SHOTGUN:
			power = 3
			ammo = 8
		Type.WPN_LASER:
			power = 2
			ammo = 20
		Type.WPN_ROCKET:
			power = 5
			ammo = 4
	notify_property_list_changed()
