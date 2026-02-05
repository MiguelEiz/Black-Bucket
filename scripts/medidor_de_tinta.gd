extends Control
@onready var progress_bar: ProgressBar = $ProgressBar

@export var ink_per_click: float = 0.2   # Tinta consumida al hacer click
@export var ink_per_circle: float = 0.1  # Tinta consumida por cada círculo pintado

func _ready():
	progress_bar.value = 100.0

func consume_ink_on_click():
	"""Consume tinta cuando se hace click"""
	progress_bar.value -= ink_per_click
	if progress_bar.value < 0:
		progress_bar.value = 0

func consume_ink_on_circles(circles: int):
	"""Consume tinta según la cantidad de círculos pintados"""
	progress_bar.value -= ink_per_circle * circles
	if progress_bar.value < 0:
		progress_bar.value = 0

func get_remaining_ink() -> float:
	"""Devuelve la tinta restante"""
	return progress_bar.value

func is_out_of_ink() -> bool:
	"""Devuelve true si no hay tinta"""
	return progress_bar.value <= 0

func refill_ink():
	"""Recarga la tinta al máximo"""
	progress_bar.value = 100.0
