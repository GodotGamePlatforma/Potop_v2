# Tower Three Inlets 02

Ten katalog zawiera prywatny pakiet produkcyjnego budynku Mapy o stable ID `tower_three_inlets_02`. Nie jest osobnym projektem Godot. Wszystkie ścieżki w tym pliku są liczone od `underwater_map_workbench/structures/tower_three_inlets_02/`, a runner używa ścieżek `res://` projektu nadrzędnego.

## Źródła prawdy

| Źródło | Właściciel szczegółu |
|---|---|
| `../../map_manifest.json`, rekord `tower_three_inlets_02` po przypięciu | stable ID, globalny origin, aktywność, opcjonalny landmark i hash-pinned rejestracja pakietu |
| `structure_manifest.json` | lokalny rozmiar, szablon, topologia, sockety, grafika, skrypty, runtime i nietrwały cykl życia próby |
| `scripts/` | prywatna implementacja ładowana wyłącznie po hash-pinned ścieżkach z manifestu, bez globalnych `class_name` |
| `assets/proxy/` | natywne proxy `2400 × 3840`; źródła SVG i renderowane PNG, bez skalowania |
| `assets/visual/` | natywne źródła produkcyjne aktywowane wyłącznie przez `structure_manifest.json` po odbiorze proxy |
| `generated/` | deterministyczne maski, prowadnice, karty socketów i truth package; nie edytuj ręcznie |
| `tests/tower_package_contract_test.gd` | walidacja manifestu, hashy, topologii i pakietowych pochodnych |
| `tests/tower_runtime_test.gd` | lokalna weryfikacja stanów, kolejności, resetu i nietrwałości próby |
| `tests/tower_proxy_capture.gd` | natywny capture kadrów prywatnej struktury; nie jest automatycznym testem pełnego runnera |
| `references/Wiezowiec_02_Trzy_Wloty_Level0_POPRAWIONY_V2.docx` | poprawione provenance `authority=false`; nie jest źródłem runtime, topologii ani zapisu |
| `references/source_provenance.json` | hashe i pochodzenie załączonego pakietu wejściowego oraz materiałów pomocniczych |

Pakiet celowo nie publikuje własnego `structure_id` ani globalnego originu. Tożsamość i placement wynikają z jednej mapowej referencji. Lokalny manifest deklaruje `attempt_state.persistence=none` oraz `attempt_state.checkpoint=none`, lecz nie ustanawia osobnego systemu zapisu.

## Kontrakt authoringu grafiki

Aktywne źródła prezentacji wskazuje wyłącznie `structure_manifest.json`; README nie utrzymuje drugiej listy bieżących assetów. Proxy służą ocenie układu, skali, kolidera i socketów, a przyjęte źródła produkcyjne zachowują ten sam natywny raster `2400 × 3840`, bez resize.

Kolejność odbioru jest zamknięta:

1. walidacja pakietu oraz deterministyczny build struktury;
2. rejestracja w jednej Mapie i render dokładnej wygenerowanej `UnderwaterMap.tscn`;
3. oględziny pełnej kompozycji oraz kadrów gracza;
4. jawna akceptacja proxy przez użytkownika;
5. dopiero wtedy finalne źródła `2400 × 3840`, bez resize, oraz ponowny build/check/capture.

## Szybki start po rejestracji

Z CWD tego katalogu:

```powershell
Test-Path ..\..\..\project.godot
git -C ..\..\.. status --short --branch
python ..\..\tools\build_underwater_map.py --build-structure tower_three_inlets_02
python ..\..\tools\build_underwater_map.py --check-structure tower_three_inlets_02
..\..\..\tests\run_all_tests.ps1 -Target underwater_map_workbench/structures/tower_three_inlets_02/tests/tower_package_contract_test.gd
..\..\..\tests\run_all_tests.ps1 -Target underwater_map_workbench/structures/tower_three_inlets_02/tests/tower_runtime_test.gd
```

Powyższe komendy nie deklarują wyniku ostatniego przebiegu. Runner tworzy izolowaną pełną kopię projektu i uruchamia cele sekwencyjnie.

Po zmianie grafiki lub prywatnej prezentacji uruchom natywny capture:

```powershell
..\..\..\tests\run_all_tests.ps1 -NativeTarget underwater_map_workbench/structures/tower_three_inlets_02/tests/tower_proxy_capture.gd
```

Artefakty trafiają do izolowanego `user://test_tower_three_inlets_02_proxy_capture`. Obejrzenie obrazów jest obowiązkowe; sam kod wyjścia potwierdza działanie harnessu, nie jakość ani osiągalność wnętrza.

## Przepis zmiany

Zmiana edytowalnego źródła wymagająca nowego seala i mapowego pinu jest jednym root-routed zadaniem na branchu `codex/structure-tower_three_inlets_02/<task-slug>`. W tym samym worktree uruchom najpierw pełną część pakietu:

```powershell
python ..\..\tools\build_underwater_map.py --seal-structure-package tower_three_inlets_02
python ..\..\tools\build_underwater_map.py --build-structure tower_three_inlets_02
python ..\..\tools\build_underwater_map.py --check-structure tower_three_inlets_02
..\..\..\tests\run_all_tests.ps1 -Target underwater_map_workbench/structures/tower_three_inlets_02/tests/tower_package_contract_test.gd
..\..\..\tests\run_all_tests.ps1 -Target underwater_map_workbench/structures/tower_three_inlets_02/tests/tower_runtime_test.gd
```

Następnie, nadal przed jednym wspólnym PR, odśwież dokładny pin, odtwórz pochodne i uruchom pełny lokalny zestaw Mapy:

```powershell
python ..\..\tools\build_underwater_map.py --refresh-structure-package tower_three_inlets_02 --sealed-package-sha256 <SHA256>
python ..\..\tools\build_underwater_map.py --build
python ..\..\tools\build_underwater_map.py --check
..\..\..\tests\run_all_tests.ps1 -Target underwater_map_workbench/tests/underwater_map_smoke_test.gd
..\..\..\tests\run_all_tests.ps1 -Target underwater_map_workbench/tests/underwater_map_visual_residency_test.gd
..\..\..\tests\run_all_tests.ps1 -Target tests/workbench_boundary_test.gd
```

`--seal-structure-package` aktualizuje wyłącznie lokalne hashe i digesty `structure_manifest.json`, a `--refresh-structure-package` wyłącznie mapowy pin i pochodne. Granice komend pozostają rozdzielone, lecz źródła pakietu, seal, dokładny pin i wszystkie pochodne muszą trafić atomowo w jednym branchu i PR. Nie twórz package-only PR ani późniejszego PR Mapy.

Jeżeli konkurencyjny PR zmieni `main`, zaktualizuj bazę do bieżącego `origin/main` i powtórz cały seal/refresh, builder oraz testy pakietu i Mapy. Tylko `fast-check PASS` pozwala enqueue PR; pełną integrację następnie wykonuje merge queue. Zmiana publicznego montażu wymaga także właściwego testu root. Zmiana grafiki wymaga capture'u rzeczywistej sceny, a zmiana topologii ręcznego przepłynięcia struktury.

## Dokumentacja

Jedynymi dokumentami kontraktowymi pakietu są `AGENTS.md` i ten operacyjny `README.md`. Pakiet nie ma własnego `.ai`, ARD ani kopii globalnego opisu produktu. DOCX i materiały źródłowe w `references/` pozostają nieautorytatywnym provenance zgodnie z `structure_manifest.json`.
