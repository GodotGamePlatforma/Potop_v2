#!/usr/bin/env python3
"""Tests for immutable cross-agent hand-off revisions."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = PROJECT_ROOT / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import freeze_workbench_revision as FREEZER  # noqa: E402


class FreezeWorkbenchRevisionTest(unittest.TestCase):
    def test_freeze_publishes_receipt_last_and_verify_accepts_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "mutable"
            target = root / "revision_r001"
            (source / "runtime").mkdir(parents=True)
            (source / "runtime" / "controller.gd").write_text(
                "extends Node\n", encoding="utf-8"
            )
            (source / "structure_manifest.json").write_text(
                "{}\n", encoding="utf-8"
            )

            receipt = FREEZER.freeze_revision(source, target, "test-thread")

            self.assertEqual(receipt["status"], "FROZEN")
            self.assertTrue((target / FREEZER.RECEIPT_NAME).is_file())
            self.assertEqual(
                FREEZER.verify_revision(target)["tree_sha256"],
                receipt["tree_sha256"],
            )

    def test_existing_target_is_never_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "mutable"
            target = root / "revision_r001"
            source.mkdir()
            target.mkdir()
            (source / "new.txt").write_text("new", encoding="utf-8")
            (target / "kept.txt").write_text("kept", encoding="utf-8")
            with self.assertRaises(FREEZER.FreezeError):
                FREEZER.freeze_revision(source, target, "test-thread")
            self.assertEqual((target / "kept.txt").read_text(), "kept")

    def test_mutation_or_extra_file_invalidates_frozen_revision(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "mutable"
            target = root / "revision_r001"
            source.mkdir()
            (source / "a.txt").write_text("a", encoding="utf-8")
            FREEZER.freeze_revision(source, target, "test-thread")
            (target / "a.txt").write_text("changed", encoding="utf-8")
            with self.assertRaises(FREEZER.FreezeError):
                FREEZER.verify_revision(target)

            (target / "a.txt").write_text("a", encoding="utf-8")
            (target / "extra.txt").write_text("extra", encoding="utf-8")
            with self.assertRaises(FREEZER.FreezeError):
                FREEZER.verify_revision(target)

    def test_transient_and_cache_directories_are_not_handoff_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "mutable"
            target = root / "revision_r001"
            source.mkdir()
            (source / "real.txt").write_text("real", encoding="utf-8")
            (source / "__pycache__").mkdir()
            (source / "__pycache__" / "cache.pyc").write_bytes(b"cache")
            (source / ".render.tmp-123").mkdir()
            (source / ".render.tmp-123" / "partial.bin").write_bytes(b"partial")

            receipt = FREEZER.freeze_revision(source, target, "test-thread")

            self.assertEqual(receipt["file_count"], 1)
            self.assertFalse((target / "__pycache__").exists())
            self.assertFalse((target / ".render.tmp-123").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
