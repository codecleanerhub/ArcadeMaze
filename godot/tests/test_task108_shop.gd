## test_task108_shop.gd — TASK 108: SHOP del mago nel labirinto + BAMBOLA
## VOODOO (possessione). Verifica RUNTIME su MainGame reale.
##
## Check:
##   A — spawn dello shop: nasce col punteggio >= costo cuore (angolo del
##       labirinto, blocco 2x2 EMPTY, BFS-raggiungibile); NON nasce sotto
##       soglia e NON sui livelli boss.
##   B — ShopScreen: acquisti (cuore +1 vita / medikit +1 energia / voodoo
##       in tasca), tasto disattivato (punti insufficienti / energia piena /
##       gia' posseduta), punteggio che scende.
##   C — ingresso/uscita: il player entra nel rettangolo -> schermata aperta
##       e tree in pausa; ESCI -> shop chiuso, player fuori dalla porta,
##       tree riprende; il reingresso e' ignorato.
##   D — VOODOO: lancio crea il nodo in volo; possessione (energia del
##       nemico, nemico tolto dal campo, puppet figlio del player, armi del
##       player intatte); morte del corpo posseduto = NESSUNA vita persa,
##       energia/posizione salvate ripristinate, punti della kill.
##   E — session snapshot: lo shop (celle/stato) e la bambola sopravvivono
##       alla morte per il continue.
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const BFS = preload("res://scripts/core/BFS.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

var fails: int = 0
var main: Node2D = null


func ok(cond: bool, label: String) -> void:
        if cond:
                print("[SHOP] OK: ", label)
        else:
                fails += 1
                print("[SHOP] FAIL: ", label)


func _ready() -> void:
        print("[TEST] === TASK 108: SHOP + VOODOO ===")
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        add_child.call_deferred(main)
        set_process(true)


var _stage: int = 0


func _process(_delta: float) -> void:
        if _stage == 0:
                if main == null or not main.is_node_ready():
                        return
                _stage = 1
                _test_shop_spawn()
                _test_shop_screen()
                _test_entry_exit()
                _test_voodoo()
                _test_snapshot()
                if fails == 0:
                        print("[SHOP] ESITO: TUTTI PASSATI")
                else:
                        print("[SHOP] ESITO: %d FALLITI" % fails)
                get_tree().quit(0 if fails == 0 else 1)


# --- A: spawn dello shop --------------------------------------------------------
func _test_shop_spawn() -> void:
        seed(108)
        main.player.score = 2000   # sotto soglia: niente shop
        main.start_level(3)
        ok(main.shop_stall == null, "A: nessuno shop sotto il costo del cuore (2000 punti)")
        seed(108)
        main.player.score = C.SHOP_COST_HEART
        main.start_level(3)
        if main.shop_stall == null:
                ok(false, "A: shop assente con score = costo cuore")
                return
        var stall = main.shop_stall  # dynamic: ShopStall
        var block: Vector2i = stall.block_cell
        # cella della porta EMPTY e BFS-raggiungibile dallo spawn
        ok(main.maze.get_cell_type(block.x, block.y) == C.CellType.EMPTY,
                        "A: cella dello shop EMPTY")
        var next: Vector2i = BFS.find_path(main.maze, Vector2i(1, 1), block)
        ok(next != Vector2i(-1, -1), "A: shop BFS-raggiungibile dallo spawn")
        # all'angolo: una delle 4 estremita' del maze
        var at_corner: bool = block.x >= C.MAZE_COLS - 12 or block.x <= 9 \
                        or block.y >= C.MAZE_ROWS - 12 or block.y <= 9
        ok(at_corner, "A: shop piazzato a un'estremita' del labirinto")
        # livello boss: mai
        seed(108)
        main.player.score = 999999
        main.start_level(4)
        ok(main.shop_stall == null, "A: nessuno shop sul livello boss (4)")
        # ripristino per i test successivi
        seed(108)
        main.player.score = 30000
        main.start_level(3)
        ok(main.shop_stall != null, "A: shop presente per i test successivi (30000 punti)")


# --- B: ShopScreen (acquisti + tasti disattivati) --------------------------------
func _test_shop_screen() -> void:
        var p: CharacterBody2D = main.player
        p.score = 10000
        p.lives = 2
        p.energy = 3
        p.voodoo_equipped = false
        var screen = load("res://scripts/ui/ShopScreen.gd").new()
        add_child(screen)
        screen.setup(p)
        var defs: Array = screen._item_defs()
        # ordine prezzi
        ok(int(defs[0]["cost"]) > int(defs[1]["cost"]) and int(defs[1]["cost"]) > int(defs[2]["cost"]),
                        "B: catalogo ordinato voodoo > cuore > medikit")
        # acquisto cuore: +1 vita, -4000 punti
        var heart_def: Dictionary = defs[1]
        ok(screen._lock_reason(heart_def) == "", "B: cuore acquistabile con 10000 punti")
        screen._buy_item(heart_def)
        ok(p.lives == 3 and p.score == 6000, "B: cuore comprato: vite 3, punti 6000")
        # voodoo: +in tasca, -6000... con 6000 esatti -> resta 0
        var voodoo_def: Dictionary = defs[0]
        screen._buy_item(voodoo_def)
        ok(p.voodoo_equipped and p.score == 0, "B: bambola comprata: in tasca, punti 0")
        p.score = 20000   # con punti: la disattivazione e' SOLO perche' gia' posseduta
        ok(screen._lock_reason(voodoo_def) == "shop.buy_owned", "B: seconda bambola DISATTIVATA (gia' posseduta)")
        p.score = 0
        # punti insufficienti: medikit a 0 punti
        var med_def: Dictionary = defs[2]
        ok(screen._lock_reason(med_def) == "shop.buy_locked", "B: medikit disattivato senza punti")
        ok(not screen._buy_item(med_def), "B: acquisto medikit rifiutato senza punti")
        # medikit a energia piena disattivato
        p.score = 5000
        p.energy = p.max_energy
        ok(screen._lock_reason(med_def) == "shop.buy_full", "B: medikit disattivato a energia piena")
        p.energy = 2
        screen._buy_item(med_def)
        ok(p.energy == 3 and p.score == 3500, "B: medikit comprato: energia 2->3, punti 3500")
        # ESCI chiude e riprende il tree
        screen._exit_shop()
        await get_tree().physics_frame
        ok(not is_instance_valid(screen) or screen.is_queued_for_deletion(),
                        "B: ESCI libera la schermata")
        ok(not get_tree().paused, "B: ESCI riprende il tree (pausa tolta)")
        p.voodoo_equipped = false
        p.score = 30000
        p.lives = 3


# --- C: ingresso/uscita dal negozio -----------------------------------------------
func _test_entry_exit() -> void:
        var p: CharacterBody2D = main.player
        p.score = 30000
        var stall = main.shop_stall  # dynamic: ShopStall
        # il player CAMBIA dentro l'edificio -> si apre la schermata
        p.position = stall.position
        main._update_shop_entry()
        ok(main._shop_screen != null, "C: entrare nella capanna apre il negozio")
        ok(get_tree().paused, "C: il tree e' in pausa col negozio aperto")
        # uscita (flusso REALE: ESC/ESCI -> ShopScreen._exit_shop -> segnale):
        # shop CHIUSO + player su cella adiacente percorribile + tree riprende
        var exit_expected: Vector2 = main._shop_exit_pos(stall.block_cell)
        var real_screen = main._shop_screen
        real_screen._exit_shop()
        await get_tree().physics_frame
        ok(not stall.open, "C: uscita -> shop CHIUSO (cartello)")
        ok(p.position.distance_to(exit_expected) < 1.0, "C: player riposizionato accanto alla porta (cella EMPTY)")
        ok(not get_tree().paused, "C: uscita -> tree riprende")
        ok(main._shop_screen == null, "C: schermata liberata")
        # reingresso ignorato (negozio chiuso)
        p.position = stall.position
        main._update_shop_entry()
        ok(main._shop_screen == null, "C: reingresso ignorato (negozio chiuso per il livello)")
        # snapshot per E
        main.player.voodoo_equipped = true


# --- D: VOODOO (lancio + possessione + morte del corpo) -----------------------------
func _test_voodoo() -> void:
        var p: CharacterBody2D = main.player
        p.voodoo_equipped = true
        p.last_dx = 1
        p.last_dy = 0
        p.energy = 2
        p.lives = 3
        var lives_before: int = p.lives
        var score_before: int = p.score
        var saved_pos: Vector2 = p.position
        # LANCIO: crea il nodo in volo e consuma la bambola
        main._throw_voodoo_doll(p)
        ok(main.voodoo_thrown != null, "D: lancio crea la bambola in volo")
        ok(not p.voodoo_equipped, "D: la bambola e' a uso singolo (consumata al lancio)")
        ok(main.voodoo_thrown.position.distance_to(p.get_pixel_pos()) < 40.0,
                        "D: la bambola parte dal player")
        main.voodoo_thrown.queue_free()
        main.voodoo_thrown = null
        # POSSESSIONE diretta (il volo e' animazione: qui si applica l'effetto)
        seed(108)
        main.start_level(3)   # shop rinasce ma il player resta al centro
        p = main.player
        p.voodoo_equipped = false
        p.energy = 2
        p.lives = 3
        p.position = Vector2(5 * C.TILE_SIZE, 5 * C.TILE_SIZE + C.UI_HEIGHT)
        saved_pos = p.position
        lives_before = p.lives
        score_before = p.score
        if main.spawner.enemies.is_empty():
                main.spawner.spawn_enemies(main.maze, 3)
        var enemy = main.spawner.enemies[0]
        var e_hp: int = int(enemy.health)
        var e_reward: int = enemy.get_score_reward()
        main._apply_voodoo_possession(p, enemy)
        ok(p.possession_active, "D: possessione attiva")
        ok(p.energy == e_hp and p.max_energy == e_hp, "D: l'energia del player e' quella del nemico (%d)" % e_hp)
        ok(not main.spawner.enemies.has(enemy), "D: il nemico e' stato tolto dal campo")
        ok(enemy.get_parent() == p, "D: il corpo del nemico e' figlio del player (puppet)")
        ok(p.current_weapon.get("type", -1) >= 0, "D: il player mantiene le SUE armi")
        # MORTE DEL CORPO POSSEDUTO: nessuna vita persa, stato ripristinato
        # (spawn guard/invulnerabilita' azzerati: qui si testa il ramo morte)
        p.spawn_guard_ms = 0
        p.damage_timer = 0
        p.invincible_timer = 0
        p.energy = 1
        p.take_damage(5)
        ok(p.possession_death_pending, "D: morte del corpo posseduto registrata (nessun collasso)")
        ok(p.lives == lives_before, "D: NESSUNA vita persa dal player")
        main._update_possession(16.0)
        ok(not p.possession_active, "D: possessione chiusa alla morte del corpo")
        ok(p.energy == 2, "D: energia ripristinata a quella pre-possessione (2)")
        ok(p.position == saved_pos, "D: posizione ripristinata a quella pre-possessione")
        ok(p.score == score_before + e_reward, "D: punti della kill accreditati (+%d)" % e_reward)
        ok(p.lives == lives_before, "D: vite invariate anche dopo la chiusura")
        # la bambola consumata non si rilancia
        ok(not p.voodoo_equipped, "D: la bambola resta consumata")


# --- E: session snapshot (continue) --------------------------------------------------
func _test_snapshot() -> void:
        var p: CharacterBody2D = main.player
        p.voodoo_equipped = true
        var stall = main.shop_stall
        var was_open: bool = stall != null and stall.open
        var snap: Dictionary = main._build_session_snapshot()
        ok(snap.has("shop") and snap["shop"].get("cell", Vector2i(-9, -9)) == stall.block_cell,
                        "E: lo snapshot del continue conserva il blocco dello shop")
        ok(bool(snap["shop"].get("closed", true)) == (not was_open), "E: lo snapshot conserva lo stato aperto/chiuso")
        ok(bool(snap.get("p1", {}).get("voodoo", false)), "E: lo snapshot conserva la bambola in tasca")
        # il restore ricrea lo shop
        stall.open = false   # simuliamo la morte DOPO l'uscita dal negozio
        var snap2: Dictionary = main._build_session_snapshot()
        if main.shop_stall != null and is_instance_valid(main.shop_stall):
                main.shop_stall.queue_free()
        main.shop_stall = null
        main._restore_session_from_snapshot(snap2)
        ok(main.shop_stall != null and not main.shop_stall.open, "E: il restore ricrea lo shop CHIUSO (stesso stato)")
        ok(main.player.voodoo_equipped, "E: il restore ridà la bambola al player")


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var content := f.get_as_text()
        f.close()
        return content
