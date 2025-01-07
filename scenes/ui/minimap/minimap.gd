# godot 4.3
extends Control

const WALKABLE_TILES := [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0), Vector2i(16,0), Vector2i(17,0)]
const WALKABLE_COLOR := Color(0.0, 1.0, 0.0)  # Green color for walkable tiles
const DEFAULT_COLOR := Color(1.0, 1.0, 1.0, 0.2)   # White color for non-walkable tiles
const PLAYER_COLOR := Color(0.0, 0.0, 1.0)  # Blue color for players
const MOB_COLOR := Color(1.0, 0.0, 0.0)     # Red color for mobs
const ENTITY_SIZE := Vector2(4, 4)           # Slightly larger than tiles for visibility

@export var tilemap: TileMapLayer
@export var player: Node2D
@export_node_path("Node") var mobs_container_path    # Path to the node containing mobs
@export_node_path("Node") var players_container_path # Path to the node containing other players
var mobs_container: Node
var players_container: Node
@export var minimap_size: Vector2 = Vector2(200, 200)
@export var tile_size: Vector2 = Vector2(3, 3)
var drawn = false

func _ready():
	tilemap = get_node("../../../../../Map/TileMap")
	custom_minimum_size = minimap_size
	mobs_container = get_node(mobs_container_path) if mobs_container_path else null
	players_container = get_node(players_container_path) if players_container_path else null

func _draw():
	if tilemap == null:
		return
	
	# Draw the tilemap first
	var used_rect = tilemap.get_used_rect()
	for x in range(used_rect.size.x):
		for y in range(used_rect.size.y):
			var cell = tilemap.get_cell_source_id(Vector2i(x, y))
			if cell != -1:
				var cell_atlas_coords = tilemap.get_cell_atlas_coords(Vector2i(x, y))
				var tile_color = WALKABLE_COLOR if cell_atlas_coords in WALKABLE_TILES else DEFAULT_COLOR
				var tile_rect = Rect2(Vector2(x, y) * tile_size, tile_size)
				draw_rect(tile_rect, tile_color)
	
	# Draw mobs
	if mobs_container:
		for mob in mobs_container.get_children():
			var mob_pos = mob.global_position / Vector2(tilemap.tile_set.tile_size)
			draw_rect(Rect2(mob_pos * tile_size - ENTITY_SIZE/2, ENTITY_SIZE), MOB_COLOR)
	
	# Draw other players
	if players_container:
		for other_player in players_container.get_children():
			var player_pos = other_player.global_position / Vector2(tilemap.tile_set.tile_size)
			draw_rect(Rect2(player_pos * tile_size - ENTITY_SIZE/2, ENTITY_SIZE), PLAYER_COLOR)
	
	# Draw main player
	if player:
		var player_pos = player.global_position / Vector2(tilemap.tile_set.tile_size)
		draw_rect(Rect2(player_pos * tile_size - ENTITY_SIZE/2, ENTITY_SIZE), PLAYER_COLOR)

func _process(_delta):
	queue_redraw()
