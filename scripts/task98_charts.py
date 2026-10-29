#!/usr/bin/env python3
"""Task 98 — grafici per il report (regole typesetting/charts.md):
niente spine alto/destra, griglia tratteggiata 20%, donut 65% con legenda
ricca (strategia C: zero testo sul grafico), etichette solo primi/ultimi/max.
"""
import json

import matplotlib
import matplotlib.font_manager as fm

fm.fontManager.addfont('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
import matplotlib.pyplot as plt

plt.rcParams['font.sans-serif'] = ['DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

# palette cascade (stessa del report)
ACCENT = '#96771c'
ACCENT_2 = '#7a63bf'
HEADER_FILL = '#544e3c'
ICON = '#85774d'
BORDER = '#c4bfaf'
TEXT = '#22211f'
MUTED = '#7b7972'

data = json.load(open('/home/z/my-project/scripts/task98_data.json'))

# ------------------------------------------------------------------ grafico 1
# curva XP cumulativa (linea) + soglia massima raggiungibile
levels = [l['livello'] for l in data['levels']]
xp = [l['xp_cumulata'] for l in data['levels']]
tot_max = data['tot_max']

fig, ax = plt.subplots(figsize=(7.4, 3.6), constrained_layout=True)
ax.plot(levels, xp, color=ACCENT, linewidth=2.5, solid_capstyle='round',
        zorder=3)
ax.fill_between(levels, xp, color=ACCENT, alpha=0.12, zorder=2)
# tetto dei punti cumulabili
ax.axhline(tot_max, color=HEADER_FILL, linewidth=1.2, linestyle=(0, (4, 3)),
           zorder=2)
ax.annotate('massimo cumulabile in una run (~201.000)',
            xy=(2.4, tot_max), xytext=(2.4, tot_max + 11000),
            fontsize=8.5, color=HEADER_FILL)
# marker SOLO sui punti chiave (primo, L20 = max raggiungibile, ultimo)
key_pts = {2: 'bottom', 20: 'bottom', 25: 'bottom'}
for lv, va in key_pts.items():
    i = levels.index(lv)
    ax.plot(lv, xp[i], 'o', color=ACCENT, markersize=5, zorder=4)
    off = -16000 if lv == 2 else -9000
    dy = 8000 if lv == 2 else 0
    if lv == 20:
        ax.annotate(f'L{lv}: {xp[i]:,}'.replace(',', '.'),
                    xy=(lv, xp[i]), xytext=(lv - 4.2, xp[i] + 12000),
                    fontsize=9, color=TEXT, fontweight='bold')
        ax.vlines(lv, 0, xp[i], color=BORDER, linewidth=0.8, linestyle=':',
                  zorder=1)
    else:
        ax.annotate(f'{xp[i]:,}'.replace(',', '.'),
                    xy=(lv, xp[i]), xytext=(lv - 0.6, xp[i] + 9000),
                    fontsize=8.5, color=MUTED)
ax.annotate('livello 20 = tetto pratico\n(L21 richiede ~207.500)',
            xy=(20, xp[levels.index(20)]), xytext=(15.6, 150000),
            fontsize=8.5, color=HEADER_FILL,
            arrowprops=dict(arrowstyle='-', color=BORDER, lw=0.8))

ax.set_xlabel('Livello del player', fontsize=9, color=TEXT)
ax.set_ylabel('Punti cumulati (XP)', fontsize=9, color=TEXT)
ax.set_xlim(1, 25.8)
ax.set_ylim(0, 230000)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_color(BORDER)
ax.spines['bottom'].set_color(BORDER)
ax.tick_params(colors=MUTED, labelsize=8)
ax.grid(True, linestyle='--', alpha=0.2, linewidth=0.5)
ax.yaxis.set_major_formatter(lambda v, _: f'{int(v/1000)}k')
fig.savefig('/home/z/my-project/scripts/task98_chart_xp.png', dpi=200)
plt.close(fig)
print('grafico XP salvato')

# ------------------------------------------------------------------ grafico 2
# composizione del massimo cumulabile: donut + legenda ricca (strategia C)
comp = data['composition']
labels_map = [
    ('Boss (17 uccisioni)', comp['boss'], ACCENT),
    ('Nemici (1.428 uccisioni)', comp['nemici'], ACCENT_2),
    ('Tesori (306 raccolte)', comp['tesori'], HEADER_FILL),
    ('Mini-boss (51 uccisioni)', comp['mini-boss'], ICON),
    ('Calici e sciami (127 eventi)', comp['calici+sciami'], BORDER),
]
tot = sum(v for _, v, _ in labels_map)

fig, (ax, lax) = plt.subplots(1, 2, figsize=(7.4, 3.1),
                              gridspec_kw={'width_ratios': [1, 1.25]},
                              constrained_layout=True)
wedges, _ = ax.pie([v for _, v, _ in labels_map],
                   colors=[c for _, _, c in labels_map],
                   startangle=90, counterclock=False,
                   wedgeprops=dict(width=0.35, edgecolor='white',
                                   linewidth=1.5))
ax.text(0, 0.06, '201k', ha='center', va='center', fontsize=17,
        color=TEXT, fontweight='bold')
ax.text(0, -0.24, 'punti massimi', ha='center', va='center', fontsize=8,
        color=MUTED)
# legenda ricca a destra (griglia allineata)
lax.axis('off')
y = 0.88
for name, v, c in labels_map:
    lax.add_patch(plt.Circle((0.03, y), 0.022, color=c,
                             transform=lax.transAxes))
    lax.text(0.09, y, name, transform=lax.transAxes, fontsize=9.5,
             va='center', color=TEXT)
    lax.text(0.97, y, f'{v/1000:.1f}k', transform=lax.transAxes, fontsize=9.5,
             va='center', ha='right', color=TEXT, fontweight='bold')
    lax.text(0.97, y - 0.09, f'{v/tot*100:.0f}% del totale',
             transform=lax.transAxes, fontsize=8, va='center', ha='right',
             color=MUTED)
    y -= 0.21
fig.savefig('/home/z/my-project/scripts/task98_chart_composition.png', dpi=200)
plt.close(fig)
print('grafico composizione salvato')
