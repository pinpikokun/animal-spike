extends RefCounted

const SimRng := preload("res://src/sim/sim_rng.gd")

static func from_time_dict(clock: Dictionary) -> Variant:
	if not clock.has("hour") or not clock.has("minute"):
		return null
	if typeof(clock["hour"]) != TYPE_INT or typeof(clock["minute"]) != TYPE_INT:
		return null
	var hour: int = clock["hour"]
	var minute: int = clock["minute"]
	if hour < 0 or hour >= 24 or minute < 0 or minute >= 60:
		return null
	return SimRng.seed_from_clock(hour, minute)

static func read_from_system() -> Variant:
	return from_time_dict(Time.get_time_dict_from_system(false))
