extends Node2D

var grassAtlasCoords = [Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(3,0),Vector2i(16,0),Vector2i(17,0)]
var waterCoors = [Vector2i(18,0), Vector2i(19,0)]
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
	
	for y in range(map_height):
		for x in range(map_width):
			var noise_value = noise.get_noise_2d(x, y)
			var tile_coord = Vector2i()
			var pos = Vector2i(x, y)
			
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
				tile_coord = grassAtlasCoords.pick_random()
				tile_map.set_cell(pos, tileset_source, tile_coord)
				walkable_tiles.append(pos)
			else:
				tile_coord = waterCoors.pick_random()
				tile_map.set_cell(pos, tileset_source, tile_coord)
	
	connect_islands()

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
				# Verify points are within map bounds with ocean border
				if p1.x >= 0 and p1.x < map_width and p1.y >= 0 and p1.y < map_height and \
				   p2.x >= 0 and p2.x < map_width and p2.y >= 0 and p2.y < map_height:
					min_distance = dist
					point1 = p1
					point2 = p2
	
	# If no valid points found, return
	if point1 == null or point2 == null:
		return
	
	# Create expanded mouths at both ends
	var mouth_radius = 4  # Increased mouth radius for wider openings
	for dx in range(-mouth_radius, mouth_radius + 1):
		for dy in range(-mouth_radius, mouth_radius + 1):
			# Use elliptical shape for mouths (wider than tall)
			if (dx * dx) / 16.0 + (dy * dy) / 9.0 <= 1.0:  # Elliptical mouth
				var mouth1 = Vector2i(point1.x + dx, point1.y + dy)
				var mouth2 = Vector2i(point2.x + dx, point2.y + dy)
				
				# Check if mouth points are within map bounds
				if is_valid_tile_position(mouth1):
					if not walkable_tiles.has(mouth1):
						tile_map.set_cell(mouth1, tileset_source, grassAtlasCoords.pick_random())
						walkable_tiles.append(mouth1)
				if is_valid_tile_position(mouth2):
					if not walkable_tiles.has(mouth2):
						tile_map.set_cell(mouth2, tileset_source, grassAtlasCoords.pick_random())
						walkable_tiles.append(mouth2)
	
	# Create a path between the closest points with some variation
	var current = point1
	var path_length = int(point1.distance_to(point2))
	var current_step = 0
	
	while current != point2:
		var dx = sign(point2.x - current.x)
		var dy = sign(point2.y - current.y)
		
		# Calculate how far along the path we are (0.0 to 1.0)
		var progress = float(current_step) / path_length
		
		# Path width varies based on distance from endpoints
		# Wider at ends, narrower in middle
		var path_width = int(lerp(2.0, 0.5, smoothstep(0.0, 0.3, min(progress, 1.0 - progress))))
		
		# Add varied width to the path
		for width_x in range(-path_width, path_width + 1):
			for width_y in range(-path_width, path_width + 1):
				if width_x * width_x + width_y * width_y <= path_width * path_width:
					var path_point = Vector2i(current.x + width_x, current.y + width_y)
					if is_valid_tile_position(path_point) and not walkable_tiles.has(path_point):
						tile_map.set_cell(path_point, tileset_source, grassAtlasCoords.pick_random())
						walkable_tiles.append(path_point)
		
		if dx != 0:
			current = Vector2i(current.x + dx, current.y)
		elif dy != 0:
			current = Vector2i(current.x, current.y + dy)
		
		current_step += 1

func is_valid_tile_position(pos: Vector2i) -> bool:
	var border_width = 8  # Same as in generate_terrain
	return pos.x >= border_width and pos.x < map_width - border_width and \
		   pos.y >= border_width and pos.y < map_height - border_width
