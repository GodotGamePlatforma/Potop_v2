# Warsztat avatara nurka

Ten katalog zawiera jedyny aktywny pakiet sceny gracza: `CharacterBody2D`, collider, gałąź wizualną, animacje, sockety, shadery, VFX oraz ich lokalne testy. Nie jest osobnym projektem Godot. Projekt, InputMap i ogólne systemy wyprawy znajdują się w `..`. Po wejściu do warsztatu wszystkie ścieżki w tym pliku są względem `diver_workbench/`.

## Pierwsze wejście

Z katalogu root projektu:

```powershell
Set-Location .\diver_workbench
Test-Path ..\project.godot
git -C .. status --short --branch
```

Agent rozpoczynający pracę w tym katalogu czyta kolejno `.ai/PROJECT_CONTEXT.md`, `.ai/DECISIONS.md` i ten plik zgodnie z lokalnym `AGENTS.md`.

## Granica pakietu

| Ścieżka | Odpowiedzialność |
|---|---|
| `runtime/Diver.tscn` | Jedyna scena gracza wraz z fizyczną bryłą, `InteractionRange`, kamerą, socketami i jednym centralnym `PointLight2D`. |
| `runtime/DiverController.gd` | Adapter wejścia i ogólnego kroku ruchu oraz właściciel orientacji, animacji, socketów i stałego wycentrowania źródła światła. |
| `runtime/DiverVisualEffects.gd` | Prezentacyjne pęcherzyki, ślady płetw, przeciek, działanie i krótkie cue. |
| `definitions/DiverSocketProfile.gd` | Walidowany typ dyskretnych socketów klatek. |
| `definitions/DiverFrameEnvelope.gd` | Zmierzone granice alfy 48 klatek konsumowane przez runtime i test. |
| `definitions/DiverFrameEnvelopeProfile.gd` | Walidowany typ docelowej koperty, skali i wycentrowania grafiki. |
| `assets/animation/` | Trzy aktywne arkusze 16-klatkowe i jeden zasób `SpriteFrames`. |
| `assets/profiles/` | Aktywny profil 288 socketów oraz walidowany profil koperty `105 × 60`. |
| `assets/shaders/` | Shader czytelności sylwetki; radialną teksturę latarni tworzy rootowy `LightSystem`. |
| `tests/` | Lokalny test Godot oraz natywny capture prezentacji. |

W root pozostają między innymi `scenes/diving/DiveScene.tscn`, `scripts/diving/DiveController.gd`, `DiveMovementSystem.gd`, tlen, ryzyko, walka, wyposażenie, UI, sesja, wynik i zapis. W `underwater_map_workbench/` pozostają mapa, teren, okludery i grafika świata. Nie twórz ich kopii tutaj.

Lokalne zadanie zapisuje tylko pliki pod bieżącym katalogiem. `../` i `../underwater_map_workbench/` są dla niego tylko do odczytu; zmiana wymagająca zapisu w root albo mapie jest zadaniem integracyjnym i przechodzi routing z `../AGENTS.md`.

Root steruje ruchem avatara przez publiczne metody `DiverController`, a ruchome bariery rozpoznają go przez jeden token `DiverController.DIVE_PLAYER_GROUP`. Pola bieżącego wejścia, prądu i sprintu oraz nazwy dzieci sceny są prywatne dla pakietu.

## Uruchamianie i testy

Root lub koordynator przydziela jedno proste zadanie jednemu agentowi Nurka. Autor pracuje w osobnym pełnym Git worktree na gałęzi `codex/diver/<task-slug>` utworzonej z aktualnego `origin/main`. Wdraża zmianę, uruchamia właściwy lokalny test i capture oraz lokalny `fast-check`, a dopiero po jego `PASS` tworzy commit, pushuje, otwiera jeden PR i włącza GitHub `merge when ready` metodą squash. Na tym kończy pracę bez pollingu. Wszystkie komendy korzystają ze wspólnego runnera i izolowanej pełnej kopii projektu z prywatnym `.godot`, `user://`, logami, portami procesu i capture. Jawny cel Nurka nie wykonuje globalnego discovery ani walidacji niezwiązanych pakietów Mapy. Z katalogu `diver_workbench/`:

```powershell
..\tests\run_all_tests.ps1 -Target diver_workbench/tests/DiverPresentationTest.tscn
```

Rootowy test ruchu i integracji sceny:

```powershell
..\tests\run_all_tests.ps1 -Target tests/dive_system_test.gd
```

Lokalny smoke Mapy celowo nie ładuje ani nie sprawdza wnętrza sceny Nurka. Testy prywatnego runtime zarejestrowanych struktur są odkrywane dynamicznie przez wspólny runner i pozostają w ich pakietach; dokumentacja Nurka nie wskazuje nazw ani ścieżek konkretnego budynku. Składanie warsztatów należy do testów integracyjnych root.

Natywny capture prezentacji:

```powershell
..\tests\run_all_tests.ps1 -NativeTarget diver_workbench/tests/DiverPresentationCapture.tscn
```

Capture zapisuje swoje artefakty w izolowanym workspace testu. Oprócz ruchu, profili jakości i socketów tworzy macierz alfy na tle collidera `105 × 60`, kadry po rzeczywistym kontakcie z pionową i poziomą ścianą oraz identyczne kadry `lantern_off`, `lantern_mk1_*` i `lantern_mk2_*` z centralnym radialnym światłem, markerami kierunków oraz okluderami. Wynik trzeba obejrzeć; sam brak błędu nie potwierdza dopasowania grafiki do collidera, prześwitów produkcyjnej mapy ani odczucia sterowania.

Po PR osobny wymagany GitHub `fast-check` sprawdza dokładny head. Dopiero jego `PASS` pozwala merge queue utworzyć kandydat `aktualny main + PR`; pełny `integration-green` uruchamia się wyłącznie na tym kandydacie. Agent nie czeka na kolejkę ani nie aktualizuje starego PR po każdym cudzym merge. Konflikt wraca do root jako nowe zadanie dla nowego agenta startującego z aktualnego `main`.

Runner odrzuca `-InPlace`; test Nurka zawsze działa w izolowanej kopii. `ERROR`, `SCRIPT ERROR`, timeout albo niezerowy kod procesu oznaczają porażkę.

## Źródło grafiki

Jedynym aktywnym authority wyglądu są trzy arkusze PNG, `assets/animation/diver_sprite_frames.tres` oraz profile pod `assets/profiles/`. Warsztat nie przechowuje roboczego modelu 3D, generatora AI ani odrzuconych renderów. Przyszła wymiana grafiki wymaga osobnego, kompletnego kandydata i jawnego odbioru przed atomową promocją do tych aktywnych ścieżek.

## Aktualny przepływ kompozycji

Aktywny runtime nadal składa się tak:

`arkusze PNG + SpriteFrames + profile socketów/koperty -> runtime/Diver.tscn -> DiveScene -> mapa runtime`

To jest kierunek własności i składania scen, nie pełny graf zależności runtime: lokalny adapter konsumuje rootowy system ruchu, a root instancjonuje i steruje publiczną sceną avatara. Zmiana organizacyjna powinna pozostawić obraz i fizykę identyczne. Zmiana grafiki lub animacji wymaga aktualizacji odpowiedniego źródła, zasobu klatek i socketów, a następnie testu i capture'u. `LampSocket` jest wizualnym punktem zgodności profilu, natomiast jedyny `DiveLight` pozostaje na originie nurka; promień, energia, kolor, cienie i stan radialnej latarni pochodzą z wyposażenia oraz systemów root. Zmiana skali, collidera, punktu emisji światła, parametrów ruchu albo `InteractionRange` jest zmianą produktu lub integracji i przechodzi globalną bramkę z `../AGENTS.md`.
