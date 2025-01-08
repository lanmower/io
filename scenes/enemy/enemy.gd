# godot 4.3
extends CharacterBody2D

var spawner : Node2D
var targetPlayer : CharacterBody2D
@export var targetPlayerId : int:
	set(value):
		targetPlayerId = value
		if multiplayer.is_server():
			targetPlayer = get_node("../../Players/"+str(value))

#stats
@export var enemyId := "":
	set(value):
		enemyId = value
		if value != "":  # Only load texture if we have a valid ID
			var enemyData = Items.mobs[value]
			%Sprite2D.texture = load("res://assets/characters/enemy/"+value+".png")
			
			# Apply visual variations if they exist
			if "variations" in enemyData:
				var vars = enemyData["variations"]
				
				# Apply scale variation
				if "scale" in vars:
					var scale_factor = randf_range(vars["scale"]["min"], vars["scale"]["max"])
					%Sprite2D.scale = Vector2(scale_factor, scale_factor)
				
				# Apply color tint and opacity
				if "tint" in vars:
					var r = randf_range(vars["tint"]["r"]["min"], vars["tint"]["r"]["max"])
					var g = randf_range(vars["tint"]["g"]["min"], vars["tint"]["g"]["max"])
					var b = randf_range(vars["tint"]["b"]["min"], vars["tint"]["b"]["max"])
					var a = 1.0
					if "opacity" in vars:
						a = randf_range(vars["opacity"]["min"], vars["opacity"]["max"])
					%Sprite2D.modulate = Color(r, g, b, a)
				
				# Apply random flip
				if "flip_chance" in vars and randf() < vars["flip_chance"]:
					%Sprite2D.flip_h = true
			
			# Apply stats
			for stat in enemyData.keys():
				if stat != "variations":  # Skip variations as it's not a stat
					set(stat, enemyData[stat])

var maxhp := 100.0:
	set(value):
		maxhp = value
		hp = value
var hp := maxhp:
	set(value):
		hp = value
		$EnemyUI/HPBar.value = hp/maxhp
var speed := 2000.0
var attack := ""
var attackRange := 50.0
var attackDamage := 20.0
var drops := {}
var circling_direction := 1  # 1 for clockwise, -1 for counter-clockwise
var circle_radius := 100.0   # How far from player to circle
var circle_speed_modifier := 0.7  # Adjust this to control circling speed

@onready var anim_player = $AnimationPlayer
@onready var footsteps_player = $FootstepsAudioPlayer

func _ready():
	# Randomly choose initial circling direction
	circling_direction = 1 if randf() > 0.5 else -1
	# Verify audio setup
	print("Enemy audio setup - FootstepsAudioPlayer volume: ", footsteps_player.volume_db)
	print("Enemy audio setup - FootstepsAudioPlayer bus: ", footsteps_player.bus)

func _process(_delta):
	if multiplayer.is_server():
		if is_instance_valid(targetPlayer):
			rotateToTarget()
			if position.distance_to(targetPlayer.position) > attackRange:
				move_towards_position()
			else:
				circle_target()
				tryAttack()
		else:
			die(false)
	
	# Handle animations based on actual velocity
	update_animation_state()

func update_animation_state():
	var is_moving = velocity.length() > 10.0  # Small threshold to account for floating point imprecision
	
	if is_moving:
		if !anim_player.is_playing() or anim_player.current_animation != "walking":
			print("Enemy starting to walk, velocity: ", velocity.length())
			anim_player.play("walking")
	else:
		if anim_player.current_animation == "walking":
			print("Enemy stopping walk animation")
			anim_player.stop()

func rotateToTarget():
	$MovingParts.look_at(targetPlayer.position)

func move_towards_position():
	var direction = (targetPlayer.position - position).normalized()
	velocity = direction * speed
	move_and_slide()

func tryAttack():
	if multiplayer.is_server() and $AttackCooldown.is_stopped():
		$AttackCooldown.start()
		var projectileScene := load("res://scenes/attacks/"+attack+".tscn")
		var projectile = projectileScene.instantiate()
		spawner.get_node("Projectiles").add_child(projectile,true)
		projectile.position = position
		projectile.get_node("MovingParts").rotation = $MovingParts.rotation
		projectile.hitPlayer.connect(hitPlayer)
		projectile.targetPos = targetPlayer.position
		
func hitPlayer(body):
	if multiplayer.is_server():
		body.getDamage(self, attackDamage, "normal")
	
func getDamage(causer, amount, _type):
	hp -= amount
	$bloodParticles.emitting = true
	if hp <= 0:
		if causer.is_in_group("player"):
			causer.mob_killed.emit()
		die(true)

func die(dropLoot):
	if multiplayer.is_server():
		$AnimationPlayer.stop()  # Stop any playing animations
		spawner.decreasePlayerEnemyCount(targetPlayerId)
		queue_free()
		if dropLoot:
			dropLoots()

func dropLoots():
	for drop in drops.keys():
		Items.spawnPickups(drop, position, randi_range(drops[drop]["min"],drops[drop]["max"]))

func circle_target():
	var to_target = targetPlayer.position - position
	var distance = to_target.length()
	
	# Calculate perpendicular direction for circling
	var circle_direction = Vector2(-to_target.y, to_target.x).normalized() * circling_direction
	
	# If too close or too far, adjust radius
	var radial_direction = to_target.normalized()
	if distance < circle_radius:
		circle_direction += -radial_direction
	elif distance > circle_radius:
		circle_direction += radial_direction
	
	velocity = circle_direction.normalized() * speed * circle_speed_modifier
	move_and_slide()
	
	# Randomly change direction sometimes
	if randf() < 0.01:  # 1% chance per frame to change direction
		circling_direction *= -1
