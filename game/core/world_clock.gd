extends Node
## WorldClock: game time. One game day defaults to 48 real minutes (Settings gameplay/day_length_minutes).
## time_hours runs 0..24; day counts from 1. Emits EventBus.hour_changed and EventBus.new_day.
## The night runs faster than the day: it lasts a third as long as the day in real time (the
## user's call, 2026-09-27), and the whole day still takes day_length_minutes (36 + 12 of 48).

signal tick(time_hours: float)

const DAYS := ["Kindleday", "Tallowday", "Merrowday", "Thornday", "Skerrday", "Hushday", "Tollday"]
const MONTHS := ["Thaw", "Naming", "Sowing", "Long Light", "Haysun", "Reaping", "Long Table", "Ashfall", "Candle"]

var time_hours: float = 8.0
var day: int = 1
var running := true
var time_scale := 1.0
var _last_hour := 8

## Game hours of night (is_night: 20:30 to 05:30) and of day, and the rates that make the night a
## third of the day in real time while the two together keep the day's length: of 24 units of
## real time the day takes 18 and the night 6, so the day runs at 15/18 and the night at 9/6.
const NIGHT_HOURS := 9.0
const DAY_HOURS := 15.0
const NIGHT_SHARE := 1.0 / 3.0
const DAY_RATE := DAY_HOURS / (24.0 / (1.0 + NIGHT_SHARE))
const NIGHT_RATE := NIGHT_HOURS / (24.0 * NIGHT_SHARE / (1.0 + NIGHT_SHARE))


func _ready() -> void:
	SaveSystem.register("clock", self)


func _process(delta: float) -> void:
	if not running:
		return
	var day_len: float = float(Settings.get_value("gameplay", "day_length_minutes", 48.0)) * 60.0
	advance_hours(delta * 24.0 / maxf(day_len, 1.0) * time_scale * (NIGHT_RATE if is_night() else DAY_RATE))


func advance_hours(hours: float) -> void:
	time_hours += hours
	while time_hours >= 24.0:
		time_hours -= 24.0
		day += 1
		EventBus.new_day.emit(day)
	var h := int(time_hours)
	if h != _last_hour:
		_last_hour = h
		EventBus.hour_changed.emit(h)
	tick.emit(time_hours)


func set_time(hours: float, new_day: int = -1) -> void:
	time_hours = fposmod(hours, 24.0)
	if new_day > 0:
		day = new_day
	_last_hour = int(time_hours)
	EventBus.hour_changed.emit(_last_hour)
	tick.emit(time_hours)


## Skip forward to the next occurrence of `hour` (e.g. sleeping until 6).
func wait_until(at_hour: float) -> float:
	var delta := fposmod(at_hour - time_hours, 24.0)
	if delta < 0.01:
		delta = 24.0
	advance_hours(delta)
	return delta


func hour() -> int:
	return int(time_hours)


func minute() -> int:
	return int(fmod(time_hours, 1.0) * 60.0)


func is_night() -> bool:
	return time_hours < 5.5 or time_hours >= 20.5


## 0 at midnight, 1 at noon (for sky blending).
func daylight() -> float:
	return clampf((cos((time_hours - 12.0) / 24.0 * TAU) + 1.0) * 0.5, 0.0, 1.0)


## Sun elevation in degrees: -90 at midnight, +90 at noon (before latitude bias).
func sun_elevation_deg() -> float:
	return -cos(time_hours / 24.0 * TAU) * 90.0


func weekday_name() -> String:
	return DAYS[(day - 1) % DAYS.size()]


func month_name() -> String:
	@warning_ignore("integer_division")
	return MONTHS[((day - 1) / 28) % MONTHS.size()]


func formatted() -> String:
	return "%02d:%02d, %s %d of %s" % [hour(), minute(), weekday_name(), ((day - 1) % 28) + 1, month_name()]


func to_save() -> Dictionary:
	return {"time_hours": time_hours, "day": day}


func from_save(d: Dictionary) -> void:
	time_hours = float(d.get("time_hours", 8.0))
	day = int(d.get("day", 1))
	_last_hour = int(time_hours)
