## Separate-space cave generation foundation.
## This produces a deterministic cave layout from a stable identity. It does
## not decide when caves reset, how depletion works, or how a scene transition
## is presented; those are persistence/runtime policies owned elsewhere.
class_name CaveSpaceGenerator
extends RefCounted

const GENERATOR_VERSION := 1

func generate_cave(world_seed: int, cave_id: String, entrance_tile: Vector2i,
		definition: CaveDefinition, resource_definitions: Dictionary = {}) -> Dictionary:
	if definition == null:
		return {}
	var context := WorldGenerationContext.new(world_seed)
	var seed := context.cave_seed(cave_id, entrance_tile, definition.id)
	var random := RandomNumberGenerator.new()
	random.seed = seed
	var room_count := random.randi_range(definition.min_rooms, maxi(definition.min_rooms, definition.max_rooms))
	var rooms: Array[Dictionary] = []
	var tunnels: Array[Dictionary] = []
	for index in range(room_count):
		# The first room is the entrance chamber, anchored at the cave-space
		# origin where the runtime places the player. Later rooms branch from it.
		var center := Vector2i.ZERO if index == 0 else Vector2i(
			random.randi_range(-definition.tunnel_length * 2, definition.tunnel_length * 2),
			random.randi_range(-definition.tunnel_length * 2, definition.tunnel_length * 2)
		)
		rooms.append({"index": index, "center": center, "size": definition.room_size})
		if index > 0:
			tunnels.append({"from": rooms[index - 1]["center"], "to": center, "width": 2})
	var resource_candidates := _generate_resource_candidates(seed, rooms, definition, resource_definitions)
	return {
		"cave_id": cave_id,
		"type_id": definition.id,
		"entrance_tile": entrance_tile,
		"seed": seed,
		"version": GENERATOR_VERSION,
		"rooms": rooms,
		"tunnels": tunnels,
		"resource_ids": definition.resource_ids,
		"resource_candidates": resource_candidates,
		"reset_policy": definition.reset_policy
	}

## Create deterministic base deposits only. This is deliberately separate from
## runtime instantiation, depletion, and reset policy.
func _generate_resource_candidates(seed: int, rooms: Array[Dictionary], definition: CaveDefinition,
		resource_definitions: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if rooms.is_empty() or definition.resource_max_deposits <= 0:
		return candidates
	var eligible: Array[ResourceDefinition] = []
	for resource_id in definition.resource_ids:
		var resource_definition := resource_definitions.get(str(resource_id)) as ResourceDefinition
		if resource_definition != null and resource_definition.can_spawn_underground(definition.environment_tags):
			eligible.append(resource_definition)
	if eligible.is_empty():
		return candidates
	var random := RandomNumberGenerator.new()
	random.seed = WorldGenerationContext.mix_seed(seed, 0, 0, 0xCAFE5)
	var desired_count := random.randi_range(definition.resource_min_deposits,
		maxi(definition.resource_min_deposits, definition.resource_max_deposits))
	var attempts := 0
	while candidates.size() < desired_count and attempts < desired_count * maxi(1, definition.resource_attempt_multiplier):
		attempts += 1
		var resource_definition := _pick_resource_definition(eligible, random)
		if resource_definition == null or random.randf() > clampf(resource_definition.abundance, 0.0, 1.0):
			continue
		var room: Dictionary = rooms[random.randi_range(0, rooms.size() - 1)]
		var center: Vector2i = room.get("center", Vector2i.ZERO)
		var room_size: Vector2i = room.get("size", Vector2i(8, 8))
		var half_size := Vector2i(maxi(1, room_size.x / 2 - 1), maxi(1, room_size.y / 2 - 1))
		var position := center + Vector2i(
			random.randi_range(-half_size.x, half_size.x), random.randi_range(-half_size.y, half_size.y)
		)
		# Keep the entrance clear for the player regardless of cave type.
		if position.length_squared() <= 4.0 or not _passes_distribution(position, resource_definition, seed, random):
			continue
		if not _respects_spacing(position, resource_definition.min_spacing_tiles, candidates):
			continue
		candidates.append({
			"candidate_id": "%s@%d,%d" % [resource_definition.id, position.x, position.y],
			"resource_id": resource_definition.id,
			"position": position,
			"health": resource_definition.base_health,
			"yields": resource_definition.get_yields_for_biome("")
		})
	return candidates

func _pick_resource_definition(eligible: Array[ResourceDefinition], random: RandomNumberGenerator) -> ResourceDefinition:
	var total_weight := 0.0
	for definition in eligible:
		total_weight += maxf(0.0, definition.spawn_weight)
	if total_weight <= 0.0:
		return eligible[0]
	var roll := random.randf() * total_weight
	for definition in eligible:
		roll -= maxf(0.0, definition.spawn_weight)
		if roll <= 0.0:
			return definition
	return eligible.back()

func _passes_distribution(position: Vector2i, definition: ResourceDefinition, seed: int,
		random: RandomNumberGenerator) -> bool:
	match definition.distribution_mode:
		"sparse":
			return random.randf() < 0.55
		"clustered", "patch", "vein":
			var radius := maxi(1, definition.cluster_radius)
			var coarse := Vector2i(floori(float(position.x) / radius), floori(float(position.y) / radius))
			var field_seed := WorldGenerationContext.mix_seed(seed, coarse.x, coarse.y,
				WorldGenerationContext.stable_string_seed(definition.id))
			return fposmod(float(field_seed), 100.0) >= (32.0 if definition.distribution_mode == "vein" else 48.0)
		_:
			return true

func _respects_spacing(position: Vector2i, spacing: int, candidates: Array[Dictionary]) -> bool:
	if spacing <= 0:
		return true
	for candidate in candidates:
		var existing: Vector2i = candidate.get("position", Vector2i.ZERO)
		if abs(position.x - existing.x) <= spacing and abs(position.y - existing.y) <= spacing:
			return false
	return true
