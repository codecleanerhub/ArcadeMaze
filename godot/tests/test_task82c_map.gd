## Verifica runtime del mapping type -> sprite id (per la rimappa del
## feedback utente sullo shot task82_facing_muzzle).
extends Node


func _ready() -> void:
	var EnemyClass = preload("res://scripts/enemies/Enemy.gd")
	var MiniBossClass = preload("res://scripts/bosses/MiniBoss.gd")
	print("=== ENEMY: type value -> sprite id (label nel vecchio sheet = m%03d) ===")
	for i in range(0, 46):
		var sid: String = EnemyClass.get_sprite_id(i)
		print("type %2d -> %-12s  (vecchia label m%03d)" % [i, sid if sid != "" else "<NESSUNO>", i])
	print("=== MINIBOSS: type value -> sprite id (label = mb%02d) ===")
	for i in range(0, 52):
		var sid: String = MiniBossClass.get_sprite_id(i)
		print("type %2d -> %-12s  (vecchia label mb%02d)" % [i, sid, i])
	get_tree().quit(0)
