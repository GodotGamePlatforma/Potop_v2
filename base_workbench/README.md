# Warsztat Bazy

`base_workbench/` skupia wszystkie kanoniczne źródła lokalnej domeny i prezentacji Przystani. Nie jest osobnym projektem ani biblioteką: używa nadrzędnego `project.godot`, publicznych stanów i usług root oraz wspólnego runnera.

## Co należy do warsztatu

- `runtime/` — aktywna `BaseScene.tscn`, `BaseController`, środowisko i świat 3D;
- `ui/` — `BuildingPanel.tscn`, `BuildingSlot.tscn` oraz lokalne panele, szyny, wskaźniki i prezentery;
- `systems/` — bezstanowe albo domenowe systemy budynków i zarządzania Bazą; `inactive/BuildingBlueprintSystem.gd` pozostaje nieaktywny;
- `definitions/` — typy definicji budynków, receptur i wydarzeń osady;
- `data/` — sześć budynków, receptury, wydarzenia oraz ich lokalny balans;
- `assets/` — platforma 3D i jej źródła, shadery, blueprinty, UI oraz audio Bazy;
- `tools/` — narzędzia odtwarzające wyłącznie źródła Bazy;
- `tests/` — testy systemów, sceniczne flow, snapshoty i capture'y Bazy.

Root nadal posiada `GameState` i wszystkie trwałe stany, zapis, migracje, atomowy koniec dnia, kampanię, misje, difficulty, pogodę, ocaleńców, nurkowanie, integrację scen i runner. Mapa oraz avatar pozostają odpowiednio w `underwater_map_workbench/` i `diver_workbench/`. Warsztat Bazy nie utrzymuje kopii tych kontraktów.

## Punkt wejścia

Otwórz pełny checkout projektu i przejdź do warsztatu:

```powershell
Set-Location .\base_workbench
```

Przed zmianą przeczytaj `AGENTS.md`, właściwy fragment `.ai/PROJECT_CONTEXT.md` i tylko potrzebne źródła. Zmiana gameplayu, trwałego stanu, persistence albo publicznej granicy wymaga powrotu do root.

## Testy

Z CWD `base_workbench/` uruchamiaj bezpośredni cel we wspólnym, izolowanym runnerze:

```powershell
..\tests\run_all_tests.ps1 -Target base_workbench/tests/building_system_test.gd
..\tests\run_all_tests.ps1 -Target base_workbench/tests/settlement_event_system_test.gd
..\tests\run_all_tests.ps1 -Target base_workbench/tests/BaseMusicTest.tscn
..\tests\run_all_tests.ps1 -NativeTarget base_workbench/tests/BaseWeatherSnapshot.tscn -KeepWorkspace
```

Po celowanych testach wróć do root i uruchom osobny fast-check:

```powershell
Set-Location ..
.\tools\agent_fast_check.ps1 -TestTarget base_workbench/tests/building_system_test.gd
```

Zwykły autor nie uruchamia pełnej regresji. Po `PASS` wraca do root i uruchamia `tools/finish_agent_task.ps1`, który tworzy logiczny commit, rewaliduje czysty exact commit oraz deleguje push i PR do publishera. Autor kończy bez pollingu dopiero po potwierdzeniu identycznych `LocalHead`, `RemoteHead` i `PullRequestHead` dla jedynego otwartego PR.

## Źródła prawdy

- lokalny proces i allowlista: `AGENTS.md`;
- potwierdzony stan warsztatu: `.ai/PROJECT_CONTEXT.md`;
- prywatne decyzje implementacyjne: `.ai/DECISIONS.md`;
- globalny kontrakt granicy: `../.ai/DECISIONS.md`, ARD-0114;
- produkt, architektura, persistence i integracja: dokumenty root.

W warsztacie nie powstaje dodatkowa dokumentacja poza czterema zatwierdzonymi plikami ani kopia źródeł Bazy pod dawnymi ścieżkami root.
