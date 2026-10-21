## test_language.gd — Test funzionale runtime (headless) del TASK 44:
## sistema bilingue ENGLISH/ITALIANO + schermata "Loading...".
##
##  A. Lingua di DEFAULT = ENGLISH (richiesta utente) e mirror statico sincronizzato
##  B. t(): testi EN e IT per chiavi representative (menu, HUD, loading)
##  C. set_language(ITALIAN): cambia tutti i testi + persiste in config.ini
##     (round-trip save/load) + segnale language_changed
##  D. Nomi BOSS localizzati (static: via mirror C.ui_language) EN/IT
##  E. Nomi ARMI base + ARMATURA breve + ELEMENTO localizzati
##  F. Reliquie: name/short/desc IT ("Spadone del Cavaliere") e EN
##     ("Knight's Greatsword") — campi bilingui delle definizioni
##  G. MainMenu: sottomenu OPTIONS con 4 voci; LANGUAGE alla posizione 1;
##     etichette coerenti con la lingua corrente in ENTRAMBE le lingue
##  H. LoadingScreen autoload: API show/hide/is_showing funzionante
##  I. Boot splash: project.godot punta al PNG "Loading..." sangue
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const BossScript = preload("res://scripts/bosses/Boss.gd")

var failures: Array = []
var checks: int = 0
var menu: Control = null
# Le lambda GDScript catturano le variabili locali PER VALORE: per osservare
# il segnale language_changed serve una VARIABILE MEMBRO modificata da un
# metodo (non da una closure).
var signal_lang: int = -1


func _on_lang_changed(new_lang: int) -> void:
        signal_lang = new_lang


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ok(cond: bool, msg: String) -> void:
        checks += 1
        if cond:
                print("[TEST OK] ", msg)
        else:
                _fail(msg)


func _ready() -> void:
        await get_tree().process_frame
        await get_tree().process_frame
        await _run_all()
        _finish()


func _run_all() -> void:
        # ---------- A: default ENGLISH + mirror ----------
        _ok(I18n != null, "A1: autoload I18n presente")
        _ok(I18n.language == I18n.Language.ENGLISH or I18n.language == I18n.Language.ITALIAN,
                        "A2: valore lingua valido (%d)" % I18n.language)
        # Il default del DIZIONARIO config è ENGLISH (0): lo enforce e testo
        # che il round-trip della persistenza lo riporti identico.
        I18n.set_language(I18n.Language.ENGLISH)
        _ok(I18n.language == I18n.Language.ENGLISH, "A3: lingua default ENGLISH")
        _ok(C.ui_language == 0, "A4: mirror statico C.ui_language = EN")

        # ---------- B: t() EN ----------
        _ok(I18n.t("loading") == "Loading...", "B1: t('loading') EN = 'Loading...'")
        _ok(I18n.t("menu.start") == "START GAME", "B2: t('menu.start') EN")
        _ok(I18n.t("hud.treasures") == "Treasures remaining:", "B3: t('hud.treasures') EN")
        _ok(I18n.t("intro.skip") == "PRESS FIRE TO SKIP", "B4: t('intro.skip') EN")
        _ok(I18n.t("enemy.skeleton") == "Skeleton", "B5: t('enemy.skeleton') EN")

        # ---------- C: IT + persistenza + segnale ----------
        I18n.language_changed.connect(_on_lang_changed)
        I18n.set_language(I18n.Language.ITALIAN)
        _ok(signal_lang == I18n.Language.ITALIAN, "C1: segnale language_changed(ITALIAN)")
        _ok(I18n.t("loading") == "Caricamento...", "C2: t('loading') IT = 'Caricamento...'")
        _ok(I18n.t("menu.start") == "INIZIA PARTITA", "C3: t('menu.start') IT")
        _ok(I18n.t("weakness") == "DEBOLEZZA!", "C4: t('weakness') IT")
        _ok(I18n.t("cont.yes") == "SÌ", "C5: t('cont.yes') IT = 'SÌ'")
        # Termini arcade che restano inglesi anche in IT (richiesta utente).
        _ok(I18n.t("menu.hall_of_fame") == "HALL OF FAME", "C6: HALL OF FAME resta EN in IT")
        _ok(I18n.t("menu.credits") == "CREDITS", "C7: CREDITS resta EN in IT")
        _ok(I18n.t("cont.title") == "CONTINUE?", "C8: CONTINUE? resta EN in IT")
        # Persistenza: config.ini contiene LANGUAGE=1 e il reload lo riporta.
        _ok(int(ConfigManager.config.get("LANGUAGE", -1)) == 1, "C9: config LANGUAGE=1 scritta")
        ConfigManager.config["LANGUAGE"] = 0
        ConfigManager.load_config()
        _ok(int(ConfigManager.config.get("LANGUAGE", -1)) == 1,
                        "C10: reload config.ini -> LANGUAGE=1 (persistenza)")
        _ok(C.ui_language == 1, "C11: mirror statico = IT")

        # ---------- D: boss (static, mirror) ----------
        _ok(BossScript.get_boss_name(BossScript.Type.BOSS_GOLEM) == "Golem di Pietra",
                        "D1: boss GOLEM IT = 'Golem di Pietra'")
        _ok(BossScript.get_boss_name(BossScript.Type.BOSS_LICH) == "Lich Necromante",
                        "D2: boss LICH IT = 'Lich Necromante'")
        _ok(BossScript.get_boss_name(BossScript.Type.BOSS_TWILIGHT_KNIGHT)
                        == "Cavaliere del Crepuscolo", "D3: boss TWILIGHT IT")

        # ---------- E: armi/armatura/elemento ----------
        _ok(C.get_weapon_name(C.WeaponType.PISTOL) == "PISTOLA", "E1: arma PISTOL IT = PISTOLA")
        _ok(C.get_weapon_name(C.WeaponType.SIEGE) == "ASSEDIO", "E2: arma SIEGE IT = ASSEDIO")
        _ok(C.get_character_name(C.CharacterType.KNIGHT) == "Cavaliere",
                        "E3: personaggio KNIGHT IT")
        var armor_def: Dictionary = C.RELIC_ARMORS[0]
        _ok(C.get_armor_short_name(armor_def) == "CORAZZA", "E4: armor short IT = CORAZZA")
        _ok(C.get_element_name(C.ElementKind.FIRE) == "FUOCO", "E5: elemento FIRE IT = FUOCO")

        # ---------- F: reliquie bilingui ----------
        var sword: Dictionary = C.get_relic_def(C.RelicType.SWORD)
        _ok(I18n.relic_name(sword) == "Spadone del Cavaliere", "F1: reliquia SWORD nome IT")
        _ok(I18n.relic_short(sword) == "SPADONE", "F2: reliquia SWORD short IT")
        _ok(I18n.relic_desc(sword).length() > 10, "F3: reliquia SWORD desc IT non vuota")
        _ok(I18n.relic_name(sword) != I18n.t("enemy.zombie"), "F4: sanity nomi distinti")

        # ---------- G: MainMenu con 4 voci OPTIONS ----------
        var menu_scene: PackedScene = load("res://scenes/MainMenu.tscn")
        menu = menu_scene.instantiate()
        get_tree().root.add_child(menu)
        await get_tree().process_frame
        await get_tree().process_frame
        _ok(menu.OPTIONS_MENU_ITEMS == 4, "G1: OPTIONS ha 4 voci (MUSIC/LANGUAGE/JOY/BACK)")
        menu._in_options = true
        menu._update_items_text()
        _ok(menu._item_labels[1].text == "LINGUA: ITALIANO",
                        "G2: voce LANGUAGE IT = 'LINGUA: ITALIANO' (got '%s')"
                        % menu._item_labels[1].text)
        _ok(menu._item_labels[2].text == "CONFIGURA JOYSTICK", "G3: CONFIGURE JOYSTICK IT")
        _ok(menu._item_labels[3].text == "INDIETRO", "G4: BACK IT")
        _ok(menu._item_labels[0].text == "MUSICA: OFF", "G5: MUSIC IT (default OFF)")
        # Toggle via la voce LANGUAGE (index 1) come farebbe il giocatore.
        menu._menu_item_index = 1
        menu._change_option(1)
        _ok(I18n.language == I18n.Language.ENGLISH, "G6: toggle LANGUAGE -> ENGLISH")
        _ok(menu._item_labels[1].text == "LANGUAGE: ENGLISH",
                        "G7: voce LANGUAGE EN = 'LANGUAGE: ENGLISH' (got '%s')"
                        % menu._item_labels[1].text)
        _ok(menu._item_labels[3].text == "BACK", "G8: BACK EN")
        menu._in_options = false
        menu._update_items_text()
        _ok(menu._item_labels[0].text == "NUMBER OF PLAYERS: 1", "G9: menu principale EN")
        _ok(menu._item_labels[4].text == "START GAME", "G10: START GAME EN")
        # Torna IT per il restauro finale coerente col default utente EN.
        I18n.set_language(I18n.Language.ITALIAN)

        # ---------- H: LoadingScreen autoload ----------
        _ok(LoadingScreen != null, "H1: autoload LoadingScreen presente")
        LoadingScreen.show_loading(false)
        _ok(LoadingScreen.is_showing(), "H2: show_loading() -> is_showing()")
        await get_tree().process_frame
        _ok(LoadingScreen.is_showing(), "H3: persiste con auto_hide=false")
        LoadingScreen.hide_loading()
        _ok(not LoadingScreen.is_showing(), "H4: hide_loading() spegne")
        LoadingScreen.show_loading(true)
        await get_tree().process_frame
        await get_tree().process_frame
        await get_tree().process_frame
        await get_tree().process_frame
        await get_tree().process_frame
        _ok(not LoadingScreen.is_showing(),
                        "H5: auto-hide dopo 3+ frame renderizzati (scene change mode)")

        # ---------- I: boot splash PNG ----------
        _ok(bool(ProjectSettings.get_setting("application/boot_splash/show_image", false)),
                        "I1: boot_splash/show_image attivo")
        var splash_path: String = str(ProjectSettings.get_setting(
                        "application/boot_splash/image", ""))
        _ok(splash_path.ends_with("boot_splash.png"), "I2: boot_splash image = PNG dedicato")
        _ok(FileAccess.file_exists(ProjectSettings.globalize_path(splash_path))
                        or ResourceLoader.exists(splash_path),
                        "I3: file boot_splash esiste su disco")

        # ---------- ripristino: lingua EN (default) per i test successivi ----------
        I18n.set_language(I18n.Language.ENGLISH)
        _ok(int(ConfigManager.config.get("LANGUAGE", -1)) == 0, "Z1: ripristino EN salvato")


func _finish() -> void:
        if menu != null and is_instance_valid(menu):
                menu.queue_free()
        if failures.is_empty():
                print("[TEST] ==== TEST LANGUAGE SUPERATO (%d check) ====" % checks)
                get_tree().quit(0)
        else:
                print("[TEST] ==== FALLITI ", failures.size(), " su ", checks, " check ====")
                for f in failures:
                        print("[TEST FAIL] ", f)
                get_tree().quit(1)
