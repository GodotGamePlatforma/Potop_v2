class_name SceneFlow
extends RefCounted

static func replace_child(parent: Node, scene: PackedScene, before_add: Callable = Callable()) -> Node:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

	var instance = scene.instantiate()
	if before_add.is_valid():
		before_add.call(instance)
	parent.add_child(instance)
	return instance
