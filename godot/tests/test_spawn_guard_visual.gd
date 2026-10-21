## test_spawn_guard_visual.gd — TASK 40 (regressione bug utente): "quando
## il player muore non si vede lampeggiare il player ma soltanto l'arma e
## se non ha arma non si vede lampeggiare nulla".
##
## ROOT CAUSE: gli shader character_enhanced/armor_outfit SOVRASCRIVEVANO
## COLOR nel fragment senza moltiplicarlo per il COLOR iniziale, che in un
## canvas_item shader trasporta la catena MODULATE (blink alpha del nodo
## Player + tint P2 + evanescenza ghost). Il modulate del nodo era gia'
## corretto (lo prova test_spawn_guard), ma lo Sprite2D del corpo con
## ShaderMaterial lo ignorava: lampeggiavano solo i draw_* del _draw
## (arma in mano, ombra, proiettili).
##
## TEST a livello di RENDERING REALE (va eseguito con server X / Xvfb,
## driver opengl3): durante la guardia di nascita si catturano frame in
## fase ON (modulate.a > 0.9) e fase OFF (a < 0.2) e si confronta la
## luminanza media della regione del player a schermo.
##   * shader ROTTO  -> ON e OFF quasi identici (il corpo non sparisce,
##                      diff tipica 0-5 su 255);
##   * shader FIXATO -> il corpo scompare nella fase OFF, diff netta >> 10.
## Salva anche i crop PNG in download/ per ispezione visiva / QA VLM.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const CROP_HALF: int = 72
const SAMPLES_PER_PHASE: int = 5
const MIN_MEAN_DIFF: float = 10.0  # /255 — separa rotto (~0-5) da fixato (>>15)

var main: Node2D = null
var t: float = 0.0
var on_means: Array = []
var off_means: Array = []
var on_crops: Array = []
var off_crops: Array = []
var failures: Array = []


func _ready() -> void:
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[TEST] boot MainGame 1P (rendering reale richiesto)...")


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ok(msg: String) -> void:
        print("[TEST] OK ", msg)


func _finish() -> void:
        if failures.is_empty():
                print("[TEST] test_spawn_guard_visual: TUTTO VERDE")
                get_tree().quit(0)
        else:
                print("[TEST] test_spawn_guard_visual: ", failures.size(), " FALLI")
                get_tree().quit(1)


func _physics_process(delta: float) -> void:
        t += delta
        if t > 60.0:
                _fail("timeout globale del test (60s)")
                get_tree().quit(1)
                return
        if main == null or not main.is_node_ready():
                return
        # Sicurezza: niente nemici/proiettili nella zona del player mentre
        # si campiona (il crop deve contenere SOLO player + pavimento).
        for e in main.spawner.enemies.duplicate():
                if is_instance_valid(e):
                        e.queue_free()
        main.spawner.enemies.clear()
        for proj in main.enemy_projectiles_node.get_children():
                proj.queue_free()
        main._since_last_treasure_ms = 0.0

        var p: CharacterBody2D = main.player
        if p.spawn_guard_ms <= 0:
                # Guardia finita prima di avere tutti i campioni.
                _analyze()
                _finish()
                return
        var a: float = p.modulate.a
        # NOTA: il nodo di test gira PRIMA di main nel tree: il frame
        # completato (restituito da get_image()) e' quello renderizzato con
        # il modulate che stiamo leggendo adesso.
        if a > 0.9 and on_means.size() < SAMPLES_PER_PHASE:
                _capture(p, true)
        elif a < 0.2 and off_means.size() < SAMPLES_PER_PHASE:
                _capture(p, false)
        if on_means.size() >= SAMPLES_PER_PHASE \
                        and off_means.size() >= SAMPLES_PER_PHASE:
                _analyze()
                _finish()


## Cattura il frame completato, ritaglia la regione del player e ne calcola
## la luminanza media (0..255). Accoda il campione nella fase giusta.
func _capture(p: CharacterBody2D, is_on: bool) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        var center: Vector2 = p.get_global_transform_with_canvas().origin
        var rect: Rect2i = Rect2i(
                        int(center.x) - CROP_HALF, int(center.y) - CROP_HALF,
                        CROP_HALF * 2, CROP_HALF * 2)
        rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
        if rect.size.x < 32 or rect.size.y < 32:
                return  # player fuori schermo: skip del campione
        var crop: Image = img.get_region(rect)
        var lum: float = _mean_luminance(crop)
        if is_on:
                on_means.append(lum)
                on_crops.append(crop)
        else:
                off_means.append(lum)
                off_crops.append(crop)


func _mean_luminance(img: Image) -> float:
        var total: float = 0.0
        var n: int = img.get_width() * img.get_height()
        for y in img.get_height():
                for x in img.get_width():
                        var c: Color = img.get_pixel(x, y)
                        total += 0.299 * c.r8 + 0.587 * c.g8 + 0.114 * c.b8
        return total / float(maxi(1, n)) if n > 0 else 0.0


func _analyze() -> void:
        if on_means.is_empty():
                _fail("nessun campione in fase ON (lampeggio mai acceso?)")
                return
        if off_means.is_empty():
                _fail("nessun campione in fase OFF (lampeggio mai spento?)")
                return
        # Campione piu' luminoso della fase ON vs piu' scuro della fase OFF:
        # massimizza la separazione e ignora i frame di transizione.
        var best_on: float = on_means.max()
        var best_off: float = off_means.min()
        var diff: float = best_on - best_off
        # Salvataggio per ispezione visiva / QA VLM.
        var on_idx: int = on_means.find(best_on)
        var off_idx: int = off_means.find(best_off)
        DirAccess.make_dir_recursive_absolute("/home/z/my-project/download")
        (on_crops[on_idx] as Image).save_png(
                        "/home/z/my-project/download/spawn_guard_blink_ON.png")
        (off_crops[off_idx] as Image).save_png(
                        "/home/z/my-project/download/spawn_guard_blink_OFF.png")
        print("[TEST] luminanza media regione player: ON=%.1f OFF=%.1f diff=%.1f"
                        % [best_on, best_off, diff])
        if diff < MIN_MEAN_DIFF:
                _fail("il corpo del player NON lampeggia a schermo "
                                + "(diff %.1f < %.1f: lo shader sta ignorando "
                                + "il modulate)" % [diff, MIN_MEAN_DIFF])
        else:
                _ok("il corpo del player LAMPEGGIA a schermo "
                                + "(diff %.1f >= %.1f)" % [diff, MIN_MEAN_DIFF])
