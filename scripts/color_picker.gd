extends Area2D

var main_sprite: Sprite2D

func _ready():
	main_sprite = get_tree().root.get_node_or_null("EscenaPrincipal/Sprite2D")
	
	# Conectar señal de input en el Area2D
	input_event.connect(_on_input_event)

func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int):
	"""Detecta clicks dentro del ColorPickerArea"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick_color_at(event.position)

func _pick_color_at(click_pos: Vector2):
	"""Lee el color del sprite en la posición del click"""
	if not main_sprite or not main_sprite.texture:
		print("No se encontró el sprite principal")
		return
	
	# Convertir posición global a coordenadas locales del sprite
	var local_pos = main_sprite.to_local(click_pos)
	
	# Convertir a coordenadas de textura (teniendo en cuenta el offset del sprite)
	var texture_size = main_sprite.texture.get_size()
	var texture_pos = local_pos + texture_size / 2.0
	
	# Validar que esté dentro de los límites
	if texture_pos.x < 0 or texture_pos.y < 0 or texture_pos.x >= texture_size.x or texture_pos.y >= texture_size.y:
		return
	
	# Obtener el color del píxel
	var image = main_sprite.texture.get_image()
	if not image:
		print("No se pudo obtener la imagen de la textura")
		return
	
	var color = image.get_pixel(int(texture_pos.x), int(texture_pos.y))
	
	# Obtener el brush del nivel actual (no de escena_principal)
	var escena_principal = get_tree().root.get_node_or_null("EscenaPrincipal")
	if not escena_principal:
		print("No se encontró EscenaPrincipal")
		return
	
	# Obtener el brush del nivel actual
	var level = null
	if escena_principal.has_method("get_current_level"):
		level = escena_principal.call("get_current_level")
	else:
		level = escena_principal.current_level

	var brush = null
	if level:
		brush = level.get_node_or_null("brush")
	
	if not brush:
		print("No se pudo encontrar el brush del nivel actual")
		return
	
	# Cambiar color del brush del nivel
	if brush.has_method("set_brush_color"):
		brush.set_brush_color(color)
	else:
		brush.brush_color = color
		brush.tap_particles_color = color
		brush.paint_particles_color = color
		if brush.tap_particles:
			brush.tap_particles.color = color
		if brush.drag_particles:
			brush.drag_particles.color = color

	# Cambiar color del trazo (preview) en el paint_target del brush
	if "paint_target" in brush and brush.paint_target:
		if brush.paint_target.has_method("set_preview_color"):
			brush.paint_target.set_preview_color(color)
		else:
			if "preview_color" in brush.paint_target:
				brush.paint_target.preview_color = color
	
	print("Color seleccionado: ", color)



