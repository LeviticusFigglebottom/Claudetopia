"""Blender scene helpers for the forge: clean scene, units, primitives, modifiers.

Conventions (CONTRACTS.md §1): metres, Z up in Blender, models face -Y; the glTF export
turns that into Y up / +Z facing in Godot. Every helper returns objects linked to the
scene collection, in object mode, with transforms applied unless stated otherwise.
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

TAU = math.tau


# --- scene ------------------------------------------------------------------------------

def reset(samples: int = 8) -> bpy.types.Scene:
    """Empty scene, metric units, Cycles CPU ready for baking."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.cycles.use_adaptive_sampling = False
    sc.render.bake.margin_type = "EXTEND"
    sc.render.bake.use_selected_to_active = False
    sc.render.bake.use_clear = True
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    sc.world = world
    return sc


def rng(seed: int) -> random.Random:
    return random.Random(seed)


def ensure_object_mode() -> None:
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")


def link(obj: bpy.types.Object) -> bpy.types.Object:
    if obj.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(obj)
    return obj


def select_only(objs) -> None:
    ensure_object_mode()
    objs = list(objs) if not isinstance(objs, bpy.types.Object) else [objs]
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def delete(objs) -> None:
    objs = list(objs) if not isinstance(objs, bpy.types.Object) else [objs]
    for o in objs:
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None and isinstance(data, bpy.types.Mesh) and data.users == 0:
            bpy.data.meshes.remove(data)


def all_mesh_objects() -> list:
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


# --- mesh construction ---------------------------------------------------------------------

def mesh_from_pydata(name: str, verts, faces, edges=(), mat=None, smooth: bool = True) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], list(edges), [tuple(f) for f in faces])
    me.update()
    me.validate()
    ob = bpy.data.objects.new(name, me)
    link(ob)
    if mat is not None:
        me.materials.append(mat)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    return ob


def bm_to_object(bm: bmesh.types.BMesh, name: str, mat=None, smooth: bool = True) -> bpy.types.Object:
    # Primitives come with a UV layer and bmesh geometry does not; joining the two would
    # otherwise leave half an object's faces at UV (0, 0). Give every mesh a layer.
    if not bm.loops.layers.uv:
        bm.loops.layers.uv.new("UVMap")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.update()
    ob = bpy.data.objects.new(name, me)
    link(ob)
    if mat is not None:
        me.materials.append(mat)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    return ob


def _finish_primitive(ob, name, location, rotation, scale, mat, smooth):
    ob.name = name
    ob.data.name = name
    if scale is not None:
        ob.scale = Vector(scale)
    if rotation is not None:
        ob.rotation_euler = Euler([math.radians(a) for a in rotation], "XYZ")
    if location is not None:
        ob.location = Vector(location)
    if mat is not None:
        ob.data.materials.append(mat)
    if smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
    return ob


def cube(name="cube", size=(1.0, 1.0, 1.0), location=(0, 0, 0), rotation=None, mat=None, smooth=False):
    """Box with its base at z=location.z (origin at the bottom centre)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    ob = bpy.context.active_object
    sx, sy, sz = size
    for v in ob.data.vertices:
        v.co = Vector((v.co.x * sx, v.co.y * sy, (v.co.z + 0.5) * sz))
    return _finish_primitive(ob, name, location, rotation, None, mat, smooth)


def box_centered(name="box", size=(1.0, 1.0, 1.0), location=(0, 0, 0), rotation=None, mat=None, smooth=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    ob = bpy.context.active_object
    sx, sy, sz = size
    for v in ob.data.vertices:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
    return _finish_primitive(ob, name, location, rotation, None, mat, smooth)


def cylinder(name="cyl", radius=0.5, depth=1.0, vertices=24, location=(0, 0, 0), rotation=None,
             radius_top=None, mat=None, smooth=True, cap="NGON", centered=False):
    """Cylinder or truncated cone standing on z=location.z (unless centered)."""
    r2 = radius if radius_top is None else radius_top
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=r2, depth=depth, end_fill_type=cap)
    ob = bpy.context.active_object
    if not centered:
        for v in ob.data.vertices:
            v.co.z += depth * 0.5
    return _finish_primitive(ob, name, location, rotation, None, mat, smooth)


def sphere(name="sphere", radius=0.5, subdivisions=3, location=(0, 0, 0), mat=None, smooth=True, scale=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius)
    ob = bpy.context.active_object
    return _finish_primitive(ob, name, location, None, scale, mat, smooth)


def uv_sphere(name="sphere", radius=0.5, segments=24, rings=12, location=(0, 0, 0), mat=None, smooth=True, scale=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius)
    ob = bpy.context.active_object
    return _finish_primitive(ob, name, location, None, scale, mat, smooth)


def torus(name="torus", major=0.5, minor=0.05, seg_major=32, seg_minor=8, location=(0, 0, 0), rotation=None, mat=None, smooth=True):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=seg_major, minor_segments=seg_minor)
    ob = bpy.context.active_object
    return _finish_primitive(ob, name, location, rotation, None, mat, smooth)


def plane(name="plane", size=(1.0, 1.0), location=(0, 0, 0), rotation=None, mat=None, subdiv=0):
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=subdiv + 1, y_subdivisions=subdiv + 1, size=1.0)
    ob = bpy.context.active_object
    sx, sy = size
    for v in ob.data.vertices:
        v.co = Vector((v.co.x * sx, v.co.y * sy, 0.0))
    return _finish_primitive(ob, name, location, rotation, None, mat, False)


def lathe(name, profile, segments=24, location=(0, 0, 0), mat=None, smooth=True, close=True, twist=0.0):
    """Revolve a 2D profile [(radius, z), ...] around Z. Radius 0 points make poles.
    Profiles run bottom to top; `close` caps the ends when the end radius is > 0."""
    bm = bmesh.new()
    rings = []
    for (r, z) in profile:
        ring = []
        if r <= 1e-6:
            ring = [bm.verts.new((0.0, 0.0, z))]
        else:
            for i in range(segments):
                a = TAU * i / segments + twist * z
                ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for i in range(segments):
                bm.faces.new((a[0], b[(i + 1) % segments], b[i]))
        elif len(b) == 1:
            for i in range(segments):
                bm.faces.new((a[i], a[(i + 1) % segments], b[0]))
        else:
            for i in range(segments):
                bm.faces.new((a[i], a[(i + 1) % segments], b[(i + 1) % segments], b[i]))
    if close:
        if len(rings[0]) > 1:
            bm.faces.new(list(reversed(rings[0])))
        if len(rings[-1]) > 1:
            bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    ob = bm_to_object(bm, name, mat, smooth)
    ob.location = Vector(location)
    return ob


def tube_along(name, points, radius=0.05, segments=8, radius_end=None, mat=None, smooth=True, cap=True):
    """Polyline swept with a circle: ropes, handles, vines, branches. `radius_end` tapers."""
    pts = [Vector(p) for p in points]
    if len(pts) < 2:
        raise ValueError("tube needs 2+ points")
    bm = bmesh.new()
    rings = []
    n = len(pts)
    up = Vector((0, 0, 1))
    prev_x = None
    for i, p in enumerate(pts):
        if i == 0:
            t = (pts[1] - pts[0]).normalized()
        elif i == n - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = ((pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()).normalized()
        if prev_x is None:
            ref = up if abs(t.dot(up)) < 0.9 else Vector((1, 0, 0))
            x = t.cross(ref).normalized()
        else:
            x = (prev_x - t * prev_x.dot(t)).normalized()
        y = t.cross(x).normalized()
        prev_x = x
        f = i / (n - 1)
        r = radius if radius_end is None else radius * (1 - f) + radius_end * f
        ring = [bm.verts.new(p + (x * math.cos(TAU * k / segments) + y * math.sin(TAU * k / segments)) * r) for k in range(segments)]
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(segments):
            bm.faces.new((a[k], a[(k + 1) % segments], b[(k + 1) % segments], b[k]))
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm_to_object(bm, name, mat, smooth)


def circle_points(radius, n, z=0.0, phase=0.0):
    return [(radius * math.cos(TAU * i / n + phase), radius * math.sin(TAU * i / n + phase), z) for i in range(n)]


# --- object operations -------------------------------------------------------------------

def apply_transforms(obj, location=True, rotation=True, scale=True) -> None:
    select_only([obj])
    bpy.ops.object.transform_apply(location=location, rotation=rotation, scale=scale)


def join(objs, name: str) -> bpy.types.Object:
    """Join several mesh objects into one (materials become slots). Transforms are applied."""
    objs = [o for o in objs if o is not None]
    if not objs:
        raise ValueError("join: nothing to join")
    for o in objs:
        apply_transforms(o)
    if len(objs) == 1:
        objs[0].name = name
        objs[0].data.name = name
        return objs[0]
    select_only(objs)
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    ob.data.name = name
    return ob


def duplicate(obj, name: str) -> bpy.types.Object:
    me = obj.data.copy()
    me.name = name
    ob = bpy.data.objects.new(name, me)
    ob.matrix_world = obj.matrix_world.copy()
    link(ob)
    return ob


## Blender 4.1 deleted auto-smooth. The forge was written against 4.0, where a smooth
## mesh carried `use_auto_smooth` plus an angle and the exporter worked the split normals
## out from it; in 4.1 and later that pair is gone and the same thing is said by marking
## the edges over the angle as sharp -- which is exactly what `shade_smooth_by_angle`
## does, and it writes a `sharp_edge` attribute the glTF exporter reads. So the angle
## still means what it meant, and every place the forge relies on it (a nine-sided billet
## staying faceted at 40 degrees, a millstone's furrow edge staying a hard step at 22)
## goes on working.
##
## This is not a graceful degradation and must not become one: the character forge's own
## copy of this call swallows the AttributeError, so under 4.2 everything it builds comes
## out fully smoothed with no threshold at all, and nothing says so.
# An RNA property is not a Python attribute of its type: `hasattr(bpy.types.Mesh,
# "use_auto_smooth")` is False even under 4.0.2, where the property exists, and sent every build
# on this machine's Blender to an operator 4.0 does not have.
_AUTO_SMOOTH = "use_auto_smooth" in bpy.types.Mesh.bl_rna.properties


def shade_smooth(obj, angle_deg: float = 35.0) -> None:
    me = obj.data
    for p in me.polygons:
        p.use_smooth = True
    if _AUTO_SMOOTH:                                     # Blender 4.0
        me.use_auto_smooth = True
        me.auto_smooth_angle = math.radians(angle_deg)
        return
    select_only([obj])                                   # Blender 4.1+
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle_deg), keep_sharp_edges=True)


def shade_flat(obj) -> None:
    for p in obj.data.polygons:
        p.use_smooth = False
    if _AUTO_SMOOTH:
        obj.data.use_auto_smooth = False
        return
    # A sharp-edge mark left by an earlier smooth pass says nothing once every face is
    # flat, but it travels through a join, so it is cleared rather than left to confuse.
    attrs = obj.data.attributes
    if "sharp_edge" in [a.name for a in attrs]:
        attrs.remove(attrs["sharp_edge"])


def tri_count(obj) -> int:
    if obj.type != "MESH":
        return 0
    return sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)


def bounds(objs):
    """World-space (min, max) Vectors over the given objects, modifiers included.

    An object's own bound box belongs to its *unmodified* mesh. A boolean that cuts the
    bottom off a sphere leaves a bound box still reaching down to where the sphere used to
    be, so grounding an asset from it drops the thing into the air -- which is exactly what
    happened to the Fallen Hand, whose palm is a dished sphere. Evaluating through the
    depsgraph costs a little and is always the geometry that will actually be exported.
    """
    objs = list(objs) if not isinstance(objs, bpy.types.Object) else [objs]
    dg = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        try:
            ev = o.evaluated_get(dg)
        except (RuntimeError, ReferenceError):
            ev = o
        mw = ev.matrix_world
        for c in ev.bound_box:
            w = mw @ Vector(c)
            lo.x, lo.y, lo.z = min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)
            hi.x, hi.y, hi.z = max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)
    return lo, hi


def radius_of(objs) -> float:
    lo, hi = bounds(objs)
    return max(0.05, (hi - lo).length * 0.5)


def add_modifier(obj, kind: str, name: str | None = None, **props):
    m = obj.modifiers.new(name or kind.lower(), kind)
    for k, v in props.items():
        setattr(m, k, v)
    return m


def apply_modifier(obj, mod) -> None:
    select_only([obj])
    bpy.ops.object.modifier_apply(modifier=mod.name)


def apply_all_modifiers(obj) -> None:
    select_only([obj])
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def bevel(obj, width=0.02, segments=2, angle_deg=30.0, clamp=True, profile=0.7) -> None:
    m = add_modifier(obj, "BEVEL", width=width, segments=segments, limit_method="ANGLE",
                     angle_limit=math.radians(angle_deg), use_clamp_overlap=clamp, profile=profile)
    m.harden_normals = False
    apply_modifier(obj, m)


def subdivide(obj, levels=1, simple=False) -> None:
    m = add_modifier(obj, "SUBSURF", levels=levels, render_levels=levels,
                     subdivision_type="SIMPLE" if simple else "CATMULL_CLARK")
    apply_modifier(obj, m)


def decimate(obj, ratio: float, planar_deg: float | None = None) -> None:
    if planar_deg is not None:
        m = add_modifier(obj, "DECIMATE", decimate_type="DISSOLVE", angle_limit=math.radians(planar_deg))
        apply_modifier(obj, m)
    if ratio < 0.999:
        m = add_modifier(obj, "DECIMATE", decimate_type="COLLAPSE", ratio=ratio, use_collapse_triangulate=True)
        apply_modifier(obj, m)


def solidify(obj, thickness=0.02, offset=-1.0) -> None:
    m = add_modifier(obj, "SOLIDIFY", thickness=thickness, offset=offset, use_even_offset=True)
    apply_modifier(obj, m)


def displace(obj, texture, strength=0.1, mid_level=0.5, direction="NORMAL", coords="LOCAL", vgroup: str | None = None) -> None:
    m = add_modifier(obj, "DISPLACE", texture=texture, strength=strength, mid_level=mid_level,
                     direction=direction, texture_coords=coords)
    if vgroup:
        m.vertex_group = vgroup
    apply_modifier(obj, m)


def boolean(obj, cutter, operation="DIFFERENCE", solver="EXACT", delete_cutter=True) -> None:
    m = add_modifier(obj, "BOOLEAN", operation=operation, object=cutter, solver=solver)
    apply_modifier(obj, m)
    if delete_cutter:
        delete([cutter])


def simple_deform(obj, method="TAPER", factor=0.3, axis="Z", angle_deg=None) -> None:
    m = add_modifier(obj, "SIMPLE_DEFORM", deform_method=method, deform_axis=axis)
    if method in ("BEND", "TWIST"):
        m.angle = math.radians(angle_deg if angle_deg is not None else factor)
    else:
        m.factor = factor
    apply_modifier(obj, m)


def new_texture(name: str, kind: str = "CLOUDS", **props):
    t = bpy.data.textures.new(name, kind)
    for k, v in props.items():
        setattr(t, k, v)
    return t


def jitter_verts(obj, amount=0.01, scale=0.3, seed=0) -> None:
    """Soft, low-frequency vertex displacement: the 'hand-made' asymmetry of props."""
    t = new_texture("jit_%d" % seed, "CLOUDS", noise_scale=scale, noise_depth=1, noise_basis="ORIGINAL_PERLIN")
    t.intensity = 1.0
    # offset by seed through a mapping trick: move the object, displace, move back
    off = Vector((seed * 7.31 % 13.0, seed * 3.17 % 11.0, seed * 1.93 % 7.0))
    obj.location += off
    apply_transforms(obj, location=True, rotation=False, scale=False)
    displace(obj, t, strength=amount, mid_level=0.5, direction="NORMAL", coords="GLOBAL")
    obj.location -= off
    apply_transforms(obj, location=True, rotation=False, scale=False)


def randomize_scale(obj, r: random.Random, pct=0.05) -> None:
    obj.scale = Vector((1 + r.uniform(-pct, pct), 1 + r.uniform(-pct, pct), 1 + r.uniform(-pct, pct)))
    apply_transforms(obj)


def tilt(obj, r: random.Random, max_deg=2.0) -> None:
    obj.rotation_euler = Euler((math.radians(r.uniform(-max_deg, max_deg)), math.radians(r.uniform(-max_deg, max_deg)),
                                math.radians(r.uniform(0, 360))), "XYZ")
    apply_transforms(obj)


def set_origin_bottom(obj) -> None:
    lo, hi = bounds([obj])
    cx = (lo.x + hi.x) * 0.5
    cy = (lo.y + hi.y) * 0.5
    for v in obj.data.vertices:
        v.co = obj.matrix_world @ v.co
    obj.matrix_world = Matrix.Identity(4)
    for v in obj.data.vertices:
        v.co -= Vector((cx, cy, lo.z))


def drop_to_ground(objs) -> None:
    objs = list(objs) if not isinstance(objs, bpy.types.Object) else [objs]
    lo, _ = bounds(objs)
    for o in objs:
        o.location.z -= lo.z
        apply_transforms(o)


def assign_material_to_faces(obj, mat, face_filter) -> None:
    """Add `mat` as a slot and assign it to faces where face_filter(polygon) is True."""
    if mat.name not in [m.name for m in obj.data.materials if m]:
        obj.data.materials.append(mat)
    idx = [m.name for m in obj.data.materials].index(mat.name)
    for p in obj.data.polygons:
        if face_filter(p):
            p.material_index = idx


def vertex_group_by_height(obj, name, z0, z1) -> str:
    """Weight 0 at z0 rising to 1 at z1 (object space), for masked displacement."""
    vg = obj.vertex_groups.new(name=name)
    for v in obj.data.vertices:
        w = (v.co.z - z0) / max(1e-6, (z1 - z0))
        vg.add([v.index], max(0.0, min(1.0, w)), "REPLACE")
    return name


def color_attribute(obj, name, fn) -> None:
    """Per-vertex colour attribute computed by fn(co: Vector) -> (r, g, b, a). Materials can
    read it through the Attribute node for painted-on masks (dirt, moss, wear)."""
    me = obj.data
    if name in me.color_attributes:
        me.color_attributes.remove(me.color_attributes[name])
    ca = me.color_attributes.new(name=name, type="FLOAT_COLOR", domain="POINT")
    for i, v in enumerate(me.vertices):
        ca.data[i].color = fn(v.co)
