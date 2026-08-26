#!/usr/bin/env python3
"""Small cross-process locks for shared-worktree promotion steps.

The lock files live in the operating-system temporary directory, so acquiring a
lock never dirties the repository.  Locks are scoped by the canonical checkout
path and released by the OS when the owning process exits unexpectedly.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
from pathlib import Path
from typing import BinaryIO


_SAFE_LOCK_NAME = re.compile(r"[a-z0-9][a-z0-9._-]{0,95}\Z")


class WorkspaceLockError(RuntimeError):
    """Raised when another process owns a requested workspace lock."""


def lock_name_for_path(prefix: str, path: str | Path) -> str:
    """Return a stable, non-sensitive lock name for one exact output path."""

    normalized = os.path.normcase(str(Path(path).resolve(strict=False)))
    digest = hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:20]
    return f"{prefix}-{digest}"


class InterprocessWorkspaceLock:
    """Exclusive, non-blocking lock shared by processes in one checkout."""

    def __init__(self, workspace_root: str | Path, name: str) -> None:
        if not _SAFE_LOCK_NAME.fullmatch(name):
            raise ValueError(
                "Lock name must be lowercase and contain only a-z, 0-9, '.', "
                "'_' or '-'."
            )
        self.workspace_root = Path(workspace_root).resolve(strict=False)
        self.name = name
        normalized_root = os.path.normcase(str(self.workspace_root))
        checkout_key = hashlib.sha256(
            normalized_root.encode("utf-8")
        ).hexdigest()[:20]
        self.path = (
            Path(tempfile.gettempdir())
            / "ostatni_pomost_workbench_locks"
            / checkout_key
            / f"{name}.lock"
        )
        self._handle: BinaryIO | None = None

    @property
    def acquired(self) -> bool:
        return self._handle is not None

    def acquire(self) -> "InterprocessWorkspaceLock":
        if self._handle is not None:
            return self
        self.path.parent.mkdir(parents=True, exist_ok=True)
        handle = self.path.open("a+b")
        handle.seek(0, os.SEEK_END)
        if handle.tell() == 0:
            handle.write(b"\0")
            handle.flush()
        handle.seek(0)
        try:
            self._lock_handle(handle)
        except OSError as error:
            owner = self._read_owner(handle)
            handle.close()
            owner_hint = f" Last owner record: {owner}." if owner else ""
            raise WorkspaceLockError(
                f"Workspace lock '{self.name}' is already active for "
                f"{self.workspace_root}.{owner_hint} Do not bypass it; retry "
                "after the current promotion/test window is released."
            ) from error
        self._handle = handle
        self._write_owner(handle)
        return self

    def release(self) -> None:
        handle = self._handle
        if handle is None:
            return
        self._handle = None
        try:
            handle.seek(0)
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.lockf(handle.fileno(), fcntl.LOCK_UN, 1)
        finally:
            handle.close()

    def __enter__(self) -> "InterprocessWorkspaceLock":
        return self.acquire()

    def __exit__(self, _exc_type: object, _exc: object, _traceback: object) -> None:
        self.release()

    @staticmethod
    def _lock_handle(handle: BinaryIO) -> None:
        if os.name == "nt":
            import msvcrt

            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl

            fcntl.lockf(
                handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB, 1
            )

    @staticmethod
    def _read_owner(handle: BinaryIO) -> str:
        try:
            handle.seek(1)
            payload = handle.read().decode("utf-8", errors="replace").strip()
            if not payload:
                return ""
            owner = json.loads(payload)
            return "thread={thread}, pid={pid}".format(
                thread=owner.get("thread", "unknown"),
                pid=owner.get("pid", "unknown"),
            )
        except (OSError, ValueError, json.JSONDecodeError):
            return ""

    @staticmethod
    def _write_owner(handle: BinaryIO) -> None:
        owner = {
            "thread": os.environ.get("CODEX_THREAD_ID", "external"),
            "pid": os.getpid(),
        }
        payload = json.dumps(owner, sort_keys=True).encode("utf-8")
        handle.seek(1)
        handle.truncate()
        handle.write(payload)
        handle.flush()


__all__ = [
    "InterprocessWorkspaceLock",
    "WorkspaceLockError",
    "lock_name_for_path",
]
