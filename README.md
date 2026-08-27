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

Helper domyślnie tylko pokazuje plan. Candidate receipt potwierdza exact commit/tree i zamknięty zestaw plików, ale sam nie dowodzi przejścia testów. Właściwe utworzenie wymaga receiptu kandydata, unikalnego task slugu, dokładnego ID tasku i threadu, krótkiego briefu, zamkniętego write-setu oraz jawnego `-Create`:

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

$taskId = "task/map-art-pass"
$threadId = "<exact-codex-thread-id>"
$taskBrief = "Dopracuj wyłącznie mapowe assety L01/L02 i ich lokalną dokumentację."
$writeSet = Join-Path $evidenceRoot "map-art-pass.write-set"
[IO.File]::WriteAllLines($writeSet, @(
  "underwater_map_workbench/assets/environment/l01_water",
  "underwater_map_workbench/assets/environment/l02_background"
), $utf8NoBom)
$destination = Join-Path (Resolve-Path ..) "agent-worktrees\map-map-art-pass"
$setup = @{
  CandidateReceipt = $candidateReceipt
  RunReceipt = $runReceipt
  Owner = "map"
  TaskSlug = "map-art-pass"
  TaskId = $taskId
  ThreadId = $threadId
  TaskBrief = $taskBrief
  WriteSet = $writeSet
  Destination = $destination
}
.\tools\setup_agent_worktree.ps1 @setup
.\tools\setup_agent_worktree.ps1 @setup -Create

$assignment = (python -B .\tools\workbench_contract.py --repo . `
  assignment status --task-id $taskId --json | Out-String) | ConvertFrom-Json
$assignmentId = [string]$assignment.assignment.assignment_id
Push-Location $destination
python -B .\tools\workbench_contract.py --repo . assignment ack `
  --task-id $taskId --assignment-id $assignmentId --thread-id $threadId `
  --owner map --write-set $writeSet
if ($LASTEXITCODE -ne 0) { throw "Task nie uzyskał ACK; nie wolno zaczynać zapisów." }
Pop-Location
```

Listy w przykładzie są zamkniętymi kotwicami wejścia/wyjścia, a candidate receipt dodatkowo przypina cały exact `HEAD^{tree}`. `lkg promote` ponownie weryfikuje oba receipty i przesuwa ref wyłącznie fast-forward przez compare-and-swap względem jawnego `--expected-old`; nie uruchamia ponownie Godota. `setup_agent_worktree.ps1` sprawdza przed i po materializacji, że candidate HEAD, pełny run HEAD i ref są nadal identyczne, a wyścig wycofuje wyłącznie zasoby własnej próby. Jego ostatnim markerem jest hashowany bundle `<git-common-dir>/codex-agent-assignments/v1/...` w stanie `WAITING_ACK`; samo istnienie worktree nie oznacza uruchomionego autora. Dopiero ACK z dokładnego, czystego destination zmienia stan na `RUNNING`. Nowe zadanie otrzymuje gałąź `codex/<owner>/<task-slug>`. Targeted `PASS` nie wystarcza. Pierwsza migracja wymaga nowego pełnego green na rewizji zawierającej resolver i promocji z `--expected-old missing`; historyczny candidate bez resolvera nie jest automatycznie uznawany za LKG.

Po ACK używaj węższej bramki przydziału. Timeout nie tworzy nowego autora: koordynator ponawia ten sam task/thread/worktree przez `assignment redispatch`; po hand-offie zamyka go przez `assignment close`. `gc` wyłącznie raportuje plan retencji i nie usuwa bundle'i:

```powershell
python -B .\tools\workbench_contract.py --repo $destination validate `
  --owner map --assignment $assignmentId --task-id $taskId `
  --thread-id $threadId --diff
python -B .\tools\workbench_contract.py --repo $destination assignment status `
  --task-id $taskId
python -B .\tools\workbench_contract.py --repo $destination assignment close `
  --task-id $taskId --assignment-id $assignmentId --thread-id $threadId `
  --reason "handoff complete"
python -B .\tools\workbench_contract.py --repo . assignment gc --retention-days 30
```

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
python -B .\tools\workbench_contract.py validate --owner <owner> `
  --assignment <assignment-id> --task-id <task-id> --thread-id <thread-id> --diff
git push -u origin HEAD
git rev-parse HEAD
```

Handoff podaje exact SHA i receipty. Po jego przekazaniu nie wykonuj rebase ani force-pusha tej rewizji; poprawka jest nowym commitem i nowym receiptem. Cudzą zależność pobieraj po `fetch` z exact SHA albo stacked PR, nigdy z live worktree i nigdy z ruchomego tipa gałęzi.

GitHub Actions rozdziela szybką informację zwrotną od pełnej bramki. `.github/workflows/agent-validation.yml` uruchamia lekki, read-only kontrakt po pushu `codex/*`; cel 30 sekund dotyczy tej warstwy, nie pełnego przebiegu Godota. `.github/workflows/agent-integration.yml` przyjmuje immutable base/head, tworzy centralny plan Git LFS i uruchamia równolegle cztery osobne Windows VM headless, jedną natywną oraz zaufany, niedestrukcyjny check authority Mapy. Każdy target powstaje w świeżej kopii importowanego seedu, ma prywatne `.godot`, `user://`, TEMP/TMP i porty, a wynik wraca jako receipt v2. Agregator pobiera plan, dokładnie pięć receiptów shardów oraz osobny mapowy receipt z logiem po exact artifact ID, a następnie sprawdza digest, run ID i zgodność z tym samym kandydatem oraz planem. Dopiero komplet terminalnych PASS może opublikować jedyny check `integration-green`; jego external ID v3 zawiera digest kanonicznego receipt-setu, który hashuje w ustalonej kolejności SHA-256 candidate receipt, pełnego agregatu Godota i mapowego receiptu.

Shardy nie mają sekretów ani prawa zapisu repozytorium. Proces Godota dostaje oczyszczone środowisko, a zaufany rodzic przechwytuje stdout/stderr, domyślnie oznacza wynik jako FAIL i wymaga pojedynczego completion record. To skutecznie rozdziela współpracujących agentów i przypadkowe zapisy, ale nie jest sandboxem na złośliwy kod działający jako konto runnera; taki model wymaga restricted SID/DACL albo dodatkowej guest VM.

Publiczne repo ma aktywny GitHub ruleset wymagający PR do `main`, rozwiązania wątków review oraz blokujący deletion i non-fast-forward bez bypassu. `AUTO_INTEGRATOR_ENABLED` pozostaje wyłączone. Włącz je dopiero po opublikowaniu workflow na `main`, pierwszym zielonym exact-main runie, konfiguracji GitHub App/environment oraz strict rulesetu wymagającego dokładnie jednego `integration-green`. Do tego czasu jeden integrator kolejkuje i scala kandydatów sekwencyjnie; lokalne assignment/candidate/run digesty nie są dowodem zdalnego status checku.

GitHub App attestera instaluj wyłącznie w tym repozytorium z uprawnieniami Checks R/W i Commit statuses R/W; token workflow jest dodatkowo zawężany do `checks:write`. Repozytorium wymaga variables `INTEGRATION_ATTESTER_CLIENT_ID` i `INTEGRATION_ATTESTER_APP_ID`. Ten sam sekret `INTEGRATION_ATTESTER_PRIVATE_KEY` zapisz osobno w environments `integration-attester` i `control-plane-maintenance`; nie zapisuj go jako sekret shardów. Environment maintenance ma dokładnie jednego reviewera — właściciela repo — z jawnym dopuszczeniem self-review, ponieważ repo ma jednego maintainera, oraz wyłączony administracyjny bypass. To jest świadomy jednoosobowy trust, nie dwuosobowy review.

Zwykły PR nie może zmieniać chronionego buildera Mapy ani jego dwóch testów wykonywalnych. Taka rzadka zmiana jest dwufazowa: pierwszy PR zawiera od jednego do trzech plików wyłącznie z listy `underwater_map_workbench/{tools/build_underwater_map.py,tests/portal_backdrop_clearance_test.py,tests/underwater_map_smoke_test.gd}`, ma label `control-plane-reviewed` i zewnętrzny bundle przeglądu. Uruchom z exact `main`:

```powershell
gh workflow run "Map control-plane maintenance authorization" --ref main `
  -f pr_number=<PR> `
  -f base_sha=<exact-main-SHA> `
  -f candidate_sha=<exact-PR-head-SHA> `
  -f evidence_sha256=<SHA-256-bundle-przegladu>
```

Po ręcznej akceptacji environment workflow certyfikuje kandydata tym samym `integration-green`, lecz nigdy go nie scala. Właściciel scala PR ręcznie; handler `pull_request: closed` sprawdza najnowszą exact rodzinę `PR/base/head/authorization`, zamkniętą listę ścieżek i ancestry, po czym automatycznie uruchamia `verify-integrated-main`. Dopiero zielony exact-main audyt pozwala utworzyć osobny zwykły PR z runtime, manifestem, sceną, generated albo dokumentacją Mapy. Pozostawiony `queued` jest redispatchowany. Ręczny retry po wiszącym `in_progress` lub failure tworzy nowszy Check Run; stare wykonanie pozostaje przypięte do starszego ID i nie może wygrać najnowszej rodziny. Authorization i audit mają osobne kolejki per exact zgoda oraz PR/head, a nieudany dispatch kończy wybrany check jako failure.

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
