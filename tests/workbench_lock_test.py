#!/usr/bin/env python3
"""Cross-process checks for shared-worktree promotion locks."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = PROJECT_ROOT / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from workbench_lock import (  # noqa: E402
    InterprocessWorkspaceLock,
    lock_name_for_path,
)


_CHILD_PROBE = """
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from workbench_lock import InterprocessWorkspaceLock, WorkspaceLockError
try:
    with InterprocessWorkspaceLock(Path(sys.argv[2]), sys.argv[3]):
        pass
except WorkspaceLockError:
    raise SystemExit(23)
"""

_CHILD_HOLD = """
import os
import sys
import time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from workbench_lock import InterprocessWorkspaceLock
lock = InterprocessWorkspaceLock(Path(sys.argv[2]), sys.argv[3])
lock.acquire()
Path(sys.argv[4]).write_text(str(os.getpid()), encoding="utf-8")
time.sleep(60)
"""


class WorkbenchLockTest(unittest.TestCase):
    def test_same_lock_is_exclusive_between_processes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            with InterprocessWorkspaceLock(workspace, "map-promotion"):
                result = subprocess.run(
                    [
                        sys.executable,
                        "-c",
                        _CHILD_PROBE,
                        str(TOOLS_DIR),
                        str(workspace),
                        "map-promotion",
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 23, result.stderr)

            result = subprocess.run(
                [
                    sys.executable,
                    "-c",
                    _CHILD_PROBE,
                    str(TOOLS_DIR),
                    str(workspace),
                    "map-promotion",
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_disjoint_locks_can_be_held_together(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            with InterprocessWorkspaceLock(workspace, "map-promotion"):
                with InterprocessWorkspaceLock(workspace, "freeze-revision-a"):
                    pass

    def test_process_death_releases_lock_without_deleting_stale_owner_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            ready = workspace / "holder.ready"
            holder = subprocess.Popen(
                [
                    sys.executable,
                    "-c",
                    _CHILD_HOLD,
                    str(TOOLS_DIR),
                    str(workspace),
                    "map-promotion",
                    str(ready),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            try:
                deadline = time.monotonic() + 5
                while not ready.is_file() and holder.poll() is None:
                    if time.monotonic() >= deadline:
                        self.fail("Lock holder did not reach the ready marker.")
                    time.sleep(0.01)
                if holder.poll() is not None:
                    stdout, stderr = holder.communicate(timeout=1)
                    self.fail(
                        "Lock holder exited before the ready marker: "
                        f"stdout={stdout!r} stderr={stderr!r}"
                    )
                self.assertEqual(int(ready.read_text(encoding="utf-8")), holder.pid)
                lock_path = InterprocessWorkspaceLock(
                    workspace, "map-promotion"
                ).path
                self.assertTrue(lock_path.is_file())

                holder.kill()
                holder.communicate(timeout=5)
                self.assertTrue(lock_path.is_file())
                self.assertIn(str(holder.pid), lock_path.read_text(errors="replace"))

                recovered = subprocess.run(
                    [
                        sys.executable,
                        "-c",
                        _CHILD_PROBE,
                        str(TOOLS_DIR),
                        str(workspace),
                        "map-promotion",
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                self.assertEqual(recovered.returncode, 0, recovered.stderr)
            finally:
                if holder.poll() is None:
                    holder.kill()
                holder.communicate(timeout=5)

    def test_path_lock_names_are_stable_and_do_not_expose_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "build" / "revision_01"
            first = lock_name_for_path("freeze-revision", target)
            second = lock_name_for_path("freeze-revision", target)
            self.assertEqual(first, second)
            self.assertRegex(first, r"^freeze-revision-[0-9a-f]{20}$")
            self.assertNotIn("revision_01", first)


if __name__ == "__main__":
    unittest.main(verbosity=2)
