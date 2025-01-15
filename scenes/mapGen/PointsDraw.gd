extends Node2D

@onready var tile_map = %TileMap

func _ready():
	if !tile_map:
		push_error("TileMap node not found! Make sure TileMap node is marked as unique with @onready %!")
		return 