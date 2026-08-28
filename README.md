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

## Praca nad zmianą

Jedno zadanie oznacza jeden pełny Git worktree, jedną gałąź `codex/<owner>/<task-slug>` i jeden PR. Agent zajmuje się implementacją oraz adekwatnymi testami lokalnymi; nie tworzy assignmentu, ACK, receiptu, lokalnego LKG ani osobnego agenta-audytora.

Przykładowy start z czystej kopii repozytorium:

```powershell
git fetch origin main
git worktree add -b codex/<owner>/<task-slug> <absolute-worktree-path> origin/main
Set-Location <absolute-worktree-path>
git status --short --branch
```

Następnie:

1. przeczytaj kontekst wymagany przez najbliższy `AGENTS.md`;
2. wprowadź zmianę wyłącznie w dozwolonej domenie;
3. uruchom proporcjonalne testy lokalne opisane niżej lub w README warsztatu;
4. sprawdź pełny diff i brak niezamierzonych plików;
5. utwórz logiczny commit, wypchnij własną gałąź i otwórz jeden PR.

```powershell
git status --short
git diff --check
git push -u origin HEAD
```

Nie pushuj bezpośrednio do `main`. Nie czytaj ani nie modyfikuj live worktree innego autora; zależność pobieraj z Git po commicie albo przez zwykły PR.

## Docelowa ochrona `main`

Docelowy przepływ rozdziela dwie bramki:

- `fast-check` musi zakończyć się `PASS`, zanim PR trafi do merge queue; każdy inny wynik blokuje enqueue i merge, także dla rzadkiej zmiany control-plane;
- merge queue tworzy merge group `aktualny main + dany PR` i przed scaleniem uruchamia pełny `integration-green`;
- tylko zielony wynik jest scalany metodą squash.

Dzięki temu `main` oznacza najnowszy kod, który przeszedł pełną regresję. Bieżący stan wdrożenia opisuje [`.ai/PROJECT_CONTEXT.md`](.ai/PROJECT_CONTEXT.md).

Każdy przebieg Godota używa izolowanego workspace, `.godot`, `user://`, logów, katalogów tymczasowych i portów. Wspólny runner wykonuje tę izolację automatycznie; `-InPlace` pozostaje niedozwolone.

## Synchronizacja czystego `main`

Lokalny mirror `main` nie kasuje zmian. Najpierw sprawdza czystość, a dopiero potem wykonuje fetch, fast-forward i pobranie LFS:

```powershell
$currentBranch = git branch --show-current
if ($LASTEXITCODE -ne 0) { throw "Nie można ustalić bieżącej gałęzi." }
if ($currentBranch.Trim() -ne "main") { throw "Synchronizacja jest dozwolona wyłącznie na gałęzi main." }

$dirtyState = git status --porcelain
if ($LASTEXITCODE -ne 0) { throw "Nie można sprawdzić czystości katalogu main." }
if ($dirtyState) { throw "Katalog main jest dirty; synchronizacja zatrzymana." }

git fetch origin main
if ($LASTEXITCODE -ne 0) { throw "Fetch origin/main nie powiódł się." }

git merge --ff-only origin/main
if ($LASTEXITCODE -ne 0) { throw "Fast-forward do origin/main nie powiódł się." }

$localMainSha = git rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw "Nie można odczytać lokalnego SHA main." }
$originMainSha = git rev-parse origin/main
if ($LASTEXITCODE -ne 0) { throw "Nie można odczytać SHA origin/main." }
if ($localMainSha.Trim() -ne $originMainSha.Trim()) { throw "Lokalny main nie jest dokładnie równy origin/main." }

git lfs pull
if ($LASTEXITCODE -ne 0) { throw "Pobranie Git LFS nie powiodło się." }
```

Nie używaj automatycznego `reset --hard`. Dirty katalog wymaga świadomego uporządkowania przez właściciela.

## Finalny builder gry

Po wdrożeniu docelowego procesu lokalny builder będzie działał wyłącznie po scaleniu:

```text
exact final main SHA
  -> Git LFS
  -> build
  -> smoke
  -> builds/by-sha/<SHA>
  -> builds/current tylko po PASS
```

Błąd builda albo smoke pozostawia poprzednie `builds/current` bez zmian. Oznacza to dwa stabilne poziomy: `main` jest pełnozielonym kodem, a `current` najnowszym pełnozielonym `main`, który dodatkowo poprawnie się zbudował. Bieżący stan opisuje [`.ai/PROJECT_CONTEXT.md`](.ai/PROJECT_CONTEXT.md).

## Chronione ścieżki

Zwykły PR nie może zmieniać:

- `.github/workflows/**`;
- narzędzi odpowiedzialnych za CI;
- konfiguracji `integration-green`;
- control-plane finalnego buildera.

Te ścieżki mają być chronione regułą GitHub. Rzadka zmiana wymaga osobnego PR i ręcznej zgody właściciela; zgoda nie omija `fast-check PASS` ani `integration-green PASS` merge group. Nie uruchamia się drugiego Codexa do oceniania pierwszego.

## Mapa podwodna

Cały aktywny pakiet konkretnej mapy i jej grafik świata znajduje się w `underwater_map_workbench/`: jedyny `map_manifest.json`, generowana `UnderwaterMap.tscn`, lokalny kompilator i cienki host runtime, pojedynczy builder i smoke test, shadery środowiska, mapowe `assets/` oraz podrzędne `structures/<id>/`. Manifest mapy zachowuje rejestr i globalny placement, a każdy zarejestrowany `structure_manifest.json` skupia wyłącznie lokalną topologię, grafikę, skrypty i testy jednego budynku. Avatar gracza nie należy do tego pakietu. Root repozytorium zawiera ogólne mechaniki nurkowania, dane domenowe, integrację Godot i runner testów, ale nie drugą kopię mapy ani katalog `assets/diving`.

Na tej maszynie:

```powershell
Set-Location .\underwater_map_workbench
Test-Path ..\project.godot
git -C .. status --short --branch
```

W Codex Desktop otwórz `underwater_map_workbench/` razem z dostępnym katalogiem nadrzędnym projektu. Bliższy `AGENTS.md` zawęża zakres, a lokalny `README.md` opisuje workflow źródła mapy i pakietów → scena. Przy pracy nad jednym budynkiem przejdź następnie do `structures/<id>/AGENTS.md`; globalny origin nadal zmienia się wyłącznie w `map_manifest.json`. Nie edytuj wygenerowanej sceny ręcznie i nie twórz wariantów mapy.

## Warsztat nurka

Jedyny aktywny pakiet avatara gracza znajduje się w `diver_workbench/`: scena `CharacterBody2D`, collider, grafika, animacje, profil socketów, shadery, VFX i lokalne testy prezentacji. Katalog korzysta z nadrzędnego `project.godot`, InputMapu, ogólnych systemów nurkowania oraz wspólnego runnera; nie jest osobnym projektem.

Na tej maszynie:

```powershell
Set-Location .\diver_workbench
Test-Path ..\project.godot
git -C .. status --short --branch
```

Agent zajmujący się skalą, colliderem, animacją, socketami albo punktem emisji latarki rozpoczyna od lokalnego `AGENTS.md`, `.ai/PROJECT_CONTEXT.md`, `.ai/DECISIONS.md` i `README.md`. Ogólne reguły ruchu, tlenu, ryzyka, wyposażenia, UI, sesji i zapisu pozostają w root, a mapa i okludery w `underwater_map_workbench/`.

## Uruchamianie

W katalogu głównym repozytorium:

```powershell
godot --path .
```

Godot 4.7 może uruchamiać projekt w trybie Game Embedding. Ten tryb nie obsługuje zmiany geometrii natywnego okna ani fullscreen. Do ręcznego sprawdzenia tych opcji w widoku **Game** rozwiń menu w prawym górnym rogu, wyłącz **Embed Game on Next Play** i uruchom grę ponownie.

## Testy

Runner domyślnie tworzy jednorazową, pełną kopię projektu z własnym cache `.godot`, osobnym `user://`, logami i portami procesu, wykonuje testy sekwencyjnie i usuwa workspace po zakończeniu. Jawny `-Target` albo `-NativeTarget` nie wykonuje globalnego discovery niezwiązanych pakietów. Żadna poniższa komenda nie jest deklaracją wyniku ostatniego przebiegu.

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

Odbiór infrastruktury współbieżnej tworzy tymczasowy Git-closed commit, dwa linked worktrees i uruchamia w nich równolegle dwa izolowane importy oraz cele Godota. Nie zmienia realnego `HEAD`, branchy ani źródeł:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\parallel_worktree_godot_test.ps1
```

Pojedynczy cel headless uruchamiaj przez `-Target`:

```powershell
.\tests\run_all_tests.ps1 -Target underwater_map_workbench/tests/underwater_map_smoke_test.gd
.\tests\run_all_tests.ps1 -Target underwater_map_workbench/structures/<id>/tests/<test>.gd
.\tests\run_all_tests.ps1 -Target diver_workbench/tests/DiverPresentationTest.tscn
.\tests\run_all_tests.ps1 -Target tests/workbench_boundary_test.gd
```

Pojedynczy cel wymagający prawdziwego okna uruchamiaj przez `-NativeTarget`:

```powershell
.\tests\run_all_tests.ps1 -NativeTarget tests/native_window_settings_test.gd
.\tests\run_all_tests.ps1 -NativeTarget diver_workbench/tests/DiverPresentationCapture.tscn
```

`-KeepWorkspace` zachowuje izolowaną kopię do diagnozy. Runner celowo odrzuca `-InPlace`; test zawsze korzysta z pełnej kopii, aby odseparować cache, `user://` i snapshot źródeł. Ścieżkę do Godot można podać przez `-GodotConsolePath`; runner preferuje windowsowy wariant `*_console.exe`. `-AllowNativeSkip` służy wyłącznie środowisku, które jawnie nie obsługuje natywnego okna.

Mapowy smoke jest jedynym testem technicznym całej złożonej mapy: sprawdza rejestr, pakiety, aktualność i ładowanie sceny oraz integrację kompilatora z runtime. Nie zawiera drugiej kopii ID, pozycji, liczby obiektów ani kolejności zawartości. Prywatny loop jednego `structures/<id>/` korzysta z celowanych trybów refresh/build/check opisanych w mapowym README oraz z testów kontraktu pakietu i jego runtime, bez globalnego placementu i persistence. Pełny mapowy build/check i smoke są bramką rejestracji, zmiany originu, publicznego montażu lub odbioru integracyjnego, a nie każdej prywatnej iteracji. `workbench_boundary_test.gd` pilnuje pojedynczych authority Root–Mapa–Struktury–Nurek, jednoznacznych pakietów struktur, zatwierdzonych dokumentów i indeksów lokalnych decyzji. Runner odkrywa testy wszystkich zarejestrowanych pakietów dynamicznie; Root nie prowadzi listy nazw budynków ani ich testów. Pozostałe testy nurkowania sprawdzają ogólne mechaniki, a nie topologię. Runner traktuje niezerowy kod procesu, timeout, `ERROR` i `SCRIPT ERROR` jako porażkę.

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
- `underwater_map_workbench/` — wyspecjalizowany onboarding, kontekst produkcji i decyzje dla mapy podwodnej oraz jej grafiki świata;
- `underwater_map_workbench/structures/<id>/` — operacyjny pakiet lokalnej topologii, grafiki, runtime i testów jednego zarejestrowanego budynku; reguły produktu pozostają w dokumentach root;
- `diver_workbench/` — wyspecjalizowany onboarding, migawka, decyzje i testy sceny avatara nurka.
