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

Root lub koordynator przydziela jedno proste, niezależne zadanie jednemu agentowi. Zadanie implementacyjne uruchamia od razu jako **Worktree**, nigdy jako Local. Jedno zadanie oznacza jeden pełny Git worktree, jedną gałąź `codex/<owner>/<task-slug>` i jeden PR. Agent ma skupić się na implementacji, nie na obsłudze systemu integracji.

Jeżeli rozmowa rozpoczęła się jako „tylko analiza”, a później ma przejść do wdrożenia, najpierw użyj **Hand off do Worktree**. Sam branch w głównym checkoutcie nie zastępuje osobnego worktree.

Codzienna ścieżka ma dwa polecenia:

```powershell
# Uruchom z dowolnego worktree repo. Powstanie unikalny branch i katalog.
.\tools\start_agent_task.ps1 -OwnerSegment root -TaskSlug <krótka-nazwa>

# Po zmianie i właściwych testach uruchom we własnym nowym worktree:
.\tools\finish_agent_task.ps1 -Title "<tytuł PR>" -CommitMessage "<typ>: <opis>" -TestTarget <test-zadania>
```

Pierwsze polecenie korzysta z exact `origin/main` i przy okazji próbuje bezpiecznie usunąć wyłącznie stare, czyste worktree exact scalonych PR-ów. Drugie zbiera zmiany zadania do jednego commita, uruchamia kanoniczny fast-check, pushuje exact SHA, tworzy jeden PR i dla zwykłej zmiany włącza merge queue. Dirty, otwarte, niescalone i przesunięte worktree są zawsze zachowywane.

Niższy poziom, używany tylko do diagnostyki albo jawnego wskazania katalogu:

```powershell
git fetch origin main
git worktree add -b codex/<owner>/<task-slug> <absolute-worktree-path> origin/main
Set-Location <absolute-worktree-path>
git status --short --branch
```

Następnie:

1. przeczytaj najbliższy `AGENTS.md`, krótki lokalny kontekst oraz związany kod i testy;
2. wprowadź zmianę wyłącznie w dozwolonej domenie;
3. uruchom lokalne testy zadania;
4. osobno uruchom lokalny `fast-check`; po `FAIL` popraw zmianę i powtórz;
5. po `PASS` sprawdź pełny diff;
6. uruchom `finish_agent_task.ps1`, który tworzy logiczny commit i publikuje go jednym helperem;
7. zakończ zadanie — agent nie polluje kolejki i nie aktualizuje starego PR po każdym cudzym merge; może powiedzieć „gotowe” dopiero po potwierdzeniu `LocalHead = RemoteHead = PullRequestHead` dla jedynego otwartego PR.

```powershell
# Najpierw właściwy test zmienianego zachowania, na przykład:
.\tests\run_all_tests.ps1 -Target <test-zadania>

# Następnie osobna szybka bramka lokalna:
.\tools\agent_fast_check.ps1 -TestTarget <test-zadania>

# Tworzy commit, rewaliduje clean exact commit, pushuje i tworzy PR. Wynik wypisuje
# LocalHead, RemoteHead i PullRequestHead; wszystkie trzy muszą być identyczne:
.\tools\finish_agent_task.ps1 -Title "<tytuł PR>" -CommitMessage "<typ>: <krótki opis>" -TestTarget <test-zadania>
```

Jeżeli zadanie nie ma celu Godot, pomiń `-TestTarget`, ale nadal wykonaj adekwatny test przed fast-checkiem. Nie pushuj bezpośrednio do `main`. Nie czytaj ani nie modyfikuj live worktree innego autora; zależność pobieraj z Git po commicie albo przez zwykły PR.

## Ochrona `main`

Przepływ rozdziela kolejne etapy weryfikacji:

- lokalne testy zadania sprawdzają zmieniane zachowanie;
- osobny lokalny `fast-check PASS` działa w worktree przed commitem i zapobiega publikacji oczywiście złej zmiany;
- po utworzeniu PR osobny, wymagany GitHub `fast-check` sprawdza dokładny head PR; `FAIL` pozostawia PR otwarty, a tylko `PASS` pozwala wejść do merge queue, także dla rzadkiej zmiany control-plane;
- merge queue tworzy merge group `aktualny main + dany PR` i uruchamia pełny `integration-green`; `FAIL` oznacza brak merge, a `PASS` pozwala na squash do `main`.

Dzięki temu `main` oznacza najnowszy kod, który przeszedł pełną regresję. Ścieżka PR i merge queue jest aktywna; bieżące dowody weryfikacji opisuje [`.ai/PROJECT_CONTEXT.md`](.ai/PROJECT_CONTEXT.md).

Merge queue sama używa aktualnego `main`; autor nie babysituje PR. Jeżeli wystąpi prawdziwy konflikt albo `integration-green` wykryje nieaktualny seal, pin lub pochodne, koordynator zamyka stary PR jako zastąpiony i przydziela nowe zadanie naprawcze. Nowy agent rozpoczyna od aktualnego `main` w świeżym worktree, branchu i PR.

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

Aktywny lokalny builder działa wyłącznie po scaleniu:

```text
exact final main SHA
  -> Git LFS
  -> build
  -> smoke
  -> builds/by-sha/<SHA>
  -> builds/current tylko po PASS
```

Jednorazowy przebieg z katalogu czystego lokalnego mirroru `main`:

```powershell
pwsh -NoProfile -File .\tools\build_playable_main.ps1 -Repository .
```

Dodanie `-Watch` uruchamia ciągłe oczekiwanie na kolejne SHA `main`. Builder sam wykonuje bezpieczną synchronizację, LFS, export i smoke; nie jest zadaniem autora PR. Błąd builda albo smoke pozostawia poprzednie `builds/current` bez zmian. Oznacza to dwa stabilne poziomy: `main` jest pełnozielonym kodem, a `current` najnowszym pełnozielonym `main`, który dodatkowo poprawnie się zbudował. Bieżące wyniki odbioru opisuje [`.ai/PROJECT_CONTEXT.md`](.ai/PROJECT_CONTEXT.md).

Na komputerze do grania watcher instaluje się jednorazowo i później sam wraca po zalogowaniu:

```powershell
.\tools\install_playable_builder.ps1 `
  -Repository D:\Dev\Game\play-main `
  -GodotConsolePath <pełna-ścieżka-do-Godot_console.exe> `
  -StartNow
```

Task Scheduler gwarantuje jedną instancję, wznowienie po awarii i start po logowaniu. Dla niezmienionego SHA kompletny artefakt jest tylko raportowany jako oczekujący — LFS, export i zapis `current` nie są ponawiane co 30 sekund.

## Rzadkie zmiany control-plane

Automatyczna ścieżka publikacji rozpoznaje między innymi:

- `.github/workflows/**`;
- narzędzi odpowiedzialnych za CI;
- konfiguracji `integration-green`;
- control-plane finalnego buildera.

Jeżeli diff je zawiera, `publish_agent_pr.ps1` publikuje PR bez auto-merge i bez automatycznego enqueue. Właściciel podejmuje jawną ręczną decyzję; pozytywna decyzja nie omija GitHub `fast-check` ani pełnego `integration-green` merge group. Bieżący plan GitHub i wspólna tożsamość konta nie zapewniają twardego rozdzielenia autora od zatwierdzającego. Pełna separacja wymagałaby osobnej GitHub App lub tożsamości i nie jest wdrażana teraz.

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

Agent Nurka rozpoczyna od krótkiego routingu w lokalnym `AGENTS.md`: dla rutynowej animacji albo socketu czyta tylko właściwy punkt `.ai/PROJECT_CONTEXT.md`, odpowiednią sekcję `README.md` oraz zmieniane źródła i test. Pełne lokalne decyzje i dokumenty root są wymagane dopiero przy zmianie skali, collidera, punktu emisji światła, produktu, publicznego kontraktu, zapisu, migracji albo granicy właściciela. Ogólne reguły ruchu, tlenu, ryzyka, wyposażenia, UI, sesji i zapisu pozostają w root, a mapa i okludery w `underwater_map_workbench/`.

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

Pełną regresję uruchamia `integration-green` na merge group w GitHub. Zwykły agent nie wykonuje jej przed PR; lokalnie pozostaje szybka bramka i cele proporcjonalne do zadania. Tryby pełne i snapshotowe są narzędziami wykonawcy CI albo jawnej diagnostyki, nie krokiem codziennego przepływu autora.

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

- `AGENTS.md` — proces pracy, proporcjonalny dobór kontekstu i routing edycji;
- `.ai/PROJECT_CONTEXT.md` — potwierdzony runtime, luki, pułapki i ostatnia weryfikacja;
- `.ai/DECISIONS.md` — trwałe decyzje, powody i jawne zastąpienia;
- `docs/OgolnyZarys.txt` — produkt, zasady, balans, narracja i zakres;
- `docs/Ostatni_Pomost_architektura_Godot.txt` — mapowanie systemów, danych, persistence i testów;
- `underwater_map_workbench/` — wyspecjalizowany onboarding, kontekst produkcji i decyzje dla mapy podwodnej oraz jej grafiki świata;
- `underwater_map_workbench/structures/<id>/` — operacyjny pakiet lokalnej topologii, grafiki, runtime i testów jednego zarejestrowanego budynku; reguły produktu pozostają w dokumentach root;
- `diver_workbench/` — wyspecjalizowany onboarding, migawka, decyzje i testy sceny avatara nurka.
