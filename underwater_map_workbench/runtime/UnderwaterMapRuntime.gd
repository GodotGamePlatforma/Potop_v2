class_name UnderwaterMapRuntime
extends "res://scripts/diving/ContinuousDiveWorld.gd"

const NORMAL_PARALLAX_SCALE_META := &"normal_parallax_scale"
const AUTHORED_PARALLAX_SCALE_META := &"parallax_scale"

## Campaign-facing map host. The authored source is map_manifest.json;
## UnderwaterMap.tscn is its generated derivative and this node owns only
## the transient runtime layer.


func set_reduced_motion(enabled: bool) -> void:
	super.set_reduced_motion(enabled)
	_apply_visual_layer_motion_setting()


func _build_source_visual_layers() -> void:
	super._build_source_visual_layers()
	_apply_visual_layer_motion_setting()


func _apply_visual_layer_motion_setting() -> void:
	var visual_layers := get_node_or_null("RuntimeDynamic/VisualLayers") as Node2D
	if visual_layers == null:
		return
	_apply_parallax_motion_recursive(visual_layers)


func _apply_parallax_motion_recursive(node: Node) -> void:
	if node is Parallax2D:
		var parallax := node as Parallax2D
		var normal_scale := _normal_parallax_scale(parallax)
		parallax.scroll_scale = Vector2.ONE if _reduced_motion else normal_scale
	for child in node.get_children():
		_apply_parallax_motion_recursive(child)


func _normal_parallax_scale(parallax: Parallax2D) -> Vector2:
	var normal_value: Variant = null
	if parallax.has_meta(NORMAL_PARALLAX_SCALE_META):
		normal_value = parallax.get_meta(NORMAL_PARALLAX_SCALE_META)
	if normal_value is Vector2:
		var has_authored_scale := (
			parallax.has_meta(AUTHORED_PARALLAX_SCALE_META)
			and parallax.get_meta(AUTHORED_PARALLAX_SCALE_META) is Vector2
		)
		if not has_authored_scale:
			parallax.set_meta(AUTHORED_PARALLAX_SCALE_META, normal_value)
		return normal_value as Vector2
	var authored_value: Variant = null
	if parallax.has_meta(AUTHORED_PARALLAX_SCALE_META):
		authored_value = parallax.get_meta(AUTHORED_PARALLAX_SCALE_META)
	var normal_scale := (authored_value as Vector2) if authored_value is Vector2 else parallax.scroll_scale
	if not authored_value is Vector2:
		parallax.set_meta(AUTHORED_PARALLAX_SCALE_META, normal_scale)
	parallax.set_meta(NORMAL_PARALLAX_SCALE_META, normal_scale)
	return normal_scale
