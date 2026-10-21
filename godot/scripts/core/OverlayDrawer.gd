## OverlayDrawer.gd - Node2D che disegna gli overlay SOPRA il maze.
## Delega il drawing al MainGameController passando se stesso come CanvasItem.
extends Node2D

var controller: Node = null

func _draw() -> void:
        if controller != null and controller.has_method("_draw_overlay"):
                controller._draw_overlay(self)
