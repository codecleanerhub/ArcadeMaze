## test_gfx_xhd.gd — Test headless del potenziamento grafico Task 22.
## Verifica nel runtime REALE di Godot:
##   A. Flag di rollback presenti e accesi (default true)
##   B. PLAYER: sheet XHD caricato (frame 256px, AtlasTexture region 256x256,
##      scala compensata 0.325) — per TUTTI i 9 personaggi
##   C. PLAYER legacy: flag OFF -> ricade sullo sheet SD (frame 64px, scala 1.3)
##      [rollback garantito]
##   D. RUOTA SELEZIONE: texture XHD caricate (larghezza 1024)
##   E. BOSS: DeformableSprite su sheet XHD PixelLab v2 (texture 1536x512
##      o 1536x768 = griglia 6x2/6x3 frame @ 256px, sub_rect 256,
##      grid 16x16, filtro LINEAR) + profili arti per tutti i 17 tipi
##      + rilevamento frame TASK 46 coerente (cols=6, rows=2/3)
##   F. BOSS legacy: flag OFF -> sheet SD (384x128/384x192, sub_rect 64,
##      grid 8x8) [rollback]
##   G. DEFORMABLE SPRITE: mesh valida per OGNI LimbProfile (nessun crash,
##      vertici attesi, offset arti non nulli a metà frame)
##   H. PROIETTILI: _draw() tematico per TUTTI i 17 BossProjKind senza crash
##      (e BP_NORMAL player invariato); flag OFF -> ramo legacy
##   I. Silhouette preservata: alpha coverage del frame XHD == frame SD
##      (entro tolleranza 1.5%: smoothstep aa)
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const PlayerScript = preload("res://scripts/core/Player.gd")
const BossScript = preload("res://scripts/bosses/Boss.gd")
const ProjectileScript = preload("res://scripts/items/Projectile.gd")
const DeformableSpriteScript = preload("res://scripts/core/DeformableSprite.gd")

var failures: Array = []
var checks: int = 0


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ok(msg: String) -> void:
        checks += 1
        print("[TEST OK] ", msg)


func _ready() -> void:
        call_deferred("_run_all")


func _run_all() -> void:
        _phase_a_flags()
        _phase_b_player_xhd()
        _phase_c_player_legacy()
        await _phase_d_select_player()
        _phase_e_boss_xhd()
        _phase_f_boss_legacy()
        _phase_g_deform_profiles()
        _phase_h_projectiles()
        _phase_i_silhouette()

        print("\n[TEST] === RISULTATO: ", checks, " controlli OK, ",
                failures.size(), " fallimenti ===")
        if failures.is_empty():
                print("[TEST] SUCCESS: potenziamento grafico XHD funzionante e reversibile")
                get_tree().quit(0)
        else:
                print("[TEST] FAILED")
                get_tree().quit(1)


# ---------------- A. Flag ----------------
func _phase_a_flags() -> void:
        print("\n[TEST] FASE A — flag di rollback")
        if C.SPRITE_XHD_ENABLED and C.BOSS_LIMB_ANIM_ENABLED and C.BOSS_PROJ_THEMED_ENABLED:
                _ok("flag SPRITE_XHD/BOSS_LIMB_ANIM/BOSS_PROJ_THEMED presenti e attivi")
        else:
                _fail("flag Task 22 non attivi di default")
        if C.SPRITE_XHD_FRAME_PX == 256 and C.xhd_sheet_path("boss_031").ends_with("boss_031_xhd_sheet.png"):
                _ok("costanti XHD coerenti (frame 256, percorso xhd/)")
        else:
                _fail("costanti XHD incoerenti")


# ---------------- B. Player XHD ----------------
func _make_player_with_sprite() -> Node:
        # Player.gd si aspetta un figlio "Sprite2D" (nella scena di gioco è un
        # nodo della scena): nei test lo creiamo a mano PRIMA di add_child
        # così @onready var sprite = $Sprite2D lo trova.
        var p := PlayerScript.new()
        var s := Sprite2D.new()
        s.name = "Sprite2D"
        p.add_child(s)
        return p


func _phase_b_player_xhd() -> void:
        print("\n[TEST] FASE B — player con sheet XHD (9 personaggi)")
        var sprite_bases := ["player1", "player2", "char_mage", "char_orc",
                "char_elf", "char_knight", "char_golem", "char_dragon", "char_vampire"]
        for ct in 9:
                var p := _make_player_with_sprite()
                add_child(p)
                p.set_character(ct, 1)
                if not p.sprite_loaded or p.sprite == null:
                        _fail("char %d: sprite non caricato" % ct)
                        remove_child(p); p.queue_free()
                        continue
                var tex: Texture2D = p.sprite.texture
                if tex is AtlasTexture:
                        var reg: Rect2 = (tex as AtlasTexture).region
                        var atlas_w: int = (tex as AtlasTexture).atlas.get_width()
                        if reg.size.x == 256 and atlas_w == 1024:
                                # scala compensata: 1.3 * 64/256 = 0.325
                                if absf(p.sprite.scale.x - 0.325) < 0.001:
                                        _ok("char %s: XHD ok (frame 256, sheet 1024, scala %.3f)"
                                                        % [sprite_bases[ct], p.sprite.scale.x])
                                else:
                                        _fail("char %s: scala XHD errata %.3f (attesa 0.325)"
                                                        % [sprite_bases[ct], p.sprite.scale.x])
                        else:
                                _fail("char %s: frame XHD errato %s (atlas %d)"
                                                % [sprite_bases[ct], reg.size, atlas_w])
                else:
                        _fail("char %d: texture non AtlasTexture" % ct)
                remove_child(p)
                p.queue_free()


# ---------------- C. Player legacy (rollback) ----------------
func _phase_c_player_legacy() -> void:
        print("\n[TEST] FASE C — player legacy (flag OFF = rollback)")
        C.SPRITE_XHD_ENABLED = false
        var p := _make_player_with_sprite()
        add_child(p)
        p.set_character(0, 1)
        if p.sprite_loaded and p.sprite != null and p.sprite.texture is AtlasTexture:
                var reg: Rect2 = (p.sprite.texture as AtlasTexture).region
                if reg.size.x == 64 and absf(p.sprite.scale.x - 1.3) < 0.001:
                        _ok("rollback: frame SD 64px + scala 1.3 (identico a pre-Task 22)")
                else:
                        _fail("rollback player: region %s scala %.3f" % [reg.size, p.sprite.scale.x])
        else:
                _fail("rollback: sprite/texture non caricati")
        remove_child(p)
        p.queue_free()
        # ripristino SEMPRE (i runtime error in GDScript abortiscono la funzione:
        # mai lasciare un flag spento dietro un ramo che può fallire)
        C.SPRITE_XHD_ENABLED = true


# ---------------- D. Ruota selezione ----------------
func _phase_d_select_player() -> void:
        print("\n[TEST] FASE D — ruota selezione personaggi")
        var scene := load("res://scenes/SelectPlayer.tscn") as PackedScene
        if scene == null:
                _fail("SelectPlayer.tscn non caricabile")
                return
        var sp := scene.instantiate()
        add_child(sp)
        await get_tree().process_frame
        var xhd_count: int = 0
        for i in sp._char_textures.size():
                var t: Texture2D = sp._char_textures[i]
                if t != null and t.get_width() == 1024:
                        xhd_count += 1
        if xhd_count == 8:
                _ok("ruota: 8/8 texture XHD (sheet 1024x256)")
        else:
                _fail("ruota: solo %d/8 texture XHD" % xhd_count)
        # un _draw completo non deve crashare
        sp.queue_redraw()
        await get_tree().process_frame
        _ok("ruota: _draw() con texture XHD senza errori")
        remove_child(sp)
        sp.queue_free()


# ---------------- E. Boss XHD + profili arti ----------------
func _phase_e_boss_xhd() -> void:
        print("\n[TEST] FASE E — boss XHD + profili arti (17 tipi)")
        for t in 17:
                var b := BossScript.new()
                add_child(b)
                b.setup(4 + t * 4, 1920, 1080)   # livello del boss tipo t
                b._draw()                          # lazy-load della texture
                if not b.deform_loaded:
                        _fail("boss tipo %d: deform sprite non caricato" % t)
                        remove_child(b); b.queue_free()
                        continue
                var tex: Texture2D = b.deform_sprite.texture
                # TASK 69: sheet boss PixelLab v2 = griglie 6x2/6x3 di frame
                # 256px -> larghezza SEMPRE 1536, altezza 512 (2 righe) o
                # 768 (3 righe: idle/attack/walk). Era 1024x256 pre-v2.
                if tex.get_width() != 1536:
                        _fail("boss tipo %d: texture XHD attesa 1536, avuta %d"
                                        % [t, tex.get_width()])
                var th: int = tex.get_height()
                if th != 512 and th != 768:
                        _fail("boss tipo %d: altezza XHD attesa 512/768, avuta %d"
                                        % [t, th])
                # TASK 46: rilevamento frame reali coerente con la griglia v2
                if b._frame_cols != 6 or b._frame_rows != th / 256:
                        _fail("boss tipo %d: frame grid %dx%d != attesa 6x%d"
                                        % [t, b._frame_cols, b._frame_rows, th / 256])
                if b.deform_sprite.sub_rect.size.x != 256.0:
                        _fail("boss tipo %d: sub_rect XHD errata %s"
                                        % [t, b.deform_sprite.sub_rect.size])
                if b.deform_sprite.grid_w != 16:
                        _fail("boss tipo %d: grid XHD attesa 16 (Task 28), avuta %d"
                                        % [t, b.deform_sprite.grid_w])
                var prof: int = BossScript.get_limb_profile(b.boss_type)
                if C.BOSS_LIMB_ANIM_ENABLED and b.deform_sprite.limb_profile != prof:
                        _fail("boss tipo %d: profilo arti %d != atteso %d"
                                        % [b.boss_type, b.deform_sprite.limb_profile, prof])
                # update_step con XHD: scala = size/256
                var out: Array = []
                b.update_step(500.0, 500.0, 16, out)
                _ok("boss tipo %d: XHD ok (tex %dx%d, grid frame %dx%d, sub_rect %.0f, grid %d, profilo %d, scala %.3f)"
                                % [b.boss_type, tex.get_width(), th, b._frame_cols,
                                   b._frame_rows, b.deform_sprite.sub_rect.size.x,
                                   b.deform_sprite.grid_w, prof, b.size / float(b._frame_px)])
                remove_child(b)
                b.queue_free()


# ---------------- F. Boss legacy (rollback) ----------------
func _phase_f_boss_legacy() -> void:
        print("\n[TEST] FASE F — boss legacy (flag OFF = rollback)")
        C.SPRITE_XHD_ENABLED = false
        C.BOSS_LIMB_ANIM_ENABLED = false
        var b := BossScript.new()
        add_child(b)
        b.setup(4, 1920, 1080)
        b._draw()
        if b.deform_loaded and b.deform_sprite.texture.get_width() == 384 \
                        and (b.deform_sprite.texture.get_height() == 128
                                        or b.deform_sprite.texture.get_height() == 192) \
                        and b.deform_sprite.sub_rect.size.x == 64.0 \
                        and b.deform_sprite.grid_w == 8:
                _ok("rollback boss: sheet SD v2 384x128/192, sub_rect 64, grid 8")
        else:
                _fail("rollback boss: tex %dx%d sub_rect %s grid %d" % [
                        b.deform_sprite.texture.get_width(),
                        b.deform_sprite.texture.get_height(),
                        b.deform_sprite.sub_rect.size, b.deform_sprite.grid_w])
        # un update_step con il flag spento deve lasciare LP_NONE
        var out: Array = []
        b.update_step(500.0, 500.0, 16, out)
        if b.deform_sprite.limb_profile == DeformableSpriteScript.LimbProfile.LP_NONE:
                _ok("rollback: profilo arti LP_NONE con flag spento")
        else:
                _fail("rollback: profilo arti non LP_NONE con flag spento")
        remove_child(b)
        b.queue_free()
        C.SPRITE_XHD_ENABLED = true
        C.BOSS_LIMB_ANIM_ENABLED = true


# ---------------- G. DeformableSprite: tutti i profili ----------------
func _phase_g_deform_profiles() -> void:
        print("\n[TEST] FASE G — DeformableSprite, mesh per ogni LimbProfile")
        for prof in 6:  # LP_NONE..LP_STALKS
                var ds := DeformableSpriteScript.new()
                add_child(ds)
                var path: String = C.xhd_sheet_path("boss_030")  # kraken XHD
                var loaded: bool = ds.load_subrect(path, 0, 0, 256, 256)
                if not loaded:
                        _fail("profilo %d: load_subrect XHD fallito" % prof)
                        remove_child(ds); ds.queue_free()
                        continue
                ds.set_grid_size(12, 12)
                ds.limb_profile = prof
                ds.update(0.77, DeformableSpriteScript.AnimMode.IDLE, 1.0, false)
                var arrays: Array = ds.mesh.surface_get_arrays(0)
                var verts: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
                var expected_verts: int = 12 * 12 * 6
                if verts.size() != expected_verts:
                        _fail("profilo %d: vertici %d != attesi %d"
                                        % [prof, verts.size(), expected_verts])
                # verifica che il profilo sposti realmente i vertici rispetto a LP_NONE
                var ds_none := DeformableSpriteScript.new()
                add_child(ds_none)
                ds_none.load_subrect(path, 0, 0, 256, 256)
                ds_none.set_grid_size(12, 12)
                ds_none.limb_profile = DeformableSpriteScript.LimbProfile.LP_NONE
                ds_none.update(0.77, DeformableSpriteScript.AnimMode.IDLE, 1.0, false)
                var verts_none: PackedVector2Array = ds_none.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
                if prof != DeformableSpriteScript.LimbProfile.LP_NONE:
                        var moved: int = 0
                        for vi in verts.size():
                                if (verts[vi] - verts_none[vi]).length() > 0.001:
                                        moved += 1
                        if moved > 0:
                                _ok("profilo %d: mesh valida (%d vertici), %d vertici mossi dagli arti"
                                                % [prof, verts.size(), moved])
                        else:
                                _fail("profilo %d: NESSUN vertice mosso (animazione arti inerte)" % prof)
                else:
                        _ok("profilo LP_NONE: mesh valida (%d vertici), identico al legacy" % verts.size())
                remove_child(ds_none)
                ds_none.queue_free()
                remove_child(ds)
                ds.queue_free()


# ---------------- H. Proiettili tematici ----------------
func _phase_h_projectiles() -> void:
        print("\n[TEST] FASE H — proiettili boss tematici (17 tipi + player)")
        # tutti i 17 tipi boss (BossProjKind 1..17)
        for kind in range(1, 18):
                var p := ProjectileScript.new()
                p.bp_kind = kind
                p.variant = 0
                p.dir = Vector2(3.0, 1.5)
                p.age_ms = 730
                p.active = true
                add_child(p)
                p._draw()   # ramo tematico: non deve crashare
                # homing con dir che cambia (angolo diverso)
                p.dir = Vector2(-2.0, 2.5)
                p.age_ms = 1500
                p._draw()
                _ok("proiettile kind %d: disegno tematico OK (2 direzioni)" % kind)
                remove_child(p)
                p.queue_free()
        # proiettili player (BP_NORMAL): ramo legacy invariato
        for wtype in 4:
                var pp := ProjectileScript.new()
                pp.bp_kind = 0
                pp.weapon_type = wtype
                pp.dir = Vector2(4.0, 0.0)
                pp.age_ms = 250
                pp.active = true
                add_child(pp)
                pp._draw()
                remove_child(pp)
                pp.queue_free()
        _ok("proiettili player BP_NORMAL: 4 armi legacy senza crash")
        # rollback: flag OFF -> il ramo legacy dei boss non crasha
        C.BOSS_PROJ_THEMED_ENABLED = false
        for kind in range(1, 18):
                var pl := ProjectileScript.new()
                pl.bp_kind = kind
                pl.dir = Vector2(3.0, 1.5)
                pl.age_ms = 730
                pl.active = true
                add_child(pl)
                pl._draw()
                remove_child(pl)
                pl.queue_free()
        C.BOSS_PROJ_THEMED_ENABLED = true
        _ok("rollback proiettili: ramo legacy OK per tutti i 17 tipi")


# ---------------- I. Silhouette preservata ----------------
func _phase_i_silhouette() -> void:
        print("\n[TEST] FASE I — silhouette XHD == SD (trasparenze preservate)")
        var probes := ["player1", "boss_030", "boss_031", "char_dragon"]
        for id in probes:
                var sd_path := "res://assets/sprites/%s_sheet.png" % id
                var xhd_path := C.xhd_sheet_path(id)
                var sd_img := Image.new()
                var xh_img := Image.new()
                var sd_abs: String = ProjectSettings.globalize_path(sd_path)
                var xh_abs: String = ProjectSettings.globalize_path(xhd_path)
                if sd_img.load(sd_abs) != OK or xh_img.load(xh_abs) != OK:
                        _fail("silhouette %s: caricamento SD/XHD fallito" % id)
                        continue
                # frame 0 di entrambi
                var cov_sd: float = _alpha_coverage(sd_img, 64)
                var cov_xhd: float = _alpha_coverage(xh_img, 256)
                var delta: float = absf(cov_sd - cov_xhd)
                if delta <= 0.015:
                        _ok("silhouette %s: coverage %.3f vs %.3f (delta %.4f <= 1.5%%)"
                                        % [id, cov_sd, cov_xhd, delta])
                else:
                        _fail("silhouette %s: delta coverage %.4f > 1.5%%" % [id, delta])


func _alpha_coverage(img: Image, frame_px: int) -> float:
        # porzione di pixel con alpha > 128 sul frame 0 (primi frame_px px)
        var opaque: int = 0
        var total: int = frame_px * frame_px
        for y in frame_px:
                for x in frame_px:
                        if img.get_pixel(x, y).a > 0.5:
                                opaque += 1
        return float(opaque) / float(total)
