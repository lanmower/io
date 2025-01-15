extends Node

signal player_spawned(peer_id: int, player_info: Dictionary)
signal player_connected(id: int)
signal player_disconnected(id: int)

var spawnedPlayers: Dictionary = {}
var mapSeed: int = 0
var players = {}
var my_info = {"name": ""}
var playerScenePath = preload("res://scenes/character/player.tscn")
var main: Node2D
var map: Node2D

func _ready():
	# Initialize multiplayer API
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)

func _on_player_connected(id: int):
	player_connected.emit(id)

func _on_player_disconnected(id: int):
	player_disconnected.emit(id)
	if players.has(id):
		players.erase(id) 

@rpc("authority", "call_remote", "reliable")
func _register_character(new_player_id: int, new_player_info: Dictionary):
	spawnedPlayers[new_player_id] = new_player_info
	player_spawned.emit(new_player_id, new_player_info)  # Emit the signal when a player is registered
	print("Player ", new_player_id, " registered with info: ", new_player_info) 

@rpc("any_peer", "call_local", "reliable")
func spawnPlayer(playerName, id, characterFile):
	var newPlayer = playerScenePath.instantiate()
	newPlayer.playerName = playerName
	newPlayer.characterFile = characterFile
	newPlayer.name = str(id)
	main.get_node("Players").add_child(newPlayer)
	
	# Get a valid spawn position on grass
	var spawnPos = Vector2.ZERO
	var mapNode = main.get_node("Map")
	
	# First try: Use center of map and expand outward until we find grass
	var center = Vector2i(mapNode.map_width/2, mapNode.map_height/2)
	var found = false
	
	# Search in expanding square from center
	for radius in range(20):  # Maximum search radius of 20 tiles
		if found: break
		
		# Check in a spiral pattern from center
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or x >= mapNode.map_width: continue
			for y in range(center.y - radius, center.y + radius + 1):
				if y < 0 or y >= mapNode.map_height: continue
				
				var pos = Vector2i(x, y)
				var tileCoords = mapNode.tile_map_layer.get_cell_atlas_coords(pos)
				
				# Only spawn on grass tiles
				if mapNode.grassAtlasCoords.has(tileCoords):
					# Check surrounding tiles to make sure we're not near water
					var is_safe = true
					for dx in range(-2, 3):
						for dy in range(-2, 3):
							var check_pos = Vector2i(x + dx, y + dy)
							if check_pos.x >= 0 and check_pos.x < mapNode.map_width and check_pos.y >= 0 and check_pos.y < mapNode.map_height:
								var check_coords = mapNode.tile_map_layer.get_cell_atlas_coords(check_pos)
								if mapNode.waterCoors.has(check_coords):
									is_safe = false
									break
						if not is_safe: break
					
					if is_safe:
						spawnPos = mapNode.tile_map_layer.map_to_local(pos)
						found = true
						break
			if found: break
	
	# Emergency fallback: Force create a safe grass area in the center
	if !found:
		print("Emergency: Creating safe spawn area in center")
		var safe_center = Vector2i(mapNode.map_width/2, mapNode.map_height/2)
		# Create a safe grass area (5x5)
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var pos = safe_center + Vector2i(dx, dy)
				if pos.x >= 0 and pos.x < mapNode.map_width and pos.y >= 0 and pos.y < mapNode.map_height:
					mapNode.tile_map_layer.set_cell(pos, mapNode.tileset_source, mapNode.grassAtlasCoords.pick_random())
					mapNode.terrain_data[pos] = "grass"
		spawnPos = mapNode.tile_map_layer.map_to_local(safe_center)
	
	# Only send position if we found a valid spawn point
	if spawnPos != Vector2.ZERO:
		newPlayer.sendPos.rpc(spawnPos)
	else:
		push_error("Failed to find valid spawn position for player ", id) 