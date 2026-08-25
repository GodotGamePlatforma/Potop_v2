# Warsztat mapy podwodnej

Ten katalog zawiera cały aktywny pakiet konkretnej mapy nurkowania. Projekt Godot i ogólne mechaniki znajdują się w katalogu nadrzędnym.

## Pierwsze 5 minut

1. Ustaw katalog roboczy na `D:\Dev\Game\Game\underwater_map_workbench`.
2. Przeczytaj kolejno `AGENTS.md`, `.ai/PROJECT_CONTEXT.md`, `.ai/DECISIONS.md` i ten plik. Migawka mówi, co naprawdę działa; decyzje mówią, jaki kontrakt ma obowiązywać.
3. Potwierdź `..\project.godot` i uruchom niedestrukcyjny `--check` z sekcji Komendy.
4. Zaklasyfikuj zmianę jako: semantyka/pozycja, topologia L05, grafika strukturalna, grafika nieblokująca albo dynamiczny gameplay.
5. Przed ImageGen sprawdź bramkę w `AGENTS.md`. Sam typ `L01/L02 texture_rect` nie wystarcza: produkcja zestawu miasta wymaga osobnych rekordów niezależnych elementów, zaakceptowanego układu proxy w rzeczywistym `UnderwaterMap.tscn` i odbioru jednej warstwy naraz. Nie otwiera to automatycznie produkcji landmarków ani pozostałych slotów.

## Jeden łańcuch prawdy

| Element | Znaczenie |
|---|---|
| `map_manifest.json` | Jedyne semantyczne authority pozycji, stable ID, relacji, rewizji, topologii i przypisań warstw. |
| `assets/topology/l05_ground_mask_source.json` | Edytowalny payload L05: jedno źródło pikselowego podziału `solid/open_water` i właściciela stałych komórek, wskazane ścieżką, SHA, canonical digestem oraz partition digestem przez manifest. Operacje struktur są lokalne względem ich originu; payload nie jest ilustracją. |
| Źródła grafiki | Grafika strukturalna jest przypisana do kanonicznego digestu L05, socketu i finalnego transformu; jawnie nieblokujące tło do rewizji prezentacji. Nigdy nie są źródłem fizyki. |
| `UnderwaterMap.tscn` | Jedyna scena używana przez runtime; byte-exact pochodna buildera, bez ręcznych poprawek. |
| `assets/generated/l05/` oraz kolizja runtime | Maski, prowadnica, pakiet prawdy, raster i segmenty fizyki są pochodnymi manifestu i payloadu L05; regenerowane, nie poprawiane ręcznie. |

„Jeden manifest i jedna scena” nie oznacza jednego pliku graficznego. Oznacza brak drugiego katalogu pozycji, alternatywnego manifestu, sceny-kandydata i równoległej wersji mapy. Wszystkie aktywne pliki źródłowe wskazuje ten sam manifest.

Łańcuch ma zawsze jeden kierunek:

`manifest z StructureRoot + payload L05 -> wspólny raster i rozłączne partycje colliderów -> proxy/grafika związana z digestem/socketem + niezmienione tło -> UnderwaterMap.tscn`

Pełnomapowa prowadnica jest deterministyczną pochodną payloadu używaną offline, nie domyślnie jedną teksturą runtime. Builder odczytuje pełne odwzorowanie: `world_units_per_pixel`, origin świata, kierunek osi, konwencję `pixel_center/pixel_edge` i regułę zaokrąglania; jednostki świata nie są automatycznie pikselami. Jeżeli obraz przekracza limit importu lub budżet tekstury, renderer używa deterministycznych socketów/chunków zachowujących dokładnie to odwzorowanie i overlap.

## Bieżąca zdolność pipeline'u

Aktywna mapa używa `topology.mode = l05_mask_v1`, payloadu `l05_owned_rect_ops_v2` i manifestu schema v5. Builder waliduje zawartość payloadu, surowy SHA, mapowanie piksel–świat, canonical digest geometrii i partition digest właścicieli, generuje pakiet prawdy oraz kompiluje jedną scenę. Oprócz istniejących elementów L01/L02 i materiału L05 obsługuje generyczne `structures.templates/instances`: jeden root instancji grupuje proceduralne proxy wnętrza L04, dokładną techniczną reprezentację jej bryły L05, lokalny `StaticCollision` i puste miejsca przyszłych obiektów dynamicznych/interaktywnych. Każdy root zachowuje `scale=Vector2.ONE`; L00 pozostaje proceduralznym kolorem wody. Dokładne rewizje, hashe, aktywne elementy i status odbioru są wyłącznie w `.ai/PROJECT_CONTEXT.md` oraz manifeście.

To jest nadal celowo wąski etap. Proceduralne proxy L04 pierwszej struktury nie otwiera jeszcze produkcyjnego importu bitmap L04 ani mechaniki windy i drzwi. Finalny artwork budynku wymaga osobnego, świeżego socketu, natywnego źródła 1:1 i odbioru faktycznego renderu proxy; nie wolno przemycić go do L01 ani L02.

## Grafika bez pixel artu

Widoczna grafika tej mapy jest realistycznym/rysunkowym 2D. Zwykłe bitmapy prezentacyjne dziedziczą projektowy globalny `Linear`, ale nigdy nie są powiększane, pomniejszane ani dopasowywane do socketu: `world_rect.size` musi być dokładnie równe `pixel_size`, a transform assetu pozostaje jednostkowy. Dotyczy to wszystkich warstw i obejmuje również zakaz jednolitego resize. Większy pas powstaje z grafiki wygenerowanej od razu w potrzebnej rozdzielczości albo z wielu różnych natywnych paneli ustawionych obok siebie.

Widoczny materiał kafelkowany może się powtarzać wyłącznie w natywnej gęstości jednego texela na jednostkę świata; nie wolno rozciągać pojedynczego kafla. Semantyczne maski L05 są technicznym wyjątkiem próbkowanym `nearest` zgodnie z własnym jawnym odwzorowaniem, aby nie rozmyć granicy kolidera; własny sampler widocznego materiału gruntu pozostaje liniowy. Zoom kamery i ruch paralaksy wpływają na projekcję ekranu, ale nie zmieniają authored skali bitmapy.

## Niezależne elementy zamiast spłaszczonej panoramy

Jednostką pracy jest najmniejszy element, który ma być osobno modyfikowalny. Zwykły wieżowiec otrzymuje własny przezroczysty PNG i osobny rekord manifestu. Mały nierozdzielny klaster może być jednym elementem, a bardzo duży budynek jednym elementem z kilku natywnych części. Nie wypiekaj wielu niezależnych budynków w jeden produkcyjny panel tylko dlatego, że ImageGen zwrócił je na wspólnym płótnie.

Builder grupuje zwykłe elementy organizacyjnie pod ich warstwą, ale wszystkie ID, pozycje, natywne rozmiary, źródła i SHA nadal należą do jednego `map_manifest.json`. Aktywna hierarchia tła to `VisualLayers/L01/Elements/<element_id>`, `VisualLayers/L02/Elements/<element_id>` oraz `VisualLayers/L05/Terrain/<element_id>`. Wchodnia instancja budynku ma osobny `StructureRoots/<structure_id>` z lokalnymi dziećmi `InteriorVisual`, `StructureVisual`, `StaticCollision`, `DynamicBodies` i `Interactives`; nie jest ręcznie rozrywana pomiędzy gałęzie sceny. Neutralny prototyp może nie mieć `landmark_id` ani lokalnych obiektów, a późniejszy budynek misji może jawnie dodać oba. Liczba instancji może się swobodnie zmieniać.

Głębię dalszego planu koryguj na rootcie warstwy przez `rgb_modulate`, zawsze z alfą `1.0`. Nie zmniejszaj przezroczystości całego L01/L02 i nie dodawaj globalnego filtra: alfa jest zarezerwowana dla wycięcia tła pojedynczego PNG. Bieżący L01 używa ciemniejszego `657786`, L02 pozostaje neutralne `ffffff`.

Przepis nowego pasa miasta:

1. W manifeście zaplanuj jedną warstwę oraz osobne prostokąty elementów w przestrzeni jej `Parallax2D`.
2. Wygeneruj tanie proxy tych prostokątów do dokładnej `UnderwaterMap.tscn` i obejrzyj pełną mapę oraz kadry docelowej kamery.
3. Dopiero po akceptacji skali, rytmu i linii bazowej wygeneruj jeden element w natywnej wielkości. Jeśli wymagany budynek jest większy niż natywne wyjście narzędzia, zbuduj go z natywnych części; nie wykonuj resize.
4. Zastąp jedno proxy, wykonaj build, `--check`, smoke i ponownie obejrzyj faktyczną scenę. Powtarzaj dla kolejnych elementów.
5. Najpierw zakończ i odbierz L01, dopiero potem L02. Na końcu oceń obie warstwy razem.

Bieżąca scena zawiera dwanaście niezależnych bitmap L01 i dziewiętnaście niezależnych bitmap L02, wszystkie wdrożone 1:1 w zaakceptowanych prostokątach proxy. Każdy budynek można teraz wymienić lub przesunąć osobno przez jego rekord manifestu. Końcowy odbiór artystyczny zintegrowanej kompozycji nadal należy wykonać w runtime użytkownika; nie wracaj do spłaszczonego pasa i nie poprawiaj wygenerowanej sceny ręcznie.

Jedynie L01/L02 używają polityki `nonblocking_backdrop_may_overlap_open_water`: mogą celowo wypełniać pusty widok nad otwartą wodą, w tym nad wschodnim zejściem parkingowym. To nigdy nie zmienia L05 ani nie oznacza budynku, ściany, podłogi, wejścia lub trasy. Nie stosuj tej polityki do L03-L10; ich grafika musi dalej szanować chronioną wodę zgodnie z `no_visual_blockage_in_protected_water`.

## Warstwy L00-L10

Stos zawiera dziesięć aktywnych slotów `L00-L09` i jeden wyłączony slot rezerwowy `L10`. To jedenaście stabilnych identyfikatorów, ale tylko dziesięć aktywnych warstw. Nie są numerami physics layers, liczbą assetów ani automatycznym z-orderem.

- różnicowa paralaksa należy dokładnie do `L01`, `L02`, `L08`, `L09`;
- `L00`, `L03`, `L04`, `L05`, `L06`, `L07` i rezerwowe `L10` są world-locked z jednostkową skalą;
- dokładną rolę, z-order i aktywność każdego slotu czytaj z manifestu, ale zmiana powyższej macierzy wymaga nowej decyzji i walidatora;
- L05 łączy się semantycznie z topologią, lecz `VisualLayers/L05` pozostaje tylko prezentacją;
- każdy landmark, wejście i element wyglądający jak stała ściana lub podłoga jest world-locked;
- paralaksa jest dozwolona tylko dla jawnie nieblokującego tła/foregroundu, które nie sugeruje alternatywnej przeszkody;
- `reduced_motion` usuwa ruch różnicowy bez usuwania treści lub zmiany kolejności.

## Przepisy zmian

### 1. Zmiana pozycji lub zawartości mapy

Najpierw zmień manifest i `revision_id`. Pozycja landmarku, urządzenia lub wejścia nigdy nie pochodzi ze screenshotu ani promptu. Regeneruj scenę i wszystkie pochodne zależne od zmienionego położenia; kartę socketu generuj dopiero dla typu jawnie obsługiwanego przez bieżący builder.

### 2. Zmiana kolidera L05

Edytuj wyłącznie `assets/topology/l05_ground_mask_source.json`. `solid_rect` dodaje grunt, `open_rect` wycina wodę, a operacje są wykonywane od góry do dołu, więc późniejsza operacja wygrywa. Przesunięcie, poszerzenie, zwężenie, usunięcie albo dodanie przejścia jest zwykłą zmianą `rect_px`; nie wymaga stałej liczby tuneli.

Jeżeli zmienia się geometria albo przypisanie jej właściciela, najpierw podnieś `revision_id` i `topology_revision` w manifeście, potem uruchom `--refresh-l05-source`. Ta komenda atomowo synchronizuje surowy SHA payloadu, canonical digest, partition digest, wiązania struktur i digest aktywnego assetu L05; celowo nie zgaduje nazw rewizji. Następnie wykonaj build, `--check` i smoke. Builder odtwarza `solid_mask.png`, `open_water_mask.png`, `boundary_mask.png`, `full_map_guide.png` i `truth_package.json`; runtime zachowuje jeden raster nawigacji, lecz tworzy globalne segmenty wyłącznie dla właściciela `world`, a collider instancji wyłącznie pod jej rootem. Nie poprawiaj żadnej z tych pochodnych ręcznie.

Wszystkie grafiki strukturalne starego digestu stają się nieaktualne. Jawnie nieblokujące L01 i L02 wymagają ponownej kontroli kompozytu, ale nie definiują kolizji. Po kontroli technicznej użytkownik ręcznie przepływa J-7 -> Archiwum -> R-3 -> C-4; nie dodawaj blokującego BFS.

### 3. Landmark lub grafika strukturalna

Użyj jednego świeżego pakietu prawdy opisanego w `AGENTS.md`: pełna prowadnica, dokładny socket w pikselach i świecie, finalny transform, trzy maski, pełny rekord struktury, warunkowo jej landmark, sąsiedzi, polityka warstwy, zaakceptowany brief/master i referencje oznaczone `STYLE_ONLY`. ImageGen tworzy propozycję detalu w tym sockecie. Wynik musi przejść obie kontrole: brak fałszywej ściany w wodzie oraz brak niewidzialnego kolidera wyglądającego jak otwarte przejście.

### 4. Poprawka wyglądu bez zmiany topologii

L01, L02 i materiał tekstury gruntu w `assets/visual/` są źródłami prezentacji. Edytuj najmniejszy niezależny element, zachowując jego world rect, skalę i rolę; zaktualizuj SHA rekordu oraz `presentation_revision`, nie `topology_revision`. `VisualLayers/L05` nie jest koliderem: shader nakłada materiał wyłącznie tam, gdzie wygenerowana maska mówi `solid`, dlatego obraz materiału nie może zawierać własnych tuneli, drzwi ani ścian. Ponownie sprawdź maskę oraz faktyczny render wygenerowanej `UnderwaterMap.tscn`; sam pełny kompozyt lub contact sheet nie wystarcza.

### 5. Dynamiczna brama lub przeszkoda

Nie wypiekaj jej stanu do statycznego tła. Manifest deklaruje obiekt oraz dostępne konfiguracje, właściwy system runtime/persistence jest właścicielem bieżącego stanu, a grafika jednoznacznie pokazuje wariant otwarty i zamknięty. Sprawdź oba warianty i przejścia między nimi w runtime.

## Kampania bez zamrażania liczności mapy

Liczba regionów, landmarków, tuneli, shortcutów i assetów wynika z bieżących tablic manifestu i może się zmieniać. Aktywna mapa zachowuje jednak semantyczną kolejność `junction_j7 -> archive_terminal -> r3_diagnostic_panel -> r3_generator -> c4_switchboard -> c4_splitter_mount`. Pozycje i przypisania tych urządzeń należą do manifestu; dawne fizyczne ID i współrzędne nie są authority.

Builder i smoke sprawdzają strukturę, unikalność i referencje, ale nie certyfikują przestrzennej osiągalności. Po zmianie L05 rozstrzyga ją ręczne przepłynięcie użytkownika.

## Pliki

- `map_manifest.json` — semantyczne authority;
- `assets/topology/l05_ground_mask_source.json` — jedyne ręcznie edytowalne źródło statycznego `solid/open_water`;
- rekordy `L01/Elements` w `map_manifest.json` oraz `assets/visual/l01_city_01.png..l01_city_12.png` — dwanaście aktywnych, niezależnych budynków dalszego planu;
- rekordy `L02/Elements` w `map_manifest.json` oraz `assets/visual/l02_city_01.png..l02_city_19.png` — dziewiętnaście aktywnych, niezależnych budynków bliższego planu; dawna bitmapa `l02_near_city.png` nie jest aktywnym assetem;
- `assets/visual/l05_ground_material.png` — aktualny materiał wizualny gruntu, maskowany L05;
- `assets/visual/imagegen_provenance.json` — techniczny zapis narzędzia, promptów, źródeł i operacji; `authority = false`;
- `assets/generated/l05/` — deterministyczne maski i pakiet prawdy; nie edytuj ręcznie;
- `UnderwaterMap.tscn` — wygenerowana scena runtime;
- `tools/build_underwater_map.py` — build i niedestrukcyjny check;
- `tests/underwater_map_smoke_test.gd` — techniczny smoke pakietu;
- `tests/underwater_map_proxy_capture_test.gd` — natywny render dokładnej wygenerowanej sceny: pełny widok i sześć kadrów gameplayowych bez HUD-u i nurka;
- `runtime/` — kompilator manifestu i cienki host mapy;
- `assets/` — zaakceptowane źródła i lokalne assety; źródła topologii i prezentacji konkretnej mapy wskazuje manifest, a ogólne assety gameplayowe pozostają referencjami właściwych scen/zasobów;
- `AGENTS.md`, `.ai/PROJECT_CONTEXT.md`, `.ai/DECISIONS.md` — proces, bieżąca migawka i trwałe decyzje.

## Komendy

Z `D:\Dev\Game\Game\underwater_map_workbench`:

```powershell
Test-Path ..\project.godot
git -C .. rev-parse --show-toplevel
python .\tools\build_underwater_map.py --check
python .\tools\build_underwater_map.py --refresh-l05-source
python .\tools\build_underwater_map.py --build
python .\tools\build_underwater_map.py --check
..\tests\run_all_tests.ps1 -Target underwater_map_workbench/tests/underwater_map_smoke_test.gd
..\tests\run_all_tests.ps1 -NativeTarget underwater_map_workbench/tests/underwater_map_proxy_capture_test.gd
git -C .. diff --name-only
git -C .. status --short
```

`--check` nie może zapisywać. `--refresh-l05-source` uruchamiaj tylko po zmianie payloadu L05 i ręcznym podbiciu właściwych rewizji; dla aktualnego payloadu jest byte-no-op. Po zmianie topologii obowiązuje kolejność refresh -> build -> check -> smoke. Po samej zmianie manifestu lub grafiki pomiń refresh i wykonaj build -> check -> smoke -> native proxy capture. Capture zapisuje artefakty pod `user://test_underwater_map_proxy_capture`; trzeba otworzyć pełny widok i kadry, nie wystarcza sam `PASS`. Runner wymaga zamknięcia Godota korzystającego z tego samego checkoutu albo uruchomienia z osobnej pełnej kopii projektu. Dodatkowe testy root dobieraj proporcjonalnie do integracji. `ERROR` lub `SCRIPT ERROR` oznacza porażkę także przy kodzie wyjścia 0.

Nie twórz plików `candidate`, `final`, drugiej sceny ani drugiego manifestu. `schema_version` jest wersją formatu wewnątrz tego samego pliku, nie nazwą wariantu. Odrzucone próby i pliki tymczasowe nie należą do aktywnego pakietu.

## Referencje techniczne

- [Godot `CollisionPolygon2D`](https://docs.godotengine.org/en/stable/classes/class_collisionpolygon2d.html) i [Godot `BitMap`](https://docs.godotengine.org/en/stable/classes/class_bitmap.html) opisują reprezentację kolizji oraz wyprowadzanie poligonów z maski;
- [Godot `Image`](https://docs.godotengine.org/en/stable/classes/class_image.html) i [import obrazów](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html) określają limity i sposób przygotowania tekstur;
- [Godot `Parallax2D`](https://docs.godotengine.org/en/stable/classes/class_parallax2d.html) oraz [Godot `CanvasItem`](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html) rozdzielają ruch i kolejność rysowania od fizyki;
- [Godot: światła i cienie 2D](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html) opisuje okludery i SDF;
- [OpenAI Image Generation prompting guide](https://developers.openai.com/cookbook/examples/multimodal/image-gen-models-prompting-guide) zaleca jawnie wskazywać rolę każdego wejścia, oddzielać elementy zmieniane od zachowywanych i iterować małymi edycjami.

Trwałe reguły projektu pozostają w `.ai/DECISIONS.md`. Żadna zewnętrzna referencja nie przejmuje pozycji ani topologii mapy.
