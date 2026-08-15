extends SceneTree

const NarrativeContentScript := preload("res://scripts/ui/NarrativeContent.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")

var _failed := false


func _initialize() -> void:
	var seen_titles: Dictionary = {}
	for step in range(TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE, TutorialStateScript.Step.COMPLETED):
		var message: Dictionary = NarrativeContentScript.tutorial_message(step)
		_assert(not message.is_empty(), "Każdy aktywny krok samouczka musi mieć treść.")
		_assert(
			str(message.get("compact_title", "")).strip_edges() != ""
			and str(message.get("body", "")).strip_edges() != "",
			"Treść kroku musi mieć tytuł i opis."
		)
		_assert(
			str(message.get("callout_layout", "")) in ["left_top", "right_top", "right_bottom"],
			"Krok samouczka ma nieznany układ calloutu."
		)
		var title := str(message.get("compact_title", ""))
		_assert(not seen_titles.has(title), "Tytuły kroków samouczka muszą być jednoznaczne.")
		seen_titles[title] = true

	var workshop: Dictionary = NarrativeContentScript.tutorial_message(TutorialStateScript.Step.BUILD_WORKSHOP)
	_assert(str(workshop.get("compact_title", "")) == "DZIEŃ 2  •  WARSZTAT", "Krok Warsztatu musi zachować kanoniczny tytuł.")
	_assert(str(workshop.get("body", "")).contains("Odbuduj podświetlony Warsztat Odzysku I."), "Krok Warsztatu musi wskazywać dokładny cel.")
	_assert(NarrativeContentScript.tutorial_message(TutorialStateScript.Step.COMPLETED).is_empty(), "Zakończony samouczek nie może pokazywać aktywnego komunikatu.")

	if _failed:
		quit(1)
		return
	print("Narrative content test passed: all active tutorial steps have complete canonical messages.")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Narrative content test failed: " + message)
