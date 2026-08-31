# Kontekst warsztatu Bazy

Rola tego pliku: krótka, datowana migawka potwierdzonego stanu lokalnego warsztatu, jego luk, pułapek i ostatniej weryfikacji. Reguły produktu, algorytmy, persistence, architektura przekrojowa oraz historia decyzji należą do dokumentów root i lokalnego rejestru decyzji.

## Stan na 2026-08-31

- `[AKTYWNE]` `base_workbench/` skupia jedyne źródła runtime, UI, systemów, definicji, danych, assetów, narzędzi i testów Bazy; relokację scalono po pełnej weryfikacji.
- `[AKTYWNE]` Baza nadal konsumuje nadrzędny `GameState`, plan dnia i usługi integracyjne; warsztat nie posiada persistence ani osobnego projektu. Kontrakt: ARD-0114.
- `[AKTYWNE]` `runtime/BaseScene.tscn` jest publicznym wejściem Bazy, a `ui/BuildingPanel.tscn` i `ui/BuildingSlot.tscn` jej lokalnymi składnikami.
- `[AKTYWNE]` Systemy kampanii, misji, difficulty, pogody, ocaleńców, nurkowania i atomowego końca dnia pozostają w root; lokalne UI może je wyłącznie konsumować.
- `[AKTYWNE]` `systems/inactive/BuildingBlueprintSystem.gd` pozostaje nieaktywnym reliktem i nie jest podstawą nowej funkcji.

## Pułapki

- CWD warsztatu nie zmienia `res://`: wszystkie ścieżki Godot nadal są liczone od nadrzędnego projektu.
- Testy lokalne leżą bezpośrednio w `base_workbench/tests/`, ale są uruchamiane wspólnym `../tests/run_all_tests.ps1`; nie istnieje lokalny runner.
- Zmiana `GameState`, persistence, końca dnia albo publicznego kontraktu nie mieści się w allowliście Bazy nawet wtedy, gdy jej konsument znajduje się w lokalnym UI.

## Ostatnia weryfikacja

- Finalny `origin/main` `df43057c72c84c9517d0f08dae506fd91ba30ba9` po squash merge PR #63; jego drzewo jest identyczne z przetestowanym headem PR `00db6417f50beb6e080b3d68640a57ef4855b415`.
- PASS: 17 lokalnych celów Bazy — pięć testów systemów, sześć scenicznych flow, pięć wymaganych snapshotów natywnych oraz `BaseOceanMotionCapture.tscn`; obejmuje `BasePortraitBindingTest.tscn` i `BuildingOccupancyBadgesSnapshot.tscn`.
- PASS: rootowe `workbench_boundary_test.gd`, `smoke_test.gd`, `worker_assignment_persistence_test.gd` i `campaign_map_contract_test.gd`.
- PASS: lokalny fast-check 33/33, GitHub PR fast-check oraz merge group: oba shardy headless, wymagany test natywny, `integration-green` i kolejowy `fast-check`.
