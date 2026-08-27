#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = REPO_ROOT / "tools" / "ci_map_check_receipt.py"
SPEC = importlib.util.spec_from_file_location("ci_map_check_receipt", TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
CI_MAP_CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI_MAP_CHECK)


def _run_git(repo: Path, *arguments: str) -> str:
    process = subprocess.run(
        ["git", "-C", str(repo), *arguments],
        text=True,
        capture_output=True,
        check=False,
    )
    if process.returncode != 0:
        raise AssertionError(process.stdout + process.stderr)
    return process.stdout.strip()


def _write_plan(path: Path, *, head: str, tree: str, snapshot: str = "a" * 64) -> None:
    body = "\n".join(
        (
            "version=godot-test-shard-plan-v1",
            f"source_head={head}",
            f"source_tree={tree}",
            "source_worktree_clean=1",
            f"source_status_digest={hashlib.sha256(b'').hexdigest()}",
            f"source_snapshot={snapshot}",
            f"runner_sha256={'b' * 64}",
            "target_count=55",
        )
    )
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
    path.write_text(f"canonical_sha256={digest}\n{body}\n", encoding="utf-8", newline="\n")


class MapCheckReceiptTest(unittest.TestCase):
    def _fixture(self, root: Path) -> tuple[Path, Path, Path, Path]:
        repo = root / "repo"
        repo.mkdir()
        for relative in CI_MAP_CHECK.REQUIRED_DEPENDENCIES:
            target = repo / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(f"# {relative}\n", encoding="utf-8")
        _run_git(repo, "init", "-q")
        _run_git(repo, "config", "user.email", "test@example.invalid")
        _run_git(repo, "config", "user.name", "CI Test")
        _run_git(repo, "add", ".")
        _run_git(repo, "commit", "-qm", "fixture")
        plan = root / "plan.receipt"
        log = root / "map-check.log"
        receipt = root / "map-check.receipt"
        _write_plan(
            plan,
            head=_run_git(repo, "rev-parse", "HEAD^{commit}"),
            tree=_run_git(repo, "rev-parse", "HEAD^{tree}"),
        )
        log.write_text("Map authority is current.\n", encoding="utf-8")
        return repo, plan, log, receipt

    def test_create_and_verify_bind_git_plan_dependencies_and_log(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ci_map_check_receipt_") as raw:
            repo, plan, log, receipt = self._fixture(Path(raw))
            created = CI_MAP_CHECK.create_receipt(repo, plan, log, receipt)
            verified = CI_MAP_CHECK.verify_receipt(repo, plan, log, receipt)
            self.assertEqual("PASS", created["status"])
            self.assertEqual(created, verified)
            self.assertEqual(55, int(CI_MAP_CHECK._plan_binding(plan)["target_count"]))

    def test_control_plane_authorization_is_bound_and_tamper_fails(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ci_map_check_authorization_") as raw:
            repo, plan, log, receipt = self._fixture(Path(raw))
            authorization = "c" * 64
            created = CI_MAP_CHECK.create_receipt(
                repo, plan, log, receipt, authorization
            )
            self.assertEqual(authorization, created["authorization_sha256"])
            verified = CI_MAP_CHECK.verify_receipt(
                repo, plan, log, receipt, authorization
            )
            self.assertEqual(created, verified)
            with self.assertRaises(CI_MAP_CHECK.MapCheckReceiptError):
                CI_MAP_CHECK.verify_receipt(repo, plan, log, receipt, "d" * 64)
            with self.assertRaises(CI_MAP_CHECK.MapCheckReceiptError):
                CI_MAP_CHECK.verify_receipt(repo, plan, log, receipt, "malformed")

    def test_log_dependency_plan_and_dirty_candidate_tamper_fail_closed(self) -> None:
        mutations = ("log", "dependency", "plan", "dirty")
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory(
                prefix="ci_map_check_tamper_"
            ) as raw:
                repo, plan, log, receipt = self._fixture(Path(raw))
                CI_MAP_CHECK.create_receipt(repo, plan, log, receipt)
                if mutation == "log":
                    log.write_text("different\n", encoding="utf-8")
                elif mutation == "dependency":
                    (repo / CI_MAP_CHECK.REQUIRED_DEPENDENCIES[0]).write_text(
                        "changed\n", encoding="utf-8"
                    )
                elif mutation == "plan":
                    text = plan.read_text(encoding="utf-8").replace(
                        "target_count=55", "target_count=54"
                    )
                    plan.write_text(text, encoding="utf-8", newline="\n")
                else:
                    (repo / "untracked.txt").write_text("dirty\n", encoding="utf-8")
                with self.assertRaises(CI_MAP_CHECK.MapCheckReceiptError):
                    CI_MAP_CHECK.verify_receipt(repo, plan, log, receipt)

    def test_cli_verification_is_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ci_map_check_cli_") as raw:
            repo, plan, log, receipt = self._fixture(Path(raw))
            created = subprocess.run(
                [
                    "python",
                    "-B",
                    str(TOOL_PATH),
                    "create",
                    "--repo",
                    str(repo),
                    "--plan",
                    str(plan),
                    "--log",
                    str(log),
                    "--receipt",
                    str(receipt),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, created.returncode, created.stdout + created.stderr)
            log.write_text("tampered\n", encoding="utf-8")
            verified = subprocess.run(
                [
                    "python",
                    "-B",
                    str(TOOL_PATH),
                    "verify",
                    "--repo",
                    str(repo),
                    "--plan",
                    str(plan),
                    "--log",
                    str(log),
                    "--receipt",
                    str(receipt),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(1, verified.returncode)
            self.assertIn("MAP CHECK RECEIPT FAILED", verified.stderr)

    def test_plan_duplicate_singleton_is_rejected_even_with_valid_envelope(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ci_map_check_duplicate_") as raw:
            _repo, plan, _log, _receipt = self._fixture(Path(raw))
            lines = plan.read_text(encoding="utf-8").splitlines()[1:]
            lines.insert(3, next(line for line in lines if line.startswith("source_head=")))
            body = "\n".join(lines)
            digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
            plan.write_text(
                f"canonical_sha256={digest}\n{body}\n",
                encoding="utf-8",
                newline="\n",
            )
            with self.assertRaises(CI_MAP_CHECK.MapCheckReceiptError):
                CI_MAP_CHECK._plan_binding(plan)


if __name__ == "__main__":
    unittest.main(verbosity=2)
