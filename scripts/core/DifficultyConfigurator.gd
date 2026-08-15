class_name DifficultyConfigurator
extends ConfirmationDialog

signal profile_configured(profile: Resource)

const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const DifficultyMathScript := preload("res://scripts/core/DifficultyMath.gd")

const AXES := [
	{"id": "starting_resources", "label": "Zapasy startowe", "hint": "Jedzenie, deski i złom dostępne w pierwszym dniu."},
	{"id": "food_consumption", "label": "Zużycie jedzenia", "hint": "Dzienny koszt wyżywienia jednej osoby."},
	{"id": "economy", "label": "Budowa i łup", "hint": "Koszty budowy, napraw oraz ilość zwykłego łupu."},
	{"id": "society", "label": "Społeczność", "hint": "Skutki Nadziei, tempo leczenia i dzienna presja chorób."},
	{"id": "diving", "label": "Warunki nurkowania", "hint": "Tlen, kombinezon, zimno, prądy, hałas i agresja zagrożeń."},
	{"id": "weather", "label": "Pogoda", "hint": "Częstotliwość i siła sztormów."},
	{"id": "events", "label": "Wydarzenia poranka", "hint": "Częstość spokojnych dni oraz proporcja pomocy do utrudnień."},
	{"id": "forgiveness", "label": "Ratowanie błędów", "hint": "Szansa awaryjnego wyciągnięcia nurka przez operatora."},
]

var _built: bool = false
var _pickers: Dictionary = {}
var _summary: RichTextLabel
var _validation_label: Label
var _axes: Dictionary = {}


func _ready() -> void:
	_ensure_built()


func open_with_axes(axes: Dictionary = {}) -> void:
	_ensure_built()
	_axes = _normalized_axes(axes)
	_sync_pickers()
	_refresh_summary()
	popup_centered(Vector2i(860, 690))


func configured_axes() -> Dictionary:
	return _axes.duplicate(true)


func build_configured_profile():
	return DifficultyProfileScript.build_custom_profile(_axes)


static func default_axes() -> Dictionary:
	var result: Dictionary = {}
	for axis in DifficultyProfileScript.custom_axis_ids():
		result[str(axis)] = 0
	return result


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	title = "Niestandardowy poziom trudności"
	dialog_text = ""
	ok_button_text = "ZAPISZ USTAWIENIA"
	cancel_button_text = "ANULUJ"
	min_size = Vector2i(780, 620)
	confirmed.connect(_on_confirmed)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 20
	margin.offset_top = 12
	margin.offset_right = -20
	margin.offset_bottom = -58
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var intro := Label.new()
	intro.text = "Wybierz charakter wyzwania. Ustawienia są zamrażane na całą kampanię i nie zmieniają się po porażce ani wczytaniu zapisu."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color("b7c9c7"))
	root.add_child(intro)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 22)
	root.add_child(columns)

	var axes_scroll := ScrollContainer.new()
	axes_scroll.custom_minimum_size = Vector2(430, 0)
	axes_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	axes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(axes_scroll)
	var axes_layout := VBoxContainer.new()
	axes_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	axes_layout.add_theme_constant_override("separation", 9)
	axes_scroll.add_child(axes_layout)

	for axis in AXES:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		axes_layout.add_child(row)
		var header := HBoxContainer.new()
		row.add_child(header)
		var label := Label.new()
		label.text = str(axis.label)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color("e5d0a1"))
		header.add_child(label)
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(170, 36)
		picker.add_item("Łagodniejsze")
		picker.set_item_metadata(0, -1)
		picker.add_item("Standardowe")
		picker.set_item_metadata(1, 0)
		picker.add_item("Surowsze")
		picker.set_item_metadata(2, 1)
		picker.item_selected.connect(_on_axis_selected.bind(str(axis.id)))
		header.add_child(picker)
		_pickers[str(axis.id)] = picker
		var hint := Label.new()
		hint.text = str(axis.hint)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color("718d8b"))
		row.add_child(hint)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(340, 0)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0c171be8")
	style.border_color = Color("365d60")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	preview_panel.add_theme_stylebox_override("panel", style)
	columns.add_child(preview_panel)
	var preview_margin := MarginContainer.new()
	preview_margin.add_theme_constant_override("margin_left", 16)
	preview_margin.add_theme_constant_override("margin_top", 14)
	preview_margin.add_theme_constant_override("margin_right", 16)
	preview_margin.add_theme_constant_override("margin_bottom", 14)
	preview_panel.add_child(preview_margin)
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = false
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary.add_theme_font_size_override("normal_font_size", 13)
	preview_margin.add_child(_summary)

	_validation_label = Label.new()
	_validation_label.visible = false
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.add_theme_color_override("font_color", Color("e98f78"))
	root.add_child(_validation_label)

	_axes = default_axes()
	_sync_pickers()
	_refresh_summary()


func _normalized_axes(raw_axes: Dictionary) -> Dictionary:
	var result := default_axes()
	for axis_id in result.keys():
		result[axis_id] = clampi(int(raw_axes.get(axis_id, 0)), -1, 1)
	return result


func _sync_pickers() -> void:
	for axis_id in _pickers.keys():
		var picker: OptionButton = _pickers[axis_id]
		var wanted := int(_axes.get(axis_id, 0))
		for index in range(picker.item_count):
			if int(picker.get_item_metadata(index)) == wanted:
				picker.select(index)
				break


func _on_axis_selected(index: int, axis_id: String) -> void:
	var picker: OptionButton = _pickers.get(axis_id)
	if picker == null:
		return
	_axes[axis_id] = int(picker.get_item_metadata(index))
	_refresh_summary()


func _refresh_summary() -> void:
	if _summary == null:
		return
	var errors: PackedStringArray = DifficultyProfileScript.custom_axis_validation_errors(_axes)
	var profile = DifficultyProfileScript.build_custom_profile(_axes) if errors.is_empty() else null
	_validation_label.visible = profile == null
	_validation_label.text = "Niepoprawna konfiguracja: %s" % "; ".join(errors) if profile == null else ""
	get_ok_button().disabled = profile == null
	if profile == null:
		_summary.text = "[color=#e98f78]Nie można wyliczyć podglądu tej konfiguracji.[/color]"
		return
	var daily_food := int(profile.food_per_adult) * 3
	var food_days := float(profile.starting_food) / float(maxi(daily_food, 1))
	var station_cost: Dictionary = DifficultyMathScript.scale_cost({"planks": 6, "scrap": 4, "fabric_rubber": 2}, float(profile.build_cost_multiplier))
	_summary.text = "\n".join([
		"[color=#e7c987][b]DOKŁADNY PODGLĄD[/b][/color]",
		"",
		"[b]Start kampanii[/b]",
		"Jedzenie: %d (%.1f dnia dla 3 osób)" % [int(profile.starting_food), food_days],
		"Deski: %d    Złom: %d" % [int(profile.starting_planks), int(profile.starting_scrap)],
		"Racja jednej osoby: %d / dzień" % int(profile.food_per_adult),
		"",
		"[b]Przykład kosztu[/b]",
		"Stacja Nurkowa I: %d desek, %d złomu, %d tkanin" % [int(station_cost.planks), int(station_cost.scrap), int(station_cost.fabric_rubber)],
		"Budowa ×%.2f    Naprawy ×%.2f" % [float(profile.build_cost_multiplier), float(profile.repair_cost_multiplier)],
		"",
		"[b]Wyprawa[/b]",
		"Zwykły łup ×%.2f    Zużycie tlenu ×%.2f" % [float(profile.loot_density_multiplier), float(profile.oxygen_use_multiplier)],
		"Kombinezon ×%.2f    Zimno ×%.2f    Zagrożenia ×%.2f" % [float(profile.suit_damage_multiplier), float(profile.cold_rate_multiplier), float(profile.threat_aggression_multiplier)],
		"Prądy ×%.2f    Hałas ×%.2f    Ciężar plecaka ×%.2f" % [float(profile.current_strength_multiplier), float(profile.noise_range_multiplier), float(profile.backpack_weight_multiplier)],
		"Szansa operatora: %d%%" % int(round(float(profile.operator_rescue_chance) * 100.0)),
		"",
		"[b]Osada i morze[/b]",
		"Wzrost Nadziei ×%.2f    Strata ×%.2f    Leczenie ×%.2f" % [float(profile.hope_gain_multiplier), float(profile.hope_loss_multiplier), float(profile.recovery_speed_multiplier)],
		"Presja chorób: %+d pkt / dzień" % int(profile.disease_pressure_modifier),
		"Sztormy ×%.2f    Obrażenia ×%.2f" % [float(profile.storm_frequency_multiplier), float(profile.storm_damage_multiplier)],
		"Bazowa cisza (przed potrzebami i gwarancjami): %.0f%%" % float(profile.quiet_day_weight),
		"Wagi kart: pomoc ×%.2f    utrudnienia ×%.2f" % [float(profile.relief_event_weight_multiplier), float(profile.hardship_event_weight_multiplier)],
	])


func _on_confirmed() -> void:
	var profile = build_configured_profile()
	if profile != null:
		profile_configured.emit(profile)
