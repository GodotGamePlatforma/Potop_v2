class_name DiveHudDock
extends PanelContainer

const DiverHudPortraitScript := preload("res://scripts/diving/DiverHudPortrait.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const ProfessionTalentSystemScript := preload("res://scripts/survivors/ProfessionTalentSystem.gd")

var oxygen_bar: ProgressBar
var oxygen_label: Label
var oxygen_fill_style: StyleBoxFlat
var health_bar: ProgressBar
var health_label: Label
var health_fill_style: StyleBoxFlat
var diver_name_label: Label
var diver_meta_label: Label
var experience_label: Label
var portrait: DiverHudPortrait
var suit_label: Label
var time_label: Label
var oxygen_tank_label: Label
var light_label: Label
var inventory_summary_label: Label
var inventory_slots: Array[PanelContainer] = []
var inventory_labels: Array[Label] = []
var vitals_cluster: PanelContainer
var inventory_cluster: PanelContainer
var context_cluster: PanelContainer

var _layout_root: Control
var _inventory_row: HBoxContainer
var _identity_detail := ""
var _oxygen_value_text := "—"
var _tank_badge := ""
var _time_detail := ""
var _light_detail := ""
var _tank_detail := ""
var _is_built := false
var _profession_talent_system = ProfessionTalentSystemScript.new()

func build() -> void:
	if _is_built:
		return
	_is_built = true
	name = "DiverStatusDock"
	# The dock spans almost the entire bottom edge, but only its visible controls
	# should participate in pointer input. Transparent gaps stay click-through.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dock_style := StyleBoxFlat.new()
	dock_style.bg_color = Color.TRANSPARENT
	dock_style.border_color = Color.TRANSPARENT
	dock_style.set_border_width_all(0)
	add_theme_stylebox_override("panel", dock_style)
	_layout_root = Control.new()
	_layout_root.name = "FloatingHudGroups"
	_layout_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layout_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layout_root)

	_build_vitals_cluster()
	_build_inventory_cluster()
	_build_context_cluster()

func update_identity(setup, resident = null) -> void:
	if setup == null:
		return
	var has_snapshot: bool = not setup.diver_display_name.is_empty()
	var diver_name: String = setup.diver_display_name if has_snapshot else resident.display_name if resident != null else setup.diver_id.capitalize()
	var profession: String = setup.diver_profession if has_snapshot else resident.profession if resident != null else "nurek"
	var secondary_profession: String = setup.diver_secondary_profession if has_snapshot else resident.secondary_profession if resident != null else ""
	var level: int = setup.diver_level if has_snapshot else resident.level if resident != null else 1
	var experience: int = setup.diver_experience if has_snapshot else resident.experience if resident != null else 0
	var experience_needed: int = setup.diver_experience_to_next_level if has_snapshot else resident.experience_to_next_level() if resident != null else 100
	var portrait_id: String = setup.diver_portrait_id if has_snapshot else resident.portrait_id if resident != null else setup.diver_id
	diver_name_label.text = diver_name.to_upper()
	diver_meta_label.text = "POZ. %d" % level
	var profession_summary := profession.to_upper()
	if not secondary_profession.is_empty():
		profession_summary += " + " + secondary_profession.to_upper()
	experience_label.text = "%s  •  PD %d / %d" % [profession_summary, experience, experience_needed]
	_identity_detail = "%s\n%s" % [diver_name, experience_label.text]
	var talent_holder = setup if has_snapshot or resident == null else resident
	var talent_detail := _profession_talent_detail(talent_holder, [profession, secondary_profession])
	if not talent_detail.is_empty():
		_identity_detail += "\nTALENTY ZAWODOWE\n" + talent_detail
	diver_name_label.tooltip_text = _identity_detail
	diver_meta_label.tooltip_text = _identity_detail
	experience_label.tooltip_text = _identity_detail
	portrait.configure(portrait_id if not portrait_id.is_empty() else setup.diver_id, diver_name)
	portrait.tooltip_text = _identity_detail
	_refresh_vitals_tooltip()


func _profession_talent_detail(holder, profession_ids: Array) -> String:
	var lines: Array[String] = []
	for raw_profession_id in profession_ids:
		var profession_id := str(raw_profession_id)
		if profession_id.is_empty():
			continue
		var talent_id := ProfessionTalentSystemScript.selected_talent_id(holder, profession_id)
		var definition = _profession_talent_system.get_definition(talent_id)
		if definition != null:
			lines.append("%s — %s" % [str(definition.display_name), str(definition.description)])
	return "\n".join(lines)

func update_vitals(session) -> void:
	if session == null:
		return
	oxygen_bar.max_value = session.oxygen_capacity
	oxygen_bar.value = session.oxygen_left
	oxygen_fill_style.bg_color = Color("dc554b") if session.oxygen_ratio() <= 0.25 else Color("d7ad4f") if session.oxygen_ratio() <= 0.5 else Color("51c8cf")
	_oxygen_value_text = "%.0f/%.0f" % [session.oxygen_left, session.oxygen_capacity]
	_refresh_oxygen_label()
	health_bar.max_value = session.health_capacity
	health_bar.value = session.health
	health_fill_style.bg_color = Color("dc554b") if session.health_ratio() <= 0.3 else Color("ba4d48")
	health_label.text = "%d/%d" % [session.health, session.health_capacity]

	suit_label.text = "KOMB. %d%%" % session.suit_condition
	suit_label.add_theme_color_override("font_color", Color("ff7464") if session.suit_condition <= 35 else Color("edc56c") if session.suit_condition < 100 else Color("d5ddd9"))
	var hazards: Array[String] = []
	if session.cold_exposure >= 1.0:
		hazards.append("CHŁÓD %.0f%%" % session.cold_exposure)
	if session.noise_level >= 1.0:
		hazards.append("HAŁAS %.0f%%" % session.noise_level)
	time_label.text = "  •  ".join(hazards)
	time_label.visible = not hazards.is_empty()
	time_label.add_theme_color_override("font_color", Color("79d4d8") if session.cold_exposure < 50.0 else Color("efb85f"))
	_update_context_cluster_height(not hazards.is_empty())
	_time_detail = "CZAS %02d:%02d\nKombinezon %d%%  •  Chłód %.0f%%  •  Hałas %.0f%%" % [
		int(session.elapsed_time) / 60,
		int(session.elapsed_time) % 60,
		session.suit_condition,
		session.cold_exposure,
		session.noise_level,
	]
	_refresh_vitals_tooltip()
	_refresh_context_tooltip()

func update_light(light_definition, is_enabled: bool = true) -> void:
	var toggle_prompt := InputPromptScript.action_text(&"dive_light_toggle")
	if light_definition != null:
		var short_name: String = str(light_definition.display_name).to_upper().replace("LATARNIA NURKOWA ", "LATARNIA ")
		var state_label := "WŁ." if is_enabled else "WYŁ."
		light_label.text = "%s • %s [%s]" % [short_name, state_label, toggle_prompt]
		_light_detail = "%s\nStan: %s\nZasięg światła: %.0f\n%s: %s" % [
			light_definition.display_name,
			"włączona" if is_enabled else "wyłączona",
			light_definition.light_outer_radius,
			toggle_prompt,
			"wyłącz" if is_enabled else "włącz",
		]
	else:
		light_label.text = "BRAK LATARNI [%s: —]" % toggle_prompt
		_light_detail = "Brak wyposażonej latarni\n%s nie uruchomi światła" % toggle_prompt
	light_label.add_theme_color_override("font_color", Color("efc768") if light_definition != null and is_enabled else Color("91a9ad") if light_definition != null else Color("ff7464"))
	_refresh_context_tooltip()

func update_oxygen_tank(tank_definition) -> void:
	if tank_definition != null:
		oxygen_tank_label.text = "%s  •  %.0f tlenu" % [tank_definition.display_name.to_upper(), tank_definition.oxygen_capacity]
		_tank_detail = oxygen_tank_label.text
		_tank_badge = "B-%s" % _roman_tier(int(tank_definition.tier))
	else:
		oxygen_tank_label.text = "BRAK SPRAWNEJ BUTLI"
		_tank_detail = oxygen_tank_label.text
		_tank_badge = ""
	_refresh_oxygen_label()
	_refresh_context_tooltip()

func update_inventory(session) -> void:
	if session == null:
		return
	_ensure_inventory_slots(session.backpack_capacity)
	var inventory_prompt := InputPromptScript.action_text(&"dive_inventory")
	inventory_summary_label.text = "PLECAK %d/%d  •  WAGA %s/%s kg  •  [%s]" % [
		session.slots_used(),
		session.backpack_capacity,
		_mass_text(session.get_carried_weight()),
		_mass_text(session.carry_capacity),
		inventory_prompt,
	]
	inventory_summary_label.tooltip_text = "%s — otwórz plecak" % inventory_prompt
	for index in range(inventory_labels.size()):
		var label := inventory_labels[index]
		var slot := inventory_slots[index]
		if index < session.carried_item_order.size():
			var resource_id: String = session.carried_item_order[index]
			var amount := int(session.carried_items[resource_id])
			var stack_weight: float = amount * session.get_unit_weight(resource_id)
			label.text = "%s\nx%d" % [_short_resource_name(resource_id), amount]
			slot.modulate = Color("f1cf78")
			slot.tooltip_text = "%02d  %s\n%d szt.  •  %s kg" % [index + 1, ResourceIdsScript.display_name(resource_id), amount, _mass_text(stack_weight)]
		else:
			label.text = "%02d" % (index + 1)
			slot.modulate = Color(0.62, 0.76, 0.78, 0.34)
			slot.tooltip_text = "Slot %02d — pusty" % (index + 1)

func _build_vitals_cluster() -> void:
	vitals_cluster = _make_panel(Color("071318b8"), Color.TRANSPARENT, 0)
	vitals_cluster.name = "VitalsCluster"
	vitals_cluster.anchor_top = 0.0
	vitals_cluster.anchor_bottom = 1.0
	vitals_cluster.offset_right = 302.0
	vitals_cluster.mouse_filter = Control.MOUSE_FILTER_PASS
	_layout_root.add_child(vitals_cluster)
	var margin := _margin_content(vitals_cluster, 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var portrait_frame := _make_panel(Color("0a171c"), Color("b9954d"), 1)
	portrait_frame.custom_minimum_size = Vector2(46, 58)
	row.add_child(portrait_frame)
	portrait = DiverHudPortraitScript.new()
	portrait.custom_minimum_size = Vector2(46, 58)
	portrait_frame.add_child(portrait)

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 1)
	row.add_child(identity)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	identity.add_child(name_row)
	diver_name_label = Label.new()
	diver_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diver_name_label.add_theme_font_size_override("font_size", 14)
	diver_name_label.add_theme_color_override("font_color", Color("f0e8d7"))
	diver_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(diver_name_label)
	diver_meta_label = Label.new()
	diver_meta_label.add_theme_font_size_override("font_size", 11)
	diver_meta_label.add_theme_color_override("font_color", Color("e6bd68"))
	name_row.add_child(diver_meta_label)
	experience_label = Label.new()
	experience_label.visible = false
	identity.add_child(experience_label)

	var health_header := _stat_header(identity, "❤  ZDROWIE", Color("d4867e"))
	health_label = health_header.get_child(1) as Label
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(0, 5)
	health_bar.show_percentage = false
	health_fill_style = _configure_progress_bar(health_bar, Color("ba4d48"), 1)
	identity.add_child(health_bar)
	var oxygen_header := _stat_header(identity, "O₂  TLEN", Color("70d0d5"))
	oxygen_label = oxygen_header.get_child(1) as Label
	oxygen_bar = ProgressBar.new()
	oxygen_bar.custom_minimum_size = Vector2(0, 8)
	oxygen_bar.show_percentage = false
	oxygen_fill_style = _configure_progress_bar(oxygen_bar, Color("51c8cf"), 1)
	identity.add_child(oxygen_bar)

func _build_inventory_cluster() -> void:
	inventory_cluster = _make_panel(Color.TRANSPARENT, Color.TRANSPARENT, 0)
	inventory_cluster.name = "InventoryCluster"
	inventory_cluster.anchor_left = 0.5
	inventory_cluster.anchor_top = 0.0
	inventory_cluster.anchor_right = 0.5
	inventory_cluster.anchor_bottom = 1.0
	inventory_cluster.offset_left = -169.0
	inventory_cluster.offset_right = 169.0
	inventory_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_root.add_child(inventory_cluster)
	var inventory_column := VBoxContainer.new()
	inventory_column.name = "InventoryBar"
	inventory_column.add_theme_constant_override("separation", 2)
	inventory_cluster.add_child(inventory_column)
	inventory_summary_label = Label.new()
	inventory_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inventory_summary_label.add_theme_font_size_override("font_size", 11)
	inventory_summary_label.add_theme_color_override("font_color", Color("c9d4d1"))
	inventory_summary_label.mouse_filter = Control.MOUSE_FILTER_STOP
	inventory_column.add_child(inventory_summary_label)
	var inventory_scroll := ScrollContainer.new()
	inventory_scroll.name = "InventoryScroll"
	inventory_scroll.custom_minimum_size = Vector2(0, 43)
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inventory_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	inventory_column.add_child(inventory_scroll)
	_inventory_row = HBoxContainer.new()
	_inventory_row.add_theme_constant_override("separation", 4)
	inventory_scroll.add_child(_inventory_row)
	_ensure_inventory_slots(6)

func _build_context_cluster() -> void:
	context_cluster = _make_panel(Color("071318b8"), Color("2f4b5180"), 1)
	context_cluster.name = "ContextCluster"
	context_cluster.anchor_left = 1.0
	context_cluster.anchor_top = 1.0
	context_cluster.anchor_right = 1.0
	context_cluster.anchor_bottom = 1.0
	context_cluster.offset_left = -270.0
	context_cluster.offset_top = -46.0
	context_cluster.mouse_filter = Control.MOUSE_FILTER_PASS
	_layout_root.add_child(context_cluster)
	var margin := _margin_content(context_cluster, 7)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)
	var primary := HBoxContainer.new()
	primary.alignment = BoxContainer.ALIGNMENT_CENTER
	primary.add_theme_constant_override("separation", 8)
	column.add_child(primary)
	suit_label = Label.new()
	suit_label.add_theme_font_size_override("font_size", 11)
	primary.add_child(suit_label)
	var divider := VSeparator.new()
	divider.custom_minimum_size.x = 1
	primary.add_child(divider)
	light_label = Label.new()
	light_label.add_theme_font_size_override("font_size", 11)
	primary.add_child(light_label)
	time_label = Label.new()
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 10)
	time_label.visible = false
	column.add_child(time_label)
	oxygen_tank_label = Label.new()
	oxygen_tank_label.visible = false
	column.add_child(oxygen_tank_label)

func _stat_header(parent: VBoxContainer, title_text: String, title_color: Color) -> HBoxContainer:
	var header := HBoxContainer.new()
	parent.add_child(header)
	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", title_color)
	header.add_child(title)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 10)
	value.add_theme_color_override("font_color", Color("e5efec"))
	header.add_child(value)
	return header

func _ensure_inventory_slots(capacity: int) -> void:
	if _inventory_row == null or inventory_slots.size() == capacity:
		return
	for child in _inventory_row.get_children():
		_inventory_row.remove_child(child)
		child.queue_free()
	inventory_slots.clear()
	inventory_labels.clear()
	for index in range(maxi(capacity, 1)):
		var slot := _make_panel(Color("081318d9"), Color("48666c"), 1)
		slot.custom_minimum_size = Vector2(40, 40)
		_inventory_row.add_child(slot)
		var label := Label.new()
		label.text = "%02d" % (index + 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_color_override("font_color", Color("d2dfdc"))
		slot.add_child(label)
		inventory_slots.append(slot)
		inventory_labels.append(label)

func _short_resource_name(resource_id: String) -> String:
	match resource_id:
		ResourceIdsScript.FOOD:
			return "JED."
		ResourceIdsScript.PLANKS:
			return "DES."
		ResourceIdsScript.SCRAP:
			return "ZŁOM"
		ResourceIdsScript.FABRIC_RUBBER:
			return "TKAN."
		ResourceIdsScript.TECH_PARTS:
			return "CZĘŚ."
		ResourceIdsScript.MEDS_CHEMICALS:
			return "LEKI"
		_:
			return ResourceIdsScript.display_name(resource_id).to_upper().left(5)

func _mass_text(value: float) -> String:
	return ("%.1f" % value).replace(".", ",")

func _roman_tier(tier: int) -> String:
	match tier:
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
		_:
			return str(maxi(tier, 1))

func _refresh_oxygen_label() -> void:
	if oxygen_label == null:
		return
	oxygen_label.text = _oxygen_value_text if _tank_badge.is_empty() else "%s  •  %s" % [_oxygen_value_text, _tank_badge]

func _refresh_vitals_tooltip() -> void:
	if vitals_cluster == null:
		return
	var values := "Zdrowie %s  •  Tlen %s" % [health_label.text if health_label != null else "—", oxygen_label.text if oxygen_label != null else "—"]
	vitals_cluster.tooltip_text = values if _identity_detail.is_empty() else "%s\n%s" % [_identity_detail, values]

func _refresh_context_tooltip() -> void:
	if context_cluster == null:
		return
	var lines: Array[String] = []
	if not _time_detail.is_empty():
		lines.append(_time_detail)
	if not _light_detail.is_empty():
		lines.append(_light_detail)
	if not _tank_detail.is_empty():
		lines.append(_tank_detail)
	context_cluster.tooltip_text = "\n".join(lines)

func _update_context_cluster_height(has_hazards: bool) -> void:
	if context_cluster == null:
		return
	context_cluster.offset_top = -62.0 if has_hazards else -46.0

func _configure_progress_bar(bar: ProgressBar, fill_color: Color, radius: int = 2) -> StyleBoxFlat:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("13242a")
	background.border_color = Color("304a50")
	background.set_border_width_all(1)
	background.set_corner_radius_all(radius)
	bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(radius)
	bar.add_theme_stylebox_override("fill", fill)
	return fill

func _make_panel(fill: Color, border: Color, width: int = 1) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _margin_content(parent: Control, amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", amount)
	margin.add_theme_constant_override("margin_top", amount)
	margin.add_theme_constant_override("margin_right", amount)
	margin.add_theme_constant_override("margin_bottom", amount)
	parent.add_child(margin)
	return margin
