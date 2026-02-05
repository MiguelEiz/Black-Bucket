extends Node2D

signal level_completed(next_level_num: int)

@export var level_number: int = 1
@export var exit_delay: float = 1.0

var personaje: CharacterBody2D
var exit_triggered: bool = false

func _ready():
	# Buscar el personaje en la escena
	personaje = get_node_or_null("Personaje")
	
	# Crear área de salida a la derecha del Sprite2D principal
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		var exit_area = Area2D.new()
		exit_area.name = "ExitArea"
		exit_area.collision_layer = 0
		exit_area.collision_mask = 2  # Detectar al personaje (capa 2)
		
		# Crear shape para el área de salida
		var shape = RectangleShape2D.new()
		shape.size = Vector2(100, 2000)  # Área vertical amplia a la derecha
		
		var collision = CollisionShape2D.new()
		collision.shape = shape
		
		exit_area.add_child(collision)
		
		# Posicionar el área a la derecha del sprite
		var sprite_bounds = sprite.texture.get_size() * sprite.scale
		exit_area.position = Vector2(sprite.position.x + sprite_bounds.x / 2 + 50, sprite.position.y)
		
		add_child(exit_area)
		
		# Conectar señal
		exit_area.body_entered.connect(_on_exit_area_entered)

func _on_exit_area_entered(body: Node2D) -> void:
	if exit_triggered:
		return
	
	# Verificar que sea el personaje y que esté en win_sequence
	if body == personaje and personaje.get("victoria"):
		exit_triggered = true
		await get_tree().create_timer(exit_delay).timeout
		_complete_level()

func _complete_level() -> void:
	level_completed.emit(level_number + 1)
