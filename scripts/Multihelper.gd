extends Node

signal player_spawned(peer_id: int, player_info: Dictionary)
signal player_connected(id: int)
signal player_disconnected(id: int)

var spawnedPlayers: Dictionary = {}
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

@rpc("authority", "call_remote", "reliable")
func _register_character(new_player_id: int, new_player_info: Dictionary):
	spawnedPlayers[new_player_id] = new_player_info
	player_spawned.emit(new_player_id, new_player_info)  # Emit the signal when a player is registered
	print("Player ", new_player_id, " registered with info: ", new_player_info) 