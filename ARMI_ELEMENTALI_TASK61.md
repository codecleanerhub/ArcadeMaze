# TASK 61 — Armi elementali per archetipo (design)

> Approvato dall'utente dopo l'audit 59 e il parere 59b:
> "i personaggi umani uomo/donna utilizzano le armi da fuoco che trovano
> nel labirinto. Gli altri tipi di personaggi giocabili... trovare nel
> labirinto armi 'elementari' al posto del fucile, pistola, lancia razzi,
> con danni diversi e distribuiti come quelle dell'uomo/donna."
> "Genera armi coerenti col personaggio... Il drago con palle di fuoco di
> diverso tipo e dimensioni, fuoco rosso, fuoco blu, i nemici si infuocano
> o si congelano e muoiono."
> "Se si usano personaggi misti ci saranno entrambe i tipi di armi ma
> faranno meno danni se un player usa l'arma di tipo errato."

## Principi

1. **Umani → armi da fuoco** (PISTOL/SHOTGUN/LASER/ROCKET): invariati.
2. **Non-umani → armi elementali** tematiche, SPAWNANO NELLE CELLE del
   labirinto (dove oggi spawcano solo le armi da fuoco).
3. **Danni DIVERSI ma DISTRIBUITI come le umane**: bilanciamento della
   serie hits-to-kill (4/3/2 — nessuna arma one-shot, regola sacra del
   gioco) e munizioni speculari (20/26/11/6).
4. **Squadre miste**: il labirinto spawna l'UNIONE dei pool dei due
   player; chi usa un'arma fuori dal proprio archetipo fa **-50% danni**
   (hits-to-kill raddoppiati).
5. **Riuso massimo**: reliquie a distanza esistenti (Task 21/24/26) dove
   tematicamente coerenti; PixelLab SOLO per i gap (stima 61c: ~6 gen).
6. **BonusScreen NON toccato**: le 18 reliquie dello schermo bonus
   restano quelle; le elementali vivono in una lista separata
   (ELEMENTAL_WEAPONS) e non entrano nell'offerta bonus.

## Colpo di grazia elementale (stati sul nemico)

Meccaniche ESISTENTI riusate 1:1 ("i nemici si infuocano o si congelano
e muoiono"):

- **fuoco** (`burn_ms` nella def): il colpo che ucciderebbe il nemico
  innesca `Enemy.start_burning()` → il nemico si ferma, brucia
  (overlay effect_fireaura), muore a fine combustione (mucchio di
  ceneri). Nessun danno extra: succede SOLO quando il colpo era comunque
  letale → il tier di bilanciamento resta identico.
- **ghiaccio** (`freeze`): il colpo letale diventa `Enemy.freeze_kill()`
  → statua di ghiaccio (come il raggio congelante Task 50).
- Gli altri colpi (non letali) fanno il danno normale del tier.

## Pool per archetipo

`AFFINITY_POOLS` in GameConstants. "@firearm" = armi da fuoco classiche.

| Archetipo | Pool (tier hits-to-kill) | Fonte |
|---|---|---|
| HERO_M / HERO_F | @firearm: PISTOL(4) LASER(3) SHOTGUN(2) ROCKET(2) | esistenti |
| KNIGHT | spada_lanciante(4) ascia_lancio(3) balestra(2, esistente) alabarda_turbinio(2) | 2 riusi PNG melee |
| MAGE | bastone_arcimago(3, esist.) verga_tempesta(3, esist.) bastone_fuoco(3, burn) lancia_ghiaccio(2, freeze) | 2 nuove |
| ELF | arco_ranger(4, esist.) pugnali_gemelli(4, esist.) freccia_ghiaccio(3, freeze) balestra(2, esist.) | 1 nuova |
| ORC | pugnali_gemelli(4, esist.) ascia_lancio(3) bombe_alchimista(2, esist.) | riuso |
| GOLEM | masso_lanciato(3) bombe(2, esist.) martello_golem_lanciato(2) | riuso proj_boulder |
| VAMPIRE | pugnali_gemelli(4, esist.) dardo_sanguigno(3) balestra(2, esist.) | riuso vampire_blade |
| DRAGON | fiammella(4, burn) palla_fuoco_rossa(3, burn) fiamma_blu(3, freeze) cataclisma(2, burn, AoE) | 4 nuove (spec utente) |

## Nuove reliquie elementali (RelicType 114-126)

Nuovi tipi in ELEMENTAL_WEAPONS (def formato = RELIC_RANGED):
THROWING_SWORD=114, THROWING_AXE=115, HALBERD_THROW=116, FIRE_STAFF=117,
ICE_LANCE=118, ICE_ARROW=119, THROWN_BOULDER=120, GOLEM_HAMMER_THROW=121,
BLOOD_DART=122, FLAME_EMBER=123, FIREBALL_RED=124, FLAME_BLUE=125,
FIRE_MAELSTROM=126.

Comportamenti riusati dalle flag delle def (già implementati in
Player/MainGameController): `fan`, `pierce_max`, `homing`, `chain`,
`lob_px`+`radius_px`. Proiettili: procedurali a tema per spade/asce/
ghiaccio (stile _draw_relic_projectile Task 23); il set DRAGO usa i PNG
del Task 60b (proj_fireball_sheet rosso, ricolorazione BLU gratuita via
PIL, proj_dragon_breath_sheet per il cataclisma, fiammella = frame
fireball scalato).

## Asset (61c)

- Riuso (0 gen): axe.png, halberd.png, golem_hammer.png,
  vampire_blade.png, proj_boulder.png, proj_fireball_sheet.png,
  proj_dragon_breath_sheet.png + ricolori PIL (fiamma blu).
- PixelLab (~6 statici): spada_lanciante, bastone_fuoco, lancia_ghiaccio,
  freccia_ghiaccio, cristallo_fuoco (pickup drago), cristallo_gelo
  (pickup drago blu). Pickup mancanti → quadrato colorato fallback.

## Penalità tipo errato

`weapon_damage_for(type, max_hp, fury, char_type)`:
- se char_type valido e l'arma NON e' nel pool dell'archetipo →
  hits-to-kill ×2 (= -50% danni per colpo).
- Si applica solo alle armi TROVATE NEL LABIRINTO; le reliquie scelte
  nello schermo bonus restano libere (scelta consapevole del player).
- Squadra singola: solo il proprio tipo spawna (umano → solo armi da
  fuoco; non-umano → solo elementali). Mista: unione di entrambi.

## Rollback

- Cancellare i PNG nuovi → fallback procedurali (in mano e pickup).
- `AFFINITY_POOLS` vuoto / char_types non passato → make_random_weapon
  comporta come prima (armi da fuoco): il laboratorio resta giocabile
  anche con il sistema disattivato.
