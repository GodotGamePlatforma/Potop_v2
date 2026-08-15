class_name DifficultyMath
extends RefCounted

const _FNV_OFFSET_BASIS: int = 2_166_136_261
const _FNV_PRIME: int = 16_777_619
const _UINT32_MASK: int = 0xFFFF_FFFF
const _UNIT_BUCKET_COUNT: int = 16_777_216


static func scale_cost_amount(base_amount: int, multiplier: float) -> int:
	if base_amount <= 0 or not is_finite(multiplier) or multiplier <= 0.0:
		return 0
	var scaled := float(base_amount) * multiplier
	return maxi(int(floor(scaled + 0.5)), 1)


static func scale_cost(base_cost: Dictionary, multiplier: float) -> Dictionary:
	var result: Dictionary = {}
	for resource_id in base_cost.keys():
		result[resource_id] = scale_cost_amount(int(base_cost[resource_id]), multiplier)
	return result


## Error-diffused rounding for a cost paid repeatedly over many days. It keeps
## the long-run average equal to base*multiplier even when the authored cost is
## one unit, while every individual payment remains an integer.
static func scale_amortized_cost_amount(base_amount: int, multiplier: float, rounding_carry: float = 0.0) -> Dictionary:
	if base_amount <= 0 or not is_finite(multiplier) or multiplier <= 0.0:
		return {"amount": 0, "next_carry": 0.0}
	var carry := clampf(rounding_carry, -0.5, 0.5)
	var exact_with_carry := float(base_amount) * multiplier + carry
	var amount := maxi(int(floor(exact_with_carry + 0.5)), 0)
	var next_carry := clampf(exact_with_carry - float(amount), -0.5, 0.5)
	if is_zero_approx(next_carry):
		next_carry = 0.0
	return {"amount": amount, "next_carry": next_carry}


static func scale_loot_amount(
	base_amount: int,
	multiplier: float,
	campaign_seed: int,
	stable_source_id: String,
	stable_item_id: String,
	minimum_for_positive: int = 0
) -> int:
	if base_amount <= 0 or not is_finite(multiplier) or multiplier <= 0.0:
		return 0
	var scaled := float(base_amount) * multiplier
	var nearest_integer := roundf(scaled)
	if is_equal_approx(scaled, nearest_integer):
		scaled = nearest_integer
	var whole_amount := int(floor(scaled))
	var fraction := scaled - float(whole_amount)
	if fraction > 0.0:
		var sample := stable_unit_sample(campaign_seed, stable_source_id, stable_item_id)
		if sample < fraction:
			whole_amount += 1
	return maxi(whole_amount, maxi(minimum_for_positive, 0))


## Lowest amount that `scale_loot_amount()` can produce for any campaign seed.
## Validation uses this to prove quantity guarantees without depending on a
## favorable deterministic fractional roll.
static func minimum_loot_amount(
	base_amount: int,
	multiplier: float,
	minimum_for_positive: int = 0
) -> int:
	if base_amount <= 0 or not is_finite(multiplier) or multiplier <= 0.0:
		return 0
	var scaled := float(base_amount) * multiplier
	var nearest_integer := roundf(scaled)
	if is_equal_approx(scaled, nearest_integer):
		scaled = nearest_integer
	return maxi(int(floor(scaled)), maxi(minimum_for_positive, 0))


static func stable_unit_sample(campaign_seed: int, stable_source_id: String, stable_item_id: String) -> float:
	var payload := "%d\u001f%s\u001f%s" % [campaign_seed, stable_source_id, stable_item_id]
	var hash_value := stable_hash_32(payload)
	return float(hash_value & 0x00FF_FFFF) / float(_UNIT_BUCKET_COUNT)


static func stable_hash_32(value: String) -> int:
	var hash_value: int = _FNV_OFFSET_BASIS
	var bytes := value.to_utf8_buffer()
	for byte_value in bytes:
		hash_value = ((hash_value ^ int(byte_value)) * _FNV_PRIME) & _UINT32_MASK
	return hash_value


static func stable_signature(payload: String) -> String:
	return payload.sha256_text()
