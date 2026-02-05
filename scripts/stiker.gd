extends Area2D

@export var scale_multiplier := 1.3
@export var grow_time := 0.2
@export var shrink_time := 0.3

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var original_scale: Vector2
var collected := false

func _ready():
	original_scale = sprite.scale
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if collected:
		return

	if body.is_in_group("player"):
		collected = true
		collect_self()

func collect_self():
	collision.disabled = true

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)

	tween.tween_property(
		sprite,
		"scale",
		original_scale * scale_multiplier,
		grow_time
	)

	tween.tween_property(
		sprite,
		"scale",
		Vector2.ZERO,
		shrink_time
	)

	# 💀 GUARANTEED self-destruction
	tween.tween_callback(queue_free)
