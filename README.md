# Ostatni Pomost

Survivalowa gra zarządczo-eksploracyjna tworzona w Godot 4.7. Gracz rozwija Przystań, utrzymuje społeczność i wysyła nurka do jednego trwałego, zatopionego świata.

## Rola README

Ten plik jest punktem wejścia dla człowieka: opisuje wymagania, uruchomienie, runner testów, podstawowe sterowanie i nawigację po dokumentacji. Szczegółowe zasady produktu należą do `docs/OgolnyZarys.txt`, techniczne mapowanie do `docs/Ostatni_Pomost_architektura_Godot.txt`, a potwierdzona migawka runtime do `.ai/PROJECT_CONTEXT.md`.

## Wymagania

- Godot 4.7; projekt jest przygotowany dla Godot 4.7.1.
- Git LFS dla wersjonowanych assetów binarnych.
- PowerShell 7 do uruchamiania runnera testów.

Przed pierwszym klonowaniem włącz Git LFS:

```powershell
git lfs install
```

W istniejącym klonie pobierz assety:

```powershell
git lfs pull
```

## Codex mapy i grafiki

Zadania projektowania mapy podwodnej, biomów, landmarków, tła i assetów świata mają własny hub `underwater_map_workbench/`. Codex uruchamiaj z tego katalogu, pozostawiając pełny checkout projektu jako jego rodzica: scena, assety, skrypty integracyjne, testy i `project.godot` pozostają na kanonicznych ścieżkach repozytorium.

Na tej maszynie:

```powershell
Set-Location D:\Dev\Game\Game\underwater_map_workbench
Test-Path ..\project.godot
git -C .. status --short --branch
```

W Codex Desktop otwórz `underwater_map_workbench/`, nie samodzielną kopię tego podkatalogu. Bliższy `AGENTS.md` zawęża zakres i dobiera proporcjonalny kontekst, a lokalny `README.md` opisuje handoff, pipeline master-first i komendy działające z tego CWD. Osobny pełny Git worktree jest opcjonalną izolacją dla równoległej pracy, a nie wymaganiem ani powodem do kopiowania scen lub pochodnych.

## Uruchamianie

W katalogu głównym repozytorium:

```powershell
godot --path .
```

Godot 4.7 może uruchamiać projekt w trybie Game Embedding. Ten tryb nie obsługuje zmiany geometrii natywnego okna ani fullscreen. Do ręcznego sprawdzenia tych opcji w widoku **Game** rozwiń menu w prawym górnym rogu, wyłącz **Embed Game on Next Play** i uruchom grę ponownie.

## Testy

Runner domyślnie tworzy jednorazową, pełną kopię projektu z własnym cache `.godot`, wykonuje testy sekwencyjnie i usuwa workspace po zakończeniu. Żadna poniższa komenda nie jest deklaracją wyniku ostatniego przebiegu.

Szybka bramka — 14 testów skryptowych i 3 przepływy sceniczne:

```powershell
.\tests\run_all_tests.ps1
```

Pełna regresja — 41 testów skryptowych, 18 przepływów scenicznych oraz dodatkowy lane wymagający natywnego okna:

```powershell
.\tests\run_all_tests.ps1 -Full
```

Pełna regresja oraz 11 celów snapshotowych:

```powershell
.\tests\run_all_tests.ps1 -Full -IncludeSnapshots
```

Pojedynczy cel headless uruchamiaj przez `-Target`:

```powershell
.\tests\run_all_tests.ps1 -Target tests/underwater_map_scene_test.gd
```

Pojedynczy cel wymagający prawdziwego okna uruchamiaj przez `-NativeTarget`:

```powershell
.\tests\run_all_tests.ps1 -NativeTarget tests/native_window_settings_test.gd
```

`-KeepWorkspace` zachowuje izolowaną kopię do diagnozy. `-InPlace` jest świadomym trybem lokalnym: przed jego użyciem zamknij wszystkie procesy Godota skierowane na ten checkout. Ścieżkę do Godot można podać przez `-GodotConsolePath`; runner preferuje windowsowy wariant `*_console.exe`. `-AllowNativeSkip` służy wyłącznie środowisku, które jawnie nie obsługuje natywnego okna.

Domyślny `dive_recovery_certification_test.gd`, także w `-Full`, wykonuje szybką bramkę kontraktu runtime. Wyczerpujący frontier 138 zapytań jest oddzielnym, ręcznym narzędziem diagnostycznym i wymaga jawnego przełączenia:

```powershell
$env:DIVE_CERT_EXHAUSTIVE = "1"
.\tests\run_all_tests.ps1 -Target tests/dive_recovery_certification_test.gd
Remove-Item Env:DIVE_CERT_EXHAUSTIVE
```

Ten tryb nie należy do zwykłej regresji i może być długotrwały; do discovery można użyć udokumentowanych w samym teście zmiennych `DIVE_CERT_EARLIEST_ONLY` oraz `DIVE_CERT_EARLIEST_SHARD_COUNT/INDEX` w osobnych pełnych kopiach projektu. Runner traktuje niezerowy kod procesu, timeout, `ERROR` i `SCRIPT ERROR` jako porażkę. Snapshoty i materiały certyfikacyjne nadal wymagają właściwej dla ich kontraktu oceny; samo wygenerowanie pliku nie oznacza akceptacji wizualnej ani potwierdzenia pełnej certyfikacji.

## Domyślne sterowanie

Klawisze można zmienić w ustawieniach menu głównego; poniżej są wartości startowe z `project.godot`:

- `WASD` albo strzałki — ruch nurka;
- `Shift` — sprint;
- `E` albo `Spacja` — interakcja i narzędzie kontekstowe;
- `R` — zwykła naprawa podczas nurkowania, archiwum raportów w bazie;
- `Shift+R` — cicha naprawa, gdy wybrany nurek ma wymagany talent;
- `F` — włącz albo wyłącz wyposażoną latarnię;
- `I` — plecak podczas nurkowania;
- `1` — Nóż ratowniczy;
- `2` — wyposażony pistolet harpunowy;
- `LPM` — atak wybranym narzędziem w kierunku kursora;
- `J` — dziennik misji;
- `Esc` — pominięcie intro, anulowanie przechwytywania klawisza albo zamknięcie opcjonalnego panelu; w bazie i podczas wyprawy kolejny `Esc` otwiera pauzę.

Menu pauzy udostępnia `KONTYNUUJ`, `ZAPISZ GRĘ`, `USTAWIENIA`, `POWRÓT DO MENU GŁÓWNEGO` i `WYJDŹ Z GRY`. Ręczny zapis jest zablokowany podczas nurkowania. Powrót do menu wymaga potwierdzenia, odrzuca bieżący runtime bez autosave i nie usuwa kampanii; wyjście z gry zamyka aplikację bez dodatkowego zapisu.

## Dokumentacja

- `AGENTS.md` — proces pracy, kolejność pełnego odczytu i routing edycji;
- `.ai/PROJECT_CONTEXT.md` — potwierdzony runtime, luki, pułapki i ostatnia weryfikacja;
- `.ai/DECISIONS.md` — trwałe decyzje, powody i jawne zastąpienia;
- `docs/OgolnyZarys.txt` — produkt, zasady, balans, narracja i zakres;
- `docs/Ostatni_Pomost_architektura_Godot.txt` — mapowanie systemów, danych, persistence i testów;
- `underwater_map_workbench/` — wyspecjalizowany onboarding, kontekst produkcji i decyzje dla mapy podwodnej oraz jej grafiki.
