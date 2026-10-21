## upscale_xhd_lib.py - Deterministic 4x pixel-art upscaler (Task 22).
##
## Strategy for CLEAN PIXEL ART sources (9-16 colors, binary alpha):
##   1. Pad transparent pixels' RGB with nearest opaque color (dilation)
##      -> avoids dark-background contamination on bicubic blends.
##   2. Bicubic 4x resize of the padded RGBA image.
##   3. Alpha: smoothstep tightening (keeps 1-2 sub-pixel AA at silhouettes).
##   4. RGB: snap every pixel to the source frame palette (nearest color).
##      -> hard edges land at sub-pixel accurate positions (xBR-like look),
##         exact same palette => art NOT altered, only smoother outlines.
##
## 100% deterministic (no RNG, no AI): same input -> same output, so the
## process can be re-run and is trivially reversible (delete xhd/ folder).
##
## Source frame conventions:
##   - main sheets   256x64  = 4 frames of 64x64
##   - single sheets  64x64  = 1 frame
## Output: 4x per frame, same layout (1024x256 / 256x256).
import numpy as np
from PIL import Image

SCALE = 4


def _pad_transparent_rgb(rgb: np.ndarray, alpha: np.ndarray, iterations: int = 4) -> np.ndarray:
    """Dilate opaque colors into transparent regions so bicubic has sane RGB
    under alpha==0 (sources store ~(12,12,12) there)."""
    out = rgb.astype(np.int16).copy()
    opaque = alpha > 0
    h, w = opaque.shape
    for _ in range(iterations):
        # 4-neighbour growth of the opaque mask
        grown = opaque.copy()
        grown[1:, :] |= opaque[:-1, :]
        grown[:-1, :] |= opaque[1:, :]
        grown[:, 1:] |= opaque[:, :-1]
        grown[:, :-1] |= opaque[:, 1:]
        newly = grown & ~opaque
        if not newly.any():
            break
        # each newly-opaque pixel takes the color of an OPAQUE neighbour
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                # destination window: pixels p whose neighbour p+(dy,dx) exists
                y0d, y1d = max(0, -dy), h - max(0, dy)
                x0d, x1d = max(0, -dx), w - max(0, dx)
                dest = (slice(y0d, y1d), slice(x0d, x1d))
                src = (slice(y0d + dy, y1d + dy), slice(x0d + dx, x1d + dx))
                mask = newly[dest] & opaque[src]
                if mask.any():
                    out[dest][mask] = out[src][mask]
        opaque = grown
    return out


def _snap_to_palette(rgb: np.ndarray, palette: np.ndarray) -> np.ndarray:
    """Nearest-palette-color snap (squared RGB distance, weighted like xBRZ)."""
    h, w, _ = rgb.shape
    flat = rgb.reshape(-1, 3).astype(np.float32)
    pal = palette.reshape(-1, 3).astype(np.float32)
    # xBRZ-ish perceptual weights: luminance-ish emphasis
    wts = np.array([2.0, 4.0, 1.0], dtype=np.float32)
    a = flat * wts
    b = pal * wts
    # dist matrix: (N, P)
    d = ((a[:, None, :] - b[None, :, :]) ** 2).sum(axis=2)
    idx = np.argmin(d, axis=1)
    snapped = pal[idx].reshape(h, w, 3)
    return np.clip(snapped + 0.5, 0, 255).astype(np.uint8)


def _smoothstep_alpha(a: np.ndarray) -> np.ndarray:
    """Tighten the bicubic alpha ramp into a ~1 sub-pixel transition."""
    x = np.clip((a.astype(np.float32) - 96.0) / 64.0, 0.0, 1.0)
    s = x * x * (3.0 - 2.0 * x)  # smoothstep between alpha 96..160
    return (s * 255.0 + 0.5).astype(np.uint8)


def upscale_frame_4x(frame: Image.Image) -> Image.Image:
    """Upscale ONE 64x64 RGBA frame to 256x256, pixel-art aware."""
    src = np.array(frame.convert("RGBA"))
    h, w = src.shape[:2]
    rgb = src[:, :, :3]
    alpha = src[:, :, 3]

    # palette = unique opaque colors of the source frame
    opaque_px = rgb[alpha > 0]
    if opaque_px.size == 0:
        # fully transparent frame: just nearest-upscale alpha
        big = frame.resize((w * SCALE, h * SCALE), Image.NEAREST)
        return big
    palette = np.unique(opaque_px.reshape(-1, 3), axis=0)

    # 1. pad transparent RGB
    padded_rgb = _pad_transparent_rgb(rgb, alpha)

    # 2. bicubic 4x on RGBA (padded RGB + raw alpha)
    tmp = np.dstack([padded_rgb.astype(np.uint8), alpha])
    tmp_img = Image.fromarray(tmp, "RGBA").resize(
        (w * SCALE, h * SCALE), Image.BICUBIC)
    big = np.array(tmp_img)

    # 3. alpha smoothstep
    big_alpha = _smoothstep_alpha(big[:, :, 3])

    # 4. RGB palette snap (only where alpha > 0; elsewhere RGB irrelevant)
    big_rgb = _snap_to_palette(big[:, :, :3], palette)

    out = np.dstack([big_rgb, big_alpha]).astype(np.uint8)
    return Image.fromarray(out)


def upscale_sheet(src_path: str, dst_path: str) -> tuple:
    """Upscale a spritesheet. Handles 256x64 (4 frames) and 64x64 (1 frame).
    Frames are processed independently to avoid cross-frame bleeding.
    Returns (n_frames, dst_size)."""
    im = Image.open(src_path).convert("RGBA")
    w, h = im.size
    if w == h:
        frames = [im]
    elif w == 4 * h:
        frames = [im.crop((i * h, 0, (i + 1) * h, h)) for i in range(4)]
    else:
        raise ValueError(f"unexpected sheet size {w}x{h} for {src_path}")

    ups = [upscale_frame_4x(f) for f in frames]
    fw, fh = ups[0].size
    if len(ups) == 1:
        sheet = ups[0]
    else:
        sheet = Image.new("RGBA", (fw * len(ups), fh), (0, 0, 0, 0))
        for i, u in enumerate(ups):
            sheet.paste(u, (i * fw, 0))
    sheet.save(dst_path, optimize=True)
    return (len(frames), sheet.size)
