extends Node3D
## VR scene: a floating panel showing the menu UI, and laser pointers on both controllers
## that turn trigger presses into mouse clicks on the panel. The game runs in this app's
## process; when it's ready this scene fades out and hands the headset over to it.

const PANEL_SIZE := Vector2(1.6, 1.0) # meters
const VIEWPORT_SIZE := Vector2i(1280, 800) # pixels
const PANEL_DISTANCE := 1.3 # meters in front of the headset
const TRIGGER_DOWN := 0.6
const TRIGGER_UP := 0.4
const FADE_SECONDS := 0.5
const SCROLL_DEADZONE := 0.5
const SCROLL_INTERVAL_MS := 90

var _viewport: SubViewport
var _panel: MeshInstance3D
var _camera: XRCamera3D
var _hands: Array[Dictionary] = []
var _panel_placed := false
var _plugin: Object
var _fade_material: StandardMaterial3D
var _handing_over := false


func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	else:
		push_error("OpenXR isn't running, the menu will only render to the window")

	_build_environment()
	var origin := XROrigin3D.new()
	add_child(origin)
	_camera = XRCamera3D.new()
	origin.add_child(_camera)
	for tracker in ["left_hand", "right_hand"]:
		_hands.append(_build_hand(origin, tracker))
	_build_panel()
	_build_fade()
	if Engine.has_singleton("Amethyst"):
		_plugin = Engine.get_singleton("Amethyst")


func _build_environment() -> void:
	add_child(preload("res://world.gd").new())


func _build_hand(origin: XROrigin3D, tracker: String) -> Dictionary:
	var controller := XRController3D.new()
	controller.tracker = tracker
	controller.pose = "aim"
	origin.add_child(controller)

	var ray := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.004, 0.004, 1.0)
	var ray_material := StandardMaterial3D.new()
	ray_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ray_material.albedo_color = Color(0.75, 0.55, 1.0)
	box.material = ray_material
	ray.mesh = box
	ray.visible = false
	controller.add_child(ray)

	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.008
	sphere.height = 0.016
	sphere.material = ray_material
	dot.mesh = sphere
	dot.visible = false
	add_child(dot)

	return {"controller": controller, "ray": ray, "dot": dot, "pressed": false, "next_scroll": 0}


func _build_panel() -> void:
	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	_viewport.gui_embed_subwindows = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var menu := preload("res://menu.gd").new()
	_viewport.add_child(menu)

	_panel = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = PANEL_SIZE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _viewport.get_texture()
	quad.material = material
	_panel.mesh = quad
	_panel.visible = false # Shown once it's placed in front of the headset
	add_child(_panel)


func _process(_delta: float) -> void:
	if _handing_over:
		return
	if _plugin and _plugin.isGameReady():
		_hand_over_to_game()
		return
	if not _panel_placed:
		_place_panel()
	for hand in _hands:
		_update_hand(hand)


## Puts the panel straight ahead of the headset at eye height, facing it. Waits until the
## headset reports a real pose, since the first frames can still be at the origin.
func _place_panel() -> void:
	var head := _camera.global_transform
	if head.origin == Vector3.ZERO:
		return
	var forward := -head.basis.z
	forward.y = 0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	_panel.global_position = head.origin + forward * PANEL_DISTANCE
	# look_at aims -Z at the target; the quad's visible side is +Z, so aim away from the player
	_panel.look_at(_panel.global_position + forward, Vector3.UP)
	_panel.visible = true
	_panel_placed = true


func _update_hand(hand: Dictionary) -> void:
	var controller: XRController3D = hand.controller
	var ray: MeshInstance3D = hand.ray
	var dot: MeshInstance3D = hand.dot
	if not controller.get_is_active():
		ray.visible = false
		dot.visible = false
		return

	var hit = _ray_to_panel(controller.global_transform)
	var length := 3.0
	if hit != null:
		length = controller.global_position.distance_to(hit.world)
		dot.global_position = hit.world
		_send_motion(hit.pixel)
	dot.visible = hit != null
	ray.visible = true
	ray.scale = Vector3(1, 1, length)
	ray.position = Vector3(0, 0, -length / 2.0)

	var trigger := controller.get_float("trigger")
	if not hand.pressed and trigger > TRIGGER_DOWN:
		hand.pressed = true
		if hit != null:
			_send_click(hit.pixel, true)
	elif hand.pressed and trigger < TRIGGER_UP:
		hand.pressed = false
		if hit != null:
			_send_click(hit.pixel, false)

	# The thumbstick scrolls whatever the pointer is on, like a mouse wheel
	var stick := controller.get_vector2("primary")
	if hit != null and absf(stick.y) > SCROLL_DEADZONE and Time.get_ticks_msec() >= hand.next_scroll:
		hand.next_scroll = Time.get_ticks_msec() + SCROLL_INTERVAL_MS
		_send_scroll(hit.pixel, stick.y > 0)


## Where a controller's ray hits the panel: {world, pixel}, or null
func _ray_to_panel(aim: Transform3D):
	var origin := aim.origin
	var direction := -aim.basis.z
	var normal := _panel.global_transform.basis.z
	var denominator := direction.dot(normal)
	if absf(denominator) < 0.0001:
		return null
	var distance := (_panel.global_position - origin).dot(normal) / denominator
	if distance < 0:
		return null
	var world := origin + direction * distance
	var local := _panel.to_local(world)
	var u := local.x / PANEL_SIZE.x + 0.5
	var v := 0.5 - local.y / PANEL_SIZE.y
	if u < 0 or u > 1 or v < 0 or v > 1:
		return null
	return {"world": world, "pixel": Vector2(u * VIEWPORT_SIZE.x, v * VIEWPORT_SIZE.y)}


func _send_motion(pixel: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pixel
	event.global_position = pixel
	_viewport.push_input(event, true)


func _send_click(pixel: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = pixel
	event.global_position = pixel
	_viewport.push_input(event, true)


func _send_scroll(pixel: Vector2, up: bool) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = pressed
		event.position = pixel
		event.global_position = pixel
		_viewport.push_input(event, true)


## A black sphere around the head, faded in before the game takes over the headset
func _build_fade() -> void:
	var fade := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	_fade_material = StandardMaterial3D.new()
	_fade_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fade_material.no_depth_test = true
	_fade_material.render_priority = Material.RENDER_PRIORITY_MAX
	_fade_material.albedo_color = Color(0, 0, 0, 0)
	sphere.material = _fade_material
	fade.mesh = sphere
	_camera.add_child(fade)


## Vivecraft opens its own OpenXR session on this activity about 2.5 seconds after the game
## says it's ready (VLoader.setupAndroid), the window QuestCraft's wrapper uses to fade out and
## shut down its XR. Do the same: fade to black, let Godot end its session, then free Godot's
## session and instance, since the runtime allows only one instance per process. The headset goes
## from this scene to the game without the Horizon loading room.
func _hand_over_to_game() -> void:
	_handing_over = true
	for hand in _hands:
		hand.ray.visible = false
		hand.dot.visible = false
	var tween := create_tween()
	tween.tween_property(_fade_material, "albedo_color:a", 1.0, FADE_SECONDS)
	await tween.finished

	var xr := XRServer.find_interface("OpenXR")
	if xr == null or not xr.is_initialized():
		return
	var api := OpenXRAPIExtension.new()
	var instance := api.get_instance()
	var session := api.get_session()
	var request_exit_session := api.get_instance_proc_addr("xrRequestExitSession")
	var destroy_session := api.get_instance_proc_addr("xrDestroySession")
	var destroy_instance := api.get_instance_proc_addr("xrDestroyInstance")

	# Godot calls xrEndSession itself once the runtime moves the session to STOPPING
	_plugin.callXr(request_exit_session, session)
	var deadline := Time.get_ticks_msec() + 1000
	while api.is_running() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	# Godot never touches OpenXR again once the interface is uninitialized and nothing renders
	xr.uninitialize()
	get_viewport().use_xr = false
	RenderingServer.render_loop_enabled = false
	await get_tree().process_frame
	await get_tree().process_frame
	_plugin.callXr(destroy_session, session)
	_plugin.callXr(destroy_instance, instance)

	# The game shares this process: leave it the CPU and memory. Godot's loop would otherwise
	# spin flat out (vsync is off for XR), and the menu scene would stay in memory.
	Engine.max_fps = 1
	OS.low_processor_usage_mode = true
	for child in get_children():
		child.queue_free()
