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
- wizualne prefaby mapy: `res://scenes/diving/map_visuals/`;
- przyszłe zatwierdzone mastery i ArtCells: `res://assets/diving/world/art_cells/`;
- layout guides i provenance: `res://assets/diving/world/layout_guides/`;
- tła i foregroundy: `res://assets/diving/world/backdrops/`, `res://assets/diving/world/foregrounds/`;
- materiały, shadery i propsy: `res://assets/diving/world/materials/`, `res://assets/diving/world/shaders/`, `res://assets/diving/world/props/`;
- profile prezentacyjne regionów: `res://data/diving_visuals/`;
- pochodne streamingu: `res://assets/diving/world/map_v2/visual_chunks/`;
- mapowe narzędzia i testy: `res://tools/` oraz `res://tests/`, tylko w zakresie wskazanym przez `AGENTS.md`.

Nie przenoś tych plików do warsztatu. Produkcyjne ścieżki, UID-y i import Godota pozostają w pełnym projekcie.

## Bieżący baseline

- Commit odniesienia `a1c33d5` usunął odrzuconą szeroką panoramę R1, pięć jej źródeł, 24 cropy i generator `build_dive_art_cells.py`.
- Aktywny manifest zawiera jedną warstwę `environment_decoration` i 15 cropów. Jej źródłowy master jest zarchiwizowany i nie istnieje w repozytorium.
- `build_dive_visual_chunks.py` nie ma `--check` i nie potrafi odbudować warstwy bez brakującego źródła. Nie używaj go jako aktywnego buildera, dopóki pipeline nie zostanie jawnie naprawiony albo zastąpiony.
- Pełnomapowy layout guide v1, manifest i generator są wersjonowanym pakietem referencyjnym z deterministycznym `--check`.
- Nie istnieje zaakceptowany szeroki composition master R1-R4.

Dokładny stan i rozdzielone statusy techniczny/artystyczny są w `.ai/PROJECT_CONTEXT.md`.

## Jak pracować

1. Rozpocznij z tego katalogu i przeczytaj `AGENTS.md` oraz właściwy kontekst wskazany przez jego routing.
2. Sprawdź `git -C .. status --short` i nie nadpisuj cudzych zmian.
3. Przed edycją nazwij dokładne pliki oraz ich kategorię: źródło, pochodna, cache albo ścieżka chroniona.
4. Edytuj źródło, nigdy ręcznie pochodny crop, raster kolizji lub SDF.
5. Dla szerokiej grafiki przejdź bramkę master-first z MAP-ARD-0001; dla lokalnego propu, materiału lub prefabu stosuj proporcjonalny zakres.
6. Po zmianie uruchom build, `--check`, celowane testy i właściwy snapshot tylko wtedy, gdy zadanie zezwala na zapis i wykonanie.
7. Obejrzyj wynik oraz sprawdź końcowy diff całego projektu przez `git -C ..`.

## Komendy z katalogu warsztatu

### Layout guide

Budowa zapisuje PNG i manifest w `res://assets/diving/world/layout_guides/full_map/`:

```powershell
python ..\tools\build_dive_map_layout_guide.py
python ..\tools\build_dive_map_layout_guide.py --check
```

Tryb `--check` nie zapisuje plików. Porównuje źródła, manifest i zdekodowane piksele bez zależności od fontów systemowych albo wariantu kompresji PNG.

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
