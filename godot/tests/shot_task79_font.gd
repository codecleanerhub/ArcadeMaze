## shot_task79_font.gd — TASK 79: verifica RENDERING del font BMFont
## "Arcadia Gothic" (oro/osso/pietra) generato a mano (nessuna licenza).
##
## Scopo: dimostrare che i .fnt si caricano via load() e che i glifi
## renderizzano a taglie intere (16/32/48) SENZA tofu (quadrati vuoti).
## Controlli: "&" (credits), "•" (hint ConfigJoy), "—" (reliquia),
## accenti minuscoli IT (àèéìòù -> art maiuscola), slash e punteggiatura.
##
## Avvio (Xvfb): scripts/xvfb_shot.sh 1920x1080 res://tests/shot_task79_font.tscn
extends Node2D

var t: float = 0.0
var stage: int = 0
var f_gold: Font = null
var f_bone: Font = null
var f_stone: Font = null
var f_ttf: Font = null
var missing: Array = []


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        f_gold = load("res://assets/fonts/arcadia_gothic_gold_32.fnt")
        f_bone = load("res://assets/fonts/arcadia_gothic_bone_32.fnt")
        f_stone = load("res://assets/fonts/arcadia_gothic_stone_32.fnt")
        f_ttf = load("res://assets/fonts/arcadia_gothic_gold_48.fnt")  # variante 48px
        for nm in [["gold", f_gold], ["bone", f_bone], ["stone", f_stone], ["gold48", f_ttf]]:
                if nm[1] == null:
                        missing.append(nm[0])
        print("[SHOT79] font caricati: ", "KO " + str(missing) if not missing.is_empty() else "OK 4/4")
        # QA glifi: ogni carattere chiave deve avere un glifo mappato
        var keys := "ARCADE MAZE FANTASY 0123456789 .,:;!?-'\"()/+%=*_&•—–ÀÈÉÌÒÙàèéìòù"
        for f in [f_gold, f_bone, f_stone]:
                if f == null:
                        continue
                for ch in keys:
                        if not f.has_char(ch.unicode_at(0)):
                                missing.append("%s:%s" % [str(f), ch])
        print("[SHOT79] glifi mancanti: ", missing if not missing.is_empty() else "NESSUNO ✓")


func _process(delta: float) -> void:
        t += delta
        if stage == 0 and t > 2.0:
                _capture("task79_font_render.png")
                stage = 1
        elif stage == 1:
                get_tree().quit(0)


func _draw() -> void:
        var bg := Rect2(0, 0, 1920, 1080)
        draw_rect(bg, Color(0.07, 0.07, 0.09))
        var x := 60.0
        var y := 40.0
        if f_ttf != null:
                draw_string(f_ttf, Vector2(x, y + 48), "ARCADE MAZE FANTASY",
                        HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color.WHITE)
                y += 90
        if f_gold != null:
                draw_string(f_gold, Vector2(x, y + 32), "HALL OF FAME - CREDITS",
                        HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE)
                y += 64
        if f_bone != null:
                draw_string(f_bone, Vector2(x, y + 32), "NUMBER OF PLAYERS: 1",
                        HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE)
                y += 60
                draw_string(f_bone, Vector2(x, y + 16), "MUSIC: ON  MODALITA: INFNITA àèéìòù",
                        HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
                y += 46
        if f_stone != null:
                draw_string(f_stone, Vector2(x, y + 32), "UP/DOWN TO SELECT - LEFT/RIGHT TO CHANGE",
                        HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE)
                y += 64
                draw_string(f_stone, Vector2(x, y + 32), "ESC TO CANCEL  •  STEP 1 OF 2",
                        HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE)
                y += 64
        if f_gold != null:
                draw_string(f_gold, Vector2(x, y + 32), "ART & GRAPHICS — STORY & WRITING",
                        HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE)
                y += 64
        if f_ttf != null:
                # variante 48px pre-scalata (titoli grandi): 1:1, zero blend
                draw_string(f_ttf, Vector2(x, y + 48), "GOLD 48: GIOCATORI 12",
                        HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color.WHITE)
                y += 86
        draw_string(ThemeDB.fallback_font, Vector2(x, y + 24),
                "check: KO=%s" % ("SI" if not missing.is_empty() else "NO"),
                HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.8, 0.2, 0.2))


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)
