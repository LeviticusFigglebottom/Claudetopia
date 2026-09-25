"""A quick front view of a painted head, ray-marched in numpy off the forge's own head field and
skin paint: for judging face paint without a Blender bake. Writes <out>.png (portrait) and
<out>_far.png (the same face at the size the Naming's whole figure shows it, blown up).

    python3 facepreview.py <out> [tone] [hair colour] [head: a character_forge HEAD_PRESETS name]"""
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(HERE))
import numpy as np
from PIL import Image
from forge.lib import rig, body as bodylib, paint, sdf

out = sys.argv[1]
tone = sys.argv[2] if len(sys.argv) > 2 else "wheat"
hair = sys.argv[3] if len(sys.argv) > 3 else "dark_brown"
N = 300
HS = None
if len(sys.argv) > 4 and sys.argv[4] != "default":
    import re
    src = (ROOT / "tools" / "forge" / "character_forge.py").read_text()
    block = src[src.index("HEAD_PRESETS"):]
    m = re.search(r'"%s":\s*(\{[^}]*\})' % re.escape(sys.argv[4]), block)
    HS = bodylib.HeadStyle.from_dict(eval(m.group(1)))

skel = rig.Skeleton(rig.Proportions())
L = bodylib.head_landmarks(skel, HS)
scene = bodylib.head_scene(skel, HS, with_neck=True)
field0 = sdf.SampledField(scene, spacing=0.0025, margin=0.04)
EYES = [np.array([sx * float(L["eye_x"]), float(L["eye_c_y"]), float(L["eye_z"])]) for sx in (1, -1)]
ER = float(L["eye_r"])


def eyes_d(P):
    return np.minimum(*[np.linalg.norm(P - c, axis=1) - ER for c in EYES])


class F:
    def eval(self, P):
        return np.minimum(field0.eval(P), eyes_d(P))


field = F()

zc = float(L["eye_z"]) - 0.035
xs = np.linspace(-0.11, 0.11, N)
zs = np.linspace(zc + 0.11, zc - 0.11, N)
X, Z = np.meshgrid(xs, zs)
O = np.stack([X.ravel(), np.full(X.size, float(L["face_y"]) - 0.20), Z.ravel()], axis=1)
D = np.array([0.0, 1.0, 0.0])
t = np.zeros(len(O))
hit = np.zeros(len(O), bool)
for _ in range(260):
    P = O + D * t[:, None]
    d = field.eval(P)
    hit |= d < 0.0004
    t = np.where(hit, t, t + np.clip(d * 0.9, 0.0005, 0.008))
    if np.all(hit | (t > 0.45)):
        break
P = O + D * t[:, None]
e = 0.0012
nrm = np.stack([field.eval(P + [e, 0, 0]) - field.eval(P - [e, 0, 0]),
                field.eval(P + [0, e, 0]) - field.eval(P - [0, e, 0]),
                field.eval(P + [0, 0, e]) - field.eval(P - [0, 0, e])], axis=1)
nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
fn = paint.skin_paint(L, tone, 0, face=True, brow_colour=hair, scene=scene, occ_radius=0.03)
col = np.zeros((len(P), 3))
col[hit] = fn(P[hit], nrm[hit])
on_eye = hit & (eyes_d(P) < 0.0008)
for c in EYES:
    q = P[on_eye] - c
    v = np.arccos(np.clip(-q[:, 1] / np.maximum(np.linalg.norm(q, axis=1), 1e-9), -1, 1)) / np.pi
    iris = np.array([0.35, 0.23, 0.12]) * 0.8
    e = np.where((v < 0.072)[:, None], np.array([0.03, 0.03, 0.03]),
                 np.where((v < 0.205)[:, None], iris, np.where((v < 0.224)[:, None], iris * 0.4, np.array([0.86, 0.83, 0.79]))))
    sel = np.linalg.norm(P[on_eye] - c, axis=1) < ER + 0.001
    idx = np.where(on_eye)[0][sel]
    col[idx] = e[sel]
key = np.array([0.45, -0.75, 0.50]); key /= np.linalg.norm(key)
fill = np.array([-0.6, -0.6, 0.1]); fill /= np.linalg.norm(fill)
lam = np.clip(nrm @ key, 0, 1) * 0.85 + np.clip((nrm @ key + 0.45) / 1.45, 0, 1) * 0.10 + np.clip(nrm @ fill, 0, 1) * 0.22 + 0.22
img = np.where(hit[:, None], np.clip(col * lam[:, None], 0, 1), np.array([0.55, 0.50, 0.44]))
img = (img.reshape(N, N, 3) * 255).astype(np.uint8)
Image.fromarray(img).save(out + ".png")
far = Image.fromarray(img).resize((30, 30), Image.LANCZOS).resize((N, N), Image.NEAREST)
far.save(out + "_far.png")
print("wrote", out)
