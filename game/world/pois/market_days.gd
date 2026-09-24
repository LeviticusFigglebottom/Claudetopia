class_name MarketDays
extends Node3D
## What stands in a market field on market day, and is packed away the rest of the week: the
## stalls, their wares and the carts. It is shown, and its bodies are in the world, on the
## market's own day of the week, and hidden and out of the world on any other. It looks again at
## every new day.

## The day of the week the market is held (WorldClock.DAYS).
var market_day := "Merrowday"


func _ready() -> void:
	EventBus.new_day.connect(_on_new_day)
	show_for(WorldClock.day)


func _exit_tree() -> void:
	if EventBus.new_day.is_connected(_on_new_day):
		EventBus.new_day.disconnect(_on_new_day)


func _on_new_day(day: int) -> void:
	show_for(day)


## Whether `day` (the clock's count, from 1) falls on the market's day of the week.
func is_market_day(day: int) -> bool:
	return WorldClock.DAYS[posmod(day - 1, WorldClock.DAYS.size())] == market_day


## Shows the stalls on a market day, and packs them away on any other: hidden, and their bodies
## out of the world, so nobody walks into a stall that is not there.
func show_for(day: int) -> void:
	var open := is_market_day(day)
	visible = open
	process_mode = Node.PROCESS_MODE_INHERIT if open else Node.PROCESS_MODE_DISABLED
