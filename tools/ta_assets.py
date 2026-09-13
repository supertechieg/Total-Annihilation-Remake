"""Read TA HAPI archives. Offsets are validated before reading; installation is read-only.

Format reference: https://github.com/MHeasell/rwe/tree/master/src/rwe/io/hpi
This module implements the binary format in Python; it does not invoke RWE.
"""
from dataclasses import dataclass
from pathlib import Path
import struct
import zlib


class FormatError(ValueError):
    pass


def span(data, start, length):
    if start < 0 or length < 0 or start + length > len(data):
        raise FormatError(f'Invalid range {start}+{length} in {len(data)} bytes')
    return data[start:start + length]


def unpack(fmt, data, offset=0):
    return struct.unpack(fmt, span(data, offset, struct.calcsize(fmt)))


def lz77(data, expected):
    window = bytearray(4096)
    cursor = 1
    out = bytearray()
    position = 0
    while position < len(data):
        tag = data[position]
        position += 1
        for bit in range(8):
            if tag & (1 << bit):
                packed, = unpack('<H', data, position)
                position += 2
                offset, count = packed >> 4, (packed & 15) + 2
                if offset == 0:
                    if len(out) != expected:
                        raise FormatError('LZ77 ended before expected output length')
                    return bytes(out)
                if len(out) + count > expected:
                    raise FormatError('LZ77 output overflow')
                for _ in range(count):
                    value = window[offset]
                    out.append(value)
                    window[cursor] = value
                    offset, cursor = (offset + 1) & 4095, (cursor + 1) & 4095
            else:
                value = span(data, position, 1)[0]
                position += 1
                if len(out) >= expected:
                    raise FormatError('LZ77 literal overflow')
                out.append(value)
                window[cursor] = value
                cursor = (cursor + 1) & 4095
    raise FormatError('LZ77 missing end marker')


@dataclass(frozen=True)
class Entry:
    path: str
    offset: int
    size: int
    compression: int


class Archive:
    def __init__(self, path):
        self.path = Path(path)
        self.length = self.path.stat().st_size
        with self.path.open('rb') as stream:
            magic, version, directory_end, key, start = unpack('<5I', stream.read(20))
        if magic != 0x49504148 or version != 0x10000:
            raise FormatError(f'Unsupported HAPI header: {self.path}')
        if not 20 <= start <= directory_end <= min(self.length, 64 * 1024 * 1024):
            raise FormatError('Invalid archive directory bounds')
        self.key = ((key << 2) | ((key & 255) >> 6)) & 255
        directory = bytes(start) + self.read_at(start, directory_end - start)
        self.entries = {}
        visited = set()

        def walk(offset, prefix, depth):
            if depth > 64 or offset in visited:
                raise FormatError('Archive directory cycle or excessive depth')
            visited.add(offset)
            count, records = unpack('<II', directory, offset)
            span(directory, records, count * 9)
            for index in range(count):
                name_at, data_at, is_dir = unpack('<IIB', directory, records + index * 9)
                if not 0 <= name_at < len(directory):
                    raise FormatError('Invalid archive name pointer')
                end = directory.find(b'\0', name_at)
                if end < 0:
                    raise FormatError('Unterminated archive name')
                name = directory[name_at:end].decode('latin-1')
                if name in ('', '.', '..') or any(c in name for c in '/\\:\0'):
                    raise FormatError('Unsafe archive path component')
                full = prefix + name
                if is_dir == 1:
                    walk(data_at, full + '/', depth + 1)
                elif is_dir == 0:
                    file_at, size, compression = unpack('<IIB', directory, data_at)
                    if compression not in (0, 1, 2) or file_at > self.length:
                        raise FormatError('Invalid file entry')
                    if full.lower() in self.entries:
                        raise FormatError('Duplicate case-insensitive archive path')
                    self.entries[full.lower()] = Entry(full, file_at, size, compression)
                else:
                    raise FormatError('Invalid directory flag')
        walk(start, '', 0)

    def read_at(self, offset, size):
        if offset < 0 or size < 0 or offset + size > self.length:
            raise FormatError('Read outside archive')
        with self.path.open('rb') as stream:
            stream.seek(offset)
            data = stream.read(size)
        if len(data) != size:
            raise FormatError('Short archive read')
        if self.key:
            return bytes(value ^ ((offset + i) & 255) ^ self.key for i, value in enumerate(data))
        return data

    def extract(self, path):
        entry = self.entries[path.replace('\\', '/').lower()]
        if entry.size > 512 * 1024 * 1024:
            raise FormatError('Asset exceeds 512 MiB extraction limit')
        if entry.compression == 0:
            return self.read_at(entry.offset, entry.size)
        count = (entry.size + 65535) // 65536
        sizes = unpack('<' + 'I' * count, self.read_at(entry.offset, count * 4))
        position = entry.offset + count * 4
        out = bytearray()
        for chunk_size in sizes:
            chunk = self.read_at(position, chunk_size)
            magic, version, method, encrypted, packed_size, raw_size, checksum = unpack('<IBBBIII', chunk)
            if magic != 0x48535153 or version != 2:
                raise FormatError('Unsupported SQSH chunk header')
            if packed_size + 19 != chunk_size or raw_size > 65536 or raw_size > entry.size - len(out):
                raise FormatError('Invalid SQSH chunk size')
            payload = span(chunk, 19, packed_size)
            if sum(payload) & 0xffffffff != checksum:
                raise FormatError('SQSH checksum mismatch')
            if encrypted:
                payload = bytes(((value - i) ^ i) & 255 for i, value in enumerate(payload))
            if method == 0:
                decoded = payload
            elif method == 1:
                decoded = lz77(payload, raw_size)
            elif method == 2:
                decoder = zlib.decompressobj()
                decoded = decoder.decompress(payload, raw_size + 1)
                if not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
                    raise FormatError('Invalid zlib stream or excessive output')
            else:
                raise FormatError('Unsupported SQSH compression')
            if len(decoded) != raw_size:
                raise FormatError('SQSH decompressed length mismatch')
            out.extend(decoded)
            position += chunk_size
        if len(out) != entry.size:
            raise FormatError('Extracted asset length mismatch')
        return bytes(out)
