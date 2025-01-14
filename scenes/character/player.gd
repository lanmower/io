# godot 4.3
extends CharacterBody2D

signal mob_killed
signal object_destroyed
signal player_killed

@export var playerName : String:
	set(value):
		playerName = value
		$PlayerUi.setPlayerName(value)
		
@export var characterFile : String:
	set(value):
		characterFile = value
		$MovingParts/Sprite2D.texture = load("res://assets/characters/bodies/"+value)
		
var inventory : Control

var equippedItem : String:
	set(value):
		equippedItem = value
		if value in Items.equips:
			var itemData = Items.equips[value]
			if "projectile" in itemData:
				spawnsProjectile = itemData["projectile"]
		else:
			spawnsProjectile = ""

#stats
@export var maxHP := 250.0
@export var hp := maxHP:
	set(value):
		hp = value
		$bloodParticles.emitting = true
		$PlayerUi.setHPBarRatio(hp/maxHP)
		if hp <= 0:
			die()
@export var base_speed := 167
@export var speed := base_speed
var stamina: float = Constants.MAX_STAMINA
var is_running: bool = false
var can_run: bool = true
var spawnsProjectile := ""
@export var attackDamage := 10:
	get:
		if equippedItem:
			return Items.equips[equippedItem]["damage"] + attackDamage
		else:
			return attackDamage
var damageType := "normal":
	get:
		if equippedItem:
			return Items.equips[equippedItem]["damageType"]
		else:
			return damageType
var attackRange := 60.0:
	set(value):
		attackRange = value
		%HitCollision.shape.height = 20 * value

func _ready():
	if multiplayer.is_server():
		Inventory.itemRemoved.connect(itemRemoved)
		mob_killed.connect(mobKilled)
		player_killed.connect(enemyPlayerKilled)
		object_destroyed.connect(objectDestroyed)
	if name == str(multiplayer.get_unique_id()):
		inventory = get_parent().get_parent().get_node("HUD/Inventory")
		inventory.player = self
		$Camera2D.enabled = true
		# Set up debug camera if debug settings are available
		if Multihelper.debug_camera_settings != null and Multihelper.debug_camera_settings.has("zoom"):
			$Camera2D.zoom = Vector2(8, 8)  # Fixed zoom to show the whole map
		# Set up audio players for local player
		$FootstepsAudioPlayer.queue_free()  # Remove the normal footsteps player
		$AnimationPlayer.get_animation("walking").track_set_path(1, NodePath("OwnFootstepsPlayer"))
	else:
		# For other players, remove the own footsteps player
		$OwnFootstepsPlayer.queue_free()
	Multihelper.player_disconnected.connect(disconnected)

func visibilityFilter(id):
	if id == int(str(name)):
		return false
	return true

@rpc("any_peer", "call_local", "reliable")
func sendMessage(text):
	if multiplayer.is_server():
		var messageBoxScene := preload("res://scenes/ui/chat/message_box.tscn")
		var messageBox := messageBoxScene.instantiate()
		%PlayerMessages.add_child(messageBox, true)
		messageBox.text = str(text)

func disconnected(id):
	if str(id) == name:
		die()
	
func _process(_delta):
	if str(multiplayer.get_unique_id()) == name:
		var base_vel = Input.get_vector("walkLeft", "walkRight", "walkUp", "walkDown")
		
		# Handle running
		if Input.is_action_pressed("run") and can_run and stamina > Constants.MIN_STAMINA_TO_RUN:
			is_running = true
			stamina = max(0.0, stamina - Constants.STAMINA_DRAIN_RATE * _delta)
			speed = int(base_speed * Constants.RUN_SPEED_MULTIPLIER)
		else:
			is_running = false
			stamina = min(Constants.MAX_STAMINA, stamina + Constants.STAMINA_REGEN_RATE * _delta)
			speed = int(base_speed)
			
		# Prevent running if stamina is too low
		if stamina <= Constants.MIN_STAMINA_TO_RUN:
			can_run = false
		elif stamina >= Constants.MIN_STAMINA_TO_RUN * 2:
			can_run = true
			
		var vel = base_vel * speed
		var mouse_position = get_global_mouse_position()
		var direction_to_mouse = mouse_position - global_position
		var angle = direction_to_mouse.angle()
		var doingAction = Input.is_action_pressed("leftClickAction")
		
		#Apply local movement
		moveProcess(vel, angle, doingAction)
		#Send input to server for replication
		var inputData = {
			"vel": vel,
			"angle": angle,
			"doingAction": doingAction,
			"is_running": is_running
		}
		sendInputstwo.rpc_id(1, inputData)
		sendPos.rpc(position)

@rpc("any_peer", "call_local", "reliable")
func sendInputstwo(data):
	moveServer(data["vel"], data["angle"], data["doingAction"])

@rpc("any_peer", "call_local", "reliable")
func moveServer(vel, angle, doingAction):
	velocity = vel  # Set velocity for animation state
	$MovingParts.rotation = angle
	handleAnims(vel, doingAction)

@rpc("any_peer", "call_local", "reliable")
func sendPos(pos):
	position = pos

func moveProcess(vel, angle, doingAction):
	velocity = vel
	if velocity != Vector2.ZERO:
		move_and_slide()
	$MovingParts.rotation = angle
	handleAnims(vel, doingAction)

func handleAnims(vel, doing_action):
	if doing_action:
		var action_anim = Items.equips[equippedItem]["attack"] if equippedItem else "punching"
		if !$AnimationPlayer.is_playing() or $AnimationPlayer.current_animation != action_anim:
			$AnimationPlayer.play(action_anim)
	elif vel.length() > 10.0:  # Small threshold to account for floating point imprecision
		if !$AnimationPlayer.is_playing() or $AnimationPlayer.current_animation != "walking":
			$AnimationPlayer.play("walking")
	else:
		if $AnimationPlayer.current_animation == "walking":
			$AnimationPlayer.stop()

func _on_next_item():
	inventory.nextSelection()

# Define what happens when previousItem is triggered
func _on_previous_item():
	inventory.prevSelection()

# Handle input events
func _unhandled_input(event):
	if name != str(multiplayer.get_unique_id()):
		return
	if event.is_action_pressed("nextItem"):
		_on_next_item()
	elif event.is_action_pressed("previousItem"):
		_on_previous_item()

func punchCheckCollision():
	var id = multiplayer.get_unique_id()
	if spawnsProjectile:
		if str(id) == name:
			var mousePos := get_global_mouse_position()
			sendProjectile.rpc_id(1, mousePos)
	if !is_multiplayer_authority():
		return
	if equippedItem:
		Inventory.useItemDurability(str(name), equippedItem)
	for body in %HitArea.get_overlapping_bodies():
		if body != self and body.is_in_group("damageable"):
			body.getDamage(self, attackDamage, damageType)

@rpc("any_peer", "reliable")
func sendProjectile(towards):
	Items.spawnProjectile(self, spawnsProjectile, towards, "damageable")

@rpc("authority", "call_local", "reliable")
func increaseScore(by):
	hp += by * 5
	maxHP += by * 5
	attackDamage += by
	speed += by
	Multihelper.spawnedPlayers[int(str(name))]["score"] += by
	Multihelper.player_score_updated.emit()

func objectDestroyed():
	increaseScore.rpc(Constants.OBJECT_SCORE_GAIN)

func mobKilled():
	increaseScore.rpc(Constants.MOB_SCORE_GAIN)

func enemyPlayerKilled():
	increaseScore.rpc(Constants.PK_SCORE_GAIN)

func getDamage(causer, amount, _type):
	hp -= amount
	if (hp - amount) <= 0 and causer.is_in_group("player"):
		causer.player_killed.emit()

func die():
	if !multiplayer.is_server():
		return
	var peerId := int(str(name))
	Multihelper._deregister_character.rpc(peerId)
	dropInventory()
	queue_free()
	if peerId in multiplayer.get_peers():
		Multihelper.showSpawnUI.rpc_id(peerId)
		
func dropInventory():
	var inventoryDict = Inventory.inventories[name]
	for item in inventoryDict.keys():
		Items.spawnPickups(item, position, inventoryDict[item])
	Inventory.inventories[name] = {}
	Inventory.inventoryUpdated.emit(name)
	Inventory.inventories.erase(name)

@rpc("any_peer", "call_local", "reliable")
func tryEquipItem(id):
	if id in Inventory.inventories[name].keys():
		equipItem.rpc(id)

@rpc("any_peer", "call_local", "reliable")
func equipItem(id):
	equippedItem = id
	%Hands.visible = false
	%HeldItem.texture = load("res://assets/items/"+id+".png")
	if multiplayer.is_server() and "scene" in Items.equips[id]:
		for c in %Equipment.get_children():
			c.queue_free()
		var itemScene := load("res://scenes/character/equipments/"+Items.equips[id]["scene"]+".tscn")
		var item = itemScene.instantiate()
		%Equipment.add_child(item)
		item.data = {"player": str(name), "item": id}

@rpc("any_peer", "call_local", "reliable")
func unequipItem():
	equippedItem = ""
	%Hands.visible = true
	%HeldItem.texture = null
	if multiplayer.is_server():
		for c in %Equipment.get_children():
			c.queue_free()

func itemRemoved(id, item):
	if !multiplayer.is_server():
		return
	if id == str(name) and item == equippedItem:
		unequipItem.rpc()

func projectileHit(body):
	body.getDamage(self, attackDamage, damageType)
