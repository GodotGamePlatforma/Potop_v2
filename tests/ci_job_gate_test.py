#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = REPO_ROOT / "tools" / "ci_job_gate.py"
SPEC = importlib.util.spec_from_file_location("ci_job_gate", TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
CI_JOB_GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI_JOB_GATE)


class CiJobGateTest(unittest.TestCase):
    def test_accepts_exact_all_green_dependency_set(self) -> None:
        payload = {
            "infra-contracts": {"result": "success", "outputs": {}},
            "prepare": {"result": "success", "outputs": {"plan": "abc"}},
            "shard": {"result": "success", "outputs": {}},
        }
        result = CI_JOB_GATE.verify_needs(
            payload, ["infra-contracts", "prepare", "shard"]
        )
        self.assertEqual(result["status"], "PASS")

    def test_rejects_failure_cancel_skip_and_unknown_results(self) -> None:
        for result in ("failure", "cancelled", "skipped", "mystery"):
            with self.subTest(result=result):
                with self.assertRaises(CI_JOB_GATE.GateError):
                    CI_JOB_GATE.verify_needs(
                        {"shard": {"result": result}}, ["shard"]
                    )

    def test_rejects_missing_or_unexpected_dependency(self) -> None:
        with self.assertRaises(CI_JOB_GATE.GateError):
            CI_JOB_GATE.verify_needs(
                {"prepare": {"result": "success"}}, ["prepare", "shard"]
            )
        with self.assertRaises(CI_JOB_GATE.GateError):
            CI_JOB_GATE.verify_needs(
                {
                    "prepare": {"result": "success"},
                    "untrusted": {"result": "success"},
                },
                ["prepare"],
            )

    def test_rejects_malformed_payload_and_required_ids(self) -> None:
        for payload in (None, [], "success"):
            with self.subTest(payload=payload):
                with self.assertRaises(CI_JOB_GATE.GateError):
                    CI_JOB_GATE.verify_needs(payload, ["prepare"])
        with self.assertRaises(CI_JOB_GATE.GateError):
            CI_JOB_GATE.verify_needs({}, [])
        with self.assertRaises(CI_JOB_GATE.GateError):
            CI_JOB_GATE.verify_needs(
                {"prepare": {"result": "success"}}, ["prepare", "prepare"]
            )

    def test_cli_is_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "needs.json"
            input_path.write_text(
                json.dumps({"prepare": {"result": "failure"}}), encoding="utf-8"
            )
            process = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(TOOL_PATH),
                    "verify-needs",
                    "--input",
                    str(input_path),
                    "--required",
                    "prepare",
                ],
                cwd=REPO_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(process.returncode, 1)
            self.assertIn("CI JOB GATE FAILED", process.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
