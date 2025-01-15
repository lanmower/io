# godot 4.3
extends Node2D

var map_width = 100
var map_height = 100

var tileset_source = 1  # This matches the source ID in the tileset

@onready var tile_map: TileMap = $TileMap  # The TileMap node

var grassAtlasCoords = [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0)]
var waterCoors = [Vector2i(18,0), Vector2i(19,0)]
var sandCoords = [Vector2i(4,0), Vector2i(5,0)]
var cementCoords = [Vector2i(8,0), Vector2i(9,0), Vector2i(10,0), Vector2i(11,0)]
var wallCoords = [Vector2i(8,12)]

var walkable_tiles: Array = []
var terrain_data: Dictionary = {}

var noise = FastNoiseLite.new()

# Noise parameters
var tile_size = 64

func _ready():
	print("Map _ready called, is_server: ", multiplayer.is_server())
	# Verify TileMap references
	if !tile_map:
		push_error("TileMap node not found!")
		print("tile_map: ", tile_map)
		return
		
	# Verify tileset source
	if !tile_map.tile_set or !tile_map.tile_set.has_source(tileset_source):
		push_error("TileMap is missing required tileset source: ", tileset_source)
		var has_source = false
		if tile_map.tile_set:
			has_source = tile_map.tile_set.has_source(tileset_source)
		print("tile_set: ", tile_map.tile_set, ", has_source: ", has_source)
		return
		
	# Initialize noise for tinting - use same settings as terrain generation
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.frequency = 0.02
	noise.seed = Multihelper.mapSeed
	print("Map initialized with seed: ", Multihelper.mapSeed)
	
	# Only generate if we're the server
	if multiplayer.is_server():
		print("Server generating initial map")
		generateMap()
	else:
		print("Client waiting for map data")
		initialize_client()

func initialize_client():
	print("Client initializing map")
	if !tile_map:
		push_error("Cannot initialize client - TileMap node not found!")
		return
		
	clear_map()
	print("Client requesting map data from server")
	request_map_data.rpc_id(1)

func clear_map():
	if !tile_map:
		push_error("Cannot clear map - TileMap node not found!")
		return
		
	terrain_data.clear()
	walkable_tiles.clear()
	for x in range(map_width):
		for y in range(map_height):
			tile_map.erase_cell(0, Vector2i(x, y))

@rpc("any_peer", "call_remote", "reliable")
func request_map_data():
	print("Received map data request from peer: ", multiplayer.get_remote_sender_id())
	if multiplayer.is_server():
		var peer_id = multiplayer.get_remote_sender_id()
		print("Server sending map data to peer ", peer_id)
		# Wait a few frames to ensure everything is set up
		await get_tree().create_timer(0.5).timeout
		send_full_map_to_client(peer_id)
	else:
		print("Warning: Non-server received map data request")

func send_full_map_to_client(peer_id: int):
	if !multiplayer.is_server():
		print("Warning: Non-server tried to send map data")
		return
		
	if !tile_map:
		push_error("Cannot send map data - TileMap node not found!")
		return
		
	print("Preparing map data for client ", peer_id)
	var map_tiles = []
	var total_cells = 0
	var valid_cells = 0
	
	for y in range(map_height):
		for x in range(map_width):
			total_cells += 1
			var pos = Vector2i(x, y)
			var source_id = tile_map.get_cell_source_id(0, pos)
			if source_id != -1:  # If tile exists
				valid_cells += 1
				var atlas_coords = tile_map.get_cell_atlas_coords(0, pos)
				var terrain_type = terrain_data.get(pos, "")
				map_tiles.append([pos, atlas_coords, terrain_type])
	
	print("Server checked ", total_cells, " cells, found ", valid_cells, " valid cells")
	print("Server sending ", map_tiles.size(), " tiles to client ", peer_id)
	print("Current terrain_data size: ", terrain_data.size())
	
	if map_tiles.size() == 0:
		push_error("No tiles to send! Map may not be generated yet.")
		print("Attempting to regenerate map...")
		generateMap()
		# Rebuild map_tiles array after regeneration
		for y in range(map_height):
			for x in range(map_width):
				var pos = Vector2i(x, y)
				var source_id = tile_map.get_cell_source_id(0, pos)
				if source_id != -1:
					var atlas_coords = tile_map.get_cell_atlas_coords(0, pos)
					var terrain_type = terrain_data.get(pos, "")
					map_tiles.append([pos, atlas_coords, terrain_type])
		print("After regeneration: ", map_tiles.size(), " tiles")
	
	if map_tiles.size() > 0:
		print("First tile data: pos=", map_tiles[0][0], " atlas=", map_tiles[0][1], " type=", map_tiles[0][2])
		sync_full_map.rpc_id(peer_id, map_tiles)
		sync_walkable_tiles.rpc_id(peer_id, walkable_tiles)
	else:
		push_error("Still no tiles after regeneration attempt!")

@rpc("authority", "call_remote", "reliable")
func sync_full_map(map_tiles: Array):
	if !tile_map:
		push_error("Cannot sync map - TileMap node not found!")
		return
		
	print("Client received map data with ", map_tiles.size(), " tiles")
	clear_map()
	
	# map_tiles is array of [pos, atlas_coords, terrain_type]
	var tiles_placed = 0
	var errors = 0
	
	for tile in map_tiles:
		var pos = tile[0]
		var atlas_coords = tile[1]
		var terrain_type = tile[2]
		
		if pos.x >= 0 and pos.x < map_width and pos.y >= 0 and pos.y < map_height:
			tile_map.set_cell(0, pos, tileset_source, atlas_coords)
			var new_source_id = tile_map.get_cell_source_id(0, pos)
			
			if new_source_id == -1:
				errors += 1
				print("Failed to place tile at pos: ", pos, " atlas_coords: ", atlas_coords)
			else:
				tiles_placed += 1
				if terrain_type:
					terrain_data[pos] = terrain_type
			
			if tiles_placed == 1 or tiles_placed % 1000 == 0:
				print("Client progress: placed ", tiles_placed, " tiles, errors: ", errors)
	
	print("Client finished processing map data:")
	print("- Tiles placed: ", tiles_placed)
	print("- Errors: ", errors)
	print("- Terrain data size: ", terrain_data.size())
	
	if tiles_placed == 0:
		print("Warning: No tiles were placed! Requesting map data again...")
		await get_tree().create_timer(1.0).timeout
		request_map_data.rpc_id(1)

func generateMap():
	# Clear terrain data at start
	terrain_data.clear()
	
	# Use the noise settings already initialized in _ready()
	generate_terrain()
	
	# Clear any invalid tiles from walkable_tiles
	walkable_tiles = walkable_tiles.filter(func(pos): 
		var tile_data = tile_map.get_cell_tile_data(0, pos)
		if !tile_data:  # No tile at this position
			return false
		var coords = tile_map.get_cell_atlas_coords(0, pos)
		return not waterCoors.has(coords)
	)
	
	# If we're the server, sync walkable tiles and terrain data to clients
	if multiplayer.is_server():
		sync_walkable_tiles.rpc(walkable_tiles)
		sync_terrain_data.rpc(terrain_data)

@rpc("authority", "call_remote", "reliable")
func sync_walkable_tiles(tiles: Array):
	walkable_tiles = tiles

@rpc("authority", "call_remote", "reliable")
func sync_terrain_data(data: Dictionary):
	terrain_data = data

func generate_terrain():
	print("Starting terrain generation with seed: ", noise.seed)
	# Clear walkable tiles at start
	walkable_tiles.clear()
	
	# First pass: Generate basic terrain with more water
	var terrain_types = {}
	print("Generating basic terrain...")
	
	for x in range(map_width):
		for y in range(map_height):
			var pos = Vector2i(x, y)
			var noise_value = noise.get_noise_2d(x * 0.1, y * 0.1)
			
			if noise_value < 0.0:  # Increased threshold for more water
				terrain_types[pos] = "water"
			else:
				terrain_types[pos] = "grass"
				walkable_tiles.append(pos)
	
	print("Basic terrain generated. Walkable tiles: ", walkable_tiles.size())
	print("Applying terrain to tilemap...")
	
	# Apply terrain to tilemap
	var tiles_set = 0
	for pos in terrain_types:
		match terrain_types[pos]:
			"grass":
				tile_map.set_cell(0, pos, tileset_source, grassAtlasCoords.pick_random())
				tiles_set += 1
			"water":
				tile_map.set_cell(0, pos, tileset_source, waterCoors.pick_random())
				tiles_set += 1
			"sand":
				tile_map.set_cell(0, pos, tileset_source, sandCoords.pick_random())
				tiles_set += 1
			"cement":
				tile_map.set_cell(0, pos, tileset_source, cementCoords.pick_random())
				tiles_set += 1
	
	print("Tiles set in tilemap: ", tiles_set)
	
	# Store terrain data
	terrain_data = terrain_types.duplicate()
	print("Terrain data size: ", terrain_data.size())
