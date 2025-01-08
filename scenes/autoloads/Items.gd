# godot 4.3
extends Node

# Mob templates with 50 tiers and bosses every 5 levels
const BASE_MOBS := {
	# Regular Zombies (Tier 1)
	"zombie_1": {
		"maxhp": 40, "speed": 50, "attack": "slash_attack", "attackDamage": 4,
		"attackRange": 50, "drops": {"wood": {"min": 1, "max": 2}},
		"day_introduced": 1,
		"variations": {"scale": {"min": 1.0, "max": 1.1}, "tint": {"r": {"min": 1.0, "max": 1.1}, "g": {"min": 1.0, "max": 1.0}, "b": {"min": 1.0, "max": 1.0}}}
	},
	# First Boss (Tier 5)
	"zombie_brute_5": {
		"maxhp": 300, "speed": 40, "attack": "slash_attack", "attackDamage": 15,
		"attackRange": 60, "drops": {"wood": {"min": 5, "max": 8}, "stone": {"min": 3, "max": 5}},
		"day_introduced": 5,
		"is_boss": true,
		"variations": {"scale": {"min": 1.8, "max": 2.0}, "tint": {"r": {"min": 1.5, "max": 1.7}, "g": {"min": 0.5, "max": 0.6}, "b": {"min": 0.5, "max": 0.6}}}
	},
	# Spider Scout (Tier 6)
	"spider_6": {
		"maxhp": 100, "speed": 120, "attack": "projectile_attack", "attackDamage": 8,
		"attackRange": 300, "drops": {"stone": {"min": 2, "max": 4}},
		"day_introduced": 6,
		"variations": {"scale": {"min": 1.0, "max": 1.1}, "tint": {"r": {"min": 0.8, "max": 0.9}, "g": {"min": 0.8, "max": 0.9}, "b": {"min": 1.0, "max": 1.2}}}
	},
	# Spider Queen Boss (Tier 10)
	"spider_queen_10": {
		"maxhp": 500, "speed": 90, "attack": "projectile_attack", "attackDamage": 20,
		"attackRange": 400, "drops": {"stone": {"min": 8, "max": 12}, "iron": {"min": 3, "max": 5}},
		"day_introduced": 10,
		"is_boss": true,
		"variations": {"scale": {"min": 2.0, "max": 2.2}, "tint": {"r": {"min": 1.2, "max": 1.4}, "g": {"min": 0.3, "max": 0.4}, "b": {"min": 1.3, "max": 1.5}}}
	},
	# Magic Zombie (Tier 11)
	"magic_zombie_11": {
		"maxhp": 200, "speed": 70, "attack": "magic_attack", "attackDamage": 15,
		"attackRange": 200, "drops": {"magicHerb": {"min": 1, "max": 2}},
		"day_introduced": 11,
		"variations": {"scale": {"min": 1.1, "max": 1.2}, "tint": {"r": {"min": 0.7, "max": 0.8}, "g": {"min": 0.7, "max": 0.8}, "b": {"min": 1.3, "max": 1.5}}}
	},
	# Necromancer Boss (Tier 15)
	"necromancer_15": {
		"maxhp": 800, "speed": 60, "attack": "magic_attack", "attackDamage": 30,
		"attackRange": 350, "drops": {"magicHerb": {"min": 5, "max": 8}, "crystalShard": {"min": 2, "max": 4}},
		"day_introduced": 15,
		"is_boss": true,
		"variations": {"scale": {"min": 1.8, "max": 2.0}, "tint": {"r": {"min": 0.4, "max": 0.5}, "g": {"min": 0.2, "max": 0.3}, "b": {"min": 1.5, "max": 1.7}}}
	},
	# Crystal Spider (Tier 16)
	"crystal_spider_16": {
		"maxhp": 300, "speed": 100, "attack": "projectile_attack", "attackDamage": 25,
		"attackRange": 350, "drops": {"crystalShard": {"min": 2, "max": 3}},
		"day_introduced": 16,
		"variations": {"scale": {"min": 1.2, "max": 1.3}, "tint": {"r": {"min": 0.7, "max": 0.8}, "g": {"min": 1.3, "max": 1.4}, "b": {"min": 1.3, "max": 1.4}}}
	},
	# Crystal Golem Boss (Tier 20)
	"crystal_golem_20": {
		"maxhp": 1200, "speed": 40, "attack": "magic_attack", "attackDamage": 40,
		"attackRange": 200, "drops": {"crystalShard": {"min": 8, "max": 12}, "magicStone": {"min": 4, "max": 6}},
		"day_introduced": 20,
		"is_boss": true,
		"variations": {"scale": {"min": 2.2, "max": 2.4}, "tint": {"r": {"min": 0.6, "max": 0.7}, "g": {"min": 1.5, "max": 1.6}, "b": {"min": 1.5, "max": 1.6}}}
	},
	# Shadow Assassin (Tier 21)
	"shadow_assassin_21": {
		"maxhp": 250, "speed": 150, "attack": "slash_attack", "attackDamage": 35,
		"attackRange": 80, "drops": {"magicHerb": {"min": 2, "max": 4}, "sap": {"min": 2, "max": 3}},
		"day_introduced": 21,
		"variations": {"scale": {"min": 0.9, "max": 1.0}, "tint": {"r": {"min": 0.2, "max": 0.3}, "g": {"min": 0.2, "max": 0.3}, "b": {"min": 0.4, "max": 0.5}}}
	},
	# Shadow Lord Boss (Tier 25)
	"shadow_lord_25": {
		"maxhp": 1500, "speed": 100, "attack": "magic_attack", "attackDamage": 50,
		"attackRange": 300, "drops": {"magicHerb": {"min": 8, "max": 12}, "crystalShard": {"min": 5, "max": 8}, "magicStone": {"min": 3, "max": 5}},
		"day_introduced": 25,
		"is_boss": true,
		"variations": {"scale": {"min": 2.3, "max": 2.5}, "tint": {"r": {"min": 0.1, "max": 0.2}, "g": {"min": 0.1, "max": 0.2}, "b": {"min": 0.3, "max": 0.4}}}
	},
	# Fire Elemental (Tier 26)
	"fire_elemental_26": {
		"maxhp": 400, "speed": 90, "attack": "magic_attack", "attackDamage": 40,
		"attackRange": 250, "drops": {"magicStone": {"min": 2, "max": 4}, "crystalShard": {"min": 1, "max": 2}},
		"day_introduced": 26,
		"variations": {"scale": {"min": 1.3, "max": 1.4}, "tint": {"r": {"min": 1.6, "max": 1.8}, "g": {"min": 0.6, "max": 0.7}, "b": {"min": 0.2, "max": 0.3}}}
	},
	# Inferno Lord Boss (Tier 30)
	"inferno_lord_30": {
		"maxhp": 2000, "speed": 80, "attack": "magic_attack", "attackDamage": 60,
		"attackRange": 400, "drops": {"magicStone": {"min": 10, "max": 15}, "crystalShard": {"min": 6, "max": 10}},
		"day_introduced": 30,
		"is_boss": true,
		"variations": {"scale": {"min": 2.4, "max": 2.6}, "tint": {"r": {"min": 1.8, "max": 2.0}, "g": {"min": 0.4, "max": 0.5}, "b": {"min": 0.1, "max": 0.2}}}
	},
	# Ice Wraith (Tier 31)
	"ice_wraith_31": {
		"maxhp": 500, "speed": 110, "attack": "magic_attack", "attackDamage": 45,
		"attackRange": 280, "drops": {"magicStone": {"min": 3, "max": 5}, "crystalShard": {"min": 2, "max": 3}},
		"day_introduced": 31,
		"variations": {"scale": {"min": 1.4, "max": 1.5}, "tint": {"r": {"min": 0.7, "max": 0.8}, "g": {"min": 1.5, "max": 1.6}, "b": {"min": 1.8, "max": 2.0}}}
	},
	# Frost Giant Boss (Tier 35)
	"frost_giant_35": {
		"maxhp": 2500, "speed": 70, "attack": "magic_attack", "attackDamage": 70,
		"attackRange": 350, "drops": {"magicStone": {"min": 12, "max": 18}, "crystalShard": {"min": 8, "max": 12}},
		"day_introduced": 35,
		"is_boss": true,
		"variations": {"scale": {"min": 2.5, "max": 2.7}, "tint": {"r": {"min": 0.6, "max": 0.7}, "g": {"min": 1.7, "max": 1.8}, "b": {"min": 2.0, "max": 2.2}}}
	},
	# Storm Elemental (Tier 36)
	"storm_elemental_36": {
		"maxhp": 600, "speed": 130, "attack": "magic_attack", "attackDamage": 50,
		"attackRange": 320, "drops": {"magicStone": {"min": 4, "max": 6}, "crystalShard": {"min": 3, "max": 4}},
		"day_introduced": 36,
		"variations": {"scale": {"min": 1.5, "max": 1.6}, "tint": {"r": {"min": 0.8, "max": 0.9}, "g": {"min": 0.8, "max": 0.9}, "b": {"min": 1.8, "max": 2.0}}}
	},
	# Thunder Lord Boss (Tier 40)
	"thunder_lord_40": {
		"maxhp": 3000, "speed": 100, "attack": "magic_attack", "attackDamage": 80,
		"attackRange": 450, "drops": {"magicStone": {"min": 15, "max": 20}, "crystalShard": {"min": 10, "max": 15}},
		"day_introduced": 40,
		"is_boss": true,
		"variations": {"scale": {"min": 2.6, "max": 2.8}, "tint": {"r": {"min": 1.0, "max": 1.1}, "g": {"min": 1.0, "max": 1.1}, "b": {"min": 2.2, "max": 2.4}}}
	},
	# Void Walker (Tier 41)
	"void_walker_41": {
		"maxhp": 800, "speed": 140, "attack": "magic_attack", "attackDamage": 60,
		"attackRange": 350, "drops": {"magicStone": {"min": 5, "max": 8}, "crystalShard": {"min": 4, "max": 6}},
		"day_introduced": 41,
		"variations": {"scale": {"min": 1.6, "max": 1.7}, "tint": {"r": {"min": 0.3, "max": 0.4}, "g": {"min": 0.1, "max": 0.2}, "b": {"min": 0.5, "max": 0.6}}}
	},
	# Void Lord Boss (Tier 45)
	"void_lord_45": {
		"maxhp": 3500, "speed": 110, "attack": "magic_attack", "attackDamage": 90,
		"attackRange": 500, "drops": {"magicStone": {"min": 18, "max": 25}, "crystalShard": {"min": 12, "max": 18}},
		"day_introduced": 45,
		"is_boss": true,
		"variations": {"scale": {"min": 2.7, "max": 2.9}, "tint": {"r": {"min": 0.2, "max": 0.3}, "g": {"min": 0.1, "max": 0.2}, "b": {"min": 0.4, "max": 0.5}}}
	},
	# Chaos Bringer (Tier 46)
	"chaos_bringer_46": {
		"maxhp": 1000, "speed": 150, "attack": "magic_attack", "attackDamage": 70,
		"attackRange": 400, "drops": {"magicStone": {"min": 6, "max": 10}, "crystalShard": {"min": 5, "max": 8}},
		"day_introduced": 46,
		"variations": {"scale": {"min": 1.7, "max": 1.8}, "tint": {"r": {"min": 1.8, "max": 2.0}, "g": {"min": 0.3, "max": 0.4}, "b": {"min": 1.8, "max": 2.0}}}
	},
	# World Ender Boss (Tier 50)
	"world_ender_50": {
		"maxhp": 5000, "speed": 120, "attack": "magic_attack", "attackDamage": 100,
		"attackRange": 600, "drops": {"magicStone": {"min": 25, "max": 30}, "crystalShard": {"min": 15, "max": 20}},
		"day_introduced": 50,
		"is_boss": true,
		"variations": {"scale": {"min": 3.0, "max": 3.2}, "tint": {"r": {"min": 2.0, "max": 2.2}, "g": {"min": 0.2, "max": 0.3}, "b": {"min": 2.0, "max": 2.2}}}
	}
}

# Store all mobs here (no generation needed, just reference the templates)
const mobs := BASE_MOBS

# Function to get available mobs for a given day
func get_mobs_for_day(day: int) -> Array:
	var available_mobs = []
	for mob_name in mobs:
		if mobs[mob_name]["day_introduced"] <= day:
			available_mobs.append(mob_name)
	return available_mobs

# Function to get only boss mobs for a given day
func get_bosses_for_day(day: int) -> Array:
	var available_bosses = []
	for mob_name in mobs:
		var mob = mobs[mob_name]
		if mob["day_introduced"] <= day and "is_boss" in mob and mob["is_boss"]:
			available_bosses.append(mob_name)
	return available_bosses

var objects := {
	"tree1": {"id": "tree1", "hp": 40, "tool": "axe", "drops": {"wood": {"min": 1, "max": 2}}},
	"rock1": {"id": "rock1", "hp": 70, "tool": "pickaxe", "drops": {"stone": {"min": 1, "max": 3}}},
	"tree2": {"id": "tree2", "hp": 50, "tool": "axe", "drops": {"wood": {"min": 2, "max": 4}}},
	"rock2": {"id": "rock2", "hp": 100, "tool": "pickaxe", "drops": {"stone": {"min": 2, "max": 5}}},
	"bush1": {"id": "bush1", "hp": 20, "tool": "sword", "drops": {"berries": {"min": 1, "max": 3}}},
	"ore1": {"id": "ore1", "hp": 120, "tool": "pickaxe", "drops": {"iron": {"min": 1, "max": 3}}},
	"tree3": {"id": "tree3", "hp": 60, "tool": "axe", "drops": {"wood": {"min": 3, "max": 5}, "sap": {"min": 1, "max": 1}}},
	"rock3": {"id": "rock3", "hp": 90, "tool": "pickaxe", "drops": {"stone": {"min": 2, "max": 4}, "coal": {"min": 1, "max": 2}}},
	"magicPlant1": {"id": "magicPlant1", "hp": 30, "tool": "sword", "drops": {"magicHerb": {"min": 1, "max": 2}}},
	"crystal1": {"id": "crystal1", "hp": 150, "tool": "pickaxe", "drops": {"crystalShard": {"min": 1, "max": 2}}},
	"magicTree1": {"id": "magicTree1", "hp": 70, "tool": "axe", "drops": {"magicWood": {"min": 1, "max": 3}}},
	"magicRock1": {"id": "magicRock1", "hp": 110, "tool": "pickaxe", "drops": {"magicStone": {"min": 1, "max": 2}}},
}

var equips := {
	"torch": {"attack": "swing", "damage": 20, "damageType": "normal", "durability": 40.0, "scene": "torch"},
	"sword1": {"attack": "swing", "damage": 30, "damageType": "normal", "durability": 5.0},
	"axe1": {"attack": "swing", "damage": 30, "damageType": "axe", "durability": 20.0},
	"pickaxe1": {"attack": "swing", "damage": 30, "damageType": "pickaxe", "durability": 20.0},
	"spear1": {"attack": "stab", "damage": 20, "damageType": "normal", "durability": 20.0, "projectile": "fireshuriken"},
	"dagger1": {"attack": "stab", "damage": 15, "damageType": "normal", "durability": 10.0},
	"axe2": {"attack": "swing", "damage": 40, "damageType": "axe", "durability": 30.0},
	"pickaxe2": {"attack": "swing", "damage": 40, "damageType": "pickaxe", "durability": 30.0},
	"magicSword1": {"attack": "swing", "damage": 35, "damageType": "magic", "durability": 10.0, "projectile": "magicBolt"},
	"magicAxe1": {"attack": "swing", "damage": 45, "damageType": "magic", "durability": 25.0, "projectile": "fireball"},
	"magicDagger1": {"attack": "stab", "damage": 25, "damageType": "magic", "durability": 15.0, "projectile": "iceShard"},
	"magicSpear1": {"attack": "stab", "damage": 30, "damageType": "magic", "durability": 20.0, "projectile": "lightningBolt"},
}

var recipes := {
	"torch": {"wood": 3},
	"sword1": {"wood": 2, "stone": 2},
	"axe1": {"wood": 2, "stone": 3},
	"pickaxe1": {"wood": 2, "stone": 3},
	"spear1": {"wood": 3, "stone": 1},
	"dagger1": {"wood": 1, "stone": 2},
	"axe2": {"wood": 3, "iron": 2},
	"pickaxe2": {"wood": 3, "iron": 2},
	"magicSword1": {"magicWood": 2, "magicStone": 2, "crystalShard": 1},
	"magicAxe1": {"magicWood": 3, "magicStone": 3, "crystalShard": 1},
	"magicDagger1": {"magicWood": 1, "magicStone": 2, "magicHerb": 2},
	"magicSpear1": {"magicWood": 3, "magicStone": 1, "magicHerb": 1},
}

var projectiles := {
	"fireshuriken": {"maxHits": 1, "speed": 50, "time": 1, "curveSpeed": true},
	"icebolt": {"maxHits": 1, "speed": 30, "time": 1.5, "curveSpeed": false, "effect": "freeze"},
	"magicBolt": {"maxHits": 1, "speed": 45, "time": 1.2, "curveSpeed": true, "effect": "magicDamage"},
	"fireball": {"maxHits": 1, "speed": 35, "time": 1.3, "curveSpeed": false, "effect": "burn"},
	"iceShard": {"maxHits": 1, "speed": 40, "time": 1.5, "curveSpeed": false, "effect": "slow"},
	"lightningBolt": {"maxHits": 1, "speed": 50, "time": 1, "curveSpeed": true, "effect": "stun"},
}

func spawnPickups(id, at, amount):
	var pickups := get_node("/root/Game/Level/Main/Pickups")
	for i in range(amount):
		var pickupScene := preload("res://scenes/item/pickup.tscn")
		var pickup := pickupScene.instantiate()
		pickups.call_deferred("add_child", pickup, true)
		pickup.itemId = id
		pickup.position = at + Vector2(randf_range(-15,15), randf_range(-15,15))

func spawnProjectile(spawner, pId, towardsPos, canTarget):
	var projectilesNode := get_node("/root/Game/Level/Main/Projectiles")
	var projectileScene := load("res://scenes/attacks/projectile_attack.tscn")
	var projectile = projectileScene.instantiate()
	projectilesNode.add_child(projectile,true)
	projectile.projectileId = pId
	projectile.targetGroup = canTarget
	projectile.position = spawner.position
	projectile.get_node("MovingParts").rotation = spawner.get_node("MovingParts").rotation
	projectile.hitPlayer.connect(spawner.projectileHit)
	projectile.targetPos = towardsPos
	projectile.spawner = spawner
