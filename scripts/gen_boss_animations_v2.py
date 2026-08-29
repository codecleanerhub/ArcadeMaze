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
     ["Rotate both arms forward by exactly 20 degrees, ONLY the arms rotate. The body, head, legs, eyes, AND canvas size MUST remain IDENTICAL to the input image. Do NOT zoom, do NOT scale, do NOT resize the character. Keep identical position, identical size, identical colors. The character bounding box MUST NOT change.",
      "Rotate both arms forward to exactly 45 degrees from the body, ONLY the arms rotate. The body, head, legs, eyes, AND canvas size MUST remain IDENTICAL. Do NOT zoom, do NOT scale, do NOT resize. Keep identical position, identical size, identical colors.",
      "Rotate both arms back to 20 degrees forward, ONLY the arms rotate. The body, head, legs, eyes, AND canvas size MUST remain IDENTICAL. Do NOT zoom, do NOT scale, do NOT resize. Keep identical position, identical size, identical colors."]),

    ("boss_032", "Lich Necromancer",
     "Pixel art sprite of a lich necromancer boss, floating skeletal mage with purple hooded robe, glowing purple eye sockets in skull face, ornate staff held vertical, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark",
     ["Tilt ONLY the staff to the right by 15 degrees at the top. The torso, robe, hood, skull, eyes, body shape, body color, body position, AND canvas size MUST remain PIXEL-IDENTICAL to the input image. Do NOT change the torso color. Do NOT change the robe drawing. Do NOT redraw the character. Only rotate the staff.",
      "Tilt ONLY the staff further to the right by 30 degrees at the top. The torso, robe, hood, skull, eyes, body shape, body color, body position, AND canvas size MUST remain PIXEL-IDENTICAL to the input image. Do NOT change the torso color. Do NOT redraw the character. Only rotate the staff.",
      "Return ONLY the staff to vertical. The torso, robe, hood, skull, eyes, body shape, body color, body position, AND canvas size MUST remain PIXEL-IDENTICAL to the input image. Do NOT change anything except the staff angle."]),

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
     ["Extend ONLY four tentacles outward to half length. The central body (head with eye and beak) MUST remain PIXEL-IDENTICAL to the input image: same size, same position, same color, same shape. Do NOT zoom, do NOT scale, do NOT resize, do NOT move the body. The character overall bounding box may grow only because tentacles extend, but the body stays fixed.",
      "Extend ALL eight tentacles fully wide spread outward. The central body (head with eye and beak) MUST remain PIXEL-IDENTICAL to the input image: same size, same position, same color, same shape. Do NOT zoom, do NOT scale, do NOT resize, do NOT move the body.",
      "Curl tentacles back inward to half extended. The central body (head with eye and beak) MUST remain PIXEL-IDENTICAL to the input image: same size, same position, same color, same shape. Do NOT zoom, do NOT scale, do NOT resize, do NOT move the body."]),

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


def process_frame(raw_path, target_height=None):
    """
    Processa un raw 1024x1024 -> 64x64 RGBA.

    NUOVO APPROCCIO PER EVITARE L'EFFETTO ZOOM:
    Invece di usare un target_bbox fisso (che causava l'effetto "salto/zoom"
    quando l'AI generava frame con personaggi di dimensioni leggermente
    diverse), usiamo un approccio di SCALA UNIFORME BASATA SULL'ALTEZZA:

    1. Per ogni frame, trova il proprio bbox.
    2. Se target_height e' fornito (riferito all'altezza del frame 0 in px
       del raw 1024), ridimensiona il crop in modo che l'altezza del
       personaggio sia ESATTAMENTE target_height. Questo garantisce che
       tutti i 4 frame abbiano lo stesso ingrandimento del personaggio.
    3. Centra il personaggio sul canvas 64x64 (in base al centroide).

    Per il kraken (che ha tentacoli che si estendono), l'altezza del corpo
    centrale resta costante anche se il bbox totale cresce: in quel caso
    il target_height va calcolato solo sul "core body", non su tutto il
    bbox (vedi funzione find_core_bbox).

    Per gli altri boss (golem, lich) il bbox coincide col corpo, quindi
    target_height = altezza del bbox del frame 0.
    """
    if not raw_path.exists():
        return None, None
    img = Image.open(raw_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]

    # 1) Flood-fill transparency
    bg_mask = flood_fill_transparency(arr)
    arr[bg_mask, 3] = 0

    # 2) Trova bbox del personaggio
    bbox = find_bbox(arr[..., 3])
    if bbox is None:
        return None, None
    rmin, rmax, cmin, cmax = bbox
    body_h = rmax - rmin + 1
    body_w = cmax - cmin + 1

    # 3) Calcola il fattore di scala per uniformare l'altezza
    # Se target_height e' fornito (altezza del frame 0), usa quello.
    # Altrimenti usa body_h di questo frame (sara' lui il riferimento).
    if target_height is None:
        # Frame 0: imposta il riferimento
        target_height = body_h
        target_width_ref = body_w
    else:
        # Frame successivi: imposta l'altezza al riferimento, mantieni
        # l'aspect ratio del frame 0 per la larghezza (per coerenza).
        pass

    # Fattore di scala = target_height / body_h (cosi' il personaggio
    # ha sempre la stessa altezza in pixel raw). Poi applichiamo
    # margine e resize a 64x64.
    scale = float(target_height) / float(body_h) if body_h > 0 else 1.0

    # 4) Crop al bbox + margine. Il margine va calcolato proporzionalmente
    # al target_height, cosi' se il personaggio del frame e' piu' piccolo
    # di quello del frame 0 (es. kraken con tentacoli retratti che risulta
    # con body_h=400 vs target_height=970 del frame 0), il margine sara'
    # proporzionale e il personaggio finale sara' dello stesso ingrandimento.
    # scale = target_height / body_h: se il frame ha personaggio piu'
    # piccolo, scale > 1 -> il crop finale includera' un'area piu' grande
    # attorno al personaggio (margine proporzionale).
    margin_y = int(CROP_MARGIN * scale) if scale > 1.0 else CROP_MARGIN
    margin_x = int(CROP_MARGIN * scale) if scale > 1.0 else CROP_MARGIN
    # Se l'aspect ratio del personaggio e' molto largo (es. drago con
    # ali spiegate), aumentiamo margin_x.
    if body_w > body_h * 1.5:
        margin_x = int(margin_x * 1.5)

    y0 = max(0, rmin - margin_y)
    y1 = min(h, rmax + margin_y + 1)
    x0 = max(0, cmin - margin_x)
    x1 = min(w, cmax + margin_x + 1)
    arr_crop = arr[y0:y1, x0:x1]

    # 5) Fill buchi intra-corpo
    arr_crop = fill_internal_holes(arr_crop)

    # 6) Ridimensiona a canvas 64x64 LANCZOS, con SCALA BASATA SUL
    # target_height (NON sul crop totale). Questo e' il CHIAVE per evitare
    # l'effetto zoom:
    #   - Tutti i 4 frame devono avere il personaggio con la stessa
    #     altezza finale nel canvas 64x64.
    #   - L'altezza del personaggio nel raw 1024 e' body_h.
    #   - Vogliamo che nel canvas 64x64, il personaggio abbia altezza
    #     = target_canvas_h (es. 56px) RAPPRESENTATA NELLE UNITA' DEL
    #     FRAME 0. Cioe': il personaggio del frame 0 ha body_h =
    #     target_height nel raw, e deve diventare ~target_canvas_h nel
    #     canvas. Quindi la scala e': target_canvas_h / target_height.
    #   - Applichiamo la STESSA scala a tutti i 4 frame: questo garantisce
    #     che il personaggio abbia sempre le stesse proporzioni finali.
    crop_h, crop_w = arr_crop.shape[:2]
    target_canvas_w = SPRITE_SIZE - 4  # 60
    target_canvas_h = SPRITE_SIZE - 8  # 56 (lascia spazio sopra per HP bar)
    # Scala uniforme: basata sul target_height (riferimento del frame 0)
    # e NON sul crop locale. Cosi' tutti i frame hanno lo stesso
    # ingrandimento del personaggio.
    final_scale = float(target_canvas_h) / float(target_height)
    new_w = max(1, int(crop_w * final_scale))
    new_h = max(1, int(crop_h * final_scale))

    # Se il personaggio e' troppo largo per il canvas 60, scala in base
    # alla larghezza (mantenendo aspect ratio). Questo puo' capitare per
    # boss molto larghi (es. drago con ali spiegate).
    if new_w > target_canvas_w:
        ratio = float(target_canvas_w) / float(new_w)
        new_w = target_canvas_w
        new_h = max(1, int(new_h * ratio))

    img = Image.fromarray(arr_crop, 'RGBA')
    img = img.resize((new_w, new_h), resample=Image.LANCZOS)
    arr_resized = np.array(img)

    # 7) Centra su canvas 64x64.
    # L'ancora del boss nel codice C++ e' (32, 56): i piedi sono a y=56
    # circa, il top della testa a y=0..8. Allineamo in basso (piedi
    # fissi a y=56) e centrriamo orizzontalmente.
    canvas = np.zeros((SPRITE_SIZE, SPRITE_SIZE, 4), dtype=np.uint8)
    # Piedi a y=56: offset_y in modo che il bottom del personaggio sia a 56
    feet_y = 56
    offset_y = feet_y - new_h
    if offset_y < 0:
        offset_y = 0
    # Se il personaggio e' piu' alto di 56, lo centriamo verticalmente
    # e lo tagliamo (caso raro, solo personaggi molto alti).
    if new_h > feet_y:
        offset_y = 0
    offset_x = (SPRITE_SIZE - new_w) // 2
    if offset_x < 0:
        offset_x = 0
    canvas[offset_y:offset_y + new_h, offset_x:offset_x + new_w] = arr_resized[:min(new_h, SPRITE_SIZE-offset_y), :min(new_w, SPRITE_SIZE-offset_x)]
    arr = canvas

    # 8) Soglia alpha
    alpha = arr[..., 3]
    arr[alpha < 32, 3] = 0
    arr[alpha >= 32, 3] = 255

    # 9) Post-fill micro-buchi
    arr = fill_internal_holes(arr)

    # 10) Applica palette
    arr = apply_palette(arr)
    return arr, target_height


def normalize_frame_sizes(frames):
    """
    Normalizza le dimensioni dei 4 frame per evitare l'effetto zoom/salto.

    PROBLEMA: anche con prompt enfatici, l'AI a volte genera frame con
    personaggi di dimensioni leggermente diverse (es. kraken con tentacoli
    estesi risulta con un corpo centrale piu' piccolo per fare spazio).
    Questo causa l'effetto "salto/zoom" durante l'animazione.

    SOLUZIONE: dopo il processing, calcoliamo l'altezza del bbox di
    ciascun frame. Se un frame ha un'altezza molto diversa dalla media
    (oltre il 25% di differenza), lo ridimensioniamo uniformemente per
    farlo corrispondere all'altezza media. Il ridimensionamento mantiene
    l'aspect ratio e centra il personaggio sul canvas.

    Questo NON risolve il problema alla radice (la AI disegna comunque
    corpi diversi), ma AMMAZZA l'effetto visivo di zoom/salto: il
    personaggio appare stabile nel canvas, le parti mobili si muovono ma
    il corpo centrale resta della stessa dimensione apparente.
    """
    if len(frames) < 2:
        return frames

    # 1) Calcola l'altezza del bbox per ogni frame
    heights = []
    bboxes = []
    for f in frames:
        if f is None:
            heights.append(0)
            bboxes.append(None)
            continue
        alpha = f[..., 3]
        rows = np.any(alpha > 0, axis=1)
        if not rows.any():
            heights.append(0)
            bboxes.append(None)
            continue
        rmin, rmax = np.where(rows)[0][[0, -1]]
        h = rmax - rmin + 1
        heights.append(h)
        bboxes.append((rmin, rmax))

    # 2) Calcola altezza target.
    # Usiamo il VALORE MASSIMO delle altezze come target: questo significa
    # che i frame con personaggio piu' piccolo vengono ingranditi fino a
    # raggiungere le dimensioni del frame piu' grande. L'assunto e' che
    # il frame piu' grande rappresenti il personaggio alla sua dimensione
    # "naturale" (solitamente il frame 0 con posa neutra). Questo e'
    # migliore della mediana perche' i frame difettosi (piu' piccoli) vengono
    # portati alla dimensione corretta, non verso una media che includerebbe
    # il difetto.
    valid_heights = [h for h in heights if h > 0]
    if not valid_heights:
        return frames
    target_h = max(valid_heights)

    # 3) Per ogni frame che differisce dal target per piu' del 10%,
    # ridimensiona uniformemente per farlo corrispondere al target_h.
    new_frames = []
    for i, f in enumerate(frames):
        if f is None or bboxes[i] is None:
            new_frames.append(f)
            continue
        h_i = heights[i]
        if h_i == 0:
            new_frames.append(f)
            continue
        # Differenza percentuale rispetto al target
        diff_pct = abs(h_i - target_h) / float(target_h)
        if diff_pct < 0.10:
            # Gia' coerente, non ridimensionare
            new_frames.append(f)
            continue

        # Ridimensiona: scala = target_h / h_i
        # Se il frame ha personaggio piu' piccolo (h_i < target_h),
        # scala > 1 -> ingrandisce. Se piu' grande, scala < 1 -> rimpicciolisce.
        scale = float(target_h) / float(h_i)
        # Nuove dimensioni del frame (mantenendo 64x64 canvas)
        # Ridimensioniamo solo il contenuto (bbox + piccolo margine), poi
        # ri-centriamo sul canvas 64x64.
        rmin, rmax = bboxes[i]
        # Estrai il bbox + 2px margine (clamped a 0..63)
        sub_rmin = max(0, rmin - 2)
        sub_rmax = min(SPRITE_SIZE - 1, rmax + 2)
        sub_cmin = 0
        sub_cmax = SPRITE_SIZE - 1
        # Trova bbox orizzontale effettivo
        alpha = f[..., 3]
        cols = np.any(alpha > 0, axis=0)
        if cols.any():
            cmin, cmax = np.where(cols)[0][[0, -1]]
            sub_cmin = max(0, cmin - 2)
            sub_cmax = min(SPRITE_SIZE - 1, cmax + 2)

        sub_h = sub_rmax - sub_rmin + 1
        sub_w = sub_cmax - sub_cmin + 1
        # Ridimensiona
        new_w = max(1, int(sub_w * scale))
        new_h = max(1, int(sub_h * scale))
        # Clampa a 64x64
        if new_w > SPRITE_SIZE:
            ratio = float(SPRITE_SIZE) / new_w
            new_w = SPRITE_SIZE
            new_h = max(1, int(new_h * ratio))
        if new_h > SPRITE_SIZE:
            ratio = float(SPRITE_SIZE) / new_h
            new_h = SPRITE_SIZE
            new_w = max(1, int(new_w * ratio))

        sub_arr = f[sub_rmin:sub_rmax + 1, sub_cmin:sub_cmax + 1]
        img = Image.fromarray(sub_arr, 'RGBA')
        img = img.resize((new_w, new_h), resample=Image.LANCZOS)
        arr_resized = np.array(img)

        # Centra su canvas 64x64.
        # Importante: centra VERTICALMENTE in base al centroide del personaggio
        # (NON allineando i piedi a y=56), perche' se il frame e' stato
        # ridimensionato in modo significativo, l'allineamento piedi-a-56
        # causerebbe clipping in alto. Invece, calcoliamo l'offset_y in
        # modo che il centro verticale del personaggio coincida col
        # centro verticale degli altri frame.
        canvas = np.zeros((SPRITE_SIZE, SPRITE_SIZE, 4), dtype=np.uint8)
        if new_h >= SPRITE_SIZE:
            # Personaggio piu' alto del canvas: centra e taglia
            offset_y = 0
            offset_x = (SPRITE_SIZE - new_w) // 2
            if offset_x < 0:
                offset_x = 0
            canvas[:, offset_x:offset_x + new_w] = arr_resized[:SPRITE_SIZE, :min(new_w, SPRITE_SIZE - offset_x)]
        else:
            # Personaggio piu' piccolo del canvas: centra verticalmente
            # usando come riferimento i "piedi" (y=56). Se il ridimensionamento
            # porta il personaggio a essere piu' alto di 56, centra invece
            # in base al centroide.
            feet_y = 56
            if new_h <= feet_y:
                offset_y = feet_y - new_h
            else:
                # Personaggio piu' alto dei piedi: centra verticalmente
                offset_y = (SPRITE_SIZE - new_h) // 2
            offset_x = (SPRITE_SIZE - new_w) // 2
            if offset_x < 0:
                offset_x = 0
            # Copia con clipping sicuro
            copy_h = min(new_h, SPRITE_SIZE - offset_y)
            copy_w = min(new_w, SPRITE_SIZE - offset_x)
            canvas[offset_y:offset_y + copy_h, offset_x:offset_x + copy_w] = \
                arr_resized[:copy_h, :copy_w]
        new_frames.append(canvas)

    return new_frames


def align_frames_to_base(frames):
    """
    Allinea i frame 1, 2, 3 al frame 0 usando il CENTROIDE orizzontale
    dei pixel opachi. Riduce l'effetto "zoppia" dovuto al fatto che l'AI
    genera frame con il corpo leggermente spostato orizzontalmente.

    Strategia:
    1. Calcola il centroide X (media delle coordinate X dei pixel opachi,
       pesata per alpha) per ogni frame.
    2. Per i frame 1, 2, 3: calcola la differenza di centroide rispetto
       al frame 0 e li trasla orizzontalmente per allinearlo.
    3. La traslazione e' limitata a +/- 8 px per non introdurre salti
       eccessivi (limite conservativo).

    NOTA: allinea solo orizzontalmente. L'allineamento verticale e'
    gia' gestito da process_frame (piedi a y=56).
    """
    if len(frames) < 2:
        return frames

    # Calcola centroide X per ogni frame
    centroids = []
    for f in frames:
        if f is None:
            centroids.append(None)
            continue
        alpha = f[..., 3]
        if alpha.sum() == 0:
            centroids.append(None)
            continue
        # Coordinate X di tutti i pixel
        h, w = alpha.shape
        xs = np.arange(w)
        # Somma pesata di X per alpha (colonna per colonna, piu' veloce)
        col_sums = alpha.sum(axis=0).astype(float)  # peso per colonna
        total_weight = col_sums.sum()
        if total_weight == 0:
            centroids.append(None)
            continue
        centroid_x = (xs * col_sums).sum() / total_weight
        centroids.append(centroid_x)

    # Frame 0 e' il riferimento
    if centroids[0] is None:
        return frames
    base_cx = centroids[0]

    new_frames = []
    max_shift = 8  # limit shift to avoid excessive jumps
    for i, f in enumerate(frames):
        if f is None or centroids[i] is None:
            new_frames.append(f)
            continue
        if i == 0:
            new_frames.append(f)
            continue
        # Calcola shift richiesto (positivo = sposta a destra)
        shift = base_cx - centroids[i]
        # Clampa il shift
        if shift > max_shift:
            shift = max_shift
        elif shift < -max_shift:
            shift = -max_shift
        # Round a intero
        shift_int = int(round(shift))
        if shift_int == 0:
            new_frames.append(f)
            continue
        # Applica shift: copia il frame su un canvas nuovo, shiftato
        new_f = np.zeros_like(f)
        h, w = f.shape[:2]
        if shift_int > 0:
            # Sposta a destra: src[0:w-shift] -> dst[shift:w]
            new_f[:, shift_int:w] = f[:, 0:w - shift_int]
        else:
            # Sposta a sinistra: shift_int e' negativo
            abs_shift = -shift_int
            new_f[:, 0:w - abs_shift] = f[:, abs_shift:w]
        new_frames.append(new_f)
    return new_frames


def compose_spritesheet(frames, out_path):
    """Composizione orizzontale: 4 frame 64x64 -> 256x64.

    Pipeline di post-processing applicata in ordine:
    1. normalize_frame_sizes: ridimensiona frame anomali per evitare
       effetto zoom/salto.
    2. align_frames_to_base: allinea orizzontalmente i centroidi dei
       frame 1/2/3 al frame 0, riducendo l'effetto "zoppia".
    """
    # 1. Normalizza dimensioni frame
    frames = normalize_frame_sizes(frames)
    # 2. Allinea centroidi orizzontali (riduce zoppia)
    frames = align_frames_to_base(frames)

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

    # --- 2. Processa frame base per trovare l'altezza di riferimento ---
    print(f"  Frame 0: post-processing per trovare altezza riferimento...")
    frame0, target_height = process_frame(base_raw_path)
    if frame0 is None:
        print(f"  [ERROR] Post-processing frame 0 fallito")
        return False
    print(f"     Altezza di riferimento (raw 1024): {target_height}px")

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
            # Il prompt rafforza MASSIMAMENTE la coerenza: il personaggio
            # deve restare IDENTICO in posizione, dimensione, colori e stile.
            # Solo le parti mobili specificate devono cambiare.
            full_prompt = (
                f"{edit_prompt}. "
                f"CRITICAL CONSTRAINTS: the character MUST remain PIXEL-IDENTICAL "
                f"to the input image in: body shape, body size, body position in "
                f"canvas, body colors, body proportions, art style, and pixel art "
                f"outlines. Do NOT zoom, do NOT scale, do NOT resize, do NOT move "
                f"the body, do NOT change body colors, do NOT redraw the character. "
                f"ONLY the explicitly specified moving parts (arms/wings/tentacles/"
                f"staff/cloak) should change. Maintain solid flat pure black "
                f"RGB(0,0,0) background."
            )
            if not edit_image(full_prompt, base_raw_path, edit_raw_path):
                print(f"  [WARN] Edit fallito per frame {i}, uso frame 0 come fallback")
                # Fallback: duplica frame 0
                frames.append(frame0.copy())
                continue

        # Processa usando la stessa altezza di riferimento del frame 0
        # per evitare l'effetto zoom (tutti i 4 frame ridimensionati
        # in modo che il personaggio abbia la stessa altezza finale).
        print(f"  Frame {i}: post-processing (stessa altezza del frame 0)...")
        frame_i, _ = process_frame(edit_raw_path, target_height=target_height)
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
