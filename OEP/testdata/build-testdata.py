#!/usr/bin/env python3
"""Build the OEP test game (original, all ages).

Creates the generated tone, optionally packs the folder into data.xp3 with the
OEP CLI, and prints a scan report so the result can be verified without an
engine.

    python3 build-testdata.py [--cli path/to/oep-cli] [--no-pack]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(HERE, "mini-vn")
DATA = os.path.join(GAME, "data")


def make_tone(path: str) -> bool:
    """Generate a short sine tone with ffmpeg (no third-party audio)."""
    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found: se.ogg will be skipped (the script handles it)", file=sys.stderr)
        return False
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "lavfi", "-i", "sine=frequency=660:duration=0.18",
        "-af", "afade=t=out:st=0.12:d=0.06,volume=0.25",
        "-c:a", "libvorbis", "-q:a", "3", path,
    ]
    try:
        subprocess.run(cmd, check=True)
        print("wrote", os.path.relpath(path, HERE))
        return True
    except (subprocess.CalledProcessError, OSError) as exc:
        print("could not generate the tone:", exc, file=sys.stderr)
        return False


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
    ap.add_argument("--no-pack", action="store_true", help="do not build data.xp3")
    args = ap.parse_args()

    os.makedirs(DATA, exist_ok=True)
    make_tone(os.path.join(DATA, "se.ogg"))

    xp3 = os.path.join(GAME, "data.xp3")
    cli = None if args.no_pack else find_cli(args.cli)
    if cli:
        subprocess.run([cli, "xp3", "pack", DATA, xp3], check=True)
    elif not args.no_pack:
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
