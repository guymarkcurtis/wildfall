## Manages all audio in the game.
class_name AudioManager
extends Node

# Audio types
enum AudioType {
	MUSIC,
	SFX,
	VOICE
}

# Audio channels
enum AudioChannel {
	BACKGROUND,
	EFFECTS,
	VOICE
}

# Audio data
var music_volume: float = 0.7
var sfx_volume: float = 0.8
var voice_volume: float = 0.9
var master_volume: float = 1.0

# Audio players
var music_player: AudioStreamPlayer = null
var sfx_player: AudioStreamPlayer = null
var voice_player: AudioStreamPlayer = null

# Audio library
var audio_library: Dictionary = {}

# Signals
signal music_changed(volume: float)
signal sfx_changed(volume: float)
signal audio_played(audio_type: AudioType, audio_id: String)
signal audio_stopped(audio_id: String)

## Initialize the audio manager.
func initialize() -> void:
	_setup_audio_players()
	_load_audio_library()
	print("AudioManager: Initialized")

## Set up audio players.
func _setup_audio_players() -> void:
	# Create music player
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	add_child(music_player)
	
	# Create SFX player
	sfx_player = AudioStreamPlayer.new()
	sfx_player.name = "SFXPlayer"
	add_child(sfx_player)
	
	# Create voice player
	voice_player = AudioStreamPlayer.new()
	voice_player.name = "VoicePlayer"
	add_child(voice_player)
	
	# Set volumes
	_update_volumes()

## Load audio library.
func _load_audio_library() -> void:
	# Music tracks
	audio_library["music_day"] = {
		"type": AudioType.MUSIC,
		"stream": null,  # Would load from resource
		"loop": true
	}
	
	audio_library["music_night"] = {
		"type": AudioType.MUSIC,
		"stream": null,
		"loop": true
	}
	
	audio_library["music_battle"] = {
		"type": AudioType.MUSIC,
		"stream": null,
		"loop": true
	}
	
	# Sound effects
	audio_library["sfx_harvest"] = {
		"type": AudioType.SFX,
		"stream": null,
		"loop": false
	}
	
	audio_library["sfx_craft"] = {
		"type": AudioType.SFX,
		"stream": null,
		"loop": false
	}
	
	audio_library["sfx_hit"] = {
		"type": AudioType.SFX,
		"stream": null,
		"loop": false
	}
	
	audio_library["sfx_pickup"] = {
		"type": AudioType.SFX,
		"stream": null,
		"loop": false
	}
	
	audio_library["sfx_footstep"] = {
		"type": AudioType.SFX,
		"stream": null,
		"loop": false
	}
	
	audio_library["sfx_door"] = {
		"type": AudioType.SFX,
		"stream": null,
		"loop": false
	}
	
	audio_library["sfx_alert"] = {
		"type": AudioType.SFX,
		"stream": null,
		"loop": false
	}
	
	# Voice lines
	audio_library["voice_greeting"] = {
		"type": AudioType.VOICE,
		"stream": null,
		"loop": false
	}

## Play music.
func play_music(music_id: String, fade_in: float = 1.0) -> void:
	var audio_data := audio_library.get(music_id)
	if not audio_data or audio_data["type"] != AudioType.MUSIC:
		return
	
	music_player.stream = audio_data["stream"]
	music_player.volume_db = linear_to_db(music_volume)
	music_player.play()
	
	if fade_in > 0:
		_fade_in(music_player, fade_in)
	
	audio_played.emit(AudioType.MUSIC, music_id)

## Play a sound effect.
func play_sfx(sfx_id: String, volume_mod: float = 1.0) -> void:
	var audio_data := audio_library.get(sfx_id)
	if not audio_data or audio_data["type"] != AudioType.SFX:
		return
	
	sfx_player.stream = audio_data["stream"]
	sfx_player.volume_db = linear_to_db(sfx_volume * volume_mod)
	sfx_player.play()
	
	audio_played.emit(AudioType.SFX, sfx_id)

## Play a voice line.
func play_voice(voice_id: String) -> void:
	var audio_data := audio_library.get(voice_id)
	if not audio_data or audio_data["type"] != AudioType.VOICE:
		return
	
	voice_player.stream = audio_data["stream"]
	voice_player.volume_db = linear_to_db(voice_volume)
	voice_player.play()
	
	audio_played.emit(AudioType.VOICE, voice_id)

## Stop music.
func stop_music(fade_out: float = 0.5) -> void:
	if music_player.stream:
		_fade_out(music_player, fade_out)
		audio_stopped.emit(music_player.stream.resource_path)

## Stop all audio.
func stop_all() -> void:
	music_player.stop()
	sfx_player.stop()
	voice_player.stop()

## Set music volume.
func set_music_volume(volume: float) -> void:
	music_volume = clamp(volume, 0.0, 1.0)
	_update_volumes()
	music_changed.emit(music_volume)

## Set SFX volume.
func set_sfx_volume(volume: float) -> void:
	sfx_volume = clamp(volume, 0.0, 1.0)
	_update_volumes()
	sfx_changed.emit(sfx_volume)

## Set master volume.
func set_master_volume(volume: float) -> void:
	master_volume = clamp(volume, 0.0, 1.0)
	_update_volumes()

## Update all volumes.
func _update_volumes() -> void:
	music_player.volume_db = linear_to_db(music_volume * master_volume)
	sfx_player.volume_db = linear_to_db(sfx_volume * master_volume)
	voice_player.volume_db = linear_to_db(voice_volume * master_volume)

## Fade in audio.
func _fade_in(player: AudioStreamPlayer, duration: float) -> void:
	player.volume_db = linear_to_db(0.0)
	var tween := create_tween()
	tween.tween_property(player, "volume_db", linear_to_db(music_volume), duration)

## Fade out audio.
func _fade_out(player: AudioStreamPlayer, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(player, "volume_db", linear_to_db(0.0), duration)
	tween.tween_callback(player.stop)

## Get current music.
func get_current_music() -> String:
	if music_player.stream:
		return music_player.stream.resource_path
	return ""

## Check if music is playing.
func is_music_playing() -> bool:
	return music_player.playing

## Get music volume.
func get_music_volume() -> float:
	return music_volume

## Get SFX volume.
func get_sfx_volume() -> float:
	return sfx_volume

## Serialize audio settings.
func serialize() -> Dictionary:
	return {
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"voice_volume": voice_volume,
		"master_volume": master_volume
	}

## Deserialize audio settings.
func deserialize(data: Dictionary) -> void:
	music_volume = data.get("music_volume", 0.7)
	sfx_volume = data.get("sfx_volume", 0.8)
	voice_volume = data.get("voice_volume", 0.9)
	master_volume = data.get("master_volume", 1.0)
	_update_volumes()
