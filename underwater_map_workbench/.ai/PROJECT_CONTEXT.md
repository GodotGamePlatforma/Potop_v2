# Kontekst warsztatu mapy podwodnej

Rola tego pliku: krótka, datowana migawka produkcji grafiki mapy, potwierdzonych braków, pułapek i ostatniego odbioru. Nie jest instrukcją pracy ani roadmapą. Globalny runtime i przekrojowe luki należą do `../../.ai/PROJECT_CONTEXT.md`, reguły gry do `../../docs/OgolnyZarys.txt`, a techniczna authority do `../../docs/Ostatni_Pomost_architektura_Godot.txt`.

## Stan na 2026-08-16

- Zweryfikowany baseline Git: `a1c33d5` (`Remove rejected R1 ArtCell background`). Aktywny manifest i produkcyjne cropy są czyste względem tego commita. Bieżący worktree zawiera osobne, niezacommitowane zmiany dokumentacji, nowy layout guide oraz zmianę `UnderwaterMap.tscn`; scena jest poza zakresem tej synchronizacji i nie została uznana za potwierdzony stan runtime.
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
| Pełnomapowy layout guide v1 | `CANDIDATE_UNTRACKED` | Zaakceptowany wcześniej jako czytelny guide, nie jako master artystyczny | Nie jest jeszcze częścią czystego checkoutu ani grafiką runtime. |
| Szeroki composition master R1-R4 | `MISSING` | `UNREVIEWED` | Finalne ArtCells i szerokie chunki nie mogą powstać przed akceptacją mastera. |

## Pełnomapowy layout guide

- Kandydat `assets/diving/world/layout_guides/full_map/underwater_map_layout_guide_v1.png` pokazuje świat na płótnie 4320 × 2430, cztery regiony, 28 landmarków oraz siatkę kamery 11 × 11 przy widoku około 1066,67 × 600 jednostek świata.
- Skrajne kadry są dociskane do granicy świata i zachowują kontrolowany 20-procentowy overlap z poprzednią kolumną lub wierszem; wartość 1067 nie jest używana do kumulacyjnego pozycjonowania.
- `tools/build_dive_map_layout_guide.py` ma tryb `--check`, osadzony font bitmapowy i porównanie zdekodowanych pikseli. Generator, PNG i manifest są obecnie zmianami worktree, nie zatwierdzonym baseline'em Git.
- Guide jest referencją do projektowania composition mastera. Nie ustanawia topologii, kolizji, chunków gameplayowych ani stylu finalnej grafiki.

## Potwierdzone luki

- `tools/build_dive_visual_chunks.py` nadal próbuje otworzyć brakujący master `environment_decoration`, nie obsługuje stanu archiwalnego i nie ma `--check`; nie jest obecnie reprodukowalnym builderem aktywnej warstwy.
- Brak zaakceptowanego composition mastera, pełnego zestawu źródeł szerokiej grafiki i kompletnego provenance nowej rewizji.
- Nie wykonano aktualnego pełnego traversal mapy ani profilu GPU/VRAM/draw calls dla przyszłych szerokich warstw.
- Nie ma pełnej mechanicznej tożsamości biomów sterowanej danymi; warsztat może rozwijać istniejące profile prezentacyjne, ale nie ustanawia nowej domeny gameplayowej.

## Ostatnia kontrola

Audyt dokumentacyjny i statyczny z 2026-08-16 potwierdził commit `a1c33d5`, brak produkcyjnych źródeł/cropów panoramy R1, jedną aktywną warstwę z 15 istniejącymi cropami i zgodność ich SHA-256 z manifestem. W ramach tej synchronizacji dokumentacji nie uruchamiano Godota, testów ani generatorów. Historyczne wyniki runtime pozostają w globalnym `../../.ai/PROJECT_CONTEXT.md` i nie są ponownie deklarowane tutaj.
