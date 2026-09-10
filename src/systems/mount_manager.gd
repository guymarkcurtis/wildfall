## Manages all mounts in the game.
class_name MountManager
extends Node

# Dictionary of mount_id -> Mount
var mounts: Dictionary = {}

# Currently ridden mount
var current_mount: Mount = null

# Signals
signal mount_acquired(mount_id: String)
signal mount_lost(mount_id: String)
signal mount_ridden(mount_id: String)
signal mount_dismounted(mount_id: String)
signal mounts_changed(mount_count: int)

## Initialize the mount manager.
func initialize() -> void:
	print("MountManager: Initialized")

## Acquire a mount.
func acquire_mount(mount: Mount) -> bool:
	var mount_id := mount.get_mount_id()
	if mounts.has(mount_id):
		return false
	
	mounts[mount_id] = mount
	mount_acquired.emit(mount_id)
	mounts_changed.emit(mounts.size())
	return true

## Lose a mount.
func lose_mount(mount_id: String) -> bool:
	if not mounts.has(mount_id):
		return false
	
	if current_mount and current_mount.get_mount_id() == mount_id:
		current_mount.dismount()
		current_mount = None
	
	mounts.erase(mount_id)
	mount_lost.emit(mount_id)
	mounts_changed.emit(mounts.size())
	return true

## Get a mount.
func get_mount(mount_id: String) -> Mount:
	return mounts.get(mount_id)

## Get all mounts.
func get_all_mounts() -> Array[Mount]:
	return mounts.values()

## Ride a mount.
func ride_mount(mount_id: String) -> bool:
	var mount := mounts.get(mount_id)
	if not mount:
		return false
	
	if current_mount:
		current_mount.dismount()
	
	mount.ride()
	current_mount = mount
	mount_ridden.emit(mount_id)
	return true

## Dismount from current mount.
func dismount_mount() -> bool:
	if not current_mount:
		return false
	
	current_mount.dismount()
	var mount_id := current_mount.get_mount_id()
	current_mount = None
	mount_dismounted.emit(mount_id)
	return true

## Get current mount.
func get_current_mount() -> Mount:
	return current_mount

## Check if player is riding.
func is_riding() -> bool:
	return current_mount != None

## Get mount count.
func get_mount_count() -> int:
	return mounts.size()

## Clear all mounts.
func clear_all() -> void:
	for mount_id in mounts:
		mounts[mount_id].queue_free()
	mounts.clear()
	current_mount = None
	mounts_changed.emit(0)

## Serialize mount data.
func serialize_all() -> Dictionary:
	var data := {}
	for mount_id in mounts:
		data[mount_id] = mounts[mount_id].serialize()
	return data

## Restore mount data from save.
func deserialize_all(data: Dictionary) -> void:
	clear_all()
	for mount_id in data:
		var mount_data := data[mount_id]
		var mount_type := mount_data.get("mount_type", 0)
		var mount = Mount.new()
		mount.deserialize(mount_data)
		mounts[mount_id] = mount
		if mount_data.get("is_ridden", false):
			mount.ride()
			current_mount = mount
	mounts_changed.emit(mounts.size())

## Get mounts of a specific type.
func get_mounts_by_type(mount_type: int) -> Array[Mount]:
	var result: Array[Mount] = []
	for mount_id in mounts:
		var mount := mounts[mount_id]
		if mount.get_mount_type() == mount_type:
			result.append(mount)
	return result
