## shot_loading_debug.gd — TASK 45: diagnostica deterministica dell'animazione
## delle gocce. Congela _anim_t a valori fissi (dopo show_loading) e cattura
## dopo RenderingServer.frame_post_draw (frame renderizzato = fase impostata).
extends Node

const OUT: String = "/home/z/my-project/download/"
var stage: int = 0
var t: float = 0.0
var busy: bool = false


func _ready() -> void:
        I18n.set_language(I18n.Language.ENGLISH)


func _physics_process(delta: float) -> void:
        t += delta
        if busy:
                return
        match stage:
                0:
                        if t > 0.4:
                                LoadingScreen.show_loading(false)
                                stage = 1
                                t = 0.0
                1:
                        if t > 0.02:
                                stage = 2
                                busy = true
                                # TASK 51 P6: fasi del ciclo PixelLab (2.4s):
                                # 0.30 = formazione, 1.35 = allungata,
                                # 2.05 = ritratto, 0.90 = cascata mista
                                _snap_at(0.30, "dbg_loading_form")
                2:
                        if t > 0.3:
                                stage = 3
                                busy = true
                                _snap_at(1.35, "dbg_loading_elong")
                3:
                        if t > 0.3:
                                stage = 4
                                busy = true
                                _snap_at(2.05, "dbg_loading_retract")
                4:
                        if t > 0.3:
                                stage = 5
                                busy = true
                                _snap_at(0.90, "dbg_loading_cascade")
                5:
                        if t > 0.3:
                                LoadingScreen.hide_loading()
                                get_tree().quit(0)


func _snap_at(anim_t: float, tag: String) -> void:
        LoadingScreen.set_anim_t_debug(anim_t)
        # aspetta il frame renderizzato con la fase CONGELATA
        await RenderingServer.frame_post_draw
        await RenderingServer.frame_post_draw
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png(OUT + tag + ".png")
        busy = false
        print("[DBG] ", tag, " anim_t=", LoadingScreen.get_anim_t())
