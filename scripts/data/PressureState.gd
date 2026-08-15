class_name PressureState
extends Resource

enum Band {
	LOW,
	NORMAL,
	HIGH,
	CRISIS,
}

const DIVE_SUCCESS := "success"
const DIVE_FAILURE := "failure"
const DIVE_DEATH := "death"
const MAX_RECENT_DIVES := 3
const VALID_ACTIVE_PRESSURE_TAGS: Array[String] = [
	"food_critical",
	"hope_critical",
	"integrity_critical",
	"workforce_critical",
	"no_shelter",
	"recent_death",
	"storm_today",
	"disease_outbreak",
]
const VALID_RECOVERY_ROLES: Array[String] = ["food", "materials", "workforce", "hope", "integrity", "medicine"]

@export var day: int = 1
@export var band: int = Band.NORMAL
@export_range(0.0, 1.0, 0.001) var strain: float = 0.0
@export_range(0.0, 3.0, 0.01) var pressure_budget: float = 0.0
@export_range(0, 3) var max_event_severity: int = 0
@export var prefer_relief: bool = false
@export var tutorial_protected: bool = false
@export var critical_gates: Array[String] = []
@export var reason_codes: Array[String] = []
@export var active_pressure_tags: Array[String] = []
@export var recovery_roles: Array[String] = []
@export var blocked_impact_tags: Array[String] = []
@export var preferred_impact_tags: Array[String] = []

@export_group("Frozen settlement metrics")
@export var population: int = 0
@export_range(0.0, 10000.0, 0.01) var food_days: float = 0.0
@export_range(0.0, 100.0, 0.01) var average_hunger: float = 0.0
@export_range(0, 100) var max_hunger: int = 0
@export_range(0, 100) var hope: int = 0
@export var healthy_workers: int = 0
@export_range(0, 100) var platform_integrity: int = 0
@export var basic_materials: int = 0
@export var medicines: int = 0
@export var shelter_capacity: int = 3
@export var free_shelter: int = 0
@export var story_act: int = 1
@export var crisis_active: bool = false
@export var weather_condition: int = -1
@export var storm_today: bool = false
@export var active_disease_cases: int = 0
@export var contagious_disease_cases: int = 0
@export var disease_outbreak_active: bool = false

@export_group("Recent pressure history")
@export var recent_dive_outcomes: Array[String] = []
@export var recent_successful_dives: int = 0
@export var recent_failed_dives: int = 0
@export var last_diver_death_day: int = 0
@export var last_hardship_event_day: int = 0
@export var recovery_days_remaining: int = 0
@export var major_event_cooldown_days_remaining: int = 0
@export var consecutive_high_days: int = 0
@export var recovery_needed: bool = false

@export_group("Committed morning selection")
@export var committed_event_id: String = ""
@export var committed_event_tone: String = ""
@export_range(0, 3) var committed_event_severity: int = 0
@export_range(0.0, 3.0, 0.01) var spent_pressure_budget: float = 0.0
@export var quiet_morning: bool = false

@export_multiline var debug_summary: String = ""

func ensure_compatibility(current_day: int = -1) -> void:
	day = maxi(day if current_day < 1 else current_day, 1)
	band = clampi(band, Band.LOW, Band.CRISIS)
	strain = clampf(strain, 0.0, 1.0)
	pressure_budget = clampf(pressure_budget, 0.0, 3.0)
	max_event_severity = clampi(max_event_severity, 0, 3)
	population = maxi(population, 0)
	food_days = maxf(food_days, 0.0)
	average_hunger = clampf(average_hunger, 0.0, 100.0)
	max_hunger = clampi(max_hunger, 0, 100)
	hope = clampi(hope, 0, 100)
	healthy_workers = clampi(healthy_workers, 0, population)
	active_disease_cases = clampi(active_disease_cases, 0, population)
	contagious_disease_cases = clampi(contagious_disease_cases, 0, active_disease_cases)
	platform_integrity = clampi(platform_integrity, 0, 100)
	basic_materials = maxi(basic_materials, 0)
	medicines = maxi(medicines, 0)
	shelter_capacity = maxi(shelter_capacity, 0)
	story_act = maxi(story_act, 1)
	last_diver_death_day = maxi(last_diver_death_day, 0)
	last_hardship_event_day = maxi(last_hardship_event_day, 0)
	recovery_days_remaining = maxi(recovery_days_remaining, 0)
	major_event_cooldown_days_remaining = maxi(major_event_cooldown_days_remaining, 0)
	consecutive_high_days = maxi(consecutive_high_days, 0)
	committed_event_severity = clampi(committed_event_severity, 0, 3)
	spent_pressure_budget = clampf(spent_pressure_budget, 0.0, pressure_budget)
	if quiet_morning:
		committed_event_id = ""
		committed_event_tone = ""
		committed_event_severity = 0
		spent_pressure_budget = 0.0
	elif committed_event_id.is_empty():
		committed_event_tone = ""
		committed_event_severity = 0
		spent_pressure_budget = 0.0
	_deduplicate_strings(critical_gates)
	_deduplicate_strings(reason_codes)
	_filter_known_strings(active_pressure_tags, VALID_ACTIVE_PRESSURE_TAGS)
	_filter_known_strings(recovery_roles, VALID_RECOVERY_ROLES)
	_deduplicate_strings(blocked_impact_tags)
	_deduplicate_strings(preferred_impact_tags)
	var compatible_outcomes: Array[String] = []
	for raw_outcome in recent_dive_outcomes:
		var outcome := str(raw_outcome)
		if outcome in [DIVE_SUCCESS, DIVE_FAILURE, DIVE_DEATH]:
			compatible_outcomes.append(outcome)
	while compatible_outcomes.size() > MAX_RECENT_DIVES:
		compatible_outcomes.pop_front()
	recent_dive_outcomes.assign(compatible_outcomes)
	recent_successful_dives = recent_dive_outcomes.count(DIVE_SUCCESS)
	recent_failed_dives = recent_dive_outcomes.count(DIVE_FAILURE) + recent_dive_outcomes.count(DIVE_DEATH)
	refresh_debug_summary()


func is_valid_for_day(expected_day: int) -> bool:
	if day != expected_day or day < 1 or band not in [Band.LOW, Band.NORMAL, Band.HIGH, Band.CRISIS]:
		return false
	if strain < 0.0 or strain > 1.0 or pressure_budget < 0.0 or pressure_budget > 3.0:
		return false
	if max_event_severity < 0 or max_event_severity > 3:
		return false
	if active_disease_cases < 0 or contagious_disease_cases < 0 or contagious_disease_cases > active_disease_cases or active_disease_cases > population:
		return false
	if not _contains_only_known(active_pressure_tags, VALID_ACTIVE_PRESSURE_TAGS) or not _contains_only_known(recovery_roles, VALID_RECOVERY_ROLES):
		return false
	if spent_pressure_budget < 0.0 or spent_pressure_budget > pressure_budget + 0.0001:
		return false
	if quiet_morning:
		return committed_event_id.is_empty() and committed_event_tone.is_empty() and committed_event_severity == 0 and is_zero_approx(spent_pressure_budget)
	if committed_event_id.is_empty():
		return committed_event_tone.is_empty() and committed_event_severity == 0 and is_zero_approx(spent_pressure_budget)
	return (
		not committed_event_tone.is_empty()
		and committed_event_severity >= 0
		and committed_event_severity <= max_event_severity
	)

func has_critical_gate(gate_id: String) -> bool:
	return critical_gates.has(gate_id)

func is_recovery_day() -> bool:
	return recovery_days_remaining > 0

func has_committed_morning() -> bool:
	return quiet_morning or not committed_event_id.is_empty()

func commit_event(event_id: String, tone: String, severity: int, pressure_cost: float) -> bool:
	var resolved_id := event_id.strip_edges()
	if resolved_id.is_empty() or severity < 0 or severity > max_event_severity:
		return false
	if pressure_cost < 0.0 or pressure_cost > pressure_budget + 0.0001:
		return false
	var resolved_tone := tone.strip_edges()
	if resolved_tone.is_empty():
		resolved_tone = "neutral"
	var resolved_severity := severity
	var resolved_cost := pressure_cost
	if has_committed_morning():
		return (
			not quiet_morning
			and committed_event_id == resolved_id
			and committed_event_tone == resolved_tone
			and committed_event_severity == resolved_severity
			and is_equal_approx(spent_pressure_budget, resolved_cost)
		)
	committed_event_id = resolved_id
	committed_event_tone = resolved_tone
	committed_event_severity = resolved_severity
	spent_pressure_budget = resolved_cost
	quiet_morning = false
	refresh_debug_summary()
	return true

func commit_quiet_morning() -> bool:
	if has_committed_morning():
		return quiet_morning
	committed_event_id = ""
	committed_event_tone = ""
	committed_event_severity = 0
	spent_pressure_budget = 0.0
	quiet_morning = true
	refresh_debug_summary()
	return true

func band_name() -> String:
	match band:
		Band.LOW:
			return "LOW"
		Band.HIGH:
			return "HIGH"
		Band.CRISIS:
			return "CRISIS"
		_:
			return "NORMAL"

func refresh_debug_summary() -> void:
	var reasons := ",".join(reason_codes) if not reason_codes.is_empty() else "none"
	var morning := "quiet" if quiet_morning else (
		"%s/%s/s%d/%.2f" % [committed_event_id, committed_event_tone, committed_event_severity, spent_pressure_budget]
		if not committed_event_id.is_empty()
		else "uncommitted"
	)
	debug_summary = (
		"D%d %s strain=%.3f budget=%.2f severity<=%d | "
		+ "food=%.2fd hunger=%.1f/%d hope=%d workers=%d/%d disease=%d/%d outbreak=%s integrity=%d act=%d | morning=%s | tags=%s roles=%s | reasons=%s"
	) % [
		day,
		band_name(),
		strain,
		pressure_budget,
		max_event_severity,
		food_days,
		average_hunger,
		max_hunger,
		hope,
		healthy_workers,
		population,
		active_disease_cases,
		contagious_disease_cases,
		str(disease_outbreak_active),
		platform_integrity,
		story_act,
		morning,
		",".join(active_pressure_tags) if not active_pressure_tags.is_empty() else "none",
		",".join(recovery_roles) if not recovery_roles.is_empty() else "none",
		reasons,
	]

func _deduplicate_strings(values: Array[String]) -> void:
	var unique: Array[String] = []
	for raw_value in values:
		var value := str(raw_value)
		if not value.is_empty() and not unique.has(value):
			unique.append(value)
	values.assign(unique)

func _filter_known_strings(values: Array[String], allowed: Array[String]) -> void:
	var filtered: Array[String] = []
	for raw_value in values:
		var value := str(raw_value)
		if allowed.has(value) and not filtered.has(value):
			filtered.append(value)
	values.assign(filtered)

func _contains_only_known(values: Array[String], allowed: Array[String]) -> bool:
	var seen: Array[String] = []
	for raw_value in values:
		var value := str(raw_value)
		if not allowed.has(value) or seen.has(value):
			return false
		seen.append(value)
	return true
