extends Camera3D

## Orbit camera for looking at the water.
##
##   LMB + mouse move  - orbit
##   wheel             - zoom
##   RMB + mouse move  - pan the target
##   space             - pause/resume animation (to inspect a single frame)
##   1 / 2 / 3         - camera presets: overview / beach level / the two pools

@export var target := Vector3(0.0, 0.0, 0.0)
@export var distance := 34.0
@export var yaw := 40.0
@export var pitch := -30.0

var _dragging := false
var _panning := false
var _paused := false


func _ready() -> void:
	_apply()


func _apply() -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var offset := Vector3(
		cos(p) * sin(y),
		sin(p),
		cos(p) * cos(y)) * distance
	# The camera sits on an orbit around the target and always faces it.
	look_at_from_position(target - offset, target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
			MOUSE_BUTTON_RIGHT:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				distance = maxf(2.0, distance - 1.0)
				_apply()
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = minf(90.0, distance + 1.0)
				_apply()
	elif event is InputEventMouseMotion:
		if _dragging:
			yaw -= event.relative.x * 0.3
			pitch = clampf(pitch - event.relative.y * 0.3, -85.0, 85.0)
			_apply()
		elif _panning:
			var right := global_transform.basis.x
			var fwd := global_transform.basis.y
			target -= (right * event.relative.x + fwd * -event.relative.y) * distance * 0.002
			_apply()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_paused = not _paused
				# Freezing time freezes TIME in the shader - handy for judging
				# the caustics/foam shapes or taking a screenshot.
				Engine.time_scale = 0.0 if _paused else 1.0
			KEY_1:
				# Overview of all three basins.
				distance = 40.0
				yaw = 35.0
				pitch = -42.0
				target = Vector3(0.0, 0.0, 0.0)
				_apply()
			KEY_2:
				# Low over the lake beach - shore glow and foam up close.
				distance = 10.0
				yaw = 118.0
				pitch = -8.0
				target = Vector3(-4.0, 0.3, 3.0)
				_apply()
			KEY_3:
				# The two pools side by side.
				distance = 17.0
				yaw = 90.0
				pitch = -42.0
				target = Vector3(13.0, 0.0, 0.0)
				_apply()
