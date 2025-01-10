# godot 4.3
extends Node

var playerScenePath = preload("res://scenes/character/player.tscn")
var isHost = false
var mapSeed = randi()
var map: Node2D
var main: Node2D
var debug_camera_settings = null

signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal server_disconnected
signal player_spawned(peer_id, player_info)
signal player_despawned
signal player_registered
@warning_ignore("unused_signal")
signal player_score_updated
signal data_loaded

const PORT = Constants.PORT
const DEFAULT_SERVER_IP = Constants.SERVER_IP

var spawnedPlayers = {}
var connectedPlayers = []
var syncedPlayers = []

var player_info = {"name": ""}

@onready var game = get_node("/root/Game")
func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func join_game(address = ""):
	if address.is_empty():
		address = DEFAULT_SERVER_IP
	multiplayer.multiplayer_peer = null
	var peer = WebSocketMultiplayerPeer.new()
	var error
	if OS.has_feature("editor"):
		error = peer.create_client("ws://" + address + ":8443")
	else:
		if Constants.USE_SSL:
			var tlsOptions = TLSOptions.client()
			error = peer.create_client("wss://" + address, tlsOptions)
		else:
			var tlsOptions = TLSOptions.client()
			error = peer.create_client("wss://" + address, tlsOptions)
	if error:
		return error
	multiplayer.multiplayer_peer = peer

func create_game():
	var peer = WebSocketMultiplayerPeer.new()
	var error
	if Constants.USE_SSL:
		var priv := load(Constants.PRIVATE_KEY_PATH)
		var cert := load(Constants.TRUSTED_CHAIN_PATH)
		var tlsOptions = TLSOptions.server(priv, cert)
		error = peer.create_server(PORT, "*", tlsOptions)
	else:
		error = peer.create_server(PORT, "*")
	if error:
		return error
	multiplayer.multiplayer_peer = peer
	player_connected.emit(1, player_info)
	game.start_game()

func remove_multiplayer_peer():
	multiplayer.multiplayer_peer = null

func _on_player_connected(id):
	print("player connected with id "+str(id)+" to "+str(multiplayer.get_unique_id()))

@rpc("call_local" ,"any_peer", "reliable")
func _register_character(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	spawnedPlayers[new_player_id] = new_player_info
	
	# If this is the first player and we're the server, reset the game
	if multiplayer.is_server() and spawnedPlayers.size() == 1:
		main = get_node("/root/Game/Level/Main")
		# Reset day and clear objects/enemies
		main.current_day = 0
		main.boss_spawned = false
		# Clear all enemies
		for enemy in main.get_node("Enemies").get_children():
			enemy.queue_free()
		main.spawnedEnemies.clear()
		# Clear all objects
		for object in main.get_node("Objects").get_children():
			object.queue_free()
		main.spawnedObjects = 0
		# Spawn initial objects
		main.spawnObjects(main.initialSpawnObjects)
	
	player_spawned.emit(new_player_id, new_player_info)
	player_registered.emit()
	
@rpc("call_local" ,"any_peer", "reliable")
func _deregister_character(id):
	spawnedPlayers.erase(id)
	player_despawned.emit()

func _on_player_disconnected(id):
	connectedPlayers.erase(id)
	spawnedPlayers.erase(id)
	syncedPlayers.erase(id)
	player_disconnected.emit(id)

func _on_connected_ok():
	game.start_game()
	var peer_id = multiplayer.get_unique_id()
	connectedPlayers.append(peer_id)
	player_connected.emit(peer_id)
	load_main_game()
	
func load_main_game():
	player_loaded.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func player_loaded():
	var sender_id = multiplayer.get_remote_sender_id()
	#print("remote sender:"+str(sender_id))
	main = game.get_node("Level/Main")
	var mapData := {
		"seed": mapSeed,
	}
	sendGameData.rpc_id(sender_id, spawnedPlayers, mapData)
	#print(connectedPlayers)
	set_process(false)

@rpc("authority", "call_remote", "reliable")
func sendGameData(playerData, mapData):
	spawnedPlayers = playerData
	mapSeed = mapData["seed"]
	main = game.get_node("Level/Main")
	loadMap()
	data_loaded.emit()
	set_process(true)

func _on_connected_fail():
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()

func loadMap():
	main = get_node("/root/Game/Level/Main")
	map = main.get_node("Map")
	map.generateMap()

func requestSpawn(playerName, id, characterFile):
	player_info["name"] = playerName
	player_info["body"] = characterFile
	player_info["score"] = 0
	spawnedPlayers[id] = player_info
	_register_character.rpc(player_info)
	spawnPlayer.rpc_id(1, playerName, id, characterFile)

@rpc("any_peer", "call_local", "reliable")
func spawnPlayer(playerName, id, characterFile):
	var newPlayer := playerScenePath.instantiate()
	newPlayer.playerName = playerName
	newPlayer.characterFile = characterFile
	newPlayer.name = str(id)
	main.get_node("Players").add_child(newPlayer)
	
	# Get a valid spawn position that's definitely not water
	var spawnPos = Vector2.ZERO
	var attempts = 0
	var maxAttempts = 20  # Increased attempts
	
	# First try: Use walkable tiles
	while attempts < maxAttempts and spawnPos == Vector2.ZERO:
		if map.walkable_tiles.size() > 0:
			var candidatePos = map.walkable_tiles.pick_random()
			var tileCoords = map.tile_map.get_cell_atlas_coords(candidatePos)
			if map.grassAtlasCoords.has(tileCoords):  # Only spawn on grass
				spawnPos = map.tile_map.map_to_local(candidatePos)
		attempts += 1
	
	# Second try: Scan for grass tiles if walkable tiles failed
	if spawnPos == Vector2.ZERO:
		print("Warning: Failed to find spawn position from walkable tiles, scanning for grass...")
		var centerX = map.map_width / 2
		var centerY = map.map_height / 2
		var radius = 1
		
		while radius < max(map.map_width, map.map_height) / 2:
			for y in range(centerY - radius, centerY + radius + 1):
				for x in range(centerX - radius, centerX + radius + 1):
					if x < 0 or x >= map.map_width or y < 0 or y >= map.map_height:
						continue
					
					var pos = Vector2i(x, y)
					var tileCoords = map.tile_map.get_cell_atlas_coords(pos)
					if map.grassAtlasCoords.has(tileCoords):
						spawnPos = map.tile_map.map_to_local(pos)
						break
				if spawnPos != Vector2.ZERO:
					break
			if spawnPos != Vector2.ZERO:
				break
			radius += 1
	
	# Emergency fallback: Use a hardcoded safe position
	if spawnPos == Vector2.ZERO:
		print("Error: Could not find valid spawn position, using emergency fallback")
		spawnPos = map.tile_map.map_to_local(Vector2i(map.map_width/2, map.map_height/2))
	
	newPlayer.sendPos.rpc(spawnPos)

@rpc("any_peer", "call_remote", "reliable")
func showSpawnUI():
	var spawnPlayerScene := preload("res://scenes/ui/spawn/spawnPlayer.tscn")
	var retry = spawnPlayerScene.instantiate()
	retry.retry = true
	get_node("/root/Game/Level/Main/HUD").add_child(retry)
