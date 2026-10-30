## fake_carrier_jump.gd — TASK 101 test: CharacterBody2D con le API minime
## che ElementalBarrel tocca sul portatore (visible/lives/soul_pending/
## position + jump_offset per il follow del salto).
extends CharacterBody2D

var lives: int = 3
var soul_pending: bool = false
var jump_offset: float = 0.0
