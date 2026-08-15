class_name IntroController
extends Control

const INTRO_DURATION := 45.0

const CAPTIONS := [
	{
		"start": 1.6,
		"end": 6.5,
		"text": "Pięć lat temu zaczął padać deszcz.\nOd tamtej pory nie przestał.",
	},
	{
		"start": 6.7,
		"end": 11.7,
		"text": "Najpierw zniknęły pola. Potem drogi,\npartery… całe miasta.",
	},
	{
		"start": 11.9,
		"end": 15.6,
		"text": "Woda zabrała nam ziemię.\nNie zabrała wszystkiego.",
	},
	{
		"start": 16.2,
		"end": 22.7,
		"text": "Kiedy znaleźliśmy pustą platformę serwisową,\nbyło nas troje: Anka, Igor i ja.",
	},
	{
		"start": 23.0,
		"end": 27.8,
		"text": "Za mało, by odbudować świat.\nDość, by przeżyć kolejny dzień.",
	},
	{
		"start": 30.2,
		"end": 36.5,
		"text": "Pod nami zostało wszystko, czego potrzebujemy…\ni może ktoś, kto wciąż czeka.",
	},
	{
		"start": 36.8,
		"end": 41.8,
		"text": "Jeśli chcemy zobaczyć jutro,\nmusimy zbudować drogę w dół.",
	},
]

@onready var city_plate: TextureRect = %CityPlate
@onready var discovery_plate: TextureRect = %DiscoveryPlate
@onready var bridge_plate: TextureRect = %BridgePlate
@onready var platform_reveal: TextureRect = %PlatformReveal
@onready var rain_overlay: ColorRect = %RainOverlay
@onready var cinematic_overlay: ColorRect = %CinematicOverlay
@onready var waterline_sweep: ColorRect = %WaterlineSweep
@onready var chapter_label: Label = %ChapterLabel
@onready var title_group: Control = %TitleGroup
@onready var subtitle_panel: PanelContainer = %SubtitlePanel
@onready var mira_portrait: Control = %MiraPortrait
@onready var narration_label: Label = %NarrationLabel
@onready var skip_button: Button = %IntroSkipButton
@onready var fade_overlay: ColorRect = %FadeOverlay
@onready var ambient_player: AudioStreamPlayer = %AmbientPlayer
@onready var animation_player: AnimationPlayer = %AnimationPlayer

var game_root: Node
var _bound := false
var _is_finishing := false
var _caption_index := -1
var _forced_timeline_time := -1.0
var _reduced_motion := false


func seed_user_settings_before_ready(_quality_id: String, reduced_motion: bool) -> void:
	# GameRoot calls this before SceneTree entry. Keep it data-only; @onready
	# consumers do not exist until _ready().
	_reduced_motion = reduced_motion


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mira_portrait.call("configure", "mira", "Mira Boruta")
	skip_button.pressed.connect(_finish_intro)
	animation_player.animation_finished.connect(_on_animation_finished)
	_build_timeline_animation()
	resized.connect(_layout_visuals)
	_layout_visuals()
	_apply_timeline(0.0)
	set_process(false)


func bind(root: Node, _state = null) -> void:
	if _bound:
		return
	game_root = root
	_bound = true
	_forced_timeline_time = -1.0
	_caption_index = -1
	_apply_timeline(0.0)
	animation_player.play(&"intro")
	if ambient_player.stream != null:
		ambient_player.play()
	set_process(true)


func set_timeline_time_for_tests(seconds: float) -> void:
	_forced_timeline_time = clampf(seconds, 0.0, INTRO_DURATION)
	animation_player.pause()
	ambient_player.stop()
	animation_player.seek(_forced_timeline_time, true)
	_apply_timeline(_forced_timeline_time)


func get_caption_windows_for_tests() -> Array[Dictionary]:
	var cues: Array[Dictionary] = []
	for caption in CAPTIONS:
		cues.append({
			"start": float(caption["start"]),
			"end": float(caption["end"]),
			"text": str(caption["text"]),
		})
	return cues


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	var timeline_time := _forced_timeline_time
	if timeline_time < 0.0 and animation_player != null:
		timeline_time = animation_player.current_animation_position
	_apply_timeline(maxf(timeline_time, 0.0))


func _process(_delta: float) -> void:
	if not _bound or _is_finishing:
		return
	var timeline_time := _forced_timeline_time
	if timeline_time < 0.0:
		timeline_time = animation_player.current_animation_position
	_apply_timeline(timeline_time)


func _unhandled_input(event: InputEvent) -> void:
	if not _bound or _is_finishing:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish_intro()


func _exit_tree() -> void:
	if ambient_player != null:
		ambient_player.stop()
		ambient_player.stream = null


func _build_timeline_animation() -> void:
	if animation_player.has_animation(&"intro"):
		return
	var animation := Animation.new()
	animation.resource_name = "intro"
	animation.length = INTRO_DURATION
	animation.loop_mode = Animation.LOOP_NONE
	var library := AnimationLibrary.new()
	library.add_animation(&"intro", animation)
	animation_player.add_animation_library(&"", library)


func _apply_timeline(timeline_time: float) -> void:
	var t := clampf(timeline_time, 0.0, INTRO_DURATION)
	var city_progress := _normalized(t, 0.0, 16.8)
	var discovery_progress := _normalized(t, 15.2, 23.7)
	var bridge_progress := _normalized(t, 29.5, 44.2)

	_set_alpha(city_plate, _fade_window(t, 0.35, 1.35, 15.2, 17.0))
	_set_alpha(discovery_plate, _fade_window(t, 15.0, 16.25, 22.25, 23.65))
	_set_alpha(platform_reveal, _fade_window(t, 22.1, 23.15, 29.75, 31.05))
	_set_alpha(bridge_plate, _fade_window(t, 29.6, 30.55, 43.8, 44.45))

	if _reduced_motion:
		city_plate.scale = Vector2.ONE
		city_plate.position = Vector2.ZERO
		discovery_plate.scale = Vector2.ONE
		discovery_plate.position = Vector2.ZERO
		bridge_plate.scale = Vector2.ONE
		bridge_plate.position = Vector2.ZERO
	else:
		city_plate.scale = Vector2.ONE * lerpf(1.035, 1.075, _ease(city_progress))
		city_plate.position = Vector2(-12.0, 2.0).lerp(Vector2(8.0, -16.0), _ease(city_progress))
		discovery_plate.scale = Vector2.ONE * lerpf(1.02, 1.075, _ease(discovery_progress))
		discovery_plate.position = Vector2(4.0, sin(t * 1.28) * 2.2).lerp(Vector2(-6.0, -6.0), _ease(discovery_progress))
		bridge_plate.scale = Vector2.ONE * lerpf(1.025, 1.065, _ease(bridge_progress))
		bridge_plate.position = Vector2(0.0, 4.0).lerp(Vector2(0.0, -38.0), _ease(bridge_progress))

	var rain_strength := 0.72
	if t >= 29.3:
		rain_strength = lerpf(0.72, 0.0, _ease(_normalized(t, 29.3, 31.0)))
	_set_alpha(rain_overlay, rain_strength)
	var rain_material := rain_overlay.material as ShaderMaterial
	if rain_material != null:
		rain_material.set_shader_parameter("anim_time", t)
		rain_material.set_shader_parameter("rain_intensity", 0.76)
	var overlay_material := cinematic_overlay.material as ShaderMaterial
	if overlay_material != null:
		overlay_material.set_shader_parameter("anim_time", t)

	var sweep_alpha := _fade_window(t, 29.45, 29.62, 30.28, 30.48)
	_set_alpha(waterline_sweep, sweep_alpha)
	waterline_sweep.position.y = size.y * 0.5 if _reduced_motion else lerpf(-56.0, size.y + 56.0, _ease(_normalized(t, 29.45, 30.48)))

	_set_alpha(chapter_label, _fade_window(t, 0.9, 1.55, 4.65, 5.45))
	_set_alpha(title_group, _fade_window(t, 41.9, 42.55, 44.05, 44.55))
	_set_alpha(fade_overlay, 1.0 - _ease(_normalized(t, 0.0, 1.15)) if t < 1.15 else _ease(_normalized(t, 44.15, 45.0)))
	_update_caption(t)


func _update_caption(timeline_time: float) -> void:
	var next_index := -1
	var caption_alpha := 0.0
	for index in range(CAPTIONS.size()):
		var caption: Dictionary = CAPTIONS[index]
		var start_time := float(caption["start"])
		var end_time := float(caption["end"])
		if timeline_time < start_time or timeline_time >= end_time:
			continue
		next_index = index
		caption_alpha = minf(
			_ease(_normalized(timeline_time, start_time, start_time + 0.28)),
			1.0 - _ease(_normalized(timeline_time, end_time - 0.32, end_time))
		)
		break
	if next_index != _caption_index:
		_caption_index = next_index
		if _caption_index >= 0:
			narration_label.text = str(CAPTIONS[_caption_index]["text"])
	_set_alpha(subtitle_panel, caption_alpha)


func _layout_visuals() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var subtitle_half_width := minf(455.0, maxf((size.x - 32.0) * 0.5, 160.0))
	subtitle_panel.offset_left = -subtitle_half_width
	subtitle_panel.offset_right = subtitle_half_width
	for plate in [city_plate, discovery_plate, platform_reveal, bridge_plate]:
		plate.pivot_offset = size * 0.5
	var rain_material := rain_overlay.material as ShaderMaterial
	if rain_material != null:
		rain_material.set_shader_parameter("viewport_size", size)
	var overlay_material := cinematic_overlay.material as ShaderMaterial
	if overlay_material != null:
		overlay_material.set_shader_parameter("viewport_size", size)


func _finish_intro() -> void:
	if _is_finishing:
		return
	_is_finishing = true
	set_process(false)
	animation_player.stop()
	ambient_player.stop()
	if game_root != null and game_root.has_method("finish_intro"):
		game_root.call("finish_intro")


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"intro":
		_finish_intro()


func _set_alpha(item: CanvasItem, alpha: float) -> void:
	var color := item.modulate
	color.a = clampf(alpha, 0.0, 1.0)
	item.modulate = color


func _fade_window(t: float, fade_in_start: float, full_start: float, full_end: float, fade_out_end: float) -> float:
	if t < fade_in_start or t >= fade_out_end:
		return 0.0
	if t < full_start:
		return _ease(_normalized(t, fade_in_start, full_start))
	if t <= full_end:
		return 1.0
	return 1.0 - _ease(_normalized(t, full_end, fade_out_end))


func _normalized(value: float, start_value: float, end_value: float) -> float:
	if is_equal_approx(start_value, end_value):
		return 1.0
	return clampf((value - start_value) / (end_value - start_value), 0.0, 1.0)


func _ease(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
