# Instrukcje warsztatu Bazy

Ten katalog jest jedynym miejscem pracy nad lokalną domeną i prezentacją Bazy. Działa wewnątrz nadrzędnego projektu Godot; CWD zadania Bazy to `base_workbench/`, ale pełny checkout z `../project.godot` musi pozostać dostępny.

## Kontekst przed pracą

Dla rutynowej zmiany przeczytaj ten plik, odpowiedni fragment `.ai/PROJECT_CONTEXT.md`, właściwą sekcję `README.md`, a następnie tylko zmieniane źródła i związane testy. `.ai/DECISIONS.md` czytaj w całości, gdy zmiana dotyka lokalnego kontraktu, authority albo zaakceptowanego inwariantu warsztatu.

Wróć do root i przeczytaj pełne globalne decyzje, produkt oraz architekturę, jeżeli zadanie zmienia zachowanie widoczne dla gracza, `GameState`, trwały stan, kolejność albo atomowość końca dnia, persistence, migrację, kampanię, misje, pogodę, difficulty, ocaleńców, nurkowanie, publiczną granicę Root–Baza albo więcej niż jednego właściciela. Taki zakres jest integracją root, nie prywatną zmianą Bazy.

## Ownership i zapis

Warsztat posiada wyłącznie:

- `runtime/` — `BaseScene.tscn`, lokalny kontroler, środowisko i świat Przystani;
- `ui/` — sceny i skrypty lokalnego interfejsu Bazy;
- `systems/` — systemy budynków, pracy, produkcji, racji, opieki, obsady i wydarzeń osady; `systems/inactive/` nie jest zgodą na aktywowanie historycznych systemów;
- `definitions/` i `data/` — definicje oraz zasoby danych należące wyłącznie do Bazy;
- `assets/` i `tools/` — grafika, audio oraz narzędzia źródłowe wyłącznie Bazy;
- `tests/` — lokalne testy i capture'y Bazy;
- dokładnie `AGENTS.md`, `README.md`, `.ai/PROJECT_CONTEXT.md` i `.ai/DECISIONS.md` jako dokumentację lokalną.

Prywatne zadanie Bazy zapisuje wyłącznie `base_workbench/**`. Root, `underwater_map_workbench/**` i `diver_workbench/**` są zależnościami tylko do odczytu. Potrzebna zmiana poza allowlistą wraca do root jako osobny albo jawnie integracyjny zakres.

Root zachowuje `GameState`, `BuildingState`, `WorkshopOrderState`, `SettlementEventState`, `WeatherState`, pozostałe trwałe stany, `SaveManager`, walidację i migracje, `EndOfDayResolver`, kampanię, misje, difficulty, pogodę, rozwój i choroby ocaleńców, systemy nurkowania, `GameRoot` oraz wspólny runner. Warsztat może konsumować ich publiczne typy i metody, ale nie może ich kopiować, reinterpretować ani poprawiać przy okazji lokalnego zadania.

Nie twórz lokalnego `project.godot`, `.godot`, InputMapu, ustawień fizyki, autoloadu, kopii globalnych dokumentów ani drugiej wersji źródeł Bazy w root. `runtime/BaseScene.tscn` jest jedyną aktywną sceną Bazy; `ui/BuildingPanel.tscn` i `ui/BuildingSlot.tscn` są jej lokalnymi składnikami.

## Weryfikacja i dostarczenie

Najpierw uruchom celowane testy bezpośrednio przez wspólny runner z projektu nadrzędnego, na przykład:

```powershell
..\tests\run_all_tests.ps1 -Target base_workbench/tests/building_system_test.gd
..\tests\run_all_tests.ps1 -Target base_workbench/tests/BaseOptionalPanelsFlowTest.tscn
..\tests\run_all_tests.ps1 -NativeTarget base_workbench/tests/BaseWeatherSnapshot.tscn -KeepWorkspace
```

Testy uruchamiaj sekwencyjnie. `ERROR`, `SCRIPT ERROR`, timeout i niezerowy kod oznaczają porażkę. Capture prezentacji wymaga także kontroli wzrokowej; nie zastępuje testu zachowania.

Po przejściu testów zadania uruchom osobno lokalny fast-check z root. Pełna regresja nie należy do zwykłego autora. Droga dostarczenia pozostaje zamknięta: `implementacja -> lokalne testy zadania -> lokalny fast-check`, a po `PASS` operacyjnie jedno `tools/finish_agent_task.ps1` tworzy logiczny commit i deleguje exact push oraz PR do publishera. Nie pushuj do `main`, nie polluj i nie babysituj kolejki. Nie ogłaszaj ukończenia, dopóki helper nie potwierdzi `LocalHead = RemoteHead = PullRequestHead` dla jedynego otwartego PR.

## Dokumentacja

`README.md` opisuje ownership, układ i komendy. `.ai/PROJECT_CONTEXT.md` jest krótką migawką potwierdzonego runtime, luk i ostatniej weryfikacji. `.ai/DECISIONS.md` zawiera wyłącznie trwałe decyzje prywatne dla Bazy. Reguły produktu, architektura przekrojowa, zapis oraz globalne decyzje pozostają w pięciu dokumentach root. Nie dodawaj innych plików dokumentacyjnych do warsztatu.
