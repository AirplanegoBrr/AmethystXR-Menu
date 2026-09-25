extends PanelContainer
## The menu shown on the VR panel. Account, instances and launching come from the launcher
## through the "Amethyst" Java plugin (VRMenuPlugin), which answers getMenuState() with JSON and
## runs signIn()/createInstance()/play(). Which versions can run in VR, and their mods, come from
## mod_catalog.gd, which installs those mods into the instances made here.

const POLL_SECONDS := 0.5
## When each startup step (see VRMenuPlugin.STARTUP_STEPS) was reached, in ms, per Minecraft version
const STARTUP_TIMES_PATH := "user://startup_times.json"
## Until a version has been started once: a 1.21.11 start on a Quest 3S
const DEFAULT_STARTUP_TIMES := [0, 3000, 17000, 23000, 31000]
const VERSION_COLUMNS := 3

const BACKGROUND := Color("17131f")
const SURFACE := Color("221b30")
const SURFACE_HOVER := Color("2c2340")
const BORDER := Color("3a2f55")
const ACCENT := Color("9b6bff")
const ACCENT_HOVER := Color("b08cff")
const TEXT := Color("f1ecfb")
const MUTED := Color("a99fc0")
const GOOD := Color("6fdc8c")
const BAD := Color("ff8a8a")

var _plugin: Object
var _catalog: Node
var _bold: FontVariation
var _block_icon: Texture2D
var _account_dot: Panel
var _account_label: Label
var _sign_in_button: Button
var _login_card: PanelContainer
var _login_label: Label
var _instance_box: VBoxContainer
var _instance_group := ButtonGroup.new()
var _instance_count: Label
var _empty_label: Label
var _version_grid: GridContainer
var _version_group := ButtonGroup.new()
var _version_hint: Label
var _create_button: Button
var _play_button: Button
var _progress: ProgressBar
var _status_label: Label
var _menu_column: VBoxContainer
var _launch_screen: PanelContainer
var _launch_title: Label
var _launch_bar: ProgressBar
var _launch_status: Label
var _launch_detail: Label
var _launch_version := ""
## The bar only ever moves forward
var _launch_value := 0.0
## From pressing Play until the game takes over the headset (or the launch fails)
var _launching := false
## From pressing Create until the instance and its mods are ready
var _create_screen := false
## Instance names in list order, and the one that's selected
var _names: Array = []
var _selected := ""
## name -> {name, version, gameDir}
var _instances := {}
## Versions shown, the one picked, and the launcher's own list (used until the catalog has one)
var _versions: Array = []
var _version := ""
var _launcher_versions: Array = []
var _last_created := ""
## Version of the instance being created, while the menu still has to install its mods
var _creating := ""
## The menu is installing mods
var _working := false
## The menu's own message for the status line, shown instead of the launcher's
var _message := ""
var _poll_timer := 0.0
var _busy := false
var _signed_in := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bold = FontVariation.new()
	_bold.base_font = ThemeDB.fallback_font
	_bold.variation_embolden = 0.9
	_block_icon = load("res://textures/block/grass_block_side.png")
	theme = _build_theme()
	add_theme_stylebox_override("panel", _box(BACKGROUND, 28, 32))
	_build_ui()

	_catalog = preload("res://mod_catalog.gd").new()
	add_child(_catalog)
	_catalog.changed.connect(_update_versions)
	if Engine.has_singleton("Amethyst"):
		_plugin = Engine.get_singleton("Amethyst")
		_refresh()
	else:
		_status_label.text = "Launcher plugin missing, run this from the Amethyst app"
	_catalog.refresh()
	_update_versions() # Shows that the catalog is checking


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 28
	t.set_color("font_color", "Label", TEXT)

	var button_colors := {"normal": SURFACE, "hover": SURFACE_HOVER, "pressed": ACCENT,
			"hover_pressed": ACCENT_HOVER, "disabled": SURFACE.darkened(0.3), "focus": SURFACE}
	for state in button_colors:
		var box := _box(button_colors[state], 16, 18)
		# Focus is drawn over the other styles; keep it invisible
		box.draw_center = state != "focus"
		t.set_stylebox(state, "Button", box)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(color, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))

	t.set_stylebox("scroll", "VScrollBar", _box(SURFACE, 5, 5))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		t.set_stylebox(state, "VScrollBar", _box(BORDER if state == "grabber" else ACCENT, 5, 5))

	t.set_stylebox("background", "ProgressBar", _box(SURFACE, 8, 0))
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT, 8, 0))
	return t


func _box(color: Color, radius: int, margin: int, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	box.border_color = border
	box.set_border_width_all(border_width)
	return box


func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	add_child(column)
	_menu_column = column

	# Header: logo and title on the left, account on the right
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	column.add_child(header)
	var logo := _icon(64)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(logo)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -4)
	header.add_child(titles)
	var title := _label("Amethyst", 46)
	title.add_theme_font_override("font", _bold)
	titles.add_child(title)
	titles.add_child(_label("Minecraft Java in VR", 22, MUTED))

	var account := PanelContainer.new()
	account.add_theme_stylebox_override("panel", _box(SURFACE, 40, 12, BORDER, 2))
	account.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(account)
	var account_row := HBoxContainer.new()
	account_row.add_theme_constant_override("separation", 14)
	account.add_child(account_row)
	_account_dot = Panel.new()
	_account_dot.custom_minimum_size = Vector2(16, 16)
	_account_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	account_row.add_child(_account_dot)
	_account_label = _label("Not signed in", 26)
	_account_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	account_row.add_child(_account_label)
	_sign_in_button = _accent_button("Sign in", 28)
	_sign_in_button.custom_minimum_size = Vector2(0, 52)
	_sign_in_button.pressed.connect(func(): _plugin.signIn())
	account_row.add_child(_sign_in_button)

	# The device code and link while signing in
	_login_card = PanelContainer.new()
	_login_card.add_theme_stylebox_override("panel", _box(SURFACE, 18, 22, ACCENT, 3))
	_login_card.visible = false
	column.add_child(_login_card)
	_login_label = _label("", 30)
	_login_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_login_card.add_child(_login_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	column.add_child(body)

	# Left: the instances
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	body.add_child(left)
	var instances_header := HBoxContainer.new()
	left.add_child(instances_header)
	var instances_title := _heading("INSTANCES")
	instances_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instances_header.add_child(instances_title)
	_instance_count = _label("", 20, MUTED)
	instances_header.add_child(_instance_count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_instance_box = VBoxContainer.new()
	_instance_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_instance_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_instance_box)
	_empty_label = _label("No instances yet. Pick a version and press Create.", 26, MUTED)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instance_box.add_child(_empty_label)

	# Right: new instance, then Play
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(470, 0)
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	right.add_child(_heading("NEW INSTANCE"))
	var create_card := PanelContainer.new()
	create_card.add_theme_stylebox_override("panel", _box(SURFACE, 20, 18, BORDER, 2))
	right.add_child(create_card)
	var create_column := VBoxContainer.new()
	create_column.add_theme_constant_override("separation", 12)
	create_card.add_child(create_column)
	# The versions sit right on the panel: a dropdown's popup closes too easily with a laser
	var version_scroll := ScrollContainer.new()
	version_scroll.custom_minimum_size = Vector2(0, 204)
	version_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	create_column.add_child(version_scroll)
	_version_grid = GridContainer.new()
	_version_grid.columns = VERSION_COLUMNS
	_version_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_version_grid.add_theme_constant_override("h_separation", 10)
	_version_grid.add_theme_constant_override("v_separation", 10)
	version_scroll.add_child(_version_grid)
	_version_hint = _label("", 20, MUTED)
	_version_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	create_column.add_child(_version_hint)
	_create_button = _button("Create")
	_create_button.custom_minimum_size = Vector2(0, 64)
	_create_button.add_theme_stylebox_override("normal", _box(SURFACE_HOVER, 16, 18, BORDER, 2))
	_create_button.add_theme_stylebox_override("hover", _box(SURFACE_HOVER.lightened(0.1), 16, 18, ACCENT, 2))
	_create_button.pressed.connect(_on_create)
	create_column.add_child(_create_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	_play_button = _accent_button("Play", 22)
	_play_button.custom_minimum_size = Vector2(0, 96)
	_play_button.add_theme_font_size_override("font_size", 38)
	_play_button.add_theme_font_override("font", _bold)
	_play_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_play_button.pressed.connect(_on_play)
	right.add_child(_play_button)
	var launcher_button := _button("Open the 2D launcher")
	launcher_button.flat = true
	launcher_button.custom_minimum_size = Vector2(0, 44)
	launcher_button.add_theme_font_size_override("font_size", 22)
	launcher_button.add_theme_color_override("font_color", MUTED)
	launcher_button.add_theme_color_override("font_hover_color", TEXT)
	launcher_button.pressed.connect(func(): if _plugin: _plugin.openLauncher())
	right.add_child(launcher_button)

	# Footer: progress and status
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 16)
	_progress.show_percentage = false
	_progress.visible = false
	footer.add_child(_progress)
	_status_label = _label("", 24, MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status_label)

	_build_launch_screen()


## Covers the whole panel while the game is being prepared and started
func _build_launch_screen() -> void:
	_launch_screen = PanelContainer.new()
	_launch_screen.add_theme_stylebox_override("panel", _box(BACKGROUND, 28, 80))
	_launch_screen.visible = false
	add_child(_launch_screen)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 28)
	_launch_screen.add_child(column)
	var logo := _icon(128)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(logo)
	_launch_title = _label("", 52)
	_launch_title.add_theme_font_override("font", _bold)
	_launch_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_launch_title)
	_launch_bar = ProgressBar.new()
	_launch_bar.custom_minimum_size = Vector2(0, 28)
	_launch_bar.show_percentage = false
	column.add_child(_launch_bar)
	_launch_status = _label("", 30, MUTED)
	_launch_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_launch_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_launch_status)
	_launch_detail = _label("", 26, MUTED.darkened(0.25))
	_launch_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_launch_detail)


func _label(text: String, size: int, color := TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _heading(text: String) -> Label:
	var label := _label(text, 20, MUTED)
	label.add_theme_font_override("font", _bold)
	return label


func _icon(size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = _block_icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(size, size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 68)
	return button


func _accent_button(text: String, radius: int) -> Button:
	var button := _button(text)
	button.add_theme_stylebox_override("normal", _box(ACCENT, radius, 18))
	button.add_theme_stylebox_override("hover", _box(ACCENT_HOVER, radius, 18))
	button.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.2), radius, 18))
	button.add_theme_stylebox_override("disabled", _box(Color(ACCENT, 0.3), radius, 18))
	return button


## A toggle button with an outline, filled with the accent color once picked
func _toggle(button: Button, radius: int, background: Color) -> void:
	button.toggle_mode = true
	button.add_theme_stylebox_override("normal", _box(background, radius, 12, BORDER, 2))
	button.add_theme_stylebox_override("hover", _box(background.lightened(0.06), radius, 12, ACCENT, 2))
	button.add_theme_stylebox_override("pressed", _box(SURFACE_HOVER, radius, 12, ACCENT, 3))
	button.add_theme_stylebox_override("hover_pressed", _box(SURFACE_HOVER.lightened(0.04), radius, 12, ACCENT_HOVER, 3))


func _process(delta: float) -> void:
	if _plugin == null:
		return
	_poll_timer += delta
	if _poll_timer >= POLL_SECONDS:
		_poll_timer = 0.0
		_refresh()


func _refresh() -> void:
	var state = JSON.parse_string(_plugin.getMenuState())
	if typeof(state) != TYPE_DICTIONARY:
		return

	_signed_in = state.signedIn
	_account_label.text = state.account if _signed_in else "Not signed in"
	_account_dot.add_theme_stylebox_override("panel", _box(GOOD if _signed_in else MUTED, 8, 0))
	_sign_in_button.visible = not _signed_in
	_login_label.text = state.loginMessage
	_login_card.visible = not _signed_in and state.loginMessage != ""

	_update_instances(state.instances)
	if state.lastCreated != _last_created:
		_last_created = state.lastCreated
		_selected = _last_created
		_update_instances(state.instances)
		if _creating != "" and _instances.has(_last_created):
			_finish_create(_instances[_last_created])
	elif _creating != "" and not state.busy:
		_creating = "" # The launcher couldn't create it; its status says why
	if state.versions != _launcher_versions:
		_launcher_versions = state.versions
		_update_versions()

	_busy = state.busy or _working or _creating != ""
	_progress.visible = _busy
	if _working:
		_progress.indeterminate = false
		_progress.value = _catalog.progress * 100.0
		_status_label.text = _catalog.status
	else:
		# Only downloads report real progress; creating and starting just show activity
		_progress.indeterminate = state.busy and state.phase != "downloading"
		_progress.value = state.progress
		_status_label.text = _message if _message != "" and not state.busy else state.status
	_status_label.add_theme_color_override("font_color", BAD if _message.begins_with("Couldn't") else MUTED)
	_update_launch_screen(state)
	_sign_in_button.disabled = _busy
	_update_create_button()
	_update_play_button()


## The catalog's versions once it has checked them, the launcher's list until then
func _update_versions() -> void:
	var versions: Array = _catalog.versions if not _catalog.versions.is_empty() else _launcher_versions
	if _catalog.busy and _catalog.versions.is_empty():
		_version_hint.text = "Checking Modrinth for VR mods…"
	elif not _catalog.versions.is_empty():
		_version_hint.text = "Vivecraft, Fabric API and performance mods, installed by the menu"
	else:
		_version_hint.text = "Couldn't reach Modrinth, showing the launcher's versions"
	if versions == _versions:
		return
	_versions = versions
	for child in _version_grid.get_children():
		child.queue_free()
	if not _versions.has(_version):
		_version = _versions[0] if not _versions.is_empty() else ""
	for version in _versions:
		var chip := _button(version)
		chip.custom_minimum_size = Vector2(0, 58)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_font_size_override("font_size", 24)
		_toggle(chip, 12, BACKGROUND)
		chip.button_group = _version_group
		chip.set_pressed_no_signal(version == _version)
		chip.pressed.connect(func(): _version = version)
		_version_grid.add_child(chip)
	_update_create_button()


## One card per instance; rebuilt only when the list changes
func _update_instances(instances: Array) -> void:
	_instances.clear()
	for instance in instances:
		_instances[instance.name] = instance
	var names := instances.map(func(instance): return instance.name)
	if not names.has(_selected):
		_selected = names[0] if not names.is_empty() else ""
	if names != _names:
		_names = names
		for child in _instance_box.get_children():
			if child != _empty_label:
				child.queue_free()
		_empty_label.visible = instances.is_empty()
		_instance_count.text = "" if instances.is_empty() else str(instances.size())
		for instance in instances:
			_instance_box.add_child(_instance_card(instance))
	for card in _instance_box.get_children():
		if card.has_meta("instance"):
			card.set_pressed_no_signal(card.get_meta("instance") == _selected)


func _instance_card(instance: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 100)
	_toggle(card, 18, SURFACE)
	card.button_group = _instance_group
	card.set_meta("instance", instance.name)
	card.pressed.connect(_on_instance_pressed.bind(instance.name))

	# Buttons don't lay out children, so the row fills the card by its anchors
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_right = -18
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon := _icon(60)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 0)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var name_label := _label(instance.name, 30)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(name_label)
	texts.add_child(_label("Minecraft " + instance.version, 22, MUTED))

	var delete := Button.new()
	delete.text = "Delete"
	delete.custom_minimum_size = Vector2(130, 56)
	delete.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	delete.add_theme_font_size_override("font_size", 22)
	delete.add_theme_color_override("font_color", MUTED)
	delete.add_theme_color_override("font_hover_color", BAD)
	delete.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0), 14, 12))
	delete.add_theme_stylebox_override("hover", _box(Color(BAD, 0.12), 14, 12))
	delete.add_theme_stylebox_override("pressed", _box(Color(BAD, 0.25), 14, 12))
	delete.pressed.connect(_on_delete_pressed.bind(delete, instance.name))
	row.add_child(delete)
	return card


## Deleting takes two presses, so a stray trigger pull can't lose an instance
func _on_delete_pressed(button: Button, instance_name: String) -> void:
	if _busy:
		return
	if button.has_meta("confirm"):
		_plugin.deleteInstance(instance_name)
		return
	button.set_meta("confirm", true)
	button.text = "Sure?"
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_stylebox_override("normal", _box(BAD.darkened(0.3), 14, 12))
	button.add_theme_stylebox_override("hover", _box(BAD.darkened(0.15), 14, 12))
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(button):
		button.remove_meta("confirm")
		button.text = "Delete"
		button.add_theme_color_override("font_color", MUTED)
		button.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0), 14, 12))
		button.add_theme_stylebox_override("hover", _box(Color(BAD, 0.12), 14, 12))


func _update_create_button() -> void:
	_create_button.disabled = _busy or _version == ""
	_create_button.text = "Create" if _version == "" else "Create  " + _version


func _update_play_button() -> void:
	_play_button.disabled = _busy or not _signed_in or _selected == ""
	_play_button.text = "Play" if _selected == "" else "Play  " + _selected


func _on_instance_pressed(instance_name: String) -> void:
	_selected = instance_name
	_update_play_button()


func _on_create() -> void:
	if _version == "" or _plugin == null:
		return
	_message = ""
	# Versions from the catalog get their mods from the menu once the launcher made the instance
	if _catalog.has_version(_version):
		_creating = _version
	_create_screen = true
	_launch_value = 0.0
	_launch_detail.text = ""
	_launch_title.text = "Creating Minecraft " + _version
	_plugin.createInstance(_version)


func _finish_create(instance: Dictionary) -> void:
	_creating = ""
	if not instance.has("gameDir"):
		return # An older launcher that doesn't say where instances live; it installs the mods
	_working = true
	var error: String = await _catalog.setup_instance(instance.gameDir, instance.version)
	_working = false
	_message = error if error != "" else "Created %s with its VR mods" % instance.name


## Instances made here get their mods checked first, so they update with the catalog
func _update_launch_screen(state: Dictionary) -> void:
	# The launcher stays busy until the game exits, so not busy means the launch failed
	if _launching and not _working and not state.busy:
		_launching = false
		if _message == "":
			_message = state.status
	# Creating is done once the launcher made the instance and the menu installed its mods
	if _create_screen and _creating == "" and not _working and not state.busy:
		_create_screen = false
	_launch_screen.visible = _launching or _create_screen
	_menu_column.visible = not _launch_screen.visible
	if _create_screen and not _launching:
		_update_create_screen(state)
		return
	if not _launching:
		return
	if _working:
		_launch_bar.indeterminate = false
		_launch_bar.value = _catalog.progress * 100.0
		_launch_status.text = _catalog.status if _catalog.status != "" else "Checking mods…"
	elif state.phase == "starting" and state.get("startupStep", -1) >= 0:
		_launch_bar.indeterminate = false
		_launch_value = maxf(_launch_value, _startup_progress(state))
		_launch_bar.value = _launch_value * 100.0
		_launch_status.text = state.status
		_launch_detail.text = state.startupText
	else:
		# Downloads report real progress; anything else just shows activity
		_launch_bar.indeterminate = state.phase != "downloading"
		_launch_bar.value = state.progress
		_launch_status.text = state.status
		_launch_detail.text = ""


func _update_create_screen(state: Dictionary) -> void:
	if _working:
		_launch_bar.indeterminate = false
		_launch_bar.value = _catalog.progress * 100.0
		_launch_status.text = "Installing VR mods"
		_launch_detail.text = _catalog.status
	else:
		_launch_bar.indeterminate = true
		_launch_status.text = "Installing Fabric"
		_launch_detail.text = state.status


## How far the game has started, 0 to 1: the step reached sets the range, and the time spent in
## it moves the bar along, based on how long that step took last time. It stops short of the next
## step until the game really gets there.
func _startup_progress(state: Dictionary) -> float:
	var expected: Array = _startup_times().get(_launch_version, DEFAULT_STARTUP_TIMES)
	var reached: Array = state.startupTimes
	var step: int = mini(state.startupStep, expected.size() - 1)
	if reached.size() == expected.size():
		_save_startup_times(reached)
	var total := float(expected[-1])
	if step >= expected.size() - 1 or total <= 0.0:
		return 1.0
	var start := float(expected[step]) / total
	var end := float(expected[step + 1]) / total
	var step_length := maxf(float(expected[step + 1] - expected[step]), 1.0)
	var in_step := (float(state.startupElapsed) - float(reached[step])) / step_length
	return start + (end - start) * clampf(in_step, 0.0, 0.95)


func _startup_times() -> Dictionary:
	if not FileAccess.file_exists(STARTUP_TIMES_PATH):
		return {}
	var times = JSON.parse_string(FileAccess.get_file_as_string(STARTUP_TIMES_PATH))
	return times if times is Dictionary else {}


func _save_startup_times(reached: Array) -> void:
	var times := _startup_times()
	if times.get(_launch_version) == reached:
		return
	times[_launch_version] = reached
	var file := FileAccess.open(STARTUP_TIMES_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(times))


func _on_play() -> void:
	var instance: Dictionary = _instances.get(_selected, {})
	if instance.is_empty():
		return
	_message = ""
	_launching = true
	_launch_version = str(instance.version)
	_launch_value = 0.0
	_launch_detail.text = ""
	_launch_title.text = "Starting Minecraft " + _launch_version
	var game_dir: String = instance.get("gameDir", "")
	if game_dir != "" and _catalog.is_menu_instance(game_dir):
		_working = true
		_update_play_button()
		# The mod list may still be loading; launching without it would skip mod updates
		while _catalog.busy:
			await get_tree().process_frame
		var error := ""
		if _catalog.has_version(instance.version):
			error = await _catalog.install_mods(game_dir, instance.version)
		else:
			error = "Couldn't get the VR mods for Minecraft %s, check your connection and try again" % instance.version
		_working = false
		if error != "":
			_message = error
			_launching = false
			return
	_plugin.play(_selected)
	_play_button.disabled = true
