## test_task25.gd — TASK 25 (aggiornato TASK 28): animazioni boss visibili
## + outfit armature. Verifica nel runtime REALE (headless):
##   A. DeformableSprite.limb_gain: LINEARITA' sotto il clamp (v(0.5)-v(0)
##      == 0.5*(v(1)-v(0))), CLAMP di integrita' a gain estremo (10.0:
##      ogni componente <= MAX_LIMB_OFFSET_UNITS) e VISIBILITA' col gain di
##      gioco (max spostamento arti > 3% del lato e <= ~4%: visibile MA
##      senza lacerazioni — Task 28: il gain 2.6 strappava la mesh).
##   B. Boss: il boss TERRESTRE in movimento usa la modalità WALK della
##      mesh (bob + dondolio zampe); i fluttuanti (Lich) restano in IDLE.
##   C. Boss: deform_sprite.limb_gain viene impostato da update_step al
##      valore di GameConstants.BOSS_LIMB_ANIM_GAIN.
##   D. Armor outfit: equip -> materiale armor_outfit sullo sprite con
##      armor_color = colore della reliquia; rottura -> torna enhancement
##      standard; rollback flag OFF -> materiale mai applicato.
##   E. Player._compute_cloth_hue: deterministico e corretto su immagini
##      sintetiche (blu -> ~0.6875, grigio -> -1, pelle -> -1).
##   F. Icona Mjolnir (rigenerata): 128x128, RGBA con contenuto opaco e
##      UNA componente connessa dominante (>97% dei pixel opachi).
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const GameConstants = preload("res://scripts/core/GameConstants.gd")
const BossScript = preload("res://scripts/bosses/Boss.gd")
const DeformableSpriteScript = preload("res://scripts/core/DeformableSprite.gd")
const PlayerScript = preload("res://scripts/core/Player.gd")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []


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


func _verdict() -> void:
        if failures.is_empty():
                print("[TEST] SUPERATO: tutte le fasi TASK 25 OK")
        else:
                print("[TEST] FALLITO: ", failures.size(), " errori")
        Engine.get_main_loop().quit()


func _physics_process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        match phase:
                0:
                        if t > 1.0:
                                _phaseA_limb_gain()
                                _phaseB_boss_walk()
                                _phaseC_boss_gain()
                                _phaseE_cloth_hue()
                                _phaseF_hammer_icon()
                                phase = 1
                1:
                        if t > 2.0:
                                _phaseD_armor_outfit()
                                _verdict()
                        elif t > 5.0:
                                _fail("D: player non pronto")
                                _verdict()


# ---------------- A. limb_gain: linearita' + clamp + visibilita' ----------------
func _phaseA_limb_gain() -> void:
        print("\n[TEST] FASE A — limb_gain (linearita' sotto clamp, clamp estremo, visibilita')")
        var ds := DeformableSpriteScript.new()
        add_child(ds)
        # TASK 28: il gioco usa i frame XHD (256px, _unit=4): i test di
        # visibilita' vanno misurati su quel percorso (a schermo 2.5 unita'
        # = 10px = ~4% del lato).
        ds.load_subrect("res://assets/sprites/xhd/boss_021_xhd_sheet.png", 0, 0, 256, 256)
        if not ds.loaded:
                _fail("A: deform sprite XHD non caricato")
                return
        ds.set_grid_size(16, 16)
        ds.limb_profile = DeformableSpriteScript.LimbProfile.LP_TENTACLES
        var gw := 16
        var gh := 16
        # vertice in basso al centro: peso tentacolo massimo
        var idx: int = gh * (gw + 1) + gw / 2
        var t_probe: float = 2.0
        ds.limb_gain = 0.0
        var v0: Vector2 = ds._transform_vertex(idx, DeformableSpriteScript.AnimMode.IDLE,
                        t_probe, gw, gh, 1.0, false, 256.0, 256.0)
        ds.limb_gain = 1.0
        var v1: Vector2 = ds._transform_vertex(idx, DeformableSpriteScript.AnimMode.IDLE,
                        t_probe, gw, gh, 1.0, false, 256.0, 256.0)
        ds.limb_gain = 0.5
        var v05: Vector2 = ds._transform_vertex(idx, DeformableSpriteScript.AnimMode.IDLE,
                        t_probe, gw, gh, 1.0, false, 256.0, 256.0)
        # 1) linearita' SOTTO il clamp (0.5 e 1.0 ampiamente dentro il limite)
        var lp_vec: Vector2 = v1 - v0
        if lp_vec.length() < 0.5:
                _fail("A: vertice campione senza movimento arti (%.3f)" % lp_vec.length())
        else:
                var expect: Vector2 = v0 + lp_vec * 0.5
                var err: float = (v05 - expect).length()
                if err < 0.05:
                        _ok("A: linearita' gain sotto clamp OK (v(0.5) == v(0)+0.5*(v(1)-v(0)), err %.4f)" % err)
                else:
                        _fail("A: linearita' gain VIOLATA sotto clamp (err %.4f)" % err)
        # 2) clamp di integrita' a gain estremo: ogni componente <= 2.5 unita'
        #    (= 10px XHD ~ 3.9% del lato): MAI lacerazioni per qualunque gain
        ds.limb_gain = 10.0
        var max_comp: float = 0.0
        for gy in range(gh + 1):
                for gx in range(gw + 1):
                        var i: int = gy * (gw + 1) + gx
                        var vv: Vector2 = ds._transform_vertex(i, DeformableSpriteScript.AnimMode.IDLE,
                                        t_probe, gw, gh, 1.0, false, 256.0, 256.0)
                        max_comp = maxf(maxf(max_comp, absf(vv.x - float(gx) * 16.0)),
                                        absf(vv.y - float(gy) * 16.0))
        var lim: float = DeformableSpriteScript.MAX_LIMB_OFFSET_UNITS * 4.0 + 0.1
        if max_comp <= lim:
                _ok("A: clamp integrita' OK (gain 10.0 -> max componente %.2fpx <= %.1fpx)"
                                % [max_comp, lim])
        else:
                _fail("A: clamp VIOLATO a gain 10.0 (max %.2fpx > %.1fpx)" % [max_comp, lim])
        # 3) visibilita' col gain di gioco: max spostamento arti sul bordo
        #    basso in 2s di animazione > 3% del lato (7.7px), e ogni
        #    componente dentro il limite anti-lacerazione (il clamp e'
        #    PER COMPONENTE: la lunghezza puo' arrivare a ~sqrt(2)x limite)
        ds.limb_gain = GameConstants.BOSS_LIMB_ANIM_GAIN
        var max_amp: float = 0.0
        var max_comp_game: float = 0.0
        for k in range(40):
                var tt: float = 0.05 * float(k)
                for gx in range(gw + 1):
                        var i2: int = gh * (gw + 1) + gx
                        ds.limb_gain = 0.0
                        var vv0: Vector2 = ds._transform_vertex(i2, DeformableSpriteScript.AnimMode.IDLE,
                                        tt, gw, gh, 1.0, false, 256.0, 256.0)
                        ds.limb_gain = GameConstants.BOSS_LIMB_ANIM_GAIN
                        var vv1: Vector2 = ds._transform_vertex(i2, DeformableSpriteScript.AnimMode.IDLE,
                                        tt, gw, gh, 1.0, false, 256.0, 256.0)
                        var dvec: Vector2 = vv1 - vv0
                        max_amp = maxf(max_amp, dvec.length())
                        max_comp_game = maxf(maxf(max_comp_game, absf(dvec.x)), absf(dvec.y))
        if max_amp > 256.0 * 0.03 and max_comp_game <= lim:
                _ok("A: visibilita' OK (max ampiezza arti %.1fpx su lato 256px = %.1f%%,"
                                % [max_amp, max_amp / 256.0 * 100.0]
                                + " max componente %.1fpx <= limite %.1fpx)" % [max_comp_game, lim])
        elif max_comp_game > lim:
                _fail("A: componente %.1fpx OLTRE il limite anti-glitch (%.1fpx)"
                                % [max_comp_game, lim])
        else:
                _fail("A: ampiezza %.1fpx sotto la soglia di visibilita' (7.7px)" % max_amp)
        remove_child(ds)
        ds.queue_free()


# ---------------- B. Boss terrestre in movimento = WALK ----------------
func _phaseB_boss_walk() -> void:
        print("\n[TEST] FASE B — modalità WALK del boss in movimento")
        var out: Array = []
        # get_boss_index(level) = (level/4) % 17: livello 68 -> 17%17 = 0
        # = GOLEM (LP_ARMS, terrestre); livello 4 -> 1 = LICH (LP_HOVER).
        var golem := BossScript.new()
        add_child(golem)
        golem.setup(68, 1920, 1080)
        golem._draw()
        if not golem.deform_loaded:
                _fail("B: golem non caricato")
        else:
                golem.dx = 1
                golem.dy = -1
                golem.attacking_timer_ms = 0
                golem.update_step(500.0, 500.0, 16, out)
                if golem.deform_sprite._current_mode == DeformableSpriteScript.AnimMode.WALK:
                        _ok("B: Golem in movimento -> WALK (prima restava in IDLE)")
                else:
                        _fail("B: Golem in movimento, modalita' %d (attesa WALK)"
                                        % golem.deform_sprite._current_mode)
        remove_child(golem)
        golem.queue_free()
        var lich := BossScript.new()
        add_child(lich)
        lich.setup(4, 1920, 1080)   # Lich (LP_HOVER, fluttuante)
        lich._draw()
        if lich.deform_loaded:
                lich.dx = 1
                lich.dy = 1
                lich.attacking_timer_ms = 0
                lich.update_step(500.0, 500.0, 16, out)
                if lich.deform_sprite._current_mode == DeformableSpriteScript.AnimMode.IDLE:
                        _ok("B: Lich fluttuante resta in IDLE (profilo LP_HOVER)")
                else:
                        _fail("B: Lich in modalita' %d (attesa IDLE)"
                                        % lich.deform_sprite._current_mode)
        else:
                _fail("B: lich non caricato")
        remove_child(lich)
        lich.queue_free()


# ---------------- C. Boss: limb_gain da GameConstants ----------------
func _phaseC_boss_gain() -> void:
        print("\n[TEST] FASE C — limb_gain del boss")
        var out: Array = []
        var b := BossScript.new()
        add_child(b)
        b.setup(4, 1920, 1080)
        b._draw()
        b.update_step(500.0, 500.0, 16, out)
        if b.deform_loaded:
                if is_equal_approx(b.deform_sprite.limb_gain,
                                GameConstants.BOSS_LIMB_ANIM_GAIN):
                        _ok("C: limb_gain %.2f == GameConstants.BOSS_LIMB_ANIM_GAIN"
                                        % b.deform_sprite.limb_gain)
                else:
                        _fail("C: limb_gain %.3f != %.3f" % [b.deform_sprite.limb_gain,
                                        GameConstants.BOSS_LIMB_ANIM_GAIN])
        else:
                _fail("C: boss non caricato")
        remove_child(b)
        b.queue_free()


# ---------------- D. Armor outfit: equip / rottura / rollback ----------------
func _phaseD_armor_outfit() -> void:
        print("\n[TEST] FASE D — outfit armatura (materiali sprite)")
        var p: CharacterBody2D = main.player
        if p == null or p.sprite == null:
                _fail("D: player/sprite null")
                return
        var fire_def: Dictionary = GameConstants.RELIC_ARMORS[4]   # corazza di fuoco
        p.equip_relic_armor(fire_def)
        if CharacterArt.has_armor_outfit(p.sprite):
                var mat: ShaderMaterial = p.sprite.material
                var col: Color = mat.get_shader_parameter("armor_color")
                if absf(col.r - fire_def.color.r) < 0.02 and absf(col.g - fire_def.color.g) < 0.02:
                        _ok("D: equip fuoco -> armor_outfit attivo, armor_color coerente")
                else:
                        _fail("D: armor_color %s != %s" % [col, fire_def.color])
                var hue_val: Variant = mat.get_shader_parameter("cloth_hue")
                var str_val: Variant = mat.get_shader_parameter("cloth_strength")
                if hue_val == null:
                        hue_val = -1.0   # personaggio senza hue vestito (tinta metallo)
                _ok("D: cloth_hue %s, cloth_strength %s (hue vestito player1)"
                                % [str(hue_val), str(str_val)])
        else:
                _fail("D: equip armatura -> materiale outfit NON applicato")
        # rottura: torna l'enhancement standard
        p._break_relic_armor()
        if not CharacterArt.has_armor_outfit(p.sprite):
                if p.sprite.material is ShaderMaterial:
                        _ok("D: rottura -> enhancement standard ripristinato")
                else:
                        _ok("D: rottura -> materiale outfit rimosso")
        else:
                _fail("D: rottura -> materiale outfit ANCORA attivo")
        # rollback: flag OFF -> mai applicato
        GameConstants.ARMOR_OUTFIT_ENABLED = false
        p.equip_relic_armor(fire_def)
        if not CharacterArt.has_armor_outfit(p.sprite):
                _ok("D: rollback ARMOR_OUTFIT_ENABLED=false -> outfit mai applicato")
        else:
                _fail("D: rollback: outfit applicato col flag spento")
        p._break_relic_armor()
        GameConstants.ARMOR_OUTFIT_ENABLED = true


# ---------------- E. _compute_cloth_hue su immagini sintetiche ----------------
func _phaseE_cloth_hue() -> void:
        print("\n[TEST] FASE E — calcolo hue vestito (deterministico)")
        var pp := PlayerScript.new()
        # immagine sintetica BLU (vestito blu su fondo trasparente)
        var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
        img.fill(Color(0, 0, 0, 0))
        for y in range(8, 56):
                for x in range(20, 44):
                        img.set_pixel(x, y, Color(0.1, 0.2, 0.9, 1.0))
        pp._character_sheet_texture = ImageTexture.create_from_image(img)
        pp._frame_px = 64
        var hue_blue: float = pp._compute_cloth_hue()
        if hue_blue > 0.6 and hue_blue < 0.75:
                _ok("E: vestito blu -> hue %.3f (atteso ~0.6875)" % hue_blue)
        else:
                _fail("E: vestito blu -> hue %.3f fuori range" % hue_blue)
        # determinismo
        if is_equal_approx(pp._compute_cloth_hue(), hue_blue):
                _ok("E: deterministico (stesso sheet -> stesso hue)")
        else:
                _fail("E: NON deterministico")
        # grigio (nessun saturo) -> -1
        var img2 := Image.create(64, 64, false, Image.FORMAT_RGBA8)
        img2.fill(Color(0.5, 0.5, 0.5, 1.0))
        pp._character_sheet_texture = ImageTexture.create_from_image(img2)
        if pp._compute_cloth_hue() < 0.0:
                _ok("E: tutto grigio -> -1 (solo tinta metallo)")
        else:
                _fail("E: tutto grigio -> atteso -1")
        # pelle -> -1 (guardia pelle)
        var img3 := Image.create(64, 64, false, Image.FORMAT_RGBA8)
        img3.fill(Color(0, 0, 0, 0))
        for y in range(8, 56):
                for x in range(20, 44):
                        img3.set_pixel(x, y, Color(1.0, 0.78, 0.62, 1.0))
        pp._character_sheet_texture = ImageTexture.create_from_image(img3)
        if pp._compute_cloth_hue() < 0.0:
                _ok("E: solo pelle -> -1 (guardia pelle)")
        else:
                _fail("E: solo pelle -> atteso -1")
        pp.queue_free()


# ---------------- F. Icona Mjolnir rigenerata ----------------
func _phaseF_hammer_icon() -> void:
        print("\n[TEST] FASE F — icona Mjolnir (rigenerata)")
        var abs_path: String = ProjectSettings.globalize_path(
                        "res://assets/sprites/collectibles/item_hammer.png")
        var img := Image.new()
        if img.load(abs_path) != OK:
                _fail("F: item_hammer.png non caricabile")
                return
        if img.get_width() != 128 or img.get_height() != 128:
                _fail("F: dimensione %dx%d (attesa 128x128)" % [img.get_width(), img.get_height()])
                return
        # flood fill a 8-connessioni sull'alpha: la componente principale deve
        # coprire >97% dei pixel opachi (il manico spezzato era ~frammentato).
        var visited: Dictionary = {}
        var opaque: int = 0
        var best_size: int = 0
        for y in range(128):
                for x in range(128):
                        var c: Color = img.get_pixel(x, y)
                        if c.a <= 0.16:
                                continue
                        opaque += 1
                        var key: int = y * 128 + x
                        if visited.has(key):
                                continue
                        # BFS (iterativo, senza ricorsione)
                        var stack: Array[int] = [key]
                        visited[key] = true
                        var size: int = 0
                        while not stack.is_empty():
                                var k: int = stack.pop_back()
                                size += 1
                                var ky: int = k / 128
                                var kx: int = k % 128
                                for d in [Vector2i(-1, 0), Vector2i(1, 0),
                                                Vector2i(0, -1), Vector2i(0, 1),
                                                Vector2i(-1, -1), Vector2i(1, -1),
                                                Vector2i(-1, 1), Vector2i(1, 1)]:
                                        var ny: int = ky + d.y
                                        var nx: int = kx + d.x
                                        if ny < 0 or ny >= 128 or nx < 0 or nx >= 128:
                                                continue
                                        var nk: int = ny * 128 + nx
                                        if visited.has(nk):
                                                continue
                                        var nc: Color = img.get_pixel(nx, ny)
                                        if nc.a > 0.16:
                                                visited[nk] = true
                                                stack.append(nk)
                        best_size = maxi(best_size, size)
        if opaque < 500:
                _fail("F: icona quasi vuota (%d px opachi)" % opaque)
        elif float(best_size) / float(opaque) > 0.97:
                _ok("F: icona Mjolnir integra (componente principale %.1f%% di %d px)"
                                % [100.0 * best_size / opaque, opaque])
        else:
                _fail("F: icona Mjolnir FRAMMENTATA (componente principale %.1f%%)"
                                % [100.0 * best_size / opaque])
