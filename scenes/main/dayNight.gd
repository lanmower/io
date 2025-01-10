@rpc("authority", "call_local", "reliable")
func reset_time():
	current_day = 0
	current_hour = 6  # Start at 6 AM
	current_minute = 0
	sync_time.rpc(current_day, current_hour, current_minute)
	time_tick.emit(current_day, current_hour, current_minute)

@rpc("authority", "call_remote", "reliable")
func sync_time(day: int, hour: int, minute: int):
	current_day = day
	current_hour = hour
	current_minute = minute
	time_tick.emit(current_day, current_hour, current_minute) 