## shot_task67_player_facing.gd — TASK 67 (feedback utente: "heroine,
## knight, elf, golem si girano dal lato opposto al verso di movimento").
##
## Harness QA: TUTTI i 9 personaggi, ciascuno mostrato DUE volte — in
## movimento verso DESTRA (last_dx=+1) e verso SINISTRA (last_dx=-1) —
## passando dal PERCORSO REALE di gioco: Player.load_character_sprite()
## + Player._update_sprite() con la tabella SPRITE_DEFAULT_FACES_RIGHT.
##
## Avvio (Xvfb, NON headless — get_image() richiede un renderer reale):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task67_player_facing.tscn
extends Node2D

const PlayerClass = preload("res://scripts/core/Player.gd")
const C = preload("res://scripts/core/GameConstants.gd")

const CHARS := [
        [C.CharacterType.HERO_M, "player1 (HERO_M)"],
        [C.CharacterType.HERO_F, "player2 (HERO_F)"],
        [C.CharacterType.MAGE, "char_mage"],
        [C.CharacterType.ORC, "char_orc"],
        [C.CharacterType.ELF, "char_elf"],
        [C.CharacterType.KNIGHT, "char_knight"],
        [C.CharacterType.GOLEM, "char_golem"],
        [C.CharacterType.DRAGON, "char_dragon"],
        [C.CharacterType.VAMPIRE, "char_vampire"],
]

var t: float = 0.0
var players: Array = []
var captured: bool = false


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var bg := ColorRect.new()
        bg.color = Color(0.09, 0.08, 0.12)
        bg.size = Vector2(1920, 1080)
        bg.z_index = -10
        add_child(bg)

        _label(Vector2(960, 50),
                        "TASK 67 — FACING PLAYER: ogni personaggio in cammino → destra e ← sinistra",
                        32, true, Color(0.94, 0.88, 0.72))
        _label(Vector2(480, 110), "MOVIMENTO → DESTRA (last_dx = +1)",
                        26, true, Color(0.5, 0.9, 0.6))
        _label(Vector2(1440, 110), "MOVIMENTO ← SINISTRA (last_dx = -1)",
                        26, true, Color(0.9, 0.6, 0.5))

        for i in CHARS.size():
                var row_y: float = 190.0 + i * 100.0
                _label(Vector2(120, row_y + 8), CHARS[i][1], 20, false,
                                Color(0.78, 0.76, 0.70))
                _spawn(480.0, row_y, CHARS[i][0], 1)
                _spawn(1440.0, row_y, CHARS[i][0], -1)


func _spawn(at_x: float, at_y: float, ctype: int, dx: int) -> void:
        var p := PlayerClass.new()
        var spr := Sprite2D.new()
        spr.name = "Sprite2D"
        p.add_child(spr)
        add_child(p)
        p.character_type = ctype
        p.load_character_sprite()
        p.last_dx = dx
        p.dx = dx  # walk cycle attivo (frame selection usa dx/dy)
        p.anim_time = 160.0
        p._update_sprite()
        p.position = Vector2(at_x, at_y)
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
        # anima il ciclo di camminata (come fa il gioco) e cattura a t>1s
        var ms := int(delta * 1000.0)
        for p in players:
                p.anim_time += float(ms)
                p._update_sprite()
        if t > 1.2 and not captured:
                captured = true
                var img := get_viewport().get_texture().get_image()
                img.save_png("/home/z/my-project/download/task67_player_facing.png")
                print("[SHOT] salvato task67_player_facing.png")
                get_tree().quit(0)
