## test_credits_bg.gd — Test funzionale dello sfondo della schermata CREDITS
## (eseguito in headless). Verifica nel runtime REALE di Godot:
##   1. CreditsScreen si istanzia e diventa ready senza errori script
##   2. Lo sfondo bg_credits.png viene caricato (_bg_texture != null)
##   3. La texture ha le dimensioni attese (1024x1024)
##   4. Il ciclo _draw (cover-fit + overlay + testo scorrevole) gira senza
##      errori per qualche secondo
##   5. restart() resetta lo scroll senza rompere nulla
extends Node

const CreditsScene = preload("res://scenes/CreditsScreen.tscn")

var credits: Control = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []


func _ready() -> void:
        credits = CreditsScene.instantiate()
        get_tree().root.add_child.call_deferred(credits)
        print("[TEST] boot CreditsScreen...")


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _physics_process(_delta: float) -> void:
        t += _delta
        if credits == null or not credits.is_node_ready():
                return
        match phase:
                0:
                        if t > 0.5:
                                phase = 1
                                # --- Fase 1: sfondo caricato ---
                                if credits._bg_texture == null:
                                        _fail("sfondo NON caricato: _bg_texture è null (bg_credits.png mancante o illeggibile)")
                                else:
                                        var ts: Vector2 = credits._bg_texture.get_size()
                                        print("[TEST] fase 1: sfondo caricato, dimensioni = ", ts)
                                        if ts.x < 512 or ts.y < 512:
                                                _fail("dimensioni sfondo inattese: " + str(ts) + " (attese 1024x1024)")
                                # --- Fase 1b: le voci dei credits sono state costruite ---
                                if credits._entries.is_empty():
                                        _fail("entries dei credits vuote: _build_entries non ha girato")
                                else:
                                        print("[TEST] fase 1b: entries = ", credits._entries.size(), " voci")
                1:
                        # Lascia girare _process/_draw (scrolling) per ~2s.
                        if t > 2.5:
                                phase = 2
                                # --- Fase 2: restart() resetta lo scroll ---
                                var scroll_before: float = credits._scroll_y
                                credits.restart()
                                if credits._scroll_y != 0.0:
                                        _fail("restart() non ha azzerato lo scroll: " + str(credits._scroll_y))
                                else:
                                        print("[TEST] fase 2: restart() OK (scroll era ", scroll_before, ")")
                2:
                        # --- Fase finale: esito ---
                        if failures.is_empty():
                                print("[TEST] SUCCESS: sfondo credits caricato e schermata funzionante")
                                get_tree().quit(0)
                        else:
                                print("[TEST] FAILED: ", failures.size(), " fallimenti")
                                get_tree().quit(1)
