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

## Mapa podwodna

Cały aktywny pakiet mapy i potrzebnych grafik podwodnego gameplayu znajduje się w `underwater_map_workbench/`: jedyny `map_manifest.json`, generowana `UnderwaterMap.tscn`, lokalny kompilator i cienki host runtime, pojedynczy builder i smoke test, shadery środowiska oraz `assets/gameplay/`. Root repozytorium zawiera ogólne mechaniki nurkowania, dane domenowe, integrację Godot i runner testów, ale nie drugą kopię mapy ani katalog `assets/diving`.

Na tej maszynie:

```powershell
Set-Location D:\Dev\Game\Game\underwater_map_workbench
Test-Path ..\project.godot
git -C .. status --short --branch
```

W Codex Desktop otwórz `underwater_map_workbench/` razem z dostępnym katalogiem nadrzędnym projektu. Bliższy `AGENTS.md` zawęża zakres, a lokalny `README.md` opisuje jedyny workflow manifest → scena. Nie edytuj wygenerowanej sceny ręcznie i nie twórz wariantów mapy.

## Uruchamianie

W katalogu głównym repozytorium:

```powershell
godot --path .
```

Godot 4.7 może uruchamiać projekt w trybie Game Embedding. Ten tryb nie obsługuje zmiany geometrii natywnego okna ani fullscreen. Do ręcznego sprawdzenia tych opcji w widoku **Game** rozwiń menu w prawym górnym rogu, wyłącz **Embed Game on Next Play** i uruchom grę ponownie.

## Testy

Runner domyślnie tworzy jednorazową, pełną kopię projektu z własnym cache `.godot`, wykonuje testy sekwencyjnie i usuwa workspace po zakończeniu. Żadna poniższa komenda nie jest deklaracją wyniku ostatniego przebiegu.

Szybka bramka:

```powershell
.\tests\run_all_tests.ps1
```

Pełna regresja wraz z dodatkowym lane'em wymagającym natywnego okna:

```powershell
.\tests\run_all_tests.ps1 -Full
```

Pełna regresja oraz aktywne cele snapshotowe:

```powershell
.\tests\run_all_tests.ps1 -Full -IncludeSnapshots
```

Pojedynczy cel headless uruchamiaj przez `-Target`:

```powershell
.\tests\run_all_tests.ps1 -Target underwater_map_workbench/tests/underwater_map_smoke_test.gd
```

Pojedynczy cel wymagający prawdziwego okna uruchamiaj przez `-NativeTarget`:

```powershell
.\tests\run_all_tests.ps1 -NativeTarget tests/native_window_settings_test.gd
```

`-KeepWorkspace` zachowuje izolowaną kopię do diagnozy. `-InPlace` jest świadomym trybem lokalnym: przed jego użyciem zamknij wszystkie procesy Godota skierowane na ten checkout. Ścieżkę do Godot można podać przez `-GodotConsolePath`; runner preferuje windowsowy wariant `*_console.exe`. `-AllowNativeSkip` służy wyłącznie środowisku, które jawnie nie obsługuje natywnego okna.

Mapowy smoke jest jedynym testem technicznym pakietu mapy: sprawdza walidację manifestu, aktualność i ładowanie sceny oraz integrację kompilatora z runtime. Nie zawiera drugiej kopii ID, pozycji, liczby obiektów ani kolejności zawartości. Pozostałe testy nurkowania sprawdzają ogólne mechaniki, a nie topologię. Runner traktuje niezerowy kod procesu, timeout, `ERROR` i `SCRIPT ERROR` jako porażkę.

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
