# godot 4.3
extends Control

@export var minimap_size = Vector2(200, 200)
@export var zoom = 0.2
@export var mobs_container_path: NodePath
@export var players_container_path: NodePath

@onready var tile_map = get_node("/root/Game/Level/Main/Map/TileMap")
var mobs_container
var players_container

const PLAYER_COLOR = Color(1, 0, 0)  # Red
const MOB_COLOR = Color(1, 0.5, 0)   # Orange
const BACKGROUND_COLOR = Color(0.1, 0.1, 0.1, 0.5)  # Dark gray with some transparency

func _ready():
	if !tile_map:
		push_error("TileMap node not found! Check the path: /root/Game/Level/Main/Map/TileMap")
		return
	custom_minimum_size = minimap_size
	mobs_container = get_node(mobs_container_path) if mobs_container_path else null
	players_container = get_node(players_container_path) if players_container_path else null

func _draw():
	if !tile_map or !tile_map.tile_set:
		return
		
	# Draw background
	draw_rect(Rect2(Vector2.ZERO, minimap_size), BACKGROUND_COLOR)
	
	# Draw mobs if container exists
	if mobs_container:
		for mob in mobs_container.get_children():
			if mob and is_instance_valid(mob):
				var mob_pos = mob.global_position * zoom
				draw_circle(mob_pos, 2, MOB_COLOR)
	
	# Draw players if container exists
	if players_container:
		for player in players_container.get_children():
			if player and is_instance_valid(player):
				var player_pos = player.global_position * zoom
				draw_circle(player_pos, 3, PLAYER_COLOR)

func _process(_delta):
	queue_redraw()
