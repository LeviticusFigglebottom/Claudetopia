class_name HardwareTier
extends RefCounted
## The graphics preset a machine is offered the first time the game starts on it, from what the
## renderer says about its graphics adapter (`recommend`). `Settings` asks once, when settings.cfg
## has no `graphics` section of its own; after that the section is the player's and is never
## touched again. The settings screen's "Recommended" button asks again on demand.
##
## The owner and a friend play on work laptops with integrated graphics (an HP G11 with a Ryzen 5
## PRO, so a Radeon 660M or 740M), where the title, the menus and the Naming crawled at High. A
## graphics card of its own keeps High, which is the game as tuned; only a weak machine's *default*
## changes, and every knob stays the player's.
##
## What is read: the adapter's type (integrated, discrete, virtual, CPU) first, then its name and
## vendor as a hint, and the machine's RAM. Godot 4.7 has no call for a card's total video memory
## (the startup trace says so too), so it is never part of the verdict; an iGPU's memory is the
## machine's own, which is why the RAM is. The Compatibility renderer reports every adapter's type
## as "other", and some drivers call an AMD APU "discrete", so then the name decides (`kind_of`).
##
## Integrated graphics gets Medium (Iris Xe, Arc graphics, Radeon 660M-890M, Apple M-series,
## Adreno), and so does an adapter nothing recognises: the safe middle. The floor under it (Low),
## and why:
##   - a software rasterizer (llvmpipe, lavapipe, WARP, SwiftShader): every frame is the CPU's;
##   - Intel's "HD Graphics" and "UHD Graphics" (Gen 9 to Gen 12 with 12-32 EUs, about 0.4 TFLOPS
##     for a UHD 620): a fifth of an Iris Xe's 96 EUs (about 2.1 TFLOPS), with Medium's 2x MSAA and
##     SSAO more than they can carry at 1080p;
##   - AMD's "Vega" iGPUs (Vega 3 to 11, about 0.4-1.8 TFLOPS on old GCN) and the Radeon 610M
##     (two RDNA 2 compute units, a third of a 660M);
##   - an integrated adapter in a machine with under 8 GB of RAM, which the iGPU shares: the
##     world's texture arrays and streamed cells alone want about 2 GB of it.

const TYPE_NAMES := ["other", "integrated", "discrete", "virtual", "cpu"]
## RAM (GB) under which an integrated adapter is given Low.
const IGPU_RAM_FLOOR_GB := 8.0

## What `adapter()` returns instead of the machine's, for a test.
static var fake_adapter: Dictionary = {}
## What was decided at this launch, for the startup trace and the log: the verdict (`recommend`)
## and the adapter, and whether it was a first launch's ("first_launch"), or {} when nothing was.
static var decision: Dictionary = {}


## The running machine's graphics adapter as the verdict reads it.
static func adapter() -> Dictionary:
	if not fake_adapter.is_empty():
		return fake_adapter.duplicate()
	var mem := OS.get_memory_info()
	return {
		"type": RenderingServer.get_video_adapter_type(),
		"name": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"ram_gb": float(mem.get("physical", 0)) / 1073741824.0,
		# no Godot call gives a card's total; kept in the record so a later engine's can go here
		"vram_mb": -1,
	}


## What kind of adapter this is: "integrated", "discrete", "cpu", "virtual", or "unknown". The
## driver's type first; the name is a hint where the type is "other" (every adapter on the
## Compatibility renderer, and some drivers) and where a driver calls an APU "discrete" (an AMD
## APU's memory is the machine's, whatever the driver says).
static func kind_of(a: Dictionary) -> String:
	var t := int(a.get("type", 0))
	var label := _label(a)
	if t == RenderingDevice.DEVICE_TYPE_CPU or _software(label):
		return "cpu"
	var hint := _name_kind(label)
	match t:
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return "integrated"
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return "integrated" if hint == "integrated" else "discrete"
		RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			return "virtual"
	return hint if hint != "" else "unknown"


## The preset for this adapter, and why, in a sentence the trace and the settings screen show:
## {"preset": "low"|"medium"|"high", "kind": kind_of(), "why": String}.
static func recommend(a: Dictionary) -> Dictionary:
	var kind := kind_of(a)
	var label := _label(a)
	var ram := float(a.get("ram_gb", 0.0))
	var preset := "medium"
	var why := ""
	match kind:
		"cpu":
			preset = "low"
			why = "drawn in software by the CPU"
		"integrated":
			if label.contains("intel") and label.contains("hd graphics") and not label.contains("iris"):
				preset = "low"
				why = "an older Intel integrated graphics (HD/UHD)"
			elif label.contains("vega") or _radeon_small(label):
				preset = "low"
				why = "a small AMD integrated graphics (Vega, or a 610M's two compute units)"
			elif ram > 0.0 and ram < IGPU_RAM_FLOOR_GB:
				preset = "low"
				why = "integrated graphics sharing %.0f GB of memory" % ram
			else:
				why = "integrated graphics, sharing the machine's memory"
		"virtual":
			why = "a virtual graphics adapter"
		"discrete":
			preset = Graphics.DEFAULT_PRESET
			why = "a graphics card of its own"
		_:
			why = "the graphics adapter was not recognised; Medium is the safe middle"
	return {"preset": preset, "kind": kind, "why": why}


## The one line the startup trace and the log carry about the adapter and the verdict.
static func describe(a: Dictionary, verdict: Dictionary) -> String:
	var vram := int(a.get("vram_mb", -1))
	return "%s (%s, %s; %s; RAM %.1f GB; VRAM %s): %s -- %s" % [str(a.get("name", "?")), str(a.get("vendor", "?")),
			str(verdict.get("kind", "?")), str(a.get("renderer", "?")), float(a.get("ram_gb", 0.0)),
			("%d MB" % vram) if vram > 0 else "not known to Godot",
			str(Graphics.PRESET_LABELS.get(str(verdict.get("preset", "")), verdict.get("preset", ""))), str(verdict.get("why", ""))]


## Whether this run is a player's launch, the only kind a first-launch verdict is for: never a
## headless run, a test, a tool or the editor's debugger (the same rule as SafeMode's).
static func players_launch() -> bool:
	return not SafeMode.skips_check(OS.get_cmdline_user_args(), OS.get_cmdline_args(),
			DisplayServer.get_name() == "headless", EngineDebugger.is_active())


static func _label(a: Dictionary) -> String:
	return ("%s %s" % [str(a.get("vendor", "")), str(a.get("name", ""))]).to_lower()


static func _software(label: String) -> bool:
	for s in ["llvmpipe", "lavapipe", "softpipe", "swiftshader", "microsoft basic render"]:
		if label.contains(s):
			return true
	return false


## What the name says the adapter is, or "" when it says nothing.
static func _name_kind(label: String) -> String:
	if label.contains("nvidia") or label.contains("geforce") or label.contains("quadro") or label.contains("radeon rx") \
			or label.contains("radeon pro") or label.contains("radeon vii") or _intel_discrete(label):
		return "discrete"
	if label.contains("radeon(tm) graphics") or label.contains("radeon graphics") or label.contains("vega") \
			or _radeon_igpu_number(label) or label.contains("intel") or label.contains("apple") \
			or label.contains("adreno") or label.contains("mali"):
		return "integrated"
	return ""


## Intel's cards are "Arc(TM) A770" / "Arc B580"; its Core Ultra iGPUs are "Arc(TM) Graphics" or
## "Arc(TM) 140V GPU".
static func _intel_discrete(label: String) -> bool:
	if not label.contains("intel") or not label.contains("arc"):
		return false
	var re := RegEx.create_from_string("arc(\\(tm\\))?\\s+[ab]\\d{3}")
	return re.search(label) != null


## AMD's APUs named by number with no "RX": Radeon 610M, 660M, 680M, 740M, 760M, 780M, 880M,
## 890M, 8060S.
static func _radeon_igpu_number(label: String) -> bool:
	if not label.contains("radeon") or label.contains("radeon rx"):
		return false
	var re := RegEx.create_from_string("radeon(\\(tm\\))?\\s+\\d{3,4}[ms]\\b")
	return re.search(label) != null


## The Radeon 610M: two RDNA 2 compute units, about a third of a 660M's six.
static func _radeon_small(label: String) -> bool:
	return label.contains("610m")
