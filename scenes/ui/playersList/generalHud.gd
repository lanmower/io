# godot 4.3
extends Control

func _ready():
	makePlayerList()
	Multihelper.player_connected.connect(makePlayerList)
	Multihelper.player_disconnected.connect(makePlayerList)

func makePlayerList():
	for c in %playerList.get_children():
		c.queue_free()
	for player in Multihelper.spawnedPlayers.keys():
		var playerSlotScene := preload("res://scenes/ui/playersList/player_slot.tscn")
		var playerSlot := playerSlotScene.instantiate()
		%playerList.add_child(playerSlot)
		playerSlot.playerId = player
