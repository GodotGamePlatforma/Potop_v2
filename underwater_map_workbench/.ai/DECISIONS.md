# Decyzje warsztatu mapy podwodnej

Rola tego pliku: trwałe, lokalne rozstrzygnięcia dotyczące authoringu konkretnej mapy, jej kompozycji, pipeline'u prezentacyjnego i zgodności grafiki z topologią. Nie ustanawia ogólnych zasad gry, właścicieli stanu, persistence, migracji ani bieżącego statusu implementacji. Konflikt rozstrzygają aktywne ARD w `../../.ai/DECISIONS.md`, dokument będący globalnym właścicielem szczegółu oraz faktyczny runtime.

Każdy nowy wpis otrzymuje stabilny identyfikator `MAP-ARD-XXXX`, status, datę, klauzule i relacje. Zmiana sensu wymaga nowego wpisu i symetrycznego zastąpienia; wpisów historycznych nie usuwa się.

Proces Codexa, CWD, allowlista i kolejność pracy należą wyłącznie do `../AGENTS.md`; komendy i onboarding do `../README.md`; bieżący stan assetów do `PROJECT_CONTEXT.md`. Ten rejestr nie powtarza tych treści.

## Indeks aktywnych decyzji

| ID | Właściciel szczegółu | Najważniejszy inwariant |
|---|---|---|
| MAP-ARD-0013 | manifest z rewizjami i stos L00-L10 | Jeden manifest semantyki generuje jedną scenę runtime; liczności zawartości są danymi rewizji, a nie ograniczeniami pipeline'u. |
| MAP-ARD-0014 | pakiet prawdy L05 i authoring ImageGen | Kolider, maski i prowadnice pochodzą z jednego payloadu L05, a grafika strukturalna jest ograniczoną propozycją sprawdzaną w obie strony względem tej geometrii. |
| MAP-ARD-0015 | język bitmap i zakotwiczenie mapy | Widoczna grafika mapy jest realistycznym/rysunkowym 2D bez pixel artu, zachowuje proporcje źródła i zakotwiczenie względem L05. |
| MAP-ARD-0016 | globalny filtr i lokalne samplery | Zwykłe bitmapy mapy dziedziczą globalny `Linear`; jawne filtry pozostają wyłącznie na samplerach o odrębnej semantyce. |
| MAP-ARD-0017 | natywna gęstość bitmap wszystkich warstw | Żadna widoczna bitmapa warstwy nie jest skalowana; większy obszar powstaje z natywnych paneli albo powtarzania kafla przy dokładnie jednym texelu na jednostkę świata. |
| MAP-ARD-0018 | niezależne elementy wizualne i proxy-first | Każdy niezależnie modyfikowalny budynek lub mały nierozdzielny klaster ma osobny rekord elementu; skalę i rozmieszczenie zatwierdza się na proxy w rzeczywistej scenie przed generacją finalnej grafiki. |
| MAP-ARD-0020 | ostateczny kontrakt tła L00 | L00 jest jednym nieprzezroczystym, proceduralnym polem `water_color`; nie zawiera grafiki, shadera, topologii ani efektów wodnego medium. |
| MAP-ARD-0021 | granica Mapy i avatara | Avatar jest zewnętrznym konsumentem mapy; warsztat mapy nie przejmuje jego sceny, fizycznej bryły, grafiki ani VFX. |
| MAP-ARD-0022 | podrzędne pakiety struktur | Mapa posiada rejestr i globalny placement, a każdy `structures/<id>/structure_manifest.json` wyłącznie lokalną topologię, grafikę i runtime jednego budynku. |
| MAP-ARD-0023 | rezydencja dalekich planów i odbiór prezentacji | L01/L02 są ładowane przejściowo dla bieżącego okna kamery, dynamiczny survey wynika z publicznej kompozycji, a detal L05 pozostaje klipowany kanoniczną bryłą bez zmiany topologii. |
| MAP-ARD-0025 | rasterowy clearance tła przy wejściach struktur | Każdy anonimowy, przechodni run na granicy struktury otrzymuje world-locked, wyłącznie wizualny clearance nad L01/L02 i pod L04, niezależny od ID oraz bez wpływu na fizykę. |
| MAP-ARD-0027 | atomowy PR pakietu i mapowego pinu | Nowy seal, dokładny pin oraz wszystkie pochodne trafiają razem w jednym root-routed branchu i PR. |

Wyłącznie wpisy z powyższego indeksu obowiązują. MAP-ARD-0001–MAP-ARD-0012 pozostają historią i provenance; ich liczności, współrzędne, kolory masek, screenshoty i instrukcje ImageGen nie są wejściem bieżącej produkcji.

---

## MAP-ARD-0001 - Jedna kompozycja master poprzedza podział panoramy

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-16
- Relacje: Zastępuje: brak | Zastąpiona przez: MAP-ARD-0012
- D1. Każde szerokie tło regionu ma jedną zatwierdzoną kompozycję master obejmującą cały docelowy pas i jego relację z kanonicznym terenem.
- D2. Master blokuje co najmniej horyzont, trzy plany głębi, skalę form, rytm gęstości, miejsca oddechu, strefę czytelności oraz przebieg kluczowych motywów przed produkcją finalnego detalu.
- D3. ArtCells, okna inpaint/outpaint i chunki runtime są pochodnymi jednego mastera. Nie wolno przyjąć zestawu niezależnie wygenerowanych finalnych obrazów jako źródła panoramy.
- D4. Po każdej większej edycji ocenia się ponownie cały złożony pas. Lokalnie poprawny kadr nie może zostać przyjęty, jeżeli psuje kompozycję globalną.
- Powód i skutek: wspólna, niskoczęstotliwościowa kompozycja usuwa szwy perspektywy, skali i rytmu, których nie wykrywa identyczny overlap pikselowy.

## MAP-ARD-0002 - Grafika mapy jest warstwowa i nie ustanawia fizyki

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-16
- Relacje: Zastępuje: brak | Zastąpiona przez: MAP-ARD-0012
- D1. Dalekie sylwety i panoramy, średni plan landmarków, skóry terenu/prefaby oraz atmosfera runtime są osobnymi warstwami z odrębną odpowiedzialnością.
- D2. Raster źródłowy może sugerować głębię i materiał, ale nie definiuje przechodniości, kolizji, stable ID, rozmieszczenia gameplayowego ani zapisu.
- D3. Globalna mgła, caustics, refrakcja, ruch wody, cząstki i światło gameplayowe pozostają w Godot. Nie wypieka się ich do neutralnych płyt, które mają działać w różnych profilach jakości i oświetleniu.
- D4. Płyta albo prefab wizualny nie zawiera nurka, HUD-u, celu, interakcji ani powierzchni sugerującej inną topologię niż kanoniczna scena.
- Powód i skutek: warstwowość pozwala poprawiać grafikę bez rozjazdu z fizyką, zapisem i wspólną atmosferą świata.

## MAP-ARD-0003 - Integralność techniczna i odbiór artystyczny są dwiema bramkami

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-16
- Relacje: Zastępuje: brak | Zastąpiona przez: MAP-ARD-0012
- D1. Bramka techniczna obejmuje w szczególności rozmiary, hashe, pochodne, brak szczelin, streaming, budżety i niezmienność gameplayu.
- D2. Bramka artystyczna obejmuje całą panoramę, perspektywę, skalę, paletę, rytm, powtórzenia, hierarchię planów, oddech kompozycyjny i czytelność w reprezentatywnym runtime.
- D3. Snapshot, metryka wkładu, zgodny overlap albo zielony test nie zastępują jawnej kontroli wzrokowej. Akceptacja wymaga obu bramek.
- D4. Jawne odrzucenie przez użytkownika cofa status wizualnego baseline'u, ale nie zmienia historycznego wyniku wąskich testów technicznych.
- Powód i skutek: pipeline nie może ponownie uznać za gotowy obrazu, który jest bezszwowy w bajtach, lecz niespójny jako świat.

## MAP-ARD-0004 - Źródła grafiki zachowują reprodukowalne provenance

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-16
- Relacje: Zastępuje: brak | Zastąpiona przez: MAP-ARD-0012
- D1. Wersjonowany zestaw źródłowy zachowuje master, layout guide, maski głębi/zasłonięcia, paletę oraz manifest operacji prowadzących do zaakceptowanej rewizji.
- D2. Manifest zapisuje użyte narzędzie i wersję/model, parametry lub seed, prompty, identyfikatory i SHA-256 referencji, geometrię okna, kolejność operacji oraz SHA-256 wyniku, o ile dane narzędzie je udostępnia.
- D3. Brak dostępnego parametru jest zapisywany jawnie jako niedostępny; nie wolno deklarować reprodukowalności na podstawie samego finalnego PNG.
- D4. Pochodne ArtCells i chunki są odtwarzane deterministycznie ze źródeł i manifestu. Nie otrzymują ręcznych zmian, które nie wróciły do mastera.
- Powód i skutek: kolejny Codex może kontynuować ten sam obraz i zdiagnozować zmianę bez zgadywania promptów, referencji i historii ręcznych poprawek.

## MAP-ARD-0005 - Sześć planów jest scenowym authority edytowalnej grafiki

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-16
- Relacje: Zastępuje: brak | Zastąpiona przez: MAP-ARD-0012
- D1. Produkcyjna grafika szerokiej mapy ma dokładnie sześć semantycznych planów `L00-L05`: bazowe pole barwy, najdalsze sylwetki, dalekie konstrukcje, średni plan i dryfujące dekoracje, skórę bliskiego terenu oraz niegameplayowe zasłonięcia pierwszego planu.
- D2. Każdy element, który ma być wybierany albo poprawiany niezależnie, jest osobnym węzłem `Node2D`, `Sprite2D`, `Polygon2D` lub instancją wizualnej `PackedScene`; jego transform i widoczność należą do sceny kompozycji, nie do manifestu runtime.
- D3. Każdy plan rozdziela zawartość paralaktyczną od zakotwiczonej w świecie. Skóra terenu i każdy element zależny od gameplayu pozostają współosiowe z kanoniczną sceną oraz nie mogą odpływać od kolizji, SDF ani stable ID.
- D4. Dalsze plany używają mniejszego tempa kamery niż bliższe. `reduced_motion` usuwa różnicowy ruch i autoscroll, zachowując wszystkie elementy, role oraz z-order; wartości strojalne należą do walidowanych profili warstw.
- D5. Spłaszczona bitmapa jest jednym elementem i cała jej zawartość dzieli transform. Indywidualna edycja obiektów wymaga osobnych węzłów albo prefabów; pochodne streamingu nigdy nie stają się źródłem authoringu.
- D6. Manifest i chunki są deterministycznymi pochodnymi prezentacji. Nie przejmują authority topologii mapy, gameplayu, persistence ani transformów sceny; archiwalne pochodne bez mastera wolno jedynie zweryfikować i zaadaptować bez nadpisywania.
- Powód i skutek: twórca otrzymuje pełną kontrolę nad każdym faktycznie niezależnym składnikiem obrazu, a runtime może stosować paralaksę i streaming bez tworzenia drugiej mapy albo rozjazdu grafiki z fizyką.

## MAP-ARD-0006 - Kompozycja biomów pokazuje skarpowe miasto portowe

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-17
- Relacje: Zastępuje: brak | Zastąpiona przez: MAP-ARD-0012
- D1. Każdy nowy master pełnej mapy zachowuje zatwierdzoną geografię ARD-0100: R1 na górnym lewym tarasie, R2 poniżej po lewej, pionowy R3 po prawej oraz pełnoszeroki R4 na dole.
- D2. R1 ma dwie czytelne wysokości w jednym biomie: spokojniejszą koronę dachów oraz niższe pionowe fasady, ulice i wnętrza. Motyw usługowy nie może być przedstawiany jako wolnostojący sklep na dachu.
- D3. Górna część R3 przedstawia nabrzeże, magazyny i stocznię obok miasta; ciężka fabryka, elektrownia, chemikalia i złom schodzą niżej. Kompozycja nie może sugerować, że cały port znajduje się bezpośrednio pod śródmieściem.
- D4. R4 jest jednym monumentalnym dolnym pasem. Metro, bunkier, laboratoria i grodzie tworzą próg, Zapadnięte Śródmieście część pośrednią, a Serce najniższy punkt kompozycji.
- D5. Przejścia R1-R2-R3 używają skarp, klinów terenu, nabrzeży, podpór i motywów zachodzących na granice zamiast trzech prostych kolorowych ścian. Globalny spadek światła wynika z głębokości, a lokalny język materiałów z biomu.
- D6. Mastery L01 i L02 ustawione względem wcześniejszych pełnoszerokich pasów tracą akceptację rozmieszczenia. Ich pojedyncze komponenty mogą zachować provenance i rolę stylistyczną, lecz muszą zostać ponownie skomponowane oraz odebrane na aktualnym guide.
- D7. Cała mapa oraz każdy landmark są rysowane jako ortograficzny przekrój boczny 2D. Warstwy mogą różnić się kontrastem, ostrością i tempem kamery, ale nie używają izometrii, perspektywicznych podłóg ani brył 2,5D sugerujących fałszywe przejścia.
- D8. Zabudowany landmark pokazuje duże, proste i fizycznie przechodnie komory zgodne z kanonicznym makroterenem. Wejście w grafice pokrywa się z wejściem w masce wody, a prefab prezentacyjny nie zamyka go, nie dodaje własnej kolizji i nie zastępuje scenowego authority.
- D9. Czytelność ma pierwszeństwo przed mikrodetalem i spektakularnym światłem: jedna dominanta oraz najwyżej kilka drugorzędnych klastrów w kadrze, spokojne półtony, kontrolowane akcenty i brak wypieczonych promieni, mgły, caustics albo efektów gameplayowych. Świat pozostaje przygodowy i atrakcyjny, lecz nie przepalony, ponury ani przeładowany.
- D10. Pełna mapa pozostaje rozpoznawalna po pomniejszeniu: każdy region ma własny obrys dużych komór, pionów i łączników, a ważne landmarki tworzą węzły tej sylwety. Referencje innych map służą wyłącznie zasadzie makroczytelności; layout, grafika, nazwy i szczegół świata pozostają oryginalne dla Ostatniego Pomostu.
- Powód i skutek: świat czyta się jako jedna zatopiona geografia, w której miasto, zielone tarasy, port i podziemny rdzeń mają wiarygodne sąsiedztwo, a nie jako cztery niezależne tapety ułożone jedna pod drugą.

## MAP-ARD-0007 - Simple-parallax jest produkcyjnym baseline'em

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-23
- Relacje: Zastępuje produkcyjne użycie pakietów V5-V7 | Zastąpiona przez: MAP-ARD-0012
- D1. Jeden map-aware master `biomes_simple_parallax_v1_map_aware` prowadzi bieżącą szeroką kompozycję; pochodne nie przejmują authority sceny ani terenu.
- D2. Scena ma dokładnie 14 osobno transformowalnych elementów authored `0/4/4/4/0/2`: cztery L01, cztery regionalne L02, cztery wybrane L03 i dwa wybrane L05.
- D3. L00 pozostaje proceduralne, a L04 generuje renderer z kanonicznej maski terenu. Generated L01/L02/L03/L05 są niewidoczne i nie tworzą równoległej kompozycji.
- D4. Wyłącznie cztery regionalne L02 podlegają streamingowi jednego payloadu; ich transformy i granice należą do sceny, a pozostałe authored elementy są scene-resident.
- D5. V5-V7 i landmarkowe overlaye pozostają historią/provenance. Ich powrót wymaga nowej akceptacji szerokiej kompozycji; bieżące pola wariantów 27 landmarków są puste.
- D6. Dokładne skale, z-ordery, progi jakości, liczby i położenia należą do walidowanych profili, sceny i manifestu. Ich zmiana wymaga ponownej kontroli pełnego obrazu, ale nie ustanawia topologii, fizyki ani persistence.
- Powód i skutek: prosty, mały stos daje czytelną głębię i przewidywalny z-order bez nakładania dawnych pełnomapowych rodzin, a L04 zachowuje zgodność grafiki z kolizją.

## MAP-ARD-0008 - Każdy element authored ma własną kanoniczną paralaksę

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-23
- Relacje: Zastępuje wyłącznie MAP-ARD-0005 D4 i MAP-ARD-0007 D2 | Zastąpiona przez: MAP-ARD-0012
- D1. Stos zachowuje dokładnie sześć semantycznych planów `L00-L05`, ich role oraz z-ordery. Rozdzielenie ruchu elementów nie tworzy nowych warstw semantycznych ani drugiego modelu świata.
- D2. Warstwy L01, L02, L03 i L05 mają neutralny root `ParallaxContent: Node2D`. Każdy authored element paralaktyczny tych warstw znajduje się w zaufanym, kanonicznym `DiveVisualElementParallax: Parallax2D`, który ma dokładnie jednego bezpośredniego potomka `DiveVisualLayerElement`. L00 i world-locked L04 zachowują dotychczasową paralaksę na rootach warstw.
- D3. Kanoniczny wrapper jest właścicielem efektywnej normalnej skali ruchu kamery danego elementu: może jawnie nadpisać domyślną skalę profilu, a bez nadpisania dziedziczy profil warstwy. Pozycja, obrót, skala obrazu, `Skew`, widoczność i granice streamingu pozostają na potomnym elemencie; wrapper zachowuje identity transform, dziedziczony z-order, wyłączone repeat i autoscroll oraz nie może zostać zastąpiony surowym albo niestandardowym `Parallax2D`.
- D4. `ParallaxContent/Authored` w L01, L02, L03 i L05 zawiera dokładnie cztery neutralne foldery organizacyjne `R1-R4`, a każdy wrapper jest bezpośrednim dzieckiem jednego z nich. Folder wskazuje przynależność edytorską do regionu, lecz jego nazwa ani ścieżka nie są stable ID, topologią, strefą gameplayową ani źródłem persistence.
- D5. Bieżący baseline ma 19 osobno transformowalnych elementów authored w podziale `0/9/4/4/0/2`. Dokładnie cztery L02 zachowują politykę `MANIFEST_STREAMED`; pozostałe authored elementy są scene-resident.
- D6. `reduced_motion` ustawia efektywną skalę każdego wrappera i obu nieprzebudowanych rootów na `Vector2.ONE`, wyłącza ruch różnicowy bez usuwania elementów i kompensuje przełączenie tak, aby nie powodować skoku obrazu. Powrót przywraca własną skalę normalną każdego elementu.
- D7. Walidacja utrzymuje monotoniczną hierarchię głębi: najmniejsza efektywna skala normalna bliższego planu musi być większa od największej efektywnej skali poprzedniego planu. Strojenie jednego elementu nie może odwrócić kolejności planów ani z-orderu.
- D8. Wrapper, jego skala i folder regionu są wyłącznie prezentacją. Nie zmieniają kolizji, przechodniości, stable ID, `WorldBlueprint`, `WorldDelta`, `map_gameplay_signature`, zapisu ani migracji.
- Powód i skutek: artysta może osobno rozstawić i stroić tempo każdego obiektu, zachowując czytelne grupowanie regionalne, wspólną hierarchię sześciu planów oraz pełną izolację grafiki od gameplayu i persistence.

## MAP-ARD-0009 - L02 R1 składa pięć niezależnych konstrukcji

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-23
- Relacje: Zastępuje wyłącznie MAP-ARD-0007 D4 i MAP-ARD-0008 D5 | Zastąpiona przez: MAP-ARD-0012
- D1. Bieżący baseline ma dokładnie 23 osobno transformowalne elementy authored w podziale `0/9/8/4/0/2` dla `L00-L05`.
- D2. `L02/R1` zawiera pięć niezależnych konstrukcji, a `L02/R2`, `L02/R3` i `L02/R4` po jednej. Wszystkie osiem elementów L02 zachowuje politykę `MANIFEST_STREAMED` w jednym payloadzie schema-v2; żaden authored element L02 nie jest scene-resident.
- D3. Każdy z pięciu elementów R1 zachowuje własny kanoniczny wrapper, skalę normalnej paralaksy, transform, granice i zasób. Folder R1 grupuje je wyłącznie w edytorze, a manifest nie przejmuje transformów, tempa kamery ani authority kompozycji.
- D4. Rozdzielenie prezentacyjne nie zmienia kolizji, przechodniości, stable ID, `WorldBlueprint`, `WorldDelta`, `map_gameplay_signature`, formatu kampanii, zapisu ani migracji.
- Powód i skutek: użytkownik może osobno rozstawić i stroić pałac, dziedziniec, wieżę, zabudowę oraz bramę R1, wzmacniając czytelność paralaksy bez ponownego spłaszczenia regionu lub tworzenia nowej warstwy semantycznej.

## MAP-ARD-0010 - Świat 12 × 12 zaczyna się od nowego mastera pełnej mapy

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-23
- Relacje: Zastępuje: brak | Zastąpiona przez: MAP-ARD-0012
- D1. Produkcja szerokiej grafiki docelowego świata `23 040 × 12 960` zaczyna się od jednej nowej, niskoczęstotliwościowej kompozycji master całej mapy, osadzonej na zatwierdzonej geografii `12 × 12` i kanonicznym makroterenie. Osobne regiony, warstwy i okna detalu nie mogą powstać jako konkurencyjne źródła kompozycji.
- D2. Bieżący simple-parallax, jego mastery, 23 elementy authored i podział `0/9/8/4/0/2` pozostają baseline'em oraz provenance obecnego świata. Nie są automatycznie skalowane, rozszerzane ani uznawane za docelowy inwentarz grafiki świata `12 × 12`.
- D3. Przed jawną akceptacją nowego mastera nie powstaje finalny detal, produkcyjny podział na ArtCells, finalne cutouty ani chunki runtime. Dopuszczalne są wyłącznie szkice i próby służące ocenie pełnej kompozycji.
- D4. Master blokuje sylwetę czterech regionów, relację z 27 stabilnymi landmarkami, duże komory i łączniki, hierarchię planów, skalę lokalnych obiektów, rytm gęstości, miejsca oddechu, paletę oraz kierunek ortograficznego przekroju bocznego 2D.
- D5. Dokładna liczba elementów wizualnych, ich podział między L01/L02/L03/L05 i R1-R4, ścieżki tekstur, rozdzielczości źródeł, polityka resident/streamed oraz indywidualne skale paralaksy pozostają `PENDING` do akceptacji mastera. Dopiero wtedy powstaje jawny inwentarz niezależnych obiektów i plan ich authoringu.
- D6. Po akceptacji mastera detal jest rozwijany oknami ze wspólnym kontekstem mastera i sąsiadów, po czym wraca do jednego źródła. ArtCells, cutouty, layout guides, manifesty i chunki są deterministycznymi pochodnymi z pełnym provenance; nie otrzymują ręcznych poprawek niewprowadzonych do mastera.
- D7. Master i wszystkie jego pochodne pozostają prezentacją. Nie ustanawiają topologii, kolizji, regionów gameplayowych, stable ID, `WorldBlueprint`, `WorldDelta`, `map_gameplay_signature`, zapisu ani migracji.
- Powód i skutek: docelowa mapa zachowuje jeden czytelny rytm i wspólną skalę mimo czterokrotnie większej powierzchni, a zespół nie utrwala przedwcześnie liczby lub układu assetów odziedziczonych po mniejszym świecie.

## MAP-ARD-0011 - L04 v4 zamraża sockety dla 27 osobno authorowanych landmarków L03

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-24
- Relacje: Uszczegóławia MAP-ARD-0002, MAP-ARD-0006 i MAP-ARD-0010 | Zastąpiona przez: MAP-ARD-0012
- D1. Rewizja `v4_single_c02_descent_two_tunnels` z manifestem SHA-256 `97c500571afa059132fda6402b60b86297730d05d17c08674e89db71ebd1abc0` oraz maską SHA-256 `0bea79c61349f0cc1d8577820ff5cb4ed87afd23f33d74302bf36c3f2701c5ae` jest zaakceptowanym, zamrożonym wejściem produkcji grafiki świata 12 × 12. Pozostaje `candidate_only`: nie jest authority topologii ani aktywnym runtime.
- D2. L04 jest prowadnicą piksel w piksel. Czarny oznacza stałą bryłę przeznaczoną do późniejszego odwzorowania materiałem gruntu, fundamentu lub betonu; cyjan oznacza wodę, której żadna warstwa L01-L03, detal, prop ani landmark nie może wizualnie zamknąć, przeciąć lub przedstawić jako ścianę.
- D3. Dokładnie 27 prostokątów `world_rect` i ich stable ID z zamrożonego manifestu tworzy inwentarz authoringu L03. Położenie, skala i sąsiedztwo socketu nie są ponownie interpretowane w promptach ani przesuwane dla wygody kompozycji pojedynczego assetu.
- D4. Każdy landmark powstaje od nowa w osobnym wywołaniu wbudowanego ImageGen i daje osobny przezroczysty cutout sRGBA L03. Nie wolno wygenerować jednego zbiorczego obrazu i uznać jego przypadkowych fragmentów za 27 źródeł ani generować różnych landmarków jednym wywołaniem batchowym.
- D5. Każde wywołanie otrzymuje wspólne referencje całej mapy, dokładną kartę własnego socketu, zamrożoną maskę L04 i tożsamość landmarku. Wynik nie zawiera siatki, etykiet, HUD-u, nurka, kolidera, wypieczonej globalnej mgły, caustics ani lokalnego emitowanego światła; oświetlenie kierunkowe pochodzi jedynie słabo z góry oceanu.
- D6. Rzędy 01–06 pozostają w całości przepływalne, więc górne landmarki są otwartymi wnętrzami miasta w niekolizyjnym tle L03. `R2-01` pozostaje szklarnią nad gruntem. Landmarki podziemne dekorują wyłącznie swoje niebieskie komory; `R4-06 Serce` jest bankiem energii, elektrownią-serwerownią, zespołem szaf elektrycznych i punktem zbiegu głównych kabli.
- D7. Asset przechodzi odbiór dopiero po dwóch kontrolach: osobnej kontroli alfy i tożsamości w sockecie oraz powrotnym złożeniu na pełnej mapie z L04. Każda widoczna ściana, podłoga, drzwi, gruz, dźwig, kabel albo wyposażenie przecinające cyjanową trasę odrzuca wynik niezależnie od jakości artystycznej.
- D8. Akceptacja grafiki L03 nie promuje maski do fizyki. Późniejsza integracja świata wymaga osobnego mapowania do scenowych `Polygon2D`, nowego podpisu mapy, recertyfikacji i właściwych testów globalnych; obrazy i manifest handoffu pozostają prezentacją oraz provenance.
- Powód i skutek: każdy landmark może otrzymać wyraźną, właściwą funkcję i detal, ale wszystkie 27 assetów zachowuje jedną skalę świata, zamrożone położenia oraz bezwarunkowo czytelną, wspólną sieć pływania.

## MAP-ARD-0012 - Manifest warsztatu jest jedynym źródłem mapy RESET-A

- Status / aktywny zakres: Historyczna; zastąpiona w całości
- Zatwierdzenie: 2026-08-25; rozszerzenie aktywnego zakresu 2026-08-26
- Relacje: Zastępuje w całości MAP-ARD-0001–MAP-ARD-0011 | Zastąpiona przez: MAP-ARD-0013
- D1. `map_manifest.json` w warsztacie jest jedynym semantycznym źródłem konkretnej mapy: wymiarów, pozycji, ról obiektów i trasy tutorialu. Nie istnieje drugi katalog pozycji, scena authorowana ręcznie ani manifest wariantu.
- D2. `UnderwaterMap.tscn` jest deterministyczną pochodną manifestu. Jedyny builder `tools/build_underwater_map.py` zapisuje scenę w trybie `--build`, a `--check` bez zapisu potwierdza byte-exact aktualność wyniku.
- D3. Warsztat posiada cały aktywny pakiet konkretnej mapy, łącznie z kompilatorem i cienkim hostem w `runtime/`, jednym smoke testem, shaderami środowiska oraz potrzebnymi assetami podwodnego gameplayu w `assets/gameplay/`. Root posiada ogólne mechaniki nurkowania i integrację Godot, ale nie drugi katalog podwodnych grafik.
- D4. Mapa ma dokładnie `12 × 12` komórek po `1920 × 1080`, czyli `23040 × 12960` jednostek. Świat jest pustą, otwartą przestrzenią ograniczoną granicą mapy.
- D5. Jedynym landmarkiem jest `R1-00` „Stacja Nurkowa”. Spawn i aktywna lina współdzielą pozycję `[11520, 1000]`.
- D6. Dwie skrzynie tutorialowe, blokada `SC-01` i `junction_j7` są aktywnymi obiektami gameplayowymi, ale nie landmarkami. Ich kolejność tworzy trasę stacja → skrzynia A → skrzynia B → blokada → J-7 → stacja.
- D7. Source `v5` jest clean breakiem bez migracji współrzędnych. Stara topologia 27 landmarków, pipeline'y i warianty V1–V7, kandydaci oraz ich testy nie są fallbackiem ani materiałem do automatycznego odtworzenia. Jedyny lokalny smoke sprawdza techniczny przepływ manifest → scena → kompilator → runtime i wyprowadza wartości z bieżącego manifestu; nie zamraża w teście ID, pozycji, liczby obiektów ani kolejności zawartości.
- D8. Reset mapy nie wyłącza ogólnych mechanik tlenu, ruchu, łupu, interakcji, wyposażenia, powrotu, tutorialu ani kampanii. Dalsza geografia i landmarki powstają od nowa przez rozszerzenie jednego manifestu, a potrzebna grafika trafia wyłącznie do lokalnego `assets/`, bez source scratch, wariantów i kopii w root.
- Powód i skutek: jeden mały, jawny plik usuwa rozjazd wersji i pozycji, a produkcyjna scena pozostaje odtwarzalna oraz sprawdzalna bez ręcznego duplikowania semantyki.

## MAP-ARD-0013 - Manifest z rewizjami generuje runtime i stos L00-L10

- Status / aktywny zakres: Częściowo zastąpiona; D1 w zakresie sceny pochodnej i zgodności zestawu źródeł, D2-D4,D7-D10 poza szczegółem podrzędnych pakietów struktur
- Zatwierdzenie: 2026-08-25
- Relacje: Zastępuje w całości MAP-ARD-0012 | Częściowo zastąpiona przez: MAP-ARD-0014/D1 w pierwszym zdaniu D1, MAP-ARD-0019/D1-D6 w zakresie D5-D6 oraz MAP-ARD-0022/D1-D8 w zakresie zagnieżdżonych pakietów struktur
- D1. `map_manifest.json` jest jedynym edytowanym źródłem semantyki konkretnej mapy. `UnderwaterMap.tscn` jest jedyną sceną mapy ładowaną przez runtime i deterministyczną, nieedytowaną ręcznie pochodną buildera. Zgodność surowego SHA manifestu blokuje użycie nieaktualnej sceny.
- D2. `schema_version` wersjonuje format danych, `revision_id` bieżącą zawartość mapy, `topology_revision` statyczną geometrię, a `presentation_revision` wygląd. Zmiana rewizji odbywa się w tym samym aktywnym manifeście; nie tworzy plików `candidate`, `final`, kopii sceny ani drugiego manifestu.
- D3. Liczby regionów, landmarków, połączeń, tuneli, shortcutów, obiektów i assetów wynikają wyłącznie z tablic bieżącego manifestu. Pipeline waliduje unikalność ID, typy, granice, referencje i wymagane semantyczne cele kampanii, lecz nie ustanawia trwałych liczności konkretnej rewizji. Dokładne bieżące wartości należą wyłącznie do manifestu i datowanej migawki `PROJECT_CONTEXT.md`.
- D4. Manifest definiuje jedenaście stabilnych semantycznych slotów `L00-L10`; numer `schema_version` opisuje bieżący format pliku i nie jest trwałym inwariantem tej decyzji. Bieżący typowany renderer obsługuje proceduralne L00, nieblokujące `L01/texture_rect` i `L02/texture_rect` oraz `L05/collision_masked_material`; użycie innego slotu lub rodzaju assetu wymaga jawnego rozszerzenia walidacji, buildera, kompilatora i smoke. `L10` pozostaje wyłączoną rezerwą; użycie rezerwy nie przenumerowuje istniejących warstw. Identyfikator `Lxx` nie jest numerem physics layer ani automatycznym `z_index`.
- D5. L05 ma rolę `collider_authority`, pozostaje world-locked z jednostkową skalą ruchu i używa `topology.mode = l05_mask_v1` z jednym hash-pinned payloadem `l05_rect_ops_v1` wskazanym przez manifest. Raster nawigacji, segmenty fizyki, maski `solid/open_water`, pas graniczny i prowadnica grafiki są pochodnymi tego samego payloadu, nigdy finalnej ilustracji.
- D6. Wszystkie korzenie `VisualLayers/L00-L10` są wyłącznie prezentacyjne i nie zawierają `CollisionObject2D`, `Area2D`, `CollisionShape2D` ani `CollisionPolygon2D`. Stała fizyka pochodzi z L05 przez kompilator, a dynamiczne bramy i obiekty gameplayowe pozostają jawnymi, odrębnymi rekordami manifestu i nie mutują bazowego kolidera.
- D7. Różnicowa paralaksa jest dozwolona wyłącznie na slotach jawnie oznaczonych jako nieblokujące tło lub foreground. L03-L07, każdy landmark związany z gameplayem oraz każda forma sugerująca ścianę, podłogę, portal lub otwór pozostają world-locked. `reduced_motion` ustawia różnicowe skale na `Vector2.ONE` bez usuwania warstw i pozwala odtworzyć ich zatwierdzone skale normalne.
- D8. Żadna warstwa nie może w fizycznie przechodniej wodzie sugerować nieistniejącej ściany, podłogi, zamkniętych drzwi ani innej trwałej blokady. Po zamrożeniu L05 manifest będzie wiązał assety strukturalne z kanonicznym digestem topologii, socketem i semantyczną maską bariery; techniczny overlap check nie zastępuje kontroli pełnego kompozytu i kadrów gameplayowych przez człowieka.
- D9. Surowy `manifest_sha256` służy wyłącznie świeżości sceny. `map_gameplay_signature` jest hashem kanonicznej projekcji wymiarów, topologii, stable ID, pozycji i gameplayu, bez kolorów, warstw i ścieżek prezentacji. `presentation_fingerprint` identyfikuje wygląd. Zmiana wyłącznie grafiki nie może sama unieważniać kampanii; zmiana L05 albo semantyki gameplayowej musi zmienić podpis gameplayu.
- D10. Rewizji nie wolno promować jako mapy kampanii, jeżeli zawiera wyłącznie stację albo nie publikuje sekwencji `junction_j7 -> archive_terminal -> r3_diagnostic_panel -> r3_generator -> c4_switchboard -> c4_splitter_mount`. Pozycje i przypisania tych urządzeń do landmarków należą wyłącznie do bieżącego manifestu. Dawne współrzędne oraz fizyczne ID `R1-09`, `R3-04` i `R4-06` nie odzyskują authority. Builder i kompilator walidują strukturę czterech etapów, sześć wymaganych ID, unikalność i referencje; smoke korzysta z produkcyjnego kompilatora bez utrzymywania drugiej listy rozmieszczenia. Żaden z nich nie wykonuje blokującego flood-fill, BFS, certyfikacji komórki, dystansu ani trasy. Rzeczywistą osiągalność L05 zatwierdza użytkownik przez ręczne przepłynięcie J-7 -> Archiwum -> R-3 -> C-4.
- Powód i skutek: format można rozwijać bez przepisywania dokumentacji przy każdej zmianie liczności, jeden kierunek zależności `manifest + wskazany payload L05 -> pochodne -> grafika -> scena runtime` usuwa rozjazd fizyki, pozycji i wyglądu, a elastyczność mapy nie odcina wymaganej ścieżki kampanii.

## MAP-ARD-0014 - Pakiet prawdy L05 wiąże kolider, prowadnice i grafikę

- Status / aktywny zakres: Częściowo zastąpiona; D1-D10 obowiązują poza szczegółem zagnieżdżonych pakietów struktur
- Zatwierdzenie: 2026-08-25
- Relacje: Zastępuje pierwsze zdanie MAP-ARD-0013 D1 i doprecyzowuje MAP-ARD-0013 D4-D9 | Częściowo zastąpiona przez: MAP-ARD-0022/D2-D4,D7-D8 w zakresie zagnieżdżonych pakietów struktur
- D1. Jeden manifest nie oznacza jednego pliku binarnego. `map_manifest.json` pozostaje jedynym semantycznym authority mapy i wskazuje dokładnie jeden aktywny payload topologii oraz zaakceptowane źródła grafiki. Payload i bitmapy są typowanymi plikami źródłowymi przypiętymi ścieżką, hashem zawartości i rewizją; nie są drugim manifestem, wariantem mapy ani sceną authority. Grafika strukturalna wiąże się z kanonicznym digestem topologii, a jawnie nieblokujące tło z rewizją prezentacji i kontekstem kompozycji. `UnderwaterMap.tscn` pozostaje wyłącznie deterministyczną pochodną.
- D2. Nazwa L05 ma dwa jawnie rozdzielone znaczenia. „Payload L05” jest maszynowym źródłem statycznego podziału `solid/open_water`, z którego kompilator tworzy fizykę. `VisualLayers/L05` jest world-locked korzeniem prezentacyjnym lub diagnostycznym i sam nigdy nie jest koliderem. Finalna ilustracja, linia podglądu ani węzeł wizualny nie mogą definiować fizyki.
- D3. Adapter odczytuje znaczenie wartości wyłącznie z aktualnego rekordu `collision_source.encoding`; agent nie zgaduje go z koloru podglądu ani historycznej referencji. Surowy SHA-256 potwierdza bajty pliku, natomiast kanoniczny digest topologii identyfikuje zdekodowaną maskę `solid/open_water` wraz z pełnym odwzorowaniem piksel-świat. Odwzorowanie jawnie zapisuje rozmiar, `world_units_per_pixel`, origin świata, kierunek obu osi, konwencję `pixel_center/pixel_edge` i regułę zaokrąglania; brak któregokolwiek pola blokuje produkcję, aby uniknąć odbicia osi lub przesunięcia o pół piksela. Z tej samej zweryfikowanej geometrii kompilator deterministycznie wyprowadza segmenty lub poligony fizyki, raster nawigacyjny, maski `solid` i `open_water`, pas graniczny, okludery/SDF oraz prowadnice grafiki.
- D4. Każde zadanie grafiki strukturalnej otrzymuje jeden aktualny pakiet prawdy: identyfikatory rewizji, SHA manifestu i pliku payloadu oraz kanoniczny digest topologii; pełnomapową prowadnicę; dokładny socket w pikselach i jednostkach świata wraz z finalnym transformem; maski `solid`, `open_water` i pasa granicznego; pełny kanoniczny rekord landmarku i kontekst sąsiadów; politykę docelowej warstwy; jeden zaakceptowany brief wizualny i — dla szerokiej mapy lub regionu — jeden niskoczęstotliwościowy master kompozycji na aktualnej prowadnicy; oraz jawnie oznaczone referencje wyłącznie stylistyczne. Master prowadzi styl, skalę i rytm, lecz nie redefiniuje topologii. Brak lub niezgodność któregokolwiek elementu blokuje generację produkcyjną. Pełnomapowa prowadnica jest pochodną authoringu offline, nie pojedynczą teksturą runtime; builder dzieli prezentację na sockety/chunki zgodne z limitami importu bez zmiany odwzorowania świata.
- D5. Wynik ImageGen jest propozycją prezentacji, nie źródłem geometrii. Zmiana lokalna używa najmniejszego wystarczającego socketu, aktualnego zaakceptowanego obrazu jako wejścia edycji, przezroczystego tła tam, gdzie wymaga go kompozycja, oraz jawnych list `zmień` i `zachowaj`. Prompt nie ma prawa przesuwać landmarku, zmieniać skali, otwierać lub zamykać przejścia ani dodawać elementów poza socketem; dokładność wymuszają deterministyczne maski, crop, transform i walidacja, a nie zaufanie do promptu.
- D6. Dawna mapa, panorama, screenshot, odrzucony wariant i historyczna karta mogą służyć wyłącznie jako oznaczona referencja stylu lub provenance. Nie mogą określać pozycji, kształtu kolidera, wejścia, socketu ani sąsiedztwa. W aktywnym pakiecie istnieje tylko jeden bieżący zestaw źródeł; nazwy `candidate`, `final`, `v2` i równoległe kopie nie tworzą alternatywnego authority.
- D7. Zmiana zdekodowanej geometrii `solid/open_water`, jej rozmiaru, odwzorowania lub znaczenia encodingu wymaga nowego `topology_revision`, kanonicznego digestu i `map_gameplay_signature`; unieważnia wszystkie pochodne kolizji oraz wszystkie grafiki strukturalne zależne od starej geometrii. Ponowny zapis pliku z innymi bajtami, ale identyczną kanoniczną geometrią, zmienia surowy SHA i świeżość źródła, lecz nie podpis gameplayu ani ważność grafiki strukturalnej. Zmiana pozycji lub socketu landmarku unieważnia jego kartę i zależne assety. Jawnie nieblokujące tło nie traci automatycznie ważności po zmianie topologii, ale wymaga ponownej kontroli pełnego kompozytu; obraz pokazujący konkretną krawędź, wejście lub pozycję landmarku jest na potrzeby invalidacji grafiką strukturalną. Zmiana wyłącznie wyglądu podnosi `presentation_revision` i fingerprint. Sam tekst etykiety rewizji nie jest dowodem zmiany topologii.
- D8. Zgodność jest sprawdzana symetrycznie: żaden piksel sklasyfikowany jako trwała struktura nie może wejść w chronioną maskę `open_water`, a każda stała krawędź kolidera musi mieć czytelne wsparcie wizualne w swoim pasie granicznym, aby nie wyglądała jak otwarte przejście. Tło paralaktyczne może istnieć za trasą tylko wtedy, gdy nie używa języka wizualnego bliskiej ściany, podłogi, zamkniętych drzwi lub innej blokady. Dynamiczne bramy mają osobne, zgodne stany grafiki i fizyki; nie wypieka się stanu zamkniętego w statyczne tło.
- D9. Warstwy L00-L09 są dziesięcioma aktywnymi slotami, a L10 jedenastym identyfikatorem zachowanym jako wyłączona rezerwa. Manifest deklaruje role, z-order i skale, a builder egzekwuje stałą macierz przestrzeni: `L01`, `L02`, `L08` i `L09` są różnicową paralaksą, natomiast `L00`, `L03`, `L04`, `L05`, `L06`, `L07` i rezerwowe `L10` są world-locked z jednostkową skalą. Każdy element komunikujący geometrię, landmark gameplayowy albo wejście może trafić wyłącznie do slotu world-locked. Zmiana tej macierzy wymaga nowej decyzji i walidatora, nie zwykłej edycji manifestu; slot paralaktyczny nie może sugerować alternatywnej topologii.
- D10. Produkcyjny authoring grafiki strukturalnej pozostaje zablokowany, dopóki builder nie obsługuje niepustego źródła kolizji L05, nie weryfikuje jego zawartości i surowego SHA, nie oblicza kanonicznego digestu topologii, nie generuje wspólnego pakietu prawdy oraz nie potrafi zrenderować typowanego `visual.assets`. Po odblokowaniu asset przechodzi kolejno kontrolę świeżości wejść, wymiarów/alfa/transformu, obu kierunków zgodności masek, pełnego kompozytu i kadrów gameplayowych. Zmiana topologii wymaga dodatkowo ręcznego przepłynięcia kampanii przez użytkownika; automatyczny BFS nie wraca jako bramka authoringu. `TECHNICAL_PASS` nie jest akceptacją artystyczną.
- Powód i skutek: model generatywny może tworzyć styl i detal, lecz nie pamięta wiarygodnie geometrii między wywołaniami. Jeden hash-pinned payload i jego deterministyczny pakiet prawdy utrzymują pozycje oraz kolider 1:1, a symetryczna kontrola usuwa zarówno fałszywe ściany, jak i niewidzialne kolizje.

## MAP-ARD-0015 - Widoczna grafika mapy nie używa pixel artu

- Status / aktywny zakres: Częściowo zastąpione; D1,D4-D5
- Zatwierdzenie: 2026-08-25
- Relacje: Uzupełnia MAP-ARD-0013 D4 i MAP-ARD-0014 D4-D10 | Zastąpiona przez: MAP-ARD-0016/D2,D6 oraz MAP-ARD-0017/D3
- D1. Widoczne bitmapy mapy używają spójnego realistycznego/rysunkowego języka 2D w rozdzielczości wystarczającej dla docelowego kadru. Pixel art, celowa pikseloza i `nearest` jako filtr prezentacyjny nie należą do języka tej mapy.
- D2. Każdy `CanvasItem` prezentujący bitmapę mapy jawnie ustawia filtrowanie liniowe odpowiednie do skali; nie dziedziczy projektowego domyślnego `nearest`. Shader jawnie deklaruje liniowe próbkowanie tekstury materiału. Zmiana globalnego filtra całej gry pozostaje poza lokalnym authority warsztatu.
- D3. Proporcja pikselowa źródła odpowiada proporcji finalnego `world_rect` albo renderer stosuje jawny, jednolity crop/overscan bez niejednostajnego rozciągania. Nie wolno dopasowywać grafiki do socketu przez niezależną zmianę skali X i Y ani przez ręczne skalowanie „na oko”.
- D4. Dane dyskretne są wyjątkiem technicznym, nie stylistycznym: payload, maska `solid/open_water`, raster nawigacyjny i inne semantyczne maski zachowują próbkowanie `nearest`, aby interpolacja nie przesuwała granicy kolidera. Materiał widoczny przez tę maskę nadal używa filtrowania liniowego.
- D5. Tło L01 może różnicowo poruszać się w poziomie, lecz każda panorama, której podstawa ma spotykać grunt L05, zachowuje pionowe zakotwiczenie w świecie i wspólną linię bazową. Obraz nie zawiera własnego pola wody, mgły, promieni, poświat ani jasnego prostokątnego tła; atmosfera pozostaje w Godot.
- D6. Odbiór techniczny sprawdza co najmniej rzeczywisty rozmiar i proporcję źródła, jawny filtr w wygenerowanej scenie, alfę oraz niezmienność podpisu gameplayu. Widoczna pikseloza, ściskanie proporcji, jasne plamy tła albo odklejenie podstawy od L05 odrzucają rewizję niezależnie od poprawnego hasha.
- Powód i skutek: mapa zachowuje gładki, jednolity kierunek realistycznego 2D, a dane kolizji nadal pozostają pikselowo dokładne. Jawne rozdzielenie filtrowania grafiki i maski usuwa pikselozę bez rozmywania lub przesuwania fizyki.

## MAP-ARD-0016 - Mapa dziedziczy globalny Linear i deklaruje tylko odmienne samplery

- Status / aktywny zakres: Obowiązuje; D1-D4
- Zatwierdzenie: 2026-08-25
- Relacje: Zastępuje MAP-ARD-0015/D2,D6 | Zastąpiona przez: brak
- D1. Zwykły `CanvasItem` wygenerowany dla widocznej bitmapy mapy dziedziczy projektowy domyślny `Linear` ustanowiony przez globalny ARD-0103. Builder nie emituje równoważnego lokalnego override, a warsztat nie utrzymuje drugiej reguły filtra całej gry.
- D2. Własny sampler shadera pozostaje jawny zgodnie z rolą danych: widoczny materiał gruntu używa `filter_linear`, a dyskretna maska topologii `filter_nearest`. Mipmapy są dozwolone wyłącznie po rzeczywistym wygenerowaniu ich w imporcie i przy uzasadnionym pomniejszaniu.
- D3. Lokalny smoke nie asertywuje powielonego `Linear` na każdym nodzie. Nadal sprawdza typ assetu, rzeczywisty rozmiar, proporcję, alfę, wiązanie maski, niezmienność podpisu gameplayu i techniczną spójność wygenerowanej sceny.
- D4. Widoczna pikseloza, niejednostajne rozciąganie, jasne plamy tła albo odklejenie podstawy od L05 nadal odrzucają rewizję w kontroli wzrokowej niezależnie od poprawnego builda i hasha.
- Powód i skutek: warsztat korzysta z jednego globalnego domyślnego filtra zamiast generować i testować jego kopie, zachowując precyzyjne próbkowanie maski oraz jawny kontrakt shaderów mapy.

## MAP-ARD-0017 - Wszystkie widoczne bitmapy zachowują natywną gęstość 1:1

- Status / aktywny zakres: Obowiązuje; D1-D6
- Zatwierdzenie: 2026-08-25
- Relacje: Zastępuje MAP-ARD-0015/D3 i zaostrza MAP-ARD-0016/D3-D4 | Zastąpiona przez: brak
- D1. Żaden widoczny asset bitmapowy w żadnym slocie L00-L10 nie może być powiększany, pomniejszany ani dopasowywany do socketu przez transform, `TextureRect`, shader, resize podczas postprocessingu lub niezależną bądź jednolitą zmianę skali osi. Węzeł zachowuje `scale = Vector2.ONE`, a zwykła bitmapa ma dokładnie `world_rect.size == pixel_size`: jeden piksel źródła odpowiada jednej jednostce świata.
- D2. Obszar większy od dostępnego wyniku źródłowego powstaje z grafiki wygenerowanej od razu we właściwej rozdzielczości albo z wielu różnych natywnych paneli ustawionych obok siebie. Crop i overscan są dozwolone wyłącznie bez resamplingu i bez zmiany gęstości pikseli. Brak odpowiedniego źródła blokuje integrację zamiast zezwalać na upscale lub downscale.
- D3. Jawnie kafelkowany materiał, taki jak widoczna tekstura gruntu L05, może się powtarzać, lecz każdy kafel zachowuje natywną gęstość: liczba powtórzeń wynosi dokładnie `world_rect.size / pixel_size`, dzięki czemu jeden texel nadal odpowiada jednej jednostce świata. Częściowy kafel na granicy prostokąta jest dozwolony; rozciągnięcie kafla nie jest.
- D4. Proceduralne pole bez bitmapy oraz dyskretne dane topologii z własnym jawnym odwzorowaniem piksel–świat nie udają grafiki prezentacyjnej i nie podlegają równaniu z D1. Zoom kamery, projekcja viewportu i przesunięcie paralaksy mogą zmieniać obraz końcowy na ekranie, ale nie mogą zmieniać authored mapowania ani skali węzła assetu.
- D5. Builder blokuje każdy zwykły bitmapowy `world_rect`, którego szerokość lub wysokość różni się od `pixel_size`, oraz generuje natywną liczbę powtórzeń materiału kafelkowanego. Smoke potwierdza rozmiar tekstury, prostokąt świata, jednostkowy transform i parametr UV materiału. Nowy typ bitmapy nie może wejść do rendererera bez równoważnej walidacji.
- D6. Provenance zapisuje rzeczywisty rozmiar każdego źródła, brak resamplingu oraz sposób rozmieszczenia paneli. Finalny odbiór wzrokowy nadal sprawdza ostrość, szwy, gęstość, zakotwiczenie i brak fałszywych przeszkód; poprawne mapowanie 1:1 nie jest samo w sobie akceptacją artystyczną.
- Powód i skutek: źródło ma być od początku odpowiednie do docelowego użycia. Zakaz wszelkiego skalowania usuwa pikselozę, rozmycie i deformacje, a natywne panele oraz kafle pozwalają rozwijać duży świat bez utraty jakości i bez zmiany kolidera.

## MAP-ARD-0018 - Niezależne elementy wizualne powstają po akceptacji proxy w scenie

- Status / aktywny zakres: Częściowo zastąpiona; D1-D10 obowiązują poza prywatnymi źródłami zagnieżdżonego pakietu struktury
- Zatwierdzenie: 2026-08-25
- Relacje: Doprecyzowuje MAP-ARD-0013 D3-D4, MAP-ARD-0014 D4-D5 i MAP-ARD-0017 D1-D2 | Częściowo zastąpiona przez: MAP-ARD-0022/D1-D7 w zakresie prywatnych źródeł pakietu struktury
- D1. Najmniejszą jednostką authoringu jest element, który użytkownik ma móc niezależnie przesunąć, usunąć, wymienić albo poprawić. Każdy taki budynek, prop lub mały nierozdzielny klaster otrzymuje osobny stabilny identyfikator wizualny i osobny rekord w tym samym `map_manifest.json`. Liczba elementów wynika wyłącznie z bieżącego manifestu i nie jest zamrażana w dokumentacji ani builderze.
- D2. Manifest jest właścicielem przypisania elementu do warstwy i grupy, pozycji, natywnego rozmiaru, źródła, SHA, aktywności oraz roli prezentacyjnej. Builder tworzy pod każdym właściwym rootem warstwy neutralną grupę organizacyjną i umieszcza w niej osobne elementy; grupa, jej ścieżka i scena pochodna nie przejmują authority manifestu. `UnderwaterMap.tscn` nadal nie podlega ręcznemu rozmieszczaniu.
- D3. Pełnoszeroka panorama albo panel zawierający kilka budynków, które mogą wymagać osobnej korekty, nie może być produkcyjną jednostką runtime. Może istnieć wyłącznie jako nieautorytatywny master kompozycji albo guide. Mały klaster jest jednym elementem tylko wtedy, gdy świadomie ma zawsze poruszać się i być wymieniany jako całość.
- D4. Prosty element bitmapowy jest zwykle jednym przezroczystym PNG w natywnej wielkości. Bardzo duży lub złożony budynek może być jednym elementem złożonym z kilku natywnych części, prefabów albo materiału powtarzanego przy dokładnie jednym texelu na jednostkę świata. Root elementu i wszystkie zwykłe bitmapy zachowują skalę `Vector2.ONE`; grupowanie nigdy nie jest zgodą na skalowanie rodzica lub potomków.
- D5. Przed produkcyjnym ImageGen builder musi umieć wyrenderować w dokładnie wygenerowanym `UnderwaterMap.tscn` lekkie proxy wszystkich planowanych elementów na podstawie ich docelowych prostokątów. Użytkownik zatwierdza na proxy skalę, wysokości, szerokości, odstępy, pokrycie, linię bazową i relację L01/L02 zarówno w pełnym widoku mapy, jak i w reprezentatywnym kadrze gameplayowym. Dopiero zaakceptowany prostokąt staje się niezmiennym wejściem generacji elementu.
- D6. ImageGen nie ustala położenia ani skali elementu. Wynik ma od początku pasować do zaakceptowanego natywnego prostokąta i widocznej obwiedni. Jeżeli narzędzie nie potrafi dostarczyć wymaganej rozdzielczości, wynik jest odrzucany albo budynek zostaje zaplanowany jako element modułowy z kilku natywnych części; nie wolno ratować go resize'em, transformem ani ponownym spłaszczeniem kilku niezależnych obiektów.
- D7. L01 i L02 mają osobne grupy oraz osobne iteracje odbioru. L01 zawiera dalsze, spokojniejsze elementy, L02 bliższe i czytelniejsze; obie warstwy pozostają nieblokujące i nie przedstawiają wejść, drzwi, podłóg ani koliderów. Najpierw zatwierdza się i integruje jedną warstwę, następnie drugą, a ich wspólny odbiór nie zastępuje odbioru każdego planu osobno.
- D8. Po integracji jednego elementu albo małej jawnej partii builder, `--check` i smoke potwierdzają identyfikatory, grupę, natywny rozmiar, jednostkowe transformy i aktualne źródło. Następnie agent obowiązkowo ogląda faktyczny render tej samej `UnderwaterMap.tscn`; dopiero ta pętla pozwala przejść do kolejnego elementu. Pełny strip, statyczny contact sheet i zgodny hash pozostają pomocnicze i nie mogą zatwierdzić kompozycji zamiast sceny.
- D9. Każda warstwa deklaruje w manifeście sześciocyfrowe `rgb_modulate`, które renderer stosuje na jej rootcie z alfą zawsze równą `1.0`. Korekcja służy do rozdzielania głębi kolorem — na przykład ciemniejszego L01 — bez półprzezroczystości całej warstwy, przenikania budynków ani globalnego filtra postprocess. Przezroczystość poza bryłą nadal pochodzi wyłącznie z alfy pojedynczego assetu.
- D10. Wyłącznie jawnie nieblokujące, dalekie plany `L01` i `L02` używają polityki `nonblocking_backdrop_may_overlap_open_water`. Mogą one świadomie przebiegać wizualnie nad otwartą wodą — także nad przyszłym lub bieżącym zejściem parkingowym — ale nigdy nie są koliderem, wejściem, podłogą, ścianą, trasą, landmarkiem ani wskazówką gameplayową. Wszystkie pozostałe warstwy zachowują politykę `no_visual_blockage_in_protected_water`; L05 pozostaje jedynym authority makroterenu. Wyjątek nie zezwala na wypiekanie przeszkody w wodzie ani na zmianę L05 przez grafikę.
- Powód i skutek: najpierw rozstrzygamy tanią, mierzalną kompozycję, a ImageGen dostarcza wyłącznie wygląd zaakceptowanych elementów. Błędny budynek można wymienić bez regenerowania panoramy, zmiana liczności nie rozbija pipeline'u, a skala nie jest już zgadywana dopiero po wstawieniu całego pasa do gry.

## MAP-ARD-0019 - Wchodnie struktury są lokalnymi, przenośnymi instancjami jednego authority L05

- Status / aktywny zakres: Zastąpiona w całości; brak aktywnego zakresu
- Zatwierdzenie: 2026-08-25
- Relacje: Zastępuje MAP-ARD-0013/D5-D6 w zakresie formatu payloadu i właściciela pochodnych colliderów; doprecyzowuje MAP-ARD-0014/D2-D4,D7-D10 i MAP-ARD-0018/D1-D8 | Zastąpiona w całości przez: MAP-ARD-0022
- D1. Manifest schema v5 publikuje typowane `structures.templates` i `structures.instances`. Szablon ustanawia rodzaj struktury, logiczne role L04/L05 i dozwolone rodzaje socketów, natomiast instancja jest właścicielem stable ID, jednego `origin`, rozmiaru, opcjonalnego `landmark_id`, aktywności, digestów i lokalnych socketów. Neutralna instancja nie musi wskazywać landmarku; jeżeli pole istnieje, musi wskazywać istniejący rekord. Pierwszy wieżowiec nie ustanawia limitu liczności, liczby pięter ani układu kolejnych instancji.
- D2. Aktywny payload `l05_owned_rect_ops_v2` zachowuje jeden raster `solid/open_water`, ale rozróżnia operacje globalne `world_px` i lokalne `structure_local_px`. Lokalny prostokąt wskazuje `structure_id`, a builder transformuje go wyłącznie przez wyrównany do siatki origin instancji. `solid_rect` przypisuje właściciela, `open_rect` czyści komórkę i właściciela, a ostatnia operacja nadal wygrywa.
- D3. `canonical_digest` identyfikuje zdekodowaną globalną geometrię wraz z mapowaniem, a `partition_digest` związek każdej stałej komórki z `world` albo konkretną strukturą. Surowy SHA zabezpiecza payload. Zmiana właściciela przy identycznej geometrii unieważnia partycję colliderów i cache, nawet jeśli sam canonical digest pozostaje bez zmian.
- D4. Builder generuje top-level `StructureRoots`, a pod nim dokładnie jeden root każdej włączonej instancji w pozycji `origin`, ze skalą `Vector2.ONE`. Root grupuje lokalną prezentację wnętrza w logicznej roli L04, dokładne techniczne wsparcie bryły L05, `StaticCollision`, `DynamicBodies` i `Interactives`. Wygenerowana scena pozostaje pochodną; przesunięcie odbywa się wyłącznie przez manifest i rebuild.
- D5. `VisualLayers/L00-L10` nadal nie zawierają fizyki. Prezentacja umieszczona pod `StructureRoot` dziedziczy world-locked politykę i z-order właściwego slotu przez typowany rekord oraz metadata, ale wspólny root ma pierwszeństwo przed fizycznym rozdzieleniem dzieci do niezależnych gałęzi sceny. L01 i L02 pozostają niezmienionym, nieblokującym tłem za strukturą.
- D6. Jeden globalny raster nawigacji pozostaje wspólną prawdą przechodniości. Segment granicy należy do stałej komórki po drugiej stronie otwartej wody: `world` trafia tylko do streamowanych chunków globalnych, a stable ID struktury tylko do lokalnego `StaticBody2D`. Po transformacji rootem unia wszystkich partycji musi być dokładnie pełną granicą L05, a przecięcie dowolnych dwóch partycji musi być puste.
- D7. Rekord mapowy zakotwiczony w strukturze przechowuje `structure_id`, `position_space=structure_local` i lokalną pozycję. Kompilator wylicza globalny punkt dla konsumentów root, a runtime mapy rodzicuje obiekt pod `Interactives`; po przeniesieniu rootu nie aktualizuje się osobno pozycji żadnego dziecka. Znaczenie trwałego stanu, zapis, reset próby i cykl życia obiektu pozostają kontraktem root opisanym w `../../.ai/DECISIONS.md` oraz `../../docs/Ostatni_Pomost_architektura_Godot.txt`; lokalne MAP-ARD określa wyłącznie mapowanie przestrzenne.
- D8. Statyczny root struktury nie porusza się podczas rozgrywki. Ruchoma kabina windy, drzwi i zmienne bramy są osobnymi obiektami pod `DynamicBodies`, z własną grafiką i fizyką, a deskryptory interakcji znajdują się pod `Interactives`; nie są częścią statycznej maski zamkniętej. Warsztat mapy publikuje ich lokalną geometrię, sockety i typowane deskryptory. Reguły progresji, bezpieczeństwa, wejścia gracza oraz czasu życia stanu należą do właściwych systemów root zgodnie z globalną architekturą.
- D9. Po zaakceptowaniu proxy produkcyjna grafika pierwszej struktury jest parą natywnych bitmap `2240 × 3680` przy dokładnym mapowaniu 1:1 i `scale=Vector2.ONE`. L04 jest wycinane dokładną lokalną maską `open_water`, a L05 dokładną lokalną maską stałych komórek ownera struktury; oba źródła są hash-pinned i związane z aktualnymi digestami topologii i partycji. Zwykła iteracja jednego wieżowca korzysta z lokalnej prowadnicy, masek i 22 kart socketów. Pełny raster mapy służy dopiero końcowemu sprawdzeniu integralności. Wynik generatora obrazu o innej rozdzielczości lub bez wymaganej alfy pozostaje wyłącznie referencją stylu i nie może zostać przeskalowany do slotu.
- D10. Builder, kompilator i smoke sprawdzają schema, referencje, wyrównanie do siatki, lokalne granice i maski, hashe assetów, digest partycji, jednostkowe transformy, pełny root, deskryptory runtime oraz dokładną, rozłączną unię colliderów. Osobny test runtime przechodzi sekwencję, ruch windy, drzwi, skróty, blokady bezpieczeństwa i reset próby, a natywny capture pokazuje stan początkowy, środek przejazdu oraz stan ukończony w rzeczywiście wygenerowanej scenie. Żaden test nie dodaje blokującego BFS; po zmianie topologii użytkownik nadal ręcznie przepływa wymaganą trasę kampanii, cały budynek i powrót.
- Powód i skutek: lokalna geometria, grafika, urządzenia i interakcje pozwalają przenieść kompletny wieżowiec jedną zmianą originu, a osobny digest właścicieli zapobiega dublowaniu jego collidera przez globalny teren. Lokalny obszar authoringu daje precyzję bez codziennego przeliczania całej mapy, a aktywny typowany kontrakt tworzy powtarzalny fundament dla kolejnych budynków.

## MAP-ARD-0020 - L00 jest ostatecznym, jednolitym tłem mapy

- Status / aktywny zakres: Obowiązuje; D1-D8
- Zatwierdzenie: 2026-08-26
- Relacje: Doprecyzowuje MAP-ARD-0013/D4-D6, MAP-ARD-0014/D2,D8-D9 i MAP-ARD-0017/D4 | Zastąpiona przez: brak
- D1. `VisualLayers/L00` jest najdalszym, prawdziwym tłem konkretnej mapy. Builder generuje pod nim dokładnie jeden produkcyjny `Water: Polygon2D`, zaczynający się w originie, o jednostkowym transformie, czterech wierzchołkach prostokąta świata i nieprzezroczystym kolorze `visual.water_color`. Jawnie włączona siatka diagnostyczna może istnieć wyłącznie jako authoringowy sibling `Grid`; aktywny baseline utrzymuje ją wyłączoną.
- D2. Rekord L00 zachowuje `role=water_base`, `space=world_locked`, `parallax_scale=[1,1]`, `rgb_modulate=ffffff`, `enabled=true`, `reserved=false`, `geometry_role=none` oraz `affordance_policy=no_visual_blockage_in_protected_water`. L00 nie jest physics layer, koliderem, okluderem, landmarkiem, wejściem ani właścicielem stanu.
- D3. Jedynym parametrem koloru konsumowanym przez L00 jest sześciocyfrowe, nieprzezroczyste `visual.water_color`. Obecność innego pola palety w manifeście nie nadaje mu automatycznie znaczenia L00 i nie zezwala na gradient, podział regionów albo drugą krzywą głębokości bez nowej decyzji.
- D4. L00 nie odczytuje payloadu, maski `solid/open_water`, canonical digestu, partition digestu ani assetów L05. Kolor, materiał i krawędzie skały lub ziemi należą do maskowanego materiału L05; ewentualne ocieplenie gruntu do brązu jest zmianą L05 i nie tworzy brązowej kopii podłoża pod L00.
- D5. Efekty wodnego medium obejmujące cały wyrenderowany świat — ambient głębokości, światło latarki, refrakcję, zamglenie, caustics, promienie i cząstki — pozostają ogólną prezentacją `UnderwaterEnvironment2D` i `LightSystem` w korzeniu projektu. Nie są dziećmi L00 ani pełnomapowym, nieprzezroczystym assetem L05-L09. Lokalne sloty mapy mogą później otrzymać wyłącznie własne, typowane i nieblokujące detale zgodne z ich rolą.
- D6. L00 nie przyjmuje bitmapy, wpisu `visual.assets`, materiału, shadera, animacji, alfy, paralaksy ani wyniku ImageGen. Jego proceduralny prostokąt nie podlega mapowaniu bitmap 1:1, ale zachowuje jednostkowy transform i pełne wymiary świata.
- D7. Builder i kompilator odrzucają zmianę tożsamości, przestrzeni, geometrii, polityki, aktywności, modulacji albo przezroczystości L00. Dokładny produkcyjny node i jego równoważność w runtime zostały odebrane jednorazowym testem celowanym. Dedykowane asercje i fixture'y L00 nie należą do stałego smoke'a i po odbiorze są usuwane, aby kolejne zmiany zawartości mapy nie ponosiły ich kosztu.
- D8. Zmiana wyłącznie `water_color` jest zmianą prezentacji: wymaga aktualizacji `presentation_revision`, builda, `--check` i oględzin rzeczywistej sceny, lecz nie zmienia `topology_revision`, podpisu gameplayu, zapisu ani grafiki gruntu. Tylko przy ponownym otwarciu kontraktu L00 wykonuje się celowany test odbiorczy, który nie pozostaje w codziennym zestawie. Bez jawnej zmiany koloru L00 uznaje się za zakończone i nie rozwija się go razem z kolejnymi budynkami, terenem lub efektami środowiska.
- Powód i skutek: jednolite pole gwarantuje tani, zawsze obecny kolor za otwartą wodą i odbiera wspólną modulację środowiska, natomiast wszystkie elementy wymagające geometrii, głębi sceny albo dynamicznego działania pozostają u właściwych właścicieli. L00 nie konkuruje dzięki temu z L05, postprocessem ani równoległą pracą nad zawartością mapy.

## MAP-ARD-0021 - Avatar gracza jest zewnętrznym konsumentem mapy

- Status / aktywny zakres: Obowiązuje; D1-D5
- Zatwierdzenie: 2026-08-26
- Relacje: Uszczegóławia globalny ARD-0105 oraz MAP-ARD-0022/D5-D10 | Zastąpiona przez: brak
- D1. Warsztat mapy nie jest właścicielem sceny, fizycznej bryły, grafiki, animacji, socketów, shaderów ani VFX avatara gracza. Jedynym authority tych elementów jest sąsiedni `diver_workbench/`.
- D2. Mapa pozostaje właścicielem topologii, statycznych i dynamicznych przeszkód świata, okluderów, grafik mapowych oraz mapowych rekordów obiektów. Avatar konsumuje te granice przez `DiveScene` i ogólne systemy root; żaden warsztat nie kopiuje źródeł drugiego.
- D3. Lokalny smoke mapy nie ładuje warsztatu nurka ani nie zamraża jego węzłów, arkuszy, profilu socketów czy wymiarów. Złożenie mapy z publiczną sceną avatara sprawdza test integracyjny w root; nie staje się ono drugim testem prezentacji nurka.
- D4. Zmiana avatara nie podnosi rewizji manifestu, topologii ani prezentacji mapy. Jeżeli zmienia osiągalność, kontakt ze ścianą, przejście przez budynek albo zachowanie światła względem okluderów, wymaga proporcjonalnego testu integracyjnego i ręcznego przepłynięcia, ale nadal nie przenosi authority do mapy.
- D5. Worldowe grafiki interakcji i obiektów powiązanych z manifestem pozostają w mapie. Żaden plik pod `assets/gameplay/` nie może być kopią avatara ani jego aktywnego źródła animacji.
- Powód i skutek: agent mapy może zmieniać świat bez przypadkowego rozwijania postaci, a agent nurka może kalibrować avatar na prawdziwych koliderach i okluderach bez tworzenia drugiej mapy.

## MAP-ARD-0022 - Wchodnie struktury są podrzędnymi pakietami jednego authority placementu mapy

- Status / aktywny zakres: Obowiązuje; D1-D10
- Zatwierdzenie: 2026-08-26
- Relacje: Zastępuje MAP-ARD-0019 w całości oraz MAP-ARD-0013/D1,D3,D5,D9, MAP-ARD-0014/D1,D3-D4,D7,D10 i MAP-ARD-0018/D1-D8 w zakresie zagnieżdżonych pakietów struktur; uszczegóławia globalny ARD-0106 | Zastąpiona przez: brak
- D1. Każda wchodnia struktura z własnym runtime jest jednym katalogiem `structures/<structure_id>/`. Stable ID i mapowa tożsamość należą do pojedynczego rekordu `structures.instances` w `map_manifest.json`, a nazwa katalogu musi być mu równa. `structure_manifest.json` nie powtarza pola `structure_id`; folder i dokładnie jedna mapowa referencja wiążą pakiet z instancją.
- D2. Rekord instancji mapowej posiada wyłącznie stable ID, jeden wyrównany do siatki `origin`, aktywność, opcjonalny `landmark_id` oraz rekord pakietu ze względną ścieżką i surowym SHA-256. Lokalny rozmiar, template, topologia, sockety, grafika, skrypty i runtime nie mogą pozostawać w mapowym rekordzie jako druga kopia.
- D3. `structure_manifest.json` schema v1 jest jedynym edytowanym źródłem lokalnego rozmiaru, szablonu, operacji kolizji, socketów, assetów wizualnych, prywatnych skryptów, konfiguracji runtime, cyklu życia próby i jawnie nieautorytatywnego provenance. Wszystkie współrzędne są lokalne. Pakiet nie zawiera globalnego originu, mapowego landmarku, kampanii ani trwałego stanu.
- D4. Ścieżki `assets`, `generated`, `runtime`, `tests` i `references` są względne wobec katalogu pakietu. Nie mogą używać `..`, wskazywać prywatnego pliku innej struktury ani utrzymywać kopii pliku root lub Nurka. Plik provenance może pozostać wyłącznie z `authority=false`; lista wykluczonych tematów nie czyni go kontraktem gameplayu.
- D5. Globalny payload L05 przechowuje wyłącznie operacje świata. Lokalne operacje `solid_rect/open_rect` struktury istnieją tylko w jej `collision` i po walidacji są transformowane mapowym originem. Builder składa je w jeden raster `solid/open_water`; każda stała komórka i krawędź należy dokładnie do `world` albo jednej aktywnej struktury, bez fallbacku dublującego collider.
- D6. Builder generuje dokładnie jeden `StructureRoot` aktywnej instancji, ze skalą `Vector2.ONE`, oraz grupuje pod nim lokalną prezentację L04/L05, `StaticCollision`, `DynamicBodies` i `Interactives`. `VisualLayers/L00-L10` pozostają bez fizyki. Root struktury nie porusza się podczas sesji, a jego mapowy origin jest jedyną transformacją globalną.
- D7. Prywatny kontroler, panel, interakcje, lokalne testy i assety pierwszego wieżowca należą wyłącznie do jego pakietu. Skrypty pakietu nie publikują globalnego `class_name`; ogólny runtime rozwiązuje ich hash-pinned ścieżki z manifestu i montuje kontroler bez preloada ścieżki pierwszego budynku, ID kontraktu albo prywatnej klasy w root. Publiczne zależności Rootu i Nurka są konsumowane bez kopiowania ich źródeł.
- D8. `attempt_state.persistence` i `attempt_state.checkpoint` mają wartość `none`; świeża instancja i reset próby przywracają stan początkowy całego budynku. Pakiet nie publikuje checkpointu, lokalnego respawnu, `persistent_id`, mutacji `DiveSessionState`, `WorldDelta` ani kampanii. Ta deklaracja techniczna nie jest drugą specyfikacją reguły gracza.
- D9. Freshness wygenerowanej sceny obejmuje map manifest oraz hash-pinned manifesty i źródła wszystkich aktywnych pakietów. Schema mapy v6 składa tę zależność przy zachowaniu `map_source_version = 5`. Czyste przeniesienie identycznej semantyki do pakietu zachowuje `map_gameplay_signature`; zmiana lokalnej geometrii, socketu, runtime, stable ID albo originu zmienia podpis, a sama grafika tylko fingerprint prezentacji.
- D10. Każdy pakiet posiada dokładnie lokalne `AGENTS.md` i operacyjny `README.md`, bez własnego `.ai`, MAP-ARD ani kopii produktu. Prywatny loop używa celowanego refresh/build/check jednej struktury oraz jej testu kontraktu i runtime. Pełny mapowy build/check i smoke sprawdzają rejestrację, hashe, kompozycję L05 i scenę dopiero przy rejestracji, zmianie originu, publicznym montażu albo przed odbiorem integracyjnym; nie są kosztem każdej prywatnej iteracji. Root sprawdza granice publiczne i brak persistence, a boundary test katalog, dokumenty i jednoznaczną referencję. Capture i ręczny playtest pozostają osobnymi bramkami grafiki oraz osiągalności.
- Powód i skutek: cały lokalny authoring jednego budynku jest skupiony obok jego runtime i testów, ale tylko mapa decyduje, czy i gdzie instancja istnieje. Usuwa to ręczne kopiowanie socketów, grafiki i zachowania do mapowego rekordu, zachowując jedną globalną fizykę, jedno położenie i brak ukrytego zapisu.

## MAP-ARD-0023 - Dalekie plany są rezydentne dla okna kamery, a survey i detal nie tworzą drugiej mapy

- Status / aktywny zakres: Obowiązuje; D1-D10
- Zatwierdzenie: 2026-08-26
- Relacje: Doprecyzowuje MAP-ARD-0013/D4-D9, MAP-ARD-0014/D2-D4,D8-D10, MAP-ARD-0015/D1-D6, MAP-ARD-0017/D1-D4 i MAP-ARD-0022/D5-D10 | Zastąpiona przez: brak
- D1. Produkcyjne bitmapy nieblokujących planów L01 i L02 są deskryptorami sceny ładowanymi przejściowo dla rzeczywistego okna kamery. Wygenerowana scena nie wiąże ich jako stałych `Texture2D`; zachowuje natomiast kanoniczną ścieżkę zasobu, hash źródła, natywny prostokąt, warstwę, paralaksę i transform przy skali `Vector2.ONE`.
- D2. Selekcja widoczności używa faktycznej transformacji canvas elementu oraz bieżącego viewportu. Profil Mapy posiada walidowane marginesy prefetch i retencji, limit równoległych żądań, limit commitów oraz budżet unikalnych pikseli. Retencja tworzy histerezę, ale nie rozpoczyna nowego ładowania.
- D3. Ładowanie odbywa się asynchronicznie, deduplikuje kanoniczną ścieżkę i zawsze doprowadza rozpoczęte żądanie do stanu terminalnego. Nieaktualny wynik zostaje odebrany i porzucony; błąd pozostaje lepki do ponownej konfiguracji, aby nie tworzyć pętli ponowień. Wszystkie przypięcia i odpięcia tekstur odbywają się na głównym wątku.
- D4. Zasób wymagany przez widoczny kadr ma pierwszeństwo przed budżetem. Po usunięciu mniej ważnych zasobów może wystąpić jawnie raportowany overcommit zamiast pustego fragmentu kadru. Prefetch nie może sam przekroczyć budżetu, a telemetria rozróżnia liczbę zasobów, unikalne piksele, żądania w toku, brakujące elementy widoczne, błędy, eksmisje i szacunkowe bajty RGBA8; szacunek nie jest pomiarem VRAM.
- D5. Rezydencja jest wyłącznie stanem prezentacyjnym sesji. Nie trafia do manifestu semantyki świata, `WorldBlueprint`, `WorldDelta`, `GameState`, zapisu, migracji ani `map_gameplay_signature`; zmiana profilu nie podnosi schema, source version ani topology revision.
- D6. Publiczny plan visual survey powstaje dynamicznie z bieżącego manifestu oraz kanonicznej projekcji nawigacji. Obejmuje wszystkie aktualne landmarki, geometrycznie wykryte wejścia struktur z obu stron, pionowe sektory świata, duże przerwy kompozycji L01/L02 jako cele oględzin oraz kafelki overview. Nie zamraża liczby obiektów, współrzędnych, prywatnych socketów, rodzajów budynków ani hierarchii sceny Nurka.
- D7. Identyfikator celu survey może zawierać wyłącznie nieprzezroczysty, deterministyczny klucz diagnostyczny. Duża przerwa obrazu jest celem inspekcji, nie automatycznym błędem topologii. Capture potwierdza techniczną kompletność kadru i zapisuje telemetrię, ale nie zastępuje odbioru artystycznego, testu osiągalności ani ręcznego przepłynięcia.
- D8. Overview składa się z kadrów renderowanych w zwykłym oknie rezydencji. Jednorazowe oddalenie kamery do rozmiaru całego świata nie jest dopuszczalnym dowodem budżetu i nie może wymuszać jednoczesnego ładowania wszystkich L01/L02.
- D9. World-locked detal L05 może różnicować odsłoniętą krawędź gruntu, szwy właścicieli oraz generyczne obramowanie geometrycznie rozpoznanego wejścia. Maska jest deterministyczną pochodną globalnego rastra `solid/open_water` i mapowania ownerów; nie odczytuje prywatnego rodzaju, nazwy ani stanu budynku.
- D10. Detal L05 i właścicielskiej grafiki struktury modyfikuje wyłącznie RGB wewnątrz kanonicznej maski stałej bryły lub ownera. Nie może dorysować alfy w otwartej wodzie, utworzyć collidera, przesunąć wejścia, zasugerować interakcji, zmienić przechodniości, partycji ani podpisu gameplayu. Zmiana wymaga build/check, smoke, natywnego capture i oględzin rzeczywistej sceny.
- Powód i skutek: mapa utrzymuje duże bitmapy tylko tam, gdzie mogą wejść do kadru, a jednocześnie zachowuje kompletność obrazu, reprodukowalny odbiór i wspólny język styku miasta z gruntem bez tworzenia drugiego źródła geometrii lub stanu gry.

## MAP-ARD-0024 - Historyczna promocja Mapy z integratorem i wspólnym lockiem

- Status / aktywny zakres: Historyczna; zastąpiona w całości przez MAP-ARD-0026
- Zatwierdzenie: 2026-08-26
- Relacje: Historycznie doprecyzowywała MAP-ARD-0013, MAP-ARD-0014, MAP-ARD-0022 i globalny ARD-0108 | Zastąpiona przez: MAP-ARD-0026
- D1. Wpis historycznie wymagał integratora Mapy, wspólnego locka, CAS, FROZEN kopii i osobnego protokołu odbioru. Mechanizmy te nie są już kontraktem pracy autora.
- Powód i skutek zastąpienia: MAP-ARD-0026 zachowuje dokładny hash sealed manifestu i spójne pochodne, ale przenosi szczegóły publikacji do wnętrza buildera oraz pozostawia autorowi zwykłą zmianę, lokalne testy i PR.

## MAP-ARD-0025 - Przechodnie wejście struktury czyści fałszywą ścianę dalekiego tła

- Status / aktywny zakres: Obowiązuje; D1-D6
- Zatwierdzenie: 2026-08-27
- Relacje: Doprecyzowuje MAP-ARD-0013/D7-D9, MAP-ARD-0014/D8-D9, MAP-ARD-0018/D7,D10 i MAP-ARD-0023/D6-D10 | Zastąpiona przez: brak
- D1. Builder wyprowadza dokładnie jeden `portal_backdrop_clearance` z każdego ciągłego runu komórek na granicy aktywnej struktury, dla którego komórka bezpośrednio po stronie wnętrza i komórka bezpośrednio po stronie zewnętrznej są `open_water`. Run zamknięty po którejkolwiek stronie nie tworzy clearance'u. Źródłem jest wyłącznie kanoniczny raster, koperta struktury i odwzorowanie piksel–świat; prywatny socket, typ budynku, stable ID, nazwa, ścieżka albo stan runtime nie uczestniczą w detekcji.
- D2. Clearance jest world-locked prezentacją hostowaną pod L04, ale używa jawnego globalnego z-orderu większego niż oba nieblokujące plany L01/L02 i mniejszego niż L03 oraz L04. Wypełnia rdzeń kolorem `visual.water_color`, a na ograniczonym rasterowym marginesie przechodzi do ciemniejszego, nadal w pełni nieprzezroczystego odcienia tego koloru. Feather używa pełnych kolorów wierzchołków wyprowadzonych z `visual.water_color` przy neutralnym białym kolorze bazowym `Polygon2D`; nie używa białych mnożników na ciemnym kolorze bazowym, bo taka reprezentacja jest zależna od semantyki renderera i tworzy jasną ramę. Wielkość rdzenia, padding wzdłuż otworu, feather i zewnętrzny tint są dodatnimi, wersjonowanymi stałymi kontraktu buildera; nie wynikają z ID ani ręcznego strojenia pojedynczego pakietu.
- D3. Tożsamość każdego clearance'u i zbiorczy digest są SHA-256 kanonicznej projekcji geometrii komórkowej: osi granicy, współrzędnej granicy, początku i końca runu, kierunku zewnętrznego oraz skali komórki. Zmiana wyłącznie ID, nazwy pakietu, ścieżki, template'u albo prywatnego socketu przy tej samej geometrii daje byte-identyczny fragment prezentacji i te same digesty.
- D4. `PortalBackdropClearances` i wszystkie jego dzieci są wyłącznie `Node2D`/`Polygon2D`. Nie zawierają `Area2D`, obiektu kolizji, shape'u, sygnału, interakcji ani stanu. Nie zmieniają rastra, colliderów, owner partition, topologii, `map_gameplay_signature`, osiągalności, persistence ani zachowania struktur; zmieniają wyłącznie fingerprint prezentacji.
- D5. Runtime i smoke odrzucają brak typowanego rootu, złą kolejność z, niekanoniczny digest, prywatne pola w projekcji geometrii, inną liczbę dzieci niż raster-derived runów, nieograniczony margines, nieaktualny tint, inny niż neutralny biały kolor bazowy featheru, kolor wierzchołka niewyprowadzony z `visual.water_color`, alfę inną niż `1.0` albo dowolny węzeł fizyki. Test buildera porównuje byte-identyczną prezentację po losowej zmianie prywatnych identyfikatorów oraz przypadek wejścia zamkniętego.
- D6. Techniczny build/check i capture nie stanowią samodzielnej akceptacji obrazu. Po każdej zmianie kontraktu trzeba obejrzeć oba kierunki każdego wejścia w rzeczywiście wygenerowanej `UnderwaterMap.tscn`; clearance jest przyjęty dopiero wtedy, gdy tło L01/L02 nie czyta się już jak fizyczna ściana, nie powstaje jasne prostokątne halo, a L04/L05 nadal jednoznacznie pokazują właściwą konstrukcję i otwartą wodę.
- Powód i skutek: realistyczna fasada dalekiego planu może legalnie leżeć za otwartą wodą, ale bez lokalnego oddechu wizualnie zamyka wejście. Geometryczny clearance usuwa tę fałszywą informację bez uczenia wspólnego buildera nazw konkretnych wieżowców i bez przenoszenia grafiki tła do prywatnego pakietu.

## MAP-ARD-0026 - Historyczna osobna granica pakietu struktury i mapowego pinu

- Status / aktywny zakres: Historyczna; zastąpiona w całości przez MAP-ARD-0027
- Zatwierdzenie: 2026-08-28
- Relacje: Zastępuje MAP-ARD-0024; doprecyzowywała MAP-ARD-0013/D1-D3,D8-D9, MAP-ARD-0014/D7-D10 i MAP-ARD-0022/D1-D3,D7-D10; stosowała globalny ARD-0113 | Zastąpiona przez: MAP-ARD-0027
- D1. `structures/<id>/structure_manifest.json` pozostaje authority prywatnych źródeł pakietu. `--seal-structure-package <id>` może zaktualizować wyłącznie jego lokalne hashe i digesty; nie zapisuje `map_manifest.json`, `UnderwaterMap.tscn`, L05, mapowych metadanych ani innego pakietu.
- D2. Prywatne `--build-structure <id>` i `--check-structure <id>` rozwiązują tylko wskazany pakiet oraz wymagane publiczne kontrakty. Nie odkrywają ani nie zapisują innych struktur lub authority Mapy.
- D3. Mapa przypina pakiet wyłącznie przez dokładny SHA-256 sealed manifestu. `--refresh-structure-package` aktualizuje mapowy pin i pochodne deklaracje złożenia, ale nigdy prywatny manifest ani źródła pakietu.
- D4. Zmiana prywatnego pakietu i zmiana mapowego pinu były zwykłymi zmianami swoich właścicieli. Nie wymagały assignmentu, ACK, receiptu, FROZEN hand-offu, lokalnego integratora ani rozmowy agentów; autor implementował, wykonywał lokalne testy i otwierał PR.
- D5. Gdy zmieniało się kilka sealed manifestów, Mapa mogła przekazać wszystkie pary `<id>, <SHA256>` w jednym batchu. Builder miał pozostawić jeden spójny zestaw pinów i deterministycznych pochodnych; blokady, rehash i sposób publikacji były jego wewnętrzną implementacją, nie protokołem pracy autora.
- D6. Celowany test pakietu obejmował jego kontrakt i runtime. Pełny mapowy build/check i smoke były potrzebne przy rejestracji, zmianie originu albo publicznym montażu; pełną integrację na aktualnym `main` i danym PR docelowo chroniła merge queue zgodnie z ARD-0113.
- D7. `structures/<id>/generated/**`, generowana scena, L05 i mapowe metadane są deterministycznymi pochodnymi. Nie wolno poprawiać ich ręcznie ani używać ich dryfu jako drugiego źródła prywatnego stanu.
- Powód i skutek zastąpienia: rozdzielenie seala i mapowego pinu między dwa PR-y tworzyło wzajemne oczekiwanie. MAP-ARD-0027 zachowuje granice authority narzędzi, ale scala publikację w jeden root-routed PR.

## MAP-ARD-0027 - Pakiet struktury i mapowy pin trafiają w jednym PR integracyjnym

- Status / aktywny zakres: Obowiązuje; D1-D7
- Zatwierdzenie: 2026-08-28
- Relacje: Zastępuje MAP-ARD-0026; doprecyzowuje MAP-ARD-0013/D1-D3,D8-D9, MAP-ARD-0014/D7-D10 i MAP-ARD-0022/D1-D3,D7-D10; stosuje globalny ARD-0113 | Zastąpiona przez: brak
- D1. `structures/<id>/structure_manifest.json` pozostaje authority prywatnych źródeł pakietu. `--seal-structure-package <id>` może zaktualizować wyłącznie jego lokalne hashe i digesty; nie zapisuje `map_manifest.json`, `UnderwaterMap.tscn`, L05, mapowych metadanych ani innego pakietu.
- D2. Prywatne `--build-structure <id>` i `--check-structure <id>` rozwiązują tylko wskazany pakiet oraz wymagane publiczne kontrakty. Nie odkrywają ani nie zapisują innych struktur lub authority Mapy.
- D3. Mapa przypina pakiet wyłącznie przez dokładny SHA-256 sealed manifestu. `--refresh-structure-package` aktualizuje mapowy pin i pochodne deklaracje złożenia, ale nigdy prywatny manifest ani źródła pakietu.
- D4. Gdy zmiana prywatnych źródeł wymaga nowego seala i mapowego pinu, root przydziela jedno proste zadanie jednemu Codexowi. Jeden worktree, branch `codex/structure-<id>/<task-slug>` i PR obejmuje atomowo źródła pakietu, sealed manifest, mapowy refresh/pin oraz deterministyczne pochodne. Rozdzielenie tego na PR struktury i późniejszy PR Mapy jest niedozwolone.
- D5. Gdy zmienia się kilka sealed manifestów, jeden root-routed PR może przekazać wszystkie pary `<id>, <SHA256>` w batchu. Builder ma pozostawić jeden spójny zestaw pinów i pochodnych; blokady, rehash i sposób publikacji są jego wewnętrzną implementacją. Native merge queue składa PR z aktualnym `main`. Prawdziwy konflikt albo nieaktualny seal, pin lub pochodna wykryta przez `integration-green` powoduje nowe zadanie naprawcze dla nowego agenta startującego z aktualnego `main`; koordynator zastępuje i zamyka stary PR zamiast wznawiać jego autora do rebase'u.
- D6. Po mechanicznych seal/refresh/build/check autor uruchamia lokalne testy zadania, a następnie osobny lokalny fast-check w worktree. Po `PASS` wykonuje commit, push i jeden PR, po czym kończy pracę bez pollingu. Osobny wymagany GitHub `fast-check` sprawdza dokładny head; `FAIL` pozostawia PR otwarty, a tylko `PASS` pozwala enqueue. Pełną integrację na merge group `aktualny main + PR` chroni następnie `integration-green` zgodnie z ARD-0113.
- D7. `structures/<id>/generated/**`, generowana scena, L05 i mapowe metadane są deterministycznymi pochodnymi. Nie wolno poprawiać ich ręcznie ani używać ich dryfu jako drugiego źródła prywatnego stanu.
- Powód i skutek: seal i mapowy pin nie mogą oczekiwać na siebie w dwóch PR-ach. Jeden root-routed autor publikuje spójny zestaw po lokalnej weryfikacji i kończy na PR, merge queue certyfikuje pełne złożenie z aktualnym `main`, a szczegóły atomowej publikacji pozostają wewnątrz buildera.
