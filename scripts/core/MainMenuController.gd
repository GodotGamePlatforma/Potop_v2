class_name MainMenuController
extends Control

const DifficultyConfiguratorScript := preload("res://scripts/core/DifficultyConfigurator.gd")

@onready var difficulty_picker: OptionButton = $Center/MenuPanel/Margin/Content/DifficultyPicker
@onready var difficulty_summary_label: Label = $Center/MenuPanel/Margin/Content/DifficultySummaryLabel
@onready var custom_difficulty_button: Button = $Center/MenuPanel/Margin/Content/CustomDifficultyButton
@onready var continue_button: Button = $Center/MenuPanel/Margin/Content/ContinueButton
@onready var settings_button: Button = $Center/MenuPanel/Margin/Content/SettingsButton
@onready var status_label: Label = $Center/MenuPanel/Margin/Content/StatusLabel
@onready var settings_menu = $SettingsOverlay

var game_root: Node
var _new_game_confirmation: ConfirmationDialog
var _pending_profile_id: String = "standard"
var _difficulty_configurator
var _custom_profile: Resource
var _custom_axes: Dictionary = {}
var _start_after_custom_configuration: bool = false

func _ready() -> void:
	$Center/MenuPanel/Margin/Content/NewGameButton.pressed.connect(_on_new_game_pressed)
	difficulty_picker.item_selected.connect(_on_difficulty_selected)
	custom_difficulty_button.pressed.connect(_on_custom_difficulty_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	$Center/MenuPanel/Margin/Content/QuitButton.pressed.connect(_on_quit_pressed)
	_new_game_confirmation = ConfirmationDialog.new()
	_new_game_confirmation.name = "NewGameConfirmation"
	_new_game_confirmation.title = "Nowa kampania"
	_new_game_confirmation.dialog_text = "Nowa kampania nieodwracalnie zastąpi bieżącą dopiero po poprawnym utworzeniu i bezpiecznym zapisie."
	_new_game_confirmation.ok_button_text = "ROZPOCZNIJ"
	_new_game_confirmation.cancel_button_text = "ANULUJ"
	_new_game_confirmation.confirmed.connect(_start_pending_campaign)
	add_child(_new_game_confirmation)
	_difficulty_configurator = DifficultyConfiguratorScript.new()
	_difficulty_configurator.profile_configured.connect(_on_custom_profile_configured)
	_difficulty_configurator.canceled.connect(_on_custom_configuration_canceled)
	add_child(_difficulty_configurator)

func bind(root: Node, _state = null) -> void:
	game_root = root
	_rebuild_difficulties()
	var has_saved_campaign: bool = bool(game_root.has_saved_campaign())
	continue_button.disabled = not has_saved_campaign
	if game_root.has_unresolved_campaign_replacement():
		status_label.text = game_root.last_new_campaign_failure_text()
	elif has_saved_campaign:
		status_label.text = "Znaleziono zapis kampanii."
	elif game_root.has_campaign_storage_for_new_campaign():
		status_label.text = "Znaleziono nieprawidłowe dane zapisu. Nowa kampania zastąpi je dopiero po bezpiecznym utworzeniu."
	else:
		status_label.text = "Brak zapisu — rozpocznij nową kampanię."

func _rebuild_difficulties() -> void:
	difficulty_picker.clear()
	var selected_index := 0
	var options: Array = game_root.get_difficulty_options()
	for profile in options:
		if profile == null:
			continue
		var index := difficulty_picker.item_count
		difficulty_picker.add_item(str(profile.profile_name))
		difficulty_picker.set_item_metadata(index, str(profile.profile_id))
		if str(profile.profile_id) == "standard":
			selected_index = index
	difficulty_picker.select(selected_index)
	_on_difficulty_selected(selected_index)

func _on_new_game_pressed() -> void:
	if game_root == null:
		return
	var profile_id := "standard"
	if difficulty_picker.item_count > 0:
		profile_id = str(difficulty_picker.get_item_metadata(difficulty_picker.selected))
	_pending_profile_id = profile_id
	if profile_id == "custom" and _custom_profile == null:
		_start_after_custom_configuration = true
		_open_custom_configurator()
		return
	_request_campaign_start()


func _request_campaign_start() -> void:
	if game_root.has_campaign_storage_for_new_campaign():
		if game_root.has_unresolved_campaign_replacement():
			_new_game_confirmation.dialog_text = game_root.last_new_campaign_failure_text()
		elif game_root.has_saved_campaign():
			_new_game_confirmation.dialog_text = "Nowa kampania nieodwracalnie zastąpi bieżącą dopiero po poprawnym utworzeniu i bezpiecznym zapisie."
		else:
			_new_game_confirmation.dialog_text = "Na dysku są nieprawidłowe dane zapisu. Nowa kampania zastąpi je dopiero po poprawnym utworzeniu."
		_new_game_confirmation.popup_centered()
	else:
		_start_pending_campaign()

func _start_pending_campaign() -> void:
	var started := false
	if _pending_profile_id == "custom" and _custom_profile != null:
		started = game_root.start_new_campaign_with_profile(_custom_profile, 0, true, true, true)
	else:
		started = game_root.start_new_campaign(_pending_profile_id, 0, true, true, true)
	if not started:
		status_label.text = game_root.last_new_campaign_failure_text()
		continue_button.disabled = not game_root.has_saved_campaign()


func _on_difficulty_selected(index: int) -> void:
	if index < 0 or index >= difficulty_picker.item_count:
		return
	var profile_id := str(difficulty_picker.get_item_metadata(index))
	_pending_profile_id = profile_id
	custom_difficulty_button.visible = profile_id == "custom"
	if profile_id == "custom":
		difficulty_summary_label.text = _profile_summary(_custom_profile) if _custom_profile != null else "Własne ustawienia wymagają konfiguracji przed startem."
		return
	var profile = game_root.get_difficulty_profile(profile_id)
	difficulty_summary_label.text = _profile_summary(profile)


func _on_custom_difficulty_pressed() -> void:
	_start_after_custom_configuration = false
	_open_custom_configurator()


func _open_custom_configurator() -> void:
	if _difficulty_configurator == null:
		return
	_difficulty_configurator.open_with_axes(_custom_axes)


func _on_custom_profile_configured(profile: Resource) -> void:
	_custom_profile = profile
	_custom_axes = _difficulty_configurator.configured_axes()
	difficulty_summary_label.text = _profile_summary(_custom_profile)
	status_label.text = "Ustawienia niestandardowe są gotowe i zostaną zamrożone przy starcie kampanii."
	if _start_after_custom_configuration:
		_start_after_custom_configuration = false
		_request_campaign_start()


func _on_custom_configuration_canceled() -> void:
	_start_after_custom_configuration = false


func _profile_summary(profile) -> String:
	if profile == null:
		return "Brak poprawnych danych profilu."
	var daily_food := maxi(int(profile.food_per_adult) * 3, 1)
	var start_days := float(profile.starting_food) / float(daily_food)
	return (
		"%s • %.1f dnia jedzenia • racja %d/os. • budowa ×%.2f • naprawy ×%.2f • łup ×%.2f\n"
		+ "Nadzieja +×%.2f/-×%.2f • leczenie ×%.2f • tlen ×%.2f • kombinezon/zimno/zagrożenia ×%.2f/%.2f/%.2f\n"
		+ "Sztormy/obrażenia ×%.2f/%.2f • bazowa cisza %.0f%% • pomoc/utrudnienia ×%.2f/%.2f • ratunek operatora %d%%"
	) % [
		str(profile.profile_name),
		start_days,
		int(profile.food_per_adult),
		float(profile.build_cost_multiplier),
		float(profile.repair_cost_multiplier),
		float(profile.loot_density_multiplier),
		float(profile.hope_gain_multiplier),
		float(profile.hope_loss_multiplier),
		float(profile.recovery_speed_multiplier),
		float(profile.oxygen_use_multiplier),
		float(profile.suit_damage_multiplier),
		float(profile.cold_rate_multiplier),
		float(profile.threat_aggression_multiplier),
		float(profile.storm_frequency_multiplier),
		float(profile.storm_damage_multiplier),
		float(profile.quiet_day_weight),
		float(profile.relief_event_weight_multiplier),
		float(profile.hardship_event_weight_multiplier),
		int(round(float(profile.operator_rescue_chance) * 100.0)),
	]

func _on_continue_pressed() -> void:
	if game_root == null:
		return
	if not game_root.continue_campaign():
		status_label.text = "Nie udało się wczytać zapisu. Możesz rozpocząć nową kampanię."
		continue_button.disabled = true


func _on_settings_pressed() -> void:
	if game_root == null:
		status_label.text = "Ustawienia użytkownika nie są dostępne."
		return
	var settings = game_root.get("user_settings")
	if settings == null:
		status_label.text = "Ustawienia użytkownika nie są dostępne."
		return
	if settings_menu == null or not settings_menu.has_method("open_with_settings"):
		status_label.text = "Nie udało się otworzyć panelu ustawień."
		return
	settings_menu.open_with_settings(settings, settings_button)

func _on_quit_pressed() -> void:
	get_tree().quit()
