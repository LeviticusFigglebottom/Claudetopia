extends TestCase
## The capture runner as an instrument: it must not be able to report success for a frame with
## no world in it.
##
## A run of tools/capture/plans/default.json once came back with three street shots at 230-290
## draw calls and 0.3 M primitives against the 400-550 and 0.5-0.8 M the same shots had measured
## an hour before, because the scatter had failed to load. `cells_loaded` said 25, the streamer
## said the ring was loaded (the cell nodes were there, they were simply empty), perf.json said
## "within_budget": true, and the capture exited 0. DECISIONS.md already has an entry about
## systems that draw nothing while reporting success; this is that species in the instrument
## rather than in the thing measured, which is worse, because a perf sheet is acted on.

const RUNNER := preload("res://tools_gd/capture_runner.gd")


## A perf sample as _sample_perf builds one, with only the fields the verdict reads.
func _sample(label: String, cells: int, instances: int, draws := 400, prims := 600000) -> Dictionary:
	return {
		"label": label,
		"draw_calls": draws,
		"primitives": prims,
		"cells_loaded": cells,
		"scatter_instances": instances,
	}


func test_a_frame_with_cells_but_no_scatter_is_flagged() -> void:
	var empty := _sample("briarwold_street", 25, 0, 230, 280000)
	assert_true(RUNNER.mark_unstreamed(empty), "25 loaded cells holding nothing is not the world")
	assert_true(bool(empty.get("unstreamed", false)),
		"the flag has to be on the sample, so it reaches perf.json and not only the log")


func test_a_streamed_frame_is_left_alone() -> void:
	var healthy := _sample("briarwold_street", 25, 9261, 547, 790000)
	assert_false(RUNNER.mark_unstreamed(healthy))
	assert_false(healthy.has("unstreamed"), "a healthy sheet should carry no flags at all")
	# Nothing streamed yet is a different thing from streamed-and-empty: there is no cell to
	# have been empty, so there is nothing to disbelieve.
	var before_anything := _sample("first_frame", 0, 0)
	assert_false(RUNNER.mark_unstreamed(before_anything))
	assert_false(before_anything.has("unstreamed"))


func test_flagged_shots_are_excluded_from_the_budget_verdict() -> void:
	var real := _sample("briarwold_vista", 25, 9261, 1900, 1400000)
	var empty := _sample("briarwold_street", 25, 0, 230, 280000)
	RUNNER.mark_unstreamed(empty)
	var v: Dictionary = RUNNER.verdict([real, empty])
	assert_eq(int(v["worst"]["draw_calls"]), 1900, "the verdict must be over the real frames")
	assert_eq(int(v["worst"]["primitives"]), 1400000)
	assert_eq(int(v["shots_counted"]), 1, "one of the two shots photographed the world")
	assert_eq(v["unstreamed_shots"], ["briarwold_street"],
		"the document has to name what it threw away")
	assert_true(bool(v["within_budget"]))


func test_a_sheet_with_nothing_left_to_measure_has_no_verdict() -> void:
	# The failure that prompted this: half the sheet empty. If every remaining shot is flagged
	# there is no measurement, and "within budget" is the one answer that must not come back --
	# an empty frame is cheap, so counting it can only ever flatter the world.
	var shots: Array = []
	for label in ["briarwold_street", "skerrow_street", "cinderlea_street"]:
		var s := _sample(label, 25, 0, 290, 330000)
		RUNNER.mark_unstreamed(s)
		shots.append(s)
	var v: Dictionary = RUNNER.verdict(shots)
	assert_false(bool(v["within_budget"]), "a sheet with no world in it cannot be within budget")
	assert_eq(int(v["shots_counted"]), 0)
	assert_eq(v["unstreamed_shots"].size(), 3)


func test_the_verdict_still_fails_a_frame_that_is_genuinely_over() -> void:
	var fat := _sample("briarwold_vista", 25, 9261, 2400, 2100000)
	var v: Dictionary = RUNNER.verdict([fat])
	assert_false(bool(v["within_budget"]), "excluding empty frames must not excuse expensive ones")
	assert_eq(int(v["shots_counted"]), 1)
	assert_empty(v["unstreamed_shots"])


# --- the ground probe's tour: the same instrument, stopping at every place --------------------------

const GROUND := preload("res://tools_gd/ground_probe.gd")


func test_a_tour_stop_whose_ring_never_stood_is_unstreamed() -> void:
	assert_true(GROUND.is_unstreamed(-1.0, {"wanted": 25, "cells": 11, "things": 5400}),
		"still coming in when the wait gave up: the frame and the footing are of half a county")


func test_a_tour_stop_whose_ring_stood_empty_is_unstreamed() -> void:
	assert_true(GROUND.is_unstreamed(6.0, {"wanted": 25, "cells": 25, "with_things": 0, "things": 0}),
		"every cell built and not one thing in any: the scatter did not load")


func test_a_tour_stop_with_the_country_in_it_is_measured() -> void:
	assert_false(GROUND.is_unstreamed(6.0, {"wanted": 25, "cells": 25, "with_things": 25, "things": 48000}))
	# the sea off a headland: most cells bare, the shore holding something
	assert_false(GROUND.is_unstreamed(3.0, {"wanted": 25, "cells": 25, "with_things": 4, "things": 900}),
		"bare cells are the country when some of the ring holds something")


func test_a_tour_stop_over_undrawn_ground_is_unstreamed() -> void:
	# a 1024 build drawn at the 4096 spacing: one region in a corner, and every other place's cells
	# built and full over brown fog, with nothing drawn under the body
	assert_true(GROUND.is_unstreamed(4.0, {"wanted": 25, "cells": 25, "with_things": 25, "things": 48000,
		"ground_drawn": false}), "cells full of trees over no ground is not the country")
