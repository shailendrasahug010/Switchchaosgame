extends Node3D
## Wardrobe: pick your creature, a hat and a paint job. Your creature stands
## on a podium (drag to spin it). Locked cosmetics show exactly how to earn
## them, with a progress bar. Everything is earned by playing: no shop, no
## random rewards, and cosmetics never change how a character plays.

enum Tab { CHARACTERS, HATS, PAINTS }

## Width of the picker panel plus its margin, in UI units.
const PANEL_WIDTH := 660.0
const CAMERA_DISTANCE := 4.6

var _tab: Tab = Tab.CHARACTERS
var _cam: Camera3D
var _spin: Node3D
var _visual: PlayerVisual
var _yaw := 0.4
var _drag_touch := -2
var _idle_spin := true
var _grid: GridContainer
var _tab_buttons: Array[Button] = []
var _name_label: Label
var _blurb_label: Label
var _detail_label: Label
var _items: Dictionary = {}   # id -> Button


func _ready() -> void:
	AudioManager.play_music(&"menu")
	_build_world()
	_build_ui()
	_refresh_preview(false)
	_show_tab(Tab.CHARACTERS)


# ---------------------------------------------------------------- 3D preview

func _build_world() -> void:
	var env := ToyEnvironment.new()
	env.sun_yaw = 30.0
	add_child(env)
	var podium := MeshFactory.make(MeshFactory.cylinder(1.35, 1.5, 0.5, 36), ToyMaterials.plastic(Color("ffb3d6")),
			Vector3(0, -0.25, 0))
	add_child(podium)
	add_child(MeshFactory.make(MeshFactory.torus(1.3, 1.5, 36, 8), ToyMaterials.plastic(Color("fff8ee")),
			Vector3(0, 0.0, 0), Vector3(1, 0.6, 1), Vector3.ZERO, false))
	var floor_mesh := MeshFactory.make(MeshFactory.cylinder(30, 30, 0.2, 48),
			ToyMaterials.patterned(Color("c9b6ff"), Color("ded2ff"), ToyMaterials.Pattern.CHECKER, 0.5), Vector3(0, -0.6, 0),
			Vector3.ONE, Vector3.ZERO, false)
	add_child(floor_mesh)
	_spin = Node3D.new()
	add_child(_spin)
	_visual = PlayerVisual.new()
	_spin.add_child(_visual)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	add_child(_cam)
	_cam.current = true
	_place_camera()
	get_viewport().size_changed.connect(_place_camera)


## Slides the camera sideways so the creature stands in the middle of the
## free space left of the picker panel, on any screen shape.
func _place_camera() -> void:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var free_fraction := clampf((vp.x - PANEL_WIDTH) / vp.x, 0.3, 0.8)
	var target_x := free_fraction * 0.5          # 0 = left edge, 1 = right edge
	var half_width := CAMERA_DISTANCE * tan(deg_to_rad(_cam.fov * 0.5)) * aspect
	var offset := (1.0 - 2.0 * target_x) * half_width
	_cam.look_at_from_position(Vector3(offset, 1.35, CAMERA_DISTANCE), Vector3(offset, 0.75, 0.0))


func _refresh_preview(cheer: bool = true) -> void:
	var prof := GameState.profile
	_visual.build(prof.character, prof.hat, prof.paint)
	if cheer:
		_visual.react(&"happy")
		_visual.play_celebration(0.8)
	var info := Catalog.character(prof.character)
	if _name_label:
		_name_label.text = info.name
		_blurb_label.text = info.blurb


func _process(delta: float) -> void:
	if _idle_spin:
		_yaw += delta * 0.5
	_spin.rotation.y = _yaw


func _unhandled_input(event: InputEvent) -> void:
	# Drag on the left side of the screen to spin the creature.
	var vp := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and t.position.x < vp.x * 0.45:
			_drag_touch = t.index
			_idle_spin = false
		elif not t.pressed and t.index == _drag_touch:
			_drag_touch = -2
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _drag_touch:
			_yaw += d.relative.x * 0.012
	elif event.is_action_pressed(&"ui_cancel"):
		_back()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	UiKit.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var back := UiKit.icon_button("", &"back", &"DarkButton", 72)
	back.pressed.connect(_back)
	root.add_child(back)
	back.position = Vector2(24, 20)

	# Name card under the creature.
	var name_card := UiKit.color_panel(Color(0.14, 0.12, 0.3, 0.8), 24, 14)
	name_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_card)
	name_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	name_card.offset_left = 24
	name_card.offset_bottom = -20
	name_card.offset_top = -150
	name_card.offset_right = 470
	var ncol := UiKit.vbox(2)
	name_card.add_child(ncol)
	_name_label = UiKit.label("", &"HeaderLabel")
	ncol.add_child(_name_label)
	_blurb_label = UiKit.wrap_label("", &"SmallLabel")
	_blurb_label.custom_minimum_size.x = 410
	ncol.add_child(_blurb_label)

	# Picker panel on the right.
	var panel := UiKit.color_panel(Color(0.14, 0.12, 0.3, 0.9), 30, 18, Color(1, 1, 1, 0.25), 0, 3)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -640
	panel.offset_right = -20
	panel.offset_top = 20
	panel.offset_bottom = -20
	var col := UiKit.vbox(12)
	panel.add_child(col)
	var title_row := UiKit.hbox(12)
	col.add_child(title_row)
	title_row.add_child(Icon.new(&"shirt", Color("8fd3ff"), 48))
	title_row.add_child(UiKit.label("Wardrobe", &"HeaderLabel"))
	var tabs := UiKit.hbox(10)
	col.add_child(tabs)
	for t in [[Tab.CHARACTERS, "Friends", &"person"], [Tab.HATS, "Hats", &"star"], [Tab.PAINTS, "Colors", &"heart"]]:
		var b := UiKit.icon_button(t[1], t[2], &"DarkButton", 64)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tab_id: Tab = t[0]
		b.pressed.connect(func() -> void: _show_tab(tab_id))
		b.add_theme_stylebox_override("pressed", UiKit.style(UiKit.VIOLET, 22, 12, Color("ffd23f"), 6, 3))
		b.add_theme_stylebox_override("hover_pressed", UiKit.style(UiKit.VIOLET, 22, 12, Color("ffd23f"), 6, 3))
		tabs.add_child(b)
		_tab_buttons.append(b)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	_detail_label = UiKit.wrap_label("", &"SmallLabel")
	_detail_label.custom_minimum_size.x = 560
	col.add_child(_detail_label)
	var stats := GameState.stats
	var summary := UiKit.label("Stars collected: %d     Rounds played: %d" % [int(stats.stars), int(stats.rounds_played)],
			&"SmallLabel")
	summary.add_theme_color_override("font_color", Color("ffd23f"))
	col.add_child(summary)


func _show_tab(tab: Tab) -> void:
	_tab = tab
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == int(tab))
	for c in _grid.get_children():
		c.queue_free()
	_items.clear()
	var prof := GameState.profile
	match tab:
		Tab.CHARACTERS:
			for c in Catalog.CHARACTERS:
				_add_item(c.id, c.name, true, prof.character == c.id, c.id, prof.hat, prof.paint, {})
			_detail_label.text = "Every friend plays exactly the same. Pick the one you like best!"
		Tab.HATS:
			for h in Catalog.HATS:
				_add_item(h.id, h.name, GameState.is_unlocked(h.id), prof.hat == h.id, prof.character, h.id, prof.paint, h)
			_detail_label.text = "Hats are just for fun. Earn new ones by playing!"
		Tab.PAINTS:
			for p in Catalog.PAINTS:
				_add_item(p.id, p.name, GameState.is_unlocked(p.id), prof.paint == p.id, prof.character, prof.hat, p.id, p)


func _add_item(id: StringName, title: String, unlocked: bool, selected: bool, character: StringName,
		hat: StringName, paint: StringName, item: Dictionary) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(134, 150)
	b.focus_mode = Control.FOCUS_ALL
	var border := Color("ffd23f") if selected else Color(1, 1, 1, 0.25)
	var bg := Color(0.24, 0.2, 0.46) if unlocked else Color(0.16, 0.14, 0.28)
	var normal := UiKit.style(bg, 22, 8, border, 0, 5 if selected else 2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", UiKit.style(bg.lightened(0.08), 22, 8, border, 0, 5 if selected else 2))
	b.add_theme_stylebox_override("pressed", normal)
	b.add_theme_stylebox_override("focus", UiKit.style(Color(0, 0, 0, 0), 22, 0, Color.WHITE, 0, 3))
	var col := UiKit.vbox(2, BoxContainer.ALIGNMENT_CENTER)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(col)
	var portrait := CharacterPortrait.new(character, 92)
	portrait.hat_id = hat
	portrait.paint_id = paint
	portrait.modulate = Color.WHITE if unlocked else Color(1, 1, 1, 0.35)
	col.add_child(portrait)
	var name_label := UiKit.label(title, &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	name_label.add_theme_font_size_override("font_size", 18)
	col.add_child(name_label)
	if not unlocked:
		var lock := Icon.new(&"lock", Color("ffd23f"), 34)
		lock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		lock.position = Vector2(92, 6)
		b.add_child(lock)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(100, 10)
		bar.value = GameState.unlock_progress(item) * 100.0
		bar.add_theme_stylebox_override("fill", UiKit.style(Color("ffd23f"), 6, 0))
		bar.add_theme_stylebox_override("background", UiKit.style(Color(0, 0, 0, 0.35), 6, 0))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(bar)
	b.pressed.connect(func() -> void: _on_item(id, unlocked, item))
	_grid.add_child(b)
	_items[id] = b


func _on_item(id: StringName, unlocked: bool, item: Dictionary) -> void:
	if not unlocked:
		_detail_label.text = "%s is locked. To earn it: %s" % [item.get("name", "This"), GameState.unlock_rule_text(item)]
		AudioManager.play(&"locked")
		return
	var prof := GameState.profile
	match _tab:
		Tab.CHARACTERS:
			GameState.set_profile(id, prof.hat, prof.paint)
		Tab.HATS:
			GameState.set_profile(prof.character, id, prof.paint)
		Tab.PAINTS:
			GameState.set_profile(prof.character, prof.hat, id)
	AudioManager.play(&"equip")
	if _tab == Tab.CHARACTERS:
		AudioManager.play(&"voice_happy", Catalog.character(id).voice_pitch, -4.0)
	_refresh_preview()
	_show_tab(_tab)


func _back() -> void:
	Router.go(&"menu")
