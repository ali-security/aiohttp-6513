import sys, brotli
from importlib.machinery import ExtensionFileLoader
our = ExtensionFileLoader('_brotli', sys.argv[1]).load_module()
print("module API:", [a for a in dir(our) if not a.startswith('__')])
LIMIT = 32 * 1024 * 1024
raw = b'\x00' * (256 * 1024 * 1024)
bomb = brotli.compress(raw)
print("bomb wire bytes:", len(bomb), "-> would expand to", len(raw))
full = brotli.decompress(bomb)                          # ORIGINAL: unbounded
print("ORIGINAL (unbounded) decompressed:", len(full), "bytes  [VULNERABLE]")
d = our.Decompressor()                                  # OURS: vendored, bounded per call
out = d.process(bomb, LIMIT + 1)                        # what DeflateBuffer feeds (limit+1)
print("OURS first-call output:", len(out), "bytes; can_accept_more_data:", d.can_accept_more_data())
assert len(out) < len(full), "ours must NOT fully expand the bomb in one shot"
assert len(out) > LIMIT, "ours exceeds limit on first call => DeflateBuffer raises ContentEncodingError"
print("RESULT: ORIGINAL fully expands to %d bytes (VULNERABLE);" % len(full))
print("        OURS stops at %d bytes in one call (> %d limit) => ContentEncodingError = PROTECTED" % (len(out), LIMIT))
print("        memory bounded to ~%d MiB instead of %d MiB" % (len(out)//(1024*1024), len(full)//(1024*1024)))
