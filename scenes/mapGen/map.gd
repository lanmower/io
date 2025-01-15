# godot 4.3
extends Node2D

var map_width = 100
var map_height = 100

var tileset_source = 1  # This matches the source ID in the tileset

@onready var tile_map: TileMapLayer = $TileMapLayer  # Changed from TileMap to TileMapLayer

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
	# Verify TileMap reference
	if !tile_map:
		push_error("TileMap node not found!")
		return
		
	# Verify tileset source
	if !tile_map.tile_set or !tile_map.tile_set.has_source(tileset_source):
		push_error("TileMap is missing required tileset source: ", tileset_source)
		return
		
	# Get the tileset source and validate it
	var source = tile_map.tile_set.get_source(tileset_source)
	if !source:
		push_error("Could not get tileset source")
		return
		
	# Validate that our basic tiles exist without checking tile data
	var missing_tiles = []
	for coords in grassAtlasCoords:
		if !source.has_tile(coords):
			missing_tiles.append("grass:" + str(coords))
	for coords in waterCoors:
		if !source.has_tile(coords):
			missing_tiles.append("water:" + str(coords))
	for coords in sandCoords:
		if !source.has_tile(coords):
			missing_tiles.append("sand:" + str(coords))
	for coords in cementCoords:
		if !source.has_tile(coords):
			missing_tiles.append("cement:" + str(coords))
	for coords in wallCoords:
		if !source.has_tile(coords):
			missing_tiles.append("wall:" + str(coords))
			
	if missing_tiles.size() > 0:
		push_error("Missing required tiles: " + str(missing_tiles))
		return
		
	print("TileMap node found and tileset source verified with all required tiles")
	
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
	clear_map()
	print("Client requesting map data from server")
	request_map_data.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func request_map_data():
	print("Received map data request from peer: ", multiplayer.get_remote_sender_id())
	if multiplayer.is_server():
		var peer_id = multiplayer.get_remote_sender_id()
		print("Server sending map data to peer ", peer_id)
		send_full_map_to_client(peer_id)
	else:
		print("Warning: Non-server received map data request")

func generateMap():
	# Clear terrain data at start
	terrain_data.clear()
	
	# Use the noise settings already initialized in _ready()
	generate_terrain()
	
	# Clear any invalid tiles from walkable_tiles
	walkable_tiles = walkable_tiles.filter(func(pos): 
		var tile_data = tile_map.get_cell_tile_data(pos)
		if !tile_data:  # No tile at this position
			return false
		var coords = tile_map.get_cell_atlas_coords(pos)
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

func clear_map():
	if !tile_map:
		push_error("Cannot clear map - TileMap node not found!")
		return
		
	terrain_data.clear()
	walkable_tiles.clear()
	for x in range(map_width):
		for y in range(map_height):
			tile_map.erase_cell(Vector2i(x, y))

func get_height_at(pos: Vector2i) -> float:
	if pos.x < 0 or pos.x >= map_width or pos.y < 0 or pos.y >= map_height:
		return 0.0
		
	# First check if there's a tile at this position
	var tile_data = tile_map.get_cell_tile_data(pos)
	if !tile_data:  # No tile at this position
		return 0.0
		
	var atlas_coords = tile_map.get_cell_atlas_coords(pos)
	
	if waterCoors.has(atlas_coords):
		return 0.0
		
	# Find nearest water
	var max_distance = 6
	var min_dist = max_distance
	
	for dx in range(-max_distance, max_distance + 1):
		for dy in range(-max_distance, max_distance + 1):
			var check_pos = pos + Vector2i(dx, dy)
			if check_pos.x >= 0 and check_pos.x < map_width and check_pos.y >= 0 and check_pos.y < map_height:
				tile_data = tile_map.get_cell_tile_data(check_pos)
				if tile_data:  # Only check if there's a tile
					var check_coords = tile_map.get_cell_atlas_coords(check_pos)
					if waterCoors.has(check_coords):
						var dist = sqrt(dx * dx + dy * dy)
						min_dist = min(min_dist, dist)
	
	if min_dist < max_distance:
		var t = float(min_dist) / max_distance
		return lerp(0.0, 1.0, pow(t, 0.7))
	return 1.0

func is_walkable(tile_pos: Vector2i) -> bool:
	var atlas_coord = tile_map.get_cell_atlas_coords(tile_pos)
	# Check if it's a wall tile (8,12) or if it's not in grassAtlasCoords
	if atlas_coord == Vector2i(8,12) or not grassAtlasCoords.has(atlas_coord):
		return false
	# Check if it's a fence in the terrain data
	if terrain_data.has(tile_pos) and terrain_data[tile_pos] == "fence":
		return false
	return true

func get_tile_neighbors(tile_pos: Vector2i) -> Array:
	var neighbors = [
		tile_pos + Vector2i(1, 0),
		tile_pos + Vector2i(-1, 0),
		tile_pos + Vector2i(0, 1),
		tile_pos + Vector2i(0, -1)
	]
	
	var valid_neighbors = []
	for neighbor in neighbors:
		if tile_map.get_cell_source_id(neighbor) != -1:  # Check if the cell is valid
			valid_neighbors.append(neighbor)
	
	return valid_neighbors

func send_full_map_to_client(peer_id: int):
	if !multiplayer.is_server():
		print("Warning: Non-server tried to send map data")
		return
		
	print("Preparing map data for client ", peer_id)
	var map_tiles = []
	for y in range(map_height):
		for x in range(map_width):
			var pos = Vector2i(x, y)
			var atlas_coords = tile_map.get_cell_atlas_coords(pos)
			if atlas_coords != Vector2i(-1, -1):  # If tile exists
				var terrain_type = terrain_data.get(pos, "")
				map_tiles.append([pos, atlas_coords, terrain_type])
	
	print("Server sending ", map_tiles.size(), " tiles to client ", peer_id)
	if map_tiles.size() > 0:
		print("First tile data: pos=", map_tiles[0][0], " atlas=", map_tiles[0][1])
	sync_full_map.rpc_id(peer_id, map_tiles)
	sync_walkable_tiles.rpc_id(peer_id, walkable_tiles)

@rpc("authority", "call_remote", "reliable")
func sync_full_map(map_tiles: Array):
	if !tile_map:
		push_error("Cannot sync map - TileMap node not found!")
		return
		
	print("Client received map data with ", map_tiles.size(), " tiles")
	clear_map()
	
	# map_tiles is array of [pos, atlas_coords, terrain_type]
	for tile in map_tiles:
		var pos = tile[0]
		var atlas_coords = tile[1]
		var terrain_type = tile[2]
		
		tile_map.set_cell(pos, tileset_source, atlas_coords)
		terrain_data[pos] = terrain_type
	
	print("Client finished processing map data, placed ", map_tiles.size(), " tiles")

func generate_terrain():
	print("Starting terrain generation")
	# Clear walkable tiles at start
	walkable_tiles.clear()
	
	# First pass: Generate basic terrain with more water
	var terrain_types = {}
	for x in range(map_width):
		for y in range(map_height):
			var pos = Vector2i(x, y)
			var noise_value = noise.get_noise_2d(x * 0.1, y * 0.1)
			
			if noise_value < 0.0:  # Increased threshold for more water
				terrain_types[pos] = "water"
			else:
				terrain_types[pos] = "grass"
				walkable_tiles.append(pos)
	
	# Second pass: Generate beaches
	for pos in terrain_types.keys():
		if terrain_types[pos] != "water":
			continue
			
		# Check neighbors for grass in a wider radius
		for dx in [-2, -1, 0, 1, 2]:  # Increased radius
			for dy in [-2, -1, 0, 1, 2]:
				if dx == 0 and dy == 0:
					continue
					
				var check_pos = pos + Vector2i(dx, dy)
				if check_pos.x < 0 or check_pos.x >= map_width or check_pos.y < 0 or check_pos.y >= map_height:
					continue
					
				if terrain_types.get(check_pos, "") == "grass":
					terrain_types[pos] = "sand"
					break
			if terrain_types[pos] == "sand":
				break
	
	# Third pass: Generate cement regions with adjusted parameters
	var cement_regions = []
	var cement_noise = FastNoiseLite.new()
	cement_noise.seed = noise.seed + 1
	cement_noise.frequency = 0.05
	
	var cement_threshold = 0.4  # Lowered threshold for more cement regions
	var min_cement_size = 8  # Increased minimum size
	var max_cement_size = 20  # Increased maximum size
	
	var visited_cement = {}
	
	for x in range(map_width):
		for y in range(map_height):
			var pos = Vector2i(x, y)
			if visited_cement.has(pos):
				continue
				
			var cement_value = cement_noise.get_noise_2d(x * 0.1, y * 0.1)
			if cement_value > cement_threshold and terrain_types[pos] == "grass":
				# Start a new cement region
				var size_x = randi_range(min_cement_size, max_cement_size)
				var size_y = randi_range(min_cement_size, max_cement_size)
				
				# Create region rect
				var region = Rect2i(pos, Vector2i(size_x, size_y))
				
				# Ensure region is within map bounds
				region = region.intersection(Rect2i(0, 0, map_width, map_height))
				
				# Mark all tiles in region as cement
				for rx in range(region.position.x, region.end.x):
					for ry in range(region.position.y, region.end.y):
						var region_pos = Vector2i(rx, ry)
						if terrain_types.get(region_pos, "") == "grass":
							terrain_types[region_pos] = "cement"
							visited_cement[region_pos] = true
							# Remove cement positions from walkable tiles
							if walkable_tiles.has(region_pos):
								walkable_tiles.erase(region_pos)
				
				cement_regions.append(region)
	
	# Apply terrain to tilemap
	for pos in terrain_types:
		match terrain_types[pos]:
			"grass":
				tile_map.set_cell(pos, tileset_source, grassAtlasCoords.pick_random())
			"water":
				tile_map.set_cell(pos, tileset_source, waterCoors.pick_random())
			"sand":
				tile_map.set_cell(pos, tileset_source, sandCoords.pick_random())
			"cement":
				tile_map.set_cell(pos, tileset_source, cementCoords.pick_random())
	
	# Add fences around cement regions
	add_fences_to_cement(terrain_types, cement_regions)
	
	# Add beaches around cement
	add_beaches_around_cement(cement_regions)
	
	# Store terrain data
	terrain_data = terrain_types
	
	# Find islands
	var islands = find_islands()
	
	# If there are multiple islands, connect them
	if islands.size() > 1:
		print("Found ", islands.size(), " islands, connecting them")
		for i in range(islands.size() - 1):
			connect_two_islands(islands[i], islands[i + 1])
	
	# Update walkable tiles after all modifications
	walkable_tiles.clear()
	for x in range(map_width):
		for y in range(map_height):
			var pos = Vector2i(x, y)
			var tile_data = tile_map.get_cell_tile_data(pos)
			if tile_data:
				var coords = tile_map.get_cell_atlas_coords(pos)
				if grassAtlasCoords.has(coords):
					walkable_tiles.append(pos)
	
	# Verify walkable tiles
	print("Final walkable tiles count: ", walkable_tiles.size())
	
	# Update noise data for tinting
	var noise_data = {}
	for x in range(map_width):
		for y in range(map_height):
			var pos = Vector2i(x, y)
			var tile_data = tile_map.get_cell_tile_data(pos)
			if tile_data:
				var coords = tile_map.get_cell_atlas_coords(pos)
				if grassAtlasCoords.has(coords):
					terrain_data[pos] = "grass"
				elif waterCoors.has(coords):
					terrain_data[pos] = "water"
				elif sandCoords.has(coords):
					terrain_data[pos] = "sand"
				elif cementCoords.has(coords):
					terrain_data[pos] = "cement"
				elif wallCoords.has(coords):
					terrain_data[pos] = "fence"
				else:
					terrain_data[pos] = "water"
				noise_data[pos] = noise.get_noise_2d(x * 0.1, y * 0.1)

func add_fences_to_cement(terrain_types: Dictionary, cement_regions: Array) -> void:
	for region in cement_regions:
		var perimeter = []
		
		# Collect perimeter tiles
		for x in range(region.position.x - 1, region.end.x + 1):
			perimeter.append(Vector2i(x, region.position.y - 1))  # Top
			perimeter.append(Vector2i(x, region.end.y))  # Bottom
		for y in range(region.position.y - 1, region.end.y + 1):
			perimeter.append(Vector2i(region.position.x - 1, y))  # Left
			perimeter.append(Vector2i(region.end.x, y))  # Right
		
		# Remove duplicates and invalid positions
		perimeter = perimeter.filter(func(pos): 
			return terrain_types.get(pos, "") != "cement" and \
				   pos.x >= 0 and pos.x < map_width and \
				   pos.y >= 0 and pos.y < map_height
		)
		
		# Add fences with variable-width gaps
		var gap_noise = FastNoiseLite.new()
		gap_noise.seed = noise.seed + 4
		gap_noise.frequency = 0.2
		
		# Determine number of gaps for each side
		var gaps_per_side = randi_range(1, 3)
		var sides = {"top": [], "bottom": [], "left": [], "right": []}
		
		# Sort perimeter tiles into sides
		for pos in perimeter:
			if pos.y == region.position.y - 1:
				sides.top.append(pos)
			elif pos.y == region.end.y:
				sides.bottom.append(pos)
			elif pos.x == region.position.x - 1:
				sides.left.append(pos)
			elif pos.x == region.end.x:
				sides.right.append(pos)
		
		# Add gaps to each side
		for side in sides.values():
			if side.size() > 2:  # Only add gaps if the side is long enough
				var gap_positions = []
				for i in range(gaps_per_side):
					var gap_pos = side[randi() % side.size()]
					gap_positions.append(gap_pos)
				
				# Place fences on this side, skipping gap positions
				for pos in side:
					if not gap_positions.has(pos):
						terrain_types[pos] = "fence"
						tile_map.set_cell(pos, tileset_source, wallCoords[0])

func add_beaches_around_cement(cement_regions: Array, max_beach_width: int = 3) -> void:
	var beach_noise = FastNoiseLite.new()
	beach_noise.seed = noise.seed + 3
	beach_noise.frequency = 0.15
	
	# First, find all cement and fence edge tiles
	for region in cement_regions:
		# Expand the check area to include area around fences
		var check_region = Rect2i(
			region.position.x - max_beach_width - 1,
			region.position.y - max_beach_width - 1,
			region.size.x + (max_beach_width + 1) * 2,
			region.size.y + (max_beach_width + 1) * 2
		)
		
		for y in range(check_region.position.y, check_region.end.y):
			for x in range(check_region.position.x, check_region.end.x):
				var pos = Vector2i(x, y)
				if terrain_data.get(pos, "") == "grass":
					# Check if adjacent to cement or fence
					var adjacent_to_structure = false
					var min_dist = INF
					
					# Check in a larger radius to find nearest cement or fence
					for radius in range(1, max_beach_width + 1):
						for dx in range(-radius, radius + 1):
							for dy in range(-radius, radius + 1):
								if abs(dx) == radius or abs(dy) == radius:
									var check_pos = Vector2i(x + dx, y + dy)
									var check_type = terrain_data.get(check_pos, "")
									if check_type == "cement" or check_type == "fence":
										var dist = sqrt(dx * dx + dy * dy)
										if dist < min_dist:
											min_dist = dist
											adjacent_to_structure = true
					
					if adjacent_to_structure:
						# Use noise to determine beach width
						var width_noise = (beach_noise.get_noise_2d(x * 0.2, y * 0.2) + 1) * 0.5
						var local_beach_width = width_noise * max_beach_width
						
						# Add randomness for gaps
						var gap_noise = beach_noise.get_noise_2d(x * 0.4, y * 0.4)
						if gap_noise > -0.7 and min_dist <= local_beach_width:  # ~15% chance of gaps
							terrain_data[pos] = "sand"
							tile_map.set_cell(pos, tileset_source, sandCoords.pick_random())

func find_islands() -> Array:
	var islands = []
	var visited = {}
	
	for x in range(map_width):
		for y in range(map_height):
			var pos = Vector2i(x, y)
			var tile_data = tile_map.get_cell_tile_data(pos)
			if tile_data:
				var coords = tile_map.get_cell_atlas_coords(pos)
				if grassAtlasCoords.has(coords) and not visited.has(pos):
					# Found a new unvisited grass tile, start a new island
					var island = []
					var to_visit = [pos]
					
					# Flood fill to find all connected grass tiles
					while not to_visit.is_empty():
						var current = to_visit.pop_front()
						
						if visited.has(current):
							continue
							
						visited[current] = true
						island.append(current)
						
						# Check neighbors
						for dx in [-1, 0, 1]:
							for dy in [-1, 0, 1]:
								if dx == 0 and dy == 0:
									continue
									
								var neighbor = current + Vector2i(dx, dy)
								if neighbor.x < 0 or neighbor.x >= map_width or neighbor.y < 0 or neighbor.y >= map_height:
									continue
									
								tile_data = tile_map.get_cell_tile_data(neighbor)
								if tile_data:
									coords = tile_map.get_cell_atlas_coords(neighbor)
									if grassAtlasCoords.has(coords) and not visited.has(neighbor):
										to_visit.append(neighbor)
					
					if not island.is_empty():
						islands.append(island)
	
	return islands

func connect_two_islands(island1: Array, island2: Array) -> void:
	# Find closest points between islands
	var min_distance = INF
	var point1 = null
	var point2 = null
	
	for p1 in island1:
		for p2 in island2:
			var dist = p1.distance_to(p2)
			if dist < min_distance:
				if p1.x >= 0 and p1.x < map_width and p1.y >= 0 and p1.y < map_height and \
				   p2.x >= 0 and p2.x < map_width and p2.y >= 0 and p2.y < map_height:
					min_distance = dist
					point1 = p1
					point2 = p2
	
	if point1 == null or point2 == null:
		return
	
	# Create wider land bridges with multiple paths
	var path_points = []
	var current = point1
	var target = point2
	
	# Generate main path points with diagonal movement
	while current != target:
		path_points.append(current)
		
		var dx = target.x - current.x
		var dy = target.y - current.y
		
		if dx != 0:
			current.x += sign(dx)
		if dy != 0:
			current.y += sign(dy)
	
	path_points.append(target)
	
	# Add new land bridge with increased width
	for path_idx in range(path_points.size()):
		var point = path_points[path_idx]
		# Calculate progress along the path (0 to 1)
		var progress = float(path_idx) / (path_points.size() - 1)
		# Width varies based on position - significantly wider throughout
		var base_radius = lerp(8.0, 6.0, sin(progress * PI))  # Increased width range
		
		# Add noise to the radius
		var radius_noise = noise.get_noise_2d(point.x * 0.1, point.y * 0.1)
		var radius = int(base_radius + radius_noise * 3)  # Increased noise influence
		
		# Create a wider path by setting tiles in a radius around the path point
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var pos = point + Vector2i(dx, dy)
				if pos.x >= 0 and pos.x < map_width and pos.y >= 0 and pos.y < map_height:
					var dist = sqrt(dx * dx + dy * dy)
					if dist <= radius:
						# Add some noise to the edges
						var edge_noise = noise.get_noise_2d(pos.x * 0.2, pos.y * 0.2)
						if dist <= radius - 2 or edge_noise > 0:
							# Check if we're replacing water or sand
							var tile_data = tile_map.get_cell_tile_data(pos)
							if tile_data:
								var coords = tile_map.get_cell_atlas_coords(pos)
								if waterCoors.has(coords) or sandCoords.has(coords):
									# Set grass tile
									tile_map.set_cell(pos, tileset_source, grassAtlasCoords.pick_random())
									terrain_data[pos] = "grass"
									walkable_tiles.append(pos)
