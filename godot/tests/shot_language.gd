## shot_language.gd — TASK 44: screenshot del sistema bilingue + Loading.
##
## Catture (in /home/z/my-project/download/):
##   1. lang_menu_en     — menu principale in ENGLISH (default)
##   2. lang_options_en  — sottomenu OPTIONS in ENGLISH (voce LANGUAGE: ENGLISH)
##   3. lang_options_it  — sottomenu OPTIONS in ITALIANO (LINGUA: ITALIANO,
##                         CONFIGURA JOYSTICK, INDIETRO)
##   4. lang_menu_it     — menu principale in ITALIANO (GIOCATORI, MODALITÀ...)
##   5. lang_loading_en  — overlay "Loading..." sangue SOLO sui 3 puntini
##                         (TASK 45: testo osseo + gocce realistiche; la
##                         cattura e' DETERMINISTICA: anim congelata a 1.69
##                         = fase ricca con goccia piena + distacco fresco
##                         + caduta in corso e scia)
##   6. lang_loading_it  — overlay "Caricamento..." stesso stile (IT)
##   + crop del pannello opzioni (entrambe le lingue) e della scritta.
extends Node

const MainMenuScene = preload("res://scenes/MainMenu.tscn")
const OUT: String = "/home/z/my-project/download/"
const LOADING_FREEZE_T: float = 1.69

var menu: Control = null
var stage: int = 0
var t: float = 0.0
var busy: bool = false


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        # Lingua deterministica: EN di default (richiesta utente).
        I18n.set_language(I18n.Language.ENGLISH)
        GameManager.num_players = 1
        menu = MainMenuScene.instantiate()
        get_tree().root.add_child.call_deferred(menu)
        print("[SHOT-LANG] boot MainMenu (EN)...")


func _capture(tag: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png(OUT + tag + ".png")
        print("[SHOT-LANG] salvato ", tag, ".png")


func _crop(tag: String, region: Rect2i) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.get_region(region).save_png(OUT + tag + ".png")
        print("[SHOT-LANG] salvato ", tag, ".png")


func _physics_process(delta: float) -> void:
        t += delta
        if menu == null or not menu.is_node_ready():
                return
        match stage:
                0:
                        if t > 2.2:
                                _capture("lang_menu_en")
                                stage = 1
                                t = 0.0
                1:
                        # Apri OPTIONS e cattura (ENGLISH).
                        if t > 0.9:
                                menu._set_in_options(true)
                                stage = 2
                                t = 0.0
                2:
                        if t > 0.9:
                                _capture("lang_options_en")
                                # crop pannello voci (centro-destra, TASK 26)
                                _crop("lang_options_en_crop",
                                        Rect2i(700, 250, 1220, 600))
                                # Toggle LANGUAGE (voce 1) -> ITALIANO
                                menu._menu_item_index = 1
                                menu._change_option(1)
                                stage = 3
                                t = 0.0
                3:
                        if t > 0.9:
                                _capture("lang_options_it")
                                _crop("lang_options_it_crop",
                                        Rect2i(700, 250, 1220, 600))
                                # BACK -> menu principale in ITALIANO
                                menu._menu_item_index = 3
                                menu._activate_current()
                                stage = 4
                                t = 0.0
                4:
                        if t > 0.9:
                                _capture("lang_menu_it")
                                stage = 5
                                t = 0.0
                5:
                        # Overlay Loading in EN (senza auto-hide).
                        # FIX: riporta prima la lingua a ENGLISH (era IT
                        # dalle catture del menu italiano).
                        if t > 0.9:
                                I18n.set_language(I18n.Language.ENGLISH)
                                LoadingScreen.show_loading(false)
                                stage = 6
                                t = 0.0
                6:
                        if t > 0.15 and not busy:
                                busy = true
                                _capture_loading("lang_loading_en")
                7:
                        if t > 0.5 and not busy:
                                # applica davvero la lingua IT prima di
                                # riattivare l'overlay.
                                I18n.set_language(I18n.Language.ITALIAN)
                                LoadingScreen.show_loading(false)
                                stage = 8
                                t = 0.0
                8:
                        if t > 0.15 and not busy:
                                busy = true
                                _capture_loading("lang_loading_it")
                9:
                        if t > 0.5:
                                # Ripristino EN (default) per l'utente.
                                I18n.set_language(I18n.Language.ENGLISH)
                                print("[SHOT-LANG] ==== CATTURE COMPLETATE (8) ====")
                                get_tree().quit(0)


## Cattura DETERMINISTICA dell'overlay loading: congela l'animazione a
## LOADING_FREEZE_T, aspetta i frame renderizzati, salva, sblocca.
func _capture_loading(tag: String) -> void:
        LoadingScreen.set_anim_t_debug(LOADING_FREEZE_T)
        await RenderingServer.frame_post_draw
        await RenderingServer.frame_post_draw
        _capture(tag)
        _crop(tag + "_crop", Rect2i(560, 300, 800, 420))
        LoadingScreen.unset_anim_t_debug()
        LoadingScreen.hide_loading()
        busy = false
        stage += 1
        t = 0.0
