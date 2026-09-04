#!/usr/bin/env python3
"""
gen_deterministic_walk.py - Genera animazioni di camminata a 4 frame
applicando TRASFORMAZIONI DETERMINISTICHE a una singola immagine base AI.

PROBLEMA DELL'APPROCCIO PRECEDENTE (4 frame AI separati):
Anche usando image-edit, l'AI ridisegna il personaggio in ogni frame.
Solo il 20-40% dei pixel e' identico tra frame consecutivi, causando
l'effetto 'gif con immagini disconnesse' / zoppia.

NUOVA STRATEGIA:
1. Per ogni entita', genera UN solo sprite base (posa neutra) con AI.
2. Crea i 3 frame animati applicando TRASFORMAZIONI DETERMINISTICHE
   in Python alla meta' inferiore dello sprite:
   - Frame 0: posa neutra (input)
   - Frame 1: gambe sinistra sollevata di 2px + corpo abbassato 1px
   - Frame 2: posa neutra + corpo sollevato 1px (passo di transizione)
   - Frame 3: gambe destra sollevata di 2px + corpo abbassato 1px
3. Il corpo (parte superiore y < 40) resta IDENTICO in tutti i 4 frame.
   Solo la meta' inferiore (gambe, y >= 40) cambia leggermente.
4. Componi spritesheet 256x64 e aggiorna meta.json.

VANTAGGI:
- 100% coerenza visiva (stesso personaggio in tutti i frame)
- 1 sola chiamata AI per entita' (invece di 4) = 4x piu' veloce
- Niente zoppia, niente gif disconnesse
- Effetto camminata realistico: bob verticale + gambe alternate
"""
import os
import sys
import json
import subprocess
import time
from pathlib import Path
from PIL import Image
import numpy as np

# Importa funzioni utility dallo script dei boss
sys.path.insert(0, '/home/z/my-project/ArcadeMaze/scripts')
from gen_boss_animations_v2 import (
    RAW_DIR, SPRITES_DIR, SPRITE_SIZE, N_FRAMES,
    PALETTE, TOL, CROP_MARGIN,
    flood_fill_transparency, find_bbox, fill_internal_holes, apply_palette
)

WALK_RAW_DIR = Path("/tmp/walk_deterministic")
WALK_RAW_DIR.mkdir(parents=True, exist_ok=True)

# Limite della parte "corpo" (sopra questa y e' corpo, sotto sono gambe)
BODY_Y_THRESHOLD = 40  # in pixel nel canvas 64x64

# === DEFINIZIONE ENTITA === (riprende gli stessi prompt del precedente script,
# ma ora servono SOLO per generare il frame base neutro)
# IMPORTANTE: i player sono SIDE-VIEW (right-facing profile) cosicche' il flip
# orizzontale (quando vanno a sinistra) sia visibile. I nemici possono restare
# front-view perche' non hanno direzione di sguardo rilevante.
PLAYERS = [
    ("player1", "Pixel art sprite of a male archaeologist adventurer, short brown hair, khaki shirt with rolled-up sleeves, brown leather vest, brown trousers, leather boots, khaki fedora hat, no weapons hands empty at sides, standing in RIGHT-FACING SIDE PROFILE view (character looks to the right), full body visible from the side, both feet on ground, realistic adventurer style NOT fantasy, 16-color palette, side profile view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("player2", "Pixel art sprite of a female blonde archaeologist adventurer, long blonde hair flowing behind, khaki shirt with rolled-up sleeves, brown leather vest, brown trousers, leather boots, no weapons hands empty at sides, standing in RIGHT-FACING SIDE PROFILE view (character looks to the right), full body visible from the side, both feet on ground, realistic adventurer style NOT fantasy, 16-color palette, side profile view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_mage", "Pixel art sprite of a wizard mage character, long blue robe with stars, pointed hat, white beard, hands empty at sides, standing in RIGHT-FACING SIDE PROFILE view (character looks to the right), full body visible from the side, both feet on ground, gothic fantasy D&D style, 16-color palette, side profile view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_orc", "Pixel art sprite of a green orc warrior standing in RIGHT-FACING SIDE PROFILE view (character looks to the right). The orc has muscular green upper body with two tusks from the lower jaw, wearing a brown loincloth. The orc has TWO LONG SEPARATED LEGS clearly distinct from each other, with thighs, knees, calves and feet visible. The legs must be about 40 percent of the total body height. The body shape must show a clear separation between torso (top half) and legs (bottom half), not a single thick column. Gothic fantasy D&D style, 16-color palette, side profile view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_elf", "Pixel art sprite of an elf ranger, pointed ears, green hooded cloak, leather armor, hands empty at sides, standing in RIGHT-FACING SIDE PROFILE view (character looks to the right), full body visible from the side, both feet on ground, gothic fantasy D&D style, 16-color palette, side profile view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_knight", "Pixel art sprite of a holy knight paladin, full plate armor, helmet with plume, hands empty at sides, standing in RIGHT-FACING SIDE PROFILE view (character looks to the right), full body visible from the side, both feet on ground, gothic fantasy D&D style, 16-color palette, side profile view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_golem", "Pixel art sprite of a stone golem character, bulky body made of grey stone blocks, glowing green eyes, no legs (column-like base), arms at sides, standing facing forward, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_dragon", "Pixel art sprite of a draconian humanoid character, dragon-like head with horns and snout, red scaled body, tail, wearing leather armor, hands empty at sides, standing in RIGHT-FACING SIDE PROFILE view (character looks to the right), full body visible from the side, both feet on ground, gothic fantasy D&D style, 16-color palette, side profile view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_vampire", "Pixel art sprite of a vampire lord character, pale skin, black hair slicked back, red and black cape, formal suit, fangs visible, hands empty at sides, standing in RIGHT-FACING SIDE PROFILE view (character looks to the right), full body visible from the side, both feet on ground, gothic fantasy D&D style, 16-color palette, side profile view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
]

# Gli stessi enemy e miniboss prompt del gen_walk_animations.py (li importo)
# Per semplicita', copio solo quelli necessari qui sotto. In una versione
# successiva potremmo importarli direttamente.
ENEMIES = [
    ("monster_001", "Pixel art sprite of a rotten skeletal ghoul, long claws, ragged flesh, hunched posture, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, side view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_002", "Pixel art sprite of an abyssal spider, armored black carapace, multiple glowing red eyes, eight hairy legs bent inward resting position, gothic fantasy D&D style, 16-color palette, top-down 45 degree view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_003", "Pixel art sprite of a spectral wolf, smoky cyan-blue translucent fur, glowing cyan eyes, sharp fangs, standing alert with all four legs on ground, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_004", "Pixel art sprite of a corrupted cultist, hooded dark red robe, runic tattoos on hands, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_005", "Pixel art sprite of a mimic treasure chest, wooden chest body with huge gaping maw full of sharp teeth, long tongue, small clawed feet, standing on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_006", "Pixel art sprite of a giant rat, matted brown fur, rotten yellow teeth, long pink tail, standing on all four legs, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_007", "Pixel art sprite of a swamp witch, pointed black hat, tattered purple robe, glowing green skin, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_008", "Pixel art sprite of a skeleton lancer, rusted armor, hollow eye sockets, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, side view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_009", "Pixel art sprite of a creeping shadow, amorphous dark smoky form, glowing yellow eyes, no visible legs, hovering above ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_010", "Pixel art sprite of a bone golem, massive ribcage body, clacking bone joints, skull head with glowing eyes, standing on stubby leg bones, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_011", "Pixel art sprite of an ash serpent, smoky grey scales, ember orange eyes, sinuous coiled body, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_012", "Pixel art sprite of a damned knight, blackened plate armor with ember cracks, tattered black cape, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_013", "Pixel art sprite of a mad wizard, glowing purple eyes, torn blue robes, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_015", "Pixel art sprite of a demonic crow, ragged black wings, metallic grey beak, glowing red eyes, perched standing position, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_016", "Pixel art sprite of a subterranean tentacle, mucous green skin, scattered yellow eyes along its length, writhing upright, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_017", "Pixel art sprite of a watchful gargoyle, grey stone texture, broken wings folded, perched stance on two legs, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_018", "Pixel art sprite of a well spirit, watery blue translucent face, bubble effects around, hovering above ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_019", "Pixel art sprite of a cursed boar, mud-caked black fur, large curved tusks, four legs standing position, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_020", "Pixel art sprite of a predator fungus, glowing red cap, white spots, stalky legs rooted on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_021", "Pixel art sprite of a green zombie, rotting flesh, tattered clothes, arms hanging forward, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_022", "Pixel art sprite of a white skeleton warrior, glowing eye sockets, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_023", "Pixel art sprite of a translucent ghost, white smoky form, hollow black eyes, hovering above ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_024", "Pixel art sprite of a black bat, leathery wings folded, glowing red eyes, hanging upside down, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_025", "Pixel art sprite of a green slime blob, gelatinous body, two yellow eyes, dripping shape, resting on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_026", "Pixel art sprite of a red demon, bat wings folded, curved black horns, glowing yellow eyes, sharp claws, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_027", "Pixel art sprite of a bronze robot, mechanical body, glowing blue eyes, articulated joints, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_028", "Pixel art sprite of a green goblin, pointed ears, loincloth, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_029", "Pixel art sprite of a wraith, dark hooded cloak, no visible body, glowing cyan eyes, hovering above ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
]

MINIBOSSES = [
    ("miniboss_01", "Pixel art sprite of a miniboss troll, massive green body, single horn, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_02", "Pixel art sprite of a miniboss dark knight, full black armor, glowing red visor eyes, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_03", "Pixel art sprite of a miniboss giant skeleton, oversized skull, rib cage, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_04", "Pixel art sprite of a miniboss ogre, fat green body, single tusk, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_05", "Pixel art sprite of a miniboss swamp beast, mass of vines and mud, glowing green eyes, rooted on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_06", "Pixel art sprite of a miniboss werewolf, brown fur, sharp claws, fangs, standing on two legs, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_07", "Pixel art sprite of a miniboss hellhound, black fur, fire mane, glowing red eyes, four legs standing position, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_08", "Pixel art sprite of a miniboss giant crab, red shell, massive pincers, eight legs, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_09", "Pixel art sprite of a miniboss minotaur, bull head, brown fur, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_10", "Pixel art sprite of a miniboss snake queen, half woman half serpent, scaled tail, hands empty at sides, standing facing forward, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_11", "Pixel art sprite of a miniboss dark priest, black robes, skull mask, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_12", "Pixel art sprite of a miniboss giant worm, segmented body, multiple eyes, sharp teeth maw, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_13", "Pixel art sprite of a miniboss executioner, black hood, massive build, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_14", "Pixel art sprite of a miniboss gargoyle king, stone body, large spread wings, glowing red eyes, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_15", "Pixel art sprite of a miniboss banshee, white ghostly female form, long hair, screaming face, hovering above ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_16", "Pixel art sprite of a miniboss living statue, grey stone humanoid, cracks, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_17", "Pixel art sprite of a miniboss dire wolf, massive black wolf, glowing yellow eyes, sharp fangs, four legs standing position, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
]


# === AI ===
def generate_base_image(prompt, output_path, timeout=300, max_retries=2):
    cmd = ["z-ai", "image", "-p", prompt, "-o", str(output_path), "-s", "1024x1024"]
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


# === POST-PROCESSING ===
def process_base_to_64x64(raw_path):
    """Processa il raw 1024x1024 in un singolo sprite 64x64 RGBA processato."""
    if not raw_path.exists():
        return None
    img = Image.open(raw_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]

    bg_mask = flood_fill_transparency(arr)
    arr[bg_mask, 3] = 0

    bbox = find_bbox(arr[..., 3])
    if bbox is None:
        return None
    rmin, rmax, cmin, cmax = bbox
    body_h = rmax - rmin + 1
    body_w = cmax - cmin + 1

    margin_y = CROP_MARGIN
    margin_x = CROP_MARGIN
    if body_w > body_h * 1.5:
        margin_x = int(margin_x * 1.5)

    y0 = max(0, rmin - margin_y)
    y1 = min(h, rmax + margin_y + 1)
    x0 = max(0, cmin - margin_x)
    x1 = min(w, cmax + margin_x + 1)
    arr_crop = arr[y0:y1, x0:x1]
    arr_crop = fill_internal_holes(arr_crop)

    crop_h, crop_w = arr_crop.shape[:2]
    target_canvas_w = SPRITE_SIZE - 4  # 60
    target_canvas_h = SPRITE_SIZE - 8  # 56
    scale_w = target_canvas_w / float(crop_w) if crop_w > 0 else 1.0
    scale_h = target_canvas_h / float(crop_h) if crop_h > 0 else 1.0
    final_scale = min(scale_w, scale_h)
    new_w = max(1, int(crop_w * final_scale))
    new_h = max(1, int(crop_h * final_scale))

    if new_w > target_canvas_w:
        ratio = float(target_canvas_w) / new_w
        new_w = target_canvas_w
        new_h = max(1, int(new_h * ratio))

    img = Image.fromarray(arr_crop, 'RGBA')
    img = img.resize((new_w, new_h), resample=Image.LANCZOS)
    arr_resized = np.array(img)

    canvas = np.zeros((SPRITE_SIZE, SPRITE_SIZE, 4), dtype=np.uint8)
    feet_y = 56
    if new_h <= feet_y:
        offset_y = feet_y - new_h
    else:
        offset_y = (SPRITE_SIZE - new_h) // 2
    offset_x = (SPRITE_SIZE - new_w) // 2
    if offset_x < 0:
        offset_x = 0
    canvas[offset_y:offset_y + new_h, offset_x:offset_x + new_w] = \
        arr_resized[:min(new_h, SPRITE_SIZE - offset_y), :min(new_w, SPRITE_SIZE - offset_x)]
    arr = canvas

    alpha = arr[..., 3]
    arr[alpha < 32, 3] = 0
    arr[alpha >= 32, 3] = 255
    arr = fill_internal_holes(arr)
    arr = apply_palette(arr)
    return arr


# === TRASFORMAZIONI DETERMINISTICHE PER WALK ===

def make_walk_frame_1(base):
    """
    Frame 1: gamba sinistra alzata (passo sinistro avanti).
    - Corpo abbassato di 1px (bob verso il basso)
    - Porzione gambe (y >= BODY_Y_THRESHOLD) shiftata a destra di 2px
      per simulare passo sinistro avanti (piu' visibile di 1px)
    - Leggero tilt del corpo superiore di 1px a sinistra (dondolio)
    """
    frame = base.copy()
    h, w = frame.shape[:2]
    # Bob verticale: tutto il corpo abbassato di 1px
    new_frame = np.zeros_like(frame)
    new_frame[1:h, :] = frame[0:h-1, :]
    # Shift orizzontale della porzione gambe (y >= BODY_Y_THRESHOLD) di 2px a destra
    legs_start = min(BODY_Y_THRESHOLD, h - 1)
    legs = new_frame[legs_start:h, :, :].copy()
    shifted_legs = np.zeros_like(legs)
    shifted_legs[:, 2:w] = legs[:, 0:w-2]
    new_frame[legs_start:h, :, :] = shifted_legs
    # Leggero tilt del corpo superiore (y < BODY_Y_THRESHOLD) di 1px a sinistra
    # per simulare il dondolio opposto al passo
    body_end = min(BODY_Y_THRESHOLD, h)
    body = new_frame[0:body_end, :, :].copy()
    tilted_body = np.zeros_like(body)
    tilted_body[:, 0:w-1] = body[:, 1:w]
    new_frame[0:body_end, :, :] = tilted_body
    return new_frame


def make_walk_frame_2(base):
    """
    Frame 2: posa neutra + corpo sollevato 1px (passo di transizione).
    """
    frame = base.copy()
    h, w = frame.shape[:2]
    new_frame = np.zeros_like(frame)
    new_frame[0:h-1, :] = frame[1:h, :]
    return new_frame


def make_walk_frame_3(base):
    """
    Frame 3: gamba destra alzata (passo destro avanti).
    - Corpo abbassato di 1px
    - Porzione gambe shiftata a sinistra di 2px (passo destro)
    - Leggero tilt del corpo superiore di 1px a destra (dondolio opposto)
    """
    frame = base.copy()
    h, w = frame.shape[:2]
    new_frame = np.zeros_like(frame)
    new_frame[1:h, :] = frame[0:h-1, :]
    legs_start = min(BODY_Y_THRESHOLD, h - 1)
    legs = new_frame[legs_start:h, :, :].copy()
    shifted_legs = np.zeros_like(legs)
    shifted_legs[:, 0:w-2] = legs[:, 2:w]
    new_frame[legs_start:h, :, :] = shifted_legs
    # Leggero tilt del corpo superiore (y < BODY_Y_THRESHOLD) di 1px a destra
    body_end = min(BODY_Y_THRESHOLD, h)
    body = new_frame[0:body_end, :, :].copy()
    tilted_body = np.zeros_like(body)
    tilted_body[:, 1:w] = body[:, 0:w-1]
    new_frame[0:body_end, :, :] = tilted_body
    return new_frame


def compose_spritesheet_deterministic(base_frame, out_path):
    """
    Composizione orizzontale di 4 frame:
    - Frame 0: base (posa neutra)
    - Frame 1: gamba sinistra alzata (bob giu + shift dx gambe)
    - Frame 2: posa neutra + bob su (passo di transizione)
    - Frame 3: gamba destra alzata (bob giu + shift sx gambe)
    Loop: 0 -> 1 -> 2 -> 3 -> 0
    """
    frames = [
        base_frame,
        make_walk_frame_1(base_frame),
        make_walk_frame_2(base_frame),
        make_walk_frame_3(base_frame),
    ]
    sheet = np.zeros((SPRITE_SIZE, SPRITE_SIZE * N_FRAMES, 4), dtype=np.uint8)
    for i, frame in enumerate(frames):
        if frame is not None:
            sheet[:, i * SPRITE_SIZE:(i + 1) * SPRITE_SIZE] = frame
    img = Image.fromarray(sheet, 'RGBA')
    img.save(out_path)
    return sheet, frames


def write_meta(creature_id):
    meta = {
        "image": f"{creature_id}_sheet.png",
        "frameWidth": SPRITE_SIZE,
        "frameHeight": SPRITE_SIZE,
        "columns": N_FRAMES,
        "rows": 1,
        "anchor": {"x": 32, "y": 56},
        "animations": {
            "idle":   {"row": 0, "frames": N_FRAMES, "frameDuration": 200},
            "walk":   {"row": 0, "frames": N_FRAMES, "frameDuration": 130},
            "attack": {"row": 0, "frames": N_FRAMES, "frameDuration": 90},
            "death":  {"row": 0, "frames": 1, "frameDuration": 120}
        }
    }
    meta_path = SPRITES_DIR / f"{creature_id}_meta.json"
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)


def process_entity(sprite_id, base_prompt):
    """Pipeline completa: 1 generate + trasformazioni deterministiche."""
    print(f"\n[GEN] {sprite_id}")
    base_raw_path = WALK_RAW_DIR / f"{sprite_id}_base_raw.png"
    if base_raw_path.exists():
        print(f"  Base: gia' esistente, skip generate")
    else:
        print(f"  Base: generazione AI...")
        if not generate_base_image(base_prompt, base_raw_path):
            print(f"  [ERROR] Generazione base fallita")
            return False

    print(f"  Post-processing base -> 64x64...")
    base_frame = process_base_to_64x64(base_raw_path)
    if base_frame is None:
        print(f"  [ERROR] Post-processing base fallito")
        return False

    print(f"  Creazione 4 frame animati (trasformazioni deterministiche)...")
    out_path = SPRITES_DIR / f"{sprite_id}_sheet.png"
    sheet, frames = compose_spritesheet_deterministic(base_frame, out_path)

    # Statistiche
    transparent = int(np.sum(sheet[..., 3] == 0))
    total = sheet.shape[0] * sheet.shape[1]
    # Verifica coerenza: conta pixel identici tra frame 0 e frame 1
    f0, f1 = frames[0], frames[1]
    mask_both = (f0[..., 3] > 0) & (f1[..., 3] > 0)
    if mask_both.sum() > 0:
        diff = np.abs(f0[..., :3].astype(int) - f1[..., :3].astype(int))[mask_both]
        identici = (diff.sum(axis=1) < 30).sum() / mask_both.sum() * 100
    else:
        identici = 0
    print(f"  [OK] {out_path.name}: {transparent}/{total} trasparenti ({transparent/total*100:.1f}%)")
    print(f"       Coerenza frame 0-1: {identici:.0f}% pixel identici")
    write_meta(sprite_id)
    return True


def main():
    only = None
    only_type = None
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        only = sys.argv[2]
    if len(sys.argv) > 2 and sys.argv[1] == "--type":
        only_type = sys.argv[2]

    print("=" * 70)
    print("GEN DETERMINISTIC WALK - 1 base AI + 3 frame trasformati")
    print(f"Players:   {len(PLAYERS)}")
    print(f"Enemies:   {len(ENEMIES)}")
    print(f"Miniboss:  {len(MINIBOSSES)}")
    total = len(PLAYERS) + len(ENEMIES) + len(MINIBOSSES)
    print(f"TOTALE:    {total} entita' x 1 chiamata AI = {total} immagini AI")
    print("=" * 70)

    ok = 0
    failed = []

    if only_type in (None, "players"):
        targets = PLAYERS if only is None else [(s, p) for s, p in PLAYERS if s == only]
        for sprite_id, base_prompt in targets:
            try:
                if process_entity(sprite_id, base_prompt):
                    ok += 1
                else:
                    failed.append(sprite_id)
            except Exception as e:
                print(f"  [EXCEPTION] {sprite_id}: {e}")
                failed.append(sprite_id)

    if only_type in (None, "enemies"):
        targets = ENEMIES if only is None else [(s, p) for s, p in ENEMIES if s == only]
        for sprite_id, base_prompt in targets:
            try:
                if process_entity(sprite_id, base_prompt):
                    ok += 1
                else:
                    failed.append(sprite_id)
            except Exception as e:
                print(f"  [EXCEPTION] {sprite_id}: {e}")
                failed.append(sprite_id)

    if only_type in (None, "miniboss"):
        targets = MINIBOSSES if only is None else [(s, p) for s, p in MINIBOSSES if s == only]
        for sprite_id, base_prompt in targets:
            try:
                if process_entity(sprite_id, base_prompt):
                    ok += 1
                else:
                    failed.append(sprite_id)
            except Exception as e:
                print(f"  [EXCEPTION] {sprite_id}: {e}")
                failed.append(sprite_id)

    print("\n" + "=" * 70)
    print(f"Riepilogo: {ok}/{total} completati")
    if failed:
        print(f"Falliti: {', '.join(failed)}")
    print("=" * 70)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
