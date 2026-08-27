extends SceneTree

const MAP_WORKBENCH_PATH := "res://underwater_map_workbench"
const MAP_MANIFEST_PATH := MAP_WORKBENCH_PATH + "/map_manifest.json"
const STRUCTURE_PACKAGES_PATH := MAP_WORKBENCH_PATH + "/structures"
const STRUCTURE_MANIFEST_FILE := "structure_manifest.json"
const REQUIRED_STRUCTURE_PACKAGE_FILES := [
	"AGENTS.md",
	"README.md",
	STRUCTURE_MANIFEST_FILE,
]
const APPROVED_STRUCTURE_DOCUMENTS := [
	"AGENTS.md",
	"README.md",
]
const MAP_STRUCTURE_INSTANCE_KEYS := {
	"id": true,
	"origin": true,
	"enabled": true,
	"landmark_id": true,
	"package": true,
}
const MAP_STRUCTURE_PACKAGE_KEYS := {
	"format": true,
	"path": true,
	"sha256": true,
}
const FORBIDDEN_MAP_STRUCTURE_INSTANCE_KEYS := {
	"template": true,
	"template_id": true,
	"size": true,
	"topology_digest": true,
	"partition_digest": true,
	"collision": true,
	"sockets": true,
	"visual_assets": true,
	"scripts": true,
	"runtime": true,
	"attempt_state": true,
}
const FORBIDDEN_STRUCTURE_MANIFEST_ROOT_KEYS := {
	"structure_id": true,
	"origin": true,
	"world_origin": true,
	"world_position": true,
	"global_position": true,
	"landmark_id": true,
	"map_gameplay_signature": true,
	"world_delta": true,
	"persistence": true,
	"checkpoint": true,
}
const STRUCTURE_REFERENCE_COLLECTIONS := [
	"visual_assets",
	"scripts",
	"references",
]
const STRUCTURE_REFERENCE_SOURCE_EXTENSIONS := {
	"gd": true,
	"gdshader": true,
	"tres": true,
	"tscn": true,
}
const DOCUMENTATION_EXTENSIONS := {
	"adoc": true,
	"doc": true,
	"docx": true,
	"md": true,
	"odt": true,
	"pdf": true,
	"rst": true,
	"txt": true,
}

const UNIQUE_AUTHORITY_PATHS := {
	"project.godot": "res://project.godot",
	"map_manifest.json": "res://underwater_map_workbench/map_manifest.json",
	"UnderwaterMap.tscn": "res://underwater_map_workbench/UnderwaterMap.tscn",
	"UnderwaterMapRuntime.gd": "res://underwater_map_workbench/runtime/UnderwaterMapRuntime.gd",
	"UnderwaterMapSceneCompiler.gd": "res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd",
	"Diver.tscn": "res://diver_workbench/runtime/Diver.tscn",
	"DiverController.gd": "res://diver_workbench/runtime/DiverController.gd",
	"DiverVisualEffects.gd": "res://diver_workbench/runtime/DiverVisualEffects.gd",
	"DiverSocketProfile.gd": "res://diver_workbench/definitions/DiverSocketProfile.gd",
	"diver_sprite_frames.tres": "res://diver_workbench/assets/animation/diver_sprite_frames.tres",
	"diver_socket_profile.tres": "res://diver_workbench/assets/profiles/diver_socket_profile.tres",
	"diver_idle_16f.png": "res://diver_workbench/assets/animation/diver_idle_16f.png",
	"diver_swim_16f.png": "res://diver_workbench/assets/animation/diver_swim_16f.png",
	"diver_sprint_16f.png": "res://diver_workbench/assets/animation/diver_sprint_16f.png",
	"diver_readability.gdshader": "res://diver_workbench/assets/shaders/diver_readability.gdshader",
}

const WORKBENCH_PATHS := [
	"res://underwater_map_workbench",
	"res://diver_workbench",
]

const REQUIRED_WORKBENCH_DOCUMENTS := [
	"AGENTS.md",
	"README.md",
	".ai/PROJECT_CONTEXT.md",
	".ai/DECISIONS.md",
]

const FORBIDDEN_LEGACY_PATHS := [
	"res://scenes/diving/UnderwaterMap.tscn",
	"res://scenes/diving/Diver.tscn",
	"res://scripts/diving/DiverController.gd",
	"res://scripts/diving/DiverController.gd.uid",
	"res://scripts/diving/DiverVisualEffects.gd",
	"res://scripts/diving/DiverVisualEffects.gd.uid",
	"res://scripts/definitions/DiverSocketProfile.gd",
	"res://scripts/definitions/DiverSocketProfile.gd.uid",
	"res://assets/diving",
	"res://underwater_map_workbench/assets/gameplay/diver",
	"res://tests/DiverPresentationCapture.tscn",
	"res://tests/DiverPresentationTest.tscn",
	"res://tests/diver_presentation_capture.gd",
	"res://tests/diver_presentation_capture.gd.uid",
	"res://tests/diver_presentation_test.gd",
	"res://tests/diver_presentation_test.gd.uid",
	"res://scripts/diving/DiveEnterableTowerController.gd",
	"res://scripts/diving/DiveEnterableTowerController.gd.uid",
	"res://scripts/diving/DivePowerDistributorPanel.gd",
	"res://scripts/diving/DivePowerDistributorPanel.gd.uid",
	"res://scripts/diving/DiveStructureInteractable.gd",
	"res://scripts/diving/DiveStructureInteractable.gd.uid",
	"res://tests/enterable_tower_runtime_test.gd",
	"res://tests/enterable_tower_runtime_test.gd.uid",
	"res://underwater_map_workbench/assets/visual/structures/tower_prototype_01",
	"res://underwater_map_workbench/assets/generated/l05/structures/tower_prototype_01",
]

const REFERENCE_SOURCE_PATHS := [
	"res://project.godot",
	"res://scenes/diving/DiveScene.tscn",
	"res://scripts/diving/DiveController.gd",
	"res://scripts/diving/ContinuousDiveWorld.gd",
	"res://underwater_map_workbench/map_manifest.json",
	"res://underwater_map_workbench/UnderwaterMap.tscn",
	"res://underwater_map_workbench/runtime/UnderwaterMapRuntime.gd",
	"res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd",
	"res://diver_workbench/runtime/Diver.tscn",
	"res://diver_workbench/runtime/DiverController.gd",
	"res://diver_workbench/runtime/DiverVisualEffects.gd",
	"res://diver_workbench/definitions/DiverSocketProfile.gd",
	"res://diver_workbench/assets/animation/diver_sprite_frames.tres",
	"res://diver_workbench/assets/profiles/diver_socket_profile.tres",
]

const DIVER_ROOT_CONTROLLER_PATH := "res://scripts/diving/DiveController.gd"
const ROOT_TEST_RUNNER_PATH := "res://tests/run_all_tests.ps1"
const ROOT_STRUCTURE_INTEGRATION_SOURCE_PATHS := [
	"res://scripts/diving/DiveController.gd",
	"res://scripts/diving/ContinuousDiveWorld.gd",
]
const MAP_STRUCTURE_INTEGRATION_SOURCE_PATHS := [
	"res://underwater_map_workbench/tools/build_underwater_map.py",
	"res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd",
	"res://underwater_map_workbench/tests/underwater_map_smoke_test.gd",
	"res://underwater_map_workbench/tests/underwater_map_proxy_capture_test.gd",
]
const GENERIC_STRUCTURE_DOCUMENT_PATHS := [
	"res://underwater_map_workbench/AGENTS.md",
	"res://underwater_map_workbench/README.md",
	"res://underwater_map_workbench/.ai/PROJECT_CONTEXT.md",
	"res://diver_workbench/AGENTS.md",
	"res://diver_workbench/README.md",
	"res://diver_workbench/.ai/PROJECT_CONTEXT.md",
	"res://diver_workbench/.ai/DECISIONS.md",
]
const BASE_FORBIDDEN_ROOT_STRUCTURE_FRAGMENTS := [
	"res://underwater_map_workbench/structures/",
]
const GENERIC_STRUCTURE_FRAGMENT_EXCEPTIONS := {
	"interactives": true,
	"current_zone": true,
}
const APPROVED_STRUCTURE_EXTERNAL_REFERENCES := [
	"res://underwater_map_workbench/UnderwaterMap.tscn",
	"res://underwater_map_workbench/assets/shaders/structure_clip_masked.gdshader",
	"res://underwater_map_workbench/runtime/UnderwaterMapRuntime.gd",
	"res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd",
	"res://diver_workbench/runtime/DiverController.gd",
	"res://scripts/data/ExpeditionSetup.gd",
	"res://scripts/data/UnderwaterWorldState.gd",
	"res://scripts/ui/InputPrompt.gd",
]
const FORBIDDEN_DIVER_ROOT_FRAGMENTS := [
	"diver.input_enabled",
	"diver.current_velocity",
	"diver.movement_input",
	"diver.is_sprinting",
	"diver.movement_speed_multiplier",
	"Diver/DiveLight",
	"Diver/Camera2D",
	"Diver/VisualEffects",
	"Diver/AnimatedSprite2D",
]

const DECISION_REGISTRIES := {
	"res://underwater_map_workbench/.ai/DECISIONS.md": "MAP-ARD",
	"res://diver_workbench/.ai/DECISIONS.md": "DIVER-ARD",
}

const REQUIRED_AGENT_CONCURRENCY_FRAGMENTS := {
	"res://AGENTS.md": [
		"osobnych pełnych Git worktrees",
		"workbench_contract.py",
		"candidate receiptem",
		"run receiptem",
		"codex-agent-assignments/v1",
		"WAITING_ACK",
		"RUNNING",
		"redispatch",
		"jednej komendzie batch",
		"map-promotion",
		"freeze_workbench_revision.py",
	],
	"res://underwater_map_workbench/AGENTS.md": [
		"osobnym pełnym Git worktree",
		"--seal-structure-package",
		"--build-structure",
		"jednej komendzie batch",
		"map-promotion",
	],
	"res://diver_workbench/AGENTS.md": [
		"Osobny CWD nie izoluje wspólnego checkoutu",
		"nie wykonuje discovery",
		"user://",
		"-InPlace",
	],
}
const REQUIRED_CONCURRENCY_GUARD_FRAGMENTS := {
	"res://tools/workbench_contract.py": [
		"owner_for_path",
		"create_publication_receipt",
		"verify_publication_receipt",
		"PUBLICATION_READY",
		"create_assignment",
		"acknowledge_assignment",
		"validate_assignment_context",
		"assignment_gc_plan",
	],
	"res://tests/workbench_contract_test.py": [
		"test_owner_classification_and_generated_boundary",
		"test_structure_doctor_rejects_typo_and_requires_explicit_staging",
		"test_publication_lock_is_shared_by_linked_worktrees",
		"test_receipt_verifies_clean_closed_candidate",
		"test_timeout_redispatch_keeps_same_task_thread_and_bundle",
		"test_process_races_create_one_bundle_and_one_ack_event",
		"test_cli_validate_assignment_diff_fails_outside_closed_set",
	],
	"res://tools/setup_agent_worktree.ps1": [
		"CandidateReceipt",
		"RunReceipt",
		"TaskId",
		"ThreadId",
		"WriteSet",
		"codex/$safeOwner/$TaskSlug",
		"Test-CandidateReceiptsAtCommit",
		"Remove-WorktreeAttempt",
		"assignment', 'create",
		"WAITING_ACK",
	],
	"res://tests/setup_agent_worktree_test.ps1": [
		"AfterGitWorktreeAdd",
		"two distinct processes",
		"Parallel loser removed or invalidated the winning worktree resource",
		"dirty isolation",
		"rollback contract",
		"Exact assignment ACK failed",
		"Assignment overlap rollback",
	],
	"res://.githooks/pre-push": [
		"refs/heads/codex/",
		"CODEX_INTEGRATOR_ALLOW_MAIN_PUSH",
		"merge-base --is-ancestor",
		"force-pushowac",
	],
	"res://tools/install_agent_git_hooks.ps1": [
		"PLAN ONLY",
		"core.hooksPath",
		"-Install -Force",
		"linked worktrees",
	],
	"res://tests/pre_push_guard_test.ps1": [
		"codex-only",
		"fast-forward",
		"integrator-bypass",
		"linked-worktree",
	],
	"res://.github/workflows/agent-integration.yml": [
		"repository_dispatch",
		"integration-green",
		"GODOT_ARCHIVE_SHA256",
		"HEADLESS_SHARD_COUNT",
		"NATIVE_SHARD_COUNT",
		"ci_protected_paths.py",
		"ci_python_entry.py",
		"WriteShardPlan",
		"AggregateShardReceipt",
	],
	"res://tools/workbench_lock.py": [
		"class InterprocessWorkspaceLock",
		"CODEX_THREAD_ID",
	],
	"res://tests/workbench_lock_test.py": [
		"test_same_lock_is_exclusive_between_processes",
		"test_disjoint_locks_can_be_held_together",
	],
	"res://tools/freeze_workbench_revision.py": [
		"FROZEN_RECEIPT.json",
		"freeze_revision",
		"verify_revision",
	],
	"res://tests/freeze_workbench_revision_test.py": [
		"test_freeze_publishes_receipt_last_and_verify_accepts_it",
		"test_mutation_or_extra_file_invalidates_frozen_revision",
	],
	"res://underwater_map_workbench/tools/build_underwater_map.py": [
		"InterprocessWorkspaceLock",
		"map-promotion",
		"_structure_local_output_root",
		"underwater_map_structure_builds",
		"_structure_local_build_lock",
		"_refresh_structure_packages",
	],
	"res://tests/map_atomic_write_test.py": [
		"test_stale_baseline_is_rejected_before_first_write",
		"test_rollback_never_overwrites_concurrent_edit",
		"test_different_structure_builds_use_disjoint_local_lanes",
		"test_structure_fingerprint_does_not_open_another_private_package",
		"test_batch_refresh_resolves_two_stale_pins_without_partial_write",
		"test_main_pairs_repeated_structure_refresh_arguments_as_one_batch",
	],
	"res://tests/run_all_tests.ps1": [
		"-InPlace is disabled",
		"Get-GitSnapshotProjectPaths",
		"sourceBefore",
		"FROZEN copy",
		"maxSnapshotAttempts = 3",
		"custom_user_dir_name",
		"godot-test-overlay-v1",
		"godot-test-run-receipt-v2",
		"godot-test-shard-plan-v1",
		"godot-test-shard-receipt-v2",
		"godot-test-aggregate-receipt-v2",
		"VerifyRunReceipt",
		"Get-ExplicitStructureTestPackageId",
		"Invoke-IsolatedStructureTargetOverlay",
		"--debug-server",
		"--dap-port",
		"--lsp-port",
	],
	"res://tests/runner_isolation_test.ps1": [
		"Run receipt verifier accepted a tampered canonical body",
		"HEAD/tree do not match",
		"Receipt binding accepted a targeted run",
		"Receipt binding accepted a full-suite",
		"required full-suite PASS",
	],
	"res://tests/parallel_worktree_godot_test.ps1": [
		"temporary_commit_from_git_closed_working_snapshot",
		"linked_common_dir",
		"concurrent_overlap_ms",
		"retained_user_directories",
	],
}

const SCAN_EXCLUDED_DIRECTORY_NAMES := {
	".git": true,
	".godot": true,
	".import": true,
	".cache": true,
	"__pycache__": true,
}

var _failed := false
var _structure_package_ids: Array[String] = []
var _structure_reference_source_paths: Array[String] = []
var _private_structure_fragments: Array[String] = []
var _approved_structure_provenance_document_paths: Array[String] = []


func _initialize() -> void:
	_assert_unique_authorities()
	_assert_legacy_authorities_absent()
	_assert_structure_packages()
	_assert_workbench_boundaries()
	_assert_authority_references_exist()
	_assert_structure_reference_boundaries()
	_assert_structure_public_boundary()
	_assert_structure_documentation_boundary()
	_assert_structure_test_discovery()
	_assert_diver_public_boundary()
	_assert_local_decision_indexes()
	_assert_concurrency_contracts()
	_finish()


func _assert_concurrency_contracts() -> void:
	for document_path in REQUIRED_AGENT_CONCURRENCY_FRAGMENTS:
		_assert_file_contains_fragments(
			document_path,
			REQUIRED_AGENT_CONCURRENCY_FRAGMENTS[document_path],
			"Instrukcja agentów nie publikuje wymaganej reguły współbieżności",
		)
	for source_path in REQUIRED_CONCURRENCY_GUARD_FRAGMENTS:
		_assert_file_contains_fragments(
			source_path,
			REQUIRED_CONCURRENCY_GUARD_FRAGMENTS[source_path],
			"Brakuje mechanicznej ochrony współbieżności",
		)

	for structure_id in _structure_package_ids:
		var agents_path := STRUCTURE_PACKAGES_PATH.path_join(structure_id).path_join("AGENTS.md")
		_assert_file_contains_fragments(
			agents_path,
			[
				"osobnym pełnym Git worktree",
				"lokalny seal",
				"map-promotion",
			],
			"Instrukcja pakietu struktury nie chroni wspólnej promocji",
		)


func _assert_file_contains_fragments(
	resource_path: String,
	required_fragments: Array,
	failure_prefix: String,
) -> void:
	var source_file := FileAccess.open(resource_path, FileAccess.READ)
	_assert(source_file != null, "%s: %s." % [failure_prefix, resource_path])
	if source_file == null:
		return
	var source_text := source_file.get_as_text()
	for fragment_value: Variant in required_fragments:
		var fragment := str(fragment_value)
		_assert(
			source_text.contains(fragment),
			"%s: %s nie zawiera '%s'." % [failure_prefix, resource_path, fragment],
		)


func _assert_unique_authorities() -> void:
	var found_paths := {}
	for file_name in UNIQUE_AUTHORITY_PATHS:
		found_paths[file_name] = []

	var project_root := ProjectSettings.globalize_path("res://")
	_collect_named_files(project_root, "", found_paths)

	for file_name in UNIQUE_AUTHORITY_PATHS:
		var actual_paths: Array = found_paths[file_name]
		actual_paths.sort()
		var expected_path: String = UNIQUE_AUTHORITY_PATHS[file_name]
		var matches_expected := actual_paths.size() == 1
		if matches_expected:
			matches_expected = actual_paths[0] == expected_path
		_assert(
			matches_expected,
			"Authority %s musi występować dokładnie raz pod %s; znaleziono: %s."
			% [file_name, expected_path, actual_paths],
		)


func _collect_named_files(
	absolute_directory_path: String,
	relative_directory_path: String,
	found_paths: Dictionary,
) -> void:
	var directory := DirAccess.open(absolute_directory_path)
	if directory == null:
		_assert(false, "Nie można odczytać katalogu podczas kontroli granic: %s." % absolute_directory_path)
		return

	directory.include_hidden = true
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		var is_directory := directory.current_is_dir()
		var child_absolute_path := absolute_directory_path.path_join(entry_name)
		var child_relative_path := entry_name
		if not relative_directory_path.is_empty():
			child_relative_path = relative_directory_path.path_join(entry_name)
		child_relative_path = child_relative_path.replace("\\", "/")
		if is_directory:
			if not SCAN_EXCLUDED_DIRECTORY_NAMES.has(entry_name):
				_collect_named_files(child_absolute_path, child_relative_path, found_paths)
		elif found_paths.has(entry_name):
			found_paths[entry_name].append("res://" + child_relative_path)
		entry_name = directory.get_next()
	directory.list_dir_end()


func _assert_legacy_authorities_absent() -> void:
	for legacy_path in FORBIDDEN_LEGACY_PATHS:
		_assert(
			not _path_exists(legacy_path),
			"Dawna kopia authority albo lokalnego testu nie może pozostać pod %s." % legacy_path,
		)


func _assert_structure_packages() -> void:
	_structure_package_ids.clear()
	_structure_reference_source_paths.clear()
	_private_structure_fragments.clear()
	var packages_absolute_path := ProjectSettings.globalize_path(STRUCTURE_PACKAGES_PATH)
	_assert(
		DirAccess.dir_exists_absolute(packages_absolute_path),
		"Warsztat Mapy musi zawierać katalog zarejestrowanych pakietów %s."
		% STRUCTURE_PACKAGES_PATH,
	)
	if not DirAccess.dir_exists_absolute(packages_absolute_path):
		return

	var package_ids_on_disk := _collect_immediate_structure_package_ids(packages_absolute_path)
	var map_manifest := _read_json_dictionary(MAP_MANIFEST_PATH)
	if map_manifest.is_empty():
		return
	var structures_value: Variant = map_manifest.get("structures", null)
	_assert(structures_value is Dictionary, "Manifest mapy musi publikować słownik structures.")
	if not structures_value is Dictionary:
		return
	var structures := structures_value as Dictionary
	_assert(
		not structures.has("templates"),
		"Schema v6 nie może utrzymywać drugiej kopii templates w map_manifest.json.",
	)
	var instances_value: Variant = structures.get("instances", null)
	_assert(instances_value is Array, "Manifest mapy musi publikować tablicę structures.instances.")
	if not instances_value is Array:
		return

	var reference_counts := {}
	for instance_value: Variant in (instances_value as Array):
		_assert(instance_value is Dictionary, "Każdy rekord structures.instances musi być słownikiem.")
		if not instance_value is Dictionary:
			continue
		var instance := instance_value as Dictionary
		var structure_id := str(instance.get("id", "")).strip_edges()
		_assert(_is_valid_structure_id(structure_id), "Niepoprawne stable ID pakietu struktury: '%s'." % structure_id)
		if structure_id.is_empty():
			continue
		for instance_key: Variant in instance.keys():
			_assert(
				MAP_STRUCTURE_INSTANCE_KEYS.has(str(instance_key)),
				"Mapowy rekord %s zawiera pole spoza publicznego rejestru: '%s'."
				% [structure_id, instance_key],
			)
		for forbidden_key in FORBIDDEN_MAP_STRUCTURE_INSTANCE_KEYS:
			_assert(
				not instance.has(forbidden_key),
				"Mapowy rekord %s powiela prywatne pole pakietu '%s'."
				% [structure_id, forbidden_key],
			)
		_assert(instance.has("origin"), "Mapowy rekord %s musi być właścicielem originu." % structure_id)
		_assert(instance.has("enabled"), "Mapowy rekord %s musi publikować aktywność." % structure_id)

		var package_value: Variant = instance.get("package", null)
		_assert(package_value is Dictionary, "Mapowy rekord %s musi wskazywać pakiet." % structure_id)
		if not package_value is Dictionary:
			continue
		var package := package_value as Dictionary
		for package_key: Variant in package.keys():
			_assert(
				MAP_STRUCTURE_PACKAGE_KEYS.has(str(package_key)),
				"Mapowa referencja pakietu %s zawiera prywatne pole '%s'."
				% [structure_id, package_key],
			)
		_assert(
			str(package.get("format", "")) == "structure_package_v1",
			"Mapowy rekord %s musi używać format=structure_package_v1." % structure_id,
		)
		var relative_manifest_path := str(package.get("path", "")).replace("\\", "/").strip_edges()
		var expected_relative_path := "structures/%s/%s" % [structure_id, STRUCTURE_MANIFEST_FILE]
		var path_matches_registry := relative_manifest_path == expected_relative_path
		var path_is_safe := _is_safe_package_relative_path(relative_manifest_path)
		_assert(
			path_matches_registry,
			"Pakiet %s musi być wskazany dokładnie przez %s; otrzymano %s."
			% [structure_id, expected_relative_path, relative_manifest_path],
		)
		_assert(
			path_is_safe,
			"Referencja pakietu %s nie może wychodzić poza warsztat: %s."
			% [structure_id, relative_manifest_path],
		)
		reference_counts[structure_id] = int(reference_counts.get(structure_id, 0)) + 1
		if not path_matches_registry or not path_is_safe:
			continue

		var manifest_resource_path := MAP_WORKBENCH_PATH.path_join(relative_manifest_path)
		_assert(
			FileAccess.file_exists(manifest_resource_path),
			"Zarejestrowany manifest struktury nie istnieje: %s." % manifest_resource_path,
		)
		if not FileAccess.file_exists(manifest_resource_path):
			continue
		var declared_sha := str(package.get("sha256", "")).to_lower()
		var actual_sha := FileAccess.get_sha256(manifest_resource_path).to_lower()
		_assert(
			declared_sha.length() == 64 and declared_sha == actual_sha,
			"Hash manifestu pakietu %s jest nieaktualny: deklarowany %s, faktyczny %s."
			% [structure_id, declared_sha, actual_sha],
		)
		var structure_manifest := _read_json_dictionary(manifest_resource_path)
		_assert_structure_manifest(structure_id, manifest_resource_path.get_base_dir(), structure_manifest)
		_register_private_structure_fragments(structure_id, structure_manifest)

	for structure_id in package_ids_on_disk:
		_assert(
			int(reference_counts.get(structure_id, 0)) == 1,
			"Katalog struktury %s musi mieć dokładnie jedną mapową referencję; znaleziono %d."
			% [structure_id, int(reference_counts.get(structure_id, 0))],
		)
		_structure_package_ids.append(structure_id)
		var package_resource_path := STRUCTURE_PACKAGES_PATH.path_join(structure_id)
		for required_file in REQUIRED_STRUCTURE_PACKAGE_FILES:
			_assert(
				FileAccess.file_exists(package_resource_path.path_join(required_file)),
				"Pakiet %s musi zawierać %s." % [structure_id, required_file],
			)
		_assert_structure_package_layout(structure_id, package_resource_path)
		_assert_structure_package_documents(structure_id, package_resource_path, package_ids_on_disk)
		_collect_structure_reference_sources(
			ProjectSettings.globalize_path(package_resource_path),
			package_resource_path,
			_structure_reference_source_paths,
		)

	for structure_id in reference_counts:
		_assert(
			package_ids_on_disk.has(str(structure_id)),
			"Mapowy rejestr wskazuje brakujący katalog struktury %s." % structure_id,
		)
	_structure_package_ids.sort()
	_structure_reference_source_paths.sort()
	_private_structure_fragments.sort()


func _register_private_structure_fragments(structure_id: String, manifest: Dictionary) -> void:
	if not _private_structure_fragments.has(structure_id):
		_private_structure_fragments.append(structure_id)
	var template_value: Variant = manifest.get("template", null)
	if template_value is Dictionary:
		var template := template_value as Dictionary
		for fragment_value in [template.get("id", ""), template.get("kind", "")]:
			_register_private_structure_fragment(str(fragment_value))
		var socket_kinds_value: Variant = template.get("allowed_socket_kinds", null)
		if socket_kinds_value is Array:
			for socket_kind_value: Variant in socket_kinds_value as Array:
				var socket_kind := str(socket_kind_value)
				if not GENERIC_STRUCTURE_FRAGMENT_EXCEPTIONS.has(socket_kind):
					_register_private_structure_fragment(socket_kind)
	var runtime_value: Variant = manifest.get("runtime", null)
	if runtime_value is Dictionary:
		var runtime := runtime_value as Dictionary
		_register_private_structure_fragment(str(runtime.get("contract", "")))
		for runtime_key_value: Variant in runtime.keys():
			var runtime_key := str(runtime_key_value)
			if runtime_key != "contract" and not GENERIC_STRUCTURE_FRAGMENT_EXCEPTIONS.has(runtime_key):
				_register_private_structure_fragment(runtime_key)
	var scripts_value: Variant = manifest.get("scripts", null)
	if not scripts_value is Array:
		return
	for script_value: Variant in scripts_value as Array:
		if not script_value is Dictionary:
			continue
		var relative_path := str((script_value as Dictionary).get("path", "")).replace("\\", "/")
		var file_name := relative_path.get_file()
		for fragment in [file_name, file_name.get_basename()]:
			_register_private_structure_fragment(fragment)


func _register_private_structure_fragment(fragment_value: Variant) -> void:
	var fragment := str(fragment_value).strip_edges()
	if not fragment.is_empty() and not _private_structure_fragments.has(fragment):
		_private_structure_fragments.append(fragment)


func _assert_structure_package_layout(structure_id: String, package_resource_path: String) -> void:
	var found_manifests := {STRUCTURE_MANIFEST_FILE: []}
	_collect_named_files(
		ProjectSettings.globalize_path(package_resource_path),
		package_resource_path.trim_prefix("res://"),
		found_manifests,
	)
	var manifest_paths: Array = found_manifests[STRUCTURE_MANIFEST_FILE]
	var expected_manifest_path := package_resource_path.path_join(STRUCTURE_MANIFEST_FILE)
	_assert(
		manifest_paths.size() == 1 and manifest_paths[0] == expected_manifest_path,
		"Pakiet %s musi zawierać dokładnie jeden manifest pod %s; znaleziono %s."
		% [structure_id, expected_manifest_path, manifest_paths],
	)

	var tests_resource_path := package_resource_path.path_join("tests")
	var contract_tests := _collect_immediate_files_with_suffix(tests_resource_path, "_package_contract_test.gd")
	var runtime_tests := _collect_immediate_files_with_suffix(tests_resource_path, "_runtime_test.gd")
	_assert(
		contract_tests.size() == 1,
		"Pakiet %s musi mieć dokładnie jeden lokalny *_package_contract_test.gd; znaleziono %s."
		% [structure_id, contract_tests],
	)
	_assert(
		runtime_tests.size() == 1,
		"Pakiet %s musi mieć dokładnie jeden lokalny *_runtime_test.gd; znaleziono %s."
		% [structure_id, runtime_tests],
	)


func _collect_immediate_files_with_suffix(resource_directory_path: String, suffix: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(ProjectSettings.globalize_path(resource_directory_path))
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if not directory.current_is_dir() and entry_name.ends_with(suffix):
			result.append(resource_directory_path.path_join(entry_name))
		entry_name = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result


func _assert_structure_package_documents(
	structure_id: String,
	package_resource_path: String,
	all_structure_ids: Array[String],
) -> void:
	var exact_package_path := "underwater_map_workbench/structures/%s/" % structure_id
	for document_name in APPROVED_STRUCTURE_DOCUMENTS:
		var document_path := package_resource_path.path_join(document_name)
		var document_file := FileAccess.open(document_path, FileAccess.READ)
		_assert(document_file != null, "Nie można odczytać dokumentu pakietu %s." % document_path)
		if document_file == null:
			continue
		var document_text := document_file.get_as_text()
		for required_fragment in [structure_id, exact_package_path, "../../map_manifest.json", "structure_manifest.json"]:
			_assert(
				document_text.contains(required_fragment),
				"Dokument %s nie identyfikuje własnego pakietu przez fragment '%s'."
				% [document_path, required_fragment],
			)
		if document_name == "AGENTS.md":
			for routing_fragment in [
				"allowlista zapisu",
				exact_package_path + "**",
				"tylko do odczytu",
				"../../AGENTS.md",
				"../../../AGENTS.md",
			]:
				_assert(
					document_text.contains(routing_fragment),
					"Lokalny AGENTS %s nie publikuje wymaganej granicy przez fragment '%s'."
					% [document_path, routing_fragment],
				)
		for other_structure_id in all_structure_ids:
			if other_structure_id == structure_id:
				continue
			_assert(
				not document_text.contains("structures/%s/" % other_structure_id),
				"Dokument %s wskazuje prywatną ścieżkę innego pakietu %s."
				% [document_path, other_structure_id],
			)


func _collect_immediate_structure_package_ids(absolute_packages_path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(absolute_packages_path)
	_assert(directory != null, "Nie można odczytać katalogu pakietów struktur.")
	if directory == null:
		return result
	directory.include_hidden = true
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if directory.current_is_dir() and not SCAN_EXCLUDED_DIRECTORY_NAMES.has(entry_name):
			_assert(_is_valid_structure_id(entry_name), "Niepoprawna nazwa katalogu struktury: %s." % entry_name)
			result.append(entry_name)
		entry_name = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result


func _is_valid_structure_id(structure_id: String) -> bool:
	var id_regex := RegEx.new()
	if id_regex.compile("^[a-z][a-z0-9_]*$") != OK:
		return false
	return id_regex.search(structure_id) != null


func _assert_structure_manifest(
	structure_id: String,
	package_resource_path: String,
	manifest: Dictionary,
) -> void:
	if manifest.is_empty():
		return
	_assert(
		int(manifest.get("schema_version", 0)) == 1,
		"Pakiet %s musi używać structure manifest schema v1." % structure_id,
	)
	_assert(
		str(manifest.get("format", "")) == "enterable_structure_package_v1",
		"Pakiet %s ma nieobsługiwany format manifestu." % structure_id,
	)
	for forbidden_key in FORBIDDEN_STRUCTURE_MANIFEST_ROOT_KEYS:
		_assert(
			not manifest.has(forbidden_key),
			"Manifest pakietu %s nie może publikować mapowego lub trwałego pola '%s'."
			% [structure_id, forbidden_key],
		)

	var attempt_state_value: Variant = manifest.get("attempt_state", null)
	_assert(attempt_state_value is Dictionary, "Pakiet %s musi deklarować attempt_state." % structure_id)
	if attempt_state_value is Dictionary:
		var attempt_state := attempt_state_value as Dictionary
		_assert(
			str(attempt_state.get("persistence", "")) == "none",
			"Pakiet %s nie może włączać persistence." % structure_id,
		)
		_assert(
			str(attempt_state.get("checkpoint", "")) == "none",
			"Pakiet %s nie może publikować checkpointu." % structure_id,
		)
	_assert_structure_persistence_boundary(manifest, structure_id)

	for collection_name in STRUCTURE_REFERENCE_COLLECTIONS:
		var collection_value: Variant = manifest.get(collection_name, [])
		_assert(
			collection_value is Array,
			"Pole %s pakietu %s musi być tablicą." % [collection_name, structure_id],
		)
		if not collection_value is Array:
			continue
		for record_value: Variant in (collection_value as Array):
			_assert(
				record_value is Dictionary,
				"Każdy rekord %s pakietu %s musi być słownikiem."
				% [collection_name, structure_id],
			)
			if not record_value is Dictionary:
				continue
			var record := record_value as Dictionary
			if collection_name == "references":
				_assert(
					record.get("authority", true) == false,
					"Referencja provenance pakietu %s musi deklarować authority=false."
					% structure_id,
				)
			var relative_path := str(record.get("path", "")).replace("\\", "/").strip_edges()
			_assert(
				_is_safe_package_relative_path(relative_path),
				"Pakiet %s zawiera niebezpieczną ścieżkę w %s: %s."
				% [structure_id, collection_name, relative_path],
			)
			if not _is_safe_package_relative_path(relative_path):
				continue
			var resource_path := package_resource_path.path_join(relative_path)
			if (
				collection_name == "references"
				and record.get("authority", true) == false
				and DOCUMENTATION_EXTENSIONS.has(relative_path.get_extension().to_lower())
				and not _approved_structure_provenance_document_paths.has(resource_path)
			):
				_approved_structure_provenance_document_paths.append(resource_path)
			_assert(
				FileAccess.file_exists(resource_path),
				"Źródło pakietu %s nie istnieje: %s." % [structure_id, resource_path],
			)
			if not FileAccess.file_exists(resource_path):
				continue
			if collection_name == "scripts":
				_assert_structure_script_is_path_private(structure_id, resource_path)
			var declared_sha := str(record.get("sha256", "")).to_lower()
			if not declared_sha.is_empty():
				var actual_sha := FileAccess.get_sha256(resource_path).to_lower()
				_assert(
					declared_sha.length() == 64 and declared_sha == actual_sha,
					"Hash źródła pakietu %s jest nieaktualny dla %s."
					% [structure_id, relative_path],
				)


func _assert_structure_script_is_path_private(structure_id: String, resource_path: String) -> void:
	var source_file := FileAccess.open(resource_path, FileAccess.READ)
	_assert(source_file != null, "Nie można odczytać prywatnego skryptu pakietu %s." % resource_path)
	if source_file == null:
		return
	for source_line: String in source_file.get_as_text().split("\n"):
		var normalized_line := source_line.strip_edges()
		_assert(
			normalized_line != "class_name"
			and not normalized_line.begins_with("class_name ")
			and not normalized_line.begins_with("class_name\t"),
			"Prywatny skrypt pakietu %s nie może publikować globalnego class_name: %s."
			% [structure_id, resource_path],
		)


func _assert_structure_persistence_boundary(value: Variant, structure_id: String, path: String = "") -> void:
	if value is Dictionary:
		for key_value: Variant in (value as Dictionary).keys():
			var key := str(key_value).to_lower()
			var child_path := key if path.is_empty() else path + "." + key
			if key in ["persistent_id", "checkpoint_id", "save_key", "world_delta", "respawn_id"]:
				_assert(false, "Pakiet %s publikuje zabronione pole trwałego stanu %s." % [structure_id, child_path])
			elif key in ["persistence", "checkpoint"] and path != "attempt_state":
				_assert(false, "Pakiet %s publikuje %s poza deklaracją attempt_state." % [structure_id, child_path])
			_assert_structure_persistence_boundary((value as Dictionary)[key_value], structure_id, child_path)
	elif value is Array:
		for item: Variant in (value as Array):
			_assert_structure_persistence_boundary(item, structure_id, path)


func _is_safe_package_relative_path(relative_path: String) -> bool:
	if relative_path.is_empty() or relative_path.begins_with("/") or relative_path.begins_with("res://"):
		return false
	if relative_path.contains(":/") or relative_path == "..":
		return false
	return not relative_path.begins_with("../") and not relative_path.contains("/../")


func _read_json_dictionary(resource_path: String) -> Dictionary:
	var source_file := FileAccess.open(resource_path, FileAccess.READ)
	_assert(source_file != null, "Nie można odczytać JSON %s." % resource_path)
	if source_file == null:
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(source_file.get_as_text())
	_assert(
		parse_error == OK,
		"Niepoprawny JSON %s, linia %d: %s."
		% [resource_path, parser.get_error_line(), parser.get_error_message()],
	)
	if parse_error != OK:
		return {}
	_assert(parser.data is Dictionary, "Korzeń JSON %s musi być słownikiem." % resource_path)
	if parser.data is Dictionary:
		return parser.data as Dictionary
	return {}


func _collect_structure_reference_sources(
	absolute_directory_path: String,
	resource_directory_path: String,
	source_paths: Array[String],
) -> void:
	var directory := DirAccess.open(absolute_directory_path)
	if directory == null:
		return
	directory.include_hidden = true
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		var is_directory := directory.current_is_dir()
		var child_absolute_path := absolute_directory_path.path_join(entry_name)
		var child_resource_path := resource_directory_path.path_join(entry_name).replace("\\", "/")
		if is_directory:
			if not SCAN_EXCLUDED_DIRECTORY_NAMES.has(entry_name):
				_collect_structure_reference_sources(
					child_absolute_path,
					child_resource_path,
					source_paths,
				)
		elif STRUCTURE_REFERENCE_SOURCE_EXTENSIONS.has(entry_name.get_extension().to_lower()):
			source_paths.append(child_resource_path)
		entry_name = directory.get_next()
	directory.list_dir_end()


func _assert_workbench_boundaries() -> void:
	for workbench_path in WORKBENCH_PATHS:
		_assert(
			DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(workbench_path)),
			"Brakuje zatwierdzonego warsztatu %s." % workbench_path,
		)
		for document_path in REQUIRED_WORKBENCH_DOCUMENTS:
			var full_document_path: String = workbench_path.path_join(document_path)
			_assert(
				FileAccess.file_exists(full_document_path),
				"Warsztat %s musi zawierać dokument %s." % [workbench_path, document_path],
			)

		var approved_document_paths := {}
		for document_path in REQUIRED_WORKBENCH_DOCUMENTS:
			approved_document_paths[workbench_path.path_join(document_path)] = true
		if workbench_path == MAP_WORKBENCH_PATH:
			for structure_id in _structure_package_ids:
				var package_path := STRUCTURE_PACKAGES_PATH.path_join(structure_id)
				for document_name in APPROVED_STRUCTURE_DOCUMENTS:
					approved_document_paths[package_path.path_join(document_name)] = true
			for provenance_document_path in _approved_structure_provenance_document_paths:
				approved_document_paths[provenance_document_path] = true
		var discovered_document_paths: Array[String] = []
		_collect_workbench_documentation(
			ProjectSettings.globalize_path(workbench_path),
			workbench_path,
			discovered_document_paths,
		)
		for document_path in discovered_document_paths:
			_assert(
				approved_document_paths.has(document_path),
				"Warsztat zawiera niezatwierdzony plik dokumentacji: %s." % document_path,
			)

		var forbidden_entries: Array[String] = []
		_collect_forbidden_workbench_entries(
			ProjectSettings.globalize_path(workbench_path),
			workbench_path,
			forbidden_entries,
		)
		for forbidden_entry in forbidden_entries:
			_assert(
				false,
				"Warsztat nie może zawierać własnego project.godot/cache .godot, a pakiet struktury także lokalnego .ai: %s."
				% forbidden_entry,
			)


func _collect_forbidden_workbench_entries(
	absolute_directory_path: String,
	resource_directory_path: String,
	forbidden_entries: Array[String],
) -> void:
	var directory := DirAccess.open(absolute_directory_path)
	if directory == null:
		return

	directory.include_hidden = true
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		var is_directory := directory.current_is_dir()
		var child_absolute_path := absolute_directory_path.path_join(entry_name)
		var child_resource_path := resource_directory_path.path_join(entry_name).replace("\\", "/")
		if is_directory:
			if (
				entry_name == ".godot"
				or (
					entry_name == ".ai"
					and child_resource_path.begins_with(STRUCTURE_PACKAGES_PATH + "/")
				)
			):
				forbidden_entries.append(child_resource_path)
			elif not SCAN_EXCLUDED_DIRECTORY_NAMES.has(entry_name):
				_collect_forbidden_workbench_entries(
					child_absolute_path,
					child_resource_path,
					forbidden_entries,
				)
		elif entry_name == "project.godot":
			forbidden_entries.append(child_resource_path)
		entry_name = directory.get_next()
	directory.list_dir_end()


func _collect_workbench_documentation(
	absolute_directory_path: String,
	resource_directory_path: String,
	document_paths: Array[String],
) -> void:
	var directory := DirAccess.open(absolute_directory_path)
	if directory == null:
		return
	directory.include_hidden = true
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		var is_directory := directory.current_is_dir()
		var child_absolute_path := absolute_directory_path.path_join(entry_name)
		var child_resource_path := resource_directory_path.path_join(entry_name).replace("\\", "/")
		if is_directory:
			if not SCAN_EXCLUDED_DIRECTORY_NAMES.has(entry_name):
				_collect_workbench_documentation(
					child_absolute_path,
					child_resource_path,
					document_paths,
				)
		elif DOCUMENTATION_EXTENSIONS.has(entry_name.get_extension().to_lower()):
			document_paths.append(child_resource_path)
		entry_name = directory.get_next()
	directory.list_dir_end()


func _assert_authority_references_exist() -> void:
	var reference_regex := RegEx.new()
	var regex_error := reference_regex.compile("res://[^\\x22\\x27\\r\\n]+")
	_assert(regex_error == OK, "Nie można przygotować parsera odwołań res://.")
	if regex_error != OK:
		return

	var checked_references := {}
	var source_paths: Array[String] = []
	source_paths.assign(REFERENCE_SOURCE_PATHS)
	for structure_source_path in _structure_reference_source_paths:
		if not source_paths.has(structure_source_path):
			source_paths.append(structure_source_path)
	for source_path in source_paths:
		var source_file := FileAccess.open(source_path, FileAccess.READ)
		_assert(source_file != null, "Nie można odczytać źródła authority %s." % source_path)
		if source_file == null:
			continue
		var source_text := source_file.get_as_text()
		for reference_match in reference_regex.search_all(source_text):
			var reference_path := reference_match.get_string().strip_edges()
			if reference_path.contains("%") or reference_path.contains("{"):
				continue
			var subresource_separator := reference_path.find("::")
			if subresource_separator >= 0:
				reference_path = reference_path.left(subresource_separator)
			var check_key := "%s -> %s" % [source_path, reference_path]
			if checked_references.has(check_key):
				continue
			checked_references[check_key] = true
			_assert(
				_path_exists(reference_path),
				"Odwołanie authority nie istnieje: %s wskazuje %s." % [source_path, reference_path],
			)


func _assert_structure_reference_boundaries() -> void:
	var reference_regex := RegEx.new()
	var regex_error := reference_regex.compile("res://[^\\x22\\x27\\r\\n]+")
	_assert(regex_error == OK, "Nie można przygotować parsera granic odwołań pakietów.")
	if regex_error != OK:
		return
	for source_path in _structure_reference_source_paths:
		var owning_structure_id := _structure_id_for_source_path(source_path)
		if owning_structure_id.is_empty():
			continue
		var source_file := FileAccess.open(source_path, FileAccess.READ)
		_assert(source_file != null, "Nie można odczytać źródła pakietu %s." % source_path)
		if source_file == null:
			continue
		var own_prefix := STRUCTURE_PACKAGES_PATH.path_join(owning_structure_id) + "/"
		for reference_match in reference_regex.search_all(source_file.get_as_text()):
			var reference_path := reference_match.get_string().strip_edges()
			var subresource_separator := reference_path.find("::")
			if subresource_separator >= 0:
				reference_path = reference_path.left(subresource_separator)
			if reference_path.begins_with(own_prefix):
				continue
			_assert(
				APPROVED_STRUCTURE_EXTERNAL_REFERENCES.has(reference_path),
				"Prywatne źródło pakietu %s wskazuje niezatwierdzoną zależność %s."
				% [source_path, reference_path],
			)


func _structure_id_for_source_path(source_path: String) -> String:
	var prefix := STRUCTURE_PACKAGES_PATH + "/"
	if not source_path.begins_with(prefix):
		return ""
	var relative_path := source_path.trim_prefix(prefix)
	var separator_index := relative_path.find("/")
	if separator_index <= 0:
		return ""
	var structure_id := relative_path.left(separator_index)
	return structure_id if _structure_package_ids.has(structure_id) else ""


func _assert_diver_public_boundary() -> void:
	var controller_file := FileAccess.open(DIVER_ROOT_CONTROLLER_PATH, FileAccess.READ)
	_assert(controller_file != null, "Nie można odczytać rootowego DiveController podczas kontroli granicy Nurka.")
	if controller_file == null:
		return
	var controller_source := controller_file.get_as_text()
	for forbidden_fragment in FORBIDDEN_DIVER_ROOT_FRAGMENTS:
		_assert(
			not controller_source.contains(str(forbidden_fragment)),
			"Rootowy DiveController omija publiczne API Nurka przez fragment '%s'." % forbidden_fragment,
		)


func _assert_structure_public_boundary() -> void:
	var root_forbidden_fragments: Array[String] = []
	for fragment in BASE_FORBIDDEN_ROOT_STRUCTURE_FRAGMENTS:
		root_forbidden_fragments.append(str(fragment))
	for fragment in _private_structure_fragments:
		if not root_forbidden_fragments.has(fragment):
			root_forbidden_fragments.append(fragment)
	_assert_sources_omit_structure_fragments(
		ROOT_STRUCTURE_INTEGRATION_SOURCE_PATHS,
		root_forbidden_fragments,
		"Rootowa integracja struktur",
	)
	_assert_sources_omit_structure_fragments(
		MAP_STRUCTURE_INTEGRATION_SOURCE_PATHS,
		_private_structure_fragments,
		"Ogólna integracja Mapy",
	)


func _assert_structure_documentation_boundary() -> void:
	_assert_sources_omit_structure_fragments(
		GENERIC_STRUCTURE_DOCUMENT_PATHS,
		_private_structure_fragments,
		"Ogólna dokumentacja warsztatów",
	)


func _assert_sources_omit_structure_fragments(
	source_paths: Array,
	forbidden_fragments: Array,
	boundary_label: String,
) -> void:
	for source_path_value: Variant in source_paths:
		var source_path := str(source_path_value)
		var source_file := FileAccess.open(source_path, FileAccess.READ)
		_assert(
			source_file != null,
			"Nie można odczytać źródła granicy '%s': %s." % [boundary_label, source_path],
		)
		if source_file == null:
			continue
		var source_text := source_file.get_as_text()
		for forbidden_fragment in forbidden_fragments:
			_assert(
				not source_text.contains(str(forbidden_fragment)),
				"%s w %s zna prywatny pakiet przez fragment '%s'."
				% [boundary_label, source_path, forbidden_fragment],
			)


func _assert_structure_test_discovery() -> void:
	var runner_file := FileAccess.open(ROOT_TEST_RUNNER_PATH, FileAccess.READ)
	_assert(runner_file != null, "Nie można odczytać wspólnego runnera testów struktur.")
	if runner_file == null:
		return
	var runner_source := runner_file.get_as_text()
	_assert(
		runner_source.contains("Get-StructurePackageTestTargets"),
		"Wspólny runner musi dynamicznie odkrywać testy pakietów struktur.",
	)
	for structure_id in _structure_package_ids:
		_assert(
			not runner_source.contains("underwater_map_workbench/structures/%s/tests/" % structure_id),
			"Wspólny runner nie może wpisywać na sztywno testów pakietu %s." % structure_id,
		)


func _assert_local_decision_indexes() -> void:
	for registry_path in DECISION_REGISTRIES:
		_assert_decision_index(registry_path, DECISION_REGISTRIES[registry_path])


func _assert_decision_index(registry_path: String, decision_prefix: String) -> void:
	var registry_file := FileAccess.open(registry_path, FileAccess.READ)
	_assert(registry_file != null, "Nie można odczytać lokalnego rejestru decyzji %s." % registry_path)
	if registry_file == null:
		return
	var registry_text := registry_file.get_as_text()

	var index_heading_regex := RegEx.new()
	index_heading_regex.compile(
		"(?m)^## (?:Indeks aktywnych decyzji|Active decisions index)\\s*$"
	)
	var index_heading_match := index_heading_regex.search(registry_text)
	if index_heading_match == null:
		_assert(
			false,
			"Lokalny rejestr %s musi deklarować jawny indeks aktywnych decyzji."
			% registry_path,
		)
		return

	var index_end := registry_text.find("\n## ", index_heading_match.get_end())
	if index_end < 0:
		index_end = registry_text.length()
	var index_block := registry_text.substr(
		index_heading_match.get_end(),
		index_end - index_heading_match.get_end(),
	)

	var id_pattern := decision_prefix + "-[0-9]{4}"
	var indexed_id_regex := RegEx.new()
	indexed_id_regex.compile("(?m)^\\|\\s*(%s)\\s*\\|" % id_pattern)
	var indexed_ids := {}
	for indexed_match in indexed_id_regex.search_all(index_block):
		var indexed_id := indexed_match.get_string(1)
		_assert(
			not indexed_ids.has(indexed_id),
			"Indeks %s zawiera zduplikowany wiersz %s." % [registry_path, indexed_id],
		)
		indexed_ids[indexed_id] = true
	_assert(
		not indexed_ids.is_empty(),
		"Jawny indeks %s w %s musi zawierać co najmniej jedną decyzję."
		% [decision_prefix, registry_path],
	)

	var entry_heading_regex := RegEx.new()
	entry_heading_regex.compile("(?m)^## (%s)\\b[^\\r\\n]*$" % id_pattern)
	var entry_matches := entry_heading_regex.search_all(registry_text)
	var status_regex := RegEx.new()
	status_regex.compile(
		"(?m)^- Status(?: / aktywny zakres)?:\\s*([^\\r\\n]+)$"
	)
	var statuses_by_id := {}
	var relations_by_id := {}
	var relation_regex := RegEx.new()
	relation_regex.compile("(?m)^- Relacje:\\s*([^\\r\\n]+)$")
	for entry_index in range(entry_matches.size()):
		var entry_match: RegExMatch = entry_matches[entry_index]
		var decision_id := entry_match.get_string(1)
		_assert(
			not statuses_by_id.has(decision_id),
			"Rejestr %s zawiera zduplikowany wpis %s." % [registry_path, decision_id],
		)
		var entry_end := registry_text.length()
		if entry_index + 1 < entry_matches.size():
			entry_end = entry_matches[entry_index + 1].get_start()
		var entry_block := registry_text.substr(
			entry_match.get_end(),
			entry_end - entry_match.get_end(),
		)
		var status_match := status_regex.search(entry_block)
		if status_match == null:
			statuses_by_id[decision_id] = ""
			_assert(false, "Wpis %s w %s nie publikuje statusu." % [decision_id, registry_path])
			continue
		statuses_by_id[decision_id] = status_match.get_string(1).strip_edges()
		var relation_match := relation_regex.search(entry_block)
		relations_by_id[decision_id] = (
			relation_match.get_string(1).strip_edges() if relation_match != null else ""
		)

	for decision_id in statuses_by_id:
		var status: String = statuses_by_id[decision_id]
		if _is_active_decision_status(status):
			_assert(
				indexed_ids.has(decision_id),
				"Aktywna decyzja %s z %s nie występuje w jawnym indeksie."
				% [decision_id, registry_path],
			)

	for decision_id in indexed_ids:
		_assert(
			statuses_by_id.has(decision_id),
			"Indeks %s wskazuje brakujący wpis %s." % [registry_path, decision_id],
		)
		if statuses_by_id.has(decision_id):
			_assert(
				_is_active_decision_status(statuses_by_id[decision_id]),
				"Indeks %s wskazuje nieaktywną decyzję %s o statusie '%s'."
				% [registry_path, decision_id, statuses_by_id[decision_id]],
			)

	_assert_replacement_symmetry(registry_path, decision_prefix, relations_by_id)


func _assert_replacement_symmetry(
	registry_path: String,
	decision_prefix: String,
	relations_by_id: Dictionary,
) -> void:
	var id_regex := RegEx.new()
	id_regex.compile(decision_prefix + "-[0-9]{4}")
	for replaced_id in relations_by_id:
		var relation := str(relations_by_id[replaced_id])
		var separator_index := relation.find("|")
		if separator_index < 0:
			continue
		var replacement_side := relation.substr(separator_index + 1)
		if not replacement_side.to_lower().contains("zastąp"):
			continue
		for target_match in id_regex.search_all(replacement_side):
			var replacing_id := target_match.get_string()
			_assert(
				relations_by_id.has(replacing_id),
				"Relacja %s w %s wskazuje brakujący wpis %s."
				% [replaced_id, registry_path, replacing_id],
			)
			if not relations_by_id.has(replacing_id):
				continue
			_assert(
				_relation_mentions_decision_id(
					str(relations_by_id[replacing_id]),
					decision_prefix,
					str(replaced_id),
				),
				"Zastąpienie %s -> %s w %s nie jest symetryczne."
				% [replaced_id, replacing_id, registry_path],
			)


func _relation_mentions_decision_id(
	relation: String,
	decision_prefix: String,
	decision_id: String,
) -> bool:
	if relation.contains(decision_id):
		return true
	var range_regex := RegEx.new()
	var compile_error := range_regex.compile(
		"%s-([0-9]{4})\\s*[–—]\\s*%s-([0-9]{4})"
		% [decision_prefix, decision_prefix]
	)
	if compile_error != OK:
		return false
	var decision_number := decision_id.trim_prefix(decision_prefix + "-").to_int()
	for range_match in range_regex.search_all(relation):
		var range_start := range_match.get_string(1).to_int()
		var range_end := range_match.get_string(2).to_int()
		if decision_number >= mini(range_start, range_end) and decision_number <= maxi(range_start, range_end):
			return true
	return false


func _is_active_decision_status(status: String) -> bool:
	var normalized_status := status.to_lower()
	return (
		normalized_status.begins_with("obowiązuje")
		or normalized_status.begins_with("częściowo zastąp")
		or normalized_status.begins_with("active")
	)


func _path_exists(resource_path: String) -> bool:
	return (
		FileAccess.file_exists(resource_path)
		or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(resource_path))
	)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print(
		"Workbench boundary test passed: Root, Map, nested Structure packages and Diver keep one authority and valid references."
	)
	quit(0)
