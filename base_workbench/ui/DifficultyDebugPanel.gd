class_name DifficultyDebugPanel
extends Control

signal closed

const WeatherSystemScript := preload("res://scripts/campaign/WeatherSystem.gd")

var _built: bool = false
var _content: RichTextLabel


func build() -> void:
	if _built:
		return
	_built = true
	name = "DifficultyDebugPanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 130
	visible = false

	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.012, 0.016, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0e191df7")
	style.border_color = Color("65a9a6")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 22)
	panel_margin.add_theme_constant_override("margin_top", 18)
	panel_margin.add_theme_constant_override("margin_right", 22)
	panel_margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(panel_margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel_margin.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "DIFFICULTY TELEMETRY  •  F10"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color("e7c987"))
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "ZAMKNIJ"
	close_button.pressed.connect(dismiss)
	header.add_child(close_button)

	_content = RichTextLabel.new()
	_content.name = "DifficultyDebugContent"
	_content.bbcode_enabled = true
	_content.fit_content = false
	_content.custom_minimum_size = Vector2(560, 520)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_font_size_override("normal_font_size", 14)
	_content.add_theme_color_override("default_color", Color("c8d5d3"))
	layout.add_child(_content)

	var note := Label.new()
	note.text = "Panel jest tylko diagnostyczny: pokazuje zamrożoną migawkę dnia i nie zmienia kampanii."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color("799492"))
	layout.add_child(note)


func present(state) -> void:
	build()
	if state == null:
		dismiss()
		return
	_content.text = _telemetry_text(state)
	visible = true


func dismiss() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func toggle(state) -> void:
	if visible:
		dismiss()
	else:
		present(state)


func _telemetry_text(state) -> String:
	var alive: Array = state.get_alive_survivors() if state.has_method("get_alive_survivors") else []
	var hunger_total := 0.0
	var max_hunger := 0
	var healthy_workers := 0
	for survivor in alive:
		hunger_total += float(survivor.hunger)
		max_hunger = maxi(max_hunger, int(survivor.hunger))
		if survivor.can_work():
			healthy_workers += 1
	var average_hunger := hunger_total / float(alive.size()) if not alive.is_empty() else 0.0
	var profile = state.difficulty_profile
	var pressure = state.get("pressure_state")
	var profile_label := str(profile.profile_name) if profile != null else "brak"
	var profile_id := str(profile.get("profile_id")) if profile != null and profile.get("profile_id") != null else "unknown"
	var signature := str(profile.get("configuration_signature")) if profile != null and profile.get("configuration_signature") != null else "brak"
	var recent_dives: Array = pressure.get("recent_dive_outcomes") if pressure != null and pressure.get("recent_dive_outcomes") is Array else []
	var reasons: Array = pressure.get("reason_codes") if pressure != null and pressure.get("reason_codes") is Array else []
	var critical: Array = pressure.get("critical_gates") if pressure != null and pressure.get("critical_gates") is Array else []
	var active_tags: Array = pressure.get("active_pressure_tags") if pressure != null and pressure.get("active_pressure_tags") is Array else []
	var recovery_roles: Array = pressure.get("recovery_roles") if pressure != null and pressure.get("recovery_roles") is Array else []
	var blocked_impacts: Array = pressure.get("blocked_impact_tags") if pressure != null and pressure.get("blocked_impact_tags") is Array else []
	var preferred_impacts: Array = pressure.get("preferred_impact_tags") if pressure != null and pressure.get("preferred_impact_tags") is Array else []
	var pressure_summary := str(pressure.debug_summary) if pressure != null else "brak migawki"
	var committed_morning := "brak migawki"
	if pressure != null:
		committed_morning = "spokojny poranek" if bool(pressure.quiet_morning) else (
			"%s • %s • poziom %d • koszt %.2f" % [pressure.committed_event_id, pressure.committed_event_tone, int(pressure.committed_event_severity), float(pressure.spent_pressure_budget)]
			if not str(pressure.committed_event_id).is_empty()
			else "jeszcze nie wybrano"
		)
	var weather_name := str(state.weather.display_name()) if state.weather != null and state.weather.has_method("display_name") else "brak"
	var next_storm := _days_until_storm(state)
	var lines: Array[String] = [
		"[color=#e7c987][b]Kampania[/b][/color]",
		"Dzień: %d    Seed: %d    Profil: %s (%s)" % [int(state.day), int(state.seed), profile_label, profile_id],
		"Podpis konfiguracji: %s" % signature,
		"",
		"[color=#82bab7][b]Osada[/b][/color]",
		"Mieszkańcy: %d    Zdolni do pracy: %d" % [alive.size(), healthy_workers],
		"Jedzenie: %.2f dnia    Śr. głód: %.1f    Maks. głód: %d" % [float(state.get_food_days_left()), average_hunger, max_hunger],
		"Nadzieja: %d    Integralność: %d%%" % [int(state.resources.get_amount("hope")), int(state.resources.get_amount("platform_integrity"))],
		"",
		"[color=#82bab7][b]Migawka presji dnia[/b][/color]",
		pressure_summary,
		"Wynik selekcji poranka: %s" % committed_morning,
		"Powody: %s" % (", ".join(reasons) if not reasons.is_empty() else "brak"),
		"Bramki krytyczne: %s" % (", ".join(critical) if not critical.is_empty() else "brak"),
		"Aktywne tagi wykluczające: %s" % (", ".join(active_tags) if not active_tags.is_empty() else "brak"),
		"Role regeneracji: %s" % (", ".join(recovery_roles) if not recovery_roles.is_empty() else "brak"),
		"Blokowane skutki: %s" % (", ".join(blocked_impacts) if not blocked_impacts.is_empty() else "brak"),
		"Preferowane skutki: %s" % (", ".join(preferred_impacts) if not preferred_impacts.is_empty() else "brak"),
		"Ostatnie wyprawy: %s" % (", ".join(recent_dives) if not recent_dives.is_empty() else "brak danych"),
		"",
		"[color=#82bab7][b]Zamrożone reguły[/b][/color]",
		"Łup ×%.2f    Tlen ×%.2f    Budowa ×%.2f    Naprawy ×%.2f" % [
			float(profile.loot_density_multiplier) if profile != null else 1.0,
			float(profile.oxygen_use_multiplier) if profile != null else 1.0,
			float(profile.build_cost_multiplier) if profile != null else 1.0,
			float(profile.repair_cost_multiplier) if profile != null else 1.0,
		],
		"Nurkowanie: kombinezon ×%.2f  zimno ×%.2f  prąd ×%.2f  hałas ×%.2f  zagrożenia ×%.2f  plecak ×%.2f" % [
			float(profile.suit_damage_multiplier) if profile != null else 1.0,
			float(profile.cold_rate_multiplier) if profile != null else 1.0,
			float(profile.current_strength_multiplier) if profile != null else 1.0,
			float(profile.noise_range_multiplier) if profile != null else 1.0,
			float(profile.threat_aggression_multiplier) if profile != null else 1.0,
			float(profile.backpack_weight_multiplier) if profile != null else 1.0,
		],
		"Społeczność: strata Nadziei ×%.2f  zysk ×%.2f  leczenie ×%.2f  ratunek operatora %d%%" % [
			float(profile.hope_loss_multiplier) if profile != null else 1.0,
			float(profile.hope_gain_multiplier) if profile != null else 1.0,
			float(profile.recovery_speed_multiplier) if profile != null else 1.0,
			int(round(float(profile.operator_rescue_chance) * 100.0)) if profile != null else 50,
		],
		"Poranek: cisza %.0f%%  pomoc ×%.2f  hardship ×%.2f" % [
			float(profile.quiet_day_weight) if profile != null else 45.0,
			float(profile.relief_event_weight_multiplier) if profile != null else 1.0,
			float(profile.hardship_event_weight_multiplier) if profile != null else 1.0,
		],
		"Morze: %s    Następny sztorm: %s" % [weather_name, "%d dni" % next_storm if next_storm >= 0 else "> 30 dni"],
	]
	return "\n".join(lines)


func _days_until_storm(state) -> int:
	if state == null:
		return -1
	var frequency := float(state.difficulty_profile.storm_frequency_multiplier) if state.difficulty_profile != null else 1.0
	var weather_system = WeatherSystemScript.new()
	for offset in range(0, 31):
		var forecast = weather_system.build_weather(int(state.seed), int(state.day) + offset, frequency)
		if forecast != null and forecast.has_method("is_storm") and forecast.is_storm():
			return offset
	return -1
