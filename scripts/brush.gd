extends Node2D

@export var paint_target_path: NodePath
@export var brush_size: float = 40.0
@export var brush_opacity: float = 1.0
@export var hide_system_cursor: bool = true
@export var tip_offset: Vector2 = Vector2(-20, 15)
@export var stroke_spacing: float = 10.0
@export var show_tip_indicator: bool = true
@export var tip_indicator_radius: float = 10.0
@export var enabled: bool = true
@export var ink_consumption_per_stroke: float = 5.0

@export var tap_sound_path: String = "res://audio/apoyar pincel.mp3"
@export var drag_sound_path: String = "res://audio/arrastrar pincel.mp3"

@export var tap_particles_enabled: bool = true
@export var tap_particles_amount: int = 3
@export var tap_particles_lifetime: float = 0.5
@export var tap_particles_speed: float = 20.0
@export var tap_particles_spread: float = 50.0
@export var tap_particles_gravity: Vector2 = Vector2(0, 20)
@export var tap_particles_color: Color = Color(0.9, 0.65, 0.063, 1.0)
@export var tap_particles_scale_min: float = 2.0
@export var tap_particles_scale_max: float = 10.0

@export var paint_particles_enabled: bool = true
@export var paint_particles_amount: int = 5
@export var paint_particles_lifetime: float = 0.8
@export var paint_particles_speed: float = 20.0
@export var paint_particles_spread: float = 20.0
@export var paint_particles_gravity: Vector2 = Vector2(0, 400)
@export var paint_particles_color: Color = Color(1.0, 0.85, 0.2, 1.0)
@export var paint_particles_scale_min: float = 2.5
@export var paint_particles_scale_max: float = 3.5

@export var motion_min_distance: float = 1.5
@export var motion_stop_delay: float = 0.08

@onready var brush_sprite: Sprite2D = $Sprite2D
var base_brush_pos: Vector2 = Vector2.ZERO
var tap_particles: CPUParticles2D
var drag_particles: CPUParticles2D
var tap_player: AudioStreamPlayer2D
var drag_player: AudioStreamPlayer2D
var ink_meter: Control = null

var is_painting: bool = false
var paint_target: Node
var last_paint_pos: Vector2
var last_motion_pos: Vector2
var last_motion_msec: int = 0
var stroke_length: float = 0.0
var stroke_used: bool = false  # Solo se permite un trazo por nivel
var brush_color: Color = Color(0.9, 0.65, 0.063, 1.0)  # Color dinámico para color_picker

func _ready():
	if hide_system_cursor:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	if brush_sprite:
		base_brush_pos = brush_sprite.position
		brush_sprite.position = -tip_offset

	if paint_target_path != NodePath(""):
		paint_target = get_node(paint_target_path)
	else:
		paint_target = get_parent()
	
	# Buscar medidor de tinta en la escena principal
	var escena_principal = get_tree().root.get_node_or_null("EscenaPrincipal")
	if escena_principal:
		ink_meter = escena_principal.get_node_or_null("MedidorDeTinta")

	tap_player = AudioStreamPlayer2D.new()
	tap_player.stream = load(tap_sound_path)
	add_child(tap_player)

	drag_player = AudioStreamPlayer2D.new()
	drag_player.stream = load(drag_sound_path)
	if drag_player.stream is AudioStreamMP3:
		drag_player.stream.loop = true
	add_child(drag_player)

	if tap_particles_enabled:
		tap_particles = CPUParticles2D.new()
		tap_particles.emitting = false
		tap_particles.one_shot = true
		tap_particles.amount = tap_particles_amount
		tap_particles.lifetime = tap_particles_lifetime
		tap_particles.initial_velocity_min = tap_particles_speed * 0.7
		tap_particles.initial_velocity_max = tap_particles_speed
		tap_particles.spread = tap_particles_spread
		tap_particles.gravity = tap_particles_gravity
		tap_particles.color = brush_color
		tap_particles.scale_amount_min = tap_particles_scale_min
		tap_particles.scale_amount_max = tap_particles_scale_max
		add_child(tap_particles)

	if paint_particles_enabled:
		drag_particles = CPUParticles2D.new()
		drag_particles.emitting = false
		drag_particles.one_shot = false
		drag_particles.amount = paint_particles_amount
		drag_particles.lifetime = paint_particles_lifetime
		drag_particles.initial_velocity_min = paint_particles_speed * 0.7
		drag_particles.initial_velocity_max = paint_particles_speed
		drag_particles.spread = paint_particles_spread
		drag_particles.gravity = paint_particles_gravity
		drag_particles.color = brush_color
		drag_particles.scale_amount_min = paint_particles_scale_min
		drag_particles.scale_amount_max = paint_particles_scale_max
		add_child(drag_particles)

func set_brush_color(new_color: Color) -> void:
	brush_color = new_color
	tap_particles_color = new_color
	paint_particles_color = new_color
	if tap_particles:
		tap_particles.color = new_color
	if drag_particles:
		drag_particles.color = new_color
	queue_redraw()

func _exit_tree():
	if hide_system_cursor:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(_delta):
	global_position = get_global_mouse_position()
	if brush_sprite:
		brush_sprite.position = -tip_offset
	if show_tip_indicator:
		queue_redraw()
	if is_painting:
		var now_msec = Time.get_ticks_msec()
		if last_motion_msec > 0 and (now_msec - last_motion_msec) > int(motion_stop_delay * 1000.0):
			_set_drag_active(false)

func _draw():
	if show_tip_indicator:
		var tip_color = brush_color
		tip_color.a = 1.0
		draw_circle(Vector2.ZERO, tip_indicator_radius, tip_color)

func _input(event):
	# Bloquear si ya se usó el trazo
	if stroke_used:
		return
	
	# Verificar si hay tinta disponible
	if ink_meter and ink_meter.is_out_of_ink():
		if is_painting:
			# Si se queda sin tinta mientras pinta, terminar el trazo
			is_painting = false
			if paint_target and paint_target.has_method("commit_preview"):
				paint_target.call("commit_preview", brush_size, brush_opacity)
			_set_drag_active(false)
		return
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_painting = event.pressed
		if is_painting:
			stroke_length = 0.0
			if tap_player and tap_player.stream:
				tap_player.play()
			last_paint_pos = get_global_mouse_position()
			last_motion_pos = last_paint_pos
			last_motion_msec = Time.get_ticks_msec()
			if paint_target and paint_target.has_method("start_preview_stroke"):
				paint_target.call("start_preview_stroke")
			if tap_particles:
				tap_particles.color = brush_color
				tap_particles.emitting = true
				tap_particles.restart()
			paint_now()
		else:
			last_paint_pos = Vector2.ZERO
			last_motion_msec = 0
			if paint_target and paint_target.has_method("commit_preview"):
				paint_target.call("commit_preview", brush_size, brush_opacity)
			_set_drag_active(false)
			# Marcar trazo como usado solo si se pintó algo
			if stroke_length > 0.0:
				stroke_used = true
	elif event is InputEventMouseMotion and is_painting:
		var current_pos = get_global_mouse_position()
		if last_motion_pos.distance_to(current_pos) >= motion_min_distance:
			last_motion_pos = current_pos
			last_motion_msec = Time.get_ticks_msec()
			_set_drag_active(true)
		paint_now()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			if paint_target and paint_target.has_method("undo_last_stroke"):
				paint_target.call("undo_last_stroke")

func _set_drag_active(active: bool):
	if drag_particles:
		if active:
			drag_particles.color = brush_color
		drag_particles.emitting = active
	if drag_player and drag_player.stream:
		if active and not drag_player.playing:
			drag_player.play()
		elif not active and drag_player.playing:
			drag_player.stop()

func paint_now():
	if paint_target and paint_target.has_method("preview_at_global_position"):
		var current_pos = get_global_mouse_position()
		if last_paint_pos == Vector2.ZERO:
			last_paint_pos = current_pos
			paint_target.call("preview_at_global_position", current_pos, brush_size)
			return

		var distance = last_paint_pos.distance_to(current_pos)
		
		# Consumir tinta en tiempo real por la distancia pintada
		if ink_meter and distance > 0:
			var ink_to_consume = distance * ink_consumption_per_stroke / 100.0
			ink_meter.progress_bar.value -= ink_to_consume
			if ink_meter.progress_bar.value < 0:
				ink_meter.progress_bar.value = 0
		
		stroke_length += distance
		var step = max(1.0, stroke_spacing)
		var steps = int(ceil(distance / step))
		for i in range(steps + 1):
			var t = float(i) / float(max(1, steps))
			var pos = last_paint_pos.lerp(current_pos, t)
			paint_target.call("preview_at_global_position", pos, brush_size)
		last_paint_pos = current_pos

func reset_stroke():
	"""Resetea el trazo para permitir pintar en el siguiente nivel"""
	stroke_used = false
	stroke_length = 0.0
	is_painting = false
