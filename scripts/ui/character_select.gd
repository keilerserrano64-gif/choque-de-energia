extends Control
## Selección de luchador con forma de libro abierto y cámara animada.
## - Izquierda: retrato grande del luchador de J1 con su técnica y despertar.
## - Centro: dos páginas (ALBA azul y OCASO roja) con 4 + 4 luchadores y
##   una casilla ALEATORIO en cada una.
## - Derecha: J2, la CPU o el rival de Arcade, con cartas apiladas detrás.
## - Arriba: cuenta atrás (30 s contra la CPU, sin límite en VS y entrenamiento).
## La "cámara" es el nodo Rig: entra con zoom y apertura del libro, se inclina
## hacia el cursor y, al confirmar, se acerca al centro antes del "VS".

const LAYOUT := [
	[0, 1, 4, 5],
	[2, 3, 6, 7],
	[SelectCell.RANDOM, SelectCell.EMBLEM, SelectCell.EMBLEM, SelectCell.RANDOM],
]
const COLS := 4
const ROWS := 3
const COUNTDOWN := 30.0

@onready var backdrop: SelectBackdrop = %Backdrop
@onready var rig: Control = %Rig
@onready var reveal: Control = %Reveal

var mode := "cpu"
var phase := 0  ## en VS CPU / entrenamiento: 0 = eligiendo J1, 1 = eligiendo rival
var cursors: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0)]
var locked: Array[bool] = [false, false]
var chosen: Array[String] = ["", ""]
var countdown := COUNTDOWN
var finished := false
var _cells: Array = []
var _pages: Array[BookPage] = []
var _showcases: Array[Control] = []
var _show_portraits: Array[FighterPortrait] = []
var _show_names: Array[Label] = []
var _show_roles: Array[Label] = []
var _show_tags: Array[Label] = []
var _show_moves: Array[Label] = []
var _show_status: Array[Label] = []
var _show_random: Array[Label] = []
var _show_player_tags: Array[Label] = []
var _timer_label: Label
var _instruction: Label
var _hint: Label
var _camera_target := Vector2.ZERO
var _rolling := 0.0
var _roll_step := 0.0
var _intro_done := false


func _ready() -> void:
	mode = Router.mode
	Sfx.play_music("menu")
	countdown = COUNTDOWN if (mode == "arcade" or mode == "cpu") else INF
	var p1_index := maxi(0, Catalog.fighter_index(Router.p1_id))
	cursors[0] = _position_of(p1_index)
	cursors[1] = _position_of(maxi(0, Catalog.fighter_index(Router.p2_id)))
	rig.pivot_offset = Vector2(480, 270)
	_build_banner()
	_build_book()
	_build_showcase(0)
	_build_showcase(1)
	_build_footer()
	_refresh_all()
	_play_intro()


# --- Construcción -----------------------------------------------------------

func _build_banner() -> void:
	var banner := Panel.new()
	banner.add_theme_stylebox_override("panel", UiKit.panel(Color("#c21f33"), Color("#ffd36e"), 2, 2, -0.3))
	banner.position = Vector2(250, 10)
	banner.size = Vector2(460, 38)
	rig.add_child(banner)
	var title := UiKit.label("SELECCIÓN DE LUCHADOR", 24, Color.WHITE, 8, Color("#4a0610"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 2)
	title.size = Vector2(460, 34)
	banner.add_child(title)

	var mode_tag := UiKit.label("MODO · %s" % Router.mode_label(), 14, UiKit.ACCENT, 4)
	mode_tag.position = Vector2(18, 18)
	rig.add_child(mode_tag)

	var clock := Panel.new()
	var clock_style := UiKit.panel(Color("#0a0d15"), Color.WHITE, 3, 30)
	clock.add_theme_stylebox_override("panel", clock_style)
	clock.position = Vector2(448, 52)
	clock.size = Vector2(64, 56)
	rig.add_child(clock)
	var clock_caption := UiKit.label("TIEMPO", 10, UiKit.GOLD)
	clock_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_caption.position = Vector2(0, 3)
	clock_caption.size = Vector2(64, 12)
	clock.add_child(clock_caption)
	_timer_label = UiKit.label("30", 28, Color.WHITE, 6)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.position = Vector2(0, 13)
	_timer_label.size = Vector2(64, 40)
	clock.add_child(_timer_label)


func _build_book() -> void:
	var spine := ColorRect.new()
	spine.color = Color("#07080d")
	spine.position = Vector2(472, 116)
	spine.size = Vector2(16, 336)
	rig.add_child(spine)
	var titles := ["ALBA", "OCASO"]
	var colors := [UiKit.BLUE_PAGE, UiKit.RED_PAGE]
	for page_index in range(2):
		var page := BookPage.new()
		page.side = -1 if page_index == 0 else 1
		page.page_color = colors[page_index]
		page.title = titles[page_index]
		page.position = Vector2(280 if page_index == 0 else 488, 120)
		page.size = Vector2(192, 326)
		page.pivot_offset = Vector2(192 if page_index == 0 else 0, 163)
		rig.add_child(page)
		_pages.append(page)
	for row in range(ROWS):
		var row_cells: Array = []
		for col in range(COLS):
			var page_index := 0 if col < 2 else 1
			var local_col := col % 2
			var cell := SelectCell.new()
			cell.setup(LAYOUT[row][col], colors[page_index])
			cell.position = Vector2(10 + local_col * 88, 56 + row * 90)
			if page_index == 1:
				cell.position.x += 4
			_pages[page_index].add_child(cell)
			var target := Vector2i(col, row)
			cell.gui_input.connect(func(event: InputEvent) -> void: _on_cell_input(event, target))
			cell.mouse_entered.connect(func() -> void: _on_cell_hover(target))
			row_cells.append(cell)
		_cells.append(row_cells)


func _build_showcase(side: int) -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = Vector2(14, 58) if side == 0 else Vector2(700, 58)
	root.size = Vector2(246, 430)
	rig.add_child(root)
	_showcases.append(root)
	var accent := UiKit.P1_COLOR if side == 0 else UiKit.P2_COLOR
	var tilt := -0.06 if side == 0 else 0.06

	if side == 1:
		for i in range(3):
			var card := Panel.new()
			card.add_theme_stylebox_override("panel", UiKit.panel(Color("#1a2035"), UiKit.GOLD.darkened(0.3), 3, 8))
			card.size = Vector2(150, 210)
			card.position = Vector2(120 + i * 12, 40 + i * 18)
			card.pivot_offset = card.size / 2.0
			card.rotation = 0.12 + i * 0.08
			var logo := UiKit.label("CHOQUE\nDE\nENERGÍA", 18, UiKit.GOLD, 4)
			logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			logo.size = card.size
			card.add_child(logo)
			card.name = "Card%d" % i
			root.add_child(card)

	var burst := Panel.new()
	burst.add_theme_stylebox_override("panel", UiKit.panel(Color("#2a0f3d"), Color("#ff5fd1"), 3, 4, -0.25 if side == 0 else 0.25))
	burst.position = Vector2(4, 0)
	burst.size = Vector2(238, 54)
	root.add_child(burst)
	var moves := UiKit.label("", 13, Color.WHITE, 4)
	moves.position = Vector2(16, 5)
	moves.size = Vector2(212, 46)
	burst.add_child(moves)
	_show_moves.append(moves)

	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", UiKit.panel(accent.darkened(0.6), accent, 4, 4))
	frame.position = Vector2(22, 62)
	frame.size = Vector2(200, 250)
	frame.pivot_offset = frame.size / 2.0
	frame.rotation = tilt
	frame.clip_contents = true
	root.add_child(frame)
	var stage_glow := StagePreview.new()
	stage_glow.stage_id = String(Catalog.STAGES[side * 3]["id"])
	stage_glow.position = Vector2(4, 4)
	stage_glow.size = Vector2(192, 242)
	stage_glow.modulate = Color(0.55, 0.55, 0.65, 1)
	frame.add_child(stage_glow)
	var portrait := FighterPortrait.new()
	portrait.position = Vector2(4, 8)
	portrait.size = Vector2(192, 238)
	portrait.facing = 1 if side == 0 else -1
	frame.add_child(portrait)
	_show_portraits.append(portrait)
	var random_mark := UiKit.label("?", 120, UiKit.GOLD, 16)
	random_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	random_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	random_mark.size = frame.size
	random_mark.visible = false
	frame.add_child(random_mark)
	_show_random.append(random_mark)
	var player_tag := UiKit.label("J1" if side == 0 else "J2", 18, Color.WHITE, 6, accent.darkened(0.5))
	player_tag.position = Vector2(10, 6)
	frame.add_child(player_tag)
	_show_player_tags.append(player_tag)

	var name_label := UiKit.label("", 36, Color.WHITE, 12, accent.darkened(0.55))
	name_label.position = Vector2(8, 312)
	name_label.size = Vector2(230, 46)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.pivot_offset = Vector2(115, 23)
	name_label.rotation = tilt
	root.add_child(name_label)
	_show_names.append(name_label)
	var role := UiKit.label("", 13, UiKit.ACCENT, 4)
	role.position = Vector2(8, 356)
	role.size = Vector2(230, 18)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(role)
	_show_roles.append(role)
	var tags := UiKit.label("", 12, UiKit.MUTED)
	tags.position = Vector2(8, 376)
	tags.size = Vector2(230, 16)
	tags.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(tags)
	_show_tags.append(tags)
	var status := UiKit.label("", 12, UiKit.GOLD, 4)
	status.position = Vector2(8, 396)
	status.size = Vector2(230, 16)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status)
	_show_status.append(status)


func _build_footer() -> void:
	var bar := ColorRect.new()
	bar.color = Color(0.02, 0.025, 0.045, 0.92)
	bar.position = Vector2(0, 496)
	bar.size = Vector2(960, 44)
	rig.add_child(bar)
	var line := ColorRect.new()
	line.color = UiKit.ACCENT
	line.position = Vector2(0, 496)
	line.size = Vector2(960, 2)
	rig.add_child(line)
	_instruction = UiKit.label("", 16, Color.WHITE, 4)
	_instruction.position = Vector2(20, 506)
	_instruction.size = Vector2(470, 24)
	rig.add_child(_instruction)
	_hint = UiKit.label("", 13, UiKit.MUTED)
	_hint.position = Vector2(470, 509)
	_hint.size = Vector2(470, 20)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rig.add_child(_hint)


# --- Animación de cámara ----------------------------------------------------

func _play_intro() -> void:
	rig.scale = Vector2(1.45, 1.45)
	rig.modulate.a = 0.0
	for page in _pages:
		page.scale = Vector2(0.02, 1.0)
	var duration := 0.85
	var tween := create_tween().set_parallel(true)
	tween.tween_property(rig, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(rig, "modulate:a", 1.0, duration * 0.5)
	for page in _pages:
		tween.tween_property(page, "scale", Vector2.ONE, duration * 0.8).set_delay(duration * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(_on_intro_finished)


func _on_intro_finished() -> void:
	_intro_done = true
	Sfx.play("announce")


func _update_camera(delta: float) -> void:
	var active := cursors[1] if (phase == 1 and mode != "versus") else cursors[0]
	_camera_target = Vector2((1.5 - active.x) * 9.0, (1.0 - active.y) * 5.0)
	rig.position = rig.position.lerp(_camera_target, minf(1.0, delta * 5.0))
	backdrop.parallax = rig.position * 2.5
	for i in range(_showcases.size()):
		var side := -1.0 if i == 0 else 1.0
		_showcases[i].position.x = (14.0 if i == 0 else 700.0) + rig.position.x * 0.8 * side
	rig.rotation = lerpf(rig.rotation, (1.5 - active.x) * -0.004, minf(1.0, delta * 5.0))


# --- Bucle ------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_camera(delta)
	if finished or not _intro_done:
		return
	if _rolling > 0.0:
		_update_roll(delta)
		return
	if countdown != INF:
		countdown = maxf(0.0, countdown - delta)
		_timer_label.text = str(ceili(countdown))
		if countdown <= 0.0:
			_auto_select()
			return
	_handle_player_input(0)
	if mode == "versus":
		_handle_player_input(1)


func _just(player: int, action: String) -> bool:
	if mode == "versus":
		return Input.is_action_just_pressed("p%d_%s" % [player + 1, action])
	var ui := {"left": "ui_left", "right": "ui_right", "jump": "ui_up", "down": "ui_down", "attack": "ui_accept", "special": "ui_cancel"}
	return Input.is_action_just_pressed("p1_" + action) or Input.is_action_just_pressed("p2_" + action) \
		or (ui.has(action) and Input.is_action_just_pressed(ui[action]))


func _handle_player_input(player: int) -> void:
	# En VS CPU y entrenamiento J1 mueve también el cursor del rival (fase 1).
	var cursor_index := player
	if mode != "versus":
		cursor_index = phase
	if _just(player, "special") or (player == 0 and Input.is_action_just_pressed("pause")):
		_go_back(cursor_index)
		return
	if locked[cursor_index]:
		return
	var direction := Vector2i.ZERO
	if _just(player, "left"):
		direction = Vector2i(-1, 0)
	elif _just(player, "right"):
		direction = Vector2i(1, 0)
	elif _just(player, "jump"):
		direction = Vector2i(0, -1)
	elif _just(player, "down"):
		direction = Vector2i(0, 1)
	if direction != Vector2i.ZERO:
		_move_cursor(cursor_index, direction)
	if _just(player, "attack"):
		_confirm(cursor_index)


func _move_cursor(index: int, direction: Vector2i) -> void:
	var pos := cursors[index]
	for attempt in range(COLS * ROWS):
		pos = Vector2i(posmod(pos.x + direction.x, COLS), posmod(pos.y + direction.y, ROWS))
		if _cell_at(pos).is_selectable():
			break
	cursors[index] = pos
	Sfx.play("cursor")
	_refresh_all()


func _cell_at(pos: Vector2i) -> SelectCell:
	return _cells[pos.y][pos.x]


func _position_of(fighter_index: int) -> Vector2i:
	for row in range(ROWS):
		for col in range(COLS):
			if LAYOUT[row][col] == fighter_index:
				return Vector2i(col, row)
	return Vector2i(0, 0)


func _resolve(pos: Vector2i, exclude: String = "") -> String:
	var index: int = LAYOUT[pos.y][pos.x]
	if index >= 0:
		return String(Catalog.FIGHTERS[index]["id"])
	var options: Array[String] = []
	for fighter in Catalog.FIGHTERS:
		if fighter["id"] != exclude:
			options.append(String(fighter["id"]))
	return options[randi() % options.size()]


func _confirm(index: int) -> void:
	var exclude := chosen[0] if (index == 1 and mode != "versus") else ""
	var fighter_id := _resolve(cursors[index], exclude)
	chosen[index] = fighter_id
	locked[index] = true
	cursors[index] = _position_of(Catalog.fighter_index(fighter_id)) if LAYOUT[cursors[index].y][cursors[index].x] == SelectCell.RANDOM else cursors[index]
	Sfx.play("confirm")
	var portrait := _show_portraits[index]
	portrait.fighter_id = fighter_id
	portrait.animation = "victory"
	portrait.flash = 0.18
	_punch(_showcases[index])
	_refresh_all()
	_after_lock(index)


func _after_lock(index: int) -> void:
	match mode:
		"versus":
			if locked[0] and locked[1]:
				_finish()
		"arcade":
			Router.start_arcade(chosen[0])
			_rolling = 1.1
			_roll_step = 0.0
		_:
			if index == 0:
				phase = 1
				cursors[1] = cursors[0]
				_move_cursor(1, Vector2i(1, 0))
			else:
				_finish()


func _go_back(index: int) -> void:
	Sfx.play("cursor")
	if mode == "versus":
		if locked[index]:
			locked[index] = false
			_show_portraits[index].animation = "intro"
			_refresh_all()
		elif not locked[0] and not locked[1]:
			Router.goto("menu")
		return
	if phase == 1:
		phase = 0
		locked[0] = false
		locked[1] = false
		_show_portraits[0].animation = "intro"
		_refresh_all()
		return
	if locked[0]:
		locked[0] = false
		_refresh_all()
		return
	Router.goto("menu")


func _auto_select() -> void:
	if not locked[0]:
		_confirm(0)
	if finished or _rolling > 0.0:
		return
	if mode != "versus" and not locked[1]:
		cursors[1] = Vector2i(3, 2)  # aleatorio
		_confirm(1)
	elif mode == "versus" and not locked[1]:
		_confirm(1)


func _update_roll(delta: float) -> void:
	# Arcade: el cursor rojo recorre la cuadrícula y se detiene en el rival.
	_rolling = maxf(0.0, _rolling - delta)
	_roll_step -= delta
	if _roll_step <= 0.0 and _rolling > 0.0:
		_roll_step = 0.07
		cursors[1] = _position_of(randi() % Catalog.FIGHTERS.size())
		Sfx.play("cursor")
		_refresh_all()
	if _rolling == 0.0:
		chosen[1] = Router.p2_id
		cursors[1] = _position_of(Catalog.fighter_index(chosen[1]))
		locked[1] = true
		_show_portraits[1].fighter_id = chosen[1]
		_show_portraits[1].animation = "victory"
		Sfx.play("confirm")
		_refresh_all()
		_finish()


# --- Ratón y pantalla táctil ------------------------------------------------

func _on_cell_hover(pos: Vector2i) -> void:
	if finished or not _intro_done or not _cell_at(pos).is_selectable():
		return
	var index := phase if mode != "versus" else 0
	if locked[index] or cursors[index] == pos:
		return
	cursors[index] = pos
	Sfx.play("cursor")
	_refresh_all()


func _on_cell_input(event: InputEvent, pos: Vector2i) -> void:
	if finished or not _intro_done or _rolling > 0.0:
		return
	var tapped := false
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		tapped = mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		tapped = touch.pressed
	if not tapped or not _cell_at(pos).is_selectable():
		return
	var index := phase if mode != "versus" else (0 if not locked[0] else 1)
	if locked[index]:
		return
	if cursors[index] == pos:
		_confirm(index)
	else:
		cursors[index] = pos
		Sfx.play("cursor")
		_refresh_all()


# --- Interfaz ---------------------------------------------------------------

func _refresh_all() -> void:
	var show_p2 := mode == "versus" or phase == 1 or locked[1] or _rolling > 0.0
	for row in range(ROWS):
		for col in range(COLS):
			var cell := _cell_at(Vector2i(col, row))
			cell.p1_here = cursors[0] == Vector2i(col, row) and not (phase == 1 and mode != "versus")
			cell.p2_here = show_p2 and cursors[1] == Vector2i(col, row)
			cell.p1_locked = locked[0]
			cell.p2_locked = locked[1]
			cell.p2_label = "J2" if mode == "versus" else "CPU"
	_update_showcase(0)
	_update_showcase(1, show_p2)
	if mode == "versus":
		_instruction.text = "Cada jugador elige a su luchador"
		_hint.text = "J1  WASD · J elegir · K volver      J2  flechas · Num1 elegir · Num2 volver"
	elif phase == 0:
		_instruction.text = "Elige a tu luchador"
		_hint.text = "MOVER  WASD / flechas     J / ENTER  CONFIRMAR     L / ESC  VOLVER"
	elif mode == "arcade":
		_instruction.text = "Buscando rival…"
		_hint.text = "ARCADE · 7 RIVALES"
	else:
		_instruction.text = "Elige a tu rival" if mode == "cpu" else "Elige al muñeco de práctica"
		_hint.text = "MOVER  WASD / flechas     J / ENTER  CONFIRMAR     L / ESC  VOLVER"
	if countdown == INF:
		_timer_label.text = "--"


func _update_showcase(side: int, visible_side: bool = true) -> void:
	var portrait := _show_portraits[side]
	var pos := cursors[side]
	var index: int = LAYOUT[pos.y][pos.x]
	var is_random := index == SelectCell.RANDOM and not locked[side]
	var hidden := not visible_side
	if mode == "arcade" and side == 1 and not locked[1] and _rolling <= 0.0:
		hidden = true
	_show_random[side].visible = is_random or hidden
	_show_random[side].text = "?"
	portrait.visible = not (is_random or hidden)
	_show_player_tags[side].text = "J1" if side == 0 else ("J2" if mode == "versus" else "CPU")
	if hidden:
		_show_names[side].text = "???"
		_show_roles[side].text = "RIVAL EN ESPERA"
		_show_tags[side].text = ""
		_show_moves[side].text = "TÉCNICA  ???\nDESPERTAR  ???"
		_show_status[side].text = ""
		return
	if is_random:
		_show_names[side].text = "ALEATORIO"
		_show_roles[side].text = "LA SUERTE DECIDE"
		_show_tags[side].text = ""
		_show_moves[side].text = "TÉCNICA  ?\nDESPERTAR  ?"
		_show_status[side].text = ""
		return
	var fighter_id := chosen[side] if locked[side] else String(Catalog.FIGHTERS[index]["id"])
	var fighter := Catalog.fighter(fighter_id)
	if portrait.fighter_id != fighter_id:
		portrait.fighter_id = fighter_id
		portrait.animation = "intro"
		portrait.flash = 0.08
	_show_names[side].text = String(fighter["name"]).to_upper()
	_show_roles[side].text = String(fighter["role"])
	var tag_list: Array = fighter.get("tags", [])
	_show_tags[side].text = " · ".join(PackedStringArray(tag_list))
	_show_moves[side].text = "TÉCNICA  %s\nDESPERTAR  %s" % [fighter["technique"], fighter["awakening"]]
	if SaveData.is_unlocked(fighter_id):
		_show_status[side].text = "DESPERTAR DISPONIBLE"
	else:
		_show_status[side].text = "DESPERTAR BLOQUEADO · TIENDA %d" % Catalog.FORM_COST


func _punch(node: Control) -> void:
	node.pivot_offset = node.size / 2.0
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2(1.06, 1.06), 0.07)
	tween.tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- Final: pantalla "VS" ---------------------------------------------------

func _finish() -> void:
	if finished:
		return
	finished = true
	Router.p1_id = chosen[0]
	Router.p2_id = chosen[1]
	await get_tree().create_timer(0.45).timeout
	var zoom := create_tween().set_parallel(true)
	zoom.tween_property(rig, "scale", Vector2(1.35, 1.35), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	zoom.tween_property(rig, "modulate:a", 0.0, 0.45)
	await zoom.finished
	_show_reveal()
	await get_tree().create_timer(1.7).timeout
	Router.goto("fight" if mode == "arcade" else "stage")


func _show_reveal() -> void:
	reveal.visible = true
	Sfx.play("announce")
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	reveal.add_child(dim)
	var halves: Array[Panel] = []
	for side in range(2):
		var accent := UiKit.P1_COLOR if side == 0 else UiKit.P2_COLOR
		var half := Panel.new()
		half.add_theme_stylebox_override("panel", UiKit.panel(accent.darkened(0.45), accent, 4, 0, -0.35 if side == 0 else -0.35))
		half.size = Vector2(500, 600)
		half.position = Vector2(-560 if side == 0 else 1020, -30)
		half.clip_contents = true
		reveal.add_child(half)
		var portrait := FighterPortrait.new()
		portrait.fighter_id = chosen[side]
		portrait.animation = "victory"
		portrait.facing = 1 if side == 0 else -1
		portrait.size = Vector2(380, 470)
		portrait.position = Vector2(80 if side == 0 else 40, 40)
		half.add_child(portrait)
		var fighter_name := UiKit.label(Catalog.fighter(chosen[side])["name"].to_upper(), 52, Color.WHITE, 14, accent.darkened(0.6))
		fighter_name.position = Vector2(60, 470)
		fighter_name.size = Vector2(380, 70)
		fighter_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		half.add_child(fighter_name)
		halves.append(half)
	var vs := UiKit.label("VS", 130, UiKit.GOLD, 22, Color("#3a1200"))
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs.size = Vector2(300, 200)
	vs.position = Vector2(330, 170)
	vs.pivot_offset = Vector2(150, 100)
	vs.scale = Vector2(3, 3)
	vs.modulate.a = 0.0
	reveal.add_child(vs)
	var detail := UiKit.label("", 16, UiKit.ACCENT, 4)
	if mode == "arcade":
		detail.text = "ARCADE · RIVAL %d DE %d · %s" % [Router.arcade_index + 1, Router.arcade_total(), Catalog.difficulty(Router.difficulty_id)["name"]]
	else:
		detail.text = Router.mode_label()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.size = Vector2(960, 24)
	detail.position = Vector2(0, 360)
	detail.modulate.a = 0.0
	reveal.add_child(detail)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(halves[0], "position:x", -40.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(halves[1], "position:x", 500.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(vs, "scale", Vector2.ONE, 0.3).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(vs, "modulate:a", 1.0, 0.2).set_delay(0.3)
	tween.tween_property(detail, "modulate:a", 1.0, 0.3).set_delay(0.55)
