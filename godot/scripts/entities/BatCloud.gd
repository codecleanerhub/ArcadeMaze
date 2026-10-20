## BatCloud.gd - TASK 32: nube di pipistrelli (evento casuale).
## =============================================================
## Uno sciame di 5 pipistrelli che spawna in un punto casuale del
## labirinto (lontano dai player) e VOLA LIBERO SOPRA I MURI verso il
## player vivo piu' vicino (movimento a pixel, non grid-locked: e' una
## nube che fluttua sopra il dungeon, con wobble sinusoidale).
##
##   * MORSO: se il centro dello sciame arriva a contatto di un player
##     grounded (salto/ghost/calice/soul_pending esonerati), il player
##     subisce il 20% dell'energia max come danno AMBIENTALE (bypass
##     armature). Dopo il morso lo sciame FLEE via per ~0.9s: niente
##     drain a raffica, il player ha tempo di reagire.
##   * ABBATTUTO: due colpi di proiettile lo disperdono (+5000 punti al
##     tiratore). Al primo colpo perde un pipistrello (sprite via +
##     squittio): feedback chiaro che ci vuole solo un altro colpo.
##   * SCADENZA: dopo 20s di caccia svolazza via da sola (angolo alto
##     piu' vicino) e l'evento e' consumato.
##   * AUDIO: battito d'ali periodico (~700ms, debounce), stridio al
##     morso/al colpo/alla dispersione.
##
## Il nodo e' creato e programmato dal MainGameController
## (_update_bat_cloud): spawn lontano da ogni player vivo, 1 evento per
## livello (2 dal livello 31). Rollback: GameConstants.BATS_ENABLED.
extends Node2D
class_name BatCloud

const C = preload("res://scripts/core/GameConstants.gd")

## Sprite del pipistrello generato ad hoc (Task 32): ali spiegate,
## 256x168 — il flap e' procedurale (oscillazione della scala Y, alias
## "ali che si richiudono"), cosi' lo sciame vola senza sheet multi-frame.
const BAT_SPRITE := "res://assets/sprites/hazards/bat.png"
const BAT_DRAW_PX: float = 46.0

## Stati: CHASE (insegue), FLEE (rimbalzo post-morso), DYING (dispersione
## a beneficio del tiratore), LEAVE (scadenza: vola via).
enum CloudState { CHASE, FLEE, DYING, LEAVE }

var state: int = CloudState.CHASE
var hp: int = C.BAT_CLOUD_HITS_TO_DIE
var lifetime_ms: float = float(C.BAT_CLOUD_LIFETIME_MS)
var state_ms: float = 0.0
var bite_cd_ms: float = 0.0
var flee_dir: Vector2 = Vector2.LEFT
var flap_ms: float = 0.0
var gone: bool = false

## Pipistrelli: [{sprite: Sprite2D, offset: Vector2, phase: float}]
var bats: Array[Dictionary] = []

var _tex: Texture2D = null


func _ready() -> void:
        _tex = load(BAT_SPRITE)
        # 5 pipistrelli attorno al centro, offset stabili + fasi sfasate
        # (il flap non batte mai all'unisono: e' uno sciame).
        var offsets: Array[Vector2] = [
                Vector2(0.0, 0.0), Vector2(-26.0, -14.0), Vector2(26.0, -12.0),
                Vector2(-18.0, 16.0), Vector2(20.0, 18.0),
        ]
        for i in offsets.size():
                var s := Sprite2D.new()
                s.texture = _tex
                var k: float = BAT_DRAW_PX / float(_tex.get_width())
                s.scale = Vector2(k, k)
                s.position = offsets[i]
                add_child(s)
                bats.append({"sprite": s, "offset": offsets[i],
                                "phase": float(i) * 0.9})
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.BAT_SCREECH)
        z_index = 50  # sopra entita' e hazard: la nube vola piu' in alto


## update_cloud: chiamato dal MainGameController ogni frame (solo maze).
## `players` = array di CharacterBody2D vivi/visibili.
func update_cloud(delta_ms: float, players: Array) -> void:
        if gone:
                return
        state_ms += delta_ms
        bite_cd_ms = maxf(0.0, bite_cd_ms - delta_ms)
        flap_ms -= delta_ms
        if flap_ms <= 0.0 and state != CloudState.DYING:
                flap_ms = 700.0
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.BAT_FLAP)

        var step: float = C.BAT_CLOUD_SPEED * (delta_ms / 16.6667)
        var target: CharacterBody2D = _nearest_player(players)

        # i colpi dei player abbattono lo sciame (in ogni stato attivo)
        if state == CloudState.CHASE or state == CloudState.FLEE:
                _check_projectiles(players)

        match state:
                CloudState.CHASE:
                        lifetime_ms -= delta_ms
                        if lifetime_ms <= 0.0:
                                _start_leaving()
                                return
                        if target != null:
                                var dir: Vector2 = (target.position - position).normalized()
                                position += dir * step
                        _try_bite(players)
                CloudState.FLEE:
                        position += flee_dir * step * 1.4
                        if state_ms >= float(C.BAT_CLOUD_FLEE_MS):
                                state = CloudState.CHASE
                                state_ms = 0.0
                CloudState.DYING:
                        # dispersione: i superstiti schizzano verso l'esterno
                        for b in bats:
                                if is_instance_valid(b["sprite"]):
                                        b["sprite"].position += b["offset"].normalized() \
                                                        * step * 3.0
                                        b["sprite"].modulate.a = maxf(0.0,
                                                        1.0 - state_ms / 600.0)
                        if state_ms >= 600.0:
                                gone = true
                CloudState.LEAVE:
                        position += flee_dir * step * 1.6
                        for b in bats:
                                if is_instance_valid(b["sprite"]):
                                        b["sprite"].modulate.a = maxf(0.0,
                                                        1.0 - state_ms / 900.0)
                        if state_ms >= 900.0:
                                gone = true

        _animate_bats(delta_ms)


## True quando lo sciame e' definitivamente concluso (morto o volato via).
func is_gone() -> bool:
        return gone


## HP residui (per test/debug).
func get_hp() -> int:
        return hp


# --- interni ---------------------------------------------------------------

func _nearest_player(players: Array) -> CharacterBody2D:
        var best: CharacterBody2D = null
        var best_d: float = INF
        for p in players:
                var d: float = p.position.distance_squared_to(position)
                if d < best_d:
                        best_d = d
                        best = p
        return best


func _try_bite(players: Array) -> void:
        if bite_cd_ms > 0.0:
                return
        for p in players:
                if p.soul_pending or p.is_ghost() or p.is_jumping() \
                                or p.is_invulnerable():
                        continue
                if p.position.distance_to(position) < 30.0:
                        var dmg: int = maxi(1, int(round(
                                        p.max_energy * C.BAT_CLOUD_PLAYER_DAMAGE_PCT)))
                        p.take_hazard_damage(dmg)
                        if AudioManager:
                                AudioManager.play_sound(
                                                AudioManager.SoundType.BAT_SCREECH)
                        if EffectsManager:
                                EffectsManager.screen_shake(3.0, 0.2)
                        # rimbalzo: lo sciame si allontana mezzo secondo
                        state = CloudState.FLEE
                        state_ms = 0.0
                        bite_cd_ms = float(C.BAT_CLOUD_BITE_CD_MS)
                        flee_dir = (position - p.position).normalized()
                        if flee_dir == Vector2.ZERO:
                                flee_dir = Vector2.UP
                        return


## Colpo di proiettile: ritorna true se il proiettile e' stato consumato.
## (chiamato dal controller nel loop proiettili, oppure usato dai test)
func take_projectile_hit(shooter: CharacterBody2D) -> bool:
        if state == CloudState.DYING or state == CloudState.LEAVE or gone:
                return false
        hp -= 1
        if hp <= 0:
                state = CloudState.DYING
                state_ms = 0.0
                if AudioManager:
                        AudioManager.play_sound(AudioManager.SoundType.BAT_SCREECH)
                if EffectsManager:
                        EffectsManager.screen_shake(4.0, 0.25)
                if shooter != null:
                        shooter.add_score(C.BAT_CLOUD_KILL_POINTS)
                return true
        # primo colpo: un pipistrello cade dallo sciame (feedback visivo)
        for i in range(bats.size() - 1, -1, -1):
                if is_instance_valid(bats[i]["sprite"]):
                        bats[i]["sprite"].queue_free()
                        bats.remove_at(i)
                        break
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.BAT_SCREECH)
        return true


## Scansione dei proiettili dei player: chi entra nel raggio dello sciame
## viene consumato e conta come colpo (il tiratore si prende i punti se
## e' il colpo finale).
func _check_projectiles(players: Array) -> void:
        for p in players:
                for proj in p.projectiles:
                        if not proj.get("active", false):
                                continue
                        var pos: Vector2 = proj.get("pos", Vector2.INF)
                        if pos.distance_to(position) < 34.0:
                                proj["active"] = false
                                take_projectile_hit(p)
                                if state == CloudState.DYING:
                                        return


func _start_leaving() -> void:
        state = CloudState.LEAVE
        state_ms = 0.0
        # vola verso l'angolo piu' lontano dal player piu' vicino
        var p: CharacterBody2D = _nearest_player(_players_ref)
        var corner: Vector2 = Vector2(60.0, 100.0)
        if p != null:
                if p.position.x > 960.0:
                        corner.x = 1860.0
                if p.position.y > 540.0:
                        corner.y = 1020.0
        flee_dir = (corner - position).normalized()
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.BAT_SCREECH)


## Riferimento ai player impostato dal controller (per _start_leaving).
var _players_ref: Array = []


func set_players_ref(players: Array) -> void:
        _players_ref = players


func _animate_bats(delta_ms: float) -> void:
        ## Flap procedurale: ogni pipistrello oscilla la scala Y (le ali si
        ## richiudono e si riaprono) con la propria fase; lo sciame intero
        ## ondeggia (wobble) attorno al centro.
        var t: float = state_ms / 1000.0
        var base_k: float = BAT_DRAW_PX / float(_tex.get_width())
        for b in bats:
                if not is_instance_valid(b["sprite"]):
                        continue
                var phase: float = float(b["phase"])
                # flap: scala Y tra 1.0 (ali spiegate) e 0.55 (richiuse)
                var flap_k: float = 0.775 + 0.225 * sin(t * 13.0 + phase)
                b["sprite"].scale = Vector2(base_k, base_k * flap_k)
                var wob: Vector2 = Vector2(sin(t * 5.0 + phase) * 4.0,
                                cos(t * 4.0 + phase * 1.3) * 5.0)
                b["sprite"].position = b["offset"] + wob
                # leggera inclinazione in curva dello sciame
                b["sprite"].rotation = sin(t * 6.0 + phase) * 0.12
