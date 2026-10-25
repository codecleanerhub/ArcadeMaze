#!/usr/bin/env python3
"""PixelLab v2 API client per Arcade Maze Fantasy (ricostruito Task 52).

Ricostruzione della pipeline persa nel 3° reset sandbox (§8.2 del contesto).
Regole API (validate sulle 95 entity dei Task 28-29):
  - POST /create-image-pixflux   SINCRONO, ritorna base64
  - POST /animate-with-text-v3   BACKGROUND job -> poll GET /background-jobs/{id}
  - GET  /balance                gratuito (subscription.generations)
  - retry su HTTP 429 con backoff 90s; retry su 5xx (3 tentativi, backoff 10s)
  - MAI duplicare un POST pagato: lo stato per-entity vive in state/{id}.json
"""
from __future__ import annotations

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE_URL = "https://api.pixellab.ai/v2"
KEY_PATHS = [
    "/home/z/my-project/secrets/.env.pixellab",
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "secrets", ".env.pixellab"),
]
MIN_RESERVE = 150.0  # budget guard §8.2: le generazioni non scendono mai sotto

_API_KEY: str | None = None


def api_key() -> str:
    """Carica la key PixelLab (env PIXELLAB_API_KEY oppure secrets/.env.pixellab)."""
    global _API_KEY
    if _API_KEY:
        return _API_KEY
    env = os.environ.get("PIXELLAB_API_KEY")
    if env:
        _API_KEY = env.strip()
        return _API_KEY
    for path in KEY_PATHS:
        if os.path.isfile(path):
            for line in open(path, encoding="utf-8"):
                line = line.strip()
                if line.startswith("PIXELLAB_API_KEY="):
                    _API_KEY = line.split("=", 1)[1].strip()
                    return _API_KEY
    raise SystemExit("ERRORE: PIXELLAB_API_KEY non trovata (env o secrets/.env.pixellab)")


def _request(method: str, path: str, payload: dict | None = None,
             timeout: int = 120, retries_5xx: int = 3) -> dict:
    """Richiesta HTTP con retry su 429 (backoff 90s) e 5xx (backoff 10s)."""
    url = f"{BASE_URL}{path}"
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    attempt_5xx = 0
    attempt_429 = 0
    while True:
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", f"Bearer {api_key()}")
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt_429 < 2:
                attempt_429 += 1
                wait = 90
                print(f"[api] 429 rate limit, attesa {wait}s (tentativo {attempt_429}/2)...", flush=True)
                time.sleep(wait)
                continue
            if 500 <= e.code < 600 and attempt_5xx < retries_5xx:
                attempt_5xx += 1
                print(f"[api] {e.code} server error, retry in 10s ({attempt_5xx}/{retries_5xx})...", flush=True)
                time.sleep(10)
                continue
            body = ""
            try:
                body = e.read().decode("utf-8", "replace")[:400]
            except Exception:
                pass
            raise RuntimeError(f"HTTP {e.code} su {method} {path}: {body}") from e
        except urllib.error.URLError as e:
            if attempt_5xx < retries_5xx:
                attempt_5xx += 1
                print(f"[api] network error ({e}), retry in 10s...", flush=True)
                time.sleep(10)
                continue
            raise


def get_balance() -> float:
    """Generazioni residue (gratuito)."""
    resp = _request("GET", "/balance")
    try:
        return float(resp["subscription"]["generations"])
    except (KeyError, TypeError, ValueError) as e:
        raise RuntimeError(f"Risposta /balance inattesa: {resp}") from e


def budget_guard(planned_cost: float, action: str = "batch") -> float:
    """Verifica che balance - planned >= MIN_RESERVE. Ritorna il balance."""
    bal = get_balance()
    if bal - planned_cost < MIN_RESERVE:
        raise SystemExit(
            f"BUDGET GUARD [{action}]: balance {bal} - costo {planned_cost} "
            f"< riserva {MIN_RESERVE} — operazione rifiutata"
        )
    return bal


def b64_of_file(path: str) -> dict:
    """Base64Image payload per l'API (type base64 / format png)."""
    with open(path, "rb") as f:
        return {"type": "base64", "format": "png",
                "base64": base64.b64encode(f.read()).decode("ascii")}


def save_b64_image(b64: str, out_path: str) -> str:
    """Decodifica e salva un'immagine base64 ritornata dall'API."""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(base64.b64decode(b64))
    return out_path


def create_image_pixflux(description: str, width: int, height: int,
                         color_image_path: str | None = None,
                         seed: int = 11, no_background: bool = True,
                         outline: str | None = None, shading: str | None = None,
                         detail: str | None = None, view: str | None = None,
                         direction: str | None = None,
                         negative_description: str | None = None,
                         raw_dump_path: str | None = None) -> list[str]:
    """POST /create-image-pixflux (SINCRONO). Ritorna lista di base64 (>=1).

    La risposta grezza viene SEMPRE salvata su raw_dump_path (se dato) per
    poter recuperare un POST già pagato senza rigenerarlo.
    """
    payload: dict = {
        "description": description,
        "image_size": {"width": width, "height": height},
        "seed": seed,
        "no_background": no_background,
    }
    if color_image_path:
        payload["color_image"] = b64_of_file(color_image_path)
    if outline:
        payload["outline"] = outline
    if shading:
        payload["shading"] = shading
    if detail:
        payload["detail"] = detail
    if view:
        payload["view"] = view
    if direction:
        payload["direction"] = direction
    if negative_description:
        payload["negative_description"] = negative_description
    resp = _request("POST", "/create-image-pixflux", payload, timeout=300)
    if raw_dump_path:
        os.makedirs(os.path.dirname(raw_dump_path), exist_ok=True)
        with open(raw_dump_path, "w", encoding="utf-8") as f:
            json.dump(resp, f)
    return extract_images(resp)


def extract_images(resp) -> list[str]:
    """Estrae i base64 dalle forme di risposta note dell'API PixelLab.

    Forme gestite (verificate: forma 1 su pixflux 2026-10):
      1. {"usage": ..., "image": {"type": "base64", "base64": "..."}}
      2. {"images": [{"base64": ...}, ...]}
      3. {"base64": "..."}
      4. ["...", ...] o [{"base64": ...}, ...]
    """
    if isinstance(resp, dict) and isinstance(resp.get("image"), dict) \
            and "base64" in resp["image"]:
        return [resp["image"]["base64"]]
    if isinstance(resp, dict) and "images" in resp:
        return [img["base64"] for img in resp["images"]
                if isinstance(img, dict) and "base64" in img]
    if isinstance(resp, dict) and "base64" in resp:
        return [resp["base64"]]
    if isinstance(resp, list):
        return [x["base64"] if isinstance(x, dict) else x for x in resp]
    raise RuntimeError(f"Risposta pixflux inattesa: {str(resp)[:300]}")


def animate_with_text_v3(first_frame_path: str, action: str,
                         frame_count: int = 4, seed: int = 7,
                         no_background: bool = True,
                         poll_interval: float = 8.0, poll_timeout: float = 420.0) -> list[str]:
    """POST /animate-with-text-v3 (BACKGROUND) + poll fino a completamento.

    Ritorna la lista di base64 delle immagini del job. La PRIMA immagine è
    il reference (da scartare — regola §8.2 passo 3).
    """
    payload = {
        "first_frame": b64_of_file(first_frame_path),
        "action": action,
        "frame_count": frame_count,
        "seed": seed,
        "no_background": no_background,
    }
    resp = _request("POST", "/animate-with-text-v3", payload, timeout=300)
    job_id = resp.get("background_job_id") or resp.get("job_id")
    if not job_id:
        # risposta sincrona inattesa: gestisci comunque immagini immediate
        if isinstance(resp, dict) and "images" in resp:
            return [img.get("base64", "") for img in resp["images"]]
        raise RuntimeError(f"Risposta animate v3 senza job id: {str(resp)[:300]}")
    print(f"[api] job {job_id} avviato, polling...", flush=True)
    t0 = time.time()
    while time.time() - t0 < poll_timeout:
        time.sleep(poll_interval)
        job = _request("GET", f"/background-jobs/{job_id}")
        status = str(job.get("status", "")).lower()
        if status in ("done", "completed", "succeeded", "success"):
            lr = job.get("last_response") or {}
            if isinstance(lr, dict) and "images" in lr:
                return [img.get("base64", "") for img in lr["images"] if img.get("base64")]
            if isinstance(lr, dict) and lr.get("base64"):
                return [lr["base64"]]
            raise RuntimeError(f"Job {job_id} done senza immagini: {str(job)[:300]}")
        if status in ("failed", "error"):
            raise RuntimeError(f"Job {job_id} FALLITO: {str(job.get('last_response'))[:400]}")
        # processing / pending: continua
    raise TimeoutError(f"Job {job_id} non completato entro {poll_timeout:.0f}s")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "balance":
        print(f"generazioni residue: {get_balance()}")
