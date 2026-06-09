import sys, brotli
from importlib.machinery import ExtensionFileLoader
so = sys.argv[1]
our = ExtensionFileLoader('_brotli', so).load_module()
print("module API:", [a for a in dir(our) if not a.startswith('__')])
print("Decompressor API:", [a for a in dir(our.Decompressor) if not a.startswith('__')])
LIMIT = 32 * 1024 * 1024
raw = b'\x00' * (256 * 1024 * 1024)          # 256 MiB bomb payload
bomb = brotli.compress(raw)
print("bomb wire bytes:", len(bomb), "-> expands to", len(raw))
full = brotli.decompress(bomb)               # ORIGINAL behavior: unbounded
print("ORIGINAL (unbounded) decompressed:", len(full), "bytes")
d = our.Decompressor()                        # OURS: vendored, bounded
bounded = None
for call in ("decompress", "process"):
    if hasattr(d, call):
        try:
            bounded = getattr(d, call)(bomb, LIMIT + 1)
        except TypeError:
            bounded = getattr(d, call)(bomb, max_length=LIMIT + 1)
        break
print("OURS (bounded) yielded:", len(bounded), "bytes (cap", LIMIT, ")")
assert len(bounded) <= LIMIT + 1, "NOT bounded!"
assert len(full) > LIMIT, "sanity"
print("RESULT: original expands to %d; ours capped <= %d  => FIX WORKS on macOS cp36" % (len(full), LIMIT + 1))
