## I18nManager.gd - Autoload "I18n": localizzazione UI ENGLISH / ITALIANO.
##
## TASK 44 (richiesta utente): voce di menu OPTIONS -> LANGUAGE che cambia
## ALLA VOLTA ogni testo del gioco (voci di menu, intro, nomi/descrizioni
## delle armi bonus-reliquie, nemici, boss, HUD, schermate). Lingua di
## DEFAULT: ENGLISH. La scelta è PERSISTITA in user://config.ini dalla
## chiave LANGUAGE di ConfigManager.
##
## Termini arcade usati in inglese ANCHE in Italia (richiesta utente):
## restano in inglese in entrambe le lingue — "HALL OF FAME", "CREDITS",
## "Hurry Up!", "GAME OVER", "CONTINUE?", "TEST MODE", "DEMO MODE",
## "ARCADE MAZE", ON/OFF, P1/P2.
##
## ARCHITETTURA:
##   * Questo autoload possiede il dizionario TEXTS e la variabile `language`.
##   * Le funzioni STATIC (Boss.get_boss_name, GameConstants.get_weapon_name)
##     NON possono risolvere gli autoload (verificato: "Identifier not
##     found"): per quelle usano il mirror statico GameConstants.ui_language,
##     che è l'UNICO punto in cui questa classe lo scrive (_sync_mirror).
##   * Le reliquie non usano chiavi: hanno già i campi bilingui nelle loro
##     definizioni (name/short/desc = IT, name_en/short_en/desc_en = EN);
##     i helper relic_name()/relic_short()/relic_desc() scelgono il campo.
##   * t("chiave") ritorna la stringa nella lingua corrente; se la chiave
##     manca ritorna la chiave stessa (errore evidente ma mai un crash).
extends Node

signal language_changed(new_language: int)

enum Language { ENGLISH = 0, ITALIAN = 1 }

const C = preload("res://scripts/core/GameConstants.gd")

# ============================================================================
# Dizionario dei testi — UNA chiave per stringa visibile.
# Formati (%d, %s) applicati dal CHIAMANTE con l'operatore %.
# ============================================================================
const TEXTS: Dictionary = {
        # ---------------- Menu principale / sottomenu OPTIONS ----------------
        "menu.num_players": {"en": "NUMBER OF PLAYERS: %d", "it": "GIOCATORI: %d"},
        "menu.game_mode": {"en": "GAME MODE: %s", "it": "MODALITÀ: %s"},
        "menu.test_mode": {"en": "TEST MODE: %s", "it": "TEST MODE: %s"},
        "menu.options": {"en": "OPTIONS", "it": "IMPOSTAZIONI"},
        "menu.start": {"en": "START GAME", "it": "INIZIA PARTITA"},
        "menu.credits": {"en": "CREDITS", "it": "CREDITS"},
        "menu.hall_of_fame": {"en": "HALL OF FAME", "it": "HALL OF FAME"},
        "menu.music": {"en": "MUSIC: %s", "it": "MUSICA: %s"},
        "menu.language": {"en": "LANGUAGE: %s", "it": "LINGUA: %s"},
        "menu.lang_english": {"en": "ENGLISH", "it": "ENGLISH"},
        "menu.lang_italian": {"en": "ITALIANO", "it": "ITALIANO"},
        "menu.configure_joystick": {"en": "CONFIGURE JOYSTICK", "it": "CONFIGURA JOYSTICK"},
        "menu.back": {"en": "BACK", "it": "INDIETRO"},
        "menu.hint": {
                "en": "UP/DOWN TO SELECT - LEFT/RIGHT TO CHANGE",
                "it": "SU/GIÙ PER SELEZIONARE - SINISTRA/DESTRA PER CAMBIARE",
        },
        "menu.on": {"en": "ON", "it": "ON"},
        "menu.off": {"en": "OFF", "it": "OFF"},
        "mode.story": {"en": "STORY", "it": "STORIA"},
        "mode.infinite": {"en": "INFINITE", "it": "INFINITA"},
        # ---------------- Ruota personaggi ----------------
        "char.hero": {"en": "HERO", "it": "EROE"},
        "char.heroine": {"en": "HEROINE", "it": "EROINA"},
        "char.mage": {"en": "MAGE", "it": "MAGO"},
        "char.orc": {"en": "ORC", "it": "ORCO"},
        "char.elf": {"en": "ELF", "it": "ELFO"},
        "char.knight": {"en": "KNIGHT", "it": "CAVALIERE"},
        "char.golem": {"en": "GOLEM", "it": "GOLEM"},
        "char.dragon": {"en": "DRAGON", "it": "DRAGO"},
        "char.vampire": {"en": "VAMPIRE", "it": "VAMPIRO"},
        # ---------------- SelectPlayer ----------------
        "select.title": {"en": "SELECT PLAYER %d", "it": "SELEZIONA GIOCATORE %d"},
        "select.hint": {
                "en": "LEFT/RIGHT TO ROTATE - ENTER TO CONFIRM",
                "it": "SINISTRA/DESTRA PER RUOTARE - INVIO PER CONFERMARE",
        },
        # ---------------- ConfigJoy ----------------
        "joy.player": {"en": "PLAYER %d", "it": "GIOCATORE %d"},
        "joy.press_jump": {"en": "PRESS JUMP BUTTON", "it": "PREMI IL TASTO SALTO"},
        "joy.press_shoot": {"en": "PRESS SHOOT BUTTON", "it": "PREMI IL TASTO FUOCO"},
        "joy.hint": {
                "en": "ESC TO CANCEL  •  STEP %d OF 2",
                "it": "ESC PER ANNULLARE  •  PASSO %d DI 2",
        },
        "joy.same_as_jump": {
                "en": "SAME AS JUMP! PRESS ANOTHER BUTTON",
                "it": "UGUALE AL SALTO! PREMI UN ALTRO TASTO",
        },
        # ---------------- Intro cutscene (4 didascalie) ----------------
        "intro.cap1": {
                "en": "It all began with the search for an island that appears on no map.\n"
                + "We chose the course. It was the storm that chose us.\n"
                + "The island welcomed us with cliffs black and hard as steel,\n"
                + "elements unseen, and whispers from below.",
                "it": "Tutto iniziò cercando un'isola che non appare su nessuna mappa.\n"
                + "Scegliemmo noi la rotta. Fu la tempesta a sceglierci.\n"
                + "L'isola ci accolse con scogliere nere e dure come acciaio,\n"
                + "elementi mai visti e sussurri dal sottosuolo.",
        },
        "intro.cap2": {
                "en": "The ruins were not dead. They were waiting.\n"
                + "Every corridor breathed. Every shadow had teeth.\n"
                + "We lit our torches and pressed deeper, driven by gold and glory.\n"
                + "The maze would test our worth.",
                "it": "Le rovine non erano morte. Stavano aspettando.\n"
                + "Ogni corridoio respirava. Ogni ombra aveva denti.\n"
                + "Accendemmo le torce e scendemmo più a fondo, spinti da oro e gloria.\n"
                + "Il labirinto avrebbe messo alla prova il nostro valore.",
        },
        "intro.cap3": {
                "en": "Creatures of nightmare roamed these halls.\n"
                + "Skeletons of ancient warriors, demons of fire and shadow,\n"
                + "beasts twisted by centuries of darkness.\n"
                + "We fought. We bled. We pressed on.",
                "it": "Creature da incubo vagavano in queste sale.\n"
                + "Scheletri di antichi guerrieri, demoni di fuoco e ombra,\n"
                + "bestie deformate da secoli di oscurità.\n"
                + "Combattemmo. Sanguinammo. Andammo avanti.",
        },
        "intro.cap4": {
                "en": "At the heart of the island, the Treasure awaited.\n"
                + "But it was guarded by the oldest evil.\n"
                + "A dragon of bone and fire, the last sentinel of a forgotten age.\n"
                + "This is where our legend begins.",
                "it": "Nel cuore dell'isola, il Tesoro attendeva.\n"
                + "Ma era custodito dal male più antico.\n"
                + "Un drago di ossa e fuoco, ultima sentinella di un'età dimenticata.\n"
                + "È qui che inizia la nostra leggenda.",
        },
        "intro.skip": {"en": "PRESS FIRE TO SKIP", "it": "PREMI FUOCO PER SALTARE"},
        # ---------------- HUD ----------------
        "hud.score": {"en": "SCORE", "it": "PUNTI"},
        "hud.lives": {"en": "LIVES", "it": "VITE"},
        "hud.energy": {"en": "ENERGY", "it": "ENERGIA"},
        "hud.wpn": {"en": "WPN", "it": "ARMA"},
        "hud.ammo": {"en": "AMMO", "it": "COLPI"},
        "hud.life": {"en": "LIFE", "it": "VITA"},
        "hud.en": {"en": "EN", "it": "EN"},
        "hud.enemy": {"en": "ENEMY:", "it": "NEMICO:"},
        "hud.boss": {"en": "BOSS", "it": "BOSS"},
        "hud.treasures": {"en": "Treasures remaining:", "it": "Tesori rimasti:"},
        "hud.player": {"en": "PLAYER %d", "it": "GIOCATORE %d"},
        # TASK 99 (LEVEL UP): HUD + annuncio + modale abilità
        "hud.level": {"en": "LV %d", "it": "LV %d"},
        "hud.skill_points": {"en": "SKILL +%d", "it": "PUNTI +%d"},
        "levelup.title": {"en": "LEVEL UP!", "it": "LEVEL UP!"},
        "levelup.reached": {"en": "LEVEL %d", "it": "LIVELLO %d"},
        "levelup.gained_one": {"en": "+1 SKILL POINT", "it": "+1 PUNTO ABILITÀ"},
        "levelup.gained_many": {"en": "+%d SKILL POINTS", "it": "+%d PUNTI ABILITÀ"},
        "levelup.points": {"en": "POINTS: %d", "it": "PUNTI: %d"},
        "levelup.hint": {
                "en": "UP/DOWN select - LEFT/RIGHT -/+ - HOLD FIRE to confirm",
                "it": "SU/GIÙ scegli — SINISTRA/DESTRA +/− — TENI FUOCO per confermare",
        },
        "levelup.ok_hold": {"en": "HOLD FIRE = OK", "it": "TENI PREMUTO FUOCO = OK"},
        "levelup.banked": {
                "en": "Not spending is fine: unspent points stay banked for the next level up",
                "it": "Puoi anche non spendere: i punti non spesi restano bancati per il prossimo level up",
        },
        "levelup.locked": {"en": "REQUIRES STAMINA 4", "it": "RICHIEDE RESISTENZA 4"},
        "levelup.max": {"en": "MAX", "it": "MAX"},
        # ---------------- TASK 105: New Game Plus (card post-credits) --------
        "ngp.title": {"en": "NEW GAME PLUS", "it": "NEW GAME PLUS"},
        "ngp.title2": {"en": "NEW GAME PLUS PLUS", "it": "NEW GAME PLUS PLUS"},
        # rev.2: domanda split su due livelli — la frase "Ricomincerai..."
        # viene mostrata SOTTO la domanda; niente chip danno/resistenza
        # né livello in card (richiesta utente).
        "ngp.question": {
                "en": "Do you want to keep playing (new game plus)?",
                "it": "Vuoi continuare a giocare (new game plus)?",
        },
        "ngp.question_sub": {
                "en": "You will restart from the first level of the game without losing your accumulated upgrades, at a higher difficulty.",
                "it": "Ricomincerai dal primo livello di gioco senza perdere i tuoi upgrade accumulati ad una difficoltà maggiore.",
        },
        "ngp.question2": {
                "en": "Do you want to keep playing (new game plus plus)?",
                "it": "Vuoi continuare a giocare (new game plus plus)?",
        },
        "ngp.question2_sub": {
                "en": "You will restart from the first level of the game without losing your accumulated upgrades, at an even higher difficulty.",
                "it": "Ricomincerai dal primo livello di gioco senza perdere i tuoi upgrade accumulati ad una difficoltà ancora maggiore.",
        },
        "ngp.yes": {"en": "YES", "it": "SÌ"},
        "ngp.no": {"en": "NO", "it": "NO"},
        "ngp.no_hint": {
                "en": "Return to the Main Menu",
                "it": "Ritorna al Menù Principale",
        },
        "ngp.hint": {
                "en": "UP/DOWN to choose - ENTER/SPACE to confirm",
                "it": "SU/GIÙ per scegliere — INVIO/SPAZIO per confermare",
        },
        # ---------------- Win / Lose ----------------
        "win.title": {"en": "VICTORY!", "it": "VITTORIA!"},
        "win.subtitle": {
                "en": "YOU CONQUERED THE ARCADE MAZE",
                "it": "HAI CONQUISTATO L'ARCADE MAZE",
        },
        "win.body": {
                "en": "All 68 levels cleared. The treasure is yours.",
                "it": "Tutti i 68 livelli completati. Il tesoro è tuo.",
        },
        "win.final_score": {"en": "FINAL SCORE: %d", "it": "PUNTEGGIO FINALE: %d"},
        "win.p_score": {"en": "P1 SCORE: %d    P2 SCORE: %d", "it": "PUNTI P1: %d    PUNTI P2: %d"},
        "screen.return_hint": {
                "en": "PRESS ENTER TO RETURN TO MENU",
                "it": "PREMI INVIO PER TORNARE AL MENU",
        },
        "lose.body": {
                "en": "The maze has claimed another soul...",
                "it": "Il labirinto si è preso un'altra anima...",
        },
        "lose.final": {
                "en": "FINAL SCORE: %d    LEVEL: %d",
                "it": "PUNTEGGIO FINALE: %d    LIVELLO: %d",
        },
        "lose.p_final": {
                "en": "P1 SCORE: %d    P2 SCORE: %d    LEVEL: %d",
                "it": "PUNTI P1: %d    PUNTI P2: %d    LIVELLO: %d",
        },
        "lose.new_high": {
                "en": "NEW HIGH SCORE! PREPARE TO ENTER YOUR NAME...",
                "it": "NUOVO RECORD! PREPARATI A INSERIRE IL TUO NOME...",
        },
        # ---------------- Continue ----------------
        "cont.title": {"en": "CONTINUE?", "it": "CONTINUE?"},
        "cont.left": {"en": "CONTINUES LEFT: %d", "it": "CONTINUE RIMASTI: %d"},
        # TASK 79b: riga completa con numero giocatore (ContinuesOverlay 2P)
        "cont.p_left": {
                "en": "PLAYER %d CONTINUES LEFT: %d",
                "it": "GIOCATORE %d — CONTINUE RIMASTI: %d",
        },
        "cont.hint": {
                "en": "LEFT/RIGHT TO SELECT - ENTER TO CONFIRM",
                "it": "SINISTRA/DESTRA PER SCEGLIERE - INVIO PER CONFERMARE",
        },
        "cont.yes": {"en": "YES", "it": "SÌ"},
        "cont.no": {"en": "NO", "it": "NO"},
        # ---------------- Hall of Fame ----------------
        "hof.rank": {"en": "RANK", "it": "POS"},
        "hof.name": {"en": "NAME", "it": "NOME"},
        "hof.score": {"en": "SCORE", "it": "PUNTI"},
        "hof.level": {"en": "LEVEL", "it": "LIV"},
        # ---------------- Name entry ----------------
        "ne.title": {"en": "NEW HIGH SCORE!", "it": "NUOVO RECORD!"},
        "ne.score_line": {"en": "SCORE: %d   -   LEVEL: %d", "it": "PUNTI: %d   -   LIVELLO: %d"},
        "ne.name_line": {"en": "NAME:  %s", "it": "NOME:  %s"},
        "ne.del": {"en": "DEL", "it": "CANC"},
        "ne.end": {"en": "END", "it": "FINE"},
        "ne.ok": {"en": "OK", "it": "OK"},
        "ne.hint1": {
                "en": "ARROWS / JOYSTICK = MOVE    FIRE = SELECT",
                "it": "FRECCE / JOYSTICK = MOVIMENTO    FUOCO = SELEZIONA",
        },
        "ne.hint2": {
                "en": "OK OR END = CONFIRM AND SAVE TO HALL OF FAME",
                "it": "OK O FINE = CONFERMA E SALVA IN HALL OF FAME",
        },
        "ne.default_name": {"en": "HERO", "it": "EROE"},
        # ---------------- Pausa ----------------
        "pause.title": {"en": "PAUSE", "it": "PAUSA"},
        "pause.hint": {"en": "PRESS P TO RESUME", "it": "PREMI P PER CONTINUARE"},
        # ---------------- Schermata bonus (reliquie) ----------------
        "bonus.title": {"en": "CHOOSE YOUR RELIC", "it": "SCEGLI LA TUA RELIQUIA"},
        "bonus.subtitle": {
                "en": "A LEGENDARY TREASURE FROM THE FORGE",
                "it": "UN TESORO LEGGENDARIO DALLA FORGE",
        },
        "bonus.good_luck": {"en": "GOOD LUCK, HEROES!", "it": "BUONA FORTUNA, EROI!"},
        "bonus.player_choose": {
                "en": "PLAYER %d — CHOOSE YOUR RELIC",
                "it": "GIOCATORE %d — SCEGLI LA TUA RELIQUIA",
        },
        "bonus.chose": {"en": "PLAYER %d CHOSE: %s", "it": "IL GIOCATORE %d HA SCELTO: %s"},
        # TASK 51 (P1): conferma tenendo premuto il fuoco
        "bonus.hold_hint": {
                "en": "HOLD FIRE TO CONFIRM",
                "it": "TIENI PREMUTO IL FUOCO PER CONFERMARE",
        },
        "bonus.family_melee": {"en": "MELEE", "it": "MISCHIA"},
        "bonus.family_ranged": {"en": "RANGED", "it": "DISTANZA"},
        "bonus.family_armor": {"en": "ARMOR", "it": "ARMATURA"},
        "bonus.family_relic": {"en": "RELIC", "it": "RELIQUIA"},
        "bonus.stat_charges": {
                "en": "charges: %d   max energy: +2",
                "it": "cariche: %d   energia max: +2",
        },
        "bonus.stat_shots": {"en": "shots: %d", "it": "colpi: %d"},
        "bonus.stat_power": {"en": "power: %d", "it": "potenza: %d"},
        "bonus.tag_piercing": {"en": "piercing", "it": "perforante"},
        "bonus.tag_homing": {"en": "homing", "it": "a ricerca"},
        "bonus.tag_fan": {"en": "fan x%d", "it": "ventaglio x%d"},
        "bonus.tag_chain": {"en": "chain", "it": "a catena"},
        "bonus.tag_area": {"en": "area", "it": "ad area"},
        "bonus.tag_stuns": {"en": "stuns", "it": "stordisce"},
        "bonus.tag_vampiric": {"en": "vampiric", "it": "vampirica"},
        "bonus.hint_1p": {
                "en": "ARROWS / D-PAD: select    Z or ENTER (FIRE button): confirm",
                "it": "FRECCE / D-PAD: seleziona    Z o INVIO (tasto FUOCO): conferma",
        },
        "bonus.hint_2p": {
                "en": "A / D: select    ENTER or P2 FIRE button: confirm",
                "it": "A / D: seleziona    INVIO o tasto FUOCO P2: conferma",
        },
        # ---------------- Demo mode ----------------
        "demo.mode": {"en": "DEMO MODE", "it": "DEMO MODE"},
        "demo.exit": {"en": "PRESS ANY KEY TO EXIT", "it": "PREMI UN TASTO PER USCIRE"},
        # ---------------- TASK 51: card bonus (prima raccolta) ----------------
        "bonuscard.new": {"en": "NEW BONUS!", "it": "NUOVO BONUS!"},
        "bonuscard.hold": {"en": "HOLD FIRE TO CONTINUE", "it": "TIENI PREMUTO IL FUOCO PER CONTINUARE"},
        "bonuscard.demo": {"en": "HOW IT WORKS", "it": "COME FUNZIONA"},
        "bonuscard.uses": {"en": "USES", "it": "USI"},
        "bonuscard.uses.one": {"en": "Single use", "it": "Uso unico"},
        "bonuscard.uses.two": {"en": "2 throws", "it": "2 lanci"},
        "bonuscard.uses.perm": {"en": "Permanent", "it": "Permanente"},
        "bonuscard.uses.5strikes": {"en": "5 strikes", "it": "5 fulmini"},
        "bonuscard.uses.2shots": {"en": "2 shots", "it": "2 colpi"},
        "bonuscard.uses.3waves": {"en": "3 waves", "it": "3 ondate"},
        "bonuscard.uses.instant": {"en": "Instant", "it": "Immediata"},
        "bonuscard.damage": {"en": "DAMAGE", "it": "DANNO"},
        "bonuscard.dmg.high": {"en": "50% of max health", "it": "50% degli HP massimi"},
        "bonuscard.dmg.blast": {"en": "Area blast", "it": "Esplosione ad area"},
        "bonuscard.dmg.boss": {"en": "30% vs boss", "it": "30% vs boss"},
        "bonuscard.dmg.fry": {"en": "Fries enemies", "it": "Folgora i nemici"},
        "bonuscard.dmg.half": {"en": "50% to all enemies", "it": "50% a tutti i nemici"},
        "bonuscard.dmg.kill": {"en": "Instant kill", "it": "Morte istantanea"},
        "bonuscard.dmg.none": {"en": "No damage", "it": "Nessun danno"},
        "bonuscard.dmg.burn": {"en": "Burns on touch", "it": "Brucia al tocco"},
        "bonuscard.name.hammer": {"en": "Thor's Hammer", "it": "Martello di Thor"},
        "bonuscard.fx.hammer": {"en": "Throw it: it smashes through inner walls, opening shortcuts, and crushes enemies on its path.", "it": "Lancialo: sfonda i muri interni aprendo scorciatoie e schiaccia i nemici sul suo percorso."},
        "bonuscard.name.dynamite": {"en": "Dynamite", "it": "Dinamite"},
        "bonuscard.fx.dynamite": {"en": "A 7-second fuse starts the moment you pick it up. Throw it before it blows!", "it": "Una miccia di 7 secondi parte appena la raccogli. Lanciala prima che esploda!"},
        "bonuscard.name.scepter": {"en": "Lightning Staff", "it": "Bastone del Fulmine"},
        "bonuscard.fx.scepter": {"en": "Calls 5 lightning strikes that fry every enemy on screen.", "it": "Evoca 5 fulmini che folgorano tutti i nemici sullo schermo."},
        "bonuscard.name.boots": {"en": "Winged Boots", "it": "Stivali Alati"},
        "bonuscard.fx.boots": {"en": "Permanent speed boost. Quicksand can no longer slow you down.", "it": "Velocita' permanente. Le sabbie mobili non possono piu' rallentarti."},
        "bonuscard.name.potion": {"en": "Ghost Potion", "it": "Pozione Fantasma"},
        "bonuscard.fx.potion": {"en": "Drink it to become ethereal for 5 seconds and walk straight through walls.", "it": "Bevila per diventare evanescente per 5 secondi e attraversare i muri."},
        "bonuscard.name.freeze": {"en": "Ice Scroll", "it": "Pergamena del Ghiaccio"},
        "bonuscard.fx.freeze": {"en": "The fire button shoots a freezing ray: enemies stay frozen in ice for the rest of the level.", "it": "Il tasto di fuoco spara un raggio congelante: i nemici restano ghiacciati per tutto il livello."},
        "bonuscard.name.quake": {"en": "Earthquake Scroll", "it": "Pergamena del Terremoto"},
        "bonuscard.fx.quake": {"en": "Shakes the whole maze: every enemy loses half its health, the weakest ones are crushed.", "it": "Scuote tutto il labirinto: ogni nemico perde meta' energia, i piu' deboli vengono schiacciati."},
        "bonuscard.name.chasm": {"en": "Chasm Scroll", "it": "Pergamena delle Voragini"},
        "bonuscard.fx.chasm": {"en": "Opens magic chasms under the enemies in 3 waves. You are immune to them.", "it": "Apre voragini magiche sotto i nemici in 3 ondate. Tu sei immune."},
        "bonuscard.name.mine": {"en": "Bouncing Mine", "it": "Mina Rimbalzante"},
        "bonuscard.fx.mine": {"en": "A live mine bounces through the maze hunting enemies and deals big damage to the boss on impact.", "it": "Una mina attiva rimbalza nel labirinto a caccia di nemici e infligge un grosso danno al boss all'impatto."},
        "bonuscard.name.chalice": {"en": "Golden Chalice", "it": "Calice d'Oro"},
        "bonuscard.fx.chalice": {"en": "About 9 seconds of pure invincibility: enemies that touch you catch fire.", "it": "Circa 9 secondi di invincibilita' totale: i nemici che ti toccano prendono fuoco."},
        "bonuscard.name.knight": {"en": "Knight Statue", "it": "Statua del Cavaliere"},
        "bonuscard.fx.knight": {"en": "Summons an allied knight who charges into battle and fights by your side.", "it": "Evoca un cavaliere alleato che si lancia in battaglia e combatte al tuo fianco."},
        # TASK 64 (alleato alternato per livello): la statuetta evoca
        # l'UNICORNO nei livelli dispari e il CAVALLIERE nei livelli pari.
        "bonuscard.name.unicorn": {"en": "Unicorn Statue", "it": "Statua dell'Unicorno"},
        "bonuscard.fx.unicorn": {"en": "Summons an allied unicorn who charges into battle and fights by your side.", "it": "Evoca un unicorno alleato che si lancia in battaglia e combatte al tuo fianco."},
        # ---------------- Nemici (44) ----------------
        "enemy.zombie": {"en": "Zombie", "it": "Zombie"},
        "enemy.skeleton": {"en": "Skeleton", "it": "Scheletro"},
        "enemy.ghost": {"en": "Ghost", "it": "Fantasma"},
        "enemy.bat": {"en": "Bat", "it": "Pipistrello"},
        "enemy.spider": {"en": "Spider", "it": "Ragno"},
        "enemy.slime": {"en": "Slime", "it": "Melma"},
        "enemy.demon": {"en": "Demon", "it": "Demone"},
        "enemy.robot": {"en": "Robot", "it": "Robot"},
        "enemy.goblin": {"en": "Goblin", "it": "Goblin"},
        "enemy.orc": {"en": "Orc", "it": "Orco"},
        "enemy.wraith": {"en": "Wraith", "it": "Spettro"},
        "enemy.ghoul": {"en": "Ghoul", "it": "Ghoul"},
        "enemy.imp": {"en": "Imp", "it": "Imp"},
        "enemy.rat": {"en": "Rat", "it": "Ratto"},
        "enemy.cultist": {"en": "Cultist", "it": "Cultista"},
        "enemy.mimic": {"en": "Mimic", "it": "Mimico"},
        "enemy.wolf": {"en": "Wolf", "it": "Lupo"},
        "enemy.witch": {"en": "Witch", "it": "Strega"},
        "enemy.bone_golem": {"en": "Bone Golem", "it": "Golem d'Ossa"},
        "enemy.ash_serpent": {"en": "Ash Serpent", "it": "Serpente di Cenere"},
        "enemy.damned_knight": {"en": "Damned Knight", "it": "Cavaliere Dannato"},
        "enemy.mad_wizard": {"en": "Mad Wizard", "it": "Mago Folle"},
        "enemy.demonic_crow": {"en": "Demonic Crow", "it": "Corvo Demoniaco"},
        "enemy.tentacle": {"en": "Tentacle", "it": "Tentacolo"},
        "enemy.gargoyle": {"en": "Gargoyle", "it": "Gargoyle"},
        "enemy.well_spirit": {"en": "Well Spirit", "it": "Spirito del Pozzo"},
        "enemy.cursed_boar": {"en": "Cursed Boar", "it": "Cinghiale Maledetto"},
        "enemy.predator_fungus": {"en": "Predatory Fungus", "it": "Fungo Predatore"},
        "enemy.owlbear": {"en": "Owlbear", "it": "Orso-Gufo"},
        "enemy.gibbering_mouther": {"en": "Gibbering Mouther", "it": "Bocca Farfugliante"},
        "enemy.hellhound": {"en": "Hellhound", "it": "Mastino Infernale"},
        "enemy.barlgura": {"en": "Barlgura", "it": "Barlgura"},
        "enemy.troglodyte": {"en": "Troglodyte", "it": "Troglodita"},
        "enemy.bulette": {"en": "Bulette", "it": "Bulette"},
        "enemy.kuo_toa": {"en": "Kuo Toa", "it": "Kuo-Toa"},
        "enemy.basilisk": {"en": "Basilisk", "it": "Basilisco"},
        "enemy.cockatrice": {"en": "Cockatrice", "it": "Coccatrice"},
        "enemy.umber_hulk": {"en": "Umber Hulk", "it": "Umber Hulk"},
        "enemy.hook_horror": {"en": "Hook Horror", "it": "Orrore Uncinato"},
        "enemy.doppelganger": {"en": "Doppelganger", "it": "Doppelganger"},
        "enemy.ent": {"en": "Ent", "it": "Ent"},
        "enemy.cave_drake": {"en": "Cave Drake", "it": "Drago delle Caverne"},
        "enemy.lost_soul": {"en": "Lost Soul", "it": "Anima Perduta"},
        "enemy.possessed_soldier": {"en": "Possessed Soldier", "it": "Soldato Posseduto"},
        "enemy.generic": {"en": "Enemy", "it": "Nemico"},
        # ---------------- Mini-boss / mietitore ----------------
        "misc.miniboss": {"en": "Mini-Boss (type %d)", "it": "Mini-Boss (tipo %d)"},
        "misc.reaper_red": {"en": "The Crimson Reaper", "it": "Il Mietitore Cremisi"},
        "misc.reaper_immortal": {"en": "The Immortal Reaper", "it": "Il Mietitore Immortale"},
        # ---------------- Boss (banner stanza) ----------------
        "boss.stone_golem": {"en": "Stone Golem", "it": "Golem di Pietra"},
        "boss.lich": {"en": "Lich Necromancer", "it": "Lich Necromante"},
        "boss.demon": {"en": "Abyssal Demon", "it": "Demone Abissale"},
        "boss.spider": {"en": "Giant Spider", "it": "Ragno Gigante"},
        "boss.abomination": {"en": "Abomination", "it": "Abominio"},
        "boss.kraken": {"en": "Kraken", "it": "Kraken"},
        "boss.dragon": {"en": "Ancient Dragon", "it": "Drago Antico"},
        "boss.wraith_lord": {"en": "Wraith Lord", "it": "Signore degli Spettri"},
        "boss.vampire": {"en": "Vampire Lord", "it": "Signore dei Vampiri"},
        "boss.beholder": {"en": "Beholder", "it": "Beholder"},
        "boss.ghoul_lord": {"en": "Ghoul Lord", "it": "Signore dei Ghoul"},
        "boss.spectral_alpha": {"en": "Spectral Alpha Wolf", "it": "Lupo Alfa Spettrale"},
        "boss.cult_herald": {"en": "Cult Herald", "it": "Araldo del Culto"},
        "boss.colossal_mimic": {"en": "Colossal Mimic", "it": "Mimico Colossale"},
        "boss.rat_king": {"en": "Rat King", "it": "Re dei Ratti"},
        "boss.supreme_witch": {"en": "Supreme Witch", "it": "Strega Suprema"},
        "boss.twilight_knight": {"en": "Twilight Knight", "it": "Cavaliere del Crepuscolo"},
        # ---------------- Credits (sezioni + ruoli) ----------------
        "cr.title": {"en": "CREDITS", "it": "CREDITS"},
        "cr.design": {"en": "GAME DESIGN", "it": "GAME DESIGN"},
        "cr.programming": {"en": "PROGRAMMING", "it": "PROGRAMMAZIONE"},
        "cr.art": {"en": "ART & GRAPHICS", "it": "ARTE & GRAFICA"},
        "cr.audio": {"en": "AUDIO", "it": "AUDIO"},
        "cr.story": {"en": "STORY & WRITING", "it": "STORIA & TESTI"},
        "cr.qa": {"en": "QUALITY ASSURANCE", "it": "CONTROLLO QUALITÀ"},
        "cr.production": {"en": "PRODUCTION", "it": "PRODUZIONE"},
        "cr.thanks": {"en": "SPECIAL THANKS", "it": "RINGRAZIAMENTI SPECIALI"},
        "cr.lead_game_designer": {"en": "Lead Game Designer", "it": "Game Designer Principale"},
        "cr.senior_level_designer": {"en": "Senior Level Designer", "it": "Level Designer Senior"},
        "cr.gameplay_engineer": {"en": "Gameplay Engineer", "it": "Ingegnere del Gameplay"},
        "cr.balance_tuning": {"en": "Balance & Tuning", "it": "Bilanciamento & Tuning"},
        "cr.lead_programmer": {"en": "Lead Programmer", "it": "Programmatore Capo"},
        "cr.engine_architecture": {"en": "Engine Architecture", "it": "Architettura dell'Engine"},
        "cr.ai_pathfinding": {"en": "AI & Pathfinding", "it": "IA & Pathfinding"},
        "cr.physics_collision": {"en": "Physics & Collision", "it": "Fisica & Collisioni"},
        "cr.audio_engine": {"en": "Audio Engine", "it": "Motore Audio"},
        "cr.procedural_generation": {
                "en": "Procedural Generation",
                "it": "Generazione Procedurale",
        },
        "cr.bug_fixing": {"en": "Bug Fixing Specialist", "it": "Specialista Bug Fixing"},
        "cr.coffee_compiler": {
                "en": "Coffee to Code Compiler",
                "it": "Compilatore Caffè in Codice",
        },
        "cr.lead_artist": {"en": "Lead Artist", "it": "Artista Principale"},
        "cr.character_design": {"en": "Character Design", "it": "Design dei Personaggi"},
        "cr.monster_design": {"en": "Monster Design", "it": "Design dei Mostri"},
        "cr.boss_design": {"en": "Boss Design", "it": "Design dei Boss"},
        "cr.environment_art": {"en": "Environment Art", "it": "Ambientazioni"},
        "cr.pixel_art_director": {"en": "Pixel Art Director", "it": "Direttore Pixel Art"},
        "cr.sprite_animation": {"en": "Sprite Animation", "it": "Animazione Sprite"},
        "cr.uiux_design": {"en": "UI/UX Design", "it": "Design UI/UX"},
        "cr.special_effects": {"en": "Special Effects", "it": "Effetti Speciali"},
        "cr.music_composer": {"en": "Music Composer", "it": "Compositore Musicale"},
        "cr.sound_designer": {"en": "Sound Designer", "it": "Sound Designer"},
        "cr.voice_acting": {"en": "Voice Acting", "it": "Doppiaggio"},
        "cr.foley_artist": {"en": "Foley Artist", "it": "Artista Foley"},
        "cr.boom_operator": {"en": "Boom Operator", "it": "Operatore Boom"},
        "cr.story_writer": {"en": "Story Writer", "it": "Scrittore"},
        "cr.dialogue": {"en": "Dialogue", "it": "Dialoghi"},
        "cr.lore_master": {"en": "Lore Master", "it": "Maestro del Lore"},
        "cr.cutscene_director": {"en": "Cutscene Director", "it": "Regia delle Cutscene"},
        "cr.lead_qa_tester": {"en": "Lead QA Tester", "it": "QA Tester Capo"},
        "cr.senior_tester": {"en": "Senior Tester", "it": "Tester Senior"},
        "cr.bug_hunter": {"en": "Bug Hunter General", "it": "Cacciatore di Bug Generale"},
        "cr.crash_reproducer": {"en": "Crash Reproducer", "it": "Riproduttore di Crash"},
        "cr.edge_case_finder": {"en": "Edge Case Finder", "it": "Cercatore di Casi Limite"},
        "cr.executive_producer": {"en": "Executive Producer", "it": "Produttore Esecutivo"},
        "cr.project_manager": {"en": "Project Manager", "it": "Project Manager"},
        "cr.scrum_master": {"en": "Scrum Master", "it": "Scrum Master"},
        "cr.schedule_optimizer": {"en": "Schedule Optimizer", "it": "Ottimizzatore dei Tempi"},
        "cr.morale_officer": {"en": "Morale Officer", "it": "Ufficiale del Morale"},
        "cr.thanks_1": {"en": "To the universe for existing", "it": "All'universo, per esistere"},
        "cr.thanks_2": {
                "en": "For the coffee that kept us going",
                "it": "Al caffè che ci ha tenuti svegli",
        },
        "cr.thanks_3": {
                "en": "For the bugs that taught us patience",
                "it": "Ai bug che ci hanno insegnato la pazienza",
        },
        "cr.thanks_4": {"en": "To all the players", "it": "A tutti i giocatori"},
        "cr.thanks_5": {"en": "For believing in the dream", "it": "Per aver creduto nel sogno"},
        "cr.thanks_6": {"en": "For never giving up", "it": "Per non essersi mai arresi"},
        "cr.tools": {"en": "TOOLS & TECHNOLOGIES", "it": "STRUMENTI & TECNOLOGIE"},
        "cr.tool_build": {"en": "Build System", "it": "Sistema di Build"},
        "cr.tool_ai": {"en": "AI Image Generation", "it": "Generazione Immagini AI"},
        "cr.tool_vcs": {"en": "Version Control", "it": "Controllo di Versione"},
        "cr.tool_python": {"en": "Python Image Processing", "it": "Elaborazione Immagini Python"},
        "cr.published_by": {"en": "PUBLISHED BY", "it": "PUBBLICATO DA"},
        "cr.thank_you": {"en": "THANK YOU FOR PLAYING!", "it": "GRAZIE PER AVER GIOCATO!"},
        "cr.press_esc": {"en": "PRESS ESC TO RETURN", "it": "PREMI ESC PER TORNARE"},
        # ---------------- Varie ----------------
        "weakness": {"en": "WEAKNESS!", "it": "DEBOLEZZA!"},
        "loading": {"en": "Loading...", "it": "Caricamento..."},
}


## Lingua corrente (Language.ENGLISH di default — richiesta utente).
var language: int = Language.ENGLISH


## Codice ISO breve della lingua ("en" / "it").
func lang_code() -> String:
        return "it" if language == Language.ITALIAN else "en"


func is_italian() -> bool:
        return language == Language.ITALIAN


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
        # ConfigManager è un autoload che viene DOPO questo nel project.godot:
        # legge il file config.ini nel suo _ready, quindi qui è già popolato.
        if ConfigManager:
                var saved: int = int(ConfigManager.config.get("LANGUAGE", 0))
                language = Language.ITALIAN if saved == Language.ITALIAN else Language.ENGLISH
        _sync_mirror()


# ============================================================================
# API pubblica
# ============================================================================

## Testo localizzato per chiave (fallback: la chiave stessa, mai crash).
func t(key: String) -> String:
        var entry: Dictionary = TEXTS.get(key, {})
        if entry.is_empty():
                push_warning("I18n: chiave mancante '%s'" % key)
                return key
        var code: String = lang_code()
        if not entry.has(code):
                code = "en"
        return str(entry.get(code, key))


## Cambia lingua: aggiorna il mirror statico, PERSISTE in config.ini e
## notifica chi deve ridisegnare testi (menu, schermate).
func set_language(lang: int) -> void:
        if lang != Language.ENGLISH and lang != Language.ITALIAN:
                lang = Language.ENGLISH
        if lang == language:
                return
        language = lang
        _sync_mirror()
        if ConfigManager:
                ConfigManager.config["LANGUAGE"] = language
                ConfigManager.save_config()
        language_changed.emit(language)


## Toggle EN <-> IT (usato dalla voce LANGUAGE del sottomenu OPTIONS).
func toggle_language() -> void:
        set_language(Language.ITALIAN if language == Language.ENGLISH else Language.ENGLISH)


## Nome della lingua corrente mostrato nel menu ("ENGLISH" / "ITALIANO"
## in ENDOONIMO in entrambe le lingue: convenzione standard).
func language_display_name() -> String:
        return "ITALIANO" if language == Language.ITALIAN else "ENGLISH"


# ============================================================================
# Reliquie: campi bilingui già presenti nelle definizioni
# (name/short/desc = italiano, name_en/short_en/desc_en = inglese).
# ============================================================================

## Nome completo localizzato della reliquia (arma o armatura).
func relic_name(def: Dictionary) -> String:
        if def.is_empty():
                return "?"
        if is_italian():
                return str(def.get("name", "?"))
        return str(def.get("name_en", def.get("name", "?")))


## Nome breve localizzato (badge HUD / caselle bonus).
func relic_short(def: Dictionary) -> String:
        if def.is_empty():
                return "?"
        if is_italian():
                return str(def.get("short", "?"))
        return str(def.get("short_en", def.get("short", "?")))


## Descrizione localizzata (pannello della schermata bonus).
func relic_desc(def: Dictionary) -> String:
        if def.is_empty():
                return ""
        if is_italian():
                return str(def.get("desc", ""))
        return str(def.get("desc_en", def.get("desc", "")))


# ============================================================================
# Interni
# ============================================================================

## L'unico punto che scrive il mirror statico letto dalle funzioni static
## (GameConstants.get_weapon_name, Boss.get_boss_name, ...).
func _sync_mirror() -> void:
        C.ui_language = language
