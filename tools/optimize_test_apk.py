"""Lossless APK container optimization. Output MUST be aligned and re-signed.
Build dependency: zopfli==0.4.3 (external, not included in the Android app).
The decompressed contents of every retained entry are verified unchanged.
"""
import argparse
import copy
from pathlib import Path
import zipfile
import zopfli.zlib


def optimize(source: Path, output: Path, iterations: int = 5):
    if source.resolve() == output.resolve():
        raise ValueError("Use a separate output path")
    original = zipfile._get_compressor
    current = ""

    class Deflate:
        def __init__(self):
            self.parts = []
        def compress(self, data):
            self.parts.append(data)
            return b""
        def flush(self):
            return zopfli.zlib.compress(b"".join(self.parts), numiterations=iterations)[2:-4]

    def compressor(kind, compresslevel=None):
        if current.endswith(".so") and kind == zipfile.ZIP_DEFLATED:
            return Deflate()
        return original(kind, compresslevel)

    retained = []
    try:
        zipfile._get_compressor = compressor
        with zipfile.ZipFile(source) as src, zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as dst:
            for entry in src.infolist():
                if entry.filename.startswith("META-INF/") and entry.filename.endswith((".RSA", ".SF", ".MF")):
                    continue  # Old signatures are invalid after container changes.
                current = entry.filename
                retained.append(current)
                dst.writestr(copy.copy(entry), src.read(current), compress_type=entry.compress_type, compresslevel=9)
    finally:
        zipfile._get_compressor = original
    with zipfile.ZipFile(source) as src, zipfile.ZipFile(output) as dst:
        if dst.testzip() is not None:
            raise ValueError("Invalid ZIP CRC")
        if any(src.read(name) != dst.read(name) for name in retained):
            raise ValueError("Entry contents changed")
    print("Unsigned optimized APK:", output, output.stat().st_size, "bytes")
    print("Run zipalign and apksigner with your own test keystore before installing.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--iterations", type=int, default=5)
    args = parser.parse_args()
    optimize(args.source, args.output, args.iterations)
