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

## Równoległa praca agentów

Codzienny przepływ użytkownika pozostaje krótki: osobny worktree, commit i zwykły PR. Helper nie wymaga receiptów ani lokalnego LKG, ale pod spodem zachowuje jeden trwały assignment, ACK i zamknięty write-set, aby równolegli agenci nie zapisywali tych samych plików.

Utworzenie worktree z aktualnego `origin/main`:

```powershell
$destination = Join-Path (Resolve-Path ..) "agent-worktrees\map-lighting"
.\tools\setup_agent_worktree.ps1 `
  -FromOriginMain -Owner map -TaskSlug map-lighting `
  -TaskId <task-id> -ThreadId <thread-id> -TaskBrief "Mapa: oświetlenie" `
  -WriteSet <pełna-ścieżka-do-write-set> `
  -Destination $destination -Branch codex/map/map-lighting
.\tools\setup_agent_worktree.ps1 `
  -FromOriginMain -Owner map -TaskSlug map-lighting `
  -TaskId <task-id> -ThreadId <thread-id> -TaskBrief "Mapa: oświetlenie" `
  -WriteSet <pełna-ścieżka-do-write-set> `
  -Destination $destination -Branch codex/map/map-lighting -Create
```

Druga komenda kończy się stanem `WAITING_ACK`. Agent wykonuje dokładny `assignment ack` podany w wyniku helpera i zaczyna zapis dopiero po stanie `RUNNING`.

Po zmianach uruchom testy celowane, zrób commit i opublikuj PR:

```powershell
git fetch --prune origin
python -B .\tools\workbench_contract.py --repo . eol-check
python -B .\tools\workbench_contract.py --repo . doctor --owner map --intent author
python -B .\tools\workbench_contract.py --repo . validate `
  --assignment <assignment-id> --task-id <task-id> --thread-id <thread-id> --diff
git add <własne-pliki>
git commit -m "Opis zmiany"
.\tools\publish_agent_pr.ps1 -Title "Opis zmiany"
```

Publisher wymaga czystego worktree, gałęzi `codex/*`, aktualnej bazy `origin/main`, dokładnie jednego assignmentu `RUNNING` i poprawnego assignment-scoped diffu. Pushuje exact HEAD, tworzy PR, wysyła `verify-fast-pr` do zaufanego receivera z `main` i włącza natywne auto-merge `squash` przypięte do tego HEAD. Wszystkie PR-y, także control-plane, przechodzą ten sam automatyczny przepływ.

## CI

PR blokuje dokładnie jeden App-owned check `fast-green`. Kandydacki workflow bez sekretów daje szybki feedback, natomiast zaufany receiver `repository_dispatch` z wersji `main` ponownie wiąże exact base/head, paginowany diff, ownera i EOL, a dopiero potem publikuje wymagany wynik. Ta sama bramka działa dla syntetycznego `merge_group`, dzięki czemu natywna kolejka testuje zmianę na aktualnym `main`. Celem operacyjnym jest około 30-60 sekund.

Zaufany klasyfikator z `main` oznacza jako wrażliwe między innymi cały control-plane. Wrażliwy PR przechodzi automatyczny Codex gate na exact head: tożsamość PR jest sprawdzana przed i po pobraniu diffu, kod kandydata nie jest wykonywany w jobie z sekretem, diff jest traktowany wyłącznie jako niezaufane dane, a wynik ma ścisłe `PASS`/`FAIL`. Diff łączący trust-root z runtime jest odrzucany automatycznie i trzeba go rozdzielić na dwa PR-y. Nie ma ręcznego review, merge, environment approval ani bypassu.

Po każdym merge workflow `.github/workflows/agent-integration.yml` uruchamia w tle niedestrukcyjny check Mapy, cztery odseparowane shardy headless i jeden natywny. Nowszy `main` anuluje starszy przebieg. Pełna regresja jest informacyjna: czerwony wynik jest widoczny w GitHub i artefaktach, ale nie cofa `main` i nie blokuje następnych agentów.

Jednorazowy bootstrap GitHub następuje dopiero po immutable review i zielonym exact-main. Najpierw instaluje istniejącą App `potop-v2-integration-attester` w organizacji, bezpiecznie potwierdza App ID 4737404 oraz dostępność `INTEGRATION_ATTESTER_PRIVATE_KEY` i `OPENAI_API_KEY` w automatycznym environment `integration-attester`, a `AUTO_INTEGRATOR_ENABLED` pozostawia wyłączone. Następnie dodaje App-owned `fast-green` obok starego `integration-green`, włącza AUTO jeszcze przy obu strict checkach i wykonuje osobne canary dla PR head oraz syntetycznego `merge_group`; niezależny pięciominutowy watchdog z `main` musi odtworzyć wynik także po regeneracji grupy. Dopiero po obu sukcesach usuwa stary check oraz ustawia `SQUASH` i `merge_queue` (`ALLGREEN`, maksymalnie jeden PR w grupie). PR, strict checks oraz zakaz deletion/non-fast-forward pozostają aktywne; exact JSON i SHA-256 rulesetu są zapisywane przed i po, a błąd przywraca poprzedni ruleset i AUTO=false. Ten commit nie ustawia sekretów, nie zmienia rulesetu i nie instaluje runnera.

## Lokalny builder i `current`

`tools/sync_play_main.ps1` rozdziela najnowszy kod od najnowszej zweryfikowanej gry. Osobny standalone source clone jest wyłącznie czystym mirrorem `main`. Jeden runner zapisuje trwałą kolejkę wszystkich nowych SHA, przetwarza je sekwencyjnie i dla każdego tworzy oddzielny immutable katalog build/test. Dopiero LFS fsck, map-check, realny eksport, pełne testy i smoke wyeksportowanego programu atomowo przełączają wskaźnik `current`; FAIL publikuje czerwony status i alert bez zmiany ostatniego grywalnego builda.

Jednorazowa próba i instalacja zadania uruchamianego co minutę:

```powershell
$play = 'D:\Dev\Game\potop-playable'
$latest = 'D:\Dev\Game\potop-main-mirror'
$godot = '<pełna-ścieżka-do-Godot_v4.7.1-stable_win64_console.exe>'
.\tools\sync_play_main.ps1 -Mode RunOnce -LatestPath $latest -PlayPath $play -GodotConsolePath $godot
.\tools\sync_play_main.ps1 -Mode Install -LatestPath $latest -PlayPath $play -GodotConsolePath $godot
.\tools\sync_play_main.ps1 -Mode Status -PlayPath $play
```

Po restarcie runner wznawia pierwszy nieterminalny element i nie pomija żadnego SHA. W repo nie ma jeszcze `export_presets.cfg` ani produkcyjnego smoke eksportu, dlatego dzisiejszy przebieg kończy się jawnie `EXPORT_BOOTSTRAP_REQUIRED` i nie może ustanowić grywalnego `current`.

Receipty i LKG są wewnętrzną diagnostyką CI/buildera, a nie ręcznym wejściem autora. Assignment i ACK pozostają automatyczną koordynacją identity/write-setu worktree, nie dowodem jakości produktu.

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
