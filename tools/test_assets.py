"""Synthetic parser regression tests; no original game files required."""
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from ta_assets import Archive, FormatError, lz77
from prepare_viewer import gaf_frame, model_3do, tnt_image


def fixture(payload=b'ABCABC', key=0, inner=False, compressed=True):
    name = b'a.bin\0'
    end = 52
    if compressed:
        packed = zlib.compress(payload)
        if inner:
            packed = bytes(((value ^ i) + i) & 255 for i, value in enumerate(packed))
        chunk = struct.pack('<IBBBIII', 0x48535153, 2, 2, int(inner), len(packed), len(payload), sum(packed)) + packed
        body = struct.pack('<I', len(chunk)) + chunk
    else:
        body = payload
    directory = struct.pack('<II', 1, 28) + struct.pack('<IIB', 37, 43, 0) + name
    directory += struct.pack('<IIB', end, len(payload), 2 if compressed else 0)
    header = struct.pack('<5I', 0x49504148, 0x10000, end, key, 20)
    tail = directory + body
    if key:
        transformed = ((key << 2) | (key >> 6)) & 255
        tail = bytes(value ^ ((i + 20) & 255) ^ transformed for i, value in enumerate(tail))
    return header + tail


class AssetsTest(unittest.TestCase):
    def archive(self, data):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        path = Path(temp.name) / 'sample.hpi'
        path.write_bytes(data)
        return Archive(path)

    def test_raw_and_zlib_with_encryption(self):
        for key in (0, 0x65):
            for inner in (False, True):
                for compressed in (False, True):
                    with self.subTest(key=key, inner=inner, compressed=compressed):
                        archive = self.archive(fixture(key=key, inner=inner, compressed=compressed))
                        self.assertEqual(archive.extract('A.BIN'), b'ABCABC')

    def test_corrupt_checksum_rejected(self):
        data = bytearray(fixture())
        data[-1] ^= 1
        with self.assertRaisesRegex(FormatError, 'checksum'):
            self.archive(data).extract('a.bin')

    def test_truncated_file_rejected(self):
        archive = self.archive(fixture()[:-1])
        with self.assertRaises(FormatError):
            archive.extract('a.bin')

    def test_directory_cycle_rejected(self):
        data = bytearray(fixture())
        struct.pack_into('<IIB', data, 28, 37, 20, 1)
        with self.assertRaisesRegex(FormatError, 'cycle'):
            self.archive(data)

    def test_lz77_back_reference(self):
        self.assertEqual(lz77(b'\x18ABC\x11\x00\x00\x00', 6), b'ABCABC')
        with self.assertRaises(FormatError):
            lz77(b'\x18ABC\x11\x00\x00\x00', 5)
        with self.assertRaises(FormatError):
            lz77(b'\x00A', 6)

    def test_gaf_transparency_repeat_literal(self):
        # Two transparent pixels, two repetitions of index 7, two literal pixels.
        row = bytes([5, 6, 7, 4, 8, 9])
        header = struct.pack('<HHhhBBHIII', 6, 1, 0, 0, 0, 1, 0, 0, 24, 0)
        data = header + struct.pack('<H', len(row)) + row
        palette = [channel for i in range(256) for channel in (i, i, i)]
        image, _, _ = gaf_frame(data, 0, palette)
        self.assertEqual([image.getpixel((x, 0)) for x in range(6)], [(0, 0, 0, 0), (0, 0, 0, 0),
                         (7, 7, 7, 255), (7, 7, 7, 255), (8, 8, 8, 255), (9, 9, 9, 255)])

    def test_tnt_tile_placement_and_palette(self):
        header = struct.pack('<16I', 0x2000, 4, 2, 64, 68, 100, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        data = header + struct.pack('<HH', 1, 0) + bytes(32) + bytes([3]) * 1024 + bytes([9]) * 1024
        image, info, heights = tnt_image(data, [i for i in range(256) for _ in range(3)])
        self.assertEqual(image.size, (64, 32))
        self.assertEqual(image.getpixel((0, 0)), 9)
        self.assertEqual(image.getpixel((32, 0)), 3)
        self.assertEqual(len(heights), 8)

    def test_bad_model_header_rejected(self):
        with self.assertRaises(FormatError):
            model_3do(bytes(52))


if __name__ == '__main__':
    unittest.main()
