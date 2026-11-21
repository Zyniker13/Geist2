#!/usr/bin/env python3
"""Enforce the per-target line-coverage threshold (decision 0008).

Reads the coverage data produced by
`swift test --enable-code-coverage --build-system native`
(.build/<triple>/debug/codecov/default.profdata), exports per-file line
summaries from the single unified test bundle SwiftPM links for the package,
aggregates them per package target, and fails if any gated target is below
the threshold.

A target whose machine code is instrumented (its objects carry a coverage
mapping) but that maps no executable lines — e.g. a module whose sources are
declarations only, like a constants-only version file — is counted as fully
covered. A target whose objects carry no coverage mapping at all is an
instrumentation failure and fails the gate; silence must never read as a
pass. Dependency sources under .build/checkouts are ignored.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

DEFAULT_THRESHOLD = 60
DEFAULT_TARGETS = ("BarCore", "BarRecipes", "BarModules")


def find_llvm_cov() -> str:
    """Locate llvm-cov: the Swift toolchain ships one on every platform."""
    try:
        out = subprocess.run(
            ["xcrun", "-f", "llvm-cov"], capture_output=True, text=True, check=True
        )
        return out.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    found = shutil_which("llvm-cov")
    if found:
        return found
    for candidate in ("/usr/share/swift/usr/bin/llvm-cov",):
        if Path(candidate).is_file():
            return candidate
    raise SystemExit("coverage_check: llvm-cov not found (xcrun, PATH, toolchain)")


def shutil_which(name: str):
    """Minimal shutil.which (kept local so the script has no unusual imports)."""
    import os

    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def find_build_dir() -> Path:
    """Return the debug build directory that holds codecov/default.profdata.

    The native SwiftPM layout is .build/<triple>/debug; accept any triple and
    require the coverage artifact so a stale or unrelated directory is never
    picked.
    """
    for candidate in sorted(Path(".build").glob("*/debug")):
        if (candidate / "codecov" / "default.profdata").is_file():
            return candidate
    raise SystemExit(
        "coverage_check: no .build/*/debug/codecov/default.profdata — run "
        "`swift test --enable-code-coverage --build-system native` first"
    )


def test_binaries(build_dir: Path):
    """Yield executable paths for the unified test bundle SwiftPM produced.

    On macOS an .xctest bundle is a directory with Contents/MacOS/<Name>;
    on Linux SwiftPM emits a plain executable file named <Name>.xctest.
    """
    for bundle in sorted(build_dir.glob("*.xctest")):
        if bundle.is_file():
            yield bundle
            continue
        inner = bundle / "Contents" / "MacOS" / bundle.stem
        if inner.is_file():
            yield inner


def aggregate_target_lines(llvm_cov: str, profdata: Path, binary: Path):
    """Return {target: (covered, total)} for one binary's coverage export."""
    export = subprocess.run(
        [llvm_cov, "export", "-summary-only", "--instr-profile", str(profdata), str(binary)],
        capture_output=True,
        text=True,
    )
    if export.returncode != 0:
        raise SystemExit(
            f"coverage_check: llvm-cov export failed for {binary}:\n{export.stderr}"
        )
    data = json.loads(export.stdout, strict=False)
    sums: dict[str, dict] = {}
    marker = "/Sources/"
    for section in data.get("data", []):
        for file in section.get("files", []):
            filename = file.get("filename", "")
            if marker not in filename:
                continue  # dependency checkouts and test sources
            target = filename.split(marker, 1)[1].split("/", 1)[0]
            lines = file["summary"]["lines"]
            agg = sums.setdefault(target, {"covered": 0, "total": 0})
            agg["covered"] += lines["covered"]
            agg["total"] += lines["count"]
    return sums


def is_instrumented(llvm_cov: str, profdata: Path, build_dir: Path, target: str) -> bool:
    """True when the target's own objects carry a coverage mapping.

    Probing with `llvm-cov report` distinguishes "compiled without coverage
    instrumentation" (hard failure) from "instrumented but no executable
    lines" (trivially covered).
    """
    objects = sorted((build_dir / f"{target}.build").glob("**/*.o"))
    if not objects:
        return False
    ok = True
    for obj in objects:
        report = subprocess.run(
            [llvm_cov, "report", "--instr-profile", str(profdata), str(obj)],
            capture_output=True,
            text=True,
        )
        if report.returncode != 0 and "no coverage data found" in report.stderr:
            ok = False
    return ok


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD)
    parser.add_argument("--targets", nargs="+", default=list(DEFAULT_TARGETS))
    parser.add_argument(
        "--build-dir", type=Path, default=None,
        help="SwiftPM debug build directory (default: auto-detected triple dir)",
    )
    args = parser.parse_args()

    build_dir = args.build_dir or find_build_dir()
    profdata = build_dir / "codecov" / "default.profdata"
    if not profdata.is_file():
        raise SystemExit(
            f"coverage_check: {profdata} missing — run "
            "`swift test --enable-code-coverage --build-system native` first"
        )
    binaries = list(test_binaries(build_dir))
    if not binaries:
        raise SystemExit("coverage_check: no .xctest bundles under " + str(build_dir))

    llvm_cov = find_llvm_cov()
    totals: dict[str, dict] = {}
    for binary in binaries:
        for target, agg in aggregate_target_lines(llvm_cov, profdata, binary).items():
            merged = totals.setdefault(target, {"covered": 0, "total": 0})
            merged["covered"] += agg["covered"]
            merged["total"] += agg["total"]

    failed = False
    for target in args.targets:
        agg = totals.get(target)
        if agg and agg["total"] > 0:
            pct = 100.0 * agg["covered"] / agg["total"]
            marker = "ok" if pct >= args.threshold else "LOW"
            print(f"coverage: {target}: {pct:.1f}% ({agg['covered']}/{agg['total']}) [{marker}]")
            if pct < args.threshold:
                failed = True
            continue
        if is_instrumented(llvm_cov, profdata, build_dir, target):
            print(f"coverage: {target}: fully covered (instrumented, 0 executable lines)")
        else:
            print(
                f"coverage: {target}: NO DATA — no instrumented code for the target "
                "in the test run"
            )
            failed = True

    if failed:
        print(
            f"coverage_check: threshold is {args.threshold:.0f}% per target "
            f"(decision 0008); it may be raised, never lowered"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
