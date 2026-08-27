#!/usr/bin/env python3
"""Fail-closed static contracts for the trusted GitHub integration workflows.

The module intentionally uses only the Python standard library.  It is not a
general YAML parser: it recognises the small workflow subset used by this
repository and fails closed on ambiguous action, permission, or job patterns.
"""

from __future__ import annotations

import re
import unittest
from dataclasses import dataclass
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS_ROOT = PROJECT_ROOT / ".github" / "workflows"
INTEGRATION_WORKFLOW = WORKFLOWS_ROOT / "agent-integration.yml"
CONTROLLER_WORKFLOW = WORKFLOWS_ROOT / "agent-auto-integrator.yml"
MAINTENANCE_WORKFLOW = WORKFLOWS_ROOT / "map-control-plane-maintenance.yml"
ATTESTER_ACTION = (
    "actions/create-github-app-token@"
    "bcd2ba49218906704ab6c1aa796996da409d3eb1"
)

_USES_RE = re.compile(r"^\s*(?:-\s*)?uses\s*:\s*(?P<value>.+?)\s*$", re.IGNORECASE)
_PINNED_ACTION_RE = re.compile(
    r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*@"
    r"(?P<sha>[0-9A-Fa-f]{40})$"
)
_YAML_KEY_RE = re.compile(
    r"^(?P<indent> *)(?P<key>[A-Za-z0-9_-]+)\s*:\s*(?P<value>.*)$"
)
_TRUE_RE = r"(?:true|yes|on)"


@dataclass(frozen=True)
class ActiveLine:
    number: int
    indent: int
    text: str
    stripped: str


@dataclass(frozen=True)
class JobBlock:
    job_id: str
    header: ActiveLine
    lines: tuple[ActiveLine, ...]

    @property
    def text(self) -> str:
        return "\n".join(line.text for line in self.lines)


def _strip_yaml_comment(raw_line: str) -> str:
    single_quoted = False
    double_quoted = False
    escaped = False
    for index, character in enumerate(raw_line):
        if escaped:
            escaped = False
            continue
        if character == "\\" and double_quoted:
            escaped = True
            continue
        if character == "'" and not double_quoted:
            single_quoted = not single_quoted
            continue
        if character == '"' and not single_quoted:
            double_quoted = not double_quoted
            continue
        if (
            character == "#"
            and not single_quoted
            and not double_quoted
            and (index == 0 or raw_line[index - 1].isspace())
        ):
            return raw_line[:index].rstrip()
    return raw_line.rstrip()


def _active_lines(text: str) -> list[ActiveLine]:
    active: list[ActiveLine] = []
    for number, raw_line in enumerate(text.splitlines(), start=1):
        indentation = raw_line[: len(raw_line) - len(raw_line.lstrip())]
        if "\t" in indentation:
            active.append(ActiveLine(number, -1, raw_line, raw_line.strip()))
            continue
        without_comment = _strip_yaml_comment(raw_line)
        if not without_comment.strip():
            continue
        indent = len(without_comment) - len(without_comment.lstrip(" "))
        active.append(
            ActiveLine(number, indent, without_comment, without_comment.strip())
        )
    return active


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def _mapping_value(line: ActiveLine, key: str) -> str | None:
    match = _YAML_KEY_RE.match(line.text)
    if match is None or match.group("key").lower() != key.lower():
        return None
    return _unquote(match.group("value"))


def _block_after(lines: list[ActiveLine], start_index: int) -> list[ActiveLine]:
    start = lines[start_index]
    block: list[ActiveLine] = []
    for line in lines[start_index + 1 :]:
        if line.indent <= start.indent:
            break
        block.append(line)
    return block


def _step_block(lines: list[ActiveLine], uses_index: int) -> list[ActiveLine]:
    start = lines[uses_index]
    block: list[ActiveLine] = []
    for line in lines[uses_index + 1 :]:
        if line.indent < start.indent:
            break
        if line.indent == start.indent and line.stripped.startswith("-"):
            break
        block.append(line)
    return block


def _jobs(lines: list[ActiveLine]) -> list[JobBlock]:
    jobs_indices = [
        index
        for index, line in enumerate(lines)
        if line.indent == 0 and _mapping_value(line, "jobs") is not None
    ]
    if len(jobs_indices) != 1:
        return []
    jobs_index = jobs_indices[0]
    jobs_block = _block_after(lines, jobs_index)
    mapping_lines = [line for line in jobs_block if _YAML_KEY_RE.match(line.text)]
    if not mapping_lines:
        return []
    job_indent = min(line.indent for line in mapping_lines)
    records: list[JobBlock] = []
    for index, line in enumerate(lines):
        if index <= jobs_index or line not in jobs_block or line.indent != job_indent:
            continue
        match = _YAML_KEY_RE.match(line.text)
        if match is None:
            continue
        records.append(
            JobBlock(
                job_id=match.group("key"),
                header=line,
                lines=tuple(_block_after(lines, index)),
            )
        )
    return records


def _find_job(lines: list[ActiveLine], job_id: str) -> JobBlock | None:
    matches = [job for job in _jobs(lines) if job.job_id == job_id]
    return matches[0] if len(matches) == 1 else None


def _direct_property(job: JobBlock, key: str) -> str | None:
    if not job.lines:
        return None
    direct_indent = min(line.indent for line in job.lines)
    matches = [
        value
        for line in job.lines
        if line.indent == direct_indent
        and (value := _mapping_value(line, key)) is not None
    ]
    return matches[0] if len(matches) == 1 else None


def _permissions_mapping(
    lines: list[ActiveLine], declaration_index: int
) -> tuple[dict[str, str] | None, str | None]:
    declaration = lines[declaration_index]
    inline = _mapping_value(declaration, "permissions")
    if inline == "{}":
        return {}, None
    if inline:
        return None, f"line {declaration.number}: ambiguous inline permissions {inline!r}"

    block = _block_after(lines, declaration_index)
    if not block:
        return None, f"line {declaration.number}: empty permissions mapping"
    direct_indent = min(line.indent for line in block)
    mapping: dict[str, str] = {}
    for line in block:
        if line.indent != direct_indent:
            continue
        match = _YAML_KEY_RE.match(line.text)
        if match is None:
            return None, f"line {line.number}: ambiguous permissions entry"
        mapping[match.group("key").lower()] = _unquote(match.group("value")).lower()
    return mapping, None


def _job_permissions(
    all_lines: list[ActiveLine], job: JobBlock
) -> tuple[dict[str, str] | None, str | None]:
    if not job.lines:
        return None, None
    direct_indent = min(line.indent for line in job.lines)
    candidates = [
        line
        for line in job.lines
        if line.indent == direct_indent
        and _mapping_value(line, "permissions") is not None
    ]
    if not candidates:
        return None, None
    if len(candidates) != 1:
        return None, f"line {job.header.number}: duplicate job permissions"
    return _permissions_mapping(all_lines, all_lines.index(candidates[0]))


def _is_runner_temp_path(value: str) -> bool:
    value = _unquote(value).strip()
    if not re.match(r"^\$\{\{\s*runner\.temp\s*\}\}(?:[/\\]|$)", value, re.I):
        return False
    lowered = value.lower()
    if "github.workspace" in lowered or "github_workspace" in lowered:
        return False
    suffix = re.sub(
        r"^\$\{\{\s*runner\.temp\s*\}\}", "", value, count=1, flags=re.I
    )
    return ".." not in re.split(r"[/\\]+", suffix)


def _audit_actions(lines: list[ActiveLine]) -> list[str]:
    violations: list[str] = []
    for index, line in enumerate(lines):
        if re.search(r"\bpull_request_target\b", line.stripped, re.I):
            violations.append(f"line {line.number}: pull_request_target is forbidden")
        if re.search(r"\bself-hosted\b", line.stripped, re.I):
            violations.append(f"line {line.number}: self-hosted runners are forbidden")
        if re.search(
            rf"\blfs\s*:\s*['\"]?{_TRUE_RE}['\"]?\b", line.stripped, re.I
        ):
            violations.append(f"line {line.number}: checkout lfs: true is forbidden")
        if re.search(
            rf"\bpersist-credentials\s*:\s*['\"]?{_TRUE_RE}['\"]?\b",
            line.stripped,
            re.I,
        ):
            violations.append(
                f"line {line.number}: checkout persist-credentials: true is forbidden"
            )

        uses_match = _USES_RE.match(line.text)
        if uses_match is None and re.search(
            r"(?:^|[,\s{-])uses\s*:", line.stripped, re.I
        ):
            violations.append(
                f"line {line.number}: ambiguous uses declaration is forbidden"
            )
            continue
        if uses_match is None:
            continue
        action = _unquote(uses_match.group("value"))
        if not action.startswith("./") and _PINNED_ACTION_RE.fullmatch(action) is None:
            violations.append(
                f"line {line.number}: external action must be pinned to a full "
                f"40-hex SHA: {action!r}"
            )
        if action.lower().startswith("actions/download-artifact@"):
            step = _step_block(lines, index)
            paths = [
                value
                for step_line in step
                if step_line.indent > line.indent
                and (value := _mapping_value(step_line, "path")) is not None
            ]
            if len(paths) != 1 or not _is_runner_temp_path(paths[0]):
                violations.append(
                    f"line {line.number}: download-artifact needs one explicit path "
                    "under ${{ runner.temp }}"
                )
            artifact_ids = [
                value
                for step_line in step
                if step_line.indent > line.indent
                and (value := _mapping_value(step_line, "artifact-ids")) is not None
            ]
            if len(artifact_ids) != 1 or not _unquote(artifact_ids[0]).strip():
                violations.append(
                    f"line {line.number}: download-artifact must bind exactly one "
                    "non-empty artifact-ids input"
                )
            for forbidden_key in ("name", "pattern", "merge-multiple"):
                if any(
                    step_line.indent > line.indent
                    and _mapping_value(step_line, forbidden_key) is not None
                    for step_line in step
                ):
                    violations.append(
                        f"line {line.number}: download-artifact must not select by "
                        f"{forbidden_key!r}; exact artifact IDs are required"
                    )
    return violations


def _audit_permissions(lines: list[ActiveLine]) -> list[str]:
    violations: list[str] = []
    top_level = [
        index
        for index, line in enumerate(lines)
        if line.indent == 0 and _mapping_value(line, "permissions") is not None
    ]
    if len(top_level) != 1:
        return ["workflow must declare exactly one top-level permissions mapping"]

    top_permissions, error = _permissions_mapping(lines, top_level[0])
    if error:
        violations.append(error)
    elif top_permissions is not None:
        for scope, access in top_permissions.items():
            if access not in {"read", "none"}:
                violations.append(
                    f"line {lines[top_level[0]].number}: top-level permission "
                    f"{scope!r} must be read/none, not {access!r}"
                )

    for line in lines:
        if re.search(r"\bpermissions\s*:\s*write-all\b", line.stripped, re.I):
            violations.append(f"line {line.number}: write-all permissions are forbidden")

    for job in _jobs(lines):
        permissions, job_error = _job_permissions(lines, job)
        if job_error:
            violations.append(job_error)
            continue
        if permissions is None:
            continue
        checkout = bool(re.search(r"(?mi)^\s*(?:-\s*)?uses:\s*actions/checkout@", job.text))
        writable = sorted(scope for scope, access in permissions.items() if access == "write")
        if checkout and writable:
            violations.append(
                f"line {job.header.number}: job {job.job_id!r} combines checkout "
                f"with write permissions: {', '.join(writable)}"
            )
    return violations


def _audit_ordinary_check_jobs(lines: list[ActiveLine]) -> list[str]:
    violations: list[str] = []
    jobs = _jobs(lines)
    identifiers = [job.job_id for job in jobs]
    for job_id in sorted(set(identifiers)):
        if identifiers.count(job_id) > 1:
            violations.append(f"duplicate YAML job id {job_id!r}")
    for job in jobs:
        if job.job_id.lower() == "integration-green":
            violations.append(
                f"line {job.header.number}: integration-green cannot be an ordinary job id"
            )
        name = _direct_property(job, "name")
        if name is not None and name.lower() == "integration-green":
            violations.append(
                f"line {job.header.number}: integration-green cannot be an ordinary job name"
            )
    return violations


def _audit_trusted_preflight(lines: list[ActiveLine]) -> list[str]:
    preflight = _find_job(lines, "trust-preflight")
    if preflight is None:
        return ["integration workflow must define the trusted trust-preflight job"]
    required = (
        "path: trusted-control",
        "path: candidate",
        "$trustedHead -cne $baseSha",
        "$candidateHead -cne $targetSha",
        'Join-Path $trustedRepository "tools/ci_protected_paths.py"',
        'Join-Path $trustedRepository "tools/ci_branch_owner.py"',
        'Join-Path $trustedRepository "tools/workbench_contract.py"',
        "--expected-head $targetSha",
        "--expected-base $baseSha",
    )
    return [
        f"line {preflight.header.number}: trusted preflight is missing {item!r}"
        for item in required
        if item not in preflight.text
    ]


def _audit_trusted_execution(lines: list[ActiveLine]) -> list[str]:
    violations: list[str] = []
    for job_id in (
        "infra-contracts",
        "prepare-lfs-plan",
        "shard",
        "aggregate-attestation",
    ):
        job = _find_job(lines, job_id)
        if job is None:
            violations.append(f"trusted execution job is missing: {job_id}")
            continue
        for required in (
            "path: trusted-control",
            "path: candidate",
            "needs.trust-preflight.outputs.base-sha",
            "needs.trust-preflight.outputs.target-sha",
        ):
            if required not in job.text:
                violations.append(
                    f"line {job.header.number}: {job_id} is missing {required!r}"
                )
        if "python -B" in job.text or re.search(r'@\(\s*"-B"', job.text):
            violations.append(
                f"line {job.header.number}: {job_id} permits candidate Python startup hooks"
            )
        if re.search(r"python\s+-I\s+-B\s+(?:tools|tests)[/\\]", job.text):
            violations.append(
                f"line {job.header.number}: {job_id} executes a candidate-relative control script"
            )

    for job_id in ("prepare-lfs-plan", "shard", "aggregate-attestation"):
        job = _find_job(lines, job_id)
        if job is None:
            continue
        if '(Join-Path $trustedRoot "tests/run_all_tests.ps1")' not in job.text:
            violations.append(
                f"line {job.header.number}: {job_id} must execute the trusted runner"
            )
        if "-SourceRepositoryPath $candidateRoot" not in job.text:
            violations.append(
                f"line {job.header.number}: {job_id} must pass the candidate as data"
            )

    aggregate = _find_job(lines, "aggregate-attestation")
    if aggregate is not None and "-GodotConsolePath" in aggregate.text:
        violations.append("aggregate-attestation must not execute candidate Godot code")
    return violations


def _audit_controller(lines: list[ActiveLine], workflow_text: str) -> list[str]:
    violations: list[str] = []
    if not re.search(r"(?m)^permissions:\s*\{\}\s*$", workflow_text):
        violations.append("default-branch controller must use global permissions: {}")
    controller_actions = re.findall(
        r"(?mi)^\s*(?:-\s*)?uses\s*:\s*(\S+)", workflow_text
    )
    if controller_actions != [ATTESTER_ACTION]:
        violations.append(
            "default-branch controller may use only the pinned attester-token action"
        )
    if "actions/checkout" in workflow_text:
        violations.append("default-branch controller cannot check out repository content")

    for job_id, action in (
        ("admit-handoff", "integrate-agent-handoff"),
        ("merge-handoff", "complete-agent-handoff"),
    ):
        job = _find_job(lines, job_id)
        if job is None:
            violations.append(f"controller job is missing: {job_id}")
            continue
        if action not in job.text:
            violations.append(f"line {job.header.number}: {job_id} has no exact event guard")
        if "vars.AUTO_INTEGRATOR_ENABLED == 'true'" not in job.text:
            violations.append(f"line {job.header.number}: {job_id} is not AUTO OFF guarded")

    admit = _find_job(lines, "admit-handoff")
    if admit is not None and re.search(
        r"github\.event\.client_payload\.[A-Za-z0-9_]*receipt[A-Za-z0-9_]*",
        admit.text,
        re.I,
    ):
        violations.append(
            f"line {admit.header.number}: admission trusts obsolete incoming receipt claims"
        )
    return violations


def _audit_aggregate_invocation(lines: list[ActiveLine]) -> list[str]:
    aggregate = _find_job(lines, "aggregate-attestation")
    if aggregate is None:
        return ["integration workflow must define aggregate-attestation"]
    text = aggregate.text
    violations: list[str] = []
    if not re.search(r"(?m)^    if:\s*\$\{\{\s*always\(\)\s*\}\}\s*$", text):
        violations.append(
            f"line {aggregate.header.number}: aggregate-attestation must use if: always()"
        )
    if "CI_NEEDS_JSON: ${{ toJSON(needs) }}" not in text:
        violations.append(
            f"line {aggregate.header.number}: aggregate must verify toJSON(needs)"
        )
    forbidden_array = re.search(
        r"(?s)\$[A-Za-z0-9_]*Arguments\s*=\s*@\(.*?"
        r"['\"]-AggregateShardReceipt['\"].*?\)\s*\+\s*\$shardReceipts",
        text,
    )
    if forbidden_array:
        violations.append(
            f"line {aggregate.header.number}: AggregateShardReceipt cannot be built "
            "as a child-CLI argument array before appending shard paths"
        )
    if "-AggregateShardReceipt $shardReceipts" not in text:
        violations.append(
            f"line {aggregate.header.number}: aggregate must bind the receipt array directly"
        )

    aggregate_step = text.find("- name: Aggregate the exact full candidate")
    verify_step = text.find("- name: Verify the aggregate against the fresh candidate receipt")
    verify_switch = text.find("-VerifyRunReceipt $aggregateReceipt")
    if not (0 <= aggregate_step < verify_step < verify_switch):
        violations.append(
            f"line {aggregate.header.number}: aggregate and exact receipt verification "
            "must be separate ordered steps"
        )
    return violations


def _check_run_mutations(job: JobBlock) -> list[str]:
    return re.findall(
        r"-Method\s+(POST|PATCH)\s*(?:`\s*)?-(?:Path|Uri)\s+['\"][^'\"\r\n]*/check-runs"
        r"(?:/[^'\"\r\n]*)?['\"]",
        job.text,
        re.I,
    )


def audit_check_surface(
    integration_text: str,
    controller_text: str,
    maintenance_text: str = "",
) -> list[str]:
    integration_lines = _active_lines(integration_text)
    controller_lines = _active_lines(controller_text)
    maintenance_lines = _active_lines(maintenance_text) if maintenance_text else []
    violations: list[str] = []
    combined = integration_text + "\n" + controller_text + "\n" + maintenance_text

    assignments = set(
        re.findall(r'\$requiredCheck\s*=\s*"([^"\r\n]+)"', combined)
    )
    if assignments != {"integration-green"}:
        violations.append(
            "the only custom required-check context must be exactly integration-green"
        )
    for obsolete in (
        "Trusted integration gate",
        "Trusted main audit",
        "candidate-v1:",
        "main-audit-v1:",
        "main-lkg-v1:",
    ):
        if obsolete in combined:
            violations.append(f"obsolete check contract remains: {obsolete}")
    if re.search(r"(?<!control-plane-)handoff-v1:", combined):
        violations.append("obsolete check contract remains: handoff-v1:")

    expected_mutations = {
        ("controller", "admit-handoff"): ["POST"],
        ("controller", "merge-handoff"): [],
        ("integration", "publish-attestation"): ["PATCH", "PATCH", "POST"],
        ("integration", "dispatch-completion"): [],
    }
    if maintenance_text:
        expected_mutations.update(
            {
                ("maintenance", "inspect"): [],
                ("maintenance", "authorize"): ["POST", "PATCH", "PATCH"],
                ("maintenance", "audit-merged-main"): [],
            }
        )
    all_jobs = {
        "controller": _jobs(controller_lines),
        "integration": _jobs(integration_lines),
    }
    if maintenance_text:
        all_jobs["maintenance"] = _jobs(maintenance_lines)
    for role, jobs in all_jobs.items():
        for job in jobs:
            mutations = [method.upper() for method in _check_run_mutations(job)]
            expected = expected_mutations.get((role, job.job_id), [])
            if mutations != expected:
                violations.append(
                    f"{role}:{job.job_id} mutates Check Runs as {mutations}, "
                    f"expected {expected}"
                )

    admit = _find_job(controller_lines, "admit-handoff")
    publisher = _find_job(integration_lines, "publish-attestation")
    if admit is not None and admit.text.count("name = $requiredCheck") != 1:
        violations.append("admission must create exactly one queued custom check")
    if publisher is not None:
        publisher_name_bindings = re.findall(
            r"(?m)^\s*(?:name|\$checkBody\.name)\s*=\s*\$requiredCheck\s*$",
            publisher.text,
        )
        if len(publisher_name_bindings) != 1:
            violations.append("publisher must create exactly one main custom check")
    if 'name = "integration-green"' in combined:
        violations.append("custom check bodies must use the single requiredCheck binding")

    if publisher is None:
        violations.append("publish-attestation job is missing")
    else:
        for required in (
            "candidate-v3:",
            "main-lkg-v3:",
            "$candidateReceiptSha",
            "$aggregateReceiptSha",
            "$mapReceiptSha",
            "$receiptSetSha",
        ):
            if required not in publisher.text:
                violations.append(f"publisher is missing fresh v3 binding {required!r}")

    combined_actions = re.findall(
        r"(?mi)^\s*(?:-\s*)?uses\s*:\s*(\S+)", combined
    )
    expected_attester_uses = 3 if maintenance_text else 2
    if combined_actions.count(ATTESTER_ACTION) != expected_attester_uses:
        violations.append(
            "only admission, publisher and optional maintenance authorization "
            "may mint scoped App tokens"
        )
    if combined.count("environment: integration-attester") != 2:
        violations.append("exactly admission and publisher must use integration-attester")
    if combined.count("INTEGRATION_ATTESTER_PRIVATE_KEY") != expected_attester_uses:
        violations.append(
            "the App private key must appear only in admission, publisher and "
            "optional maintenance authorization"
        )
    if "permission-administration: write" in combined:
        violations.append("the Checks-only attester must never receive Administration:write")
    if combined.count("permission-checks: write") != expected_attester_uses:
        violations.append(
            "only admission, publisher and optional maintenance authorization "
            "may request Checks:write"
        )
    if re.search(r"(?m)^\s+checks:\s*write\s*$", combined):
        violations.append("GITHUB_TOKEN must never receive checks: write")
    if re.search(r"(?m)^\s+(?:owner|repositories):\s*", combined):
        violations.append("attester tokens must remain scoped to the current repository")
    if "github-actions" in integration_text + "\n" + controller_text:
        violations.append("generic GitHub Actions identity cannot attest integration-green")

    trusted_reader_jobs = (
        _find_job(integration_lines, "trust-preflight"),
        _find_job(integration_lines, "dispatch-completion"),
    )
    for job in trusted_reader_jobs:
        if job is None:
            continue
        if "INTEGRATION_ATTESTER_APP_ID" not in job.text or "app.id" not in job.text:
            violations.append(
                f"{job.job_id} must bind checks to the numeric dedicated App ID"
            )
        if "INTEGRATION_ATTESTER_PRIVATE_KEY" in job.text:
            violations.append(f"{job.job_id} must not receive the attester private key")

    merge = _find_job(controller_lines, "merge-handoff")
    if merge is not None:
        for forbidden in (
            ATTESTER_ACTION,
            "INTEGRATION_ATTESTER_PRIVATE_KEY",
            "RULESET_AUDITOR_TOKEN",
            "permission-checks: write",
            "permission-administration: write",
            "bypass_actors",
        ):
            if forbidden in merge.text:
                violations.append(f"merge must not contain privileged token surface {forbidden!r}")
    return violations


def audit_workflow(path: Path, text: str, *, role: str = "generic") -> list[str]:
    lines = _active_lines(text)
    violations: list[str] = []
    if any(line.indent == -1 for line in lines):
        violations.append("YAML indentation must not contain tabs")
    violations.extend(_audit_actions(lines))
    violations.extend(_audit_permissions(lines))
    violations.extend(_audit_ordinary_check_jobs(lines))
    if role == "integration":
        violations.extend(_audit_trusted_preflight(lines))
        violations.extend(_audit_trusted_execution(lines))
        violations.extend(_audit_aggregate_invocation(lines))
    elif role == "controller":
        violations.extend(_audit_controller(lines, text))
    return [f"{path.name}: {violation}" for violation in violations]


class WorkflowAuditorNegativeFixtureTest(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.integration = INTEGRATION_WORKFLOW.read_text(encoding="utf-8")
        cls.controller = CONTROLLER_WORKFLOW.read_text(encoding="utf-8")
        cls.maintenance = MAINTENANCE_WORKFLOW.read_text(encoding="utf-8")

    def test_current_pair_is_accepted_by_the_security_auditor(self) -> None:
        violations = audit_workflow(
            INTEGRATION_WORKFLOW, self.integration, role="integration"
        )
        violations.extend(
            audit_workflow(CONTROLLER_WORKFLOW, self.controller, role="controller")
        )
        violations.extend(
            audit_workflow(MAINTENANCE_WORKFLOW, self.maintenance, role="generic")
        )
        violations.extend(
            audit_check_surface(
                self.integration,
                self.controller,
                self.maintenance,
            )
        )
        self.assertEqual([], violations, "\n" + "\n".join(violations))

    def test_unpinned_external_action_is_rejected(self) -> None:
        fixture = re.sub(
            r"actions/checkout@[0-9a-f]{40}",
            "actions/checkout@v7",
            self.integration,
            count=1,
        )
        violations = audit_workflow(
            Path("unpinned.yml"), fixture, role="integration"
        )
        self.assertTrue(any("full 40-hex SHA" in item for item in violations))

    def test_download_by_name_or_pattern_is_rejected(self) -> None:
        by_name = self.integration.replace("          artifact-ids:", "          name:", 1)
        self.assertNotEqual(self.integration, by_name)
        name_violations = audit_workflow(
            Path("download-by-name.yml"), by_name, role="integration"
        )
        self.assertTrue(
            any("exactly one non-empty artifact-ids" in item for item in name_violations)
        )
        self.assertTrue(any("select by 'name'" in item for item in name_violations))

        by_pattern = self.integration.replace(
            "          artifact-ids:", "          pattern:", 1
        )
        self.assertNotEqual(self.integration, by_pattern)
        pattern_violations = audit_workflow(
            Path("download-by-pattern.yml"), by_pattern, role="integration"
        )
        self.assertTrue(
            any("exactly one non-empty artifact-ids" in item for item in pattern_violations)
        )
        self.assertTrue(any("select by 'pattern'" in item for item in pattern_violations))

    def test_write_permission_combined_with_checkout_is_rejected(self) -> None:
        fixture = self.integration.replace("      checks: read", "      checks: write", 1)
        violations = audit_workflow(
            Path("write-checkout.yml"), fixture, role="integration"
        )
        self.assertTrue(
            any("combines checkout with write permissions" in item for item in violations)
        )

    def test_candidate_python_startup_hook_regression_is_rejected(self) -> None:
        fixture = self.integration.replace(
            'python -I -B (Join-Path $trustedRoot "tools/ci_lfs.py")',
            "python -B tools/ci_lfs.py",
            1,
        )
        self.assertNotEqual(self.integration, fixture)
        violations = audit_workflow(
            Path("candidate-sitecustomize.yml"), fixture, role="integration"
        )
        self.assertTrue(
            any("Python startup hooks" in item for item in violations),
            "tools/sitecustomize.py regression was not rejected",
        )

    def test_duplicate_or_ordinary_integration_green_is_rejected(self) -> None:
        ordinary = self.integration.replace(
            "    name: Publish trusted exact-SHA attestation",
            "    name: integration-green",
            1,
        )
        ordinary_violations = audit_workflow(
            Path("ordinary-check.yml"), ordinary, role="integration"
        )
        self.assertTrue(
            any("ordinary job name" in item for item in ordinary_violations)
        )

        duplicate = self.integration.replace(
            "              $checkBody.name = $requiredCheck",
            "              $checkBody.name = $requiredCheck\n              $checkBody.name = $requiredCheck",
            1,
        )
        self.assertNotEqual(self.integration, duplicate)
        duplicate_violations = audit_check_surface(duplicate, self.controller)
        self.assertTrue(
            any("exactly one main custom check" in item for item in duplicate_violations)
        )

    def test_missing_trusted_preflight_is_rejected(self) -> None:
        fixture = self.integration.replace("  trust-preflight:", "  removed-preflight:", 1)
        violations = audit_workflow(
            Path("missing-preflight.yml"), fixture, role="integration"
        )
        self.assertTrue(any("trust-preflight" in item for item in violations))

    def test_old_incoming_receipt_claim_is_rejected(self) -> None:
        needle = "          CANDIDATE_SHA: ${{ github.event.client_payload.candidate_sha }}"
        replacement = (
            needle
            + "\n          CANDIDATE_RECEIPT_SHA256: "
            + "${{ github.event.client_payload.candidate_receipt_sha256 }}"
        )
        self.assertIn(needle, self.controller)
        fixture = self.controller.replace(needle, replacement, 1)
        violations = audit_workflow(
            Path("old-receipt-claim.yml"), fixture, role="controller"
        )
        self.assertTrue(any("incoming receipt claims" in item for item in violations))

    def test_child_cli_aggregate_array_binding_is_rejected(self) -> None:
        needle = "            -AggregateShardReceipt $shardReceipts `"
        replacement = (
            '          $aggregateArguments = @("-AggregateShardReceipt") '
            "+ $shardReceipts\n"
            "          & pwsh @aggregateArguments"
        )
        self.assertIn(needle, self.integration)
        fixture = self.integration.replace(needle, replacement, 1)
        violations = audit_workflow(
            Path("aggregate-array.yml"), fixture, role="integration"
        )
        self.assertTrue(any("child-CLI argument array" in item for item in violations))


class RepositoryWorkflowContractTest(unittest.TestCase):
    def test_all_workflows_and_the_public_check_surface_are_fail_closed(self) -> None:
        workflows = sorted(WORKFLOWS_ROOT.glob("*.yml")) + sorted(
            WORKFLOWS_ROOT.glob("*.yaml")
        )
        self.assertTrue(workflows, f"No workflows found under {WORKFLOWS_ROOT}")
        self.assertTrue(INTEGRATION_WORKFLOW.is_file())
        self.assertTrue(CONTROLLER_WORKFLOW.is_file())

        violations: list[str] = []
        for workflow in workflows:
            role = "generic"
            if workflow.resolve() == INTEGRATION_WORKFLOW.resolve():
                role = "integration"
            elif workflow.resolve() == CONTROLLER_WORKFLOW.resolve():
                role = "controller"
            violations.extend(
                audit_workflow(
                    workflow,
                    workflow.read_text(encoding="utf-8"),
                    role=role,
                )
            )
        violations.extend(
            audit_check_surface(
                INTEGRATION_WORKFLOW.read_text(encoding="utf-8"),
                CONTROLLER_WORKFLOW.read_text(encoding="utf-8"),
                MAINTENANCE_WORKFLOW.read_text(encoding="utf-8"),
            )
        )
        self.assertEqual([], violations, "\n" + "\n".join(violations))


if __name__ == "__main__":
    unittest.main(verbosity=2)
