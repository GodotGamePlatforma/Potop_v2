class_name CompetencySystem
extends RefCounted

const MAX_LEVEL := 3
const IDS: Array[String] = [
	"swimming", "oxygen_economy", "cold_resistance", "production",
	"cooperation", "resilience", "tool_handling", "vigilance",
	"load_trim", "quiet_profile", "composure", "seal_control",
	"work_ergonomics", "fortitude", "workplace_hygiene",
]

const LABELS: Dictionary = {
	"swimming": "Pływanie",
	"oxygen_economy": "Gospodarka tlenem",
	"cold_resistance": "Odporność na chłód",
	"production": "Produkcja",
	"cooperation": "Współpraca",
	"resilience": "Odporność organizmu",
	"tool_handling": "Obsługa narzędzi",
	"vigilance": "Czujność",
	"load_trim": "Trym ładunku",
	"quiet_profile": "Cichy profil",
	"composure": "Zimna krew",
	"seal_control": "Kontrola szczelności",
	"work_ergonomics": "Ergonomia pracy",
	"fortitude": "Hart ducha",
	"workplace_hygiene": "Higiena pracy",
}

const DESCRIPTIONS: Dictionary = {
	"swimming": "Zwiększa szybkość tej osoby podczas pływania o 5% za każdy poziom.",
	"oxygen_economy": "Zmniejsza zużycie tlenu tej osoby podczas wyprawy o 4% za każdy poziom.",
	"cold_resistance": "Zmniejsza tempo narastania wychłodzenia tej osoby o 5% za każdy poziom.",
	"production": "Zwiększa osobisty wkład tej osoby w produkcję Warsztatu o 5% za każdy poziom.",
	"cooperation": "Zwiększa osobistą wydajność pracy tej osoby o 4% za każdy poziom.",
	"resilience": "Zmniejsza jawną presję choroby tej osoby o 1 punkt za każdy poziom.",
	"tool_handling": "Skraca czas interakcji tej osoby podczas wyprawy o 5% za każdy poziom.",
	"vigilance": "Obniża próg wizualnego ostrzeżenia o zagrożeniu o 5 punktów za każdy poziom, więc ostrzeżenie pojawia się wcześniej.",
	"load_trim": "Zmniejsza część zużycia tlenu wynikającą z obciążenia o 20% na I, 35% na II i 50% na III poziomie.",
	"quiet_profile": "Przyspiesza zanikanie hałasu poza sprintem o 20% za każdy poziom.",
	"composure": "Przyspiesza opadanie alarmu zagrożeń bez aktywnego bodźca o 15% za każdy poziom.",
	"seal_control": "Gdy stan kombinezonu spadnie poniżej 50%, zmniejsza obrażenia zdrowia od przecieku o 15% za każdy poziom.",
	"work_ergonomics": "Zmniejsza przyrost zmęczenia tej osoby z faktycznie wykonanej pracy o 1 punkt za każdy poziom.",
	"fortitude": "Zmniejsza osobistą utratę morale wynikającą z niskiej Nadziei o 1 punkt za każdy poziom; kryzys nadal odbiera co najmniej 1 punkt.",
	"workplace_hygiene": "Zmniejsza presję choroby przekazywaną współpracownikom przez tę osobę o 1 punkt za każdy poziom.",
}

static func is_valid_id(competency_id: String) -> bool:
	return competency_id in IDS

static func level(holder, competency_id: String) -> int:
	if holder == null or not is_valid_id(competency_id):
		return 0
	var levels: Dictionary = holder.competency_levels if "competency_levels" in holder else {}
	return clampi(int(levels.get(competency_id, 0)), 0, MAX_LEVEL)

static func bonus(holder, competency_id: String, per_level: float) -> float:
	return float(level(holder, competency_id)) * per_level

static func swimming_multiplier(holder) -> float:
	return 1.0 + bonus(holder, "swimming", 0.05)

static func oxygen_use_multiplier(holder) -> float:
	return 1.0 - bonus(holder, "oxygen_economy", 0.04)

static func cold_rate_multiplier(holder) -> float:
	return 1.0 - bonus(holder, "cold_resistance", 0.05)

static func production_multiplier(holder) -> float:
	return 1.0 + bonus(holder, "production", 0.05)

static func cooperation_multiplier(holder) -> float:
	return 1.0 + bonus(holder, "cooperation", 0.04)

static func disease_pressure_reduction(holder) -> int:
	return level(holder, "resilience")

static func interaction_speed_multiplier(holder) -> float:
	return 1.0 / maxf(1.0 - bonus(holder, "tool_handling", 0.05), 0.01)

static func vigilance_warning_reduction(holder) -> float:
	return bonus(holder, "vigilance", 5.0)


static func load_oxygen_surcharge_multiplier(holder) -> float:
	match level(holder, "load_trim"):
		1:
			return 0.80
		2:
			return 0.65
		3:
			return 0.50
	return 1.0


static func noise_decay_multiplier(holder) -> float:
	return 1.0 + bonus(holder, "quiet_profile", 0.20)


static func threat_alert_decay_multiplier(holder) -> float:
	return 1.0 + bonus(holder, "composure", 0.15)


static func leak_health_damage_multiplier(holder) -> float:
	return 1.0 - bonus(holder, "seal_control", 0.15)


static func work_fatigue_reduction(holder) -> int:
	return level(holder, "work_ergonomics")


static func low_hope_morale_loss_reduction(holder) -> int:
	return level(holder, "fortitude")


static func emitted_disease_pressure_reduction(holder) -> int:
	return level(holder, "workplace_hygiene")


static func tooltip_text(holder, competency_id: String) -> String:
	if not is_valid_id(competency_id):
		return "Nieznana kompetencja."
	var current_level := level(holder, competency_id)
	return "%s — poziom %d/%d\n%s\nAktualny efekt: %s" % [
		str(LABELS[competency_id]),
		current_level,
		MAX_LEVEL,
		str(DESCRIPTIONS[competency_id]),
		_effect_summary(competency_id, current_level),
	]


static func _effect_summary(competency_id: String, current_level: int) -> String:
	match competency_id:
		"swimming":
			return "+%d%% szybkości pływania." % (current_level * 5)
		"oxygen_economy":
			return "−%d%% zużycia tlenu." % (current_level * 4)
		"cold_resistance":
			return "−%d%% tempa narastania zimna." % (current_level * 5)
		"production":
			return "+%d%% osobistego wkładu w produkcję." % (current_level * 5)
		"cooperation":
			return "+%d%% osobistej wydajności pracy." % (current_level * 4)
		"resilience":
			return "−%d pkt presji choroby." % current_level
		"tool_handling":
			return "−%d%% czasu interakcji." % (current_level * 5)
		"vigilance":
			return "ostrzeżenie o %d pkt wcześniej." % (current_level * 5)
		"load_trim":
			var reductions := [0, 20, 35, 50]
			return "−%d%% tlenowej dopłaty za ładunek." % int(reductions[clampi(current_level, 0, MAX_LEVEL)])
		"quiet_profile":
			return "+%d%% tempa zanikania hałasu poza sprintem." % (current_level * 20)
		"composure":
			return "+%d%% tempa opadania alarmu bez bodźca." % (current_level * 15)
		"seal_control":
			return "−%d%% obrażeń zdrowia od przecieku poniżej 50%% stanu kombinezonu." % (current_level * 15)
		"work_ergonomics":
			return "−%d pkt zmęczenia z wykonanej pracy." % current_level
		"fortitude":
			return "do −%d pkt osobistej utraty morale z niskiej Nadziei." % current_level
		"workplace_hygiene":
			return "−%d pkt presji choroby przekazywanej współpracownikom." % current_level
	return "brak aktywnego efektu."
