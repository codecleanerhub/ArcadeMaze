#!/usr/bin/env python3
"""
gen_boss_animations_v2.py - Genera animazioni di 4 frame coerenti per i 17
boss usando 1 generate + 3 image-edit per garantire coerenza visiva.

PROBLEMA DELL'APPROCCIO V1:
Generare 4 immagini separate con AI produce 4 personaggi DIVERSI (posa,
stile, dimensioni, proporzioni) - effetto "gatto-cane-topo" invece di
un'animazione fluida.

SOLUZIONE V2 (questa):
1. Per ogni boss, genera UN'immagine base 1024x1024 (posa neutra) con z-ai image
2. Crea 3 varianti con z-ai image-edit: l'AI parte dall'immagine base e
   applica solo la modifica richiesta (es. "alza le ali di 45 gradi,
   mantieni identico il resto del corpo"), garantendo coerenza totale
3. Processa i 4 frame (1 base + 3 editati) -> 4 frame 64x64 coerenti
4. Composizione orizzontale -> spritesheet 256x64
5. Aggiornamento meta.json: columns=4, rows=1, idle.frames=4

Questo approccio garantisce che il personaggio sia IDENTICO in tutti i 4
frame, con solo le parti mobili (ali, braccia, tentacoli, ecc.) che
cambiano leggermente per creare un loop di animazione fluido.
"""
import os
import json
import sys
import subprocess
import time
from pathlib import Path
from PIL import Image
import numpy as np
from collections import deque
import concurrent.futures

# --- Config ---
RAW_DIR = Path("/tmp/boss_anim_v2")
SPRITES_DIR = Path("/home/z/my-project/ArcadeMaze/assets/sprites")
SPRITE_SIZE = 64
RAW_SIZE = "1024x1024"
CROP_MARGIN = 12
TOL = 28
N_FRAMES = 4

# Palette 16 colori
PALETTE = [
    (12, 12, 12),   (48, 40, 36),   (96, 80, 72),   (160, 128, 112),
    (200, 180, 160), (120, 140, 160), (80, 120, 100),  (40, 80, 60),
    (160, 40, 40),  (200, 80, 80),  (220, 160, 40),  (200, 200, 80),
    (120, 200, 200), (80, 160, 220), (160, 120, 200), (240, 240, 240)
]

# --- Definizione dei 17 boss ---
# Per ogni boss: (sprite_id, nome, descrizione base per generate, lista di
# 3 modifiche per image-edit).
# Frame 0 = base (posa neutra), Frame 1/2/3 = edit dal frame 0.
BOSSES = [
    ("boss_031", "Stone Golem",
     "Pixel art sprite of a massive stone golem boss, bulky rectangular body made of grey stone blocks, glowing green eyes in carved eye sockets, thick arms hanging at sides, no legs, gothic fantasy D&D style, 16-color palette, side view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, only empty background around the character is transparent, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Slightly raise both arms forward to 20 degrees, keep body and head identical",
      "Raise both arms forward to 45 degrees, keep body and head identical",
      "Lower both arms back to 20 degrees forward, keep body and head identical"]),

    ("boss_032", "Lich Necromancer",
     "Pixel art sprite of a lich necromancer boss, floating skeletal mage with purple hooded robe, glowing purple eye sockets in skull face, ornate staff held vertical, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Tilt the staff slightly to the right at 15 degrees and sway the robe gently to the right, keep body and face identical",
      "Tilt the staff more to the right at 30 degrees and sway the robe further to the right, keep body and face identical",
      "Return the staff to vertical and return the robe to center, keep body and face identical"]),

    ("boss_033", "Abyssal Demon",
     "Pixel art sprite of an abyssal demon boss, muscular red-skinned humanoid with massive bat wings folded at rest against the body, curved black horns, glowing yellow eyes, sharp claws, arms at sides, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Spread the bat wings out to half extended at 45 degrees and raise arms slightly, keep body and face identical",
      "Spread the bat wings fully wide open at 90 degrees and raise arms more, keep body and face identical",
      "Fold the bat wings back to half extended at 45 degrees and lower arms slightly, keep body and face identical"]),

    ("boss_022", "Giant Spider",
     "Pixel art sprite of a giant spider boss, enormous black arachnid with red eye cluster, eight long hairy legs bent inward resting position, fangs dripping venom, gothic fantasy D&D style, 16-color palette, top-down 45 degree view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Extend the front four legs forward and raise the body slightly, keep all other legs identical",
      "Spread all eight legs wide and raise the body high aggressive pose, keep body identical",
      "Return the front four legs to half extended inward and lower the body slightly, keep all other legs identical"]),

    ("boss_034", "Abomination",
     "Pixel art sprite of an abomination boss, hulking undead flesh golem with mismatched body parts, exposed bones, stitches, one large right arm and one small left arm both hanging at sides, glowing yellow eyes, head bowed hunched posture, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Raise the large right arm forward to 30 degrees and turn head slightly right, keep body and left arm identical",
      "Raise the large right arm to 90 degrees sideways and turn head further right, keep body and left arm identical",
      "Lower the large right arm back to 30 degrees and return head toward forward, keep body and left arm identical"]),

    ("boss_030", "Kraken",
     "Pixel art sprite of a kraken boss, colossal purple cephalopod with eight long tentacles curled inward close to body, massive yellow eye, sharp beak, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Extend four tentacles outward to half length and raise body slightly, keep eye and beak identical",
      "Extend all eight tentacles fully wide spread and raise body high, keep eye and beak identical",
      "Curl tentacles back inward to half extended and lower body slightly, keep eye and beak identical"]),

    ("boss_035", "Ancient Dragon",
     "Pixel art sprite of an ancient skeletal dragon boss, massive body with rich red crimson scales on lower half, dark grey bone structure on upper body, large leathery red wings folded at rest against back, long tail hanging straight down, sharp horns, glowing red eye, gothic fantasy D&D style, 16-color palette, side profile view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Spread the wings up to 45 degrees and raise the tail slightly, keep body and head identical",
      "Spread the wings fully up at 90 degrees above body and raise the tail high, keep body and head identical",
      "Lower the wings back to 45 degrees and lower the tail back, keep body and head identical"]),

    ("boss_036", "Wraith Lord",
     "Pixel art sprite of a wraith lord boss, ghostly undead king in tattered dark cloak hanging straight down, no legs visible below cloak, glowing cyan eyes, holding ethereal sword vertical, hovering still, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Billow the cloak gently to the right and tilt the sword to the right at 15 degrees, keep body and face identical",
      "Billow the cloak strongly to the right and swing the sword to the right at 30 degrees, keep body and face identical",
      "Return the cloak to center and return the sword to vertical, keep body and face identical"]),

    ("boss_029", "Vampire Lord",
     "Pixel art sprite of a vampire lord boss, elegant aristocratic vampire in black and red cape hanging straight behind, pale skin, red glowing eyes, sharp fangs, slicked black hair, arms at sides, standing tall, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Billow the cape slightly to the right and raise the right arm forward at 20 degrees, keep body and face identical",
      "Billow the cape strongly to the right and raise the right arm forward at 45 degrees with claw extended, keep body and face identical",
      "Return the cape to center and lower the right arm back to 20 degrees, keep body and face identical"]),

    ("boss_037", "Beholder",
     "Pixel art sprite of a beholder boss, large floating central eyeball with massive purple iris, ten smaller eyes on long stalks curled inward close to central body, central eye open, sharp teeth below, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Extend five eye stalks outward to half length, keep central eye and teeth identical",
      "Extend all ten eye stalks fully wide spread and open central eye wider, keep teeth identical",
      "Curl eye stalks back inward to half extended and return central eye to normal, keep teeth identical"]),

    ("boss_021", "Ghoul Lord",
     "Pixel art sprite of a ghoul lord boss, hulking undead humanoid with sickly pale green-grey decaying flesh, exposed ribcage, long powerful arms with sharp bone claws hanging at sides, tattered dark rags at waist, glowing green eyes, head facing forward hunched posture, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Raise the right arm forward to 30 degrees with claws extended and tilt head slightly, keep body and left arm identical",
      "Raise the right arm forward to 90 degrees with claws fully extended and turn head further, keep body and left arm identical",
      "Lower the right arm back to 30 degrees and return head toward forward, keep body and left arm identical"]),

    ("boss_023", "Spectral Alpha Wolf",
     "Pixel art sprite of a spectral alpha wolf boss, large ghostly wolf with smoky cyan-blue translucent fur, glowing cyan eyes, sharp fangs, standing alert with head up, tail hanging down, ears forward, gothic fantasy D&D style, 16-color palette, side profile view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps (spectral mist ok around edges), solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Lower the head slightly, raise the tail, and fold ears back, keep body and legs identical",
      "Lower the head further in mid crouch, raise the tail high, and flatten ears back, keep body and legs identical",
      "Raise the head back up, lower the tail, and return ears forward, keep body and legs identical"]),

    ("boss_024", "Cult Herald",
     "Pixel art sprite of a cult herald boss, hooded figure in ornate crimson and gold robes hanging straight down, holding ritual dagger low at side, no visible face inside hood only darkness, hovering still, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Sway the robe gently to the right and raise the dagger to chest height, keep body and hood identical",
      "Billow the robe strongly to the right and raise the dagger high above head, keep body and hood identical",
      "Return the robe to center and lower the dagger back to chest height, keep body and hood identical"]),

    ("boss_025", "Colossal Mimic",
     "Pixel art sprite of a colossal mimic boss, massive treasure chest body with huge gaping maw closed showing teeth, long prehensile tongue inside, treasure spilling out, large clawed feet, lid at rest, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Open the mouth slightly, extend the tongue out partially, and raise the lid slightly, keep body and feet identical",
      "Open the mouth wide open, extend the tongue fully out lashing, and raise the lid high, keep body and feet identical",
      "Close the mouth back to slightly open, retract the tongue partially, and lower the lid back, keep body and feet identical"]),

    ("boss_026", "Rat King",
     "Pixel art sprite of a rat king boss, massive bloated rat with multiple smaller rat heads growing from body all looking forward, matted brown fur, yellow eyes, long pink tail, body at rest, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Turn two rat heads to the left and shift the body slightly left, keep all other rat heads identical",
      "Turn all rat heads aggressively to the left and lurch the body further left, keep main body identical",
      "Return rat heads to forward and return body to center, keep body identical"]),

    ("boss_027", "Supreme Witch",
     "Pixel art sprite of a supreme witch boss, hunched old woman in tattered black and purple robes hanging straight down, pointed hat, glowing green eyes, holding crooked staff with crystal vertical, potion vials at belt, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Sway the robe to the right, tilt the staff to the right at 20 degrees, and tilt the hat slightly right, keep body and face identical",
      "Billow the robe strongly to the right, swing the staff to the right at 40 degrees, and tilt the hat further right, keep body and face identical",
      "Return the robe to center, return the staff to vertical, and return the hat to center, keep body and face identical"]),

    ("boss_028", "Twilight Knight",
     "Pixel art sprite of a twilight knight boss, armored dark knight in black plate armor with purple twilight glow, visored helm with glowing purple eyes, holding massive greatsword vertical in front, tattered black cloak hanging straight down, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Sway the cloak to the right, tilt the greatsword to the right at 15 degrees, and turn body slightly right, keep armor and helm identical",
      "Billow the cloak strongly to the right, swing the greatsword to the right horizontal at 90 degrees, and turn body further right, keep armor and helm identical",
      "Return the cloak to center, return the greatsword to vertical, and return body to forward, keep armor and helm identical"]),
]


# ============================================================================
# FUNZIONI AI
# ============================================================================

def generate_base_image(prompt, output_path, timeout=300, max_retries=2):
    """Genera l'immagine base 1024x1024 con z-ai image."""
    cmd = ["z-ai", "image", "-p", prompt, "-o", str(output_path), "-s", RAW_SIZE]
    for attempt in range(max_retries):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            if result.returncode == 0 and output_path.exists():
                return True
            if attempt < max_retries - 1:
                time.sleep(3)
        except subprocess.TimeoutExpired:
            print(f"      TIMEOUT (tentativo {attempt+1}/{max_retries})")
            if attempt < max_retries - 1:
                time.sleep(5)
        except Exception as e:
            print(f"      ERROR: {e}")
            return False
    return False


# Percorso dello script Node helper per image-edit (la CLI z-ai non
# supporta data URL lunghi via command line, quindi usiamo direttamente
# lo SDK Node che accetta data URL come parametro).
#
# NOTA: questo script helper Node deve essere creato manualmente se si
# vuole rigenerare gli sprite. Contenuto minimo:
#   const ZAI = require('z-ai-web-dev-sdk').default;
#   const fs = require('fs');
#   async function main() {
#     const [inPath, outPath, prompt] = process.argv.slice(2);
#     const buf = fs.readFileSync(inPath);
#     const dataUrl = `data:image/png;base64,${buf.toString('base64')}`;
#     const zai = await ZAI.create();
#     const resp = await zai.images.generations.edit({
#       prompt, images: [{ url: dataUrl }], size: '1024x1024'
#     });
#     fs.writeFileSync(outPath, Buffer.from(resp.data[0].base64, 'base64'));
#   }
#   main().catch(e => { console.error(e); process.exit(1); });
# Salvarlo in una directory dove e' disponibile z-ai-web-dev-sdk, es:
#   /home/z/.bun/install/global/node_modules/edit_one.js
# (lo script deve essere eseguito da quella directory per risolvere il require)
NODE_EDIT_SCRIPT = "/home/z/.bun/install/global/node_modules/edit_one.js"


def edit_image(prompt, input_path, output_path, timeout=300, max_retries=2):
    """
    Modifica un'immagine esistente con z-ai image-edit via Node SDK.
    L'AI parte dall'immagine di input e applica SOLO la modifica richiesta,
    mantenendo identico il resto (garanzia di coerenza visiva).

    Usa uno script Node helper perché la CLI z-ai non supporta data URL
    lunghi (>130KB) via command line ("Argument list too long"). Lo script
    Node legge il file, lo converte in base64 data URL, e chiama lo SDK.
    """
    cmd = ["node", NODE_EDIT_SCRIPT,
           str(input_path),
           str(output_path),
           prompt]
    for attempt in range(max_retries):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            if result.returncode == 0 and output_path.exists():
                return True
            # Log dell'errore per debug
            if attempt == 0:
                err = (result.stderr or "")[:200]
                print(f"      edit fail: {err}")
            if attempt < max_retries - 1:
                time.sleep(3)
        except subprocess.TimeoutExpired:
            print(f"      TIMEOUT (tentativo {attempt+1}/{max_retries})")
            if attempt < max_retries - 1:
                time.sleep(5)
        except Exception as e:
            print(f"      ERROR: {e}")
            return False
    return False


# ============================================================================
# FUNZIONI DI POST-PROCESSING IMMAGINI
# ============================================================================

def flood_fill_transparency(arr):
    """Marca come trasparenti i pixel di sfondo connessi al bordo."""
    h, w = arr.shape[:2]
    rgb = arr[..., :3].astype(int)
    corners = [rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]]
    dist_to_corners = np.stack([np.sum((rgb - c) ** 2, axis=2) for c in corners], axis=0)
    min_dist = dist_to_corners.min(axis=0)
    is_bg_candidate = min_dist < TOL ** 2

    visited = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        for y in [0, h - 1]:
            if is_bg_candidate[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in [0, w - 1]:
            if is_bg_candidate[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and is_bg_candidate[ny, nx]:
                visited[ny, nx] = True
                queue.append((ny, nx))
    return visited


def find_bbox(alpha):
    rows = np.any(alpha > 0, axis=1)
    cols = np.any(alpha > 0, axis=0)
    if not rows.any() or not cols.any():
        return None
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    return int(rmin), int(rmax), int(cmin), int(cmax)


def fill_internal_holes(rgba):
    """Riempie i buchi intra-corpo."""
    h, w = rgba.shape[:2]
    alpha = rgba[..., 3]
    transparent_mask = (alpha == 0)

    visited = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        for y in [0, h - 1]:
            if transparent_mask[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in [0, w - 1]:
            if transparent_mask[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and transparent_mask[ny, nx]:
                visited[ny, nx] = True
                queue.append((ny, nx))

    holes = transparent_mask & (~visited)
    if holes.sum() == 0:
        return rgba

    rgb = rgba[..., :3].astype(int).copy()
    filled_alpha = alpha.copy()
    ys, xs = np.where(holes)
    for y, x in zip(ys, xs):
        for r in range(1, 12):
            y0 = max(0, y - r); y1 = min(h, y + r + 1)
            x0 = max(0, x - r); x1 = min(w, x + r + 1)
            neighborhood_alpha = alpha[y0:y1, x0:x1]
            neighborhood_rgb = rgb[y0:y1, x0:x1]
            mask = neighborhood_alpha > 0
            if mask.sum() > 0:
                rgb[y, x] = neighborhood_rgb[mask].mean(axis=0).astype(int)
                filled_alpha[y, x] = 255
                break
    return np.dstack([rgb, filled_alpha]).astype(np.uint8)


def apply_palette(rgba):
    arr = rgba
    alpha = arr[..., 3]
    rgb = arr[..., :3].reshape(-1, 3).astype(int)
    rgb[alpha.reshape(-1) == 0] = [0, 0, 0]
    palette_arr = np.array(PALETTE)
    dists = np.sum((rgb[:, None, :] - palette_arr[None, :, :]) ** 2, axis=2)
    idxs = np.argmin(dists, axis=1)
    new_rgb = palette_arr[idxs].reshape(arr.shape[0], arr.shape[1], 3)
    return np.dstack([new_rgb, alpha]).astype(np.uint8)


def process_frame(raw_path, target_bbox=None):
    """
    Processa un raw 1024x1024 -> 64x64 RGBA.
    Se target_bbox e' fornito (rmin, rmax, cmin, cmax in coordinate 1024),
    ritaglia esattamente a quel bbox (per allineare i 4 frame).
    Altrimenti ritaglia al bbox del personaggio corrente.
    """
    if not raw_path.exists():
        return None, None
    img = Image.open(raw_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]

    # 1) Flood-fill transparency
    bg_mask = flood_fill_transparency(arr)
    arr[bg_mask, 3] = 0

    # 2) Trova bbox (o usa quello fornito per allineamento)
    if target_bbox is not None:
        rmin, rmax, cmin, cmax = target_bbox
    else:
        bbox = find_bbox(arr[..., 3])
        if bbox is None:
            return None, None
        rmin, rmax, cmin, cmax = bbox
        # Salva il bbox come riferimento per i frame successivi
        target_bbox = (rmin, rmax, cmin, cmax)

    # 3) Crop al bbox + margine
    y0 = max(0, rmin - CROP_MARGIN)
    y1 = min(h, rmax + CROP_MARGIN + 1)
    x0 = max(0, cmin - CROP_MARGIN)
    x1 = min(w, cmax + CROP_MARGIN + 1)
    arr = arr[y0:y1, x0:x1]

    # 4) Fill buchi intra-corpo
    arr = fill_internal_holes(arr)

    # 5) Resize a 64x64 LANCZOS
    img = Image.fromarray(arr, 'RGBA')
    img = img.resize((SPRITE_SIZE, SPRITE_SIZE), resample=Image.LANCZOS)
    arr = np.array(img)

    # 6) Soglia alpha
    alpha = arr[..., 3]
    arr[alpha < 32, 3] = 0
    arr[alpha >= 32, 3] = 255

    # 7) Post-fill micro-buchi
    arr = fill_internal_holes(arr)

    # 8) Applica palette
    arr = apply_palette(arr)
    return arr, target_bbox


def compose_spritesheet(frames, out_path):
    """Composizione orizzontale: 4 frame 64x64 -> 256x64."""
    sheet = np.zeros((SPRITE_SIZE, SPRITE_SIZE * N_FRAMES, 4), dtype=np.uint8)
    for i, frame in enumerate(frames):
        if frame is not None:
            sheet[:, i * SPRITE_SIZE:(i + 1) * SPRITE_SIZE] = frame
    img = Image.fromarray(sheet, 'RGBA')
    img.save(out_path)
    return sheet


def write_meta(creature_id):
    """Scrive il meta.json per spritesheet 4-frame orizzontale."""
    meta = {
        "image": f"{creature_id}_sheet.png",
        "frameWidth": SPRITE_SIZE,
        "frameHeight": SPRITE_SIZE,
        "columns": N_FRAMES,
        "rows": 1,
        "anchor": {"x": 32, "y": 56},
        "animations": {
            "idle":   {"row": 0, "frames": N_FRAMES, "frameDuration": 180},
            "walk":   {"row": 0, "frames": N_FRAMES, "frameDuration": 120},
            "attack": {"row": 0, "frames": N_FRAMES, "frameDuration": 90},
            "death":  {"row": 0, "frames": 1, "frameDuration": 120}
        }
    }
    meta_path = SPRITES_DIR / f"{creature_id}_meta.json"
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)


# ============================================================================
# PIPELINE PRINCIPALE PER BOSS
# ============================================================================

def process_boss(boss_def):
    """
    Per ogni boss:
    1. Genera il frame base (posa neutra) con z-ai image
    2. Trova il bbox del personaggio nel frame base
    3. Genera 3 varianti con z-ai image-edit DAL frame base
    4. Processa tutti e 4 i frame usando lo stesso bbox (allineamento)
    5. Componi spritesheet 256x64
    6. Salva meta.json
    """
    sprite_id, name, base_prompt, edit_prompts = boss_def
    print(f"\n[Boss] {sprite_id} ({name})")

    # --- 1. Genera frame base ---
    base_raw_path = RAW_DIR / f"{sprite_id}_frame0_raw.png"
    if base_raw_path.exists():
        print(f"  Frame 0 (base): gia' esistente, skip generate")
    else:
        print(f"  Frame 0 (base): generazione AI...")
        if not generate_base_image(base_prompt, base_raw_path):
            print(f"  [ERROR] Generazione base fallita per {sprite_id}")
            return False

    # --- 2. Processa frame base per trovare il bbox ---
    print(f"  Frame 0: post-processing per trovare bbox...")
    frame0, target_bbox = process_frame(base_raw_path)
    if frame0 is None:
        print(f"  [ERROR] Post-processing frame 0 fallito")
        return False
    print(f"     BBox rilevato: y={target_bbox[0]}..{target_bbox[1]}, x={target_bbox[2]}..{target_bbox[3]}")

    # --- 3. Genera 3 varianti con image-edit ---
    # Ogni edit parte dal frame base (NON dal frame precedente) per
    # massimizzare la coerenza con il personaggio originale.
    frames = [frame0]
    for i, edit_prompt in enumerate(edit_prompts, start=1):
        edit_raw_path = RAW_DIR / f"{sprite_id}_frame{i}_raw.png"
        if edit_raw_path.exists():
            print(f"  Frame {i}: gia' esistente, skip edit")
        else:
            print(f"  Frame {i}: image-edit AI dal frame 0...")
            # Il prompt enffatizza il mantenimento dell'identita'
            full_prompt = (
                f"{edit_prompt}. "
                f"MUST keep the character identical in style, proportions, "
                f"colors, position in canvas. ONLY the specified parts move. "
                f"Maintain solid flat pure black RGB(0,0,0) background."
            )
            if not edit_image(full_prompt, base_raw_path, edit_raw_path):
                print(f"  [WARN] Edit fallito per frame {i}, uso frame 0 come fallback")
                # Fallback: duplica frame 0
                frames.append(frame0.copy())
                continue

        # Processa usando lo stesso bbox del frame 0 per allineamento
        print(f"  Frame {i}: post-processing (stesso bbox del frame 0)...")
        frame_i, _ = process_frame(edit_raw_path, target_bbox=target_bbox)
        if frame_i is None:
            print(f"  [WARN] Post-processing frame {i} fallito, uso frame 0")
            frames.append(frame0.copy())
        else:
            frames.append(frame_i)

    # --- 4. Composizione spritesheet ---
    out_path = SPRITES_DIR / f"{sprite_id}_sheet.png"
    sheet = compose_spritesheet(frames, out_path)

    # Statistiche
    transparent = int(np.sum(sheet[..., 3] == 0))
    total = sheet.shape[0] * sheet.shape[1]
    print(f"  [OK] {out_path.name}: {out_path.stat().st_size} bytes, "
          f"trasparenti={transparent}/{total} ({transparent/total*100:.1f}%)")

    # --- 5. Meta JSON ---
    write_meta(sprite_id)
    print(f"  [OK] meta.json aggiornato (columns={N_FRAMES}, idle.frames={N_FRAMES})")
    return True


def main():
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    SPRITES_DIR.mkdir(parents=True, exist_ok=True)

    only_id = None
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        only_id = sys.argv[2]

    print("=" * 70)
    print(f"GEN BOSS ANIMATIONS V2 - 1 base + 3 edit per coerenza")
    print(f"Total: {len(BOSSES)} boss x 4 frame = {len(BOSSES) * N_FRAMES} immagini")
    print("=" * 70)

    ok = 0
    failed = []
    for boss_def in BOSSES:
        if only_id and boss_def[0] != only_id:
            continue
        try:
            if process_boss(boss_def):
                ok += 1
            else:
                failed.append(boss_def[0])
        except Exception as e:
            print(f"  [EXCEPTION] {boss_def[0]}: {e}")
            failed.append(boss_def[0])

    print("\n" + "=" * 70)
    print(f"Riepilogo: {ok}/{len(BOSSES) if not only_id else 1} boss completati")
    if failed:
        print(f"Falliti: {', '.join(failed)}")
    print("=" * 70)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
