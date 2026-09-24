extends Control

var controller: Node = null

func _draw() -> void:
	if controller != null and controller.has_method("draw_overlay"):
		controller.draw_overlay(self)
