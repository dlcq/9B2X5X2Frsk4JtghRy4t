#!/usr/bin/env python3
"""Build the OEP test game (original, all ages).

Creates the generated tone, optionally packs the folder into data.xp3 with the
OEP CLI, and prints a scan report so the result can be verified without an
engine.

    python3 build-testdata.py [--cli path/to/oep-cli] [--no-pack]
"""
import argparse
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(HERE, "mini-vn")
DATA = os.path.join(GAME, "data")


def make_tone(path: str) -> bool:
    """Write a short sine beep as WAV (no external tools, no third-party audio)."""
    rate = 44100
    seconds = 0.18
    freq = 660.0
    frames = int(rate * seconds)
    data = bytearray()
    for i in range(frames):
        t = i / rate
        envelope = 1.0 if t < 0.12 else max(0.0, 1.0 - (t - 0.12) / 0.06)
        sample = int(0.25 * envelope * math.sin(2.0 * math.pi * freq * t) * 32767)
        data += struct.pack("<h", sample)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(bytes(data))
    print("wrote", os.path.relpath(path, HERE))
    return True


def find_cli(explicit):
    if explicit:
        return explicit
    for candidate in (
        os.path.join(HERE, "..", "core", "build", "oep-cli.exe"),
        os.path.join(HERE, "..", "core", "build", "oep-cli"),
    ):
        if os.path.exists(candidate):
            return os.path.abspath(candidate)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cli", help="path to the oep-cli binary")
    ap.add_argument("--pack", action="store_true",
                    help="also build data.xp3 (the bundled test game uses data/ directly)")
    ap.add_argument("--no-pack", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args()

    os.makedirs(DATA, exist_ok=True)
    make_tone(os.path.join(DATA, "se.wav"))

    xp3 = os.path.join(GAME, "data.xp3")
    cli = None if (args.no_pack or not args.pack) else find_cli(args.cli)
    if cli:
        subprocess.run([cli, "xp3", "pack", DATA, xp3], check=True)
    elif args.pack:
        print("oep-cli not found: skipping data.xp3 (the data/ folder is enough)", file=sys.stderr)

    if cli:
        out = subprocess.run([cli, "scan", GAME, "--json"], capture_output=True)
        text = out.stdout.decode("utf-8", "replace")
        try:
            report = json.loads(text)
            print("scan:", report["displayName"], report["engine"]["kind"],
                  report["supportLevel"], f'{len(report["archives"])} archive(s)')
        except json.JSONDecodeError:
            print(text)


if __name__ == "__main__":
    main()
