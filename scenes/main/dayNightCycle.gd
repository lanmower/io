# godot 4.3
extends CanvasModulate

const MINUTES_PER_DAY = 1440.0
const MINUTES_PER_HOUR = 60.0
const INGAME_TO_REAL_MINUTE_DURATION = (2 * PI) / MINUTES_PER_DAY

signal time_tick(day:int, hour:int, minute:int)

@export var gradient_texture:GradientTexture1D
@export var INGAME_SPEED = 10.0
@export var INITIAL_HOUR = 12:
	set(h):
		INITIAL_HOUR = h
		time = INGAME_TO_REAL_MINUTE_DURATION * MINUTES_PER_HOUR * INITIAL_HOUR

@export var time:float = 0.0:
	set(value):
		time = value
		_update_color()
		_recalculate_time()

var past_minute:int = -1
var current_day := 0
var current_hour := 12
var current_minute := 0

func _ready() -> void:
	time = INGAME_TO_REAL_MINUTE_DURATION * MINUTES_PER_HOUR * INITIAL_HOUR

func _process(delta: float) -> void:
	if multiplayer.is_server():
		time += delta * INGAME_TO_REAL_MINUTE_DURATION * INGAME_SPEED

func _update_color() -> void:
	var value = (sin(time - PI / 2.0) + 1.0) / 2.0
	self.color = gradient_texture.gradient.sample(value)

@rpc("any_peer", "call_local", "reliable")
func sync_time(day: int, hour: int, minute: int) -> void:
	current_day = day
	current_hour = hour
	current_minute = minute
	time = (day * MINUTES_PER_DAY + hour * MINUTES_PER_HOUR + minute) * INGAME_TO_REAL_MINUTE_DURATION

func _recalculate_time() -> void:
	var total_minutes = int(time / INGAME_TO_REAL_MINUTE_DURATION)
	
	current_day = int(total_minutes / MINUTES_PER_DAY)
	var current_day_minutes = total_minutes % int(MINUTES_PER_DAY)
	current_hour = int(current_day_minutes / MINUTES_PER_HOUR)
	current_minute = int(current_day_minutes % int(MINUTES_PER_HOUR))
	
	if past_minute != current_minute:
		past_minute = current_minute
		time_tick.emit(current_day, current_hour, current_minute)

