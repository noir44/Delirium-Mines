# Renders a Meshy rock GLB as a 3x3 PZ object: one colour image and one
# cell-id mask of the whole rock, both 1536x1536 (4x of the 384x384 area the
# nine 2x frames cover). cut_rock.py then cuts them into the nine frames.
#   blender --background --factory-startup --python render_rock.py -- <model.glb> <rotation_deg> <out_prefix> [yaw] [foot] [max_h] [z_stretch]
#
# Same PZ camera as Delirium-Roads/art/render_meshy.py (ortho, elevation 30,
# azimuth 45, 90.51 px per unit at 2x). Blender x = PZ x (east), -y = PZ y
# (south). The rock fills cells x 0..3, -y 0..3; the anchor (north-west)
# cell's frame is the top middle of the image, its centre 32 px (2x) below
# the image centre. An orthographic camera makes every cell's frame a plain
# crop of this one image (cut_rock.py), so one render serves all nine.
# yaw turns the model so its work face looks to -Y (south); rotation then
# turns it to its facing (0 = S, 90 = E).
import bpy, sys, math, os
from mathutils import Vector, Euler, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
glb = os.path.abspath(argv[0])
rot = math.radians(float(argv[1]))
prefix = os.path.abspath(argv[2])
YAW = math.radians(float(argv[3])) if len(argv) > 3 else 0.0
FOOT = float(argv[4]) if len(argv) > 4 else 2.9
MAX_H = float(argv[5]) if len(argv) > 5 else 2.2
# Meshy rocks come out flat for a 3x3 footprint: stretch them upwards.
Z_STRETCH = float(argv[6]) if len(argv) > 6 else 1.4
SCALE = 4
SIZE = 384
PX_PER_UNIT = 128 / math.sqrt(2)

sc = bpy.context.scene
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

bpy.ops.import_scene.gltf(filepath=glb)
meshes = [o for o in sc.objects if o.type == "MESH"]
for o in [o for o in sc.objects if o.type != "MESH"]:
    bpy.data.objects.remove(o, do_unlink=True)

# Yaw first, then fit the turned model's bounds into the 3x3 footprint.
turn = Matrix.Rotation(YAW, 4, "Z")
pts = [turn @ o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
size = mx - mn
s = min(FOOT / max(size.x, size.y), MAX_H / (size.z * Z_STRETCH))
stretch = Matrix.Diagonal((1, 1, Z_STRETCH, 1))
fit = (Matrix.Translation(Vector((1.5, -1.5, 0))) @ Matrix.Rotation(rot, 4, "Z") @ stretch @ Matrix.Scale(s, 4)
       @ Matrix.Translation(Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))) @ turn)
for o in meshes:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = fit @ mw
    for slot in o.material_slots:
        m = slot.material
        if m and m.node_tree:
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Roughness"].default_value = 0.85
                bsdf.inputs["Metallic"].default_value = 0.0
print("FIT size", round(size.x * s, 3), round(size.y * s, 3), round(size.z * s * Z_STRETCH, 3))

cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.sensor_fit = "VERTICAL"
cam_data.ortho_scale = SIZE / PX_PER_UNIT
cam_data.shift_y = 32 / SIZE
cam = bpy.data.objects.new("Cam", cam_data)
sc.collection.objects.link(cam)
cam.rotation_euler = Euler((math.radians(60), 0, math.radians(45)))
m3 = cam.rotation_euler.to_matrix()
fwd, right, up = m3 @ Vector((0, 0, -1)), m3 @ Vector((1, 0, 0)), m3 @ Vector((0, 1, 0))
cam.location = Vector((0.5, -0.5, 0)) - fwd * 30
cam_data.clip_end = 100
sc.camera = cam

sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 3.8
sun = bpy.data.objects.new("Sun", sun_data)
sc.collection.objects.link(sun)
frm = (-right * 0.7 + up * 0.9 - fwd * 0.5).normalized()
sun.rotation_euler = (-frm).to_track_quat("-Z", "Y").to_euler()

# Fill from the right: an east work face sits on the shaded side.
fill_data = bpy.data.lights.new("Fill", "SUN")
fill_data.energy = 1.6
fill = bpy.data.objects.new("Fill", fill_data)
sc.collection.objects.link(fill)
frm2 = (right * 0.8 + up * 0.5 - fwd * 0.6).normalized()
fill.rotation_euler = (-frm2).to_track_quat("-Z", "Y").to_euler()

world = bpy.data.worlds.new("W")
sc.world = world
try:
    world.use_nodes = True
except Exception:
    pass
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.5

r = sc.render
r.engine = "CYCLES"
sc.cycles.device = "CPU"
r.resolution_x = SIZE * SCALE
r.resolution_y = SIZE * SCALE
r.resolution_percentage = 100
r.film_transparent = True
r.image_settings.file_format = "PNG"
r.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Standard"


def render(path, samples):
    sc.cycles.samples = samples
    r.filepath = path
    bpy.ops.render.render(write_still=True)


render(prefix + "_color.png", 64)

# Mask: every surface emits its cell, R = column (PZ x), G = row (PZ y),
# 0 / 0.214 / 1 linear = 0 / 0.5 / 1 in sRGB; cut_rock.py rounds them.
mat = bpy.data.materials.new("Mask")
try:
    mat.use_nodes = True
except Exception:
    pass
nt = mat.node_tree
for node in list(nt.nodes):
    nt.nodes.remove(node)
geo = nt.nodes.new("ShaderNodeNewGeometry")
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])
neg = nt.nodes.new("ShaderNodeMath")
neg.operation = "MULTIPLY"
neg.inputs[1].default_value = -1.0
nt.links.new(sep.outputs["Y"], neg.inputs[0])


def cell_level(socket):
    fl = nt.nodes.new("ShaderNodeMath")
    fl.operation = "FLOOR"
    nt.links.new(socket, fl.inputs[0])
    cl = nt.nodes.new("ShaderNodeClamp")
    cl.inputs["Min"].default_value = 0.0
    cl.inputs["Max"].default_value = 2.0
    nt.links.new(fl.outputs[0], cl.inputs["Value"])
    # 0, 1, 2 -> 0, 0.214, 1: f(v) = -0.072 v + 0.286 v^2
    sq = nt.nodes.new("ShaderNodeMath")
    sq.operation = "MULTIPLY"
    nt.links.new(cl.outputs[0], sq.inputs[0])
    nt.links.new(cl.outputs[0], sq.inputs[1])
    lin = nt.nodes.new("ShaderNodeMath")
    lin.operation = "MULTIPLY"
    nt.links.new(cl.outputs[0], lin.inputs[0])
    lin.inputs[1].default_value = -0.072
    out = nt.nodes.new("ShaderNodeMath")
    out.operation = "MULTIPLY_ADD"
    nt.links.new(sq.outputs[0], out.inputs[0])
    out.inputs[1].default_value = 0.286
    nt.links.new(lin.outputs[0], out.inputs[2])
    return out


comb = nt.nodes.new("ShaderNodeCombineXYZ")
nt.links.new(cell_level(sep.outputs["X"]).outputs[0], comb.inputs["X"])
nt.links.new(cell_level(neg.outputs[0]).outputs[0], comb.inputs["Y"])
comb.inputs["Z"].default_value = 1.0
emit = nt.nodes.new("ShaderNodeEmission")
nt.links.new(comb.outputs[0], emit.inputs["Color"])
outn = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(emit.outputs["Emission"], outn.inputs["Surface"])
for o in meshes:
    o.data.materials.clear()
    o.data.materials.append(mat)
sc.cycles.filter_width = 0.01
render(prefix + "_mask.png", 1)
print("RENDERED", prefix)
