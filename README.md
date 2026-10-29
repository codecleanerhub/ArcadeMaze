<p align="center">
  <img src="docs/banner.png" alt="Arcade Maze Fantasy" width="860">
</p>

<h1 align="center">Arcade Maze Fantasy</h1>

<p align="center">
  <a href="https://godotengine.org"><img src="https://img.shields.io/badge/Godot-4.7.2-478CBF?logo=godotengine&logoColor=white" alt="Godot 4.7.2"></a>
  <img src="https://img.shields.io/badge/Linguaggio-GDScript-355570" alt="GDScript">
  <img src="https://img.shields.io/badge/Rendering-GL_Compatibility-6E6E6E" alt="GL Compatibility">
  <img src="https://img.shields.io/badge/Formato-1920%C3%971080-1D6F42" alt="1920x1080">
  <img src="https://img.shields.io/badge/Licenza-Tutti_i_diritti_riservati-C62828" alt="Tutti i diritti riservati">
</p>

<p align="center"><em>English version: <a href="README_EN.md">README_EN.md</a></em></p>

---

**Arcade Maze Fantasy** è un arcade maze action game a tema fantasy/horror: esplora labirinti procedurali infestati, raccogli tesori e reliquie magiche, sopravvivi all'assalto dei fantasmi e affronta 17 boss unici in duello. Nato come prototipo C++/SFML, è stato interamente riportato in **Godot 4.7.2 / GDScript** con audio sintetizzato in tempo reale, interfaccia localizzata IT/EN e zero file audio nel progetto.

## Indice

- [Caratteristiche](#caratteristiche)
- [Gameplay](#gameplay)
- [Controlli](#controlli)
- [Requisiti e avvio](#requisiti-e-avvio)
- [Struttura del progetto](#struttura-del-progetto)
- [Architettura tecnica](#architettura-tecnica)
- [Qualità e test](#qualità-e-test)
- [Rami di sviluppo](#rami-di-sviluppo)
- [Licenza](#licenza)

## Caratteristiche

- **68 livelli story** organizzati in 17 cicli: 3 livelli a labirinto + 1 boss room per ciascun ciclo.
- **Labirinti procedurali** 30×15 celle generati a ogni partita, con tunnel di collegamento ai bordi in stile arcade classico.
- **17 boss unici**, ognuno con stanza dedicata, schema di attacco e proiettili tematici propri; **51 tipi di mini-boss** e **44 tipi di nemico**.
- **Pericoli del labirinto**: i **fantasmi a lenzuolo** (bianco, rosso, verde) attraversano i muri e si rigenerano per tutto il livello a ondate crescenti col progresso — tolgono il 33% dell'energia al tocco e si schivano saltando; le **celle zombie** nascondono braccia che spuntano dalle inferriate dei muri: danno inevitabile, occorre attendere la ritrazione o pagare il tocco.
- **Sistema reliquie**: 18 reliquie raccolte nelle schermate bonus post-boss — 6 armi da mischia, 6 armi a distanza, 6 armature con effetti speciali (riflessione proiettili, spine, rigenerazione, aure dannose…) — più **armi elementali per archetipo** (fiamma, gelo, arcano) con lampo di volata dedicato per arma ed elemento.
- **Atmosfera dungeon**: torce con pozze di luce calda che lampeggiano sul pavimento, lanterna che segue l'eroe, arredi gotici generati (altari, bare, garguglie, ragnatele…), palette scure per livello.
- **Co-op 2 giocatori** locale: fuoco amico attivo, trasferimento dell'anima tra giocatori e crediti continue separati.
- **Audio 100% procedurale**: 56 effetti sonori e 10 tracce musicali sintetizzate a runtime, senza alcun file audio nel progetto — incluso un intermezzo lirico verista di pubblico dominio trascritto nota per nota. La sintesi gira in un thread in background: avvio in ~2,5 secondi.
- **Grafica pixel-art AI** (pipeline PixelLab) con set sprite in alta definizione (frame 256px), meta-dati di orientamento per un verso di marcia coerente, animazione procedurale degli arti dei boss via mesh deformation e interfaccia gotica in oro medievale (font Goth And Gothic).
- **Localizzazione IT/EN** completa: menu, HUD, overlay e loghi per lingua, selezionabile da `OPTIONS → LANGUAGE` e salvata nella configurazione.
- **Sistemi arcade classici**: Hall of Fame persistente top 10, continue con countdown, modalità demo attract con AI pathfinding BFS dopo 30 s di inattività nel menu, "Hurry Up!" con inseguitore immortale.
- **Supporto joystick** completo con rimappatura dei tasti da menu.

## Gameplay

Il ciclo di gioco alterna **esplorazione del labirinto** e **duello con il boss**:

1. **Nel labirinto** raccogli gli 8 tesori per aprire la porta di uscita; trova armi, munizioni e 9 collectible per livello (calice dell'immortalità, pozione fantasma che attraversa i muri, scettro dei fulmini, stivali velocità, medikit, statue alleate…). Attenzione ai fantasmi lenzuolo e alle celle zombie: attraversano e invadono i corridoi. Al 50% dei nemici eliminati si apre un portale che respawna nemici e un mini-boss.
2. **Nella boss room** il combattimento è libero a pixel: schiva i proiettili tematici del boss, usa le armi che cadono a terra (si rigenerano finché il boss vive), il cannone d'assedio dedicato e la mina rimbalzante che toglie il 30% della vita del boss.
3. **Dopo ogni boss** (tranne l'ultimo livello) scegli una reliquia nella schermata bonus della fucina: una per famiglia, con rotazione pensata per collezionarle tutte in un playthrough completo.

Meccaniche di profondità: stamina che limita a 2 i salti consecutivi, respawn progressivo dei nemici nei livelli avanzati, invincibilità temporanea del calice, modalità fantasma della pozione, nemici che mirano il giocatore vivo più vicino in 2P, ondate di fantasmi che si infittiscono salendo di livello.

## Controlli

| Azione | Giocatore 1 | Giocatore 2 |
|---|---|---|
| Movimento | Frecce | W A S D |
| Salto (doppio con stamina) | Spazio | Q |
| Sparo | Z | E |
| Pausa | P | — |
| Conferma nei menu | Invio / Spazio | — |

**Joystick**: movimento su stick analogico e D-pad; i tasti salto/sparo sono configurabili dal menu `OPTIONS` (configurazione separata per P1 e P2, salvata in `config.ini`).

## Requisiti e avvio

- [Godot 4.7.2](https://godotengine.org/download) (esattamente questa versione: il progetto usa le feature del ramo 4.7)
- Nessuna dipendenza aggiuntiva: asset e audio sono generati dal progetto stesso

```bash
# Avvio dall'editor
#   apri godot/project.godot e premi F5

# Avvio da terminale
godot --path godot

# Verifica headless (senza finestra)
godot --headless --quit --path godot
```

Per l'export eseguibile usare i template di export Godot 4.7.2 (renderer GL Compatibility: compatibile anche con hardware datato e WebGL). Le procedure di build multipiattaforma (Windows, Linux, macOS) sono documentate in [BUILD_WINDOWS.md](BUILD_WINDOWS.md).

## Struttura del progetto

```
godot/                       # Progetto Godot (aprire questo)
├── project.godot            # autoload, input map, impostazioni finestra
├── scripts/
│   ├── core/                # MainGameController, Player, Maze, BFS,
│   │                        #   GameConstants, I18nManager, DemoController…
│   ├── bosses/              # Boss, MiniBoss
│   ├── enemies/             # Enemy, EnemySpawner (respawn progressivo)
│   ├── entities/            # GhostReaper, KnightAlly, MazeGhosts,
│   │                        #   ZombieCells, effetti (anima, fulmini)
│   ├── items/               # Weapon, Projectile, Collectibles, Hammer
│   ├── audio/               # AudioManager (sintesi procedurale completa)
│   └── ui/                  # HUD, menu, schermate, BonusScreen, ContinuesOverlay
├── scenes/                  # 13 scene .tscn
├── shaders/                 # 11 shader (enhancement, outfit armature, deform boss…)
├── assets/                  # sprites (SD + XHD + env), backgrounds, fonts
└── tests/                   # 42 test runtime headless + 69 harness screenshot
src/                         # Prototipo legacy C++/SFML (solo riferimento)
scripts/                     # Generatori Python degli asset sprite
tools/bestiary/              # Generatori del bestiario
docs/                        # Banner e materiali del repository
```

## Architettura tecnica

- **Autoload** (10, in ordine di caricamento): `LoadingScreen`, `BootManager`, `GameManager`, `SpriteManager`, `ConfigManager`, `I18n`, `AudioManager`, `EffectsManager`, `EnvironmentArt`, `CharacterArt`.
- **MainGameController** gestisce il ciclo labirinto: input, pickup, portale, "Hurry Up!", fuoco amico, passate delle reliquie, respawn progressivo, continue per giocatore e i due pericoli del labirinto (`MazeGhosts`, `ZombieCells`).
- **BossRoomController** gestisce il duello: proiettili homing, rigenerazione armi, cannone d'assedio, anti-softlock, fase bonus post-boss con congelamento del fight.
- **Player** a doppia modalità: movimento grid-locked nel labirinto, movimento libero nella boss room; stato completo reliquie e armi elementali, stamina salti, ghost mode, orientamento coerente col verso di marcia e muzzle flash per arma.
- **I18nManager** (autoload `I18n`): localizzazione IT/EN con dizionari, segnale di cambio lingua e loghi per lingua.
- **AudioManager**: 3182 righe di sintesi in GDScript puro — oscillatori, noise, riverberi a tap circolari per loop senza giunzioni, pool di voci con debounce; la sintesi avviene in un thread in background con priorità (menu → SFX → musica) per un avvio rapido.
- **Maze** rendering procedurale (palette per livello, muri con luminanza calibrata, torce e lanterne) e `DeformableSprite`: mesh 2D con profili di animazione degli arti per tipo di boss e enhancement canvas via shader.
- Costanti e bilanciamento centralizzati in **GameConstants.gd** (alias `C`), con flag statici di rollback per ogni feature grafica (lanterne, fantasmi, celle zombie, XHD…).
- **Performance**: cache di materiali e texture degli effetti, niente readback GPU→CPU per frame, cap sugli FX simultanei, sprite a caricamento differito.

## Qualità e test

Il progetto ha una suite di **42 test runtime headless** più **69 harness di screenshot** per la QA visiva, eseguibili senza finestra:

```bash
# Esempio: esecuzione di un test
godot --headless --path godot res://tests/test_stamina_weapons.tscn

# Esempio: screenshot di validazione (richiede X server virtuale)
xvfb-run godot --path godot res://tests/shot_showcase.tscn
```

La suite copre: stamina e armi, tunnel in 2P, boss room 2P, HUD, reliquie, armi elementali, fuoco amico, continue, respawn progressivo, localizzazione, fantasmi a ondate e celle zombie, facing degli sprite, audio, pausa e grafica XHD. Ogni modifica al gameplay passa per test dedicati prima del commit; le verifiche visive combinano screenshot a piena risoluzione, QA VLM e controlli numerici sui pixel.

## Rami di sviluppo

| Ramo | Contenuto |
|---|---|
| `main` | Prototipo originale C++/SFML |
| `engine/godot-engine` | **Il gioco corrente** — porting completo Godot 4.7.2 (ramo attivo; confluisce in `main` tramite la [PR #9](https://github.com/codecleanerhub/ArcadeMaze/pull/9)) |
| `gameplay`, `linux`, `multi_plat`, `feature/*` | Rami storici del prototipo C++ |

Il prototipo C++ in `src/` resta nel repository come riferimento dei comportamenti canonici: la logica GDScript ne replica algoritmi e bilanciamento (BFS, generazione labirinto, schema dei boss).

## Licenza

**Tutti i diritti riservati.** Questo progetto è privato e non è rilasciato con alcuna licenza d'uso. È vietata qualsiasi riproduzione, distribuzione, modifica o utilizzo del codice, degli asset e dei contenuti senza autorizzazione scritta esplicita dell'autore. Il progetto è valutato per una futura distribuzione commerciale.
