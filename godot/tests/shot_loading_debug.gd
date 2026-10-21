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
                                _snap_at(1.10, "dbg_loading_110")
                2:
                        if t > 0.3:
                                stage = 3
                                busy = true
                                _snap_at(1.69, "dbg_loading_169")
                3:
                        if t > 0.3:
                                stage = 4
                                busy = true
                                _snap_at(2.30, "dbg_loading_230")
                4:
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
