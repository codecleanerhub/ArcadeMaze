#!/usr/bin/env python3
"""Genera i 34 nuovi sprite mini-boss (18-51) con AI."""
import os, sys, json, subprocess, time
from pathlib import Path
from PIL import Image
import numpy as np

sys.path.insert(0, '/home/z/my-project/ArcadeMaze/scripts')
from gen_boss_animations_v2 import (
    RAW_DIR, SPRITES_DIR, SPRITE_SIZE, N_FRAMES,
    PALETTE, TOL, CROP_MARGIN,
    flood_fill_transparency, find_bbox, fill_internal_holes, apply_palette,
    compose_spritesheet, write_meta, NODE_EDIT_SCRIPT
)

WALK_RAW_DIR = Path("/tmp/miniboss_ai_gen")
WALK_RAW_DIR.mkdir(parents=True, exist_ok=True)

# 34 nuovi mini-boss con prompt specifici
NEW_MINIBOSSES = [
    # Narnia (7)
    ("miniboss_18", "Pixel art sprite of Fenris Wolf from Narnia, massive black wolf with glowing red eyes, sharp fangs, dark fur with frost tips, standing on all four legs, side profile view, gothic fantasy Narnia style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_19", "Pixel art sprite of a White Witch Guard from Narnia, armored knight in silver plate armor with ice crystal decorations, holding an ice sword, blue cape with frost patterns, standing facing forward with both feet on ground, gothic fantasy Narnia style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_20", "Pixel art sprite of a Narnia Minotaur, massive bull-headed warrior with brown fur, sharp horns, wearing bronze armor, holding a double-headed axe, standing facing forward with both feet on ground, gothic fantasy Narnia style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_21", "Pixel art sprite of a Narnia Dwarf Berserker, stocky bearded dwarf warrior with red beard, iron helmet with horns, chainmail armor, holding a war axe, standing facing forward with both feet on ground, gothic fantasy Narnia style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_22", "Pixel art sprite of a Witch Knight from Narnia, dark knight in black armor with white fur cloak, holding an ice lance, glowing blue eyes, standing facing forward with both feet on ground, gothic fantasy Narnia style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_23", "Pixel art sprite of a Corrupted Talking Beast from Narnia, a large wolf-like creature with twisted features, dark matted fur, glowing purple eyes, sharp claws, standing on all four legs, side profile view, gothic fantasy Narnia style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_24", "Pixel art sprite of an Ice Giant from Narnia, massive humanoid made of blue-white ice crystals, glowing cyan eyes, holding a huge ice mace, standing facing forward with both feet on ground, gothic fantasy Narnia style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    # The Witcher (10)
    ("miniboss_25", "Pixel art sprite of a Leshen from The Witcher, tall skeletal forest creature with deer skull head, antlers, wooden body with roots and branches, blackbirds perched on antlers, standing facing forward, gothic dark fantasy Witcher style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_26", "Pixel art sprite of a Bruxa from The Witcher, pale vampire woman with long black hair, red glowing eyes, sharp fangs, tattered black dress, standing facing forward, gothic dark fantasy Witcher style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_27", "Pixel art sprite of a Katakan from The Witcher, muscular vampire creature with grey skin, red eyes, sharp claws, bat-like features, tattered flesh, standing facing forward with both feet on ground, gothic dark fantasy Witcher style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_28", "Pixel art sprite of a Fiend from The Witcher, massive demonic beast with black fur, large curved horns, glowing red eyes, four legs standing position, side profile view, gothic dark fantasy Witcher style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_29", "Pixel art sprite of a Witcher Golem, massive stone golem with glowing orange cracks, rocky body, no head just a glowing core, standing facing forward, gothic dark fantasy Witcher style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_30", "Pixel art sprite of a Noonwraith from The Witcher, ghostly female spirit with flowing white dress, translucent body, sun-like aura, empty eye sockets, standing facing forward, gothic dark fantasy Witcher style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_31", "Pixel art sprite of a Foglet from The Witcher, hunched creature made of fog and shadow, glowing yellow eyes, clawed hands, smoky body, standing facing forward, gothic dark fantasy Witcher style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_32", "Pixel art sprite of a Grave Hag from The Witcher, old hunched witch with long white hair, hunched posture, ragged clothes, sharp claws, standing facing forward, gothic dark fantasy Witcher style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_33", "Pixel art sprite of a Manticore from The Witcher, lion-bodied creature with bat wings, scorpion tail with spikes, human face, standing on all four legs, side profile view, gothic dark fantasy Witcher style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_34", "Pixel art sprite of a Cyclops from The Witcher, massive one-eyed giant, grey skin, single large eye in center of forehead, holding a huge stone mace, standing facing forward, gothic dark fantasy Witcher style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    # Doom (10)
    ("miniboss_35", "Pixel art sprite of a Doom Imp, brown leathery demon with spikes on back, glowing red eyes, sharp claws, standing facing forward with both feet on ground, Doom FPS game style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_36", "Pixel art sprite of a Pinky Demon from Doom, massive pink bull-like demon with horns, wide mouth full of teeth, no eyes, four legs standing position, side profile view, Doom FPS game style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_37", "Pixel art sprite of a Revenant from Doom, skeletal warrior with rocket launcher attached to shoulder, glowing eye sockets, standing facing forward with both feet on ground, Doom FPS game style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_38", "Pixel art sprite of a Cacodemon from Doom, large red spherical demon with one large eye, sharp teeth, horns, hovering with no legs, Doom FPS game style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_39", "Pixel art sprite of a Hell Knight from Doom, tall muscular demon with grey skin, no horns, sharp claws, standing facing forward with both feet on ground, Doom FPS game style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_40", "Pixel art sprite of a Mancubus from Doom, massive obese demon with fire cannons for hands, brown leathery skin, standing facing forward with both feet on ground, Doom FPS game style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_41", "Pixel art sprite of an Archvile from Doom, tall thin demon with elongated arms, yellow skin, burning hands, standing facing forward with both feet on ground, Doom FPS game style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_42", "Pixel art sprite of a Baron of Hell from Doom, tall pink demon with horns, hooves, sharp claws, standing facing forward with both feet on ground, Doom FPS game style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_43", "Pixel art sprite of a Pain Elemental from Doom, brown flying demon with wide mouth full of teeth, stubby arms, no legs, Doom FPS game style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_44", "Pixel art sprite of a Cyberdemon from Doom, massive cybernetic demon with rocket launcher arm, metal legs, red skin, standing facing forward, Doom FPS game style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    # Ibridi (7)
    ("miniboss_45", "Pixel art sprite of a Shadow Assassin, dark hooded figure with glowing purple daggers, smoke-like body, no visible face, standing facing forward with both feet on ground, dark fantasy style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_46", "Pixel art sprite of a Crystal Golem, humanoid made of translucent blue crystals, glowing inner core, jagged crystal body, standing facing forward, fantasy style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_47", "Pixel art sprite of a Void Walker, dark entity with purple void energy, elongated limbs, glowing white eyes, standing facing forward, cosmic horror style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_48", "Pixel art sprite of a Blood Elemental, swirling mass of red blood energy, humanoid shape made of liquid blood, dripping, standing facing forward, dark fantasy horror style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_49", "Pixel art sprite of a Storm Titan, massive humanoid made of dark clouds and lightning, glowing yellow eyes, lightning bolts as arms, standing facing forward, elemental fantasy style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_50", "Pixel art sprite of a Plague Lord, bloated green-rotted figure with plague mask, tattered purple robes, dripping pus, holding a staff, standing facing forward, dark fantasy horror style, 16-color palette, front view, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
    ("miniboss_51", "Pixel art sprite of a Void Serpent, massive coiled snake with purple-black scales, glowing violet eyes, fanged mouth, side profile view, cosmic horror style, 16-color palette, full body filling the canvas, OPAQUE body with NO transparency, solid flat pure black RGB(0,0,0) background, crisp pixel art outlines, NO text NO UI NO watermark"),
]


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


def edit_image(prompt, input_path, output_path, timeout=300, max_retries=2):
    cmd = ["node", NODE_EDIT_SCRIPT, str(input_path), str(output_path), prompt]
    for attempt in range(max_retries):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            if result.returncode == 0 and output_path.exists():
                return True
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


WALK_EDIT_PROMPTS = [
    "Move ONLY the legs to a mid-stride position: lift the right leg forward and bend the left leg slightly back, keep the upper body, head, arms, torso, AND canvas size PIXEL-IDENTICAL to the input image. Only the legs change. Do NOT zoom, do NOT scale, do NOT move the body. Maintain solid flat pure black RGB(0,0,0) background.",
    "Move ONLY the legs to a passing position: both feet close together mid-air as if mid-step, keep the upper body, head, arms, torso, AND canvas size PIXEL-IDENTICAL to the input image. Only the legs change. Do NOT zoom, do NOT scale, do NOT move the body.",
    "Move ONLY the legs to the opposite mid-stride: lift the left leg forward and bend the right leg slightly back, keep the upper body, head, arms, torso, AND canvas size PIXEL-IDENTICAL to the input image. Only the legs change. Do NOT zoom, do NOT scale, do NOT move the body.",
]


def process_base_to_64x64(raw_path):
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
    target_canvas_w = SPRITE_SIZE - 4
    target_canvas_h = SPRITE_SIZE - 8
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


def process_miniboss(sprite_id, base_prompt):
    print(f"\n[GEN] {sprite_id}")
    base_raw_path = WALK_RAW_DIR / f"{sprite_id}_frame0_raw.png"
    if base_raw_path.exists():
        print(f"  Base: gia' esistente, skip generate")
    else:
        print(f"  Base: generazione AI...")
        if not generate_base_image(base_prompt, base_raw_path):
            print(f"  [ERROR] Generazione base fallita")
            return False

    frame0 = process_base_to_64x64(base_raw_path)
    if frame0 is None:
        print(f"  [ERROR] Post-processing base fallito")
        return False

    frames = [frame0]
    for i, edit_prompt in enumerate(WALK_EDIT_PROMPTS, start=1):
        edit_raw_path = WALK_RAW_DIR / f"{sprite_id}_frame{i}_raw.png"
        if edit_raw_path.exists():
            print(f"  Frame {i}: gia' esistente, skip edit")
        else:
            print(f"  Frame {i}: image-edit...")
            full_prompt = f"{edit_prompt}. CRITICAL CONSTRAINTS: the character MUST remain PIXEL-IDENTICAL to the input image in: body shape, body size, body position in canvas, body colors, body proportions, art style. Do NOT zoom, do NOT scale, do NOT resize, do NOT move the body. ONLY the legs change. Maintain solid flat pure black RGB(0,0,0) background."
            if not edit_image(full_prompt, base_raw_path, edit_raw_path):
                print(f"  [WARN] Edit fallito frame {i}, uso frame 0")
                frames.append(frame0.copy())
                continue
        frame_i = process_base_to_64x64(edit_raw_path)
        if frame_i is None:
            frames.append(frame0.copy())
        else:
            frames.append(frame_i)

    out_path = SPRITES_DIR / f"{sprite_id}_sheet.png"
    sheet = compose_spritesheet(frames, out_path)
    transparent = int(np.sum(sheet[..., 3] == 0))
    total = sheet.shape[0] * sheet.shape[1]
    print(f"  [OK] {out_path.name}: {transparent}/{total} ({transparent/total*100:.1f}%)")
    write_meta(sprite_id)
    return True


def main():
    only = None
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        only = sys.argv[2]

    print("=" * 60)
    print(f"GEN 34 NUOVI MINI-BOSS CON AI (Narnia/Witcher/Doom)")
    print("=" * 60)

    ok = 0
    failed = []
    for sprite_id, base_prompt in NEW_MINIBOSSES:
        if only and sprite_id != only:
            continue
        try:
            if process_miniboss(sprite_id, base_prompt):
                ok += 1
            else:
                failed.append(sprite_id)
        except Exception as e:
            print(f"  [EXCEPTION] {sprite_id}: {e}")
            failed.append(sprite_id)

    print(f"\n=== Riepilogo: {ok}/{len(NEW_MINIBOSSES)} completati ===")
    if failed:
        print(f"Falliti: {', '.join(failed)}")
    return 0 if not failed else 1

if __name__ == "__main__":
    sys.exit(main())
