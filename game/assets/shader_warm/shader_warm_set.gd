class_name ShaderWarmSet
extends Resource
## One material for every shader the game was seen to draw with (tools_gd/material_census.gd), kept
## so the export's shader baker compiles them all ahead of time (docs/FIRST_LAUNCH.md). A shader the
## game builds in code -- a StandardMaterial3D.new() with its flags, a water shader with its defines,
## Terrain3D's -- has no file the baker could find; the cache is keyed by the shader's source, so a
## material here with the same features bakes the entry the running game then finds.
##
## Nothing in the game loads this: it is read by the export, and by the census when it adds to it.
## Its textures are shared placeholders (a material's shader depends on which slots are set, not
## on what is in them).

## The materials, one per feature key (MaterialCensus.key_of).
@export var materials: Array[Material] = []
## Where each was first seen: the node's path and the run, for whoever wonders why one is here.
@export var seen_at: PackedStringArray = PackedStringArray()
