extends Node3D
## VR scene: a floating panel showing the menu UI, and laser pointers on both controllers
## that turn trigger presses into mouse clicks on the panel.

const PANEL_SIZE := Vector2(1.6, 1.0) # meters
const VIEWPORT_SIZE := Vector2i(1280, 800) # pixels
const PANEL_DISTANCE := 1.3 # meters in front of the headset
const TRIGGER_DOWN := 0.6
const TRIGGER_UP := 0.4

var _viewport: SubViewport
var _panel: MeshInstance3D
var _camera: XRCamera3D
var _hands: Array[Dictionary] = []
var _panel_placed := false


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


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.14, 0.11, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# A floor so the room doesn't feel like a void
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.25, 0.2, 0.32)
	plane.material = floor_material
	floor_mesh.mesh = plane
	add_child(floor_mesh)


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

	return {"controller": controller, "ray": ray, "dot": dot, "pressed": false}


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
