# godot 4.3
extends Node2D

#objects
const initialSpawnObjects := 10
const maxObjects := Constants.MAX_OBJECTS
const objectWaveCount := 10
var spawnedObjects := 0

#server camera
const SERVER_CAMERA_ZOOM := Vector2(0.1, 0.1)

#enemies
var current_day := 0  # Track the current day
const enemyWaveCount := 1
const maxEnemiesPerPlayer := Constants.MAX_ENEMIES_PER_PLAYER
const enemySpawnRadiusMin := 8
const enemySpawnRadiusMax := 9
var spawnedEnemies := {}
var boss_spawned := false  # Track if boss is spawned for current day

func _ready():
	if multiplayer.is_server():
		Multihelper.loadMap()
		spawnObjects(initialSpawnObjects)
		$HUD.queue_free()
		setupServerCamera()
	$dayNight.time_tick.connect(_on_time_tick)
	$dayNight.time_tick.connect(%DayNightCycleUI.set_daytime)
	Multihelper.player_spawned.connect(_on_player_spawned)
	createHUD()

func _on_time_tick(day: int, hour: int, _minute: int):
	if day != current_day:
		current_day = day
		boss_spawned = false  # Reset boss spawn flag for new day
	
	# Try to spawn boss at noon
	if hour == 12 and !boss_spawned:
		trySpawnBoss()

func setupServerCamera():
	var camera := Camera2D.new()
	camera.enabled = true
	camera.zoom = SERVER_CAMERA_ZOOM
	camera.position = Vector2(Constants.MAP_SIZE * 64) / 2
	add_child(camera)

func createHUD():
	var hudScene := preload("res://scenes/ui/playersList/generalHud.tscn")
	var hud := hudScene.instantiate()
	$HUD.add_child(hud)

#object spawn

func spawnObjects(amount):
	var breakableScene := preload("res://scenes/object/breakable.tscn")
	var spawnedThisWave := 0
	
	# Filter walkable tiles to exclude those too close to water
	var valid_spawn_tiles = []
	var water_check_radius = 2  # Minimum tiles away from water
	
	for tile in $Map.walkable_tiles:
		var is_valid = true
		# Check surrounding area for water
		for dx in range(-water_check_radius, water_check_radius + 1):
			for dy in range(-water_check_radius, water_check_radius + 1):
				var check_pos = Vector2i(tile.x + dx, tile.y + dy)
				if check_pos.x >= 0 and check_pos.x < $Map.map_width and check_pos.y >= 0 and check_pos.y < $Map.map_height:
					var cell = $Map.tile_map.get_cell_atlas_coords(check_pos)
					if $Map.waterCoors.has(cell):
						is_valid = false
						break
			if not is_valid:
				break
		if is_valid:
			valid_spawn_tiles.append(tile)
	
	# Only spawn if we have valid tiles
	if valid_spawn_tiles.size() > 0:
		for i in range(amount):
			var spawnTile = valid_spawn_tiles.pick_random()
			var spawnPos = $Map.tile_map.map_to_local(spawnTile)
			var breakable := breakableScene.instantiate()
			var objectId = Items.objects.keys().pick_random()
			$Objects.add_child(breakable,true)
			breakable.objectId = objectId
			breakable.position = spawnPos
			breakable.spawner = self
			spawnedObjects += 1
			spawnedThisWave += 1
	
	return spawnedThisWave

func trySpawnObjectWave():
	if spawnedObjects < maxObjects:
		var toMax := maxObjects - spawnedObjects
		
		spawnObjects(min(objectWaveCount, toMax))

func _on_object_spawn_timer_timeout():
	if multiplayer.is_server():
		trySpawnObjectWave()

#enemy spawn
func trySpawnBoss():
	var available_bosses = Items.get_bosses_for_day(current_day)
	if available_bosses.is_empty():
		return
		
	var enemyScene := preload("res://scenes/enemy/enemy.tscn")
	var players = Multihelper.spawnedPlayers.keys()
	if players.is_empty():
		return
		
	# Spawn boss near a random player
	var target_player = players.pick_random()
	var spawn_pos = $NavHelper.getNRandomNavigableTileInPlayerRadius(target_player, 1, enemySpawnRadiusMin, enemySpawnRadiusMax)[0]
	
	var boss = enemyScene.instantiate()
	$Enemies.add_child(boss, true)
	boss.position = spawn_pos
	boss.spawner = self
	boss.targetPlayerId = target_player
	boss.enemyId = available_bosses.pick_random()
	boss_spawned = true
	increasePlayerEnemyCount(target_player)

func trySpawnEnemies():
	var enemyScene := preload("res://scenes/enemy/enemy.tscn")
	var players = Multihelper.spawnedPlayers.keys()
	var available_mobs = Items.get_mobs_for_day(current_day)
	
	# Filter out boss mobs from regular spawns
	available_mobs = available_mobs.filter(func(mob_name): return !("is_boss" in Items.mobs[mob_name] and Items.mobs[mob_name]["is_boss"]))
	
	if available_mobs.is_empty():
		return
		
	for player in players:
		var playerEnemies := getPlayerEnemyCount(player)
		if playerEnemies < maxEnemiesPerPlayer:
			var toSpawn = min(maxEnemiesPerPlayer - playerEnemies, enemyWaveCount)
			var spawnPositions = $NavHelper.getNRandomNavigableTileInPlayerRadius(player, toSpawn, enemySpawnRadiusMin, enemySpawnRadiusMax)
			for pos in spawnPositions:
				var enemy = enemyScene.instantiate()
				$Enemies.add_child(enemy,true)
				enemy.position = pos
				enemy.spawner = self
				enemy.targetPlayerId = player
				enemy.enemyId = available_mobs.pick_random()
				increasePlayerEnemyCount(player)

func getPlayerEnemyCount(pId) -> int:
	if pId in spawnedEnemies:
		return spawnedEnemies[pId]
	return 0

func increasePlayerEnemyCount(pId) -> void:
	if pId in spawnedEnemies:
		spawnedEnemies[pId] += 1
	else:
		spawnedEnemies[pId] = 1

func decreasePlayerEnemyCount(pId) -> void:
	if pId in spawnedEnemies:
		spawnedEnemies[pId] -= 1
	else:
		spawnedEnemies[pId] = 1

func _on_enemy_spawn_timer_timeout():
	if multiplayer.is_server():
		trySpawnEnemies()

func _on_player_spawned(_peer_id: int, player_info: Dictionary):
	# Update UI or handle any other player spawn related logic
	if "score" in player_info:
		# Update player score display
		pass
