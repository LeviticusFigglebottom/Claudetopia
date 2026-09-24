extends TestCase
## The probes the long runs are driven by (the flow, the captures) compile.
##
## Nothing else loads them: a mistake in one is found when `./run.sh flow` or `./run.sh shots`
## reaches it, which on a loaded machine is most of an hour in. Loading them here with the game's
## singletons up finds it in a second, and the runner counts the engine's parse errors.

const PROBES := ["res://tools_gd/flow_probe.gd", "res://tools_gd/capture_runner.gd"]


func test_the_long_runs_probes_compile() -> void:
	for path: String in PROBES:
		var script := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		assert_true(script != null and script.can_instantiate(), "%s compiles" % path)
