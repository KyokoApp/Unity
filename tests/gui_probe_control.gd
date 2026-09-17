class_name GuiProbeControl
extends Control

## Control pasif untuk menyelidiki routing touch di GUI (headless CI).
var last_event := ""
var fired := false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		fired = true
		last_event = "touch idx=%d pos=%s" % [event.index, str(event.position)]
