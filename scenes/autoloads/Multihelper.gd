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
	
	# If there are no active players and we're the server, reset the game
	if multiplayer.is_server():
		var active_players = []
		for id in spawnedPlayers.keys():
			# Check if the player is still connected
			if id in multiplayer.get_peers() or id == 1:  # Include server (id 1)
				active_players.append(id)
		
		if active_players.is_empty():
			main = get_node("/root/Game/Level/Main")
			
			# Reset the day/night cycle first and wait for it to complete
			var dayNight = main.get_node("dayNight")
			dayNight.current_day = 0
			dayNight.current_hour = 6  # Start at 6 AM
			dayNight.current_minute = 0
			dayNight.sync_time.rpc(0, 6, 0)
			dayNight.time_tick.emit(0, 6, 0)
			
			# Reset main scene state
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
			
			# Give a small delay to ensure everything is synced
			await get_tree().create_timer(0.1).timeout
	
	# Now register the player
	spawnedPlayers[new_player_id] = new_player_info
	player_spawned.emit(new_player_id, new_player_info)
	player_registered.emit()

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
	main = game.get_node("Level/Main")
	var dayNight = main.get_node("dayNight")
	
	# If this is the first player loading, wait a bit to ensure reset is complete
	if multiplayer.is_server() and spawnedPlayers.size() == 1:
		await get_tree().create_timer(0.2).timeout
	
	var mapData := {
		"seed": mapSeed,
		"current_day": main.current_day,
		"current_hour": dayNight.current_hour,
		"current_minute": dayNight.current_minute
	}
	sendGameData.rpc_id(sender_id, spawnedPlayers, mapData)
	set_process(false)

@rpc("authority", "call_remote", "reliable")
func sendGameData(playerData, mapData):
	spawnedPlayers = playerData
	mapSeed = mapData["seed"]
	main = get_node("/root/Game/Level/Main")
	map = main.get_node("Map")
	
	# Sync time state
	if mapData.has("current_day"):
		main.current_day = mapData["current_day"]
		var dayNight = main.get_node("dayNight")
		dayNight.sync_time.rpc(mapData["current_day"], mapData["current_hour"], mapData["current_minute"])
	
	# Clear any existing map data on client
	if !multiplayer.is_server():
		map.clear_map()
	
	data_loaded.emit()
	set_process(true)

func _on_connected_fail():
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()

func loadMap():
	# This function is now only used by the server
	if !multiplayer.is_server():
		return
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
	
	# Get a valid spawn position on grass
	var spawnPos = Vector2.ZERO
	var valid_tiles = []
	
	# First try: Use center of map and expand outward until we find grass
	var center = Vector2i(map.map_width/2, map.map_height/2)
	var found = false
	
	# Search in expanding square from center
	for radius in range(20):  # Maximum search radius of 20 tiles
		if found: break
		
		# Check in a spiral pattern from center
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or x >= map.map_width: continue
			for y in range(center.y - radius, center.y + radius + 1):
				if y < 0 or y >= map.map_height: continue
				
				var pos = Vector2i(x, y)
				var tileCoords = map.tile_map.get_cell_atlas_coords(pos)
				
				# Only spawn on grass tiles
				if map.grassAtlasCoords.has(tileCoords):
					# Check surrounding tiles to make sure we're not near water
					var is_safe = true
					for dx in range(-2, 3):
						for dy in range(-2, 3):
							var check_pos = Vector2i(x + dx, y + dy)
							if check_pos.x >= 0 and check_pos.x < map.map_width and check_pos.y >= 0 and check_pos.y < map.map_height:
								var check_coords = map.tile_map.get_cell_atlas_coords(check_pos)
								if map.waterCoors.has(check_coords):
									is_safe = false
									break
						if not is_safe: break
					
					if is_safe:
						spawnPos = map.tile_map.map_to_local(pos)
						found = true
						break
			if found: break
	
	# Emergency fallback: Force create a safe grass area in the center
	if spawnPos == Vector2.ZERO:
		print("Emergency: Creating safe spawn area in center")
		var safe_center = Vector2i(map.map_width/2, map.map_height/2)
		# Create a safe grass area (5x5)
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var pos = safe_center + Vector2i(dx, dy)
				if pos.x >= 0 and pos.x < map.map_width and pos.y >= 0 and pos.y < map.map_height:
						map.set_tile(pos, "grass", map.grassAtlasCoords.pick_random())
		spawnPos = map.tile_map.map_to_local(safe_center)
	
	newPlayer.sendPos.rpc(spawnPos)

@rpc("any_peer", "call_remote", "reliable")
func showSpawnUI():
	var spawnPlayerScene := preload("res://scenes/ui/spawn/spawnPlayer.tscn")
	var retry = spawnPlayerScene.instantiate()
	retry.retry = true
	get_node("/root/Game/Level/Main/HUD").add_child(retry)
