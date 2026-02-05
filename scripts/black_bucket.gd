extends Node2D

@export var run_speed := 200.0
@export var exit_margin := 100.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

signal bucket_finished

func _ready():
	print("Sprite encontrado:", sprite)
	sprite.play("idle")

func run_away():
	sprite.play("run_away")

func _process(delta):
	if sprite.animation == "run_away":
		position.x += run_speed * delta
