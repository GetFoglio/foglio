#!/usr/bin/env python3
"""Writes a small EMF (shapes, a path, text, a 2x2 bitmap) and a placeable WMF for the UI tests."""
import struct, sys

def rec(t, payload): return struct.pack('<II', t, 8 + len(payload)) + payload

def emf(path):
    body = b''
    body += rec(39, struct.pack('<IIII', 1, 0, 0x0030A0F0, 0))            # CREATEBRUSHINDIRECT #1 orange
    body += rec(38, struct.pack('<IIiiI', 2, 0, 4, 0, 0x00402010))        # CREATEPEN #2 dark blue, 4 units
    body += rec(37, struct.pack('<I', 1)) + rec(37, struct.pack('<I', 2))
    body += rec(42, struct.pack('<4i', 20, 20, 380, 280))                 # ELLIPSE
    body += rec(37, struct.pack('<I', 0x80000004))                        # BLACK_BRUSH
    pts = [(200, 40), (360, 260), (40, 260)]
    body += rec(86, struct.pack('<4iI', 40, 40, 360, 260, 3) + b''.join(struct.pack('<hh', *p) for p in pts))  # POLYGON16
    font = struct.pack('<5i8B', -40, 0, 0, 0, 700, 0, 0, 0, 0, 0, 0, 0, 0) + 'Arial'.encode('utf-16-le').ljust(64, b'\0')
    body += rec(82, struct.pack('<I', 3) + font) + rec(37, struct.pack('<I', 3))
    body += rec(24, struct.pack('<I', 0x00FFFFFF)) + rec(18, struct.pack('<I', 1))    # white text, transparent
    text = 'Foglio'.encode('utf-16-le')
    emrtext = struct.pack('<iiIII4iI', 150, 180, 6, 76, 0, 0, 0, 0, 0, 0)
    body += rec(84, struct.pack('<4iIff', 0, 0, 0, 0, 1, 1, 1) + emrtext + text)       # EXTTEXTOUTW
    bmi = struct.pack('<IiiHHIIiiII', 40, 2, 2, 1, 24, 0, 16, 0, 0, 0, 0)
    bits = bytes([0, 0, 255, 0, 255, 0, 0, 0]) + bytes([255, 0, 0, 255, 255, 255, 0, 0])
    sdib = struct.pack('<4i', 0, 0, 40, 40) + struct.pack('<iiiiiiIIIIIIii', 0, 0, 0, 0, 2, 2, 80, 40, 120, 16, 0, 0x00CC0020, 40, 40)
    body += rec(81, sdib + bmi + bits)                                    # STRETCHDIBITS
    body += rec(14, struct.pack('<III', 0, 16, 20))                       # EOF
    header = struct.pack('<4i4iIIIIHHIII2i2i', 0, 0, 400, 300, 0, 0, 10583, 7937, 0x464D4520, 0x10000,
                         0, 0, 4, 0, 0, 0, 0, 1920, 1080, 508, 286)
    header = rec(1, header)
    data = header + body
    recs = 0; off = 0
    while off < len(data): recs += 1; off += struct.unpack_from('<I', data, off + 4)[0]
    data = data[:48] + struct.pack('<II', len(data), recs) + data[56:]
    open(path, 'wb').write(data)

def wmf(path):
    def w(fn, *params): return struct.pack('<IH', 3 + len(params), fn) + struct.pack('<%dh' % len(params), *params)
    recs = w(0x020B, 0, 0) + w(0x020C, 600, 800)
    recs += struct.pack('<IH', 7, 0x02FC) + struct.pack('<H4BH', 0, 0x20, 0x80, 0xE0, 0, 0)   # blue brush
    recs += w(0x012D, 0) + w(0x041B, 500, 700, 100, 100)                                       # RECTANGLE
    recs += w(0x0000)
    header = struct.pack('<HHHIHIH', 1, 9, 0x300, 9 + len(recs) // 2, 1, 7, 0)
    place = struct.pack('<IH4hHI', 0x9AC6CDD7, 0, 0, 0, 800, 600, 144, 0)
    chk = 0
    for i in range(0, 20, 2): chk ^= struct.unpack_from('<H', place, i)[0]
    open(path, 'wb').write(place + struct.pack('<H', chk) + header + recs)

emf(sys.argv[1]); wmf(sys.argv[2])
