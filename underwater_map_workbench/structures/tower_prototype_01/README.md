# Tower Prototype 01

Ten katalog zawiera jeden zarejestrowany, podrzędny pakiet struktury Mapy. Nie jest osobnym projektem Godot. Wszystkie ścieżki w tym pliku są liczone od `underwater_map_workbench/structures/tower_prototype_01/`, a runner używa ścieżek `res://` projektu nadrzędnego.

## Źródła prawdy

| Źródło | Właściciel szczegółu |
|---|---|
| `../../map_manifest.json`, rekord `tower_prototype_01` | stable ID, globalny origin, aktywność, opcjonalny landmark i hash-pinned rejestracja pakietu |
| `structure_manifest.json` | lokalny rozmiar, szablon, topologia, sockety, grafika, skrypty, runtime i nietrwały cykl życia próby |
| `runtime/` | prywatna implementacja ładowana wyłącznie po hash-pinned ścieżkach z manifestu, bez globalnych `class_name` |
| `assets/` | edytowalne źródła wizualne pakietu |
| `generated/` | deterministyczne maski, prowadnice, karty socketów i truth package; nie edytuj ręcznie |
| `tests/tower_package_contract_test.gd` | walidacja manifestu, hashy i pakietowych pochodnych |
| `tests/tower_runtime_test.gd` | lokalna weryfikacja prywatnego runtime i resetu próby |
| `tests/tower_proxy_capture.gd` | natywny capture prywatnych kadrów i stanów tej struktury; nie jest automatycznym testem pełnego runnera |
| `references/Wiezowiec_2D_Analiza_i_Dokumentacja_POPRAWIONA.docx` | provenance `authority=false`; nie jest źródłem gameplayu, topologii ani zapisu |

Pakiet celowo nie publikuje własnego `structure_id`: tożsamość wynika z nazwy katalogu i jedynej mapowej referencji. Nie przechowuje też globalnego originu. Lokalny manifest może deklarować `attempt_state.persistence=none` i `attempt_state.checkpoint=none`, ale nie ustanawia osobnej reguły produktu ani mechanizmu zapisu.

Zachowanie widoczne dla gracza ma jednego właściciela: `../../../docs/OgolnyZarys.txt`, sekcje `[AKTYWNE] — BIEŻĄCY NEUTRALNY PROTOTYP WIEŻOWCA` oraz `[DOCELOWE] — ARCHIWUM W PIWNICY I DEDUKCYJNA SEKWENCJA A–D`. Nie jest kopiowane do tego README. Przekrojowe mapowanie techniczne znajduje się w `../../../docs/Ostatni_Pomost_architektura_Godot.txt`, sekcje 2, 9.1 i 13; trwałe granice w globalnym ARD-0106 i lokalnym MAP-ARD-0022.

## Szybki start

Z CWD tego katalogu:

```powershell
Test-Path ..\..\..\project.godot
git -C ..\..\.. status --short --branch
python ..\..\tools\build_underwater_map.py --build-structure tower_prototype_01
python ..\..\tools\build_underwater_map.py --check-structure tower_prototype_01
..\..\..\tests\run_all_tests.ps1 -Target underwater_map_workbench/structures/tower_prototype_01/tests/tower_package_contract_test.gd
..\..\..\tests\run_all_tests.ps1 -Target underwater_map_workbench/structures/tower_prototype_01/tests/tower_runtime_test.gd
```

Powyższe komendy nie są deklaracją wyniku ostatniego przebiegu. Runner tworzy izolowaną pełną kopię projektu i uruchamia cele sekwencyjnie.

Po zmianie grafiki lub prywatnej prezentacji uruchom natywny capture:

```powershell
..\..\..\tests\run_all_tests.ps1 -NativeTarget underwater_map_workbench/structures/tower_prototype_01/tests/tower_proxy_capture.gd
```

Artefakty trafiają do izolowanego `user://test_tower_prototype_01_proxy_capture`. Obejrzenie obrazów jest obowiązkowe; sam kod wyjścia potwierdza działanie harnessu, nie jakość ani osiągalność wnętrza.

## Przepis zmiany

Po zmianie edytowalnego źródła lub hash-pinned pliku pakietu uruchom najpierw seal. Jeśli hashe się nie zmieniły, pomiń pierwszą komendę:

```powershell
python ..\..\tools\build_underwater_map.py --seal-structure-package tower_prototype_01
python ..\..\tools\build_underwater_map.py --build-structure tower_prototype_01
python ..\..\tools\build_underwater_map.py --check-structure tower_prototype_01
..\..\..\tests\run_all_tests.ps1 -Target underwater_map_workbench/structures/tower_prototype_01/tests/tower_package_contract_test.gd
..\..\..\tests\run_all_tests.ps1 -Target underwater_map_workbench/structures/tower_prototype_01/tests/tower_runtime_test.gd
```

`--seal-structure-package` aktualizuje wyłącznie lokalne hashe i digesty `structure_manifest.json`. Po zgodnym checku sprawdź diff i otwórz PR pakietu. Osobny PR właściciela Mapy wykonuje `--refresh-structure-package tower_prototype_01 --sealed-package-sha256 <SHA256>` dla dokładnego SHA-256 sealed manifestu oraz odtwarza pin i wspólne pochodne; autor pakietu nigdy nie zapisuje `../../map_manifest.json`.

Pełny `--build`, `--check`, `underwater_map_smoke_test.gd` i `workbench_boundary_test.gd` uruchamia zakres Mapy przy rejestracji pakietu, zmianie originu albo publicznym montażu. Nie należą do zwykłego prywatnego loopu; pełną integrację docelowo wykonuje merge queue przed scaleniem. Zmiana publicznego montażu wymaga także właściwego testu root. Zmiana grafiki wymaga natywnego capture'u i oględzin, a zmiana topologii ręcznego przepłynięcia budynku. Nie poprawiaj ręcznie `generated/**` ani `../../UnderwaterMap.tscn`.

Zmiana globalnego originu, aktywności, landmarku lub referencji pakietu odbywa się wyłącznie w zadaniu Mapy z CWD `../..`; prywatny agent pakietu traktuje ten rekord jako read-only. Zmiana zachowania gracza, kampanii, publicznego kontraktu albo persistence jest zadaniem integracyjnym root.

## Dokumentacja

Jedynymi dokumentami kontraktowymi pakietu są `AGENTS.md` i ten operacyjny `README.md`. Pakiet nie ma własnego `.ai`, ARD ani kopii opisu gameplayu. DOCX w `references/` pozostaje wyłącznie nieautorytatywnym provenance zgodnie z `structure_manifest.json`.
