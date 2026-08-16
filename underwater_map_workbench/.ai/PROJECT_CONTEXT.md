# Kontekst warsztatu mapy podwodnej

Rola tego pliku: krótka, datowana migawka produkcji grafiki mapy, potwierdzonych braków, pułapek i ostatniego odbioru. Nie jest instrukcją pracy ani roadmapą. Globalny runtime i przekrojowe luki należą do `../../.ai/PROJECT_CONTEXT.md`, reguły gry do `../../docs/OgolnyZarys.txt`, a techniczna authority do `../../docs/Ostatni_Pomost_architektura_Godot.txt`.

## Stan na 2026-08-16

- Zweryfikowany baseline historii: `a1c33d5` (`Remove rejected R1 ArtCell background`). Bieżące drzewo dodaje wersjonowany warsztat, pełnomapowy layout guide z generatorem oraz stabilne `unique_id` węzłów makroterenu. Ponadto 16 z 28 środków landmarków przeniesiono z terenu zablokowanego albo zbyt ciasnej wody do głównej statycznej składowej C35; wszystkie 28 środków spełnia teraz ten kontrakt. Powiększono wyłącznie bounds R3-02 i R4-01, aby zachować powiązane cele z zapasem 8 jednostek. Nie zmieniono punktów `Polygon2D`, entry/exit, obiektów gameplayowych, stable ID ani wymagań narzędzi urządzeń Wspólnej Linii. Zatwierdzony clean break zmienia podpis gameplayowy mapy i celowo odrzuca kampanie zapisane ze starym podpisem.
- Jedynym źródłem statycznego świata jest `res://scenes/diving/UnderwaterMap.tscn`. Scenowe `Polygon2D` są authority makroterenu, a PNG, SDF, segmenty kolizji, okludery i chunki są pochodnymi.
- Mapa ma 11 520 × 6 480 jednostek świata i cztery regiony. Geometria, stable ID, rozmieszczenie gameplayowe, source-v4, `WorldDelta` i podpis mapy nie należą do zwykłej pracy wizualnej warsztatu.
- Aktywny `map_visual_chunks_v1.json` ma schema 1, siatkę wizualną 1024, gutter 2, jedną warstwę `environment_decoration` oraz 15 cropów. Wszystkie 15 PNG istnieje, a ich SHA-256 odpowiada manifestowi.
- Źródłowy `duzaMapaEnvironmentDecorationLayer-v3.png` nie istnieje. Manifest oznacza go `source_archived = true`; zachowane cropy są aktywnymi pochodnymi runtime, ale nie stanowią reprodukowalnego źródła.
- Odrzucona szeroka panorama R1 została usunięta: brak pięciu źródłowych PNG, manifestu R1, 24 cropów, generatora `build_dive_art_cells.py` i slotu `R1ArtCells` w baseline `a1c33d5`. Pozostałe lokalnie osierocone i ignorowane przez repozytorium pliki `.import` są metadanymi importu bez odpowiadających im PNG; nie są źródłami ani assetami baseline'u.
- `R1J7ArtCell.tscn` pozostaje odrębnym, bezkolizyjnym prefabem landmarku J-7 i zachowuje wyłącznie przycinany przez SDF `AuthoredTerrainSkin`. Nie ma już `FarPlate`, `EnvironmentPlate` ani zależności od usuniętego `r1_j7_drowned_city_v1.png`.
- Odrzucony authored pion R3-04 został wycofany. Landmark nie ma lokalnej `Visual Scene` i pozostaje na wspólnym proceduralnym tle oraz terenie regionu; nie istnieje zaakceptowany szeroki composition master R1-R4.
- `res://assets/diving/world/layout_guides/style_references/biomes_v2_layered/` zawiera cztery spłaszczone guide'y kompozycyjne R1-R4 i manifest provenance. Pokazują język planów, ale nie są runtime, osobnymi warstwami alfa ani zaakceptowanym composition masterem.
- `res://assets/diving/world/layout_guides/style_references/biomes_v3_six_layer/` zawiera 24 współosiowe wynikowe PNG sRGBA, po sześć dla R1-R4, cztery pochodne preview, 21 wersjonowanych surowych wyników ImageGen oraz manifest pełnych promptów i operacji. `L00` jest jednolitym kolorem biomu, a `L01-L05` są niezależnymi warstwami alfa. Użytkownik zaakceptował zestaw jako wzorzec stylu i konstrukcji sześciu warstw; pozostaje on referencją prezentacyjną, nie runtime, topologią ani composition masterem. Lokalne jasne krawędzie i refleksy w R1, R3 i R4 wymagają ponownej oceny dopiero po integracji ze wspólnym oświetleniem Godota.
- `res://assets/diving/world/layout_guides/style_references/landmarks_v1_six_layer/` zawiera komplet referencyjny wszystkich 28 landmarków: 28 źródłowych arkuszy ImageGen, 168 współosiowych PNG alfa `L00-L05`, 28 pochodnych preview, cztery regionalne rekordy pełnego provenance i manifest nadrzędny. Pakiet jest technicznie poprawny, pozostaje niepodłączony do runtime i oczekuje na odbiór artystyczny użytkownika.
- `res://assets/diving/world/layout_guides/composition_masters/biomes_l01_v1/` zawiera jeden współosiowy master-preview całej mapy 4320 × 2430, cztery regionalne cropy R1-R4 i pełny manifest provenance. Pakiet obejmuje wyłącznie transparentną warstwę `L01 ultra_far_silhouettes`, ma `TECHNICAL_PASS`, nie jest podłączony do runtime ani zaakceptowanym masterem produkcyjnym; odbiór użytkownika pozostaje `PENDING_USER_REVIEW`.
- `res://assets/diving/world/layout_guides/style_references/r1_rooftops_l01_l04_supplement_v1/` zawiera dodatkowy, współosiowy zestaw R1: cztery źródła chroma-key, cztery niezależne PNG alfa `L01-L04`, złożony preview oraz manifest pełnych promptów i operacji. Pakiet uzupełnia zaakceptowany wzorzec V3 bez podmiany jego plików; pozostaje referencją poza runtime i composition masterem oraz oczekuje na odbiór artystyczny.

## Status assetów

Status techniczny i odbiór artystyczny są rozdzielone zgodnie z MAP-ARD-0003.

| Element | Stan techniczny | Odbiór artystyczny | Konsekwencja |
|---|---|---|---|
| Szeroka panorama ArtCells R1 rev. 2 | `REMOVED` | `REJECTED` | Nie jest baseline'em, źródłem ani kandydatem do ponownego eksportu. |
| 15 cropów `environment_decoration` | `PRESENT_VALID` | Nieoceniane ponownie w tym audycie | Runtime może je ładować; brak źródła blokuje bezpieczną przebudowę. |
| Pion landmarku R3-04 | `REMOVED` | `REJECTED` | Stary prefab i jego dwa lokalne obrazy nie są już referencjonowane; R3-04 nie ma lokalnej `Visual Scene` i pozostaje na wspólnym tle oraz terenie regionu. |
| Pełnomapowy layout guide v1 | `PRESENT_VALID` | Zaakceptowany jako czytelny guide, nie jako master artystyczny | Jest wersjonowaną referencją projektową, nie grafiką runtime ani authority mapy. |
| Warstwowe referencje biomów R1-R4 v2 | `PRESENT_VALID` | `PENDING_USER_REVIEW` | Cztery neutralne PNG RGB i manifest operacji; R1 zachowuje górny rytm dachów, a R2-R4 otwartą bezdenną toń. |
| Sześciowarstwowe referencje biomów R1-R4 v3 | `PRESENT_VALID` | `USER_ACCEPTED_AS_STYLE_REFERENCE` | 24 wyniki `L00-L05`, cztery preview, 21 wersjonowanych rawów i manifest provenance; akceptacja dotyczy języka 2D i konstrukcji warstw, nie composition mastera ani runtime. Jasne krawędzie/refleksy R1, R3 i R4 pozostają caveatem integracji z oświetleniem. |
| Sześciowarstwowe referencje 28 landmarków v1 | `PRESENT_VALID` | `PENDING_USER_REVIEW` | 28 źródeł, 168 warstw alfa, 28 preview i pełne provenance; pakiet jest źródłem/referencją i nie ma jeszcze prefabów `map_visuals` ani przypisań `Visual Scene`. |
| Szeroki composition master-preview L01 R1-R4 v1 | `PRESENT_VALID_CANDIDATE` | `PENDING_USER_REVIEW` | Jeden full-map master, cztery bezskalowe cropy i manifest są gotowe do oceny; finalne ArtCells, chunki i warstwy L02-L05 nie mogą powstać przed akceptacją. |
| Dodatkowe warstwy R1 L01-L04 v1 | `PRESENT_VALID` | `PENDING_USER_REVIEW` | Cztery współosiowe warstwy sRGBA `1672 × 941` i preview uzupełniają słownik V3; nie zastępują go, nie są production masterem i nie są podłączone do runtime. |

## Pełnomapowy layout guide

- Kandydat `assets/diving/world/layout_guides/full_map/underwater_map_layout_guide_v1.png` pokazuje świat na płótnie 4320 × 2430, cztery regiony, 28 landmarków oraz siatkę kamery 11 × 11 przy widoku około 1066,67 × 600 jednostek świata.
- Skrajne kadry są dociskane do granicy świata i zachowują kontrolowany 20-procentowy overlap z poprzednią kolumną lub wierszem; wartość 1067 nie jest używana do kumulacyjnego pozycjonowania.
- `tools/build_dive_map_layout_guide.py` ma tryb `--check`, osadzony font bitmapowy i porównanie zdekodowanych pikseli. Generator, PNG i manifest tworzą jeden wersjonowany pakiet pochodny.
- Guide jest referencją do projektowania composition mastera. Nie ustanawia topologii, kolizji, chunków gameplayowych ani stylu finalnej grafiki.
- Wariant A naprawia wcześniejsze odwrócenie kolorów: surowy raster zachowuje `0 = open_water`, guide pokazuje teraz otwartą wodę jasno, a teren ciemno. Po przebudowie guide odpowiada bieżącej scenie, wszystkie 28 punktów centrów ma wartość rastra 0 i leży na jasnej, otwartej wodzie; rekomendacja wizualna Codexa jest pozytywna.

## Potwierdzone luki

- `tools/build_dive_visual_chunks.py` nadal próbuje otworzyć brakujący master `environment_decoration`, nie obsługuje stanu archiwalnego i nie ma `--check`; nie jest obecnie reprodukowalnym builderem aktywnej warstwy.
- Brak zaakceptowanego composition mastera i pełnego zestawu produkcyjnych źródeł szerokiej grafiki. Kandydat `biomes_l01_v1` zamyka wyłącznie etap niskoczęstotliwościowego preview L01; do czasu jawnej akceptacji nie jest masterem produkcyjnym i nie zezwala na ArtCells, chunki ani warstwy L02-L05.
- Użytkownik 2026-08-16 jawnie potwierdził prawa albo zgodną licencję pozwalającą umieścić i opublikować w repozytorium siedem wejściowych assetów v2 oraz ich pochodne. Manifest v2 i package composition zapisują zakres potwierdzenia bez przypisywania niewskazanej nazwy licencji; blokada publikacji została zdjęta.
- Relokacja zmienia automatycznie wyprowadzone punkty sześciu tras skrótów: SC-02, SC-03, SC-04, SC-05, SC-07 i SC-08; scenowe pozycje ich `ShortcutGate` pozostały fizycznym authority i bez zmian. Survey potwierdził czytelny obraz runtime, ale nie zastępuje sterowanego wejścia, kolizji ani rzeczywistego przejścia przez bramy. Stan to `PLAYTEST_PENDING`, bez blokera brakującego assetu.
- Nie wykonano profilu GPU/VRAM/draw calls dla przyszłych szerokich warstw, które pozostają poza runtime.
- Nie ma pełnej mechanicznej tożsamości biomów sterowanej danymi; warsztat może rozwijać istniejące profile prezentacyjne, ale nie ustanawia nowej domeny gameplayowej.
- Pakiet warstw landmarków nie ma jeszcze kolizyjnie pustych prefabów w `res://scenes/diving/map_visuals/` ani przypisań do istniejących pól `Visual Scene`. To osobny, chroniony etap runtime; same PNG nie mogą przejąć authority topologii, kolizji ani stable ID.

## Ostatnia kontrola

Kontrola bieżącego drzewa z 2026-08-16 zakończyła się czystym importem i testami Godota 4.7.1 bez `ERROR` ani `SCRIPT ERROR`. Domyślny runner przeszedł `18/18`; osobno przeszły `underwater_map_scene_test.gd`, `continuous_map_collision_test.gd`, `dive_navigation_snapshot_test.gd`, `dive_layout_story_regression_test.gd` oraz `dive_visual_chunk_streaming_test.gd`. Test mapy obejmuje teraz wszystkie 28 centrów w C35 i głównej składowej, region containment, zapas 8 jednostek dla powiązanych celów, nearest-landmark, usunięcie płyty J-7, brak lokalnej sceny R3-04 oraz odrzucenie starego podpisu bez mutacji `WorldDelta`. Historyczny timeout testu układu nie odtwarza się; pełny scenariusz zakończył się `PASS` po około 6 min 15 s.

Generator guide'a oraz `--check` przeszły z SHA-256 PNG `53442cb22aad7d407ebe30b50b19aee3af232367795fb1f31d9de4da5a23f999`. Audyt dziewięciu manifestów i 287 PNG potwierdził dekodowanie, wymiary, tryby, hashe, 271 referencji, 21 wersjonowanych rawów v3, pikselowo identyczne rekompozycje i cropy oraz rozdzielenie surowego hasha RGBA od hasha generatora. Odstępstwa docelowego udziału otwartej wody R1, R2 i R4 są jawnie oznaczone jako advisory, a nie ukryte pod `technical=pass`.

Pełnomapowy `VISUAL_SURVEY` bieżącego drzewa przeszedł `PASS 1/1` w Godot 4.7.1, `Forward+`, 1280×720, `high`, bez persistence. Kamera przeszła serpentyną `C01-R01 -> C11-R11` przy 600 u/s przez 121 punktów i wszystkie cztery regiony; stan sesji oraz podpis gameplayu `9e771c91d6a5b9a9cb303e59bdf48e804c432bd72e651c8a38c3d53d5709b673` pozostały niezmienione. H.264 MP4 ma 6364 klatki, 212,133 s i stałe 30 FPS. Kontaktówka, pełne kadry R1-R4 i arkusz czasowy filmu potwierdzają kompletne pokrycie bez pustych pól, brak brakujących tekstur, szwów, pop-inu, nurka i HUD-u; rekomendacja Codexa to `CODEX_VISUAL_RECOMMENDATION=PASS`. Survey nie jest playtestem, dlatego sterowanie, kolizje i rzeczywiste przejście przez sześć skrótów o przeliczonych trasach pozostają `PLAYTEST_PENDING`.

Pakiety referencyjne pozostają poza runtime. V3 ma komplet 21 surowych wyników ImageGen, landmarki zachowują 28 source sheets i 168 warstw, a composition preview L01 zachowuje jeden master oraz cztery bezskalowe cropy. Odbiór artystyczny landmarków, suplementu R1 i kandydata L01 pozostaje `PENDING_USER_REVIEW`; potwierdzona podstawa praw pozwala opublikować siedem wejściowych assetów v2 oraz ich pochodne w tym repozytorium.
