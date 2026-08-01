#!/usr/bin/env python3
"""Compare a resized SlopNet screen with pyte using real recordings.

With no arguments this runs the two shrink boundaries from the recordings'
real capture geometry: 94x40 to 40x40, and 94x40 to 94x15. It also resizes
partway through the real chat recording and feeds the rest, so cursor commands
which arrive after a resize are checked rather than merely the clipped final
screen. A single recording and geometry can be supplied for investigating
another real capture:

    /tmp/refterm/bin/python tests/console_resize_oracle.py \
        tests/zellij_recording.bin 94 40 40 40

An optional final byte count stops both emulators at the same exact point in
that recording. The helper compiles into a temporary directory and leaves the
workspace untouched.
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RECORDINGS = (
    ROOT / "tests" / "agy_login_recording.bin",
    ROOT / "tests" / "agy_picker_recording.bin",
    ROOT / "tests" / "top_recording.bin",
    ROOT / "tests" / "zellij_recording.bin",
)
SPLIT_RECORDING = ROOT / "tests" / "agy_chat_recording.bin"
SPLIT_BYTE = 1014  # An ESC boundary before the recording's relative cursor moves.


def compile_picture(destination):
    subprocess.run(
        [
            "clang", "-fobjc-arc", "-Wall", "-Wextra",
            "-framework", "AppKit", "-framework", "CoreText",
            "-I", str(ROOT / "packaging"),
            str(ROOT / "tests" / "console_picture.m"),
            str(ROOT / "packaging" / "SlopNetConsole.m"),
            str(ROOT / "packaging" / "SlopNetBrand.m"),
            "-o", str(destination),
        ],
        check=True,
        cwd=ROOT,
    )


def printed_rows(text):
    rows = text.split("\n")
    if rows and rows[-1] == "":
        rows.pop()  # reference_screen.py prints one newline after its last row
    return rows


def compare_case(picture, temporary, recording, initial_columns, initial_rows,
                 final_columns, final_rows, byte_count, continue_after_resize=False):
    split = f" split@{byte_count}" if continue_after_resize else ""
    label = (f"{recording.name} {initial_columns}x{initial_rows}->"
             f"{final_columns}x{final_rows}{split}")
    screen_file = temporary / f"screen-{recording.stem}-{final_columns}x{final_rows}.txt"
    image_file = temporary / f"screen-{recording.stem}-{final_columns}x{final_rows}.png"
    environment = os.environ.copy()
    environment["SCREEN_FILE"] = str(screen_file)
    console_arguments = [
        str(picture), str(recording), str(image_file),
        str(initial_columns), str(initial_rows), str(byte_count),
        str(final_columns), str(final_rows),
    ]
    if continue_after_resize:
        console_arguments.append("continue")
    console = subprocess.run(
        console_arguments,
        cwd=ROOT,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if console.returncode != 0:
        print(f"FAIL {label}: console renderer exited {console.returncode}")
        return False

    reference_arguments = [
        sys.executable, str(ROOT / "tests" / "reference_screen.py"),
        str(recording), str(initial_columns), str(initial_rows),
        str(byte_count), str(final_columns), str(final_rows),
    ]
    if continue_after_resize:
        reference_arguments.append("continue")
    reference = subprocess.run(
        reference_arguments,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if reference.returncode != 0:
        print(f"FAIL {label}: pyte oracle exited {reference.returncode}")
        if reference.stderr.strip():
            print(reference.stderr.strip())
        return False

    actual = screen_file.read_text(encoding="utf-8").split("\n")
    expected = printed_rows(reference.stdout)
    if actual == expected:
        print(f"ok   {label}")
        return True

    many = min(len(actual), len(expected))
    row = next((index for index in range(many) if actual[index] != expected[index]), many)
    if row < many:
        got, wanted = actual[row], expected[row]
        upto = min(len(got), len(wanted))
        column = next((index for index in range(upto) if got[index] != wanted[index]), upto)
        print(f"FAIL {label}: first difference at row {row + 1}, column {column + 1}")
    else:
        print(f"FAIL {label}: row count is {len(actual)}, oracle has {len(expected)}")
    return False


def cases_from_arguments(arguments):
    if not arguments:
        for recording in DEFAULT_RECORDINGS:
            size = recording.stat().st_size
            yield recording, 94, 40, 40, 40, size, False
            yield recording, 94, 40, 94, 15, size, False
        yield SPLIT_RECORDING, 94, 40, 40, 40, SPLIT_BYTE, True
        return
    if len(arguments) not in (5, 6):
        raise SystemExit(
            "usage: console_resize_oracle.py "
            "[recording initial-columns initial-rows final-columns final-rows [bytes]]"
        )
    recording = Path(arguments[0]).resolve()
    byte_count = int(arguments[5]) if len(arguments) == 6 else recording.stat().st_size
    yield recording, *(int(value) for value in arguments[1:5]), byte_count, False


def main():
    cases = list(cases_from_arguments(sys.argv[1:]))
    with tempfile.TemporaryDirectory(prefix="slopnet-resize-oracle-") as directory:
        temporary = Path(directory)
        picture = temporary / "picture"
        compile_picture(picture)
        results = [compare_case(picture, temporary, *case) for case in cases]
    if all(results):
        print("RESIZE ORACLE DONE — all ok")
        return 0
    print(f"RESIZE ORACLE DONE — {results.count(False)} failed")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
