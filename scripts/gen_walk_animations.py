#!/usr/bin/env python3
"""
gen_walk_animations.py - Genera animazioni di camminata a 4 frame coerenti per:
- 8 personaggi giocabili (player1, player2, char_mage, char_orc, char_elf,
  char_knight, char_golem, char_dragon, char_vampire)
- 28 nemici del labirinto (monster_001..029 escluso 014)
- 17 mini-boss (miniboss_01..17)
- 1 sprite cuore per UI vite

STRATEGIA (stessa dei boss, gia' validata):
1. Per ogni entita', genera 1 immagine base (posa neutra) con z-ai image
2. Crea 3 varianti con z-ai image-edit DAL frame base
   (garantisce coerenza: il personaggio e' IDENTICO, cambiano solo le gambe)
3. Post-processa: flood-fill transparency, fill buchi intra-corpo,
   ridimensiona a 64x64 con LANCZOS, palette 16 colori
4. Normalizza dimensioni frame per evitare effetto zoom/salto
5. Componi spritesheet 256x64 (4 frame x 64px)
6. Aggiorna meta.json: columns=4, walk.frames=4, idle.frames=4

Per il cuore: 1 sola immagine 32x32, senza animazione.

TIMEOUT: ogni chiamata z-ai ha timeout di 300s. Se scade, retry 2 volte.
Se tutti i retry falliscono, usa il frame 0 come fallback.
"""
import os
import sys
import json
import subprocess
import time
import signal
from pathlib import Path
from PIL import Image
import numpy as np
from collections import deque
import concurrent.futures

# Importa funzioni utility dallo script dei boss (gia' validato)
sys.path.insert(0, '/home/z/my-project/ArcadeMaze/scripts')
from gen_boss_animations_v2 import (
    RAW_DIR, SPRITES_DIR, SPRITE_SIZE, N_FRAMES,
    PALETTE, TOL, CROP_MARGIN,
    flood_fill_transparency, find_bbox, fill_internal_holes, apply_palette,
    normalize_frame_sizes, compose_spritesheet, write_meta,
    NODE_EDIT_SCRIPT
)

# Directory raw separata per non confliggere coi boss
WALK_RAW_DIR = Path("/tmp/walk_anim")
WALK_RAW_DIR.mkdir(parents=True, exist_ok=True)

# === DEFINIZIONE ENTITA' ===
# Per ciascuna: (sprite_id, base_prompt_for_generate, list_of_3_edit_prompts_for_walk)
# I prompt walk sono simili per tutti: ciclo camminata 4-frame con gambe alternate.

# Prompt base condiviso per ciclo camminata (le 3 edit)
WALK_EDIT_PROMPTS = [
    "Move ONLY the legs to a mid-stride position: lift the right leg forward and bend the left leg slightly back, keep the upper body, head, arms, torso, AND canvas size PIXEL-IDENTICAL to the input image. Only the legs change. Do NOT zoom, do NOT scale, do NOT move the body. Maintain solid flat pure black RGB(0,0,0) background.",
    "Move ONLY the legs to a passing position: both feet close together mid-air as if mid-step, keep the upper body, head, arms, torso, AND canvas size PIXEL-IDENTICAL to the input image. Only the legs change. Do NOT zoom, do NOT scale, do NOT move the body.",
    "Move ONLY the legs to the opposite mid-stride: lift the left leg forward and bend the right leg slightly back, keep the upper body, head, arms, torso, AND canvas size PIXEL-IDENTICAL to the input image. Only the legs change. Do NOT zoom, do NOT scale, do NOT move the body.",
]

# === 8 PERSONAGGI GIOCABILI ===
# IMPORTANTE: NESSUN player ha armi nello sprite, perche' le armi vengono
# raccolte durante il gioco (non fanno parte del "vestito").
# Per player1 e player2: archeologi stile Indiana Jones, NON fantasy.
PLAYERS = [
    ("player1", "Pixel art sprite of a male archaeologist adventurer, short brown hair, khaki shirt with rolled-up sleeves, brown leather vest, brown trousers, leather boots, khaki fedora hat, no weapons hands empty at sides, standing facing forward with both feet on ground, realistic adventurer style NOT fantasy, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("player2", "Pixel art sprite of a female blonde archaeologist adventurer, long blonde hair, khaki shirt with rolled-up sleeves, brown leather vest, brown trousers, leather boots, no weapons hands empty at sides, standing facing forward with both feet on ground, realistic adventurer style NOT fantasy, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_mage", "Pixel art sprite of a wizard mage character, long blue robe with stars, pointed hat, white beard, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_orc", "Pixel art sprite of a green orc warrior, muscular green skin, tusks, loincloth, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_elf", "Pixel art sprite of an elf ranger, pointed ears, green hooded cloak, leather armor, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_knight", "Pixel art sprite of a holy knight paladin, full plate armor, helmet with plume, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_golem", "Pixel art sprite of a stone golem character, bulky body made of grey stone blocks, glowing green eyes, no legs (column-like base), arms at sides, standing facing forward, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_dragon", "Pixel art sprite of a draconian humanoid character, dragon-like head with horns and snout, red scaled body, tail, wearing leather armor, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
    ("char_vampire", "Pixel art sprite of a vampire lord character, pale skin, black hair slicked back, red and black cape, formal suit, fangs visible, hands empty at sides, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, high contrast gothic lighting, NO text NO UI NO watermark"),
]

# === 28 NEMICI DEL LABIRINTO ===
# (sprite_id, base_prompt). Tutti usano lo stesso WALK_EDIT_PROMPTS
ENEMIES = [
    ("monster_001", "Pixel art sprite of a rotten skeletal ghoul, long claws, ragged flesh, hunched posture, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, side view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_002", "Pixel art sprite of an abyssal spider, armored black carapace, multiple glowing red eyes, eight hairy legs bent inward resting position, gothic fantasy D&D style, 16-color palette, top-down 45 degree view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_003", "Pixel art sprite of a spectral wolf, smoky cyan-blue translucent fur, glowing cyan eyes, sharp fangs, standing alert with all four legs on ground, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_004", "Pixel art sprite of a corrupted cultist, hooded dark red robe, runic tattoos on hands, holding a ritual dagger, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_005", "Pixel art sprite of a mimic treasure chest, wooden chest body with huge gaping maw full of sharp teeth, long tongue, small clawed feet, standing on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_006", "Pixel art sprite of a giant rat, matted brown fur, rotten yellow teeth, long pink tail, standing on all four legs, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_007", "Pixel art sprite of a swamp witch, pointed black hat, tattered purple robe, glowing green skin, holding a potion vial, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_008", "Pixel art sprite of a skeleton lancer, rusted armor, broken spear in hand, hollow eye sockets, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, side view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_009", "Pixel art sprite of a creeping shadow, amorphous dark smoky form, glowing yellow eyes, no visible legs, hovering above ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_010", "Pixel art sprite of a bone golem, massive ribcage body, clacking bone joints, skull head with glowing eyes, standing on stubby leg bones, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_011", "Pixel art sprite of an ash serpent, smoky grey scales, ember orange eyes, sinuous coiled body, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_012", "Pixel art sprite of a damned knight, blackened plate armor with ember cracks, tattered black cape, holding a broken sword, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_013", "Pixel art sprite of a mad wizard, glowing purple eyes, torn blue robes, floating scrolls around, holding a crooked staff, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_015", "Pixel art sprite of a demonic crow, ragged black wings, metallic grey beak, glowing red eyes, perched standing position, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_016", "Pixel art sprite of a subterranean tentacle, mucous green skin, scattered yellow eyes along its length, writhing upright, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_017", "Pixel art sprite of a watchful gargoyle, grey stone texture, broken wings folded, perched stance on two legs, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_018", "Pixel art sprite of a well spirit, watery blue translucent face, bubble effects around, hovering above ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_019", "Pixel art sprite of a cursed boar, mud-caked black fur, large curved tusks, four legs standing position, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_020", "Pixel art sprite of a predator fungus, glowing red cap, white spots, stalky legs rooted on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    # 15 originali (zombie, skeleton, ghost, bat, spider, slime, demon, robot, goblin, orc, wraith, ghoul, imp, rat, cultist)
    ("monster_021", "Pixel art sprite of a green zombie, rotting flesh, tattered clothes, arms hanging forward, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_022", "Pixel art sprite of a white skeleton warrior, rusty sword in hand, glowing eye sockets, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_023", "Pixel art sprite of a translucent ghost, white smoky form, hollow black eyes, hovering above ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_024", "Pixel art sprite of a black bat, leathery wings folded, glowing red eyes, hanging upside down, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_025", "Pixel art sprite of a green slime blob, gelatinous body, two yellow eyes, dripping shape, resting on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_026", "Pixel art sprite of a red demon, bat wings folded, curved black horns, glowing yellow eyes, sharp claws, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_027", "Pixel art sprite of a bronze robot, mechanical body, glowing blue eyes, articulated joints, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_028", "Pixel art sprite of a green goblin, pointed ears, loincloth, holding a rusty dagger, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("monster_029", "Pixel art sprite of a wraith, dark hooded cloak, no visible body, glowing cyan eyes, hovering above ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
]

# === 17 MINI-BOSS ===
MINIBOSSES = [
    ("miniboss_01", "Pixel art sprite of a miniboss troll, massive green body, single horn, club in hand, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_02", "Pixel art sprite of a miniboss dark knight, full black armor, glowing red visor eyes, holding a massive sword, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_03", "Pixel art sprite of a miniboss giant skeleton, oversized skull, rib cage, holding a scythe, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_04", "Pixel art sprite of a miniboss ogre, fat green body, single tusk, holding a tree trunk club, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_05", "Pixel art sprite of a miniboss swamp beast, mass of vines and mud, glowing green eyes, rooted on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_06", "Pixel art sprite of a miniboss werewolf, brown fur, sharp claws, fangs, standing on two legs, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_07", "Pixel art sprite of a miniboss hellhound, black fur, fire mane, glowing red eyes, four legs standing position, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_08", "Pixel art sprite of a miniboss giant crab, red shell, massive pincers, eight legs, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_09", "Pixel art sprite of a miniboss minotaur, bull head, brown fur, massive axe, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_10", "Pixel art sprite of a miniboss snake queen, half woman half serpent, scaled tail, holding two daggers, standing facing forward, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_11", "Pixel art sprite of a miniboss dark priest, black robes, skull mask, holding a cursed staff, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_12", "Pixel art sprite of a miniboss giant worm, segmented body, multiple eyes, sharp teeth maw, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_13", "Pixel art sprite of a miniboss executioner, black hood, massive build, holding a giant axe, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_14", "Pixel art sprite of a miniboss gargoyle king, stone body, large spread wings, glowing red eyes, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_15", "Pixel art sprite of a miniboss banshee, white ghostly female form, long hair, screaming face, hovering above ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_16", "Pixel art sprite of a miniboss living statue, grey stone humanoid, cracks, holding a stone sword, standing facing forward with both feet on ground, gothic fantasy D&D style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_17", "Pixel art sprite of a miniboss dire wolf, massive black wolf, glowing yellow eyes, sharp fangs, four legs standing position, side profile view, gothic fantasy D&D style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency and NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
]


# === FUNZIONI AI ===

def generate_base_image(prompt, output_path, timeout=300, max_retries=2):
    """Genera l'immagine base 1024x1024 con timeout esplicito."""
    cmd = ["z-ai", "image", "-p", prompt, "-o", str(output_path), "-s", "1024x1024"]
    for attempt in range(max_retries):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            if result.returncode == 0 and output_path.exists():
                return True
            if attempt < max_retries - 1:
                time.sleep(3)
        except subprocess.TimeoutExpired:
            # Kill esplicito del processo figlio in caso di timeout
            print(f"      TIMEOUT (tentativo {attempt+1}/{max_retries})")
            if attempt < max_retries - 1:
                time.sleep(5)
        except Exception as e:
            print(f"      ERROR: {e}")
            return False
    return False


def edit_image(prompt, input_path, output_path, timeout=300, max_retries=2):
    """Image-edit via Node SDK con timeout esplicito."""
    cmd = ["node", NODE_EDIT_SCRIPT,
           str(input_path),
           str(output_path),
           prompt]
    for attempt in range(max_retries):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            if result.returncode == 0 and output_path.exists():
                return True
            if attempt == 0:
                err = (result.stderr or "")[:200]
                print(f"      edit fail: {err}")
            if attempt < max_retries - 1:
                time.sleep(3)
        except subprocess.TimeoutExpired:
            print(f"      TIMEOUT edit (tentativo {attempt+1}/{max_retries})")
            if attempt < max_retries - 1:
                time.sleep(5)
        except Exception as e:
            print(f"      ERROR: {e}")
            return False
    return False


# === POST-PROCESSING (riusa funzioni importate) ===

def process_frame(raw_path, target_height=None):
    """Stesso process_frame del boss script, con target_height per allineamento."""
    if not raw_path.exists():
        return None, None
    img = Image.open(raw_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]

    # 1) Flood-fill transparency
    bg_mask = flood_fill_transparency(arr)
    arr[bg_mask, 3] = 0

    # 2) Trova bbox
    bbox = find_bbox(arr[..., 3])
    if bbox is None:
        return None, None
    rmin, rmax, cmin, cmax = bbox
    body_h = rmax - rmin + 1
    body_w = cmax - cmin + 1

    if target_height is None:
        target_height = body_h

    scale = float(target_height) / float(body_h) if body_h > 0 else 1.0
    margin_y = int(CROP_MARGIN * scale) if scale > 1.0 else CROP_MARGIN
    margin_x = int(CROP_MARGIN * scale) if scale > 1.0 else CROP_MARGIN
    if body_w > body_h * 1.5:
        margin_x = int(margin_x * 1.5)

    y0 = max(0, rmin - margin_y)
    y1 = min(h, rmax + margin_y + 1)
    x0 = max(0, cmin - margin_x)
    x1 = min(w, cmax + margin_x + 1)
    arr_crop = arr[y0:y1, x0:x1]

    arr_crop = fill_internal_holes(arr_crop)

    crop_h, crop_w = arr_crop.shape[:2]
    target_canvas_w = SPRITE_SIZE - 4
    target_canvas_h = SPRITE_SIZE - 8
    final_scale = float(target_canvas_h) / float(target_height)
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
    return arr, target_height


# === PIPELINE PRINCIPALE PER ENTITA' ===

def process_entity(sprite_id, base_prompt, edit_prompts):
    """Pipeline completa per un'entita': 1 generate + 3 edit + composizione."""
    print(f"\n[GEN] {sprite_id}")
    # 1. Genera frame base
    base_raw_path = WALK_RAW_DIR / f"{sprite_id}_frame0_raw.png"
    if base_raw_path.exists():
        print(f"  Frame 0 (base): gia' esistente, skip")
    else:
        print(f"  Frame 0 (base): generazione AI...")
        if not generate_base_image(base_prompt, base_raw_path):
            print(f"  [ERROR] Generazione base fallita")
            return False

    # 2. Processa frame base per trovare target_height
    frame0, target_height = process_frame(base_raw_path)
    if frame0 is None:
        print(f"  [ERROR] Post-processing frame 0 fallito")
        return False
    print(f"     Altezza riferimento: {target_height}px")

    # 3. Genera 3 edit
    frames = [frame0]
    for i, edit_prompt in enumerate(edit_prompts, start=1):
        edit_raw_path = WALK_RAW_DIR / f"{sprite_id}_frame{i}_raw.png"
        if edit_raw_path.exists():
            print(f"  Frame {i}: gia' esistente, skip edit")
        else:
            print(f"  Frame {i}: image-edit...")
            full_prompt = (
                f"{edit_prompt}. "
                f"CRITICAL CONSTRAINTS: the character MUST remain PIXEL-IDENTICAL "
                f"to the input image in: body shape, body size, body position in "
                f"canvas, body colors, body proportions, art style. Do NOT zoom, "
                f"do NOT scale, do NOT resize, do NOT move the body. ONLY the legs "
                f"change. Maintain solid flat pure black RGB(0,0,0) background."
            )
            if not edit_image(full_prompt, base_raw_path, edit_raw_path):
                print(f"  [WARN] Edit fallito frame {i}, uso frame 0")
                frames.append(frame0.copy())
                continue

        frame_i, _ = process_frame(edit_raw_path, target_height=target_height)
        if frame_i is None:
            frames.append(frame0.copy())
        else:
            frames.append(frame_i)

    # 4. Composizione con normalizzazione dimensioni
    out_path = SPRITES_DIR / f"{sprite_id}_sheet.png"
    sheet = compose_spritesheet(frames, out_path)

    # 5. Meta JSON (columns=4, walk.frames=4, idle.frames=4)
    meta = {
        "image": f"{sprite_id}_sheet.png",
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
    meta_path = SPRITES_DIR / f"{sprite_id}_meta.json"
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    transparent = int(np.sum(sheet[..., 3] == 0))
    total = sheet.shape[0] * sheet.shape[1]
    print(f"  [OK] {out_path.name}: {transparent}/{total} trasparenti ({transparent/total*100:.1f}%)")
    return True


def generate_heart_sprite():
    """Genera il singolo sprite del cuore per UI vite."""
    print(f"\n[GEN] ui_heart (singolo sprite, no animazione)")
    raw_path = WALK_RAW_DIR / "ui_heart_raw.png"
    if not raw_path.exists():
        prompt = (
            "Pixel art icon of a red heart symbol for video game lives UI, "
            "classic cartoon heart shape with two rounded lobes at top and pointed bottom, "
            "bright red color with darker red outline, small white highlight on top-left lobe for shine effect, "
            "gothic fantasy D&D style, 16-color palette, centered, "
            "OPAQUE heart with NO transparency inside the heart silhouette, "
            "solid flat pure black RGB(0,0,0) background, "
            "crisp pixel art outlines, high contrast. "
            "NO text NO UI NO watermark."
        )
        if not generate_base_image(prompt, raw_path):
            print(f"  [ERROR] Generazione cuore fallita")
            return False

    # Post-processa: ritaglia, ridimensiona a 32x32 (piccolo per UI)
    img = Image.open(raw_path).convert("RGBA")
    arr = np.array(img)
    bg_mask = flood_fill_transparency(arr)
    arr[bg_mask, 3] = 0
    bbox = find_bbox(arr[..., 3])
    if bbox is None:
        print(f"  [ERROR] bbox cuore non trovato")
        return False
    rmin, rmax, cmin, cmax = bbox
    # Ritaglia quadrato centrato sul cuore (piu' piccolo lato)
    side = max(rmax - rmin + 1, cmax - cmin + 1)
    cy = (rmin + rmax) // 2
    cx = (cmin + cmax) // 2
    half = side // 2 + 4
    y0 = max(0, cy - half); y1 = min(arr.shape[0], cy + half)
    x0 = max(0, cx - half); x1 = min(arr.shape[1], cx + half)
    arr = arr[y0:y1, x0:x1]
    arr = fill_internal_holes(arr)
    # Ridimensiona a 32x32 con LANCZOS
    img = Image.fromarray(arr, 'RGBA')
    img = img.resize((32, 32), resample=Image.LANCZOS)
    arr = np.array(img)
    alpha = arr[..., 3]
    arr[alpha < 32, 3] = 0
    arr[alpha >= 32, 3] = 255
    arr = apply_palette(arr)
    out = Image.fromarray(arr.astype('uint8'), 'RGBA')
    out_path = SPRITES_DIR / "ui_heart.png"
    out.save(out_path)
    print(f"  [OK] {out_path.name}: 32x32")
    return True


def main():
    only = None
    only_type = None
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        only = sys.argv[2]
    if len(sys.argv) > 2 and sys.argv[1] == "--type":
        only_type = sys.argv[2]

    print("=" * 70)
    print("GEN WALK ANIMATIONS - players + enemies + minibosses + heart")
    print(f"Players:   {len(PLAYERS)}")
    print(f"Enemies:   {len(ENEMIES)}")
    print(f"Miniboss:  {len(MINIBOSSES)}")
    print(f"Heart:     1")
    total = len(PLAYERS) + len(ENEMIES) + len(MINIBOSSES) + 1
    print(f"TOTALE:    {total} entita' x 4 frame = {total * 4 - 3} chiamate API")
    print("=" * 70)

    ok = 0
    failed = []

    # Heart prima (e' veloce)
    if only_type in (None, "heart") and only is None:
        if generate_heart_sprite():
            ok += 1
        else:
            failed.append("ui_heart")

    # Players
    if only_type in (None, "players"):
        if only is None:
            targets = [(s, p) for s, p in PLAYERS]
        else:
            targets = [(s, p) for s, p in PLAYERS if s == only]
        for sprite_id, base_prompt in targets:
            try:
                if process_entity(sprite_id, base_prompt, WALK_EDIT_PROMPTS):
                    ok += 1
                else:
                    failed.append(sprite_id)
            except Exception as e:
                print(f"  [EXCEPTION] {sprite_id}: {e}")
                failed.append(sprite_id)

    # Enemies
    if only_type in (None, "enemies"):
        if only is None:
            targets = [(s, p) for s, p in ENEMIES]
        else:
            targets = [(s, p) for s, p in ENEMIES if s == only]
        for sprite_id, base_prompt in targets:
            try:
                if process_entity(sprite_id, base_prompt, WALK_EDIT_PROMPTS):
                    ok += 1
                else:
                    failed.append(sprite_id)
            except Exception as e:
                print(f"  [EXCEPTION] {sprite_id}: {e}")
                failed.append(sprite_id)

    # Miniboss
    if only_type in (None, "miniboss"):
        if only is None:
            targets = [(s, p) for s, p in MINIBOSSES]
        else:
            targets = [(s, p) for s, p in MINIBOSSES if s == only]
        for sprite_id, base_prompt in targets:
            try:
                if process_entity(sprite_id, base_prompt, WALK_EDIT_PROMPTS):
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
