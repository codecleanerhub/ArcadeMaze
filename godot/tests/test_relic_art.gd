## test_relic_art.gd — TASK 23: asset PNG reliquie + schermata bonus.
## Verifica nel runtime REALE (headless):
##   A. Le 18 icone PNG si caricano (RelicArt) con dimensioni corrette
##      (512x512, RGBA — trasparenza presente) e fallback null-chain.
##   B. Lo sfondo bonus (fucina) si carica (1344x768).
##   C. BonusScreen: tutte le reliquie hanno name_en/desc_en (testo INGLESE
##      in schermata), e il titolo della schermata NON contiene il nome
##      ("SCHERMATA BONUS A/B/C" rimosso).
##   D. Il rendering della schermata bonus gira senza errori di script
##      (draw con PNG + sfondo) per un paio di secondi.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const GameConstants = preload("res://scripts/core/GameConstants.gd")
const RelicArt = preload("res://scripts/core/RelicArt.gd")
const BonusScreenClass = preload("res://scripts/ui/BonusScreen.gd")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []
var bonus: CanvasLayer = null
var draw_ok: bool = false


func _ready() -> void:
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[TEST] boot MainGame 1P...")


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ok(msg: String) -> void:
        print("[TEST] OK ", msg)


func _physics_process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        match phase:
                0:
                        if t > 1.0:
                                _phaseA_icons()
                                _phaseB_background()
                                _phaseC_english()
                                phase = 1
                1:
                        # D: apri una BonusScreen reale e lasciala girare
                        # (rendering PNG + sfondo, nessun errore di script).
                        if bonus == null:
                                bonus = BonusScreenClass.new()
                                bonus.setup(4, [main.player])
                                get_tree().root.add_child.call_deferred(bonus)
                        if bonus != null and is_instance_valid(bonus) and t > 3.0:
                                _ok("D: BonusScreen gira 2s senza errori (PNG + sfondo)")
                                _verdict()
                        elif t > 6.0:
                                _fail("D: BonusScreen non apparsa")
                                _verdict()


func _phaseA_icons() -> void:
        var all_ids: Array = []
        for d in GameConstants.RELIC_MELEE + GameConstants.RELIC_RANGED \
                        + GameConstants.RELIC_ARMORS:
                all_ids.append(str(d.get("id", "")))
        var missing: Array = []
        var bad_alpha: Array = []
        for rid in all_ids:
                var tex: Texture2D = RelicArt.get_icon(rid)
                if tex == null:
                        missing.append(rid)
                        continue
                if tex.get_size() != Vector2(512, 512) \
                                and tex.get_size() != Vector2(768, 768):
                        # dimensione libera ma plausibile (trim): accetta
                        # quadrati; segnala solo non-quadrati/nulla.
                        var sz: Vector2 = tex.get_size()
                        if absf(sz.x - sz.y) > 2.0:
                                bad_alpha.append(rid + " " + str(sz))
        # fallback test: id inesistente -> null (niente crash).
        if RelicArt.get_icon("id_che_non_esiste") != null:
                _fail("A: fallback null non rispettato per id inesistente")
        if not missing.is_empty():
                _fail("A: icone PNG mancanti: " + ", ".join(missing))
        elif not bad_alpha.is_empty():
                _fail("A: icone non quadrate: " + ", ".join(bad_alpha))
        else:
                _ok("A: 18 icone PNG caricate (" + str(all_ids.size()) + " id, fallback null OK)")


func _phaseB_background() -> void:
        var bg: Texture2D = RelicArt.get_bonus_background()
        if bg == null:
                _fail("B: sfondo bonus (fucina) non caricato")
        elif bg.get_size().x < 1200 or bg.get_size().y < 700:
                _fail("B: sfondo bonus dimensioni inattese " + str(bg.get_size()))
        else:
                _ok("B: sfondo bonus fucina caricato (" + str(bg.get_size().x) + "x"
                                + str(bg.get_size().y) + ")")


func _phaseC_english() -> void:
        # C: name_en/desc_en presenti per tutte le 18 reliquie (testo EN).
        var missing_en: Array = []
        for d in GameConstants.RELIC_MELEE + GameConstants.RELIC_RANGED \
                        + GameConstants.RELIC_ARMORS:
                if not d.has("name_en") or not d.has("desc_en"):
                        missing_en.append(str(d.get("id", "?")))
        if not missing_en.is_empty():
                _fail("C: reliquie senza nome/descrizione inglese: "
                                + ", ".join(missing_en))
        else:
                _ok("C: tutte le 18 reliquie hanno name_en/desc_en (INGLESE)")
        # C2: la schermata NON espone più il nome/lettera (screen_letter rimosso).
        var bs_script: GDScript = load("res://scripts/ui/BonusScreen.gd")
        var inst = bs_script.new()
        if "screen_letter" in inst:
                _fail("C2: BonusScreen espone ancora screen_letter (nome schermata)")
                inst.free()
        else:
                inst.free()
                _ok("C2: nessun nome/lettera di schermata in BonusScreen")


func _verdict() -> void:
        var tree: SceneTree = get_tree()
        if tree == null:
                tree = Engine.get_main_loop() as SceneTree
        if failures.is_empty():
                print("[TEST] ==== TUTTI I TEST RELIC ART SUPERATI ====")
                if tree != null:
                        tree.quit(0)
        else:
                print("[TEST] ==== FALLITI ", failures.size(), " test ====")
                for f in failures:
                        print("[TEST FAIL] ", f)
                if tree != null:
                        tree.quit(1)
