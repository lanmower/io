extends Node2D

@onready var tile_map = get_node_or_null("/root/Game/Level/Main/Map/TileMap")

func _ready():
	if !tile_map:
		push_error("TileMap node not found! Check the path: /root/Game/Level/Main/Map/TileMap")
		return
	
	# Make sure we have the right node type
	if !tile_map is TileMap:
		push_error("Found node at path but it's not a TileMap!")
		return 