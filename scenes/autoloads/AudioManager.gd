# godot 4.3
extends Node

func _ready():
	# Get the master bus index
	var master_bus_idx = AudioServer.get_bus_index("Master")
	
	# Set the master volume to normal (0 dB as reference)
	AudioServer.set_bus_volume_db(master_bus_idx, 0.0)
	
	# Create a new bus for footsteps
	AudioServer.add_bus()
	var footsteps_bus_idx = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(footsteps_bus_idx, "FootstepSounds")
	
	# Set footsteps to +12 dB (loud and clear)
	AudioServer.set_bus_send(footsteps_bus_idx, "Master")
	AudioServer.set_bus_volume_db(footsteps_bus_idx, 12.0)
	
	# Create a new bus for attack sounds
	AudioServer.add_bus()
	var attack_bus_idx = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(attack_bus_idx, "AttackSounds")
	
	# Set attack sounds to -30 dB (very quiet)
	AudioServer.set_bus_send(attack_bus_idx, "Master")
	AudioServer.set_bus_volume_db(attack_bus_idx, -30.0) 