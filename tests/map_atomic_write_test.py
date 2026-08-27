#!/usr/bin/env python3
"""Regression checks for compare-and-swap Map output promotion."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import nullcontext
from pathlib import Path
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MAP_TOOLS_DIR = PROJECT_ROOT / "underwater_map_workbench" / "tools"
if str(MAP_TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(MAP_TOOLS_DIR))

import build_underwater_map as builder  # noqa: E402


class MapAtomicWriteTest(unittest.TestCase):
    def test_targeted_l05_refresh_allows_unrelated_stale_package_pin(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            manifest_path = Path(temporary) / "map_manifest.json"
            manifest_path.write_text(
                '{"topology":{"mode":"l05_mask_v1"}}',
                encoding="utf-8",
            )

            with (
                mock.patch.object(builder, "MANIFEST_PATH", manifest_path),
                mock.patch.object(
                    builder,
                    "_capture_manifest_input_fingerprint",
                    return_value={},
                ),
                mock.patch.object(
                    builder,
                    "_resolve_structure_packages",
                    side_effect=builder.ManifestError("stop after resolver"),
                ) as resolver,
            ):
                with self.assertRaisesRegex(
                    builder.ManifestError,
                    "stop after resolver",
                ):
                    builder._refresh_l05_source(full_manifest_validation=False)

            resolver.assert_called_once_with(
                mock.ANY,
                verify_package_hashes=False,
            )

    def test_standalone_l05_refresh_keeps_package_pin_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            manifest_path = Path(temporary) / "map_manifest.json"
            manifest_path.write_text(
                '{"topology":{"mode":"l05_mask_v1"}}',
                encoding="utf-8",
            )

            with (
                mock.patch.object(builder, "MANIFEST_PATH", manifest_path),
                mock.patch.object(
                    builder,
                    "_capture_manifest_input_fingerprint",
                    return_value={},
                ),
                mock.patch.object(
                    builder,
                    "_resolve_structure_packages",
                    side_effect=builder.ManifestError("stop after resolver"),
                ) as resolver,
            ):
                with self.assertRaisesRegex(
                    builder.ManifestError,
                    "stop after resolver",
                ):
                    builder._refresh_l05_source()

            resolver.assert_called_once_with(
                mock.ANY,
                verify_package_hashes=True,
            )

    def test_exact_baseline_promotes_all_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = root / "first.bin"
            second = root / "second.bin"
            first.write_bytes(b"first-old")
            second.write_bytes(b"second-old")

            builder._publish_outputs_with_cas(
                {first: b"first-new", second: b"second-new"},
                expected_current={
                    first: b"first-old",
                    second: b"second-old",
                },
            )

            self.assertEqual(first.read_bytes(), b"first-new")
            self.assertEqual(second.read_bytes(), b"second-new")

    def test_commit_marker_is_replaced_last(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            marker = root / "scene.tscn"
            payload = root / "payload.bin"
            marker.write_bytes(b"marker-old")
            payload.write_bytes(b"payload-old")
            replacement_order: list[Path] = []
            real_replace = builder.os.replace

            def record_replace(source: object, destination: object) -> None:
                replacement_order.append(Path(destination))
                real_replace(source, destination)

            with mock.patch.object(
                builder.os,
                "replace",
                side_effect=record_replace,
            ):
                builder._publish_outputs_with_cas(
                    {marker: b"marker-new", payload: b"payload-new"},
                    expected_current={
                        marker: b"marker-old",
                        payload: b"payload-old",
                    },
                    commit_marker=marker,
                )

            self.assertEqual(replacement_order, [payload, marker])

    def test_stale_baseline_is_rejected_before_first_write(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "manifest.json"
            target.write_bytes(b"external-edit")

            with self.assertRaisesRegex(
                builder.ManifestError,
                "concurrent edit detected before CAS publication",
            ):
                builder._publish_outputs_with_cas(
                    {target: b"our-edit"},
                    expected_current={target: b"stale-read"},
                )

            self.assertEqual(target.read_bytes(), b"external-edit")

    def test_partial_os_failure_rolls_back_owned_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = root / "first.bin"
            second = root / "second.bin"
            first.write_bytes(b"first-old")
            second.write_bytes(b"second-old")
            real_replace = builder.os.replace
            call_count = 0

            def fail_second_replace(source: object, destination: object) -> None:
                nonlocal call_count
                call_count += 1
                if call_count == 2:
                    raise OSError("injected second replace failure")
                real_replace(source, destination)

            with mock.patch.object(
                builder.os,
                "replace",
                side_effect=fail_second_replace,
            ):
                with self.assertRaisesRegex(
                    OSError,
                    "injected second replace failure",
                ):
                    builder._publish_outputs_with_cas(
                        {first: b"first-new", second: b"second-new"},
                        expected_current={
                            first: b"first-old",
                            second: b"second-old",
                        },
                    )

            self.assertEqual(first.read_bytes(), b"first-old")
            self.assertEqual(second.read_bytes(), b"second-old")

    def test_rollback_never_overwrites_concurrent_edit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = root / "first.bin"
            second = root / "second.bin"
            first.write_bytes(b"first-old")
            second.write_bytes(b"second-old")
            real_replace = builder.os.replace
            call_count = 0

            def edit_after_first_replace(source: object, destination: object) -> None:
                nonlocal call_count
                call_count += 1
                real_replace(source, destination)
                if call_count == 1:
                    Path(destination).write_bytes(b"external-edit")

            with mock.patch.object(
                builder.os,
                "replace",
                side_effect=edit_after_first_replace,
            ):
                with self.assertRaisesRegex(
                    builder.ManifestError,
                    "rollback did not overwrite concurrent work",
                ):
                    builder._publish_outputs_with_cas(
                        {first: b"first-new", second: b"second-new"},
                        expected_current={
                            first: b"first-old",
                            second: b"second-old",
                        },
                    )

            self.assertEqual(first.read_bytes(), b"external-edit")
            self.assertEqual(second.read_bytes(), b"second-old")

    @staticmethod
    def _private_package(local_digest: str = "stale") -> dict[str, object]:
        return {
            "schema_version": 1,
            "format": builder.STRUCTURE_PACKAGE_FORMAT,
            "template": {},
            "size": [40, 40],
            "local_topology_digest": local_digest,
            "collision": {
                "format": builder.STRUCTURE_PACKAGE_COLLISION_FORMAT,
                "base": "open_water",
                "pixel_size": [1, 1],
                "world_units_per_pixel": [40, 40],
                "operations": [
                    {"id": "solid", "op": "solid_rect", "rect_px": [0, 0, 1, 1]}
                ],
            },
            "sockets": [],
            "runtime": {},
            "visual_assets": [],
            "scripts": [],
            "attempt_state": {},
            "references": [],
        }

    def test_seal_structure_package_writes_only_private_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbench = Path(temporary) / "underwater_map_workbench"
            package_path = (
                workbench
                / "structures"
                / "test_tower"
                / "structure_manifest.json"
            )
            package_path.parent.mkdir(parents=True)
            package_path.write_text(
                json.dumps(self._private_package(), indent=2) + "\n",
                encoding="utf-8",
            )
            map_path = workbench / "map_manifest.json"
            map_path.write_bytes(b"map-authority-must-not-change")

            with mock.patch.object(builder, "WORKBENCH_DIR", workbench):
                builder._seal_structure_package("test_tower")

            sealed = json.loads(package_path.read_text(encoding="utf-8"))
            self.assertRegex(
                sealed["local_topology_digest"],
                r"^structure-topology-v1:[0-9a-f]{64}$",
            )
            self.assertEqual(map_path.read_bytes(), b"map-authority-must-not-change")

    def test_refresh_structure_package_promotes_pin_without_private_write(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbench = Path(temporary) / "underwater_map_workbench"
            package_path = (
                workbench
                / "structures"
                / "test_tower"
                / "structure_manifest.json"
            )
            package_path.parent.mkdir(parents=True)
            unsealed_raw = (
                json.dumps(self._private_package(), indent=2) + "\n"
            ).encode("utf-8")
            package_path.write_bytes(unsealed_raw)
            with mock.patch.object(builder, "WORKBENCH_DIR", workbench):
                sealed_raw, package_sha, _digest = (
                    builder._prepare_structure_package_seal(
                        "test_tower",
                        unsealed_raw,
                        validate_visuals=False,
                    )
                )
            package_path.write_bytes(sealed_raw)
            map_path = workbench / "map_manifest.json"
            map_path.write_text(
                json.dumps(
                    {
                        "structures": {
                            "instances": [
                                {
                                    "id": "test_tower",
                                    "origin": [0, 0],
                                    "enabled": True,
                                    "package": {
                                        "format": builder.STRUCTURE_PACKAGE_REFERENCE_FORMAT,
                                        "path": "structures/test_tower/structure_manifest.json",
                                        "sha256": "0" * 64,
                                    },
                                }
                            ]
                        }
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            private_before = package_path.read_bytes()
            map_before = map_path.read_bytes()
            prepare_options: list[dict[str, object]] = []

            def prepare_l05(raw: bytes, **kwargs: object) -> tuple[bytes, bool, str, str, str]:
                prepare_options.append(kwargs)
                manifest = json.loads(raw.decode("utf-8"))
                manifest["promoted"] = True
                updated = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
                return updated, True, "payload", "topology", "partition"

            with (
                mock.patch.object(builder, "WORKBENCH_DIR", workbench),
                mock.patch.object(builder, "MANIFEST_PATH", map_path),
                mock.patch.object(
                    builder,
                    "_capture_manifest_input_fingerprint",
                    return_value={},
                ),
                mock.patch.object(
                    builder,
                    "_prepare_l05_source_refresh",
                    side_effect=prepare_l05,
                ),
                mock.patch.object(
                    builder,
                    "_map_promotion_lock",
                    return_value=nullcontext(),
                ),
            ):
                with self.assertRaisesRegex(
                    builder.ManifestError,
                    "sealed hand-off",
                ):
                    builder._refresh_structure_package("test_tower", "f" * 64)
                self.assertEqual(map_path.read_bytes(), map_before)
                builder._refresh_structure_package("test_tower", package_sha)

            promoted = json.loads(map_path.read_text(encoding="utf-8"))
            self.assertEqual(
                promoted["structures"]["instances"][0]["package"]["sha256"],
                package_sha,
            )
            self.assertEqual(
                package_sha,
                hashlib.sha256(private_before).hexdigest(),
            )
            self.assertEqual(package_path.read_bytes(), private_before)
            self.assertEqual(
                prepare_options,
                [{"full_manifest_validation": False, "verify_package_hashes": True}],
            )

    def test_batch_refresh_resolves_two_stale_pins_without_partial_write(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbench = Path(temporary) / "underwater_map_workbench"
            structure_ids = ("tower_alpha", "tower_beta")
            package_shas: dict[str, str] = {}
            private_before: dict[str, bytes] = {}
            for index, structure_id in enumerate(structure_ids):
                package_path = (
                    workbench
                    / "structures"
                    / structure_id
                    / "structure_manifest.json"
                )
                package_path.parent.mkdir(parents=True)
                package = self._private_package()
                package["attempt_state"] = {"fixture": index}
                unsealed_raw = (json.dumps(package, indent=2) + "\n").encode(
                    "utf-8"
                )
                package_path.write_bytes(unsealed_raw)
                with mock.patch.object(builder, "WORKBENCH_DIR", workbench):
                    sealed_raw, package_sha, _digest = (
                        builder._prepare_structure_package_seal(
                            structure_id,
                            unsealed_raw,
                            validate_visuals=False,
                        )
                    )
                package_path.write_bytes(sealed_raw)
                package_shas[structure_id] = package_sha
                private_before[structure_id] = sealed_raw

            map_path = workbench / "map_manifest.json"
            map_path.write_text(
                json.dumps(
                    {
                        "structures": {
                            "instances": [
                                {
                                    "id": structure_id,
                                    "origin": [index * 100, 0],
                                    "enabled": True,
                                    "package": {
                                        "format": builder.STRUCTURE_PACKAGE_REFERENCE_FORMAT,
                                        "path": (
                                            f"structures/{structure_id}/"
                                            "structure_manifest.json"
                                        ),
                                        "sha256": "0" * 64,
                                    },
                                }
                                for index, structure_id in enumerate(structure_ids)
                            ]
                        }
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            map_before = map_path.read_bytes()
            prepare_calls: list[dict[str, object]] = []

            def prepare_l05(
                raw: bytes,
                **kwargs: object,
            ) -> tuple[bytes, bool, str, str, str]:
                prepare_calls.append(kwargs)
                manifest = json.loads(raw.decode("utf-8"))
                actual_pins = {
                    record["id"]: record["package"]["sha256"]
                    for record in manifest["structures"]["instances"]
                }
                for structure_id, expected_sha in package_shas.items():
                    if actual_pins.get(structure_id) != expected_sha:
                        raise builder.ManifestError(
                            f"{structure_id} package pin is stale"
                        )
                manifest["composed_batch"] = True
                updated = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
                return updated, True, "payload", "topology", "partition"

            validated_candidates: list[bytes] = []

            def validate_candidate(raw: bytes) -> None:
                candidate = json.loads(raw.decode("utf-8"))
                self.assertTrue(candidate["composed_batch"])
                self.assertEqual(
                    {
                        record["id"]: record["package"]["sha256"]
                        for record in candidate["structures"]["instances"]
                    },
                    package_shas,
                )
                validated_candidates.append(raw)

            with (
                mock.patch.object(builder, "WORKBENCH_DIR", workbench),
                mock.patch.object(builder, "MANIFEST_PATH", map_path),
                mock.patch.object(
                    builder,
                    "_capture_manifest_input_fingerprint",
                    return_value={},
                ) as capture_inputs,
                mock.patch.object(
                    builder,
                    "_prepare_l05_source_refresh",
                    side_effect=prepare_l05,
                ),
                mock.patch.object(
                    builder,
                    "_load_and_validate_manifest_raw",
                    side_effect=validate_candidate,
                ) as full_validation,
                mock.patch.object(
                    builder,
                    "_map_promotion_lock",
                    return_value=nullcontext(),
                ) as map_lock,
            ):
                with self.assertRaisesRegex(builder.ManifestError, "sealed hand-off"):
                    builder._refresh_structure_packages(
                        [
                            ("tower_alpha", package_shas["tower_alpha"]),
                            ("tower_beta", "f" * 64),
                        ],
                        full_manifest_validation=True,
                    )
                self.assertEqual(map_path.read_bytes(), map_before)

                with self.assertRaisesRegex(
                    builder.ManifestError,
                    "tower_beta package pin is stale",
                ):
                    builder._refresh_structure_package(
                        "tower_alpha",
                        package_shas["tower_alpha"],
                    )
                self.assertEqual(map_path.read_bytes(), map_before)

                builder._refresh_structure_packages(
                    [
                        (structure_id, package_shas[structure_id])
                        for structure_id in structure_ids
                    ],
                    full_manifest_validation=True,
                )

            promoted = json.loads(map_path.read_text(encoding="utf-8"))
            self.assertEqual(
                {
                    record["id"]: record["package"]["sha256"]
                    for record in promoted["structures"]["instances"]
                },
                package_shas,
            )
            self.assertTrue(promoted["composed_batch"])
            self.assertEqual(len(validated_candidates), 1)
            full_validation.assert_called_once()
            self.assertEqual(map_lock.call_count, 1)
            self.assertEqual(
                [call.kwargs["include_map_visual_assets"] for call in capture_inputs.call_args_list],
                [True, False, True],
            )
            self.assertEqual(
                prepare_calls,
                [
                    {"full_manifest_validation": False, "verify_package_hashes": True},
                    {"full_manifest_validation": False, "verify_package_hashes": True},
                ],
            )
            for structure_id in structure_ids:
                package_path = (
                    workbench
                    / "structures"
                    / structure_id
                    / "structure_manifest.json"
                )
                self.assertEqual(package_path.read_bytes(), private_before[structure_id])

    def test_main_pairs_repeated_structure_refresh_arguments_as_one_batch(self) -> None:
        args = argparse.Namespace(
            seal_structure_package=None,
            refresh_l05_source=False,
            refresh_structure_package=["tower_alpha", "tower_beta"],
            sealed_package_sha256=["a" * 64, "b" * 64],
        )
        with (
            mock.patch.object(builder, "_parse_args", return_value=args),
            mock.patch.object(builder, "_refresh_structure_packages") as refresh_batch,
        ):
            self.assertEqual(builder.main(), 0)

        refresh_batch.assert_called_once_with(
            [("tower_alpha", "a" * 64), ("tower_beta", "b" * 64)],
            full_manifest_validation=True,
        )

    def test_refresh_structure_package_rejects_unsealed_private_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbench = Path(temporary) / "underwater_map_workbench"
            package_path = (
                workbench
                / "structures"
                / "test_tower"
                / "structure_manifest.json"
            )
            package_path.parent.mkdir(parents=True)
            package_path.write_text(
                json.dumps(self._private_package(), indent=2) + "\n",
                encoding="utf-8",
            )
            map_path = workbench / "map_manifest.json"
            map_path.write_text(
                json.dumps(
                    {
                        "structures": {
                            "instances": [
                                {
                                    "id": "test_tower",
                                    "origin": [0, 0],
                                    "enabled": True,
                                    "package": {
                                        "format": builder.STRUCTURE_PACKAGE_REFERENCE_FORMAT,
                                        "path": "structures/test_tower/structure_manifest.json",
                                        "sha256": "0" * 64,
                                    },
                                }
                            ]
                        }
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            map_before = map_path.read_bytes()

            with (
                mock.patch.object(builder, "WORKBENCH_DIR", workbench),
                mock.patch.object(builder, "MANIFEST_PATH", map_path),
                mock.patch.object(
                    builder,
                    "_capture_manifest_input_fingerprint",
                    return_value={},
                ),
            ):
                with self.assertRaisesRegex(builder.ManifestError, "is not sealed"):
                    builder._refresh_structure_package(
                        "test_tower",
                        hashlib.sha256(package_path.read_bytes()).hexdigest(),
                    )

            self.assertEqual(map_path.read_bytes(), map_before)

    def test_read_only_main_does_not_resolve_or_take_map_lock(self) -> None:
        args = argparse.Namespace(
            seal_structure_package=None,
            refresh_l05_source=False,
            refresh_structure_package=None,
            sealed_package_sha256=None,
        )
        with (
            mock.patch.object(builder, "_parse_args", return_value=args),
            mock.patch.object(builder, "_run_render_mode", return_value=0),
            mock.patch.object(builder, "_git_common_directory") as common_dir,
        ):
            self.assertEqual(builder.main(), 0)
        common_dir.assert_not_called()

    def test_structure_check_uses_only_local_candidate_renderer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbench = Path(temporary) / "underwater_map_workbench"
            authority_output = (
                workbench
                / "structures"
                / "test_tower"
                / "generated"
                / "structure.tscn"
            )
            output = (
                workbench.parent
                / ".godot"
                / "underwater_map_structure_builds"
                / "test_tower"
                / "generated"
                / "structure.tscn"
            )
            output.parent.mkdir(parents=True)
            output.write_bytes(b"current")
            manifest_path = workbench / "map_manifest.json"
            manifest_path.parent.mkdir(parents=True, exist_ok=True)
            manifest_path.write_bytes(b"manifest")
            args = argparse.Namespace(
                build=False,
                check=False,
                build_structure=None,
                check_structure="test_tower",
            )

            with (
                mock.patch.object(builder, "WORKBENCH_DIR", workbench),
                mock.patch.object(builder, "MANIFEST_PATH", manifest_path),
                mock.patch.object(
                    builder,
                    "_capture_manifest_input_fingerprint",
                    return_value={},
                ) as capture,
                mock.patch.object(
                    builder,
                    "_render_structure_build_candidate",
                    return_value=({authority_output: b"current"}, {}, "manifest-sha"),
                ) as local_render,
                mock.patch.object(builder, "_render_build_candidate") as full_render,
                mock.patch.object(builder, "_map_promotion_lock") as map_lock,
            ):
                self.assertEqual(builder._run_render_mode(args), 0)

            capture.assert_called_once_with(
                b"manifest",
                include_map_visual_assets=False,
                structure_id_filter="test_tower",
            )
            local_render.assert_called_once_with(b"manifest", "test_tower")
            full_render.assert_not_called()
            map_lock.assert_not_called()

    def test_different_structure_builds_use_disjoint_local_lanes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbench = Path(temporary) / "underwater_map_workbench"
            manifest_path = workbench / "map_manifest.json"
            manifest_path.parent.mkdir(parents=True)
            manifest_path.write_bytes(b"manifest")
            lock_ids: list[str] = []
            publications: list[dict[Path, bytes]] = []

            def local_lock(structure_id: str) -> object:
                lock_ids.append(structure_id)
                return nullcontext()

            def render(
                _raw: bytes,
                structure_id: str,
            ) -> tuple[dict[Path, bytes], dict[str, object], str]:
                authority_output = (
                    workbench
                    / "structures"
                    / structure_id
                    / "generated"
                    / "structure.tscn"
                )
                return {authority_output: structure_id.encode("utf-8")}, {}, "sha"

            def publish(outputs: dict[Path, bytes], **_kwargs: object) -> None:
                publications.append(outputs)

            with (
                mock.patch.object(builder, "WORKBENCH_DIR", workbench),
                mock.patch.object(builder, "MANIFEST_PATH", manifest_path),
                mock.patch.object(
                    builder,
                    "_capture_manifest_input_fingerprint",
                    return_value={},
                ),
                mock.patch.object(
                    builder,
                    "_render_structure_build_candidate",
                    side_effect=render,
                ),
                mock.patch.object(
                    builder,
                    "_structure_local_build_lock",
                    side_effect=local_lock,
                ),
                mock.patch.object(
                    builder,
                    "_publish_outputs_with_cas",
                    side_effect=publish,
                ),
                mock.patch.object(builder, "_map_promotion_lock") as map_lock,
            ):
                for structure_id in ("tower_a", "tower_b"):
                    args = argparse.Namespace(
                        build=False,
                        check=False,
                        build_structure=structure_id,
                        check_structure=None,
                    )
                    self.assertEqual(builder._run_render_mode(args), 0)

            map_lock.assert_not_called()
            self.assertEqual(lock_ids, ["tower_a", "tower_a", "tower_b", "tower_b"])
            published_paths = [next(iter(outputs)) for outputs in publications]
            self.assertEqual(len(set(published_paths)), 2)
            self.assertIn("tower_a", published_paths[0].parts)
            self.assertIn("tower_b", published_paths[1].parts)
            for path in published_paths:
                self.assertIn(".godot", path.parts)
                self.assertNotIn("underwater_map_workbench", path.parts)

    def test_structure_fingerprint_does_not_open_another_private_package(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbench = Path(temporary) / "underwater_map_workbench"
            topology_path = workbench / "assets" / "topology" / "source.json"
            topology_path.parent.mkdir(parents=True)
            topology_path.write_bytes(b"topology")
            target_package = (
                workbench
                / "structures"
                / "target_tower"
                / "structure_manifest.json"
            )
            target_package.parent.mkdir(parents=True)
            target_package.write_text(
                json.dumps(
                    {
                        "visual_assets": [],
                        "scripts": [],
                        "references": [],
                    }
                ),
                encoding="utf-8",
            )
            unrelated_package = (
                workbench
                / "structures"
                / "unrelated_tower"
                / "structure_manifest.json"
            )
            manifest = {
                "topology": {
                    "collision_source": {
                        "path": "assets/topology/source.json",
                    }
                },
                "structures": {
                    "instances": [
                        {
                            "id": "target_tower",
                            "package": {
                                "path": "structures/target_tower/structure_manifest.json",
                            },
                        },
                        {
                            "id": "unrelated_tower",
                            "package": {
                                "path": "structures/unrelated_tower/structure_manifest.json",
                            },
                        },
                    ]
                },
            }
            manifest_raw = json.dumps(manifest).encode("utf-8")
            manifest_path = workbench / "map_manifest.json"
            manifest_path.write_bytes(manifest_raw)

            with (
                mock.patch.object(builder, "WORKBENCH_DIR", workbench),
                mock.patch.object(builder, "MANIFEST_PATH", manifest_path),
            ):
                fingerprints = builder._capture_manifest_input_fingerprint(
                    manifest_raw,
                    include_map_visual_assets=False,
                    structure_id_filter="target_tower",
                )

            self.assertIn(target_package.resolve(), fingerprints)
            self.assertNotIn(unrelated_package.resolve(), fingerprints)

    def test_build_captures_output_baseline_before_render(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workbench = Path(temporary) / "underwater_map_workbench"
            manifest_path = workbench / "map_manifest.json"
            scene_path = workbench / "UnderwaterMap.tscn"
            manifest_path.parent.mkdir(parents=True)
            manifest_path.write_bytes(b"manifest")
            events: list[str] = []

            class RecordingContext:
                def __enter__(self) -> "RecordingContext":
                    events.append("lock")
                    return self

                def __exit__(self, *_args: object) -> None:
                    return None

            def render(_raw: bytes) -> tuple[dict[Path, bytes], dict[str, object], str, str, str]:
                events.append("render")
                return {scene_path: b"new"}, {}, "sha", "gameplay", "presentation"

            def publish(
                outputs: dict[Path, bytes],
                **kwargs: object,
            ) -> None:
                events.append("publish")
                self.assertEqual(outputs, {scene_path: b"new"})
                self.assertEqual(kwargs["expected_current"], {scene_path: b"old"})
                self.assertEqual(kwargs["commit_marker"], scene_path)

            args = argparse.Namespace(
                build=True,
                check=False,
                build_structure=None,
                check_structure=None,
            )
            with (
                mock.patch.object(builder, "WORKBENCH_DIR", workbench),
                mock.patch.object(builder, "MANIFEST_PATH", manifest_path),
                mock.patch.object(builder, "SCENE_PATH", scene_path),
                mock.patch.object(
                    builder,
                    "_capture_manifest_input_fingerprint",
                    return_value={},
                ),
                mock.patch.object(
                    builder,
                    "_capture_publication_output_baseline",
                    side_effect=lambda **_kwargs: (
                        events.append("baseline") or {scene_path: b"old"}
                    ),
                ),
                mock.patch.object(
                    builder,
                    "_render_build_candidate",
                    side_effect=render,
                ),
                mock.patch.object(
                    builder,
                    "_map_promotion_lock",
                    side_effect=lambda: RecordingContext(),
                ),
                mock.patch.object(
                    builder,
                    "_publish_outputs_with_cas",
                    side_effect=publish,
                ),
            ):
                self.assertEqual(builder._run_render_mode(args), 0)

            self.assertEqual(
                events,
                ["lock", "baseline", "render", "lock", "publish"],
            )

    def test_git_common_directory_resolves_relative_git_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            completed = builder.subprocess.CompletedProcess(
                args=["git"],
                returncode=0,
                stdout=".git\n",
                stderr="",
            )
            with mock.patch.object(builder.subprocess, "run", return_value=completed):
                self.assertEqual(
                    builder._git_common_directory(root),
                    (root / ".git").resolve(),
                )

    def test_map_promotion_lock_uses_local_and_git_common_scopes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            project_root = Path(temporary).resolve()
            workbench = project_root / "underwater_map_workbench"
            common_directory = project_root / "shared.git"
            entered: list[Path] = []

            class RecordingLock:
                def __init__(self, scope: Path, name: str) -> None:
                    self.scope = Path(scope)
                    self.name = name

                def __enter__(self) -> "RecordingLock":
                    self.assert_name()
                    entered.append(self.scope)
                    return self

                def __exit__(self, *_args: object) -> None:
                    return None

                def assert_name(self) -> None:
                    if self.name != "map-promotion":
                        raise AssertionError(self.name)

            with (
                mock.patch.object(builder, "WORKBENCH_DIR", workbench),
                mock.patch.object(
                    builder,
                    "_git_common_directory",
                    return_value=common_directory,
                ),
                mock.patch.object(
                    builder,
                    "InterprocessWorkspaceLock",
                    side_effect=RecordingLock,
                ),
            ):
                with builder._map_promotion_lock():
                    pass

            self.assertEqual(entered, [project_root, common_directory])

    def test_input_fingerprint_rejects_changed_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source.bin"
            source.write_bytes(b"sealed-input")
            expected = {
                source: builder._content_fingerprint(b"sealed-input")
            }
            source.write_bytes(b"concurrent-edit")

            with self.assertRaisesRegex(
                builder.ManifestError,
                "build inputs changed before publication",
            ):
                builder._assert_input_fingerprint(expected)

    def test_ordinary_non_git_builder_fails_without_isolated_proof(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            root_tools = project / "tools"
            map_tools = project / "underwater_map_workbench" / "tools"
            root_tools.mkdir(parents=True)
            map_tools.mkdir(parents=True)
            shutil.copyfile(
                PROJECT_ROOT / "tools" / "workbench_contract.py",
                root_tools / "workbench_contract.py",
            )
            shutil.copyfile(
                PROJECT_ROOT / "tools" / "workbench_lock.py",
                root_tools / "workbench_lock.py",
            )
            copied_builder = map_tools / "build_underwater_map.py"
            shutil.copyfile(
                PROJECT_ROOT
                / "underwater_map_workbench"
                / "tools"
                / "build_underwater_map.py",
                copied_builder,
            )
            environment = builder.os.environ.copy()
            environment.pop(builder.ISOLATED_EOL_PROOF_PATH_ENV, None)
            environment.pop(builder.ISOLATED_EOL_PROOF_KEY_ENV, None)

            result = subprocess.run(
                [sys.executable, "-B", str(copied_builder), "--build-structure", "tower_local"],
                cwd=project / "underwater_map_workbench",
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("tracked EOL preflight failed", result.stderr)
            self.assertIn("No Git worktree found", result.stderr)

    def test_non_git_structure_builder_accepts_only_verified_proof(self) -> None:
        args = argparse.Namespace(
            build=False,
            check=False,
            build_structure="tower_local",
            check_structure=None,
        )
        with (
            mock.patch.object(
                builder,
                "repository_root",
                side_effect=builder.ContractError("No Git worktree found"),
            ),
            mock.patch.dict(
                builder.os.environ,
                {
                    builder.ISOLATED_EOL_PROOF_PATH_ENV: "proof.json",
                    builder.ISOLATED_EOL_PROOF_KEY_ENV: "ab" * 32,
                },
                clear=False,
            ),
            mock.patch.object(
                builder,
                "verify_isolated_eol_proof",
                return_value={"source_snapshot_sha256": "c" * 64},
            ) as verifier,
        ):
            builder._assert_builder_eol_preflight(args)

        verifier.assert_called_once_with(
            builder.WORKBENCH_DIR.parent.resolve(),
            proof_path="proof.json",
            structure_id="tower_local",
            secret_hex="ab" * 32,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
