# godot 4.3
extends Node2D

var grassAtlasCoords = [Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(3,0),Vector2i(16,0),Vector2i(17,0)]
var waterCoors = [Vector2i(18,0), Vector2i(19,0)]
var sandCoords = [Vector2i(4,0), Vector2i(5,0)]
var cementCoords = [Vector2i(6,0), Vector2i(7,0), Vector2i(8,0), Vector2i(9,0)]
var wallCoords = [Vector2i(8,12)]
var noise = FastNoiseLite.new()
var tileset_source = 1
# Noise parameters
var tile_size = 64
var map_width = Constants.MAP_SIZE.x
var map_height = Constants.MAP_SIZE.y

var walkable_tiles = []
@onready var tile_map = $TileMap

func _ready():
	# Initialize noise for tinting - use same settings as terrain generation
	noise.seed = Multihelper.mapSeed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.frequency = 0.02
	
	# Only generate map on server or in single player
	if multiplayer.is_server():
		generateMap()

func set_tile(pos: Vector2i, tile_type: String, atlas_coords: Vector2i) -> void:
	# Only server should set tiles initially
	if !multiplayer.is_server():
		return
		
	# Set the base tile
	tile_map.set_cell(pos, tileset_source, atlas_coords)
	
	# Get the exact same noise value used for terrain generation
	var noise_val = noise.get_noise_2d(pos.x, pos.y)
	
	# Calculate tint based on terrain height
	var tint = Color.WHITE
	match tile_type:
		"grass":
			# Use noise value for terrain-based variation
			# Convert from -1,1 to 0,1 range and enhance contrast
			var height_factor = pow((noise_val + 1.0) * 0.5, 0.7)  # Power less than 1 enhances darker areas
			tint = Color(
				lerp(0.5, 1.3, height_factor),  # red - strong variation
				lerp(0.6, 1.4, height_factor),  # green - strongest variation for grass
				lerp(0.5, 1.3, height_factor)   # blue - strong variation
			)
		"water":
			# More visible water depth variation
			var depth_factor = pow((-noise_val + 1.0) * 0.5, 1.3)  # Power greater than 1 enhances deeper areas
			tint = Color(
				lerp(0.9, 0.3, depth_factor),  # red - dramatic darkening in deep water
				lerp(0.9, 0.3, depth_factor),  # green - dramatic darkening in deep water
				lerp(1.1, 0.6, depth_factor)   # blue - maintain water feel with strong depth variation
			)
		"sand":
			# More visible sand height variation
			var height_factor = pow((noise_val + 1.0) * 0.5, 0.8)  # Slightly enhance lower areas
			tint = Color(
				lerp(0.6, 1.2, height_factor),  # red - strong variation
				lerp(0.5, 1.1, height_factor),  # green - moderate variation
				lerp(0.4, 1.0, height_factor)   # blue - less variation
			)
		"cement":
			# More visible cement height variation
			var height_factor = pow((noise_val + 1.0) * 0.5, 0.9)
			var gray = lerp(0.6, 1.3, height_factor)  # Increased contrast
			tint = Color(gray, gray, gray)
	
	# Apply tint to the tile
	var tile_data = tile_map.get_cell_tile_data(pos)
	if tile_data:
		tile_data.modulate = tint
		
	# Synchronize the tile to clients
	sync_tile.rpc(pos, atlas_coords, tint)

@rpc("authority", "call_remote", "reliable")
func sync_tile(pos: Vector2i, atlas_coords: Vector2i, tint: Color):
	# Clients receive the tile data from server
	tile_map.set_cell(pos, tileset_source, atlas_coords)
	var tile_data = tile_map.get_cell_tile_data(pos)
	if tile_data:
		tile_data.modulate = tint

func generateMap():
	# Initialize main terrain noise
	noise.seed = Multihelper.mapSeed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.frequency = 0.02
	
	generate_terrain()

func generate_terrain():
	walkable_tiles.clear()
	var border_width = 8
	var border_falloff = 4
	
	var terrain_data = {}
	var noise_data = {}
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
				terrain_data[pos] = "grass"
				walkable_tiles.append(pos)
				set_tile(pos, "grass", grassAtlasCoords.pick_random())
			else:
				terrain_data[pos] = "water"
				set_tile(pos, "water", waterCoors.pick_random())
	
	generate_beaches(terrain_data, noise_data)
	connect_islands()
	generate_cement_areas(terrain_data)

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
				valid_pos.x - width/2,
				valid_pos.y - height/2
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
