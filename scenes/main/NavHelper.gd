# godot 4.3
extends Node2D

var tilemap: Node

func _ready():
	# Try to get TileMap first
	tilemap = get_node_or_null("../Map/TileMap")
	
	# If TileMap not found, try TileMapLayer
	if !tilemap:
		tilemap = get_node_or_null("../Map/TileMapLayer")
	
	# Check if we found either node
	if !tilemap:
		push_error("Neither TileMap nor TileMapLayer node found! Check paths: ../Map/TileMap or ../Map/TileMapLayer")
		return
	
	# Make sure we have the right node type
	if !tilemap is TileMap and !tilemap is TileMapLayer:
		push_error("Found node at path but it's not a TileMap or TileMapLayer!")
		return

const WALKABLE_TILES = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]  # List of walkable atlas coordinates
const MIN_DISTANCE = 8  # Minimum distance in tiles
const MAX_DISTANCE = 9  # Maximum distance in tiles

func getNavigableTiles(playerId, minR, maxR):
	if !tilemap:
		return
	var player = $"../Players".get_node_or_null(str(playerId))
	if !player:
		return
	var player_tile_pos = tilemap.local_to_map(player.global_position)
	var walkable_tiles = get_walkable_tiles_in_distance(player_tile_pos, minR, maxR)
	return walkable_tiles

func getNRandomNavigableTileInPlayerRadius(playerId, n, minR, maxR) -> Array:
	if !tilemap:
		return []
	var tiles = getNavigableTiles(playerId, minR, maxR)
	var randomPositions := []
	if tiles.is_empty():
		return []
	for i in range(n):
		randomPositions.append(tilemap.map_to_local(tiles.pick_random()))
	return randomPositions

func get_walkable_tiles_in_distance(player_tile_pos: Vector2i, min_distance: int, max_distance: int) -> Array:
	if !tilemap:
		return []
	var walkable_tiles = []
	var visited = {}
	var queue = []
	
	queue.append([player_tile_pos, 0])  # [tile_position, current_distance]
	visited[player_tile_pos] = true

	while queue.size() > 0:
		var item = queue.pop_front()
		var current_pos = item[0]
		var current_dist = item[1]

		if current_dist > max_distance:
			continue

		if current_dist >= min_distance and is_walkable(current_pos):
			walkable_tiles.append(current_pos)

		for neighbor in get_neighbors(current_pos):
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append([neighbor, current_dist + 1])

	return walkable_tiles

func is_walkable(tile_pos: Vector2i) -> bool:
	if !tilemap:
		return false
	var atlas_coord = tilemap.get_cell_atlas_coords(0, tile_pos, false)
	# Check if it's a wall tile (8,12) or if it's not in WALKABLE_TILES
	if atlas_coord == Vector2i(8,12) or not atlas_coord in WALKABLE_TILES:
		return false
	# Check if it's a fence in the terrain data
	var map_node = $"../Map"
	if !map_node:
		return false
	var terrain_data = map_node.terrain_data
	if terrain_data.has(tile_pos) and terrain_data[tile_pos] == "fence":
		return false
	return true

func get_neighbors(tile_pos: Vector2i) -> Array:
	if !tilemap:
		return []
	var neighbors = [
		tile_pos + Vector2i(1, 0),
		tile_pos + Vector2i(-1, 0),
		tile_pos + Vector2i(0, 1),
		tile_pos + Vector2i(0, -1)
	]

	var valid_neighbors = []
	for neighbor in neighbors:
		if tilemap.get_cell_source_id(0, neighbor) != -1:  # Check if the cell is valid
			valid_neighbors.append(neighbor)

	return valid_neighbors
