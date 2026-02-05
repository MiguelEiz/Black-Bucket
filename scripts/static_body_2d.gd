extends StaticBody2D

@onready var sprite: Sprite2D = $Sprite2D

# Máscara que guarda las áreas reveladas por el jugador
var reveal_mask: Image
var reveal_texture: ImageTexture
var original_bitmap: BitMap
var image_size: Vector2i

# Trazo previo (amarillo)
@export var preview_color: Color = Color(1, 1, 0, 0.8)
var preview_mask: Image
var preview_texture: ImageTexture
var preview_layer: Sprite2D
var preview_dirty_rect: Rect2i
var has_preview: bool = false
var stroke_points: Array[Vector2] = []
var last_preview_point: Vector2
@export var stroke_record_min_distance: float = 2.0

# Revelado animado
@export var reveal_points_per_frame: int = 20
@export var reveal_points_per_second: float = 200.0
var reveal_queue: Array[Vector2] = []
var reveal_active: bool = false
var reveal_brush_size: float = 0.0
var reveal_brush_opacity: float = 1.0
var last_preview_brush_size: float = 0.0
var reveal_accumulator: float = 0.0
var reveal_total_points: int = 0
var is_undoing: bool = false
var stroke_history: Array[Dictionary] = []
var undo_queue: Array[Vector2] = []

# Capa negra que cubre todo
var black_layer: Sprite2D

# Optimización GPU
@export var use_gpu_rendering: bool = true

# Suavizado por shader (GPU)
@export var enable_soft_shader: bool = true
@export var soft_shader_radius: float = 3.5
@export var soft_shader_strength: float = 0.95

# Actualización de colliders
@export var enable_colliders: bool = false
@export var collider_downscale_size: int = 512
@export var update_colliders_while_painting: bool = false
@export var collider_update_interval: float = 0.25
@export var collider_update_delay_after_reveal: float = 0.5
var collider_dirty: bool = false
var collider_timer: float = 0.0
var collider_pending_update: bool = false
var collider_delay_timer: float = 0.0

# Animación de revelado total
signal full_reveal_completed
var full_reveal_active: bool = false
var full_reveal_speed: float = 0.5  # Segundos para revelar todo
var full_reveal_progress: float = 0.0
var full_reveal_circular: bool = false  # Si true, hace revelado circular
var full_reveal_center: Vector2 = Vector2.ZERO  # Centro del círculo de revelado
var full_reveal_max_radius: float = 0.0  # Radio máximo para cubrir toda la imagen

func _ready():
	# Obtener imagen del Sprite2D
	var texture = sprite.texture
	var image = texture.get_image()
	image_size = image.get_size()
	
	if use_gpu_rendering:
		# Ocultar sprite original, usaremos shader
		sprite.visible = false
	else:
		sprite.visible = true
	
	# Crear bitmap original
	original_bitmap = BitMap.new()
	original_bitmap.create_from_image_alpha(image)
	
	# Inicializar máscara de revelado (totalmente negra al inicio)
	reveal_mask = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
	reveal_mask.fill(Color(0, 0, 0, 1))  # Todo negro opaco = nada revelado
	
	# Crear textura de la máscara
	reveal_texture = ImageTexture.create_from_image(reveal_mask)
	
	if use_gpu_rendering:
		# Crear sprite con shader que combina imagen original y máscara
		black_layer = Sprite2D.new()
		black_layer.texture = sprite.texture
		black_layer.material = _create_reveal_shader_material()
		_sync_overlay_transform(black_layer)
		black_layer.visible = true
		add_child(black_layer)
	else:
		# Método antiguo: capa negra encima
		black_layer = Sprite2D.new()
		black_layer.texture = reveal_texture
		if enable_soft_shader:
			black_layer.material = _create_soft_mask_material()
		_sync_overlay_transform(black_layer)
		black_layer.visible = true
		add_child(black_layer)

	# Inicializar máscara de trazo previo
	preview_mask = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
	preview_mask.fill(Color(0, 0, 0, 0))
	preview_texture = ImageTexture.create_from_image(preview_mask)
	preview_layer = Sprite2D.new()
	preview_layer.texture = preview_texture
	_sync_overlay_transform(preview_layer)
	preview_layer.visible = true
	add_child(preview_layer)

func _process(delta):
	_sync_overlay_transform(black_layer)
	_sync_overlay_transform(preview_layer)
	
	# Animación de revelado total
	if full_reveal_active:
		full_reveal_progress += delta / full_reveal_speed
		if full_reveal_progress >= 1.0:
			full_reveal_progress = 1.0
			full_reveal_active = false
			
			if full_reveal_circular:
				# Al terminar el revelado circular, limpiar la máscara completamente
				reveal_mask.fill(Color(0, 0, 0, 0))
				reveal_texture.update(reveal_mask)
				if black_layer and black_layer.material:
					black_layer.material.set_shader_parameter("circular_reveal", false)
			
			emit_signal("full_reveal_completed")
		
		if full_reveal_circular:
			# Revelado circular usando shader (fluido)
			if black_layer and black_layer.material:
				var current_radius = full_reveal_progress * 1.5  # Radio normalizado (más de 1 para cubrir esquinas)
				black_layer.material.set_shader_parameter("circular_reveal", true)
				black_layer.material.set_shader_parameter("reveal_radius", current_radius)
				black_layer.material.set_shader_parameter("reveal_center", full_reveal_center)
		else:
			# Ir haciendo transparente toda la máscara gradualmente
			var target_alpha = 1.0 - full_reveal_progress
			reveal_mask.fill(Color(0, 0, 0, target_alpha))
			reveal_texture.update(reveal_mask)
		return
	
	if reveal_active:
		reveal_accumulator += delta * max(1.0, reveal_points_per_second)
		var max_count = min(reveal_points_per_frame, reveal_queue.size())
		var count = min(int(reveal_accumulator), max_count)
		if count > 0:
			reveal_accumulator -= float(count)
		for i in range(count):
			var pos = reveal_queue.pop_front()
			if not is_undoing:
				_apply_reveal_at(pos, reveal_brush_size, reveal_brush_opacity)
				_apply_preview_clear(pos, reveal_brush_size)
			else:
				_apply_undo_at(pos, reveal_brush_size)
		if count > 0:
			reveal_texture.update(reveal_mask)
			if not is_undoing:
				preview_texture.update(preview_mask)
		if reveal_queue.is_empty():
			reveal_active = false
			reveal_accumulator = 0.0
			reveal_total_points = 0
			if not is_undoing:
				clear_preview()
			is_undoing = false
			if enable_colliders:
				# Marcar para actualizar después, no inmediatamente
				collider_pending_update = true
				collider_delay_timer = 0.0
	if collider_dirty and update_colliders_while_painting:
		collider_timer += delta
		if collider_timer >= max(0.0, collider_update_interval):
			collider_timer = 0.0
			collider_dirty = false
			update_colliders()
	
	# Actualizar colliders con retraso después del revelado
	if collider_pending_update:
		collider_delay_timer += delta
		if collider_delay_timer >= collider_update_delay_after_reveal:
			collider_pending_update = false
			force_collider_update()

func _sync_overlay_transform(node: Node2D):
	if not node:
		return
	if node is Sprite2D:
		node.position = sprite.position
		node.rotation = sprite.rotation
		node.scale = sprite.scale
		node.offset = sprite.offset
		node.centered = sprite.centered
	else:
		node.position = sprite.position
		node.rotation = sprite.rotation
		node.scale = sprite.scale

func _create_soft_mask_material() -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float radius = 1.5;
uniform float strength = 0.8;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * radius;
	float a = texture(TEXTURE, UV).a;
	float a1 = texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	float a2 = texture(TEXTURE, UV - vec2(px.x, 0.0)).a;
	float a3 = texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	float a4 = texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	float avg = (a + a1 + a2 + a3 + a4) * 0.2;
	float soft = mix(a, avg, strength);
	COLOR = vec4(0.0, 0.0, 0.0, soft);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("radius", soft_shader_radius)
	mat.set_shader_parameter("strength", soft_shader_strength)
	return mat

func _create_reveal_shader_material() -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform sampler2D reveal_mask : hint_default_black;
uniform bool circular_reveal = false;
uniform float reveal_radius = 0.0;
uniform vec2 reveal_center = vec2(0.5, 0.5);

void fragment() {
	float a = texture(reveal_mask, UV).a;
	
	if (circular_reveal && reveal_radius > 0.0) {
		// Revelado circular
		vec2 pixel_pos = UV;
		float distance = distance(pixel_pos, reveal_center);
		float max_distance = 1.0; // Distancia máxima normalizada
		
		if (distance <= reveal_radius) {
			// Dentro del círculo = revelado
			a = 0.0;
		}
	}
	
	// Negro donde no se ha revelado, transparente donde sí
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("reveal_mask", reveal_texture)
	mat.set_shader_parameter("circular_reveal", false)
	mat.set_shader_parameter("reveal_radius", 0.0)
	mat.set_shader_parameter("reveal_center", Vector2(0.5, 0.5))
	return mat

func paint_at_global_position(global_pos: Vector2, brush_size_param: float, brush_opacity_param: float):
	# Convertir posición global a local del sprite
	var local_pos = sprite.to_local(global_pos)
	if sprite.centered:
		local_pos += Vector2(image_size) / 2
	local_pos -= sprite.offset
	paint_reveal(local_pos, brush_size_param, brush_opacity_param)

func start_preview_stroke():
	clear_preview()
	stroke_points.clear()
	last_preview_point = Vector2.ZERO

func set_preview_color(new_color: Color) -> void:
	preview_color = new_color

func preview_at_global_position(global_pos: Vector2, brush_size_param: float):
	var local_pos = sprite.to_local(global_pos)
	if sprite.centered:
		local_pos += Vector2(image_size) / 2
	local_pos -= sprite.offset
	paint_preview(local_pos, brush_size_param)
	last_preview_brush_size = brush_size_param
	if last_preview_point == Vector2.ZERO or last_preview_point.distance_to(local_pos) >= stroke_record_min_distance:
		stroke_points.append(local_pos)
		last_preview_point = local_pos

func commit_preview(brush_size_param: float, brush_opacity_param: float):
	if not has_preview or stroke_points.is_empty():
		return
	reveal_queue = stroke_points.duplicate()
	reveal_total_points = reveal_queue.size()
	reveal_brush_size = brush_size_param if brush_size_param > 0.0 else last_preview_brush_size
	reveal_brush_opacity = brush_opacity_param
	reveal_accumulator = 0.0
	reveal_active = true
	is_undoing = false
	
	# Guardar en historial
	stroke_history.append({
		"points": stroke_points.duplicate(),
		"brush_size": reveal_brush_size,
		"brush_opacity": reveal_brush_opacity
	})

# Pintar y revelar área
func paint_reveal(pos: Vector2, brush_size_param: float, brush_opacity_param: float):
	# Pintar en la máscara de revelado (hacer transparente = revelar)
	_apply_reveal_at(pos, brush_size_param, brush_opacity_param)
	
	# Actualizar textura visual
	reveal_texture.update(reveal_mask)

	# Solicitar actualización de colliders (debounce)
	request_collider_update()

func _apply_reveal_at(pos: Vector2, brush_size_param: float, brush_opacity_param: float):
	for x in range(max(0, int(pos.x - brush_size_param)), min(image_size.x, int(pos.x + brush_size_param))):
		for y in range(max(0, int(pos.y - brush_size_param)), min(image_size.y, int(pos.y + brush_size_param))):
			var dist = pos.distance_to(Vector2(x, y))
			if dist <= brush_size_param:
				var alpha = 1.0 - (dist / brush_size_param) * (1.0 - brush_opacity_param)
				var current = reveal_mask.get_pixel(x, y)
				reveal_mask.set_pixel(x, y, Color(0, 0, 0, current.a * (1.0 - alpha)))

func paint_preview(pos: Vector2, brush_size_param: float):
	# Pintar en la máscara de previsualización (amarillo)
	var min_x = max(0, int(pos.x - brush_size_param))
	var max_x = min(image_size.x, int(pos.x + brush_size_param))
	var min_y = max(0, int(pos.y - brush_size_param))
	var max_y = min(image_size.y, int(pos.y + brush_size_param))

	if not has_preview:
		preview_dirty_rect = Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)
		has_preview = true
	else:
		var rect_min_x = min(preview_dirty_rect.position.x, min_x)
		var rect_min_y = min(preview_dirty_rect.position.y, min_y)
		var rect_max_x = max(preview_dirty_rect.position.x + preview_dirty_rect.size.x, max_x)
		var rect_max_y = max(preview_dirty_rect.position.y + preview_dirty_rect.size.y, max_y)
		preview_dirty_rect = Rect2i(rect_min_x, rect_min_y, rect_max_x - rect_min_x, rect_max_y - rect_min_y)

	for x in range(min_x, max_x):
		for y in range(min_y, max_y):
			var dist = pos.distance_to(Vector2(x, y))
			if dist <= brush_size_param:
				var current = preview_mask.get_pixel(x, y)
				var new_alpha = max(current.a, preview_color.a)
				preview_mask.set_pixel(x, y, Color(preview_color.r, preview_color.g, preview_color.b, new_alpha))

	preview_texture.update(preview_mask)

func _apply_preview_clear(pos: Vector2, brush_size_param: float):
	for x in range(max(0, int(pos.x - brush_size_param)), min(image_size.x, int(pos.x + brush_size_param))):
		for y in range(max(0, int(pos.y - brush_size_param)), min(image_size.y, int(pos.y + brush_size_param))):
			var dist = pos.distance_to(Vector2(x, y))
			if dist <= brush_size_param:
				preview_mask.set_pixel(x, y, Color(0, 0, 0, 0))

func undo_last_stroke():
	if stroke_history.is_empty() or reveal_active or is_undoing:
		return
	var last_stroke = stroke_history.pop_back()
	undo_queue = last_stroke["points"].duplicate()
	undo_queue.reverse()
	reveal_queue = undo_queue
	reveal_brush_size = last_stroke["brush_size"]
	reveal_brush_opacity = last_stroke["brush_opacity"]
	reveal_total_points = reveal_queue.size()
	reveal_accumulator = 0.0
	reveal_active = true
	is_undoing = true

func _apply_undo_at(pos: Vector2, brush_size_param: float):
	for x in range(max(0, int(pos.x - brush_size_param)), min(image_size.x, int(pos.x + brush_size_param))):
		for y in range(max(0, int(pos.y - brush_size_param)), min(image_size.y, int(pos.y + brush_size_param))):
			var dist = pos.distance_to(Vector2(x, y))
			if dist <= brush_size_param:
				reveal_mask.set_pixel(x, y, Color(0, 0, 0, 1))

func clear_preview():
	preview_mask.fill(Color(0, 0, 0, 0))
	preview_texture.update(preview_mask)
	preview_dirty_rect = Rect2i()
	has_preview = false

func request_collider_update():
	if not enable_colliders:
		return
	collider_dirty = true
	if update_colliders_while_painting and collider_update_interval <= 0.0:
		collider_dirty = false
		update_colliders()

func force_collider_update():
	if not enable_colliders:
		return
	collider_dirty = false
	collider_timer = 0.0
	update_colliders()

# Actualizar colliders basándose en áreas reveladas
func update_colliders():
	# Limpiar colliders existentes
	for child in get_children():
		if child is CollisionPolygon2D:
			child.queue_free()
	
	# Crear versión reducida temporal de las imágenes para calcular colliders
	var scale_factor = 1.0
	var collider_size = image_size
	
	if collider_downscale_size > 0:
		var max_dim = max(image_size.x, image_size.y)
		if max_dim > collider_downscale_size:
			scale_factor = float(collider_downscale_size) / float(max_dim)
			collider_size = Vector2i(
				int(image_size.x * scale_factor),
				int(image_size.y * scale_factor)
			)
			print("Colliders: Usando imagen reducida ", collider_size, " (factor: ", scale_factor, ")")
	
	# Crear bitmap combinado con el tamaño reducido
	var combined_bitmap = BitMap.new()
	combined_bitmap.create(collider_size)
	
	# Procesar solo la imagen reducida
	for x in range(collider_size.x):
		for y in range(collider_size.y):
			# Mapear coordenadas reducidas a originales
			var orig_x = int(x / scale_factor)
			var orig_y = int(y / scale_factor)
			
			var is_original = original_bitmap.get_bit(orig_x, orig_y)
			var is_revealed = reveal_mask.get_pixel(orig_x, orig_y).a < 0.5
			combined_bitmap.set_bit(x, y, is_original and is_revealed)
	
	# Convertir áreas opacas en polígonos (con tamaño reducido)
	var polygons = combined_bitmap.opaque_to_polygons(Rect2(Vector2(0, 0), collider_size))
	
	print("Colliders: Generados ", polygons.size(), " polígonos")
	
	var total_vertices = 0
	# Crear CollisionPolygon2D para cada polígono
	for polygon in polygons:
		total_vertices += polygon.size()
		var collider = CollisionPolygon2D.new()
		for i in range(polygon.size()):
			# Escalar de vuelta al tamaño original
			polygon[i] = polygon[i] / scale_factor
			
			if sprite.centered:
				polygon[i] -= Vector2(image_size) / 2
			polygon[i] += sprite.offset
		collider.polygon = polygon
		collider.position = sprite.position
		collider.rotation = sprite.rotation
		collider.scale = sprite.scale
		add_child(collider)
	
	print("Colliders: Total de ", total_vertices, " vértices en los polígonos")

func start_full_reveal(duration: float = 5.0, circular: bool = false):
	"""Inicia la animación de revelado total de la imagen"""
	full_reveal_speed = duration
	full_reveal_progress = 0.0
	full_reveal_active = true
	full_reveal_circular = circular
	
	if circular:
		# Centro normalizado (0.5, 0.5 = centro de la imagen)
		full_reveal_center = Vector2(0.5, 0.5)
		full_reveal_max_radius = 1.5  # Radio suficiente para cubrir toda la imagen
