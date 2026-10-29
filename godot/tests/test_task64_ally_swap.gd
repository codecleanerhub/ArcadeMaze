## test_task64_ally_swap.gd — TASK 64 (richiesta utente): l'alleato della
## statuetta alterna per livello — UNICORNO nei livelli dispari (1,3,5..,
## comportamento storico, retrocompatibile col livello 1) e CAVALLIERE nei
## livelli pari (2,4,6..). Entrambi gli sheet sono PixelLab v2.
##
##   A — regola di parita': _ally_variant_for_level() su livelli 1..8.
##   B — KnightAlly: ally_variant decide lo sheet caricato (match byte dei
##       PNG unicorn_ally/knight_ally); default "unicorn" senza variante.
##   C — Collectibles: _knight_statue_png() segue statue_variant (icona
##       a terra coerente: item_unicorn_statue / item_knight_statue).
##   D — BonusCardOverlay: per variante cambiano demo sheet, titolo i18n
##       (bonuscard.name.unicorn/knight) e icona statuetta (cache separata).
##   E — integrazione MainGame: livello 1 -> statuetta unicorno + alleato
##       evocato unicorno; livello 2 -> statuetta e alleato cavaliere.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const KnightAllyClass = preload("res://scripts/entities/KnightAlly.gd")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")
const BonusCardOverlayClass = preload("res://scripts/ui/BonusCardOverlay.gd")

const UNICORN_SHEET := "res://assets/sprites/unicorn_ally_sheet.png"
const KNIGHT_SHEET := "res://assets/sprites/knight_ally_sheet.png"
const UNICORN_STATUE_PNG := "res://assets/sprites/collectibles/item_unicorn_statue.png"
const KNIGHT_STATUE_PNG := "res://assets/sprites/collectibles/item_knight_statue.png"

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []
var checks: int = 0


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[TEST-64] boot MainGame...")


func _ok(cond: bool, msg: String) -> void:
        checks += 1
        if cond:
                print("[TEST-64] OK: ", msg)
        else:
                failures.append(msg)
                print("[TEST-64] FAIL: ", msg)


func _finish() -> void:
        if get_tree():
                get_tree().paused = false
        if failures.is_empty():
                print("[TEST-64] ==== TEST ALLEATO ALTERNATO SUPERATO (",
                                checks, " check) ====")
                get_tree().quit(0)
        else:
                for f in failures:
                        print("[TEST-64] FAIL: ", f)
                print("[TEST-64] ==== TEST ALLEATO ALTERNATO FALLITO (",
                                failures.size(), "/", checks, ") ====")
                get_tree().quit(1)


func _physics_process(delta: float) -> void:
        t += delta
        match phase:
                0:
                        if main != null and main.is_node_ready() and t > 1.2:
                                phase = 1
                                _run_a_parity()
                                _run_b_knight_ally()
                                _run_c_collectibles()
                                _run_d_bonus_card()
                1:
                        _run_e_level1()
                        phase = 2
                2:
                        # passa al livello 2 e verifica il wiring del Cavaliere
                        main.start_level(2)
                        phase = 3
                3:
                        _run_e_level2()
                        _finish()


## True se la texture contiene ESATTAMENTE i pixel del PNG a res_path
## (match byte-per-byte: distingue i due sheet senza ambiguita').
func _sheet_matches(tex: Texture2D, res_path: String) -> bool:
        if tex == null:
                return false
        var ref := Image.new()
        if ref.load(ProjectSettings.globalize_path(res_path)) != OK:
                return false
        var got: Image = tex.get_image()
        if got == null or got.get_size() != ref.get_size():
                return false
        return got.get_data() == ref.get_data()


# A — regola di parita' (livelli 1..8)
func _run_a_parity() -> void:
        for lvl in range(1, 9):
                main.current_level = lvl
                var expected: String = "knight" if lvl % 2 == 0 else "unicorn"
                _ok(main._ally_variant_for_level() == expected,
                                "A: livello %d -> variante %s" % [lvl, expected])
        main.current_level = 1


# B — KnightAlly: sheet caricato per variante + default retrocompatibile
func _run_b_knight_ally() -> void:
        # variante unicorn (default storico)
        var ka_u := KnightAllyClass.new()
        ka_u.ally_variant = "unicorn"
        add_child(ka_u)
        _ok(ka_u._sprite_loaded and _sheet_matches(ka_u._sprite_sheet, UNICORN_SHEET),
                        "B: variant unicorn -> sheet unicorn_ally caricato")
        ka_u.queue_free()
        # variante knight
        var ka_k := KnightAllyClass.new()
        ka_k.ally_variant = "knight"
        add_child(ka_k)
        _ok(ka_k._sprite_loaded and _sheet_matches(ka_k._sprite_sheet, KNIGHT_SHEET),
                        "B: variant knight -> sheet knight_ally caricato")
        ka_k.queue_free()
        # SENZA variante esplicita (call-site legacy/test): default unicorno
        var ka_d := KnightAllyClass.new()
        add_child(ka_d)
        _ok(ka_d.ally_variant == "unicorn"
                        and _sheet_matches(ka_d._sprite_sheet, UNICORN_SHEET),
                        "B: default senza variante -> unicorno (retrocompatibile)")
        ka_d.queue_free()


# C — Collectibles: path icona statuetta per variante
func _run_c_collectibles() -> void:
        var st_u: Collectibles = CollectiblesClass.make_knight_statue(Vector2.ZERO)
        _ok(st_u.statue_variant == "unicorn"
                        and st_u._knight_statue_png() == UNICORN_STATUE_PNG,
                        "C: statuetta default -> item_unicorn_statue.png")
        var st_k: Collectibles = CollectiblesClass.make_knight_statue(Vector2.ZERO)
        st_k.statue_variant = "knight"
        _ok(st_k._knight_statue_png() == KNIGHT_STATUE_PNG,
                        "C: statuetta variant knight -> item_knight_statue.png")


# D — BonusCardOverlay: demo + titolo + icona per variante
func _run_d_bonus_card() -> void:
        # variante unicorn (livelli dispari)
        var cd_u: CanvasLayer = BonusCardOverlayClass.new()
        cd_u.setup(CollectiblesClass.Kind.KNIGHT_STATUE, 1, 0, "unicorn")
        add_child(cd_u)
        _ok(cd_u._title == I18n.t("bonuscard.name.unicorn"),
                        "D: card unicorn -> titolo Statua dell'Unicorno")
        _ok(cd_u._demo_ally_tex != null
                        and cd_u._demo_ally_path == UNICORN_SHEET
                        and cd_u._demo_ally_tex.get_image().get_size() == Vector2i(256, 64),
                        "D: card unicorn -> demo sheet unicorn_ally (256x64)")
        var ic_u: Texture2D = BonusCardOverlayClass._icon_texture(
                        CollectiblesClass.Kind.KNIGHT_STATUE, "unicorn")
        _ok(ic_u != null and _sheet_matches(ic_u, UNICORN_STATUE_PNG),
                        "D: icona card unicorn -> item_unicorn_statue.png")
        cd_u.queue_free()
        # variante knight (livelli pari)
        var cd_k: CanvasLayer = BonusCardOverlayClass.new()
        cd_k.setup(CollectiblesClass.Kind.KNIGHT_STATUE, 1, 0, "knight")
        add_child(cd_k)
        _ok(cd_k._title == I18n.t("bonuscard.name.knight"),
                        "D: card knight -> titolo Statua del Cavaliere")
        _ok(cd_k._demo_ally_tex != null
                        and cd_k._demo_ally_path == KNIGHT_SHEET
                        and cd_k._demo_ally_tex.get_image().get_size() == Vector2i(256, 64),
                        "D: card knight -> demo sheet knight_ally (256x64)")
        var ic_k: Texture2D = BonusCardOverlayClass._icon_texture(
                        CollectiblesClass.Kind.KNIGHT_STATUE, "knight")
        _ok(ic_k != null and _sheet_matches(ic_k, KNIGHT_STATUE_PNG),
                        "D: icona card knight -> item_knight_statue.png")
        # le due icone devono essere DIVERSE (cache keyed per variante)
        _ok(ic_u != ic_k, "D: icone unicorn/knight distinte (cache per variante)")
        cd_k.queue_free()


# E1 — wiring reale al livello 1 (boot): statuetta + alleato unicorno
func _run_e_level1() -> void:
        _ok(main.current_level == 1, "E: boot al livello 1")
        if main.knight_statue_item != null:
                _ok(main.knight_statue_item.statue_variant == "unicorn",
                                "E: statuetta livello 1 -> variante unicorn")
        else:
                _ok(false, "E: statuetta livello 1 mancante (spawn fallito)")
        main._spawn_knight_ally(main.player.get_pixel_pos())
        _ok(main.knight_ally != null and is_instance_valid(main.knight_ally)
                        and main.knight_ally.ally_variant == "unicorn",
                        "E: alleato evocato al livello 1 -> unicorn")
        if main.knight_ally != null:
                _ok(_sheet_matches(main.knight_ally._sprite_sheet, UNICORN_SHEET),
                                "E: alleato livello 1 -> sheet unicorn_ally")
                main.knight_ally.queue_free()
                main.knight_ally = null


# E2 — wiring reale al livello 2: statuetta + alleato cavaliere
func _run_e_level2() -> void:
        _ok(main.current_level == 2, "E: start_level(2) -> current_level 2")
        if main.knight_statue_item != null:
                _ok(main.knight_statue_item.statue_variant == "knight",
                                "E: statuetta livello 2 -> variante knight")
        else:
                _ok(false, "E: statuetta livello 2 mancante (spawn fallito)")
        main._spawn_knight_ally(main.player.get_pixel_pos())
        _ok(main.knight_ally != null and is_instance_valid(main.knight_ally)
                        and main.knight_ally.ally_variant == "knight",
                        "E: alleato evocato al livello 2 -> knight")
        if main.knight_ally != null:
                _ok(_sheet_matches(main.knight_ally._sprite_sheet, KNIGHT_SHEET),
                                "E: alleato livello 2 -> sheet knight_ally")
                main.knight_ally.queue_free()
                main.knight_ally = null
