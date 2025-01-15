extends Node2D

@onready var tile_map = %TileMapLayer

func _ready():
	if !tile_map:
		push_error("TileMapLayer node not found! Make sure TileMapLayer node is marked as unique with @onready %!")
		return 