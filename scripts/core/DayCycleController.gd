class_name DayCycleController
extends RefCounted

const EndOfDayResolverScript := preload("res://scripts/base/EndOfDayResolver.gd")

func resolve_day(state, dive_result, persist: bool = true):
	var resolver = EndOfDayResolverScript.new()
	return resolver.resolve(state, dive_result, persist)
