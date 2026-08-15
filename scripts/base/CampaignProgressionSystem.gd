class_name CampaignProgressionSystem
extends RefCounted

const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const StoryProgressStateScript := preload("res://scripts/data/StoryProgressState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const ENERGY_HARBOR := "harbor"
const ENERGY_NORTH := "north"
const ENERGY_COMMON_LINE := "common_line"
const OUTCOME_QUIET_AFTER_STORM := "quiet_after_storm"
const OUTCOME_DEBT_REPAID := "debt_repaid"
const OUTCOME_LAST_BRIDGE := "last_bridge"
const JUNCTION_J7_DEVICE_ID := "junction_j7"
const ARCHIVE_TERMINAL_DEVICE_ID := "archive_terminal"
const R3_DIAGNOSTIC_DEVICE_ID := "r3_diagnostic_panel"
const R3_GENERATOR_DEVICE_ID := "r3_generator"
const C4_SWITCHBOARD_DEVICE_ID := "c4_switchboard"
const COMMON_LINE_SPLITTER_DEVICE_ID := "c4_splitter_mount"
const BLACK_FRONT_DAYS_EASY := 15
const BLACK_FRONT_DAYS_STANDARD := 12
const BLACK_FRONT_DAYS_HARD := 10
const CRISIS_DAYS := 3
const CRISIS_RECOVERY_HOPE := 15

func apply_dive_result(state, dive_result, report) -> Dictionary:
	var recovered: Dictionary = {}
	if state == null or dive_result == null or state.story_flags == null:
		return recovered
	var story = state.story_flags
	if bool(dive_result.diver_dead):
		story.diver_deaths += 1
	else:
		story.successful_dives += 1
	story.rescued_survivor_count += dive_result.rescued_survivors.size()
	if dive_result.activated_fixed_devices.has(JUNCTION_J7_DEVICE_ID) and not story.junction_j7_active:
		story.junction_j7_active = true
		story.junction_j7_activated_day = int(state.day)
		story.set_flag("junction_j7_active", true)
		_start_black_front_countdown(state)
		if report != null:
			report.add_entry("Uruchomiono węzeł J-7. Wspólna Linia otrzymała pierwszy aktywny punkt sieci.")
	if dive_result.activated_fixed_devices.has(ARCHIVE_TERMINAL_DEVICE_ID) and not story.archive_terminal_active:
		story.archive_terminal_active = true
		story.archive_map_transmitted = true
		story.archive_terminal_activated_day = int(state.day)
		story.set_flag("archive_terminal_active", true)
		story.set_flag("archive_map_transmitted", true)
		if report != null:
			report.add_entry("Terminal Zalanego Archiwum uruchomiony. Mapa Wspólnej Linii została przesłana do Przystani.")
	if dive_result.activated_fixed_devices.has(R3_DIAGNOSTIC_DEVICE_ID) and story.archive_terminal_active and not story.r3_diagnosed:
		story.r3_diagnosed = true
		story.r3_diagnosed_day = int(state.day)
		story.set_flag("r3_diagnosed", true)
		if report != null:
			report.add_entry("Diagnostyka R-3 zakończona. Warsztat otrzymał parametry Regulatora R-3.")
	if dive_result.activated_fixed_devices.has(R3_GENERATOR_DEVICE_ID) and story.r3_regulator_ready and not story.r3_generator_active:
		story.r3_generator_active = true
		story.r3_generator_activated_day = int(state.day)
		story.set_flag("r3_generator_active", true)
		if report != null:
			report.add_entry("Generator R-3 uruchomiony. Zasilanie Wspólnej Linii zostało ustabilizowane.")
	if dive_result.activated_fixed_devices.has(C4_SWITCHBOARD_DEVICE_ID) and story.r3_generator_active and not story.c4_switchboard_active:
		story.c4_switchboard_active = true
		story.c4_switchboard_activated_day = int(state.day)
		story.set_flag("c4_switchboard_active", true)
		if report != null:
			report.add_entry("Rozdzielnia C-4 uruchomiona. Podstawowe sterowanie Wspólną Linią jest gotowe.")
	if dive_result.activated_fixed_devices.has(COMMON_LINE_SPLITTER_DEVICE_ID) and story.c4_switchboard_active and story.common_line_splitter_ready and not story.common_line_splitter_installed:
		story.common_line_splitter_installed = true
		story.common_line_splitter_installed_day = int(state.day)
		story.set_flag("common_line_splitter_installed", true)
		if report != null:
			report.add_entry("Rozdzielacz zamontowany przy C-4. Wspólna Linia jest gotowa do dalszej rozbudowy.")

	return recovered

func act_display_name(state) -> String:
	if state == null or state.story_flags == null:
		return "Wspólna Linia"
	if state.story_flags.final_chronicle_continued:
		return "Kronika Przystani"
	if state.story_flags.junction_j7_active:
		return "Wspólna Linia — Dług prądu"
	return "Wspólna Linia — Pierwsze zejście"

func objective_text(state) -> String:
	if state == null or state.story_flags == null:
		return "Utrzymaj Przystań przy życiu."
	var story = state.story_flags
	var front_text := "Czarny Front za: %d dni. Doprowadź Integralność Przystani do dokładnie 100%%." % story.black_front_days_remaining if story.black_front_active else ""
	if story.crisis_active:
		var crisis_text := "KRYZYS: odbuduj Nadzieję do %d. Pozostałe pełne dni: %d." % [CRISIS_RECOVERY_HOPE, story.crisis_days_remaining]
		return "%s  %s" % [front_text, crisis_text] if not front_text.is_empty() else crisis_text
	if not story.game_over_reason.is_empty():
		return game_over_title(story.game_over_reason)
	if story.black_front_arrived:
		return "Czarny Front dotarł. Integralność 100% — ostatnia decyzja energetyczna jest gotowa."
	if story.black_front_active:
		if not story.archive_map_transmitted:
			return "%s  Uruchom terminal w Zalanym Archiwum R1-09 i prześlij mapę Wspólnej Linii." % front_text
		if not story.r3_diagnosed:
			return "%s  Dotrzyj do Elektrowni R3-04 i wykonaj diagnostykę Generatora R-3." % front_text
		if not story.r3_regulator_ready:
			return "%s  Wykonaj Regulator R-3 w Warsztacie II: 6 złomu, 3 tkaniny/gumy, 2 części techniczne i 200 punktów pracy." % front_text
		if not story.r3_generator_active:
			return "%s  Wróć do Elektrowni R3-04, zamontuj Regulator R-3 i uruchom generator." % front_text
		if not story.c4_switchboard_active:
			return "%s  Dotrzyj do Serca R4-06 i uruchom awaryjny panel Rozdzielni C-4." % front_text
		if not story.common_line_splitter_ready:
			return "%s  Wykonaj Rozdzielacz Wspólnej Linii w Warsztacie III: 10 złomu, 5 tkaniny/gumy, 4 części techniczne i 400 punktów pracy." % front_text
		if not story.common_line_splitter_installed:
			return "%s  Wróć do Serca R4-06 i zamontuj Rozdzielacz przy Rozdzielni C-4." % front_text
		return "%s  Rozdzielacz działa — utrzymaj 100%% Integralności i rozbudowuj Wspólną Linię." % front_text
	return "Uruchom węzeł J-7 i odbuduj Wspólną Linię."

func resolve_day_outcome(state, report) -> void:
	if state == null or state.story_flags == null:
		return
	var story = state.story_flags
	var alive_count: int = state.get_alive_survivors().size()
	if alive_count <= 0:
		_set_game_over(state, "settlement_lost", report)
		return
	if state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) <= 0:
		_set_game_over(state, "platform_destroyed", report)
		return
	_record_full_integrity_day(state)
	_advance_black_front_countdown(state, report)
	if not story.game_over_reason.is_empty():
		return
	if story.energy_choice_pending:
		state.current_phase = GamePhaseScript.Phase.ENDING
		return

	var hope: int = state.resources.get_amount(ResourceIdsScript.HOPE)
	if story.crisis_active:
		if hope >= CRISIS_RECOVERY_HOPE:
			story.crisis_active = false
			story.crisis_days_remaining = 0
			story.set_flag("leadership_crisis_survived", true)
			if report != null:
				report.add_entry("Przystań odzyskała wspólny cel. Kryzys przywództwa został zażegnany.")
		else:
			story.crisis_days_remaining = maxi(story.crisis_days_remaining - 1, 0)
			if story.crisis_days_remaining <= 0:
				_set_game_over(state, "leadership_collapse", report)
				return
			if report != null:
				report.add_warning("Kryzys trwa. Pozostałe pełne dni na odbudowę Nadziei: %d." % story.crisis_days_remaining)
	elif hope <= 0:
		story.crisis_active = true
		story.crisis_days_remaining = CRISIS_DAYS
		story.crisis_started_day = int(state.day)
		story.set_flag("leadership_crisis_started", true)
		if report != null:
			report.add_warning("Nadzieja spadła do zera. Rozpoczyna się kryzys przywództwa: masz trzy pełne dni, by podnieść ją do 15.")

	if story.crisis_active:
		state.current_phase = GamePhaseScript.Phase.CRISIS
		return
	state.current_phase = GamePhaseScript.Phase.DAY_START_REPORT

func continue_chronicle(state) -> bool:
	if state == null or state.story_flags == null:
		return false
	var story = state.story_flags
	if str(story.final_outcome_id).is_empty() or story.final_chronicle_continued or story.chronicle_summary.is_empty():
		return false
	story.final_chronicle_continued = true
	story.act = StoryProgressStateScript.ACT_EPILOGUE
	story.set_flag("common_line_chronicle_continued", true)
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	var final_morning = ReportStateScript.new()
	final_morning.title = "Kronika Przystani — dzień %d" % state.day
	final_morning.day = state.day
	final_morning.add_entry("Czarny Front minął. Przystań kontynuuje na tym samym zapisie, zachowując ludzi, świat i skutki wyboru energii.")
	if story.north_platform_survived:
		final_morning.add_entry("Platforma Północna przetrwała i pozostaje osiągalna przez radio.")
	else:
		final_morning.add_warning("Częstotliwość Platformy Północnej pozostaje martwa.")
	state.last_morning_report = final_morning
	state.begin_new_day_plan()
	return true

func energy_configuration_options(state) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for configuration_id in [ENERGY_HARBOR, ENERGY_NORTH, ENERGY_COMMON_LINE]:
		var blocker := energy_configuration_blocker(state, configuration_id)
		options.append({
			"id": configuration_id,
			"title": energy_configuration_title(configuration_id),
			"description": energy_configuration_description(configuration_id),
			"blocker": blocker,
			"available": blocker.is_empty(),
		})
	return options

func energy_configuration_blocker(state, configuration_id: String) -> String:
	if state == null or state.story_flags == null:
		return "Brak aktywnego stanu kampanii."
	var story = state.story_flags
	if not story.energy_choice_pending or not story.black_front_arrived or state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) != 100:
		return "Ostatnia decyzja energetyczna nie jest jeszcze dostępna."
	match configuration_id:
		ENERGY_HARBOR:
			return ""
		ENERGY_NORTH:
			if not story.r3_generator_active or not story.c4_switchboard_active:
				return "Wymaga działającego Generatora R-3 i aktywnej Rozdzielni C-4."
			return ""
		ENERGY_COMMON_LINE:
			if not story.r3_generator_active or not story.c4_switchboard_active or not story.common_line_splitter_installed:
				return "Wymaga R-3, C-4 i zamontowanego Rozdzielacza Wspólnej Linii."
			var community = state.find_building_by_definition("community_house")
			if community == null or not community.is_active() or int(community.level) < 3:
				return "Wymaga Domu Wspólnoty III — Radiostacji."
			for survivor_id in community.assigned_survivor_ids:
				var survivor = state.find_survivor(str(survivor_id))
				if survivor != null and survivor.can_work():
					return ""
			return "Radiostacja wymaga co najmniej jednej zdolnej osoby w obsadzie Domu Wspólnoty."
	return "Nieznana konfiguracja energii."

func choose_energy_configuration(state, configuration_id: String) -> bool:
	if not energy_configuration_blocker(state, configuration_id).is_empty():
		return false
	var story = state.story_flags
	story.energy_choice_pending = false
	story.energy_configuration = configuration_id
	story.final_resolved_day = maxi(int(state.day) - 1, 1)
	match configuration_id:
		ENERGY_HARBOR:
			story.final_outcome_id = OUTCOME_QUIET_AFTER_STORM
			story.north_platform_survived = false
		ENERGY_NORTH:
			story.final_outcome_id = OUTCOME_DEBT_REPAID
			story.north_platform_survived = true
		ENERGY_COMMON_LINE:
			story.final_outcome_id = OUTCOME_LAST_BRIDGE
			story.north_platform_survived = true
	story.final_summary = {
		"day": int(story.final_resolved_day),
		"survivors": state.get_alive_survivors().size(),
		"hope": state.resources.get_amount(ResourceIdsScript.HOPE),
		"platform_integrity": state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY),
		"successful_dives": int(story.successful_dives),
		"diver_deaths": int(story.diver_deaths),
	}
	story.chronicle_summary = _build_common_line_chronicle(state)
	story.set_flag("energy_configuration_%s" % configuration_id, true)
	story.set_flag("common_line_final_resolved", true)
	state.current_phase = GamePhaseScript.Phase.ENDING
	return true

func _record_full_integrity_day(state) -> void:
	var story = state.story_flags
	if state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) != 100:
		return
	if int(story.first_full_integrity_day) == 0:
		story.first_full_integrity_day = int(state.day)
	story.full_integrity_days += 1

func _build_common_line_chronicle(state) -> Dictionary:
	var story = state.story_flags
	var living: Array[String] = []
	var dead: Array[String] = []
	for survivor in state.survivors:
		if survivor == null:
			continue
		if int(survivor.status) == SurvivorStateScript.Status.DEAD:
			dead.append(str(survivor.display_name))
		elif survivor.is_alive():
			living.append(str(survivor.display_name))
	var buildings: Array[Dictionary] = []
	for building in state.buildings:
		if building != null and building.is_active():
			buildings.append({"definition_id": str(building.definition_id), "level": int(building.level)})
	buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.definition_id) < str(b.definition_id))
	var accepted: Array[String] = []
	var rejected: Array[String] = []
	var decisions: Array[String] = []
	for event in state.settlement_event_history:
		if event == null:
			continue
		if not str(event.result_text).is_empty():
			decisions.append("Dzień %d — %s" % [int(event.resolved_day), str(event.result_text)])
		for survivor_id in event.added_survivor_ids:
			var admitted = state.find_survivor(str(survivor_id))
			accepted.append(str(admitted.display_name) if admitted != null else str(survivor_id))
		if str(event.event_id) == "survivors_on_horizon" and event.added_survivor_ids.is_empty():
			rejected.append(str(event.result_text) if not str(event.result_text).is_empty() else "Odrzucono ludzi na horyzoncie")
	var recovered_backpacks := 0
	for backpack in state.underwater_world.delta.lost_backpacks.values():
		if backpack is Dictionary and bool(backpack.get("recovered", false)):
			recovered_backpacks += 1
	var leon_fate := "nierozstrzygnięty"
	for rescue in state.underwater_world.delta.rescued_or_dead_survivors.values():
		if rescue is Dictionary and str(rescue.get("survivor_id", "")) == "leon":
			leon_fate = str(rescue.get("status", leon_fate))
	var resources: Dictionary = {}
	for resource_id in ResourceIdsScript.all():
		resources[resource_id] = state.resources.get_amount(resource_id)
	return {
		"outcome_id": str(story.final_outcome_id),
		"ending_title": energy_configuration_title(str(story.energy_configuration)),
		"black_front_day": int(story.final_resolved_day),
		"first_full_integrity_day": int(story.first_full_integrity_day),
		"integrity_before_storm": 100,
		"integrity_after_storm": 100,
		"full_integrity_days": int(story.full_integrity_days),
		"dives": int(story.successful_dives + story.diver_deaths),
		"safe_returns": int(story.successful_dives),
		"diver_deaths": int(story.diver_deaths),
		"recovered_backpacks": recovered_backpacks,
		"living_survivors": living,
		"dead_survivors": dead,
		"accepted_survivors": accepted,
		"rejected_survivors": rejected,
		"rescued_survivors": int(story.rescued_survivor_count),
		"leon_fate": leon_fate,
		"buildings": buildings,
		"resources": resources,
		"r3_active": bool(story.r3_generator_active),
		"c4_active": bool(story.c4_switchboard_active),
		"splitter_installed": bool(story.common_line_splitter_installed),
		"radio_active": _has_active_radio(state),
		"energy_configuration": str(story.energy_configuration),
		"north_platform_survived": bool(story.north_platform_survived),
		"hope": state.resources.get_amount(ResourceIdsScript.HOPE),
		"important_decisions": decisions,
	}

func _has_active_radio(state) -> bool:
	var community = state.find_building_by_definition("community_house")
	return community != null and community.is_active() and int(community.level) >= 3

func energy_configuration_title(configuration_id: String) -> String:
	match configuration_id:
		ENERGY_HARBOR: return "PRZYSTAŃ"
		ENERGY_NORTH: return "PÓŁNOCNA"
		ENERGY_COMMON_LINE: return "WSPÓLNA LINIA"
	return "NIEZNANA KONFIGURACJA"

func energy_configuration_description(configuration_id: String) -> String:
	match configuration_id:
		ENERGY_HARBOR: return "Skieruj całą energię do Przystani. Pomost 7 przetrwa, lecz pompy Platformy Północnej zamilkną."
		ENERGY_NORTH: return "Skieruj energię do pomp Północnej. Przystań przejdzie przez sztorm bez głównego zasilania."
		ENERGY_COMMON_LINE: return "Podziel obciążenie dzięki Rozdzielaczowi i utrzymaj obie platformy w kontakcie przez Radiostację."
	return ""

func game_over_title(reason: String) -> String:
	match reason:
		"leadership_collapse":
			return "Bunt w Przystani"
		"platform_destroyed":
			return "Przystań pochłonęła woda"
		"settlement_lost":
			return "Nie ocalał nikt"
		"black_front_unprepared":
			return "Czarny Front przełamał Przystań"
	return "Koniec kampanii"

func game_over_description(reason: String) -> String:
	match reason:
		"leadership_collapse":
			return "Trzy dni bez wspólnego celu zakończyły się buntem. Magazyny zostały rozgrabione, a wspólnota rozpadła się na wodzie."
		"platform_destroyed":
			return "Integralność platformy spadła do zera. Ostatnie połączenia puściły i Przystań przestała być miejscem, które można obronić."
		"settlement_lost":
			return "Głód, urazy i głębina zabrały ostatnich mieszkańców. Pozostała tylko pusta platforma."
		"black_front_unprepared":
			return "Front dotarł, zanim Integralność Przystani osiągnęła dokładnie 100%. Konstrukcja nie wytrzymała uderzenia."
	return "Ta kronika dobiegła końca."

func black_front_days_for_profile(profile) -> int:
	if profile == null:
		return BLACK_FRONT_DAYS_STANDARD
	match str(profile.profile_id):
		"easy":
			return BLACK_FRONT_DAYS_EASY
		"hard":
			return BLACK_FRONT_DAYS_HARD
		"custom":
			if float(profile.storm_frequency_multiplier) <= 0.8:
				return BLACK_FRONT_DAYS_EASY
			if float(profile.storm_frequency_multiplier) >= 1.2:
				return BLACK_FRONT_DAYS_HARD
	return BLACK_FRONT_DAYS_STANDARD

func _start_black_front_countdown(state) -> void:
	var story = state.story_flags
	if story.black_front_active or story.black_front_arrived:
		return
	var days := black_front_days_for_profile(state.difficulty_profile)
	story.black_front_active = true
	story.black_front_days_total = days
	story.black_front_days_remaining = days
	story.black_front_started_day = int(state.day)
	story.black_front_last_advanced_day = int(state.day)
	story.set_flag("black_front_countdown_started", true)

func _advance_black_front_countdown(state, report) -> void:
	var story = state.story_flags
	if not story.black_front_active or int(state.day) <= story.black_front_last_advanced_day:
		return
	story.black_front_last_advanced_day = int(state.day)
	story.black_front_days_remaining = maxi(story.black_front_days_remaining - 1, 0)
	if story.black_front_days_remaining > 0:
		if report != null:
			report.add_warning("Czarny Front zbliża się. Pozostało dni: %d." % story.black_front_days_remaining)
		return
	story.black_front_active = false
	story.black_front_arrived = true
	story.set_flag("black_front_arrived", true)
	if state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) != 100:
		_set_game_over(state, "black_front_unprepared", report)
		return
	story.set_flag("black_front_final_ready", true)
	story.energy_choice_pending = true
	state.current_phase = GamePhaseScript.Phase.ENDING
	if report != null:
		report.add_entry("Czarny Front dotarł. Przystań ma 100% Integralności i jest gotowa na ostatnią decyzję energetyczną.")

func _set_game_over(state, reason: String, report) -> void:
	var story = state.story_flags
	story.game_over_reason = reason
	story.game_over_day = int(state.day)
	story.crisis_active = false
	story.crisis_days_remaining = 0
	state.current_phase = GamePhaseScript.Phase.GAME_OVER
	if report != null:
		report.add_warning("KONIEC KAMPANII: %s." % game_over_title(reason))
