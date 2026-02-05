extends StaticBody2D

var _win_triggered: bool = false

# Nivel script: detecta cuando el personaje entra en el area de victoria y lanza la secuencia de victoria
func _ready():
	# Conectar la señal si el nodo WinArea existe
	if has_node("WinArea"):
		var win_area := $WinArea
		if not win_area.is_connected("body_entered", Callable(self, "_on_win_area_body_entered")):
			win_area.connect("body_entered", Callable(self, "_on_win_area_body_entered"))

func _on_win_area_body_entered(body: Node) -> void:
	if not body or _win_triggered:
		return
	# Evitar que se dispare múltiples veces
	_win_triggered = true
	# Debug: mostrar qué cuerpo entró y si tiene win_sequence
	print("[Goal Platform] WinArea body_entered:", body.name, "has_win_sequence:", body.has_method("win_sequence"))
	
	# Revelar toda la máscara negra del escenario con efecto circular
	var static_body = get_node_or_null("../StaticBody2D")
	if static_body and static_body.has_method("start_full_reveal"):
		static_body.start_full_reveal(5.0, true)  # Duración de 5 segundos, revelado circular
		print("[Goal Platform] Iniciando revelado circular del escenario")
	
	# Llamar al método de personaje si existe
	if body.has_method("win_sequence"):
		# Pasamos duraciones por defecto: 1.5s para 'tusmuerto' y 2.0s para correr
		body.win_sequence(1.5, 2.0, 300.0)
