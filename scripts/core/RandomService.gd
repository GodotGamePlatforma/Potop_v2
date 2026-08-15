extends RefCounted

static func sample_for_seed(seed_value: int, day: int, domain_salt: int) -> float:
	var mixed := int(seed_value) * 1_103_515_245 + int(day) * 2_531_011 + int(domain_salt) * 7_919
	mixed = mixed ^ (mixed >> 16)
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = mixed
	return local_rng.randf()
