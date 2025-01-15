extends Node

signal player_spawned(peer_id: int, player_info: Dictionary)
signal player_connected(id: int)
signal player_disconnected(id: int)

var mapSeed: int = 0
var players = {}
var my_info = {"name": ""}

func _ready():
	# Initialize multiplayer API
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)

func _on_player_connected(id: int):
	player_connected.emit(id)

func _on_player_disconnected(id: int):
	player_disconnected.emit(id)
	if players.has(id):
		players.erase(id) 