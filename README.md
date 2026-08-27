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

Każdy jednocześnie zapisujący agent pracuje w osobnym pełnym Git worktree i na gałęzi `codex/<owner>/<task-slug>` z commita integracyjnego potwierdzonego candidate receiptem, zgodnym pełnym run receiptem `PASS` oraz lokalnym refem `refs/last-green/integration`. Osobny katalog roboczy wewnątrz tego samego checkoutu nie izoluje indeksu Git, plików ani Godota. Nie twórz baseline'u z bieżącego dirty stanu ani nie traktuj samego `HEAD` lub candidate receiptu jako dowodu zielonych testów.

Sprawdzenie właściciela i planowanego diffu:

```powershell
python -B .\tools\workbench_contract.py --repo . eol-check
python -B .\tools\workbench_contract.py doctor --owner map --intent author
python -B .\tools\workbench_contract.py validate --owner map --diff
```

Dozwoleni ownerzy to `root`, `map`, `diver`, `structure:<id>` i `integration`. Strażnik uwzględnia pliki śledzone oraz wymagane niesledzone pliki niewykluczone przez `.gitignore`, a `generated/**` struktur przypisuje Mapie. `eol-check` dopuszcza dirty treść zapisaną LF, lecz odrzuca tracked `w/crlf` i `w/mixed` przy `eol=lf`; runner i builder wykonują tę samą bramkę automatycznie. Candidate receipt sprawdza mocniej surowe bajty śledzonych plików względem exact HEAD/index, więc nieprzenośnego checkoutu nie da się ukryć samym czystym statusem Git.

Helper domyślnie tylko pokazuje plan. Candidate receipt potwierdza exact commit/tree i zamknięty zestaw plików, ale sam nie dowodzi przejścia testów. Właściwe utworzenie wymaga receiptu kandydata, unikalnego task slugu i jawnego `-Create`:

```powershell
$evidenceRoot = Join-Path (Resolve-Path ..) ("agent-evidence\" + (git rev-parse --short HEAD))
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$runReceipt = Join-Path $evidenceRoot "full-run.receipt"
$candidateReceipt = Join-Path $evidenceRoot "candidate-receipt.json"
$inputList = Join-Path $evidenceRoot "candidate-inputs.list"
$outputList = Join-Path $evidenceRoot "candidate-outputs.list"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllLines($inputList, @("project.godot"), $utf8NoBom)
[IO.File]::WriteAllLines($outputList, @("underwater_map_workbench/UnderwaterMap.tscn"), $utf8NoBom)

.\tests\run_all_tests.ps1 -Full -RunReceiptOutputPath $runReceipt
if ($LASTEXITCODE -ne 0) { throw "Pełna bramka nie przeszła; candidate nie jest green." }
python -B .\tools\workbench_contract.py publication create `
  --input-list $inputList --output-list $outputList `
  --input-root project.godot `
  --output-root underwater_map_workbench/UnderwaterMap.tscn `
  --receipt $candidateReceipt

$expectedOld = (& git rev-parse --verify --quiet refs/last-green/integration 2>$null)
if ([string]::IsNullOrWhiteSpace($expectedOld)) { $expectedOld = "missing" }
python -B .\tools\workbench_contract.py lkg promote `
  --candidate-receipt $candidateReceipt --run-receipt $runReceipt `
  --expected-old $expectedOld
if ($LASTEXITCODE -ne 0) { throw "Lokalna promocja LKG nie przeszła." }
python -B .\tools\workbench_contract.py lkg resolve `
  --candidate-receipt $candidateReceipt --run-receipt $runReceipt

.\tools\setup_agent_worktree.ps1 -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt -Owner map -TaskSlug map-art-pass -Destination ..\agent-worktrees\map-map-art-pass
.\tools\setup_agent_worktree.ps1 -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt -Owner map -TaskSlug map-art-pass -Destination ..\agent-worktrees\map-map-art-pass -Create
.\tools\setup_agent_worktree.ps1 -CandidateReceipt $candidateReceipt -RunReceipt $runReceipt -Owner structure:tower_prototype_01 -TaskSlug tower-audio -Destination ..\agent-worktrees\tower-prototype-01-tower-audio -Create
```

Listy w przykładzie są zamkniętymi kotwicami wejścia/wyjścia, a candidate receipt dodatkowo przypina cały exact `HEAD^{tree}`. `lkg promote` ponownie weryfikuje oba receipty i przesuwa ref wyłącznie fast-forward przez compare-and-swap względem jawnego `--expected-old`; nie uruchamia ponownie Godota. `setup_agent_worktree.ps1` sprawdza przed i po materializacji, że candidate HEAD, pełny run HEAD i ref są nadal identyczne, a wyścig wycofuje nowe drzewo. Nowe zadanie otrzymuje gałąź `codex/<owner>/<task-slug>`. Targeted `PASS` nie wystarcza. Pierwsza migracja wymaga nowego pełnego green na rewizji zawierającej resolver i promocji z `--expected-old missing`; historyczny candidate bez resolvera nie jest automatycznie uznawany za LKG.

`refs/last-green/integration` jest wyłącznie lokalnym authority wspólnego Git common-dir: widzą go wszystkie linked worktrees tego klonu, ale nie jest przesyłany przez clone, fetch ani push. Zdalny LKG wymagałby osobnego chronionego refspecu albo authority CI i nie jest tutaj wdrożony. Osobne worktrees przeznacz dla integracji oraz ręcznego edytora/playtestu. Producent przekazuje integratorowi niezmienny commit albo zweryfikowaną rewizję FROZEN i może od razu rozwijać N+1. Wspólny lock jest potrzebny tylko przy krótkiej publikacji wieloplikowego wyniku Mapy, nie podczas prywatnego authoringu ani testów.

Repozytoryjny hook blokuje bezpośrednie pushe agentów do `main`, tagi, kasowanie refów i non-fast-forward/force-push istniejących gałęzi `codex/*`. Ten sam zachowany strumień rekordów push najpierw przechodzi lokalną politykę refów, a po jej akceptacji trafia do `git lfs pre-push`; brak albo błąd Git LFS blokuje push. Instalator jest domyślnie plan-only; właściwa instalacja ustawia współdzielone przez linked worktrees `core.hooksPath=.githooks`:

```powershell
.\tools\install_agent_git_hooks.ps1
.\tools\install_agent_git_hooks.ps1 -Install
```

Przed hand-offem agent pobiera wyłącznie referencje, sprawdza swój owner/diff i celowane testy, tworzy mały logiczny commit, a następnie po raz pierwszy pushuje własną gałąź:

```powershell
git fetch --prune
python -B .\tools\workbench_contract.py doctor --owner <owner> --intent author
python -B .\tools\workbench_contract.py validate --owner <owner> --diff
git push -u origin HEAD
git rev-parse HEAD
```

Handoff podaje exact SHA i receipty. Po jego przekazaniu nie wykonuj rebase ani force-pusha tej rewizji; poprawka jest nowym commitem i nowym receiptem. Cudzą zależność pobieraj po `fetch` z exact SHA albo stacked PR, nigdy z live worktree i nigdy z ruchomego tipa gałęzi. Workflow `.github/workflows/agent-integration.yml` publikuje raport i run receipt dla PR/manual/`merge_group`, ale sam nie chroni `main`. Dopóki hosting nie egzekwuje branch protection i required checks, tylko jeden integrator kolejkuje i scala kandydatów sekwencyjnie; lokalny hook jest celowo słabszą ochroną proceduralną.

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
