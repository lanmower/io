# godot 4.3
extends Node2D

var grassAtlasCoords = [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0)]
var waterCoors = [Vector2i(4,0), Vector2i(5,0)]
var sandCoords = [Vector2i(6,0), Vector2i(7,0)]
var cementCoords = [Vector2i(8,0), Vector2i(9,0)]
var wallCoords = [Vector2i(8,0)]
var noise = FastNoiseLite.new()
var tileset_source = 1
# Noise parameters
var tile_size = 64
var map_width = Constants.MAP_SIZE.x
var map_height = Constants.MAP_SIZE.y

var walkable_tiles = []
var terrain_data = {}  # Store terrain types for each tile
@onready var tile_map = $TileMap

signal map_reset

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
		
	# Validate that our basic tiles exist
	var missing_tiles = []
	for coords in grassAtlasCoords:
		if !source.has_tile(coords) or !source.get_tile_data(coords, 0):
			missing_tiles.append("grass:" + str(coords))
	for coords in waterCoors:
		if !source.has_tile(coords) or !source.get_tile_data(coords, 0):
			missing_tiles.append("water:" + str(coords))
	for coords in sandCoords:
		if !source.has_tile(coords) or !source.get_tile_data(coords, 0):
			missing_tiles.append("sand:" + str(coords))
	for coords in cementCoords:
		if !source.has_tile(coords) or !source.get_tile_data(coords, 0):
			missing_tiles.append("cement:" + str(coords))
	for coords in wallCoords:
		if !source.has_tile(coords) or !source.get_tile_data(coords, 0):
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

# Called by Multihelper when client is ready to receive map
func initialize_client():
	print("Client initializing map")
	clear_map()
	print("Client requesting map data from server")
	request_map_data.rpc_id(1)

func set_tile(pos: Vector2i, tile_type: String, atlas_coords: Vector2i) -> void:
	if !tile_map:
		push_error("Cannot set tile - TileMap node not found!")
		return
		
	# Validate position is within map bounds
	if pos.x < 0 or pos.x >= map_width or pos.y < 0 or pos.y >= map_height:
		push_error("Tile position out of bounds: " + str(pos))
		return
		
	# Get the tileset source
	var source = tile_map.tile_set.get_source(tileset_source) if tile_map.tile_set else null
	if !source:
		push_error("Invalid tileset source")
		return
		
	# Try to set the tile with the original coordinates
	var success = false
	
	# Debug print for tile setting attempt
	print("Attempting to set tile at pos: ", pos, " type: ", tile_type, " coords: ", atlas_coords)
	
	# Validate the tile exists in the source
	if source.has_tile(atlas_coords):
		# Get the tile data to ensure it's valid
		var tile_data = source.get_tile_data(atlas_coords, 0)
		if tile_data:
			# Use erase_cell first to clear any existing tile
			tile_map.erase_cell(pos)
			# Then set the new tile with explicit alternative
			tile_map.set_cell(pos, tileset_source, atlas_coords, 0, 0)
			success = true
			print("Successfully set tile at pos: ", pos)
		else:
			push_error("Invalid tile data for coords: " + str(atlas_coords))
	else:
		print("Tile not found in source for coords: ", atlas_coords)
	
	if !success:
		# If the original coordinates failed, try alternative coordinates
		var alternative_coords = null
		match tile_type:
			"grass": 
				alternative_coords = grassAtlasCoords[0]
				print("Using grass alternative: ", alternative_coords)
			"water": 
				alternative_coords = waterCoors[0]
				print("Using water alternative: ", alternative_coords)
			"sand": 
				alternative_coords = sandCoords[0]
				print("Using sand alternative: ", alternative_coords)
			"cement": 
				alternative_coords = cementCoords[0]
				print("Using cement alternative: ", alternative_coords)
			"fence": 
				alternative_coords = wallCoords[0]
				print("Using fence alternative: ", alternative_coords)
		
		if alternative_coords and source.has_tile(alternative_coords):
			var tile_data = source.get_tile_data(alternative_coords, 0)
			if tile_data:
				print("Using alternative coordinates for ", tile_type, ": ", alternative_coords)
				# Use erase_cell first to clear any existing tile
				tile_map.erase_cell(pos)
				# Then set the new tile with explicit alternative
				tile_map.set_cell(pos, tileset_source, alternative_coords, 0, 0)
				success = true
				print("Successfully set alternative tile at pos: ", pos)
			else:
				push_error("Invalid tile data for alternative coords: " + str(alternative_coords))
		else:
			push_error("Alternative coordinates not found in source: " + str(alternative_coords))
	
	if success:
		# Store the terrain type
		terrain_data[pos] = tile_type
		
		# If we're the server, synchronize to clients
		if multiplayer.is_server():
			sync_tile.rpc(pos, atlas_coords)
	else:
		push_error("Failed to set tile at pos: " + str(pos) + " type: " + tile_type)

@rpc("authority", "call_remote", "reliable")
func sync_tile(pos: Vector2i, atlas_coords: Vector2i):
	if !tile_map:
		push_error("Cannot sync tile - TileMap node not found!")
		return
		
	# Validate position is within map bounds
	if pos.x < 0 or pos.x >= map_width or pos.y < 0 or pos.y >= map_height:
		push_error("Sync tile position out of bounds: " + str(pos))
		return
		
	# Get the tileset source
	var source = tile_map.tile_set.get_source(tileset_source) if tile_map.tile_set else null
	if !source:
		push_error("Invalid tileset source in sync_tile")
		return
		
	# Try to set the tile with the original coordinates
	var success = false
	var terrain_type = ""
	
	print("Attempting to sync tile at pos: ", pos, " coords: ", atlas_coords)
	
	# First try to determine terrain type from the original coordinates
	if grassAtlasCoords.has(atlas_coords):
		terrain_type = "grass"
		print("Detected grass tile in sync")
	elif waterCoors.has(atlas_coords):
		terrain_type = "water"
		print("Detected water tile in sync")
	elif sandCoords.has(atlas_coords):
		terrain_type = "sand"
		print("Detected sand tile in sync")
	elif cementCoords.has(atlas_coords):
		terrain_type = "cement"
		print("Detected cement tile in sync")
	elif wallCoords.has(atlas_coords):
		terrain_type = "fence"
		print("Detected fence tile in sync")
	
	# Try to set the tile
	if source.has_tile(atlas_coords):
		var tile_data = source.get_tile_data(atlas_coords, 0)
		if tile_data:
			# Use erase_cell first to clear any existing tile
			tile_map.erase_cell(pos)
			# Then set the new tile with explicit alternative
			tile_map.set_cell(pos, tileset_source, atlas_coords, 0, 0)
			success = true
			print("Successfully synced tile at pos: ", pos)
		else:
			push_error("Invalid tile data for sync coords: " + str(atlas_coords))
	else:
		print("Tile not found in source for sync coords: ", atlas_coords)
	
	if !success:
		# If original coordinates failed, determine terrain type from coordinate ranges
		if terrain_type.is_empty():
			if atlas_coords.x <= 3:
				terrain_type = "grass"
				print("Fallback to grass based on coords")
			elif atlas_coords.x <= 5:
				terrain_type = "water"
				print("Fallback to water based on coords")
			elif atlas_coords.x <= 7:
				terrain_type = "sand"
				print("Fallback to sand based on coords")
			elif atlas_coords.x <= 9:
				terrain_type = "cement"
				print("Fallback to cement based on coords")
			else:
				terrain_type = "grass"  # Default fallback
				print("Using default grass fallback")
		
		# Get alternative coordinates based on terrain type
		var alternative_coords = null
		match terrain_type:
			"grass": 
				alternative_coords = grassAtlasCoords[0]
				print("Using grass alternative in sync: ", alternative_coords)
			"water": 
				alternative_coords = waterCoors[0]
				print("Using water alternative in sync: ", alternative_coords)
			"sand": 
				alternative_coords = sandCoords[0]
				print("Using sand alternative in sync: ", alternative_coords)
			"cement": 
				alternative_coords = cementCoords[0]
				print("Using cement alternative in sync: ", alternative_coords)
			"fence": 
				alternative_coords = wallCoords[0]
				print("Using fence alternative in sync: ", alternative_coords)
		
		if alternative_coords and source.has_tile(alternative_coords):
			var tile_data = source.get_tile_data(alternative_coords, 0)
			if tile_data:
				print("Using alternative coordinates in sync for ", terrain_type, ": ", alternative_coords)
				# Use erase_cell first to clear any existing tile
				tile_map.erase_cell(pos)
				# Then set the new tile with explicit alternative
				tile_map.set_cell(pos, tileset_source, alternative_coords, 0, 0)
				success = true
				print("Successfully synced alternative tile at pos: ", pos)
			else:
				push_error("Invalid tile data for alternative sync coords: " + str(alternative_coords))
		else:
			push_error("Alternative coordinates not found in source for sync: " + str(alternative_coords))
	
	if success:
		terrain_data[pos] = terrain_type
	else:
		push_error("Failed to sync tile at pos: " + str(pos) + " type: " + terrain_type)

# Remove loadMap as it's no longer needed - clients only receive tiles from server
func clear_map():
	if !tile_map:
		push_error("Cannot clear map - TileMap node not found!")
		return
		
	terrain_data.clear()
	walkable_tiles.clear()
	for x in range(map_width):
		for y in range(map_height):
			tile_map.erase_cell(Vector2i(x, y))  # Use erase_cell instead of set_cell(-1)

func get_height_at(pos: Vector2i) -> float:
	if pos.x < 0 or pos.x >= map_width or pos.y < 0 or pos.y >= map_height:
		return 0.0
		
	var cell = tile_map.get_cell_atlas_coords(pos)
	if waterCoors.has(cell):
		return 0.0
		
	# Find nearest water
	var max_distance = 6
	var min_dist = max_distance
	
	for dx in range(-max_distance, max_distance + 1):
		for dy in range(-max_distance, max_distance + 1):
			var check_pos = pos + Vector2i(dx, dy)
			if check_pos.x >= 0 and check_pos.x < map_width and check_pos.y >= 0 and check_pos.y < map_height:
				var check_cell = tile_map.get_cell_atlas_coords(check_pos)
				if waterCoors.has(check_cell):
					var dist = Vector2(dx, dy).length()
					min_dist = min(min_dist, dist)
	
	if min_dist < max_distance:
		var t = float(min_dist) / max_distance
		return lerp(0.0, 1.0, pow(t, 0.7))
	return 1.0

@rpc("authority", "call_remote", "reliable")
func sync_walkable_tiles(tiles: Array):
	walkable_tiles = tiles

@rpc("authority", "call_remote", "reliable")
func sync_terrain_data(data: Dictionary):
	terrain_data = data

func generateMap():
	# Clear terrain data at start
	terrain_data.clear()
	
	# Use the noise settings already initialized in _ready()
	generate_terrain()
	
	# Clear any invalid tiles from walkable_tiles
	walkable_tiles = walkable_tiles.filter(func(pos): 
		var tileCoords = tile_map.get_cell_atlas_coords(pos)
		return not waterCoors.has(tileCoords)
	)
	
	# If we're the server, sync walkable tiles and terrain data to clients
	if multiplayer.is_server():
		sync_walkable_tiles.rpc(walkable_tiles)
		sync_terrain_data.rpc(terrain_data)

func generate_terrain():
	print("Starting terrain generation")
	# Clear walkable tiles at start
	walkable_tiles.clear()
	
	var border_width = 8
	var border_falloff = 4
	
	var terrain_types = {}  # Renamed from terrain_data to avoid confusion
	var noise_data = {}
	
	print("Generating base terrain with noise seed: ", noise.seed)
	# First pass: Generate base terrain
	for y in range(map_height):
		for x in range(map_width):
			var noise_value = noise.get_noise_2d(x, y)
			var pos = Vector2i(x, y)
			noise_data[pos] = noise_value
			
			var dist_from_edge = min(
				min(x, map_width - x),
				min(y, map_height - y)
			)
			
			var threshold = -0.1
			if dist_from_edge < border_width:
				threshold = 1.0
			elif dist_from_edge < border_width + border_falloff:
				var t = float(dist_from_edge - border_width) / border_falloff
				threshold = lerp(1.0, -0.1, t)
			
			if noise_value > threshold:
				terrain_types[pos] = "grass"
				set_tile(pos, "grass", grassAtlasCoords.pick_random())
			else:
				terrain_types[pos] = "water"
				set_tile(pos, "water", waterCoors.pick_random())
	
	# Second pass: Validate and add walkable tiles
	for y in range(map_height):
		for x in range(map_width):
			var pos = Vector2i(x, y)
			var tileCoords = tile_map.get_cell_atlas_coords(pos)
			# Only add if it's grass (not water, sand, or cement)
			if grassAtlasCoords.has(tileCoords):
				walkable_tiles.append(pos)
	
	generate_beaches(terrain_types, noise_data)
	connect_islands()
	generate_cement_areas(terrain_types)
	
	# Final validation of walkable tiles
	var validated_tiles = []
	for pos in walkable_tiles:
		var tileCoords = tile_map.get_cell_atlas_coords(pos)
		# Strict check: only allow grass tiles
		if grassAtlasCoords.has(tileCoords):
			validated_tiles.append(pos)
	walkable_tiles = validated_tiles
	
	# Ensure we have at least some walkable grass tiles
	if walkable_tiles.is_empty():
		push_error("No walkable tiles found after map generation!")
		# Force create some grass tiles in the center
		var center = Vector2i(map_width/2, map_height/2)
		for dx in range(-5, 6):
			for dy in range(-5, 6):
				var pos = center + Vector2i(dx, dy)
				if pos.x >= 0 and pos.x < map_width and pos.y >= 0 and pos.y < map_height:
					set_tile(pos, "grass", grassAtlasCoords.pick_random())
					walkable_tiles.append(pos)
	
	# Sync walkable tiles to clients
	if multiplayer.is_server():
		sync_walkable_tiles.rpc(walkable_tiles)

func generate_beaches(terrain_data: Dictionary, noise_data: Dictionary) -> void:
	var max_beach_width = 3
	var beach_noise = FastNoiseLite.new()
	beach_noise.seed = noise.seed + 1
	beach_noise.frequency = 0.1
	
	for y in range(map_height):
		for x in range(map_width):
			var pos = Vector2i(x, y)
			if terrain_data[pos] == "grass":
				var has_water = false
				var closest_water_dist = INF
				
				for radius in range(1, max_beach_width + 1):
					for dx in range(-radius, radius + 1):
						for dy in range(-radius, radius + 1):
							if abs(dx) == radius or abs(dy) == radius:
								var check_pos = Vector2i(x + dx, y + dy)
								if check_pos.x >= 0 and check_pos.x < map_width and \
								   check_pos.y >= 0 and check_pos.y < map_height:
									if terrain_data.get(check_pos, "") == "water":
										var dist = Vector2(dx, dy).length()
										if dist < closest_water_dist:
											closest_water_dist = dist
											has_water = true
				
				if has_water and closest_water_dist <= max_beach_width:
					var width_noise = (beach_noise.get_noise_2d(x * 0.1, y * 0.1) + 1) * 0.5
					var local_beach_width = width_noise * max_beach_width
					
					var gap_noise = beach_noise.get_noise_2d(x * 0.3, y * 0.3)
					if gap_noise > -0.7 and closest_water_dist <= local_beach_width:
						terrain_data[pos] = "sand"
						set_tile(pos, "sand", sandCoords.pick_random())
						if not walkable_tiles.has(pos):
							walkable_tiles.append(pos)

func connect_islands():
	var islands = find_islands()
	if islands.size() <= 1:
		return  # No need to connect if there's only one or no islands
	
	# Sort islands by size (largest first) to use biggest island as main
	islands.sort_custom(func(a, b): return a.size() > b.size())
	
	# Connect all islands to the first one
	var main_island = islands[0]
	for i in range(1, islands.size()):
		connect_two_islands(main_island, islands[i])

func find_islands() -> Array:
	var islands = []
	var visited = {}
	
	for tile in walkable_tiles:
		if visited.has(tile):
			continue
		
		var current_island = []
		var to_visit = [tile]
		
		while to_visit.size() > 0:
			var current = to_visit.pop_front()
			if visited.has(current):
				continue
			
			visited[current] = true
			current_island.append(current)
			
			# Check neighbors
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var neighbor = Vector2i(current.x + dx, current.y + dy)
					if walkable_tiles.has(neighbor) and not visited.has(neighbor):
						to_visit.append(neighbor)
		
		islands.append(current_island)
	
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
		var dx = sign(target.x - current.x)
		var dy = sign(target.y - current.y)
		
		# Allow diagonal movement for more natural paths
		if dx != 0 and dy != 0:
			# Randomly choose whether to move diagonally or in a single direction
			if randf() > 0.5:
				current = Vector2i(current.x + dx, current.y + dy)
			else:
				# Move in either x or y direction randomly
				if randf() > 0.5:
					current = Vector2i(current.x + dx, current.y)
				else:
					current = Vector2i(current.x, current.y + dy)
		else:
			if dx != 0:
				current = Vector2i(current.x + dx, current.y)
			elif dy != 0:
				current = Vector2i(current.x, current.y + dy)
	path_points.append(target)
	
	# Create natural-looking land with noise-based width variation
	var terrain_data = {}
	var noise_data = {}
	
	# First, collect existing terrain data
	for y in range(map_height):
		for x in range(map_width):
			var pos = Vector2i(x, y)
			var cell_data = tile_map.get_cell_atlas_coords(pos)
			terrain_data[pos] = "water"
			noise_data[pos] = noise.get_noise_2d(x * 0.1, y * 0.1)
			
			if grassAtlasCoords.has(cell_data):
				terrain_data[pos] = "grass"
			elif sandCoords.has(cell_data):
				terrain_data[pos] = "sand"
	
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
		
		# Create a wider elliptical shape around the path point
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var check_point = Vector2i(point.x + dx, point.y + dy)
				# Use elliptical distance check for more natural shape
				var dist = sqrt(pow(dx / base_radius, 2) + pow(dy / (base_radius * 0.8), 2))
				if dist <= 1.0 and is_valid_tile_position(check_point):
					# Add some randomness to the edges
					if dist > 0.8 and randf() > 0.7:  # 30% chance to skip edge tiles for natural look
						continue
					terrain_data[check_point] = "grass"
					if not walkable_tiles.has(check_point):
						walkable_tiles.append(check_point)
					tile_map.set_cell(check_point, tileset_source, grassAtlasCoords.pick_random())
	
	# Generate beaches for the new land with wider beach areas
	generate_beaches(terrain_data, noise_data)

func is_valid_tile_position(pos: Vector2i) -> bool:
	var border_width = 8  # Same as in generate_terrain
	return pos.x >= border_width and pos.x < map_width - border_width and \
		   pos.y >= border_width and pos.y < map_height - border_width

func generate_cement_areas(terrain_data: Dictionary) -> void:
	var num_cement_areas = randi_range(3, 9)  # Generate 3-9 cement areas
	var cement_regions = []  # Store cement regions for overlap checking
	
	# Create a separate noise for cement placement
	var cement_noise = FastNoiseLite.new()
	cement_noise.seed = noise.seed + 2
	cement_noise.frequency = 0.1
	
	# First, find all valid grass positions away from water
	var valid_positions = []
	for y in range(10, map_height - 10):
		for x in range(10, map_width - 10):
			var pos = Vector2i(x, y)
			var valid = true
			
			# Check surrounding area for water
			for check_y in range(pos.y - 2, pos.y + 2):
				for check_x in range(pos.x - 2, pos.x + 2):
					var check_pos = Vector2i(check_x, check_y)
					if terrain_data.get(check_pos, "") == "water":
						valid = false
						break
				if not valid:
					break
			
			if valid:
				valid_positions.append(pos)
	
	# Generate cement areas with occasional overlaps
	for _i in range(num_cement_areas):
		var width = randi_range(4, 12)
		var height = randi_range(4, 12)
		
		# 30% chance to try to overlap with existing building
		var pos: Vector2i
		if cement_regions.size() > 0 and randf() < 0.3:
			# Pick a random existing region
			var existing_region = cement_regions.pick_random()
			# Generate position near the existing region with some randomness
			var offset_x = randi_range(-width, existing_region.size.x)
			var offset_y = randi_range(-height, existing_region.size.y)
			pos = Vector2i(
				existing_region.position.x + offset_x,
				existing_region.position.y + offset_y
			)
		else:
			# Place in a new area
			var valid_pos = valid_positions.pick_random()
			pos = Vector2i(
				valid_pos.x - float(width)/2,
				valid_pos.y - float(height)/2
			)
		
		# Ensure position is within valid range
		pos.x = clamp(pos.x, 10, map_width - width - 10)
		pos.y = clamp(pos.y, 10, map_height - height - 10)
		
		var region = Rect2i(pos.x, pos.y, width, height)
		
		# Merge with any overlapping regions
		var merged_region = region
		var regions_to_remove = []
		for existing_region in cement_regions:
			if merged_region.intersects(existing_region):
				merged_region = merged_region.merge(existing_region)
				regions_to_remove.append(existing_region)
		
		# Remove merged regions and add new merged region
		for r in regions_to_remove:
			cement_regions.erase(r)
		cement_regions.append(merged_region)
		place_cement_area(merged_region, terrain_data)
	
	# First add fences around cement areas
	add_fences_to_cement(terrain_data, cement_regions)
	
	# Then add beaches around cement and fences
	generate_cement_beaches(terrain_data, cement_regions)

func place_cement_area(region: Rect2i, terrain_data: Dictionary) -> void:
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var pos = Vector2i(x, y)
			terrain_data[pos] = "cement"
			set_tile(pos, "cement", cementCoords.pick_random())

func generate_cement_beaches(terrain_data: Dictionary, cement_regions: Array) -> void:
	var max_beach_width = 3  # Increased maximum beach width around cement
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
										var dist = Vector2(dx, dy).length()
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

func add_fences_to_cement(terrain_data: Dictionary, cement_regions: Array) -> void:
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
			return terrain_data.get(pos, "") != "cement" and \
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
		
		# Add variable-width gaps to each side
		for side in sides.values():
			if side.size() > 4:  # Only add gaps if side is long enough
				for _i in range(gaps_per_side):
					# Determine gap width (1-4 blocks)
					var gap_width = randi_range(1, 4)
					
					# Make sure we don't exceed the side length
					gap_width = mini(gap_width, side.size() - 2)  # Leave at least 2 fence blocks
					
					if side.size() >= gap_width:
						# Find a valid starting position for the gap
						var valid_start_indices = range(0, side.size() - gap_width)
						if valid_start_indices.size() > 0:
							var start_idx = valid_start_indices.pick_random()
							# Remove all positions in the gap width
							for w in range(gap_width):
								if start_idx < side.size():
									side.remove_at(start_idx)
		
		# Place fences on remaining positions
		for side in sides.values():
			for pos in side:
				if terrain_data.get(pos, "") != "cement":
					terrain_data[pos] = "fence"  # Mark the position as fence in terrain data
					tile_map.set_cell(pos, tileset_source, wallCoords[0])
					# Remove fence positions from walkable tiles
					if walkable_tiles.has(pos):
						walkable_tiles.erase(pos)

func reset_map():
	# Clear all existing objects
	for child in get_children():
		if child != tile_map:  # Keep the tile map but clear everything else
			child.queue_free()
	
	# Reset the map generation
	generateMap()
	
	# Emit signal that map has been reset
	map_reset.emit()

# Add this function to be called when a player spawns
func handle_player_spawn(is_first_player: bool):
	if is_first_player:
		# Reset to day 1 and clear the map
		reset_map()
		
		# If we're the server, notify clients
		if multiplayer.is_server():
			reset_map_rpc.rpc()

@rpc("authority", "call_remote", "reliable")
func reset_map_rpc():
	reset_map()

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

@rpc("any_peer", "call_remote", "reliable")
func request_map_data():
	print("Received map data request from peer: ", multiplayer.get_remote_sender_id())
	if multiplayer.is_server():
		var peer_id = multiplayer.get_remote_sender_id()
		print("Server sending map data to peer ", peer_id)
		send_full_map_to_client(peer_id)
	else:
		print("Warning: Non-server received map data request")
