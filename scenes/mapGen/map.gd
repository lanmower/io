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
	for y in range(map_height):
		for x in range(map_width):
			var noise_value = noise.get_noise_2d(x, y)
			var tile_coord = Vector2i()
			var pos = Vector2i(x, y)
			if noise_value > 0.03:
				tile_coord = grassAtlasCoords.pick_random()
				tile_map.set_cell(0, pos, tileset_source, tile_coord)
				walkable_tiles.append(pos)
			else:
				tile_coord = waterCoors.pick_random()
				tile_map.set_cell(0, pos, tileset_source, tile_coord)
	
	connect_islands()

func connect_islands():
	var islands = find_islands()
	if islands.size() <= 1:
		return
	
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
				min_distance = dist
				point1 = p1
				point2 = p2
	
	# Create a path between the closest points
	var current = point1
	while current != point2:
		var dx = sign(point2.x - current.x)
		var dy = sign(point2.y - current.y)
		
		if dx != 0:
			current = Vector2i(current.x + dx, current.y)
		elif dy != 0:
			current = Vector2i(current.x, current.y + dy)
		
		if not walkable_tiles.has(current):
			tile_map.set_cell(0, current, tileset_source, grassAtlasCoords[0])
			walkable_tiles.append(current)
