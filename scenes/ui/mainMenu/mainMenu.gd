# godot 4.3
extends Control

func _ready():
	if DisplayServer.get_name() == "headless":
		Multihelper.create_game()

func server_offline():
	$connectTimer.start()

func _on_hostDebugButton_pressed():
	# Set up debug camera settings
	var debug_camera_settings = {
		"debug_mode": true,
		"zoom": Vector2(8, 8)  # Fixed zoom to show the whole map
	}
	# Store the debug settings in an autoload for access by the player camera
	Multihelper.debug_camera_settings = debug_camera_settings
	Multihelper.create_game()

func _on_connect_timer_timeout():
	Multihelper.join_game()
