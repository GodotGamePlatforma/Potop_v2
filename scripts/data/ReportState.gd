class_name ReportState
extends Resource

@export var title: String = ""
@export var day: int = 0
@export var includes_dive: bool = false
@export var entries: Array[String] = []
@export var warnings: Array[String] = []

func add_entry(text: String) -> void:
	entries.append(text)

func add_warning(text: String) -> void:
	warnings.append(text)
