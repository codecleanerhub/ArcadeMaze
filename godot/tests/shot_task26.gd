## shot_task26.gd — TASK 26: screenshot REALI di validazione:
##   1) MENU: pannello voci auto-dimensionato al centro-destra + fiamma sulla
##      voce selezionata;
##   2) HUD: 8 vite -> "8x" + singolo cuore (niente fila che invade WPN) e
##      arma reliquia equipaggiata SENZA nome (slot WPN vuoto, solo AMMO);
##   3) BOSS A/B: due Golem XHD affiancati, uno CON enhancement canvas (fix
##      "colori sbiaditi") e uno SENZA (percorso pre-Task-26) su sfondo scuro;
##   4) BOSS ANIMATI: 3 boss in gioco (Golem/Kraken/Demon) con enhancement
##      attivo, a due istanti diversi (arti in posizioni diverse).
extends Node2D

const BossScript = preload("res://scripts/bosses/Boss.gd")
const HUDClass = preload("res://scripts/ui/HUD.gd")

var main: Node2D = null
var menu: Control = null
var setup_done := false
var stage := 0
var t := 0.0
var bosses: Array = []
var ab_pair: Array = []


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()


func _process(delta: float) -> void:
        t += delta
        match stage:
                0:
                        # --- STAGE 1: menu (1.6s per il layout + fiamma) ---
                        # FIX: il menu (Control) va sotto la ROOT del viewport:
                        # sotto un parent Node2D l'ancora full-rect non ha rect
                        # di riferimento e lo screen resta nero.
                        if menu == null:
                                var mscene := load("res://scenes/MainMenu.tscn") as PackedScene
                                menu = mscene.instantiate()
                                get_tree().root.add_child.call_deferred(menu)
                                return
                        if not menu.is_inside_tree():
                                return
                        if t > 1.6:
                                print("SHOT26 stage=menu t=%.2f panel_center=%s" % [
                                        t, str(menu._panel.get_global_rect().get_center())])
                                stage = 1
                                t = 0.0
                                menu.queue_free()
                                menu = null
                1:
                        # --- STAGE 2/3/4: scena MainGame con HUD forzato ---
                        if main == null:
                                var scene := load("res://scenes/MainGame.tscn") as PackedScene
                                main = scene.instantiate()
                                add_child.call_deferred(main)
                                return
                        if not main.is_node_ready():
                                return
                        for e in main.spawner.enemies.duplicate():
                                if is_instance_valid(e):
                                        e.queue_free()
                        main.spawner.enemies.clear()
                        main._since_last_treasure_ms = 0.0
                        if not setup_done:
                                _setup()
                                return
                        # aggiorna i boss manualmente (pattern shot_task25)
                        for b in bosses:
                                if is_instance_valid(b):
                                        var out: Array = []
                                        b.update_step(b.pos.x + 40.0, 500.0,
                                                        int(delta * 1000.0), out)
                        if fmod(t, 0.25) < delta:
                                print("SHOT26 stage=game t=%.2f player=(%.0f,%.0f)" % [
                                        t, main.player.position.x, main.player.position.y])


func _setup() -> void:
        setup_done = true
        var p: CharacterBody2D = main.player
        # HUD: 8 vite + reliquia equipaggiata (nome assente per costruzione).
        p.lives = 8
        p.current_weapon = GameConstants.make_relic_weapon(GameConstants.RELIC_MELEE[0])
        # player in un corridoio centrale.
        var cell := _find_corridor()
        var ppos := Vector2(cell.x * 64.0 + 32.0, 80.0 + cell.y * 64.0 + 32.0)
        p.set_position_abs(ppos.x, ppos.y)
        p.last_dx = 1
        p.last_dy = 0
        # 3 boss col setup reale (enhancement canvas attivo dal _draw).
        var specs: Array = [
                [4, Vector2(500.0, 300.0)],      # Golem
                [20, Vector2(900.0, 300.0)],      # Kraken
                [8, Vector2(1300.0, 300.0)],      # Demon
        ]
        for s in specs:
                var b: Node = BossScript.new()
                add_child(b)
                b.setup(s[0], 1920, 1080)
                b.pos = s[1]
                bosses.append(b)
        # A/B: due Golem affiancati, uno SENZA enhancement (rollback look).
        var ds_on := DeformableSprite.new()
        ds_on.load_subrect("res://assets/sprites/xhd/boss_031_xhd_sheet.png", 0, 0, 256, 256)
        ds_on.set_grid_size(12, 12)
        ds_on.position = Vector2(1650.0, 700.0 - 128.0)
        ds_on.enable_canvas_enhancement()
        add_child(ds_on)
        ds_on.update(0.0, DeformableSprite.AnimMode.IDLE, 1.0, false)
        ab_pair.append(ds_on)
        var ds_off := DeformableSprite.new()
        ds_off.load_subrect("res://assets/sprites/xhd/boss_031_xhd_sheet.png", 0, 0, 256, 256)
        ds_off.set_grid_size(12, 12)
        ds_off.position = Vector2(820.0, 700.0 - 128.0)
        add_child(ds_off)
        ds_off.update(0.0, DeformableSprite.AnimMode.IDLE, 1.0, false)
        ab_pair.append(ds_off)
        print("SHOT26 setup completo: 3 boss + A/B (ON a destra x=1650, OFF a sinistra x=820, y=700)")


func _find_corridor() -> Vector2i:
        for r in range(5, 10):
                for c in range(3, 25):
                        if not main.maze.is_wall(c, r) \
                                        and not main.maze.is_wall(c + 1, r) \
                                        and not main.maze.is_wall(c - 1, r):
                                return Vector2i(c, r)
        return Vector2i(1, 1)
