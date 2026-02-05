extends CharacterBody2D

const SPEED = 400.0
const JUMP_VELOCITY = -500.0
const JUMP_SOUND = preload("res://audio/jump.mp3")
const POP_SOUND = preload("res://audio/pop.ogg")
const GRITO_SOUND = preload("res://audio/grito3.mp3")

var _muerto: bool = false
var was_on_floor: bool = true
# Bandera para evitar que la animación "run" sobrescriba "jump" en el mismo frame
var _jump_queued: bool = false
# Bandera para bloquear físicas hasta que termine la animación de spawn
var _spawning: bool = false
# Evitar ejecutar varias veces la finalización del spawn si la animación está en loop
var _spawn_handled: bool = false
# Indica si ya se ha reproducido el sonido 'pop' durante el spawn
var _spawn_pop_played: bool = false
# Coyote time: permite saltar durante un tiempo después de dejar el suelo
var coyote_timer: float = 0.0
const COYOTE_TIME: float = 0.1  # Segundos que puedes saltar después de dejar el suelo
# Señal emitida cuando termina la secuencia de victoria
signal level_won
# Estado de victoria (cuando true el personaje no acepta input)
var victoria: bool = false
# Flags para la fase de 'run' de la secuencia de victoria
var _win_running: bool = false
var _win_move_remaining: float = 0.0
var _win_run_speed: float = 0.0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var col_idle: CollisionShape2D = get_node_or_null("CollisionShapeIdle")
@onready var col_run: CollisionShape2D = get_node_or_null("CollisionShapeRun")
@onready var col_jump: CollisionShape2D = get_node_or_null("CollisionShapeJump")
@onready var col_spawn: CollisionShape2D = get_node_or_null("CollisionShapeSpawn")


func _ready():
	# Si existe animación 'spawn', reproducirla y bloquear físicas hasta que termine
	var frames = $AnimatedSprite2D.sprite_frames
	if frames and frames.has_animation("spawn"):
		# Asegurar que la animación 'spawn' empiece desde el frame 0 para que se vea
		$AnimatedSprite2D.frame = 0
		$AnimatedSprite2D.frame_progress = 0.0
		$AnimatedSprite2D.play("spawn")
		_set_collider_for("spawn")
		_spawning = true
		# Asegurarnos de que no suenan efectos mientras aparece
		if $RunSound.playing:
			$RunSound.stop()
		# Asignar stream y reproducir 'pop' al inicio del spawn (sonará antes o junto a la animación)
		if POP_SOUND and has_node("SpawnSound"):
			$SpawnSound.stream = POP_SOUND
			$SpawnSound.volume_db = -6
			$SpawnSound.play()
			_spawn_pop_played = true
		# Conectar tanto animation_finished como frame_changed para detectar el final incluso si la animación hace loop
		$AnimatedSprite2D.connect("animation_finished", Callable(self, "_on_animation_finished"))
		$AnimatedSprite2D.connect("frame_changed", Callable(self, "_on_frame_changed"))
		_spawn_handled = false
	else:
		$AnimatedSprite2D.play("idle")
		_set_collider_for("idle")
	# Precargar audio para evitar delay en la primera reproducción
	var s = preload("res://audio/run.wav")
	$RunSound.stream = s
	# Ajuste de volumen (en decibelios). Valores negativos reducen el volumen; -6 es un poco más bajo.
	$RunSound.volume_db = -1
	# Asignar sonido de salto pre-cargado para minimizar delay
	if JUMP_SOUND:
		$JumpSound.stream = JUMP_SOUND
	else:
		push_error("No se encontró el recurso res://audio/jump.mp3 (preload)")
	# Asignar grito si está disponible, sin borrar ni modificar nodos existentes
	if GRITO_SOUND:
		$GritoSound.stream = GRITO_SOUND
	else:
		push_error("No se encontró el recurso res://audio/grito3.mp3 (preload)")

	# Si es un AudioStreamSample, activamos loop hacia adelante (sin referencia directa al tipo)
	if s and s.get_class() == "AudioStreamSample":
		s.loop_mode = s.LOOP_FORWARD

func _set_collider_for(anim_name: String) -> void:
	# Deshabilitar todas (usar set_deferred para evitar cambiar el estado durante consultas físicas)
	if col_idle:
		col_idle.set_deferred("disabled", true)
		col_idle.set_deferred("visible", false)
	if col_run:
		col_run.set_deferred("disabled", true)
		col_run.set_deferred("visible", false)
	if col_jump:
		col_jump.set_deferred("disabled", true)
		col_jump.set_deferred("visible", false)
	if col_spawn:
		col_spawn.set_deferred("disabled", true)
		col_spawn.set_deferred("visible", false)

	# Activar la forma correspondiente (también deferred)
	match anim_name:
		"idle":
			if col_idle:
				col_idle.set_deferred("disabled", false)
				col_idle.set_deferred("visible", true)
		"run":
			if col_run:
				col_run.set_deferred("disabled", false)
				col_run.set_deferred("visible", true)
		"jump":
			if col_jump:
				col_jump.set_deferred("disabled", false)
				col_jump.set_deferred("visible", true)
		"spawn":
			if col_spawn:
				col_spawn.set_deferred("disabled", false)
				col_spawn.set_deferred("visible", true)

func _on_frame_changed() -> void:
	# Detectar el último frame de 'spawn' en caso de que la animación haga loop
	if _spawning and not _spawn_handled and $AnimatedSprite2D.animation == "spawn":
		var total = $AnimatedSprite2D.sprite_frames.get_frame_count("spawn")
		if $AnimatedSprite2D.frame == total - 1:
			_spawn_handled = true
			_end_spawn()

func _on_animation_finished(anim_name: String = "") -> void:
	# AnimatedSprite2D puede emitir 'animation_finished' sin argumentos en algunas versiones.
	var name: String
	if anim_name != "":
		name = anim_name
	else:
		name = String($AnimatedSprite2D.animation)
	if name == "spawn":
		_end_spawn()

func _end_spawn() -> void:
	# Ejecutar al terminar la animación de spawn
	_spawning = false
	# Reproducir sonido de aparición si aún no se reprodujo (fallback)
	if has_node("SpawnSound") and not _spawn_pop_played:
		$SpawnSound.play()
		_spawn_pop_played = true
	$AnimatedSprite2D.play("idle")
	_set_collider_for("idle")

# Inicia la secuencia de victoria: reproducir 'tusmuerto' durante `t_death` segundos
# y después reproducir 'run' mientras se desplaza a la derecha durante `t_run` segundos.
func win_sequence(t_death: float = 1.5, t_run: float = 2.0, run_speed: float = SPEED) -> void:
	if victoria:
		return
	# Marcar victoria y bloquear input
	victoria = true
	# Detener efectos de movimiento actuales
	if $RunSound.playing:
		$RunSound.stop()
	 # ESTE ITXINE
	await get_tree().create_timer(0.3).timeout

	# Reproducir animación de muerte/celebración si existe
	if $AnimatedSprite2D.sprite_frames and $AnimatedSprite2D.sprite_frames.has_animation("tusmuerto"):
		$AnimatedSprite2D.play("tusmuerto")
	else:
		$AnimatedSprite2D.play("idle")
	# Ajustar collider a idle/seguro mientras dura la animación
	_set_collider_for("idle")

	# Reproducir grito justo al empezar (o ligeramente después) si existe
	if GRITO_SOUND:
		$GritoSound.stream = GRITO_SOUND
		$GritoSound.volume_db = -8
		# Esperar un frame para sincronizar con el inicio de la animación
		$GritoSound.play()

	# Esperar la duración de la animación 'tusmuerto'
	await get_tree().create_timer(t_death).timeout
	# Avisar al BlackBucket para que huya
	var bucket := get_tree().get_first_node_in_group("black_bucket")
	if bucket and bucket.has_method("run_away"):
		bucket.run_away()
	# Esperar 1 segundo
	var timer = get_tree().create_timer(1.0)
	await timer.timeout

	# Empezar fase de correr hacia la derecha
	_win_running = true
	_win_move_remaining = t_run
	_win_run_speed = run_speed
	$AnimatedSprite2D.play("run")
	_set_collider_for("run")
	# Asegurarse de que el personaje mire a la derecha
	anim.flip_h = false

func _physics_process(delta: float) -> void: 

	if _muerto:
		if $RunSound.playing:
			$RunSound.stop()
		return

	# Durante 'spawn' bloqueamos el input pero permitimos que la gravedad actúe
	if _spawning:
		# Asegurarnos de que no suenen efectos de carrera mientras aparece
		if $RunSound.playing:
			$RunSound.stop()
		# Aplicar sólo gravedad y mover la física para permitir que caiga hasta la plataforma
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return
	# Si estamos en la secuencia de victoria, gestionar las fases
	if victoria:
		# Fase de correr activa: mover a la derecha durante el tiempo restante
		if _win_running:
			velocity.x = _win_run_speed
			# Reproducir sonido de correr si no está ya sonando
			if not $RunSound.playing:
				$RunSound.play()
			# Aplicar física y contar tiempo
			move_and_slide()
			_win_move_remaining -= delta
			if _win_move_remaining <= 0.0:
				_win_running = false
				victoria = false
				velocity.x = 0
				$AnimatedSprite2D.play("idle")
				_set_collider_for("idle")
				# Emitir señal de victoria para que otros sistemas la manejen
				emit_signal("level_won")
			return
		# Fase de 'tusmuerto' (solo gravedad y bloqueo de input)
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return
	# Gravedad
	if not is_on_floor():
		velocity += get_gravity() * delta
	var on_floor = is_on_floor()

	# Actualizar coyote timer
	if on_floor:
		coyote_timer = COYOTE_TIME  # Reset cuando estamos en el suelo
	else:
		coyote_timer -= delta  # Decrementar cuando estamos en el aire

	# Salto (ahora con coyote time)
	if (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_up")) and coyote_timer > 0.0:
		$AnimatedSprite2D.play("jump")
		_set_collider_for("jump")
		# Reproducir sonido de salto
		$JumpSound.play()
		velocity.y = JUMP_VELOCITY
		# Consumir el coyote time al saltar
		coyote_timer = 0.0
		# Evitar que en el mismo frame se vuelva a poner la animación "run"
		_jump_queued = true

	# ATERRIZA
	if on_floor and not was_on_floor:
		$AnimatedSprite2D.play("idle")
		_set_collider_for("idle")

	was_on_floor = on_floor

	# Movimiento horizontal
	var direction := Input.get_axis("ui_left", "ui_right")

	# Detener sonido si no está en el suelo
	if not on_floor and $RunSound.playing:
		$RunSound.stop()

	if direction != 0:
		velocity.x = direction * SPEED
		# FLIP
		anim.flip_h = direction < 0
		# Reproducir sonido si está en el suelo y no está ya sonando (cubre izquierda y derecha)
		# No poner "run" si acabamos de saltar este frame o si la animación actual es "jump" o "spawn"
		if on_floor:
			if not _jump_queued and $AnimatedSprite2D.animation != "jump" and $AnimatedSprite2D.animation != "spawn":
				$AnimatedSprite2D.play("run")
				_set_collider_for("run")
			if not $RunSound.playing:
				$RunSound.play()

	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		if $RunSound.playing:
			$RunSound.stop()
		# Si hemos dejado de pulsar dirección y estamos en el suelo, volver a "idle"
		if on_floor and not _jump_queued:
			$AnimatedSprite2D.play("idle")
			_set_collider_for("idle")

	move_and_slide()
	# Reiniciar la bandera de salto para permitir animaciones normales en el siguiente frame
	_jump_queued = false
