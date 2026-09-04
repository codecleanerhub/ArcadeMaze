extends Control

# SelectPlayer.gd - Selezione personaggio (ruota 8 personaggi)
# Porting di Game.cpp STATE_SELECT_PLAYER

signal player_selected(character_index: int, player_num: int)

const CHARACTERS: Array[String] = [
	"player1", "player2", "char_mage", "char_orc",
	"char_elf", "char_knight", "char_golem", "char_vampire", "char_dragon"
]
const CHARACTER_NAMES: Array[String] = [
	"HERO", "HEROINE", "MAGE", "ORC", "ELF", "KNIGHT", "GOLEM", "VAMPIRE", "DRAGON"
]

var current_index: int = 0
var player_num: int = 1  # 1 or 2
var wheel_rotation: float = 0.0
var wheel_target: int = 0

@onready var preview: Sprite2D = $CharacterWheel/Preview
@onready var player_label: Label = $PlayerLabel
@onready var hint: Label = $Hint

func _ready() -> void:
	player_label.text = "PLAYER " + str(player_num) if player_num > 0 else "PLAYER 1"
	_update_preview()

func _process(delta: float) -> void:
	# Anima la rotazione verso wheel_target
	if current_index != wheel_target:
		wheel_rotation += 0.15 * 60.0 * delta
		if wheel_rotation >= 1.0:
			wheel_rotation = 0.0
			var diff := wheel_target - current_index
			if diff > 4: diff -= 8
			elif diff < -4: diff += 8
			if diff > 0: current_index = (current_index + 1) % 8
			elif diff < 0: current_index = (current_index - 1 + 8) % 8
			_update_preview()
	
	# Input
	if Input.is_action_just_pressed("move_left"):
		wheel_target = (wheel_target + 1) % 8
		AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
	elif Input.is_action_just_pressed("move_right"):
		wheel_target = (wheel_target - 1 + 8) % 8
		AudioManager.play_sound(AudioManager.SoundType.MENU_SELECT)
	elif Input.is_action_just_pressed("confirm"):
		AudioManager.play_sound(AudioManager.SoundType.MENU_CONFIRM)
		player_selected.emit(current_index, player_num)

func _update_preview() -> void:
	var path := "res://assets/sprites/" + CHARACTERS[current_index] + "_sheet.png"
	if ResourceLoader.exists(path):
		preview.texture = load(path)
	# Mostra solo il primo frame (64x64 da sheet 256x64)
	if preview.texture:
		var region := Rect2(0, 0, 64, 64)
		var atlas := AtlasTexture.new()
		atlas.atlas = preview.texture
		atlas.region = region
		preview.texture = atlas
	hint.text = CHARACTER_NAMES[current_index] + " - LEFT/RIGHT TO CHOOSE, ENTER TO CONFIRM"
