# godot 4.3
extends Node

#Multiplayer
const SERVER_IP := "io.lan.247420.xyz"
const PORT := 8443
#const PORT := 8443
const USE_SSL := false # put certs in assets/certs, a free let's encrypt one works for itch.io
const TRUSTED_CHAIN_PATH := ""
const PRIVATE_KEY_PATH := ""

#Map
const MAP_SIZE := Vector2i(128,128) # see map.gd for tileset specific constants
const MAX_OBJECTS := 30
const MAX_ENEMIES_PER_PLAYER := 2 # see main.gd for more object and enemy spawner constants

#Player
const MAX_INVENTORY_SLOTS := 9
const OBJECT_SCORE_GAIN := 1
const MOB_SCORE_GAIN := 2
const PK_SCORE_GAIN := 4

# Player stamina settings
const MAX_STAMINA = 100.0
const STAMINA_DRAIN_RATE = 40.0  # Increased from 25.0 to drain faster
const STAMINA_REGEN_RATE = 5.0  # Reduced from 7.5 to make recovery slower
const MIN_STAMINA_TO_RUN = 10.0  # Minimum stamina needed to start running
const RUN_SPEED_MULTIPLIER = 1.6  # How much faster running is than walking

# more player related consts are in player.gd
# Item, object and equipment data is in "Items" autoload.
