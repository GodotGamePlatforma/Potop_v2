# Warsztat mapy podwodnej

Ten katalog jest punktem wejścia dla Codexa projektującego `UnderwaterMap` oraz grafikę, assety i prezentację świata nurkowania. Codex pracuje z tego katalogu i tylko w domenie mapy. Pełny projekt Godot pozostaje w katalogu nadrzędnym `..`; warsztat nie jest jego kopią ani osobnym projektem.

## Uruchomienie Codexa

Na bieżącej maszynie:

```powershell
Set-Location D:\Dev\Game\Game\underwater_map_workbench
Test-Path ..\project.godot
git -C .. status --short --branch
```

W Codex Desktop otwórz katalog `underwater_map_workbench`. W CLI można uruchomić nową sesję poleceniem:

```powershell
codex --cd D:\Dev\Game\Game\underwater_map_workbench
```

W innym checkoutcie lub Git worktree użyj odpowiadającej mu ścieżki `<repo>\underwater_map_workbench`. Nie otwieraj samej kopii tego katalogu bez rodzica zawierającego `project.godot`.

Codex automatycznie otrzymuje instrukcje korzeniowe, a następnie bliższy `underwater_map_workbench/AGENTS.md`, który zawęża pracę do mapy. Po zmianie pliku `AGENTS.md` rozpocznij nową sesję, ponieważ łańcuch instrukcji jest budowany na początku uruchomienia.

## Dokumenty warsztatu

- `AGENTS.md` — obowiązkowy proces Codexa, lokalny CWD, allowlista i bramki;
- `.ai/PROJECT_CONTEXT.md` — datowana migawka assetów, luk i ostatniej kontroli;
- `.ai/DECISIONS.md` — trwałe decyzje kompozycji, pipeline'u, provenance i akceptacji;
- `README.md` — niniejszy onboarding, ścieżki i komendy.

Reguły gry, globalna architektura, persistence i potwierdzony runtime pozostają u właścicieli w katalogu nadrzędnym. Lokalny `AGENTS.md` określa, które ich sekcje trzeba przeczytać dla danego typu zadania.

## Kanoniczne ścieżki projektu

Ścieżki `res://` są niezależne od lokalizacji worktree:

- mapa i authority statycznego świata: `res://scenes/diving/UnderwaterMap.tscn`;
- wizualne prefaby mapy, w tym edytowalna kompozycja `UnderwaterMapSixLayerVisuals.tscn` i szablon `LayerVisualElement.tscn`: `res://scenes/diving/map_visuals/`;
- przyszłe zatwierdzone mastery i ArtCells: `res://assets/diving/world/art_cells/`;
- layout guides i provenance: `res://assets/diving/world/layout_guides/`;
- kandydaci szerokich composition masterów i ich cropy podglądowe: `res://assets/diving/world/layout_guides/composition_masters/`;
- referencje języka wizualnego, warstwy parallax i ich manifesty provenance: `res://assets/diving/world/layout_guides/style_references/`; nie są masterem, topologią ani assetem ładowanym przez grę;
- niezależne tekstury elementów biomów gotowe do przypisania do `Sprite2D`: `res://assets/diving/world/layout_guides/style_references/biomes_v3_sprite_elements_v1/`;
- historyczne sześciowarstwowe referencje pierwotnych 28 landmarków: `res://assets/diving/world/layout_guides/style_references/landmarks_v1_six_layer/`; wycofane `R2-04` pozostaje tam tylko jako provenance i nie jest kandydatem runtime;
- tła i foregroundy: `res://assets/diving/world/backdrops/`, `res://assets/diving/world/foregrounds/`;
- materiały, shadery i propsy: `res://assets/diving/world/materials/`, `res://assets/diving/world/shaders/`, `res://assets/diving/world/props/`;
- profile prezentacyjne regionów i sześciu planów: `res://data/diving_visuals/`;
- pochodne streamingu: `res://assets/diving/world/map_v2/visual_chunks/`;
- mapowe narzędzia i testy: `res://tools/` oraz `res://tests/`, tylko w zakresie wskazanym przez `AGENTS.md`.

Nie przenoś tych plików do warsztatu. Produkcyjne ścieżki, UID-y i import Godota pozostają w pełnym projekcie.

## Bieżący baseline

- Commit odniesienia `a1c33d5` usunął odrzuconą szeroką panoramę R1, pięć jej źródeł, 24 cropy i generator `build_dive_art_cells.py`.
- Runtime ma dokładnie sześć planów `L00-L05` z profilami `scroll_scale`; `L04` pozostaje związana ze światem, a `reduced_motion` ustawia wszystkie plany na `(1,1)` bez ukrywania grafiki. Kompozycja i transformy elementów należą do `UnderwaterMapSixLayerVisuals.tscn`, nie do manifestu.
- Aktywny `map_visual_chunks_v2.json` opisuje sześć planów i adoptuje 15 zachowanych cropów jako 15 osobnych, wybieralnych elementów L02. Zamrożony manifest v1 oraz PNG pozostają nienaruszonym dowodem integralności; ich źródłowy master jest zarchiwizowany i nie istnieje w repozytorium.
- `build_dive_visual_chunks.py --build` zapisuje atomowo wyłącznie manifest v2 po walidacji sceny, profili, v1 i wszystkich cropów; `--check` niczego nie zapisuje. Builder nigdy nie otwiera brakującego mastera ani nie modyfikuje zamrożonych PNG.
- Pełnomapowy layout guide v1, manifest i generator są wersjonowanym pakietem referencyjnym z deterministycznym `--check`.
- `biomes_v2_layered` zawiera cztery spłaszczone guide'y kompozycyjne R1-R4 oraz ich manifest provenance; nie są warstwami runtime ani composition masterem.
- `biomes_v3_six_layer` zawiera po sześć współosiowych PNG `L00-L05` dla każdego biomu, cztery pochodne podglądy złożenia, 21 wersjonowanych surowych wyników ImageGen i manifest reprodukcji. Użytkownik zaakceptował go jako wzorzec stylu i konstrukcji sześciu warstw; nie jest to akceptacja composition mastera ani assetu runtime.
- `biomes_v3_sprite_elements_v1` rozdziela zaakceptowane referencje V3 na 4 pełne płaszczyzny `L00`, 84 niezależne elementy core `L01-L05` oraz 30 niezależnych elementów suplementu R1. Każdy crop zachowuje źródłowe RGBA, ma 16 px przezroczystego marginesu i pozycję rekonstrukcyjną w manifeście; pakiet pozostaje referencją niepodłączoną do runtime.
- `landmarks_v1_six_layer` zachowuje historyczne 28 źródłowych arkuszy, 168 niezależnych PNG alfa `L00-L05`, 28 pochodnych podglądów, cztery regionalne rekordy pełnego provenance i manifest nadrzędny. `R2-04` jest wyłącznie wycofanym dowodem provenance; bieżąca mapa ma 27 landmarków. Zestaw oczekuje na odbiór artystyczny i pozostaje niepodłączony do runtime.
- `composition_masters/biomes_l01_v1` zawiera technicznie poprawny kandydat full-map `L01`, cztery regionalne cropy i manifest provenance. Ma `production_master = false`, `runtime_asset = false` oraz `PENDING_USER_REVIEW`.
- Nie istnieje zaakceptowany szeroki composition master R1-R4.

Dokładny stan i rozdzielone statusy techniczny/artystyczny są w `.ai/PROJECT_CONTEXT.md`.

## Edycja sześciu warstw runtime

Otwórz bezpośrednio `res://scenes/diving/map_visuals/UnderwaterMapSixLayerVisuals.tscn`; `UnderwaterMap.tscn` instancjuje tę kompozycję pod `VisualLayers/SixLayerVisuals`. Każdy plan `L00-L05` ma dwie przestrzenie (`ParallaxContent` i `WorldContent`) oraz trzy buckety (`Authored`, `Generated`, `Streamed`). Nowe ręcznie ustawiane elementy dodawaj do `Authored`; elementy związane z kolizją lub kanonicznym terenem umieszczaj w `WorldContent`, a zwykłe tło i dekoracje głębi w `ParallaxContent`.

Każdy niezależny obiekt musi być osobnym `DiveVisualLayerElement`, `Sprite2D`, `Polygon2D` albo kolizyjnie pustą instancją `PackedScene`. Jego zwykły transform `Node2D` i `visible` są authority pozycji, obrotu, skali, niezależnego rozciągania osi i ukrycia. Najprościej zduplikować `LayerVisualElement.tscn`, nadać unikalne `element_id`, wskazać teksturę lub scenę oraz ustawić `local_bounds`. Domyślny tryb `Scene Resident` sam ładuje zasób do dziecka `Attachment` i nie wymaga wpisu manifestu. `Manifest Streamed` wybieraj wyłącznie dla zasobu jawnie zarejestrowanego przez builder v2; obecnie dotyczy to 15 zaadaptowanych cropów L02. Oba tryby zachowują transform elementu, a jakość steruje tylko treścią `Attachment`, nigdy autorskim `visible=false`. Prefab `PackedScene` musi być czysto wizualny: bez własnych skryptów, kolizji, nawigacji, `CanvasLayer`, `top_level` i absolutnego albo lokalnie przesuniętego z-order; do ruchu całego obiektu używaj transformu zewnętrznego `DiveVisualLayerElement`.

Jedna spłaszczona bitmapa nadal jest jednym elementem. Aby przesuwać osobno rurę, roślinę lub fragment budynku, trzeba dostarczyć je jako osobne tekstury albo prefaby; sześć dużych PNG daje tylko sześć transformów. Obecne 15 cropów jest już niezależne między sobą, ale piksele wewnątrz pojedynczego cropa pozostają nierozdzielne z powodu brakującego źródła.

## Użycie elementów Sprite2D biomów

Pakiet `res://assets/diving/world/layout_guides/style_references/biomes_v3_sprite_elements_v1/` zawiera osobny PNG dla każdego logicznego obiektu z referencji biomów V3 oraz suplementu R1. Katalogi są rozdzielone według biomu i warstwy, a `biome_sprite_element_set_v1.json` zapisuje dla każdego pliku warstwę `L01-L05`, źródłowy prostokąt, SHA-256, punkt obrotu i początkową pozycję odtwarzającą referencję przy `Sprite2D.centered = true`. `L00` pozostaje pojedynczą pełną płaszczyzną koloru na biom.

Tekstury można przypisać pojedynczo do osobnych `Sprite2D` lub `DiveVisualLayerElement` i następnie ustawiać niezależnie w odpowiednim buckecie warstwy. Manifest jest wyłącznie provenance i pomocą kompozycyjną: nie ustanawia transformów produkcyjnych, stable ID ani authority mapy. Pakiet nie jest automatycznie ładowany przez grę i jego podłączenie do `UnderwaterMapSixLayerVisuals.tscn` pozostaje osobnym zadaniem runtime.

Element z `edge_locked = true` był już ucięty przez krawędź źródłowego płótna. Nadal jest niezależną teksturą, lecz po odsunięciu od odpowiadającej krawędzi ujawni prostą linię kadru; przed swobodnym umieszczeniem w otwartej wodzie wymaga outpaintu. Suplement R1 zachowuje osobny namespace i status `PENDING_USER_REVIEW`.

## Użycie warstw landmarków

Każdy landmark ma sześć współosiowych PNG `1024 × 512` ze wspólnym początkiem i bez przycinania płótna. Składaj je jako osobne dzieci `Sprite2D` w kolejności lokalnej `L00 rear_silhouette`, `L01 structural_shell`, `L02 identity_core`, `L03 detail_props`, `L04 terrain_integration`, `L05 foreground_occluder`. Źródłowy arkusz służy do provenance, a `derived/*_composite_preview.png` jest spłaszczonym podglądem nad kolorem biomu; żaden z nich nie jest siódmą warstwą runtime.

Docelowy prefab landmarku ma być kolizyjnie pustym `Node2D` w `res://scenes/diving/map_visuals/`, przypisywanym przez istniejące pole `Visual Scene` właściwego obiektu w `UnderwaterMap.tscn`. Samo przypisanie sceny jest osobnym zadaniem dotyczącym chronionego runtime. Warstwy nie mogą tworzyć kolizji, topologii, tras, stable ID ani obiektów gameplayowych; `L04` tylko wizualnie styka się z kanonicznym terenem.

Wszystkie sześć warstw pojedynczego landmarku pozostaje zakotwiczone do jego prefabu. Ogólny kontrakt `Visual Scene` daje kolejność rysowania, ale nie zapewnia niezależnego parallaxu względem kamery wewnątrz landmarku; szeroki parallax należy do warstw biomu. Jeżeli konkretne detale landmarku mają poruszać się niezależnie, wymaga to dedykowanej implementacji prezentacyjnej i weryfikacji runtime, a nie przesuwania plików referencyjnych.

Światło gameplayowe, globalne pole wody, mgła, caustics, refrakcja, cząstki, bąble, prąd, grading, profile jakości i `reduced_motion` pozostają efektami Godota. Nie należy wypiekać ich do tych PNG.

## Jak pracować

1. Rozpocznij z tego katalogu i przeczytaj `AGENTS.md` oraz właściwy kontekst wskazany przez jego routing.
2. Sprawdź `git -C .. status --short` i nie nadpisuj cudzych zmian.
3. Przed edycją nazwij dokładne pliki oraz ich kategorię: źródło, pochodna, cache albo ścieżka chroniona.
4. Edytuj źródło, nigdy ręcznie pochodny crop, raster kolizji lub SDF.
5. Dla szerokiej grafiki przejdź bramkę master-first z MAP-ARD-0001; dla lokalnego propu, materiału lub prefabu stosuj proporcjonalny zakres.
6. Po zmianie uruchom build, `--check`, celowane testy, właściwy snapshot i — dla szerokiej zmiany wizualnej — pełnomapowy survey tylko wtedy, gdy zadanie zezwala na zapis i wykonanie.
7. Otwórz wynik survey, oceń kontaktówkę, pełne kadry i ruch, a następnie sprawdź końcowy diff całego projektu przez `git -C ..`.

## Komendy z katalogu warsztatu

### Layout guide

Budowa zapisuje PNG i manifest w `res://assets/diving/world/layout_guides/full_map/`:

```powershell
python ..\tools\build_dive_map_layout_guide.py
python ..\tools\build_dive_map_layout_guide.py --check
```

Tryb `--check` nie zapisuje plików. Porównuje źródła, manifest i zdekodowane piksele bez zależności od fontów systemowych albo wariantu kompresji PNG.

### Manifest sześciu warstw

```powershell
python ..\tools\build_dive_visual_chunks.py --build
python ..\tools\build_dive_visual_chunks.py --check
```

Pierwsza komenda zapisuje atomowo tylko `map_visual_chunks_v2.json`; druga jest bez-zapisową bramką aktualności i integralności. Po zmianie sceny kompozycji lub profilu warstwy uruchom ponownie `--build`, a następnie `--check`.

Przy tworzeniu presetu eksportu dodaj `*.json` do filtra **Resources > Filters to export non-resource files/folders**, aby `map_visual_chunks_v2.json` trafił do PCK. Repozytorium nie zawiera obecnie `export_presets.cfg`, więc tej bramki nie da się odziedziczyć automatycznie ani potwierdzić eksportem bez wskazania docelowej platformy i presetu. Importowane tekstury pozostają zwykłymi zasobami Godota; runtime sprawdza ich dostępność przez `ResourceLoader`, a ścisłe SHA-256 plików źródłowych pozostaje bramką edytora/buildera.

### Elementy PNG biomów dla Sprite2D

```powershell
.\tools\build_biome_sprite_elements.ps1
.\tools\build_biome_sprite_elements.ps1 -Check
```

Pierwsza komenda deterministycznie odtwarza `biomes_v3_sprite_elements_v1` z zaakceptowanych referencji i osobnego suplementu R1. `-Check` buduje pełnego kandydata wyłącznie w katalogu tymczasowym, porównuje listę plików i wszystkie SHA-256 z pakietem w repozytorium, po czym usuwa kandydata bez zapisu do projektu. Każda z 24 płaszczyzn alfa musi złożyć się z wyciętych elementów bez różnicy pikselowej.

### Celowane testy mapy

```powershell
..\tests\run_all_tests.ps1 -Target tests/underwater_map_scene_test.gd
..\tests\run_all_tests.ps1 -Target tests/dive_visual_chunk_streaming_test.gd
..\tests\run_all_tests.ps1 -Target tests/underwater_environment_test.gd
..\tests\run_all_tests.ps1 -Target tests/continuous_map_collision_test.gd
```

Natywny snapshot świata:

```powershell
..\tests\run_all_tests.ps1 -NativeTarget tests/PngWorldSnapshot.tscn
```

Runner sam rozwiązuje korzeń projektu przez własny `$PSScriptRoot`, tworzy izolowaną kopię i wykonuje cele sekwencyjnie. `ERROR`, `SCRIPT ERROR`, timeout lub niezerowy kod oznaczają porażkę. W trybie `TYLKO ANALIZA` tych komend nie uruchamiaj.

### Automatyczny pełnomapowy survey runtime

Domyślny odbiór `high`, pełny ruch, 1280×720, 30 FPS, `600 u/s` i automatyczna trasa po całej mapie:

```powershell
..\tools\run_dive_map_visual_survey.ps1
```

Przykładowe warianty:

```powershell
..\tools\run_dive_map_visual_survey.ps1 -Quality medium -ReducedMotion
..\tools\run_dive_map_visual_survey.ps1 -CameraSpeed 1200 -MovieFps 20
..\tools\run_dive_map_visual_survey.ps1 -OutputDirectory D:\VisualSurveys
```

Launcher otwiera prawdziwe `GameRoot -> DiveScene`, ukrywa nurka i HUD, zatrzymuje stan sesji, a kamerę prowadzi poziomą serpentyną po 11×11 punktach pokrywających cały świat: pierwszy wiersz od lewej do prawej, krok w dół, drugi od prawej do lewej i tak dalej. Domyślny przejazd trwa około 3,5 minuty. Nie trzeba sterować postacią. To odbiór wizualny działającej mapy, nie test kolizji, osiągalności ani wejścia gracza.

Dla ochrony limitu 4 GB surowego AVI launcher wymaga `MovieFps / CameraSpeed <= 0.1`; komunikat błędu podaje bezpieczny maksymalny FPS dla wybranej prędkości.

Każdy przebieg powstaje w izolowanej pełnej kopii projektu. Domyślny katalog wyników to `%LOCALAPPDATA%\OstatniPomost\VisualSurveys\run_<timestamp>_<id>`; dokładną ścieżkę podaje linia `SURVEY_ARTIFACT_DIR=...`. `-OutputDirectory` wskazuje wyłącznie zewnętrzny katalog nadrzędny — launcher także pod nim zawsze tworzy nowy, unikalny `run_<timestamp>_<id>` i nigdy nie używa wskazanego katalogu jako miejsca do nadpisania poprzedniego przebiegu. Wynik zawiera:

- `full_map_scan.mp4` — przycięty film do oglądania, tworzony przez `ffmpeg`;
- `full_map_scan_raw.avi` — deterministyczny zapis Godot Movie Maker w MJPEG, walidowany przed konwersją;
- `contact_sheet_11x11.png` — całą mapę złożoną z 121 kadrów;
- `frames/frame_000.png` ... `frame_120.png` oraz metadane każdego kadru;
- `telemetry.jsonl` i `run_manifest.json` — trasę, streaming, renderer, profil i inwarianty.

Pełny przebieg może potrwać kilka minut, zwłaszcza przy pierwszym imporcie. Do kompletnego wyniku potrzebne są `ffmpeg` i `ffprobe` dostępne w `PATH`; gdy ich brakuje, launcher zachowuje surowy AVI, 121 PNG, telemetrię i manifest, ale zwraca `TECHNICAL_FAIL`, ponieważ nie może utworzyć albo zweryfikować MP4 i kontaktówki. `PASS` techniczny wymaga braku `ERROR`/`SCRIPT ERROR`, dokładnie 121 kadrów oraz surowego filmu i MP4 o zgodnym czasie, FPS, liczbie dekodowalnych klatek; MP4 musi także przejść pełne dekodowanie. Codex musi jeszcze naprawdę otworzyć artefakty i ocenić kompozycję; sama zielona komenda nie jest odbiorem artystycznym. W trybie `TYLKO ANALIZA` survey pozostaje zabroniony.

### Kontrola zakresu

```powershell
git -C .. status --short
git -C .. diff --name-only
git -C .. diff --check
```

Zwykły `git diff` nie pokazuje treści nowych plików untracked. Do odbioru przed commitem zawsze użyj również `git -C .. status --short --untracked-files=all`.

## Źródła, pochodne i cache

- Źródło ręczne: zaakceptowany master, maski, paleta, prefab wizualny albo profil `.tres`.
- Pochodna wersjonowana: ArtCell, crop runtime, layout guide, manifest, raster lub SDF odtwarzane z jawnego źródła.
- Źródło archiwalne: brakujące źródło jawnie oznaczone w manifeście; jego pochodne można zachować w runtime, ale nie wolno deklarować reprodukowalnego buildera.
- Cache Godota: `.godot/`; nie jest źródłem i nie podlega ręcznej edycji ani wersjonowaniu.
- Osierocone `.import`: lokalne metadane importu bez odpowiadającego źródła; nie są źródłem ani podstawą odbudowy assetu.

Każda nowa rewizja szerokiej grafiki przechowuje pełne provenance zgodnie z MAP-ARD-0004. Zgodny SHA albo overlap nie zastępuje odbioru całej kompozycji zgodnie z MAP-ARD-0003.

## Handoff

Po zadaniu podaj:

- zakres i listę zmienionych plików;
- źródła oraz wyprowadzone pochodne;
- wykonane komendy i wyniki;
- status techniczny oraz osobny wynik odbioru artystycznego;
- nierozwiązane luki i najbliższy bezpieczny krok.

Nie deklaruj testu, profilu ani akceptacji, których faktycznie nie wykonano.
