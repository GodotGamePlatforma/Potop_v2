# Kontekst warsztatu Bazy

Rola tego pliku: krótka, datowana migawka potwierdzonego stanu lokalnego warsztatu, jego luk, pułapek i ostatniej weryfikacji. Reguły produktu, algorytmy, persistence, architektura przekrojowa oraz historia decyzji należą do dokumentów root i lokalnego rejestru decyzji.

## Stan na 2026-08-29

- `[AKTYWNE]` `base_workbench/` skupia jedyne źródła runtime, UI, systemów, definicji, danych, assetów, narzędzi i testów Bazy; relokację potwierdziły lokalne testy oraz rootowy boundary i smoke.
- `[AKTYWNE]` Baza nadal konsumuje nadrzędny `GameState`, plan dnia i usługi integracyjne; warsztat nie posiada persistence ani osobnego projektu. Kontrakt: ARD-0114.
- `[AKTYWNE]` `runtime/BaseScene.tscn` jest publicznym wejściem Bazy, a `ui/BuildingPanel.tscn` i `ui/BuildingSlot.tscn` jej lokalnymi składnikami.
- `[AKTYWNE]` Systemy kampanii, misji, difficulty, pogody, ocaleńców, nurkowania i atomowego końca dnia pozostają w root; lokalne UI może je wyłącznie konsumować.
- `[AKTYWNE]` `systems/inactive/BuildingBlueprintSystem.gd` pozostaje nieaktywnym reliktem i nie jest podstawą nowej funkcji.

## Pułapki

- CWD warsztatu nie zmienia `res://`: wszystkie ścieżki Godot nadal są liczone od nadrzędnego projektu.
- Testy lokalne leżą bezpośrednio w `base_workbench/tests/`, ale są uruchamiane wspólnym `../tests/run_all_tests.ps1`; nie istnieje lokalny runner.
- Zmiana `GameState`, persistence, końca dnia albo publicznego kontraktu nie mieści się w allowliście Bazy nawet wtedy, gdy jej konsument znajduje się w lokalnym UI.

## Ostatnia weryfikacja

- 2026-08-29, Godot 4.7.1: celowane testy Bazy oraz lokalny `fast-check` zakończyły się `33/33 PASS`, w tym rootowy boundary, smoke i persistence przypisań pracowników.
