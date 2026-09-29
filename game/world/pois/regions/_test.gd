extends RefCounted
## A region's builders as the tests see them (tests/unit/test_poi_preview.gd): a POI def of the region
## "core:region/_test" with `"builder": "marked_cairn"` is built here. Not a region of the world.


static func marked_cairn(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().WAYSIDE.cairn(d)
	var mark := Node3D.new()
	mark.name = "RegionalMark"
	d.add_child(mark)
