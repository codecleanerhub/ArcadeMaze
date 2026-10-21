#!/bin/bash
# TASK 35 — PNG per le due PERGAMENE EVENTO (terremoto + voragini).
# Stesso stile/forma, palette diversa:
#   * quake_scroll : pergamena color sabbia/ambra, sigillo CERALACCA ARANCIO
#     fuoco, bordi bruciati (tinte calde) → sfondo MAGENTA
#   * chasm_scroll : pergamena VIOLA/INDACO scura, sigillo ceralacca viola
#     psichico, bordi bruciati → sfondo CIANO (le tinte viola cadono nella
#     famiglia magenta: chiave ciano per il chroma-key, vedi
#     process_relic_icons.py lezione TASK 25)
# Output: /tmp/parchment_gen/<id>.png (1024x1024)
# Il piccolo SIMBOLO in alto a destra (zigzag sismico / spirale voragine)
# viene compositato DETERMINISTICAMENTE in process_parchment_sprites.py:
# l'AI non è affidabile sui dettagli posizionali.

OUT=/tmp/parchment_gen
mkdir -p "$OUT"

STYLE_COMMON="dark fantasy video game item icon, high quality detailed digital painting, painterly style, dramatic warm rim lighting, strong contrast, centered single item filling about 70 percent of the frame with margins, full item fully visible, plain flat solid pure"

gen() {
  local id="$1"; local bg="$2"; shift 2
  local desc="$1"
  if [ -s "$OUT/$id.png" ]; then
    echo "SKIP $id (già presente)"
    return 0
  fi
  echo "=== $id ==="
  z-ai image -p "$desc, $STYLE_COMMON $bg background color, absolutely uniform background, no gradient background, no drop shadow on the background, no text, no watermark, no border, no frame" -o "$OUT/$id.png" -s 1024x1024 \
    && echo "OK $id" || echo "FAIL $id"
}

# STESSA FORMA: rotolo di pergamena verticale chiuso, estremità arrotolate
# in alto e in basso, leggermente srotolato al centro con rune incise,
# nastro di cuoio e sigillo di ceralacca. Cambia SOLO la palette.
BASE_SHAPE="an ancient magic parchment scroll, vertical rolled parchment with curled wooden roller ends top and bottom, partially unrolled vellum body with two short glowing runic inscriptions engraved in the center, a thin leather ribbon strap wrapped around the middle holding"

gen quake_scroll "magenta #FF00FF" "$BASE_SHAPE a round orange-red wax seal, aged sandstone parchment in warm amber parchment tones with scorched singed edges, faint ember glow along the burn marks, glowing orange runes"

gen chasm_scroll "cyan #00FFFF" "$BASE_SHAPE a round violet wax seal, dusk-violet enchanted parchment in deep indigo purple tones with scorched singed edges, faint violet void glow along the burn marks, glowing purple runes"

ls -la "$OUT"
