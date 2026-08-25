# Warsztat mapy podwodnej

Ten katalog zawiera cały aktywny pakiet konkretnej mapy nurkowania. Projekt Godot i ogólne mechaniki znajdują się w katalogu nadrzędnym.

## Pierwsze 5 minut

1. Ustaw katalog roboczy na `D:\Dev\Game\Game\underwater_map_workbench`.
2. Przeczytaj kolejno `AGENTS.md`, `.ai/PROJECT_CONTEXT.md`, `.ai/DECISIONS.md` i ten plik. Migawka mówi, co naprawdę działa; decyzje mówią, jaki kontrakt ma obowiązywać.
3. Potwierdź `..\project.godot` i uruchom niedestrukcyjny `--check` z sekcji Komendy.
4. Zaklasyfikuj zmianę jako: semantyka/pozycja, topologia L05, grafika strukturalna, grafika nieblokująca albo dynamiczny gameplay.
5. Przed ImageGen sprawdź bramkę w `AGENTS.md`. Brak payloadu, masek, świeżej karty socketu lub renderera oznacza STOP dla produkcyjnej grafiki strukturalnej.

## Jeden łańcuch prawdy

| Element | Znaczenie |
|---|---|
| `map_manifest.json` | Jedyne semantyczne authority pozycji, stable ID, relacji, rewizji, topologii i przypisań warstw. |
| Payload L05 | `[DOCELOWE]` Jedno źródło pikselowego podziału `solid/open_water`, wskazane ścieżką i SHA przez manifest. |
| Źródła grafiki | Grafika strukturalna jest przypisana do kanonicznego digestu L05, socketu i finalnego transformu; jawnie nieblokujące tło do rewizji prezentacji. Nigdy nie są źródłem fizyki. |
| `UnderwaterMap.tscn` | Jedyna scena używana przez runtime; byte-exact pochodna buildera, bez ręcznych poprawek. |
| Kolizja, nawigacja, maski, SDF/okludery, prowadnice i socket cards | Pochodne manifestu i payloadu L05; regenerowane, nie poprawiane ręcznie. |

„Jeden manifest i jedna scena” nie oznacza jednego pliku graficznego. Oznacza brak drugiego katalogu pozycji, alternatywnego manifestu, sceny-kandydata i równoległej wersji mapy. Wszystkie aktywne pliki źródłowe wskazuje ten sam manifest.

Łańcuch ma zawsze jeden kierunek:

`manifest + payload L05 -> kolider i prowadnice -> grafika strukturalna związana z digestem/socketem + tło związane z rewizją prezentacji -> UnderwaterMap.tscn`

Pełnomapowa prowadnica jest deterministyczną pochodną payloadu używaną offline, nie domyślnie jedną teksturą runtime. Builder odczytuje pełne odwzorowanie: `world_units_per_pixel`, origin świata, kierunek osi, konwencję `pixel_center/pixel_edge` i regułę zaokrąglania; jednostki świata nie są automatycznie pikselami. Jeżeli obraz przekracza limit importu lub budżet tekstury, renderer używa deterministycznych socketów/chunków zachowujących dokładnie to odwzorowanie i overlap.

## Stan a kontrakt docelowy

Aktualne możliwości i luki są zapisane tylko w `.ai/PROJECT_CONTEXT.md`. Jeżeli migawka nadal podaje `topology.mode = open_world`, `collision_source.format = none`, brak pakietu prowadnic albo wymagane puste `visual.assets`, pipeline jest foundationem, a nie gotowym authoringiem grafiki 1:1. Wtedy właściwym następnym zadaniem jest wybranie produkcyjnego formatu payloadu w schema, dodanie jego walidacji i deterministycznego generatora pakietu prawdy do buildera oraz test z rzeczywistym payloadem — nie generowanie finalnych ścian, budynków lub landmarków. Obecnie nie istnieje zatwierdzona komenda authoringu L05.

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

Najpierw zmień manifest i `revision_id`. Pozycja landmarku, urządzenia lub wejścia nigdy nie pochodzi ze screenshotu ani promptu. Regeneruj scenę, odpowiednie karty socketów oraz wszystkie grafiki zależne od zmienionego położenia.

### 2. Zmiana kolidera L05

Po wdrożeniu adaptera zmień źródłowy payload i jego rekord w manifeście. Gdy zmieniła się zdekodowana geometria lub odwzorowanie, podnieś `topology_revision`, przelicz surowy SHA i kanoniczny digest oraz wygeneruj od nowa fizykę, nawigację, maski, pas graniczny, prowadnicę i sockety. Wszystkie grafiki strukturalne starego digestu są nieaktualne; nieblokujące tło przechodzi ponowną kontrolę kompozytu. Ponowny zapis identycznej geometrii zmienia tylko surowy SHA, nie podpis gameplayu. Po build/check i kontrolach technicznych użytkownik ręcznie przepływa J-7 -> Archiwum -> R-3 -> C-4; nie dodawaj blokującego BFS.

### 3. Landmark lub grafika strukturalna

Użyj jednego świeżego pakietu prawdy opisanego w `AGENTS.md`: pełna prowadnica, dokładny socket w pikselach i świecie, finalny transform, trzy maski, pełny rekord landmarku, sąsiedzi, polityka warstwy, zaakceptowany brief/master i referencje oznaczone `STYLE_ONLY`. ImageGen tworzy propozycję detalu w tym sockecie. Wynik musi przejść obie kontrole: brak fałszywej ściany w wodzie oraz brak niewidzialnego kolidera wyglądającego jak otwarte przejście.

### 4. Poprawka wyglądu bez zmiany topologii

Edytuj najmniejszy potrzebny obszar aktualnego zaakceptowanego źródła, zachowując socket, skalę i sąsiadów. Podnieś `presentation_revision`, nie podpis gameplayu. Ponownie sprawdź maski, pełny kompozyt i kadry gameplayowe.

### 5. Dynamiczna brama lub przeszkoda

Nie wypiekaj jej stanu do statycznego tła. Manifest deklaruje obiekt oraz dostępne konfiguracje, właściwy system runtime/persistence jest właścicielem bieżącego stanu, a grafika jednoznacznie pokazuje wariant otwarty i zamknięty. Sprawdź oba warianty i przejścia między nimi w runtime.

## Kampania bez zamrażania liczności mapy

Liczba regionów, landmarków, tuneli, shortcutów i assetów wynika z bieżących tablic manifestu i może się zmieniać. Aktywna mapa zachowuje jednak semantyczną kolejność `junction_j7 -> archive_terminal -> r3_diagnostic_panel -> r3_generator -> c4_switchboard -> c4_splitter_mount`. Pozycje i przypisania tych urządzeń należą do manifestu; dawne fizyczne ID i współrzędne nie są authority.

Builder i smoke sprawdzają strukturę, unikalność i referencje, ale nie certyfikują przestrzennej osiągalności. Po zmianie L05 rozstrzyga ją ręczne przepłynięcie użytkownika.

## Pliki

- `map_manifest.json` — semantyczne authority;
- `UnderwaterMap.tscn` — wygenerowana scena runtime;
- `tools/build_underwater_map.py` — build i niedestrukcyjny check;
- `tests/underwater_map_smoke_test.gd` — techniczny smoke pakietu;
- `runtime/` — kompilator manifestu i cienki host mapy;
- `assets/` — zaakceptowane źródła i lokalne assety; źródła topologii i prezentacji konkretnej mapy wskazuje manifest, a ogólne assety gameplayowe pozostają referencjami właściwych scen/zasobów;
- `AGENTS.md`, `.ai/PROJECT_CONTEXT.md`, `.ai/DECISIONS.md` — proces, bieżąca migawka i trwałe decyzje.

## Komendy

Z `D:\Dev\Game\Game\underwater_map_workbench`:

```powershell
Test-Path ..\project.godot
git -C .. rev-parse --show-toplevel
python .\tools\build_underwater_map.py --check
python .\tools\build_underwater_map.py --build
python .\tools\build_underwater_map.py --check
..\tests\run_all_tests.ps1 -Target underwater_map_workbench/tests/underwater_map_smoke_test.gd
git -C .. diff --name-only
git -C .. status --short
```

`--check` nie może zapisywać. Po zmianie źródła obowiązuje kolejność build -> check -> smoke; dodatkowe testy root dobieraj proporcjonalnie do integracji. `ERROR` lub `SCRIPT ERROR` oznacza porażkę także przy kodzie wyjścia 0.

Nie twórz plików `candidate`, `final`, drugiej sceny ani drugiego manifestu. `schema_version` jest wersją formatu wewnątrz tego samego pliku, nie nazwą wariantu. Odrzucone próby i pliki tymczasowe nie należą do aktywnego pakietu.

## Referencje techniczne

- [Godot `CollisionPolygon2D`](https://docs.godotengine.org/en/stable/classes/class_collisionpolygon2d.html) i [Godot `BitMap`](https://docs.godotengine.org/en/stable/classes/class_bitmap.html) opisują reprezentację kolizji oraz wyprowadzanie poligonów z maski;
- [Godot `Image`](https://docs.godotengine.org/en/stable/classes/class_image.html) i [import obrazów](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html) określają limity i sposób przygotowania tekstur;
- [Godot `Parallax2D`](https://docs.godotengine.org/en/stable/classes/class_parallax2d.html) oraz [Godot `CanvasItem`](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html) rozdzielają ruch i kolejność rysowania od fizyki;
- [Godot: światła i cienie 2D](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html) opisuje okludery i SDF;
- [OpenAI Image Generation prompting guide](https://developers.openai.com/cookbook/examples/multimodal/image-gen-models-prompting-guide) zaleca jawnie wskazywać rolę każdego wejścia, oddzielać elementy zmieniane od zachowywanych i iterować małymi edycjami.

Trwałe reguły projektu pozostają w `.ai/DECISIONS.md`. Żadna zewnętrzna referencja nie przejmuje pozycji ani topologii mapy.
