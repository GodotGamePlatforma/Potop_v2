# Instrukcje warsztatu mapy podwodnej

Ten plik obowiązuje dla Codexa uruchomionego z katalogu `underwater_map_workbench/`. Jest lokalnym, bardziej szczegółowym rozszerzeniem korzeniowego `../AGENTS.md`: zawęża pracę do mapy podwodnej, ale nie osłabia globalnej bramki rozbieżności, ochrony zapisu, zasad testów ani zakazu destrukcyjnych operacji.

## Punkt wejścia i granica projektu

- Katalog roboczy Codexa pozostaje w `underwater_map_workbench/`. Na tej maszynie jest to `D:\Dev\Game\Game\underwater_map_workbench`.
- Pełny checkout projektu Godot musi być dostępny jako `..`; przed pracą potwierdź istnienie `../project.godot` i korzenia Git przez `git -C .. rev-parse --show-toplevel`.
- Warsztat jest hubem procesu, nie osobnym projektem Godot ani sandboxem systemu plików. Nie kopiuj do niego scen, assetów, testów, cache `.godot` ani plików `.import`.
- Ograniczenie „tylko mapa” jest granicą analiz i mutacji. Pliki globalne wolno czytać wyłącznie w zakresie potrzebnym do potwierdzenia kontraktu mapy; nie proponuj ani nie wykonuj niezwiązanych zmian w Bazie, UI, narracji, ekonomii, audio, zapisie lub innych domenach.

## Tryb zadania jest nadrzędny

- `TYLKO ANALIZA`, audyt, review lub diagnoza oznaczają pełny tryb read-only: bez edycji, nowych plików, generatorów zapisujących, Godota, testów tworzących artefakty, stagingu i commitów.
- Zadanie zmiany lub budowy zezwala wyłącznie na działania mieszczące się w jawnie podanym zakresie i poniższej allowliście.
- Polecenie zawierające szeroki plan wdrożenia nie rozszerza późniejszego ograniczenia użytkownika. Najnowszy jednoznaczny zakres ma pierwszeństwo.
- Rozbieżność z runtime, aktywnym ARD, produktem, architekturą lub zapisem uruchamia globalną bramkę: przedstaw dowód i warianty, a edycję rozpocznij dopiero po kolejnej wiadomości użytkownika zatwierdzającej konkretny wariant.

## Proporcjonalny kontekst

Dla zadań uruchomionych w tym katalogu poniższy routing zastępuje ogólny wymóg pełnego odczytu wszystkich dokumentów przy każdej drobnej pracy mapowej. Globalne zasady bezpieczeństwa i właściciele dokumentacji nadal obowiązują.

1. Zawsze przeczytaj lokalny `.ai/PROJECT_CONTEXT.md` oraz indeks aktywnych wpisów w lokalnym `.ai/DECISIONS.md`.
2. Praca wyłącznie wizualna wymaga odpowiednich wpisów lokalnych MAP-ARD, mapowych akapitów `../.ai/PROJECT_CONTEXT.md`, właściwych aktywnych ARD oraz tylko tych sekcji produktu i architektury, których dotyka zmiana; dla szerokiego tła są to co najmniej produkt 7.1 oraz architektura 9.1-9.1.2 i mapowa część 13.
3. Zmiana topologii, terenu, obiektu gameplayowego, stable ID, trasy lub osiągalności wymaga dodatkowo właściwych sekcji produktu 6-7, architektury 5.6, 9, 11 i 13 oraz ARD dotyczących mapy, podpisu i persistence.
4. `README.md` czytaj, gdy zadanie dotyczy uruchamiania, komend, onboardingu albo handoffu.
5. Pełne pięć dokumentów globalnych i komplet czterech dokumentów warsztatu czytaj tylko dla audytu całej dokumentacji, przekrojowej zmiany produktu/persistence albo jawnego żądania użytkownika.

Do wybranych dokumentów stosuj widoczny pełny odczyt potrzebnych sekcji i SHA-256 przed/po. `rg` wolno użyć do znalezienia nagłówków i aktywnych decyzji po przeczytaniu niniejszego routingu oraz lokalnej migawki. Jeśli źródła są sprzeczne, nie wybieraj arbitralnie jednego z nich — sprawdź runtime i zgłoś rozbieżność.

## Dozwolony zakres zapisów

Domyślna allowlista pracy mapowej obejmuje:

- `./AGENTS.md`, `./README.md`, `./.ai/PROJECT_CONTEXT.md` i `./.ai/DECISIONS.md` — tylko gdy routing dokumentacji wymaga zmiany;
- `../assets/diving/world/art_cells/`;
- `../assets/diving/world/backdrops/` i `../assets/diving/world/foregrounds/`;
- `../assets/diving/world/layout_guides/`;
- `../assets/diving/world/materials/`, `../assets/diving/world/props/` i `../assets/diving/world/shaders/`;
- `../scenes/diving/map_visuals/`;
- `../data/diving_visuals/`.

Mapowe narzędzie albo test poza tą listą można edytować tylko wtedy, gdy przed pierwszą edycją podasz dokładną ścieżkę i związek z zadaniem. `../assets/diving/world/map_v2/visual_chunks/` jest wyłącznie wyjściem zatwierdzonego generatora; nie poprawiaj cropów ręcznie.

Ścieżki chronione wymagające osobnego, jawnie zatwierdzonego zakresu globalnego:

- `../scenes/diving/UnderwaterMap.tscn` i `../scenes/diving/map_objects/`;
- scenowe `Polygon2D`, przechodniość, kolizje, trasy, obiekty gameplayowe i stable ID;
- `world_collision_grid.png`, SDF, semantyczne chunki, blueprint, `WorldDelta` i podpis mapy;
- skrypty runtime, persistence, `project.godot` oraz pięć dokumentów globalnych.

Pozostałe ścieżki są poza zakresem. Przed edycją wypisz planowane pliki i ich kategorię. Po edycji uruchom `git -C .. diff --name-only` oraz `git -C .. status --short`; nieplanowana ścieżka zatrzymuje pracę.

## Authority i pochodne

- `../scenes/diving/UnderwaterMap.tscn` pozostaje jedynym authority statycznego świata. Manifest, guide, PNG, SDF, segmenty, okludery i chunki nie mogą przejąć tej roli.
- Scenowe `Polygon2D` są authority makroterenu. `world_collision_grid.png` i SDF są pochodnymi i nie podlegają ręcznej edycji.
- Profile `.tres` przechowują dane prezentacyjne, sceny wizualne kompozycję, a skrypty zachowanie. Nie twórz drugiego manifestu świata ani równoległego modelu biomów.
- Źródło, pochodna i cache muszą być rozróżnione w manifeście oraz handoffie. Brak źródła oznacza pipeline archiwalny lub zablokowany, nie zgodę na odtworzenie go z cropów.

## Workflow grafiki

Trwałe inwarianty określają lokalne MAP-ARD. Dla nowego szerokiego tła albo przebudowy regionu obowiązuje skrócona bramka:

1. Zbierz dowód runtime oraz relację z kanonicznym terenem i landmarkami.
2. Zbuduj jeden brief i jeden niskoczęstotliwościowy composition master całego pasa.
3. Uzyskaj jawną akceptację mastera przed finalnym detalem, ArtCells i chunkami.
4. Rozwijaj detal oknami ze wspólnym masterem, sąsiadami i tymi samymi referencjami; każda poprawka wraca do mastera.
5. Wyprowadź pochodne deterministycznie i oceń jednocześnie integralność techniczną, pełną panoramę, kadry clean/gameplay, profile jakości i `reduced_motion`.

Zmiana pojedynczego propu, materiału, shadera albo lokalnego prefabu nie wymaga nowego mastera całego regionu, o ile nie zmienia szerokiej kompozycji, topologii ani czytelności trasy.

Bitmapa nie zawiera HUD-u, nurka, celu, fizyki, sugestii nowej przechodniości ani wypieczonej globalnej mgły, caustics lub światła gameplayowego. Atmosfera i ruch pozostają wspólnymi efektami Godota.

## Weryfikacja z bieżącego katalogu

- Polecenia kieruj jawnie do pełnego projektu przez `..`; nie zmieniaj CWD jako sposobu obchodzenia zakresu.
- Godot uruchamiaj wyłącznie przez `..\tests\run_all_tests.ps1` i sekwencyjnie.
- Generator budujący pochodne musi mieć niedestrukcyjny `--check`, jawne źródło i deterministyczny wynik. Jeżeli któregoś elementu brakuje, nie uruchamiaj buildera jako aktywnego pipeline'u; zgłoś lukę.
- Po dozwolonej zmianie źródła wykonaj build, następnie `--check`, celowane testy i właściwy snapshot natywny. Otwórz i oceń wynik wizualnie.
- `PASS`, zgodny SHA, brak szczeliny albo wysoki wynik A/B potwierdzają tylko swój kontrakt. Akceptacja artystyczna wymaga osobnej kontroli całej kompozycji.
- `ERROR`, `SCRIPT ERROR`, timeout albo brak wymaganego źródła są porażką także przy kodzie wyjścia 0.

## Dokumentacja

- Lokalny `.ai/PROJECT_CONTEXT.md` jest wyłącznie datowaną migawką assetów, luk i ostatniego odbioru.
- Lokalny `.ai/DECISIONS.md` jest wyłącznie rejestrem trwałych decyzji języka wizualnego i pipeline'u.
- Lokalny `README.md` jest praktycznym onboardingiem, indeksem ścieżek i zbiorem działających komend z tego CWD.
- Niniejszy `AGENTS.md` jest jedynym właścicielem lokalnego procesu Codexa, allowlisty i bramek wykonawczych.
- Zmiany produktu, technicznej authority, persistence i przekrojowego runtime nadal należą do właścicieli w `../AGENTS.md`.

Nie twórz kolejnych plików dokumentacyjnych. Briefy, layout guides, maski, manifesty provenance, grafiki i raporty maszynowe są assetami albo danymi technicznymi, nie nowym źródłem reguł projektu.
