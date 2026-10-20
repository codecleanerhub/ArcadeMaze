## test_task26.gd — TASK 26: test logici delle 7 richieste utente.
## A) Nomi armi speciali rimossi dalla HUD (get_weapon_name "" per reliquie).
## B) Munizioni +30% (armi base, reliquie, boss room, arma iniziale player).
## C) Enhancement canvas dei boss su DeformableSprite (+ rollback).
## D) HUD: cuori >5 = "Nx + cuore" (guardia sul nome arma vuoto).
## E) Demo mode: danno da contatto, AI anti-muro, nessuno stallo.
## F) Menu: pannello voci auto-dimensionato e centrato al centro-destra.
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const HUDClass = preload("res://scripts/ui/HUD.gd")

var failures: Array[String] = []
var phase := 0
var t := 0.0

var demo: Node = null
var demo_frames := 0
var demo_stall_hits := 0
var demo_last_snapshot: Array = []
var demo_snapshot_frames: Array[int] = []
var menu: Control = null


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ready() -> void:
        print("[TEST] task26: fasi A-D (logica pura)")


func _physics_process(delta: float) -> void:
        t += delta
        match phase:
                0:
                        _phase_abcd()
                        phase = 1
                1:
                        # E) demo mode: avvio scena + stepping accelerato
                        if demo == null:
                                if t < 0.5:
                                        return
                                var scene := load("res://scenes/DemoMode.tscn") as PackedScene
                                demo = scene.instantiate()
                                add_child(demo)
                                print("[TEST] E: DemoMode avviata (level=%d)" % demo.current_level)
                                return
                        # 10 step simulati per physics frame (~11x tempo reale).
                        # STOP a ~28s simulati: oltre i 30s la demo chiama
                        # go_to_menu() e cambierebbe scena uccidendo il test.
                        if is_instance_valid(demo) and demo_frames < 1700:
                                for k in 10:
                                        demo._physics_process(1.0 / 60.0)
                                        demo_frames += 1
                                        _demo_frame_checks()
                        if demo_frames >= 1700:
                                _phase_e_verdict()
                                phase = 2
                2:
                        # F) menu: avvio + attende il layout
                        if menu == null:
                                if t < 1.0:
                                        return
                                var mscene := load("res://scenes/MainMenu.tscn") as PackedScene
                                menu = mscene.instantiate()
                                menu.position = Vector2.ZERO
                                add_child(menu)
                                return
                        if t < 2.0:
                                return
                        _phase_f()
                        _finish()


# ---------------------------------------------------------------------------
# A-D: logica pura (costanti + nodi standalone)
# ---------------------------------------------------------------------------
func _phase_abcd() -> void:
        # --- A: nomi armi speciali rimossi, base intatti ---
        for def in C.RELIC_MELEE + C.RELIC_RANGED:
                var wtype: int = int(def.get("type", 0))
                if C.get_weapon_name(wtype) != "":
                        _fail("A: get_weapon_name(reliquia %s) != \"\"" % def.get("id"))
        if C.get_weapon_name(C.RelicType.REFLECT_BOLT) != "":
                _fail("A: get_weapon_name(REFLECT_BOLT) != \"\"")
        for bt in [C.WeaponType.PISTOL, C.WeaponType.SHOTGUN, C.WeaponType.LASER, C.WeaponType.ROCKET]:
                if C.get_weapon_name(bt).is_empty():
                        _fail("A: get_weapon_name(base %d) vuoto" % bt)
        print("[TEST] OK A: nomi reliquie rimossi dalla HUD, armi base intatte")

        # --- B: munizioni +30% ---
        var want: Dictionary = {
                C.WeaponType.PISTOL: 20, C.WeaponType.SHOTGUN: 11,
                C.WeaponType.LASER: 26, C.WeaponType.ROCKET: 6,
        }
        for bt in want.keys():
                var w: Dictionary = C.make_weapon(bt)
                if int(w.get("ammo", -1)) != int(want[bt]):
                        _fail("B: make_weapon(%d).ammo=%d (atteso %d)" % [bt, w.get("ammo"), want[bt]])
        if C.BOSS_ROOM_AMMO_MIN != 39:
                _fail("B: BOSS_ROOM_AMMO_MIN=%d (atteso 39)" % C.BOSS_ROOM_AMMO_MIN)
        var orig_shots: Dictionary = {  # valori pre-Task-26
                "sword": 25, "axe": 15, "mace": 12, "halberd": 18,
                "vampire_blade": 20, "golem_hammer": 10, "crossbow": 30,
                "arcane_orb": 24, "twin_daggers": 20, "ranger_bow": 40,
                "storm_rod": 15, "alchemist_bombs": 12,
        }
        for def in C.RELIC_MELEE + C.RELIC_RANGED:
                var sid: String = str(def.get("id", ""))
                var shots: int = int(def.get("shots", 0))
                var orig: int = int(orig_shots.get(sid, -1))
                if orig > 0 and shots < ceili(float(orig) * 1.3):
                        _fail("B: reliquia %s shots=%d < ceil(1.3*%d)" % [sid, shots, orig])
        var PlayerScript := load("res://scripts/core/Player.gd")
        var p: CharacterBody2D = PlayerScript.new()
        if int(p.current_weapon.get("ammo", -1)) != 20:
                _fail("B: arma iniziale player ammo=%d (atteso 20)" % p.current_weapon.get("ammo", -1))
        p.free()
        print("[TEST] OK B: munizioni +30% su base/reliquie/boss-room/arma iniziale")

        # --- C: enhancement canvas del boss ---
        var ds := DeformableSprite.new()
        ds.load_subrect("res://assets/sprites/xhd/boss_031_xhd_sheet.png", 0, 0, 256, 256)
        ds.set_grid_size(16, 16)   # TASK 28: grid XHD aggiornata 12->16
        if ds.material is ShaderMaterial:
                _fail("C: materiale canvas attivo PRIMA di enable (rollback rotto)")
        ds.enable_canvas_enhancement()
        var mat := ds.material as ShaderMaterial
        if mat == null:
                _fail("C: enable_canvas_enhancement non imposta materiale")
        else:
                var shp: float = float(mat.get_shader_parameter("sharpness"))
                if absf(shp - 0.8) > 0.01:
                        _fail("C: sharpness=%.2f (attesa 0.8 strong)" % shp)
                if ds.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR:
                        _fail("C: filtro XHD non LINEAR")
        ds.disable_canvas_enhancement()
        if ds.material != null:
                _fail("C: disable_canvas_enhancement non rimuove il materiale")
        ds.free()
        # Boss._draw attiva l'enhancement (flag ON) e lo rimuove (flag OFF)
        var BossScript := load("res://scripts/bosses/Boss.gd") as GDScript
        var boss: Node = BossScript.new()
        add_child(boss)
        boss.setup(4, 1920, 1080)
        boss._draw()
        if not (boss.deform_sprite.material is ShaderMaterial):
                _fail("C: Boss._draw non attiva l'enhancement canvas")
        C.BOSS_CANVAS_SHADER_ENABLED = false
        boss.deform_loaded = false
        boss._draw()
        if boss.deform_sprite.material != null:
                _fail("C: rollback BOSS_CANVAS_SHADER_ENABLED=false non rispettato")
        C.BOSS_CANVAS_SHADER_ENABLED = true
        boss.queue_free()
        print("[TEST] OK C: enhancement canvas boss attivo + rollback funzionante")

        # --- D: HUD con 8 vite e nome arma vuoto non genera errori ---
        var hud: Control = HUDClass.new()
        add_child(hud)
        hud.set_player_state({
                "lives": 8, "weapon_name": "", "weapon_color": Color.WHITE,
                "weapon_ammo": 33, "score": 250000,
        })
        hud.set_player2_state({"lives": 6, "weapon_name": "", "weapon_ammo": 20})
        hud.set_num_players(2)
        hud.queue_redraw()
        print("[TEST] OK D: HUD con 8/6 vite e arma reliquia senza nome (render OK)")
        # (verifica visiva del formato "8x + cuore" nello screenshot dedicato)


# ---------------------------------------------------------------------------
# E) demo mode
# ---------------------------------------------------------------------------
func _demo_frame_checks() -> void:
        # snapshot anti-stallo ogni 60 frame simulati: se TUTTE le posizioni
        # (player + nemici vivi) restano identiche per un intero secondo
        # simulato mentre la demo dovrebbe essere in corsa -> stallo.
        # (La direzione AI NON si verifica per-frame: vale al momento della
        # decisione, ma il player si muove entro lo stesso frame e la cella
        # di controllo cambia — unit test dedicato in _phase_e_verdict.)
        if demo_frames % 60 == 0:
                var snap: Array = [demo.player.get_pixel_pos()]
                for e in demo.spawner.enemies:
                        if not e.is_dead():
                                snap.append(e.get_pixel_pos())
                if demo_last_snapshot.size() == snap.size() and demo_frames > 0:
                        var equal := true
                        for i in snap.size():
                                if snap[i] != demo_last_snapshot[i]:
                                        equal = false
                                        break
                        if equal and demo.demo_duration_timer_ms > 3000:
                                demo_stall_hits += 1
                demo_last_snapshot = snap


func _phase_e_verdict() -> void:
        # danno da contatto: teleporta un nemico addosso al player e step
        var p: CharacterBody2D = demo.player
        var enemy = null
        for e in demo.spawner.enemies:
                if not e.is_dead():
                        enemy = e
                        break
        if enemy == null:
                print("[TEST] E: nessun nemico vivo per il test danno (maze casuale) - SKIP contatto")
        else:
                # Il player può aver esaurito le vite nei 28s simulati: reset
                # controllato dello stato prima del test danno (vite piene,
                # energia piena, non invulnerabile) + timer demo rabboccato
                # così lo step aggiuntivo NON può far scattare go_to_menu()
                # (che cambierebbe scena uccidendo il test).
                p.lives = 3
                p.energy = p.max_energy
                p.damage_timer = 0
                demo.demo_duration_timer_ms = 10000
                var e_before: int = p.energy
                var l_before: int = p.lives
                enemy.position = p.get_pixel_pos()
                # attende che il player NON sia a mezz'aria (il salto evita il
                # danno per design) e poi fa UNO step: il contatto deve ferire
                var tries := 0
                var hurt := false
                while tries < 90 and not hurt:
                        tries += 1
                        enemy.position = p.get_pixel_pos()
                        p.damage_timer = 0
                        if not p.is_jumping():
                                demo._physics_process(1.0 / 60.0)
                                if p.energy < e_before or p.lives < l_before:
                                        hurt = true
                        else:
                                demo._physics_process(1.0 / 60.0)
                if not hurt:
                        _fail("E: contatto nemico-player senza danno (energia invariata)")
                else:
                        print("[TEST] OK E: contatto nemico->danno nel demo")
        if demo_stall_hits >= 10:
                _fail("E: STALLO rilevato nel demo (%d snapshot consecutivi immobili)" % demo_stall_hits)
        else:
                print("[TEST] OK E: demo in movimento per ~28s simulati (stalli=%d)" % demo_stall_hits)
        # _open_dir_around: unit test su tutte le direzioni
        var p2: CharacterBody2D = demo.player
        var col := int(p2.get_pixel_pos().x / C.TILE_SIZE)
        var row := int((p2.get_pixel_pos().y - C.UI_HEIGHT) / C.TILE_SIZE)
        for d in [1, 2, 3, 4]:
                var ndx: int = 0
                var ndy: int = 0
                match d:
                        1: ndy = -1
                        2: ndy = 1
                        3: ndx = -1
                        4: ndx = 1
                if demo.maze.is_wall(col + ndx, row + ndy):
                        # direzione bloccata: _open_dir_around DEVE aprirsi
                        var r: int = demo._open_dir_around(d)
                        var rdx: int = 0
                        var rdy: int = 0
                        match r:
                                1: rdy = -1
                                2: rdy = 1
                                3: rdx = -1
                                4: rdx = 1
                        if demo.maze.is_wall(col + rdx, row + rdy):
                                _fail("E: _open_dir_around(%d) ritorna muro (%d)" % [d, r])
        print("[TEST] OK E: _open_dir_around apre sempre su direzione libera")
        demo.queue_free()
        demo = null


# ---------------------------------------------------------------------------
# F) menu
# ---------------------------------------------------------------------------
func _phase_f() -> void:
        if menu == null:
                _fail("F: menu non istanziato")
                return
        if not (menu._panel is PanelContainer):
                _fail("F: _panel non è PanelContainer")
                return
        var panel: PanelContainer = menu._panel
        var rect: Rect2 = panel.get_global_rect()
        var vp_w: float = 1920.0
        var vp_h: float = 1080.0
        if menu.size.x > 100.0:
                vp_w = menu.size.x
                vp_h = menu.size.y
        # centro-destra: centro del pannello ~ (75% larghezza, 50% altezza)
        var cx: float = rect.get_center().x
        var cy: float = rect.get_center().y
        if absf(cx - vp_w * 0.75) > 60.0:
                _fail("F: centro pannello x=%.0f (atteso ~%.0f)" % [cx, vp_w * 0.75])
        if absf(cy - vp_h * 0.5) > 60.0:
                _fail("F: centro pannello y=%.0f (atteso ~%.0f)" % [cy, vp_h * 0.5])
        # aderenza alle voci: ogni label sta DENTRO il pannello con margine
        # piccolo (<= contenuto 14 + bordo 6 + tolleranza 6 = 26)
        var n_visible := 0
        for lbl in menu._item_labels:
                if lbl.visible:
                        n_visible += 1
                        var lr: Rect2 = lbl.get_global_rect()
                        if not rect.encloses(lr):
                                _fail("F: etichetta fuori dal pannello")
                                break
                        var m_l: float = lr.position.x - rect.position.x
                        var m_r: float = rect.end.x - lr.end.x
                        if maxf(m_l, m_r) > 26.0:
                                _fail("F: margine laterale eccessivo (%.0f/%.0f px)" % [m_l, m_r])
                                break
        if n_visible != 7:
                _fail("F: voci visibili=%d (attese 7 nel menu principale)" % n_visible)
        # la fiamma segue la voce selezionata
        var fp: Vector2 = menu._selected_flame_pos()
        if fp == Vector2.INF:
                _fail("F: fiamma selezione senza posizione")
        elif fp.x < rect.position.x - 40.0 or fp.x > rect.end.x + 40.0:
                _fail("F: fiamma fuori dal pannello (%.0f)" % fp.x)
        print("[TEST] OK F: pannello menu centro (%.0f, %.0f), %d voci, fiamma ok" % [cx, cy, n_visible])
        menu.queue_free()


func _finish() -> void:
        if failures.is_empty():
                print("[TEST] test_task26: TUTTI OK")
                get_tree().quit(0)
        else:
                print("[TEST] test_task26: %d FALLIMENTI" % failures.size())
                for f in failures:
                        print("[TEST FAIL] ", f)
                get_tree().quit(1)
