import os, sys, random
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from mgm_ref import mgm_encrypt, self_test, V_ICN, V_AAD, V_PT, TEST_KEY

self_test()
random.seed(9058)
rnd = lambda n: bytes(random.randrange(256) for _ in range(n))
lines = []
def rec(t, flags, data): lines.append("%02x%02x%032x" % (t, flags, data))
def blocks(b): return [b[i:i + 16] for i in range(0, len(b), 16)]
def word(blk, junk=False):
    pad = rnd(16 - len(blk)) if junk else bytes(16 - len(blk))
    return int.from_bytes(blk + pad, "big")

def case(icn, aad, pt, decrypt):
    ct, tag = mgm_encrypt(TEST_KEY, icn, aad, pt)
    src, dst = (ct, pt) if decrypt else (pt, ct)
    rec(1, 1 if decrypt else 0, int.from_bytes(icn, "big"))
    ab, sb = blocks(aad), blocks(src)
    for i, b in enumerate(ab):
        rec(2, len(b) | 0x20 | (0x40 if (i == len(ab) - 1 and not sb) else 0), word(b, True))
    for i, b in enumerate(sb):
        rec(2, len(b) | (0x40 if i == len(sb) - 1 else 0), word(b, True))
    db = blocks(dst)
    for i, b in enumerate(db):
        rec(3, len(b) | (0x40 if i == len(db) - 1 else 0), word(b))
    rec(4, 0, int.from_bytes(tag, "big"))
    rec(5, 0, 0)

n = 0
case(V_ICN, V_AAD, V_PT, False); case(V_ICN, V_AAD, V_PT, True); n += 2
shapes = [(0, 1), (1, 0), (16, 16), (15, 17), (17, 15), (0, 16), (16, 0), (8, 64), (20, 100),
          (41, 67), (0, 1500), (8, 1500), (33, 1), (1, 33), (48, 0), (0, 31), (12, 1438), (255, 255)]
for a, p in shapes:
    for d in (False, True):
        icn = bytes([random.randrange(128)]) + rnd(15)
        case(icn, rnd(a), rnd(p), d); n += 1
rec(0, 0, 0)
out = os.path.join(os.path.dirname(__file__), "mgm_cases.hex")
open(out, "w").write("\n".join(lines) + "\n")
print("wrote", out, ":", n, "cases,", len(lines), "records")
