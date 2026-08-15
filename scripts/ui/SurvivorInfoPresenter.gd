class_name SurvivorInfoPresenter
extends RefCounted

const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")


static func section_tooltip(section_id: String) -> String:
	match section_id:
		"states":
			return "Stany to bieżące wartości zdrowia, głodu, zmęczenia i morale. Mogą osobno zablokować pracę albo nurkowanie. Najedź na konkretną wartość, aby zobaczyć jej progi."
		"traits":
			return "Cechy opisują osobowość mieszkańca. Obecnie są informacją narracyjną i nie zmieniają statystyk, zdolności ani wyniku pracy."
		"competencies":
			return "Kompetencje to pasywne umiejętności rozwijane od poziomu 0 do 3. Każda ma własny, deterministyczny efekt. Najedź na nazwę, aby zobaczyć dokładne działanie."
	return ""


static func stat_text(survivor, stat_id: String) -> String:
	if survivor == null:
		return "—"
	match stat_id:
		"health":
			return "Zdrowie %d/%d" % [int(survivor.health), int(survivor.get_max_health())]
		"hunger":
			return "Głód %d%%" % int(survivor.hunger)
		"fatigue":
			return "Zmęczenie %d%%" % int(survivor.fatigue)
		"morale":
			return "Morale %d%%" % int(survivor.morale)
		"oxygen":
			return "Tlen osobisty %.0f" % float(survivor.get_oxygen_capacity())
		"carry":
			return "Udźwig %.1f kg" % float(survivor.get_carry_capacity())
	return stat_id.capitalize()


static func stat_tooltip(survivor, stat_id: String) -> String:
	if survivor == null:
		return "Brak danych mieszkańca."
	match stat_id:
		"health":
			return "%s (%.0f%% maksimum).\nOkreśla przeżycie i odporność na obrażenia. Praca wymaga co najmniej %.0f%%, a stanowisko Nurka co najmniej %.0f%% maksimum." % [
				stat_text(survivor, stat_id),
				float(survivor.health_ratio()) * 100.0,
				SurvivorStateScript.WORK_MIN_HEALTH_RATIO * 100.0,
				SurvivorStateScript.DIVE_MIN_HEALTH_RATIO * 100.0,
			]
		"hunger":
			return "%s. Im wyższy Głód, tym gorzej.\nPraca wymaga wartości poniżej %d%%, a stanowisko Nurka poniżej %d%%." % [
				stat_text(survivor, stat_id),
				SurvivorStateScript.WORK_MAX_HUNGER_EXCLUSIVE,
				SurvivorStateScript.DIVE_MAX_HUNGER_EXCLUSIVE,
			]
		"fatigue":
			return "%s. Im wyższe Zmęczenie, tym gorzej.\nPraca wymaga wartości poniżej %d%%, a stanowisko Nurka poniżej %d%%. Przy 85–89%% osoba może nadal pracować z 35%% zwykłej wydajności, ale nie może nurkować." % [
				stat_text(survivor, stat_id),
				SurvivorStateScript.WORK_MAX_FATIGUE_EXCLUSIVE,
				SurvivorStateScript.DIVE_MAX_FATIGUE_EXCLUSIVE,
			]
		"morale":
			return "%s. Wyższe Morale pomaga utrzymać zdolność i wydajność pracy.\nPraca wymaga co najmniej %d%%, a stanowisko Nurka co najmniej %d%%." % [
				stat_text(survivor, stat_id),
				SurvivorStateScript.WORK_MIN_MORALE,
				SurvivorStateScript.DIVE_MIN_MORALE,
			]
		"oxygen":
			return "%s. To osobista pojemność tlenu mieszkańca. Przy wyprawie system łączy ją z wyposażoną butlą i premią specjalizacji Nurka." % stat_text(survivor, stat_id)
		"carry":
			return "%s. To maksymalna masa łupu niesionego przez tę osobę; liczba slotów plecaka jest osobnym limitem." % stat_text(survivor, stat_id)
	return stat_text(survivor, stat_id)


static func trait_tooltip(trait_name: String, positive: bool) -> String:
	var normalized := trait_name.strip_edges()
	if normalized.is_empty():
		return "Brak zapisanej cechy."
	return "%s: %s.\nCecha narracyjna opisująca osobowość. Obecnie nie zmienia statystyk, zdolności ani wyniku pracy." % [
		"Atut" if positive else "Słabość",
		normalized.capitalize(),
	]


static func combined_state_tooltip(survivor) -> String:
	return "\n\n".join([
		stat_tooltip(survivor, "health"),
		stat_tooltip(survivor, "hunger"),
		stat_tooltip(survivor, "fatigue"),
		stat_tooltip(survivor, "morale"),
	])
