# godot 4.3
extends Node2D

var grassAtlasCoords = [Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(3,0),Vector2i(16,0),Vector2i(17,0)]
var waterCoors = [Vector2i(18,0), Vector2i(19,0)]
var sandCoords = [Vector2i(4,0), Vector2i(5,0)]
var noise = FastNoiseLite.new()
var tileset_source = 1
# Noise parameters
var tile_size = 64
var map_width = Constants.MAP_SIZE.x
var map_height = Constants.MAP_SIZE.y

var walkable_tiles = []
@onready var tile_map = $TileMap

func generateMap():
	noise.seed = Multihelper.mapSeed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_octaves = 1.1
	noise.fractal_lacunarity = 2.0
	noise.frequency = 0.03
	generate_terrain()

func generate_terrain():
	walkable_tiles.clear()
	var border_width = 8  # Width of ocean border
	var border_falloff = 4  # How gradually the border blends
	
	# First pass: Generate basic terrain (grass and water)
	var terrain_data = {}
	var noise_data = {}  # Store raw noise values for better transitions
	for y in range(map_height):
		for x in range(map_width):
			var noise_value = noise.get_noise_2d(x, y)
			var pos = Vector2i(x, y)
			noise_data[pos] = noise_value
			
			# Calculate distance from edges
			var dist_from_edge = min(
				min(x, map_width - x),
				min(y, map_height - y)
			)
			
			# Adjust noise threshold based on distance from edge
			var threshold = 0.03  # Base threshold
			if dist_from_edge < border_width:
				threshold = 1.0  # Guarantee ocean
			elif dist_from_edge < border_width + border_falloff:
				var t = float(dist_from_edge - border_width) / border_falloff
				threshold = lerp(1.0, 0.03, t)  # Gradual transition
			
			if noise_value > threshold:
				terrain_data[pos] = "grass"
				walkable_tiles.append(pos)
				tile_map.set_cell(pos, tileset_source, grassAtlasCoords.pick_random(), Vector2i(0, 0))  # Set grass
			else:
				terrain_data[pos] = "water"
				tile_map.set_cell(pos, tileset_source, waterCoors.pick_random(), Vector2i(0, 0))  # Set water
	
	# Generate beaches and set tiles
	generate_beaches(terrain_data, noise_data)
	
	# Connect islands
	connect_islands()

func generate_beaches(terrain_data: Dictionary, noise_data: Dictionary) -> void:
	# Add sand borders with multiple layers
	var beach_width = 4  # Increased beach width further
	var sand_positions = []  # Track sand positions to add to walkable_tiles at the end
	
	for layer in range(beach_width):
		for y in range(map_height):
			for x in range(map_width):
				var pos = Vector2i(x, y)
				if terrain_data[pos] == "grass":
					# Check for water or sand in expanding radius
					var has_water_or_outer_sand = false
					for radius in range(1, layer + 2):
						for dx in range(-radius, radius + 1):
							for dy in range(-radius, radius + 1):
								if abs(dx) == radius or abs(dy) == radius:  # Check only the outer ring
									var check_pos = Vector2i(x + dx, y + dy)
									if check_pos.x >= 0 and check_pos.x < map_width and \
									   check_pos.y >= 0 and check_pos.y < map_height:
										var check_type = terrain_data.get(check_pos, "")
										if check_type == "water" or (layer > 0 and check_type == "sand"):
											# Use noise value to create more natural transitions
											var noise_diff = abs(noise_data[pos] - noise_data.get(check_pos, 0))
											if noise_diff < 0.15 + (0.08 * layer):  # Increased thresholds for wider beaches
												has_water_or_outer_sand = true
												break
							if has_water_or_outer_sand:
								break
						if has_water_or_outer_sand:
							break
					
					if has_water_or_outer_sand:
						terrain_data[pos] = "sand"
						sand_positions.append(pos)
						tile_map.set_cell(pos, tileset_source, sandCoords.pick_random(), Vector2i(0, 0))  # Set sand
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
	
	# Create natural-looking land bridges with varying width
	var path_points = []
	var current = point1
	var target = point2
	
	# Generate main path points
	while current != target:
		path_points.append(current)
		var dx = sign(target.x - current.x)
		var dy = sign(target.y - current.y)
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
			var cell_data = tile_map.get_cell_atlas_coords(0, pos)  # Layer 0
			terrain_data[pos] = "water"
			noise_data[pos] = noise.get_noise_2d(x * 0.1, y * 0.1)
			
			# Check if it's grass based on the actual tile
			if grassAtlasCoords.has(cell_data):
				terrain_data[pos] = "grass"
			elif sandCoords.has(cell_data):
				terrain_data[pos] = "sand"
	
	# Add new land bridge
	for path_idx in range(path_points.size()):
		var point = path_points[path_idx]
		# Calculate progress along the path (0 to 1)
		var progress = float(path_idx) / (path_points.size() - 1)
		# Width varies based on position - wider at ends, narrower in middle
		var base_radius = lerp(6.0, 4.0, sin(progress * PI))  # Increased width range
		
		# Add noise to the radius
		var radius_noise = noise.get_noise_2d(point.x * 0.1, point.y * 0.1)
		var radius = int(base_radius + radius_noise * 2)
		
		# Create an elliptical shape around the path point
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var check_point = Vector2i(point.x + dx, point.y + dy)
				# Use elliptical distance check for more natural shape
				var dist = sqrt(pow(dx / base_radius, 2) + pow(dy / (base_radius * 0.7), 2))
				if dist <= 1.0 and is_valid_tile_position(check_point):
					terrain_data[check_point] = "grass"
					if not walkable_tiles.has(check_point):
						walkable_tiles.append(check_point)
					tile_map.set_cell(check_point, tileset_source, grassAtlasCoords.pick_random(), Vector2i(0, 0))  # Set grass
	
	# Generate beaches for the new land
	generate_beaches(terrain_data, noise_data)

func is_valid_tile_position(pos: Vector2i) -> bool:
	var border_width = 8  # Same as in generate_terrain
	return pos.x >= border_width and pos.x < map_width - border_width and \
		   pos.y >= border_width and pos.y < map_height - border_width
