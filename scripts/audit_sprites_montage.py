#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
audit_sprites_montage.py — Audit visivo "mezzo busto" nemici/boss ArcadeMaze.

Crea montaggi PNG (in /home/z/my-project/download/) del frame 0 di ogni
spritesheet nemico/boss, con etichette leggibili, per l'analisi VLM
(character shot full-body vs half-body bust).

Uso:
  python3 audit_sprites_montage.py enemies      # montaggi nemici (12 per img)
  python3 audit_sprites_montage.py bosses       # montaggi boss (9 per img, incl. USER-IMAGE)
  python3 audit_sprites_montage.py all          # entrambi
  python3 audit_sprites_montage.py crops m007,boss_027,boss_021
                                                # crop dedicati 2x per query VLM
                                                # (mostra piu' frame: walk/idle/attack)

NON modifica asset del gioco: solo lettura + scrittura in download/.
"""
import os
import sys
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = "/home/z/my-project"
SPRITES = os.path.join(ROOT, "ArcadeMaze/godot/assets/sprites")
OUT_DIR = os.path.join(ROOT, "download")
USER_IMG = os.path.join(ROOT, "upload/pasted_image_1793297193139.png")

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"

# Sfondo scuro + colori etichette
BG = (18, 18, 28)
TILE_BG = (30, 30, 44)
GRID = (60, 60, 90)
LABEL_COLOR = (255, 220, 90)     # giallo: nome tipo
SUB_LABEL_COLOR = (170, 170, 200)  # grigio-chiaro: id + nome display
USER_LABEL_COLOR = (120, 255, 120)

# ---------------------------------------------------------------------------
# MAPPA NEMICI (da godot/scripts/enemies/Enemy.gd: enum EnemyType righe 43-59,
# SPRITE_ID righe 70-115; nomi display da I18nManager.gd righe 305-348).
# Ordine = id sprite crescente. (monster_014 NON esiste: slot saltato.)
# ---------------------------------------------------------------------------
ENEMIES = [
    ("GHOUL",             "monster_001", "Ghoul"),
    ("SPIDER",            "monster_002", "Ragno Abissale"),
    ("WOLF",              "monster_003", "Lupo Spettrale"),
    ("CULTIST",           "monster_004", "Cultista Corrotto"),
    ("MIMIC",             "monster_005", "Mimic Borsa"),
    ("RAT",               "monster_006", "Ratto Gigante"),
    ("WITCH",             "monster_007", "Strega delle Paludi"),
    ("SKELETON",          "monster_008", "Scheletro Lanciere"),
    ("GHOST",             "monster_009", "Ombra Strisciante"),
    ("BONE_GOLEM",        "monster_010", "Golem di Ossa"),
    ("ASH_SERPENT",       "monster_011", "Serpente di Cenere"),
    ("DAMNED_KNIGHT",     "monster_012", "Cavaliere Dannato"),
    ("MAD_WIZARD",        "monster_013", "Mago Folle"),
    ("DEMONIC_CROW",      "monster_015", "Corvo Demoniaco"),
    ("TENTACLE",          "monster_016", "Tentacolo Sotterraneo"),
    ("GARGOYLE",          "monster_017", "Gargoyle Vegliante"),
    ("WELL_SPIRIT",       "monster_018", "Spirito del Pozzo"),
    ("CURSED_BOAR",       "monster_019", "Cinghiale Maledetto"),
    ("PREDATOR_FUNGUS",   "monster_020", "Fungo Predatore"),
    ("ZOMBIE",            "monster_021", "Zombie"),
    ("BAT",               "monster_022", "Pipistrello"),
    ("SLIME",             "monster_023", "Melma"),
    ("DEMON",             "monster_024", "Demone"),
    ("ROBOT",             "monster_025", "Robot"),
    ("GOBLIN",            "monster_026", "Goblin"),
    ("ORC",               "monster_027", "Orco"),
    ("WRAITH",            "monster_028", "Spettro"),
    ("IMP",               "monster_029", "Imp"),
    ("OWLBEAR",           "monster_030", "Orso-Gufo"),
    ("GIBBERING_MOUTHER", "monster_031", "Bocca Farfugliante"),
    ("HELLHOUND",         "monster_032", "Mastino Infernale"),
    ("BARLGURA",          "monster_033", "Barlgura"),
    ("TROGLODYTE",        "monster_034", "Troglodita"),
    ("BULETTE",           "monster_035", "Bulette"),
    ("KUO_TOA",           "monster_036", "Kuo-Toa"),
    ("BASILISK",          "monster_037", "Basilisco"),
    ("COCKATRICE",        "monster_038", "Coccatrice"),
    ("UMBER_HULK",        "monster_039", "Umber Hulk"),
    ("HOOK_HORROR",       "monster_040", "Orrore Uncinato"),
    ("DOPPELGANGER",      "monster_041", "Doppelganger"),
    ("ENT",               "monster_042", "Ent"),
    ("CAVE_DRAKE",        "monster_043", "Drago delle Caverne"),
    ("LOST_SOUL",         "monster_044", "Anima Perduta"),
    ("POSSESSED_SOLDIER", "monster_045", "Soldato Posseduto"),
]

# ---------------------------------------------------------------------------
# MAPPA BOSS (da godot/scripts/bosses/Boss.gd: enum Type righe 33-40,
# get_sprite_id righe 223-242, get_boss_name righe 248-270).
# ---------------------------------------------------------------------------
BOSSES = [
    ("BOSS_GHOUL_LORD",      "boss_021", "Signore dei Ghoul"),
    ("BOSS_SPIDER",          "boss_022", "Regina Ragno Abissale"),
    ("BOSS_SPECTRAL_ALPHA",  "boss_023", "Lupo Alfa Spettrale"),
    ("BOSS_CULT_HERALD",     "boss_024", "Araldo del Culto"),
    ("BOSS_COLOSSAL_MIMIC",  "boss_025", "Mimico Colossale"),
    ("BOSS_RAT_KING",        "boss_026", "Re dei Ratti"),
    ("BOSS_SUPREME_WITCH",   "boss_027", "Strega Suprema"),
    ("BOSS_TWILIGHT_KNIGHT", "boss_028", "Cavaliere del Crepuscolo"),
    ("BOSS_VAMPIRE",         "boss_029", "Vescovo Vampiro"),
    ("BOSS_KRAKEN",          "boss_030", "Guardiano delle Profondita'"),
    ("BOSS_GOLEM",           "boss_031", "Golem di Pietra"),
    ("BOSS_LICH",            "boss_032", "Lich Necromante"),
    ("BOSS_DEMON",           "boss_033", "Demone Abissale"),
    ("BOSS_ABOMINATION",     "boss_034", "Abominio"),
    ("BOSS_DRAGON",          "boss_035", "Drago Antico"),
    ("BOSS_WRAITH_LORD",     "boss_036", "Signore degli Spettri"),
    ("BOSS_BEHOLDER",        "boss_037", "Beholder"),
]


def load_sheet_frames(sprite_id):
    """Carica lo sheet SD e ritorna (meta, lista frame PIL) di riga 0 e delle
    altre righe. Frame = 64x64 (default) o come da meta.json."""
    png = os.path.join(SPRITES, sprite_id + "_sheet.png")
    meta_path = os.path.join(SPRITES, sprite_id + "_meta.json")
    if not os.path.exists(png):
        return None, []
    im = Image.open(png).convert("RGBA")
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)
    fw = int(meta.get("frameWidth", 64))
    fh = int(meta.get("frameHeight", 64))
    cols = int(meta.get("columns", max(1, im.width // fw)))
    rows = int(meta.get("rows", max(1, im.height // fh)))
    frames = []
    for r in range(rows):
        row_frames = []
        for c in range(cols):
            box = (c * fw, r * fh, (c + 1) * fw, (r + 1) * fh)
            if box[2] <= im.width and box[3] <= im.height:
                row_frames.append(im.crop(box))
        frames.append(row_frames)
    return meta, frames


def draw_sprite_on_tile(draw_img, sprite_rgba, area_x, area_y, area_size):
    """Incolla lo sprite (RGBA) centrato in un'area area_size x area_size,
    sfondo scuro, resize NEAREST preservando l'aspetto."""
    cell = Image.new("RGBA", (area_size, area_size), TILE_BG + (255,))
    w, h = sprite_rgba.size
    scale = min(area_size // w, area_size // h)
    scale = max(1, scale)
    nw, nh = w * scale, h * scale
    resized = sprite_rgba.resize((nw, nh), Image.NEAREST)
    cell.paste(resized, ((area_size - nw) // 2, (area_size - nh) // 2), resized)
    draw_img.alpha_composite(cell, (area_x, area_y))


def make_tile(entry, size=128, user_image=False):
    """Tile singolo: sprite 2x + etichetta su 2 righe. Ritorna PIL RGBA."""
    type_name, sprite_id, display = entry
    pad = 6
    label_h = 40
    tile_w = size + pad * 2
    tile_h = size + pad * 2 + label_h
    tile = Image.new("RGBA", (tile_w, tile_h), TILE_BG + (255,))
    d = ImageDraw.Draw(tile)
    d.rectangle([0, 0, tile_w - 1, tile_h - 1], outline=GRID, width=1)

    if user_image:
        img = Image.open(USER_IMG).convert("RGBA")
        # resize per riempire l'area mantenendo NEAREST
        w, h = img.size
        scale = max(size // w, size // h)
        nw, nh = w * scale, h * scale
        img = img.resize((nw, nh), Image.NEAREST)
        left = max(0, (nw - size) // 2)
        top = max(0, (nh - size) // 2)
        img = img.crop((left, top, left + size, top + size))
        tile.paste(img, (pad, pad), img)
        label1 = "USER-IMAGE"
        label2 = "strega (riferimento utente)"
        color1 = USER_LABEL_COLOR
    else:
        meta, frames = load_sheet_frames(sprite_id)
        if frames and frames[0]:
            draw_sprite_on_tile(tile, frames[0][0], pad, pad, size)
        else:
            d.text((pad + 4, pad + size // 2), "SHEET\nMANCANTE", fill=(255, 80, 80))
        label1 = type_name
        label2 = "%s - %s" % (sprite_id, display)
        color1 = LABEL_COLOR

    f1 = ImageFont.truetype(FONT_BOLD, 15)
    f2 = ImageFont.truetype(FONT_MONO, 11)
    d.text((pad + 1, pad * 2 + size + 3), label1, font=f1, fill=color1)
    # sub-label: tronca se troppo lungo
    max_chars = 30
    if len(label2) > max_chars:
        label2 = label2[: max_chars - 1] + "."
    d.text((pad + 1, pad * 2 + size + 21), label2, font=f2, fill=SUB_LABEL_COLOR)
    return tile


def make_montage(entries, out_path, cols, title, user_image_entries=0):
    """Montaggio a griglia di tile."""
    size = 128
    pad = 6
    label_h = 40
    tile_w = size + pad * 2
    tile_h = size + pad * 2 + label_h
    margin = 14
    title_h = 34
    rows = (len(entries) + cols - 1) // cols
    W = margin * 2 + cols * tile_w + (cols - 1) * 8
    H = title_h + margin * 2 + rows * tile_h + (rows - 1) * 8
    canvas = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(canvas)
    ft = ImageFont.truetype(FONT_BOLD, 19)
    d.text((margin, 10), title, font=ft, fill=(240, 240, 255))

    for i, entry in enumerate(entries):
        is_user = i < user_image_entries  # le user-image stanno in testa
        tile = make_tile(entry, size=size, user_image=is_user)
        r, c = divmod(i, cols)
        x = margin + c * (tile_w + 8)
        y = title_h + margin + r * (tile_h + 8)
        canvas.alpha_composite(tile, (x, y))

    canvas.convert("RGB").save(out_path, "PNG")
    print("salvato: %s (%d sprite, %dx%d)" % (out_path, len(entries), W, H))


def cmd_enemies():
    per_img = 12
    batches = [ENEMIES[i:i + per_img] for i in range(0, len(ENEMIES), per_img)]
    for i, batch in enumerate(batches, 1):
        out = os.path.join(OUT_DIR, "audit_enemies_%d.png" % i)
        make_montage(
            batch, out, cols=4,
            title="AUDIT NEMICI — frame 0 (sheet SD 64px, cella 128px) — batch %d/%d"
                  % (i, len(batches)))


def cmd_bosses():
    per_img = 9
    # USER-IMAGE inserita solo nel primo batch (in testa) per confronto diretto
    user_entry = ("USER-IMAGE", "user", "riferimento utente (strega)")
    entries = [user_entry] + BOSSES
    batches = [entries[i:i + per_img] for i in range(0, len(entries), per_img)]
    for i, batch in enumerate(batches, 1):
        out = os.path.join(OUT_DIR, "audit_bosses_%d.png" % i)
        make_montage(
            batch, out, cols=3,
            title="AUDIT BOSS — frame 0 riga 0 (sheet SD 64px, cella 128px) — batch %d/%d"
                  % (i, len(batches)),
            user_image_entries=1 if i == 1 else 0)


def cmd_crops(specs):
    """Crop dedicati 2x per query VLM su sprite ambigui.
    specs: lista di 'm007' / 'monster_007' / 'boss_027'."""
    for spec in specs:
        sid = spec.strip()
        if sid.startswith("m"):
            sid = "monster_" + sid[1:]
        meta, frames = load_sheet_frames(sid)
        if not frames:
            print("sheet non trovato: %s" % sid)
            continue
        # pannello: riga0 f0..f3 (walk/idle cycle) e, se >1 riga, riga1 f0, riga2 f0
        panels = []
        row0 = frames[0][:4]
        for fr in row0:
            panels.append(("walk/idle", fr))
        if len(frames) > 1:
            panels.append(("attack r1f0", frames[1][0]))
        if len(frames) > 2:
            panels.append(("walk r2f0", frames[2][0]))
        size = 128  # 64 -> 128 (2x, NEAREST)
        pad = 8
        label_h = 18
        W = pad + len(panels) * (size + 10)
        H = pad * 2 + label_h + size + 26
        canvas = Image.new("RGBA", (W, H), BG + (255,))
        d = ImageDraw.Draw(canvas)
        f1 = ImageFont.truetype(FONT_BOLD, 16)
        f2 = ImageFont.truetype(FONT_MONO, 11)
        d.text((pad, 6), "CROP %s (2x)" % sid, font=f1, fill=(240, 240, 255))
        x = pad
        for label, fr in panels:
            draw_sprite_on_tile(canvas, fr, x, pad + 24, size)
            d.rectangle([x, pad + 24, x + size, pad + 24 + size], outline=GRID)
            d.text((x + 2, pad + 26 + size + 2), label, font=f2, fill=SUB_LABEL_COLOR)
            x += size + 10
        out = os.path.join(OUT_DIR, "audit_crop_%s.png" % sid)
        canvas.convert("RGB").save(out, "PNG")
        print("salvato: %s (%d pannelli)" % (out, len(panels)))


def cmd_compare():
    """Confronto diretto USER-IMAGE vs witch nemico (m007) vs witch boss (b027)."""
    size = 128
    pad = 10
    W = pad + 3 * (size + 12) + 10
    H = pad + 24 + size + 30 + 40
    canvas = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(canvas)
    f1 = ImageFont.truetype(FONT_BOLD, 16)
    f2 = ImageFont.truetype(FONT_MONO, 11)
    d.text((pad, 6), "CONFRONTO STREGA: user vs monster_007 vs boss_027", font=f1,
           fill=(240, 240, 255))

    # pannello 1: USER-IMAGE
    x = pad
    img = Image.open(USER_IMG).convert("RGBA")
    w, h = img.size
    scale = max(size // w, size // h)
    nw, nh = w * scale, h * scale
    img = img.resize((nw, nh), Image.NEAREST)
    left = max(0, (nw - size) // 2)
    top = max(0, (nh - size) // 2)
    img = img.crop((left, top, left + size, top + size))
    canvas.paste(img, (x, pad + 24), img)
    d.rectangle([x, pad + 24, x + size, pad + 24 + size], outline=GRID)
    d.text((x + 2, pad + 26), "USER-IMAGE", font=f2, fill=USER_LABEL_COLOR)

    # pannello 2: monster_007 frame 0
    x = pad + (size + 12)
    meta, frames = load_sheet_frames("monster_007")
    if frames and frames[0]:
        draw_sprite_on_tile(canvas, frames[0][0], x, pad + 24, size)
    d.rectangle([x, pad + 24, x + size, pad + 24 + size], outline=GRID)
    d.text((x + 2, pad + 26), "monster_007", font=f2, fill=LABEL_COLOR)
    d.text((x + 2, pad + 28 + size), "WITCH (nemico)", font=f2, fill=SUB_LABEL_COLOR)

    # pannello 3: boss_027 frame 0
    x = pad + 2 * (size + 12)
    meta, frames = load_sheet_frames("boss_027")
    if frames and frames[0]:
        draw_sprite_on_tile(canvas, frames[0][0], x, pad + 24, size)
    d.rectangle([x, pad + 24, x + size, pad + 24 + size], outline=GRID)
    d.text((x + 2, pad + 26), "boss_027", font=f2, fill=LABEL_COLOR)
    d.text((x + 2, pad + 28 + size), "SUPREME WITCH (boss)", font=f2, fill=SUB_LABEL_COLOR)

    out = os.path.join(OUT_DIR, "audit_compare_witch.png")
    canvas.convert("RGB").save(out, "PNG")
    print("salvato: %s" % out)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return
    cmd = args[0]
    if cmd == "enemies":
        cmd_enemies()
    elif cmd == "bosses":
        cmd_bosses()
    elif cmd == "compare":
        cmd_compare()
    elif cmd == "crops":
        if len(args) < 2:
            print("uso: audit_sprites_montage.py crops m007,boss_027,...")
            return
        cmd_crops(args[1].split(","))
    elif cmd == "all":
        cmd_enemies()
        cmd_bosses()
    else:
        print("comando sconosciuto: %s" % cmd)


if __name__ == "__main__":
    main()
