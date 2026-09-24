extends PanelContainer
## The menu shown on the VR panel. All data comes from the launcher through the "Amethyst"
## Java plugin (VRMenuPlugin), which answers getMenuState() with JSON and runs signIn()/play().

const POLL_SECONDS := 0.5

var _plugin: Object
var _account_label: Label
var _sign_in_button: Button
var _login_label: Label
var _instance_list: ItemList
var _play_button: Button
var _progress: ProgressBar
var _status_label: Label
## One entry per list row: {name, version, exists}
var _entries: Array = []
var _poll_timer := 0.0
var _busy := false
var _signed_in := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.1, 0.08, 0.15)
	background.set_content_margin_all(40)
	add_theme_stylebox_override("panel", background)
	_build_ui()

	if Engine.has_singleton("Amethyst"):
		_plugin = Engine.get_singleton("Amethyst")
		_refresh()
	else:
		_status_label.text = "Launcher plugin missing, run this from the Amethyst app"


func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	add_child(column)

	column.add_child(_label("Amethyst VR", 52))

	var account_row := HBoxContainer.new()
	account_row.add_theme_constant_override("separation", 20)
	column.add_child(account_row)
	_account_label = _label("Not signed in", 30)
	_account_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_row.add_child(_account_label)
	_sign_in_button = _button("Sign in with a code")
	_sign_in_button.pressed.connect(_on_sign_in)
	account_row.add_child(_sign_in_button)

	_login_label = _label("", 30)
	_login_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_login_label)

	_instance_list = ItemList.new()
	_instance_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_instance_list.add_theme_font_size_override("font_size", 32)
	_instance_list.item_selected.connect(func(_index): _update_play_button())
	column.add_child(_instance_list)

	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", 20)
	column.add_child(play_row)
	_play_button = _button("Play")
	_play_button.custom_minimum_size = Vector2(260, 80)
	_play_button.pressed.connect(_on_play)
	play_row.add_child(_play_button)
	_progress = ProgressBar.new()
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.custom_minimum_size = Vector2(0, 40)
	_progress.visible = false
	play_row.add_child(_progress)
	var launcher_button := _button("2D launcher")
	launcher_button.pressed.connect(_on_open_launcher)
	play_row.add_child(launcher_button)

	_status_label = _label("", 26)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 30)
	button.custom_minimum_size = Vector2(0, 70)
	return button


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

	_account_label.text = "Signed in as " + state.account if state.signedIn else "Not signed in"
	_login_label.text = state.loginMessage
	_update_instances(state.instances, state.versions)

	_busy = state.busy
	_signed_in = state.signedIn
	_progress.visible = _busy
	_progress.value = state.progress
	_status_label.text = state.status
	_sign_in_button.disabled = _busy
	_update_play_button()


## Existing instances first, then a "New" row for each supported version without one
func _update_instances(instances: Array, versions: Array) -> void:
	var entries := []
	var covered := {}
	for instance in instances:
		entries.append({"name": instance.name, "version": instance.version, "exists": true})
		covered[instance.version] = true
	for version in versions:
		if not covered.has(version):
			entries.append({"name": version, "version": version, "exists": false})
	if entries == _entries:
		return

	var selected_name := ""
	if not _instance_list.get_selected_items().is_empty():
		selected_name = _entries[_instance_list.get_selected_items()[0]].name
	_entries = entries
	_instance_list.clear()
	for entry in entries:
		var text: String = "%s  (%s)" % [entry.name, entry.version] if entry.exists else "New: Minecraft %s" % entry.version
		_instance_list.add_item(text)
		if entry.name == selected_name:
			_instance_list.select(_instance_list.item_count - 1)
	if not _instance_list.is_anything_selected() and _instance_list.item_count > 0:
		_instance_list.select(0)


func _update_play_button() -> void:
	_play_button.disabled = _busy or not _signed_in or not _instance_list.is_anything_selected()


func _on_sign_in() -> void:
	_plugin.signIn()


func _on_play() -> void:
	var entry: Dictionary = _entries[_instance_list.get_selected_items()[0]]
	_plugin.play(entry.name, entry.version)
	_play_button.disabled = true


func _on_open_launcher() -> void:
	if _plugin:
		_plugin.openLauncher()
