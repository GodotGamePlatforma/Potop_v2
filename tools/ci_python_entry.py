#!/usr/bin/env python3
"""Run one exact Python entry point without candidate-controlled startup paths.

The caller must use ``python -I -B``.  Sibling modules needed by a legacy
entry point are loaded from explicit absolute paths before the entry point is
executed.  No script or working-directory path is added to ``sys.path``.
"""

from __future__ import annotations

import importlib.util
import os
import re
import runpy
import sys
from pathlib import Path


MODULE_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")


class EntryPointError(RuntimeError):
    """Raised when the requested isolated entry point is ambiguous or unsafe."""


def _exact_file(value: str, *, label: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        raise EntryPointError(f"{label} must be an absolute path: {value!r}")
    if path.is_symlink():
        raise EntryPointError(f"{label} must not be a symlink: {path}")
    resolved = path.resolve(strict=True)
    if not resolved.is_file():
        raise EntryPointError(f"{label} must be one regular non-symlink file: {resolved}")
    return resolved


def _exact_directory(value: str, *, label: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        raise EntryPointError(f"{label} must be an absolute path: {value!r}")
    if path.is_symlink():
        raise EntryPointError(f"{label} must not be a symlink: {path}")
    resolved = path.resolve(strict=True)
    if not resolved.is_dir():
        raise EntryPointError(f"{label} must be one directory: {resolved}")
    return resolved


def _parse(
    argv: list[str],
) -> tuple[list[tuple[str, Path]], Path | None, list[Path], Path, list[str]]:
    preloads: list[tuple[str, Path]] = []
    seen_modules: set[str] = set()
    working_directory: Path | None = None
    path_executables: list[Path] = []
    index = 0
    while index < len(argv):
        token = argv[index]
        if token == "--cwd":
            if working_directory is not None or index + 1 >= len(argv):
                raise EntryPointError("--cwd requires exactly one absolute directory")
            working_directory = _exact_directory(argv[index + 1], label="cwd")
            index += 2
            continue
        if token == "--path-executable":
            if index + 1 >= len(argv):
                raise EntryPointError("--path-executable requires an absolute file")
            path_executables.append(
                _exact_file(argv[index + 1], label="path executable")
            )
            index += 2
            continue
        if token == "--preload":
            if index + 1 >= len(argv) or "=" not in argv[index + 1]:
                raise EntryPointError("--preload requires MODULE=ABSOLUTE_PATH")
            module_name, raw_path = argv[index + 1].split("=", 1)
            if MODULE_NAME.fullmatch(module_name) is None:
                raise EntryPointError(f"Invalid preload module name: {module_name!r}")
            if module_name in seen_modules:
                raise EntryPointError(f"Duplicate preload module: {module_name}")
            seen_modules.add(module_name)
            preloads.append(
                (module_name, _exact_file(raw_path, label=f"preload {module_name}"))
            )
            index += 2
            continue
        if token == "--script":
            if index + 1 >= len(argv):
                raise EntryPointError("--script requires an absolute path")
            script = _exact_file(argv[index + 1], label="script")
            remaining = argv[index + 2 :]
            if remaining[:1] == ["--"]:
                remaining = remaining[1:]
            return preloads, working_directory, path_executables, script, remaining
        raise EntryPointError(f"Unexpected launcher argument: {token!r}")
    raise EntryPointError("--script is required")


def _load_exact_module(module_name: str, path: Path) -> None:
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise EntryPointError(f"Cannot load exact module {module_name!r} from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)


def main(argv: list[str] | None = None) -> int:
    if sys.flags.isolated != 1 or not sys.flags.dont_write_bytecode:
        raise EntryPointError("Launcher requires python -I -B")
    preloads, working_directory, path_executables, script, script_arguments = _parse(
        list(sys.argv[1:] if argv is None else argv)
    )
    if working_directory is not None:
        os.chdir(working_directory)
    if path_executables:
        trusted_directories: list[str] = []
        for executable in path_executables:
            directory = str(executable.parent)
            if directory not in trusted_directories:
                trusted_directories.append(directory)
        existing_path = os.environ.get("PATH", "")
        os.environ["PATH"] = os.pathsep.join(
            [*trusted_directories, *([existing_path] if existing_path else [])]
        )
    for module_name, path in preloads:
        _load_exact_module(module_name, path)
    sys.argv = [str(script), *script_arguments]
    runpy.run_path(str(script), run_name="__main__")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EntryPointError as exc:
        print(f"CI_PYTHON_ENTRY_ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
