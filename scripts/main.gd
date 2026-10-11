extends Node3D

const PORT := 24567
const MAX_PLAYERS := 8
const ARENA_SIZE := 22.0

var players: Dictionary = {}
var local_id := 1
var host_field: LineEdit
var status_label: Label
var score_label: Label
var hud: Control
var move_touch := Vector2.ZERO
var fire_requested := false
var last_sync := 0.0
var last_shot := 0.0
var scores: Dictionary = {}
var health: Dictionary = {}
var spawn_points := [Vector3(-7, 0.8, -7), Vector3(7, 0.8, 7), Vector3(-7, 0.8, 7), Vector3(7, 0.8, -7), Vector3(0, 0.8, -8), Vector3(0, 0.8, 8), Vector3(-8, 0.8, 0), Vector3(8, 0.8, 0)]

func _ready() -> void:
	_build_arena()
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_set_status("Offline • Host a room or join by IP")

func _build_arena() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.055, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.85)
	env.ambient_light_energy = 0.8
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 25, 25)
	camera.rotation_degrees = Vector3(-42, 0, 0)
	camera.current = true
	camera.fov = 58
	add_child(camera)
	_make_box("Arena Floor", Vector3(0, -0.35, 0), Vector3(ARENA_SIZE * 2, 0.6, ARENA_SIZE * 2), Color(0.12, 0.17, 0.23))
	for x in [-ARENA_SIZE, ARENA_SIZE]:
		_make_box("Boundary", Vector3(x, 1, 0), Vector3(0.7, 2, ARENA_SIZE * 2), Color(0.12, 0.55, 0.72))
	for z in [-ARENA_SIZE, ARENA_SIZE]:
		_make_box("Boundary", Vector3(0, 1, z), Vector3(ARENA_SIZE * 2, 2, 0.7), Color(0.12, 0.55, 0.72))
	for i in range(12):
		var a := float(i) * 0.9
		var p := Vector3(cos(a) * 6.5, 0.8, sin(a) * 6.5)
		_make_box("Cover", p, Vector3(1.8, 1.6, 1.8), Color(0.18, 0.28, 0.38))
	for i in range(5):
		_make_box("Neon Strip", Vector3(-14 + i * 7, 0.02, 0), Vector3(0.08, 0.04, 26), Color(0.05, 0.45, 0.62))

func _make_box(label: String, pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.25
	mat.roughness = 0.65
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var collision := BoxShape3D.new()
	collision.size = size
	shape.shape = collision
	body.add_child(shape)
	add_child(body)

func _build_ui() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 16)
	panel.size = Vector2(360, 170)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "DAFAN ARENA  •  ALPHA"
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)
	status_label = Label.new()
	status_label.text = "Starting..."
	vb.add_child(status_label)
	score_label = Label.new()
	score_label.text = "Players: 1/8   •   Kills: 0   •   HP: 100"
	vb.add_child(score_label)
	var row := HBoxContainer.new()
	vb.add_child(row)
	var host_btn := Button.new()
	host_btn.text = "HOST ROOM"
	host_btn.pressed.connect(_host_game)
	row.add_child(host_btn)
	host_field = LineEdit.new()
	host_field.placeholder_text = "Server IP"
	host_field.text = "127.0.0.1"
	host_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(host_field)
	var join_btn := Button.new()
	join_btn.text = "JOIN"
	join_btn.pressed.connect(_join_game)
	row.add_child(join_btn)
	var hint := Label.new()
	hint.text = "Move: WASD / left touch • Fire: Space / FIRE"
	hint.add_theme_font_size_override("font_size", 13)
	vb.add_child(hint)
	hud.add_child(panel)
	var fire := Button.new()
	fire.text = "FIRE"
	fire.position = Vector2(-150, -130)
	fire.size = Vector2(120, 90)
	fire.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	fire.button_down.connect(func(): fire_requested = true)
	fire.button_up.connect(func(): fire_requested = false)
	hud.add_child(fire)
	var up := Button.new()
	up.text = "▲"
	up.position = Vector2(90, -205)
	up.size = Vector2(70, 65)
	up.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	up.button_down.connect(func(): move_touch.y = -1)
	up.button_up.connect(_release_vertical_up)
	hud.add_child(up)
	var down := Button.new()
	down.text = "▼"
	down.position = Vector2(90, -75)
	down.size = Vector2(70, 65)
	down.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	down.button_down.connect(func(): move_touch.y = 1)
	down.button_up.connect(_release_vertical_down)
	hud.add_child(down)
	var left := Button.new()
	left.text = "◀"
	left.position = Vector2(15, -140)
	left.size = Vector2(70, 65)
	left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	left.button_down.connect(func(): move_touch.x = -1)
	left.button_up.connect(_release_horizontal_left)
	hud.add_child(left)
	var right := Button.new()
	right.text = "▶"
	right.position = Vector2(165, -140)
	right.size = Vector2(70, 65)
	right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	right.button_down.connect(func(): move_touch.x = 1)
	right.button_up.connect(_release_horizontal_right)
	hud.add_child(right)

func _release_vertical_up() -> void:
	if move_touch.y < 0: move_touch.y = 0

func _release_vertical_down() -> void:
	if move_touch.y > 0: move_touch.y = 0

func _release_horizontal_left() -> void:
	if move_touch.x < 0: move_touch.x = 0

func _release_horizontal_right() -> void:
	if move_touch.x > 0: move_touch.x = 0

func _host_game() -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		_set_status("Already connected. Restart the app to host again.")
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		_set_status("Host failed: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	local_id = 1
	_add_player(1, true)
	_set_status("Room hosted • UDP port %d • share your reachable IP" % PORT)

func _join_game() -> void:
	var ip := host_field.text.strip_edges()
	if ip.is_empty():
		_set_status("Enter the host IP address")
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		_set_status("Join failed: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	_set_status("Connecting to %s:%d ..." % [ip, PORT])

func _on_connected() -> void:
	local_id = multiplayer.get_unique_id()
	_set_status("Connected • Player ID %d" % local_id)
	rpc_id(1, "request_spawn", local_id)

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	_set_status("Connection failed. Check IP, UDP port and firewall.")

func _on_server_disconnected() -> void:
	_set_status("Server disconnected")

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		for existing_id in players.keys():
			rpc_id(id, "spawn_remote", int(existing_id), players[existing_id].position)

func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
		scores.erase(id)
		health.erase(id)
	_update_stats()

@rpc("any_peer", "reliable")
func request_spawn(id: int) -> void:
	if not multiplayer.is_server(): return
	var sender := multiplayer.get_remote_sender_id()
	if sender != id: return
	if players.size() >= MAX_PLAYERS: return
	var pos: Vector3 = spawn_points[posmod(id, spawn_points.size())]
	_add_player(id, false, pos)
	rpc("spawn_remote", id, pos)

@rpc("authority", "call_local", "reliable")
func spawn_remote(id: int, pos: Vector3) -> void:
	if players.has(id): return
	_add_player(id, id == local_id, pos)

func _add_player(id: int, is_local: bool, pos: Vector3 = Vector3.ZERO) -> void:
	if players.has(id): return
	var character := CharacterBody3D.new()
	character.name = "Player_%d" % id
	character.position = pos if pos != Vector3.ZERO else spawn_points[posmod(id, spawn_points.size())]
	character.set_meta("player_id", id)
	character.set_meta("local_player", is_local)
	var capsule := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.42
	mesh.height = 1.55
	capsule.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.85, 1.0) if is_local else Color(1.0, 0.3, 0.22)
	material.metallic = 0.3
	capsule.material_override = material
	character.add_child(capsule)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.55
	col.shape = shape
	character.add_child(col)
	var pivot := Node3D.new()
	pivot.name = "AimPivot"
	pivot.position.y = 0.35
	character.add_child(pivot)
	var gun := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.18, 0.16, 0.8)
	gun.mesh = gm
	gun.position = Vector3(0.3, 0, -0.45)
	var gunmat := StandardMaterial3D.new()
	gunmat.albedo_color = Color(0.1, 0.95, 0.65)
	gun.material_override = gunmat
	pivot.add_child(gun)
	add_child(character)
	players[id] = character
	scores[id] = scores.get(id, 0)
	health[id] = health.get(id, 100)
	_update_stats()

func _process(delta: float) -> void:
	if players.has(local_id):
		var p: CharacterBody3D = players[local_id]
		var input := Vector2.ZERO
		input.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
		input.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
		input += move_touch
		if input.length() > 1: input = input.normalized()
		var direction := Vector3(input.x, 0, input.y)
		p.velocity.x = direction.x * 7.0
		p.velocity.z = direction.z * 7.0
		p.velocity.y = 0
		p.move_and_slide()
		p.position.x = clampf(p.position.x, -ARENA_SIZE + 1, ARENA_SIZE - 1)
		p.position.z = clampf(p.position.z, -ARENA_SIZE + 1, ARENA_SIZE - 1)
		if direction.length() > 0.1:
			p.rotation.y = atan2(direction.x, direction.z)
		last_sync += delta
		if last_sync > 0.05:
			last_sync = 0
			if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				if multiplayer.is_server():
					rpc("relay_player", local_id, p.position, p.rotation.y)
				else:
					rpc_id(1, "sync_player", local_id, p.position, p.rotation.y)
		if Input.is_action_pressed("ui_accept") or fire_requested:
			last_shot += delta
			if last_shot >= 0.35:
				last_shot = 0
				_shoot()
	_update_stats()

@rpc("any_peer", "unreliable")
func sync_player(id: int, pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server(): return
	if id != multiplayer.get_remote_sender_id(): return
	if not players.has(id): return
	players[id].position = pos
	players[id].rotation.y = rot_y
	rpc("relay_player", id, pos, rot_y)

@rpc("authority", "call_remote", "unreliable")
func relay_player(id: int, pos: Vector3, rot_y: float) -> void:
	if players.has(id) and id != local_id:
		players[id].position = players[id].position.lerp(pos, 0.7)
		players[id].rotation.y = rot_y

func _shoot() -> void:
	if not players.has(local_id): return
	var shooter: Node3D = players[local_id]
	var best_id := -1
	var best_dist := 8.5
	var forward := Vector3(sin(shooter.rotation.y), 0, cos(shooter.rotation.y))
	for id in players.keys():
		if int(id) == local_id: continue
		var target: Node3D = players[id]
		var diff := target.global_position - shooter.global_position
		var flat := Vector3(diff.x, 0, diff.z)
		var dist := flat.length()
		if dist < best_dist and dist > 0.1 and forward.dot(flat.normalized()) > 0.78:
			best_id = int(id)
			best_dist = dist
	if best_id >= 0:
		if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			if multiplayer.is_server():
				_apply_hit(best_id, local_id)
				rpc("apply_hit_remote", best_id, local_id)
			else:
				rpc_id(1, "request_hit", best_id)
		else:
			_apply_hit(best_id, local_id)

@rpc("any_peer", "reliable")
func request_hit(target_id: int) -> void:
	if not multiplayer.is_server(): return
	var shooter_id := multiplayer.get_remote_sender_id()
	if not players.has(shooter_id) or not players.has(target_id) or shooter_id == target_id: return
	var dist: float = players[shooter_id].global_position.distance_to(players[target_id].global_position)
	if dist > 10.0: return
	_apply_hit(target_id, shooter_id)
	rpc("apply_hit_remote", target_id, shooter_id)

@rpc("authority", "call_local", "reliable")
func apply_hit_remote(target_id: int, shooter_id: int) -> void:
	if multiplayer.is_server(): return
	_apply_hit(target_id, shooter_id)

func _apply_hit(target_id: int, shooter_id: int) -> void:
	if not health.has(target_id): return
	health[target_id] = int(health[target_id]) - 25
	if int(health[target_id]) <= 0:
		scores[shooter_id] = int(scores.get(shooter_id, 0)) + 1
		health[target_id] = 100
		if players.has(target_id):
			players[target_id].position = spawn_points[posmod(target_id + int(scores[shooter_id]), spawn_points.size())]
	_update_stats()

func _update_stats() -> void:
	if score_label == null: return
	var my_score := int(scores.get(local_id, 0))
	var my_hp := int(health.get(local_id, 100))
	score_label.text = "Players: %d/%d   •   Kills: %d   •   HP: %d" % [players.size(), MAX_PLAYERS, my_score, my_hp]

func _set_status(message: String) -> void:
	if status_label != null: status_label.text = message
