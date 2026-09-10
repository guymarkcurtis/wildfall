## Manages positional audio and ambient sounds.
class_name AudioEffects
extends Node

var audio_manager: AudioManager = null

# Ambient sounds
var ambient_players: Dictionary = {}

# Signals
signal ambient_started(sound_id: String)
signal ambient_stopped(sound_id: String)

## Initialize the audio effects system.
func initialize(manager: AudioManager) -> void:
	audio_manager = manager
	_setup_ambient_sounds()
	print("AudioEffects: Initialized")

## Set up ambient sounds.
func _setup_ambient_sounds() -> void:
	# Day ambient
	ambient_players["day_birds"] = _create_ambient_player("day_birds")
	ambient_players["day_wind"] = _create_ambient_player("day_wind")
	
	# Night ambient
	ambient_players["night_crickets"] = _create_ambient_player("night_crickets")
	ambient_players["night_wind"] = _create_ambient_player("night_wind")
	
	# Battle ambient
	ambient_players["battle_sounds"] = _create_ambient_player("battle_sounds")

## Create an ambient audio player.
func _create_ambient_player(sound_id: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = sound_id
	add_child(player)
	return player

## Start ambient sounds.
func start_ambient(time_of_day: String = "day") -> void:
	match time_of_day:
		"day":
			_start_ambient_sound("day_birds")
			_start_ambient_sound("day_wind")
		"night":
			_start_ambient_sound("night_crickets")
			_start_ambient_sound("night_wind")

## Stop ambient sounds.
func stop_ambient() -> void:
	for sound_id in ambient_players:
		_stop_ambient_sound(sound_id)

## Start an ambient sound.
func _start_ambient_sound(sound_id: String) -> void:
	var player := ambient_players.get(sound_id)
	if player:
		player.play()
		ambient_started.emit(sound_id)

## Stop an ambient sound.
func _stop_ambient_sound(sound_id: String) -> void:
	var player := ambient_players.get(sound_id)
	if player:
		player.stop()
		ambient_stopped.emit(sound_id)

## Play positional sound.
func play_positional_sound(sound_id: String, position: Vector2) -> void:
	# Simplified - would use 3D audio in full implementation
	if audio_manager:
		audio_manager.play_sfx(sound_id)

## Play proximity sound.
func play_proximity_sound(sound_id: String, player_position: Vector2, sound_position: Vector2, max_distance: float = 200.0) -> void:
	var distance := player_position.distance_to(sound_position)
	if distance <= max_distance:
		var volume := 1.0 - (distance / max_distance)
		if audio_manager:
			audio_manager.play_sfx(sound_id, volume)

## Update audio based on game state.
func _process(delta: float) -> void:
	# Update ambient sounds based on time of day
	var day_night := get_node_or_null("/root/Main/DayNightCycle")
	if day_night:
		var is_day := day_night.is_daytime()
		if is_day and not ambient_players["day_birds"].playing:
			start_ambient("day")
		elif not is_day and not ambient_players["night_crickets"].playing:
			start_ambient("night")
