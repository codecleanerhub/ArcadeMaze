## shot_stamina_colors.gd — Task 37: screenshot della barra STAMINA nei
## tre stati colore richiesti: ROSA piena (0 salti usati, 2 disponibili),
## ARANCIONE dopo il 1° salto (metà barra), ROSSA dopo il 2° salto (barra
## svuotata, player esausto: lampeggia con stub minimo visibile).
## Istanzia SOLO l'HUD (nessun MainGame: niente maze/nemici), forza gli
## stati via set_player_state e cattura full-screen + crop ingrandito della
## barra (per QA pixel + VLM).
extends Node2D

const HUD_SCRIPT := preload("res://scripts/ui/HUD.gd")

var hud: Control = null
var stage: int = 0
var t: float = 0.0

func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        var layer := CanvasLayer.new()
        layer.layer = 10
        add_child(layer)
        hud = HUD_SCRIPT.new()
        layer.add_child(hud)
        print("[SHOT-STAMINA] HUD montata su CanvasLayer 10")


func _process(delta: float) -> void:
        t += delta
        match stage:
                0:
                        if hud != null and hud.is_node_ready() and t > 0.6:
                                _set_state(1.0, false)    # VERDE: piena, 0 salti usati (TASK 96, era rosa)
                                stage = 1
                                t = 0.0
                1:
                        if t > 0.3:
                                _capture("stamina_1_green")
                                _set_state(0.5, false)    # ARANCIONE: 1° salto fatto
                                stage = 2
                                t = 0.0
                2:
                        if t > 0.3:
                                _capture("stamina_2_orange")
                                _set_state(0.0, true)     # ROSSO: 2° salto, esausto
                                stage = 3
                                t = 0.0
                3:
                        # Il lampeggio rosso va RIDISEGNATO ogni frame (la HUD
                        # ridisegna solo su queue_redraw). Aspetto la fase ACCESA
                        # (periodo 0.36s, duty 50%) prima di catturare.
                        hud.queue_redraw()
                        if t > 0.3 and fmod(Time.get_ticks_msec() / 1000.0, 0.36) < 0.18:
                                stage = 4
                                t = 0.0
                4:
                        # Il frame precedente è stato renderizzato in fase ON:
                        # la texture contiene lo stub ROSSO brillante.
                        _capture("stamina_3_red")
                        print("[SHOT-STAMINA] 3 stati catturati: verde, arancione, rosso")
                        get_tree().quit(0)


func _set_state(ratio: float, exhausted: bool) -> void:
        hud.set_num_players(1)
        hud.set_player_state({
                "score": 12345, "lives": 3,
                "energy": 100.0, "max_energy": 100.0,
                "weapon_name": "PISTOL",
                "weapon_color": Color(0.784, 0.784, 0.196),
                "weapon_ammo": 15, "weapon_max": 15,
                "stamina": ratio, "stamina_exhausted": exhausted,
        })
        hud.set_remaining_treasures(12)


func _capture(tag: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + tag + ".png")
        # Crop sulla zona ENERGY + STAMINA (layout 1P: barra stamina a
        # x=280..380, y=52..62) ingrandito 4x per ispezione visiva.
        var crop: Image = img.get_region(Rect2i(258, 26, 190, 52))
        crop.resize(760, 208, Image.INTERPOLATE_NEAREST)
        crop.save_png("/home/z/my-project/download/" + tag + "_crop.png")
        print("[SHOT-STAMINA] salvato ", tag, " (+crop barra)")
