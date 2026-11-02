# Meshy image-to-3D for the rock art (render only, not game meshes):
# art/concept/<name>.jpg -> art/meshy/<name>.glb. MESHY_KEY in the environment,
# client from Delirium-Terminal/tools/meshy.py.
import os, sys
sys.path.insert(0, r"E:\mods\Delirium-Terminal\tools")
import meshy
from concurrent.futures import ThreadPoolExecutor

here = os.path.dirname(os.path.abspath(__file__))
names = sys.argv[1:] or ["quarry", "mine"]


def one(n):
    try:
        meshy.make(os.path.join(here, "meshy"), n, os.path.join(here, "concept", n + ".jpg"), 30000)
    except SystemExit:
        pass
    except Exception as e:
        print(n, "error", e, flush=True)


with ThreadPoolExecutor(2) as ex:
    list(ex.map(one, names))
print("balance", meshy.balance())
