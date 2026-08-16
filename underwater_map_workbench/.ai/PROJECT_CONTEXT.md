# Kontekst warsztatu mapy podwodnej

Rola tego pliku: krótka, datowana migawka produkcji grafiki mapy, potwierdzonych braków, pułapek i ostatniego odbioru. Nie jest instrukcją pracy ani roadmapą. Globalny runtime i przekrojowe luki należą do `../../.ai/PROJECT_CONTEXT.md`, reguły gry do `../../docs/OgolnyZarys.txt`, a techniczna authority do `../../docs/Ostatni_Pomost_architektura_Godot.txt`.

## Stan na 2026-08-16

- Zweryfikowany baseline historii: `a1c33d5` (`Remove rejected R1 ArtCell background`). Bieżąca rewizja dodaje wersjonowany warsztat, pełnomapowy layout guide z generatorem oraz stabilne `unique_id` węzłów makroterenu. Nie zmienia punktów `Polygon2D`, przechodniości ani wymagań narzędzi urządzeń Wspólnej Linii.
- Jedynym źródłem statycznego świata jest `res://scenes/diving/UnderwaterMap.tscn`. Scenowe `Polygon2D` są authority makroterenu, a PNG, SDF, segmenty kolizji, okludery i chunki są pochodnymi.
- Mapa ma 11 520 × 6 480 jednostek świata i cztery regiony. Geometria, stable ID, rozmieszczenie gameplayowe, source-v4, `WorldDelta` i podpis mapy nie należą do zwykłej pracy wizualnej warsztatu.
- Aktywny `map_visual_chunks_v1.json` ma schema 1, siatkę wizualną 1024, gutter 2, jedną warstwę `environment_decoration` oraz 15 cropów. Wszystkie 15 PNG istnieje, a ich SHA-256 odpowiada manifestowi.
- Źródłowy `duzaMapaEnvironmentDecorationLayer-v3.png` nie istnieje. Manifest oznacza go `source_archived = true`; zachowane cropy są aktywnymi pochodnymi runtime, ale nie stanowią reprodukowalnego źródła.
- Odrzucona szeroka panorama R1 została usunięta: brak pięciu źródłowych PNG, manifestu R1, 24 cropów, generatora `build_dive_art_cells.py` i slotu `R1ArtCells` w baseline `a1c33d5`. Pozostałe lokalnie osierocone i ignorowane przez repozytorium pliki `.import` są metadanymi importu bez odpowiadających im PNG; nie są źródłami ani assetami baseline'u.
- `R1J7ArtCell.tscn` pozostaje odrębnym lokalnym prefabem landmarku J-7 i nie jest pozostałością szerokiej panoramy R1.
- R3-04 zachowuje istniejący authored pion landmarku. Cztery regiony korzystają obecnie z proceduralnych motywów Godota; nie istnieje zaakceptowany szeroki composition master R1-R4.

## Status assetów

Status techniczny i odbiór artystyczny są rozdzielone zgodnie z MAP-ARD-0003.

| Element | Stan techniczny | Odbiór artystyczny | Konsekwencja |
|---|---|---|---|
| Szeroka panorama ArtCells R1 rev. 2 | `REMOVED` | `REJECTED` | Nie jest baseline'em, źródłem ani kandydatem do ponownego eksportu. |
| 15 cropów `environment_decoration` | `PRESENT_VALID` | Nieoceniane ponownie w tym audycie | Runtime może je ładować; brak źródła blokuje bezpieczną przebudowę. |
| Pion landmarku R3-04 | `PRESENT` | Nieoceniany ponownie w tym audycie | Pozostaje niezależnym prefabem średniego planu. |
| Pełnomapowy layout guide v1 | `PRESENT_VALID` | Zaakceptowany jako czytelny guide, nie jako master artystyczny | Jest wersjonowaną referencją projektową, nie grafiką runtime ani authority mapy. |
| Szeroki composition master R1-R4 | `MISSING` | `UNREVIEWED` | Finalne ArtCells i szerokie chunki nie mogą powstać przed akceptacją mastera. |

## Pełnomapowy layout guide

- Kandydat `assets/diving/world/layout_guides/full_map/underwater_map_layout_guide_v1.png` pokazuje świat na płótnie 4320 × 2430, cztery regiony, 28 landmarków oraz siatkę kamery 11 × 11 przy widoku około 1066,67 × 600 jednostek świata.
- Skrajne kadry są dociskane do granicy świata i zachowują kontrolowany 20-procentowy overlap z poprzednią kolumną lub wierszem; wartość 1067 nie jest używana do kumulacyjnego pozycjonowania.
- `tools/build_dive_map_layout_guide.py` ma tryb `--check`, osadzony font bitmapowy i porównanie zdekodowanych pikseli. Generator, PNG i manifest tworzą jeden wersjonowany pakiet pochodny.
- Guide jest referencją do projektowania composition mastera. Nie ustanawia topologii, kolizji, chunków gameplayowych ani stylu finalnej grafiki.

## Potwierdzone luki

- `tools/build_dive_visual_chunks.py` nadal próbuje otworzyć brakujący master `environment_decoration`, nie obsługuje stanu archiwalnego i nie ma `--check`; nie jest obecnie reprodukowalnym builderem aktywnej warstwy.
- Brak zaakceptowanego composition mastera, pełnego zestawu źródeł szerokiej grafiki i kompletnego provenance nowej rewizji.
- Nie wykonano aktualnego pełnego traversal mapy ani profilu GPU/VRAM/draw calls dla przyszłych szerokich warstw.
- Nie ma pełnej mechanicznej tożsamości biomów sterowanej danymi; warsztat może rozwijać istniejące profile prezentacyjne, ale nie ustanawia nowej domeny gameplayowej.

## Ostatnia kontrola

Kontrola z 2026-08-16 potwierdziła brak produkcyjnych źródeł/cropów panoramy R1, jedną aktywną warstwę z 15 istniejącymi cropami i zgodność ich SHA-256 z manifestem. Layout guide przebudowano i potwierdzono przez `--check`; `underwater_map_scene_test.gd`, `macro_terrain_raster_test.gd` i `dive_layout_story_regression_test.gd` przeszły sekwencyjnie w Godot 4.7.1. Historyczne wyniki szerszych testów pozostają w globalnym `../../.ai/PROJECT_CONTEXT.md` i nie są ponownie deklarowane tutaj.

Na czystym izolowanym worktree selektywnego feature'u automatyczny pełnomapowy survey zakończył runner wynikiem `PASS 1/1` bez `ERROR` i `SCRIPT ERROR` w Godot 4.7.1, `Forward+`, 1280×720, `high`, bez persistence. Kamera przeszła poziomą serpentyną `C01-R01 -> C11-R11` z prędkością 600 u/s przez 121 punktów i wszystkie cztery regiony; stan sesji oraz podpis gameplayu pozostały niezmienione. Widoczna trasa trwa 212,133 s. Surowy AVI ma 6549 dekodowalnych klatek przy stałych 30 FPS, a przycięty H.264 MP4 ma 6364 klatki, 212,133 s i również stałe 30 FPS; pełne dekodowanie oraz automatyczna kontrola czarnych interwałów przeszły. Obejrzane kontaktówki całej mapy i ruchu oraz reprezentatywne pełne kadry R1-R4 potwierdzają kompletne pokrycie, brak pustych pól, nurka i HUD-u. Wynik dotyczy czystego selektywnego checkoutu feature'u; nie reinterpretowano nim niezależnych zmian bieżącego brudnego drzewa.
