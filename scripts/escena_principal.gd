extends Node2D

@onready var audio_stream_player: AudioStreamPlayer = $AudioStreamPlayer
@export var start_level: int = 1
@export var death_zone_y: float = 1200.0
@export var death_zone_width: float = 3000.0
@export var reveal_duration: float = 2.0
@export var fadeout_duration: float = 0.8

var current_level: Node2D
var current_level_num: int = 1
var death_area: Area2D
var waiting_for_click: bool = false
var next_level_to_load: int = -1
var fade_overlay: ColorRect
var is_fading_out: bool = false
var fade_progress: float = 0.0
var is_revealing: bool = false

var level_scenes: Array[String] = [
	"res://scenes/lvl_1.tscn",
	"res://scenes/lvl_2.tscn",
	"res://scenes/lvl_3.tscn",
    "res://scenes/lvl_4.tscn"
]

var musica_de_gameplay = preload("res://audio/echoofsadness.mp3")

func _ready() -> void:
	# Música de fondo
	audio_stream_player.stream = musica_de_gameplay
	audio_stream_player.play()
	
	# Inicialización del nivel
	_create_fade_overlay()
	_create_death_zone()
	load_level(start_level)

func _create_fade_overlay():
	fade_overlay = ColorRect.new()
	fade_overlay.color = Color(0, 0, 0, 0)
	fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_overlay.z_index = 100
	add_child(fade_overlay)

func _create_death_zone():
	death_area = Area2D.new()
	death_area.name = "DeathZone"
	death_area.collision_layer = 0
	death_area.collision_mask = 2
	
	var shape = RectangleShape2D.new()
	shape.size = Vector2(death_zone_width, 100)
	
	var collision = CollisionShape2D.new()
	collision.shape = shape
	
	death_area.add_child(collision)
	death_area.position = Vector2(death_zone_width / 2, death_zone_y)
	
	add_child(death_area)
	
	death_area.body_entered.connect(_on_death_zone_entered)

func _on_death_zone_entered(body: Node2D) -> void:
	if body and (body.is_in_group("player") or (body.name == "Personaje")):
		print("Personaje cayó fuera del nivel - Reiniciando")
		restart_current_level.call_deferred()

func load_level(level_num: int):
	if current_level:
		current_level.queue_free()
		current_level = null
	
	if level_num < 1 or level_num > level_scenes.size():
		print("Nivel ", level_num, " no existe")
		return
	
	current_level_num = level_num
	waiting_for_click = false
	next_level_to_load = -1
	
	fade_overlay.color.a = 0.0
	
	var brush = get_node_or_null("brush")
	if brush:
		brush.enabled = true
		if brush.has_method("reset_stroke"):
			brush.reset_stroke()
	
	var ink_meter = get_node_or_null("MedidorDeTinta")
	if ink_meter:
		ink_meter.refill_ink()
	
	var level_path = level_scenes[level_num - 1]
	var level_scene = load(level_path)
	if level_scene:
		current_level = level_scene.instantiate()
		add_child(current_level)
		
		if current_level.has_signal("level_completed"):
			current_level.level_completed.connect(_on_level_completed)
		
		print("Nivel ", level_num, " cargado")
	else:
		print("Error al cargar nivel: ", level_path)

func restart_current_level():
	load_level(current_level_num)

func get_current_level() -> Node2D:
	return current_level

func _process(delta):
	if is_fading_out:
		fade_progress += delta / fadeout_duration
		if fade_progress >= 1.0:
			fade_progress = 1.0
			is_fading_out = false
			if next_level_to_load > 0:
				print("Fade out completado - Cargando nivel ", next_level_to_load)
				load_level(next_level_to_load)
		fade_overlay.color.a = fade_progress
	
	if is_revealing:
		fade_progress += delta / reveal_duration
		if fade_progress >= 1.0:
			fade_progress = 1.0
			is_revealing = false
			waiting_for_click = true
			print("Capa revelada. Click para continuar...")
		fade_overlay.color.a = 1.0 - fade_progress

func _on_level_completed(next_level_num: int):
	load_level(next_level_num)
