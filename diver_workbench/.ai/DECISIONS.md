# Decyzje warsztatu avatara nurka

Ten plik przechowuje wyłącznie trwałe decyzje authoringu i integracji avatara gracza. Globalne reguły produktu, ruchu, sesji, zapisu i mapy pozostają w dokumentach nadrzędnych. Wszystkie ścieżki lokalne są zapisywane względem katalogu roboczego `diver_workbench/`, a `../` oznacza root projektu. Nowy wpis podaje status, zakres, relacje, decyzje, powód i odwołania; nie służy jako dziennik wdrożenia.

## Indeks aktywnych decyzji

| ID | Zakres | Aktywny kontrakt |
|---|---|---|
| DIVER-ARD-0001 | authority i integracja avatara | Jedna scena i publiczne API `DiverController`; prywatne wnętrze pozostaje lokalne. |
| DIVER-ARD-0003 | radialna latarnia | Jedno centralne światło dookoła nurka; sprzęt root steruje promieniem, energią i stanem. |
| DIVER-ARD-0005 | źródło aktywnej grafiki | Aktywne arkusze 2D i profile są jedynym authority; warsztat nie utrzymuje zatwierdzonego pipeline'u 3D/AI. |
| DIVER-ARD-0006 | fizyczna koperta 105 × 60 | Stabilna kapsuła oraz mierzalna kalibracja aktywnej grafiki do większej, czytelnej koperty. |

Obowiązują wyłącznie wpisy wymienione w tym indeksie. Zastąpienie wymaga symetrycznej relacji w starym i nowym wpisie.

## DIVER-ARD-0001 - Jeden pakiet i jedna scena są authority avatara

- Status / aktywny zakres: Obowiązuje; D1-D8
- Zatwierdzenie: 2026-08-26
- Relacje: Uszczegóławia globalny ARD-0105 | Zastąpiona przez: brak
- D1. `diver_workbench/` działa wewnątrz projektu nadrzędnego i nie posiada własnego `project.godot`, InputMap, autoloadów, cache ani runnera.
- D2. `runtime/Diver.tscn` jest jedyną aktywną sceną avatara. Rootowa `DiveScene` instancjonuje ją bezpośrednio; nie istnieje wrapper ani kopia pod `scenes/diving`.
- D3. Warsztat jest jedynym właścicielem adaptera `DiverController`, fizycznej bryły, `DiverVisualEffects`, klipów i arkuszy animacji, profilu socketów oraz shaderów avatara. PNG zachowują wersjonowane `.import` i UID.
- D4. Ogólne systemy ruchu, sesji, ryzyka, wyposażenia, interakcji, UI i persistence pozostają w root, a teren, okludery i grafika świata w warsztacie mapy. Zależności przechodzą przez publiczną scenę i istniejące API, nie przez kopie.
- D5. Lokalny test prezentacji chroni wnętrze pakietu, a rootowe testy ruchu, sprzętu i składania scen chronią jego rzeczywistą integrację przez publiczną granicę. Mapowy smoke nie ładuje ani nie sprawdza avatara. Wszystkie testy korzystają ze wspólnego sekwencyjnego runnera projektu.
- D6. Pierwsze wydzielenie jest relokacją bez zmiany skali, collidera, `InteractionRange`, socketów, latarni, VFX, ruchu, zapisu ani podpisu mapy.
- D7. Publiczną granicą Root↔Diver jest root sceny `runtime/Diver.tscn` ze skryptem `DiverController`, jego jawnie konsumowane sygnały i metody oraz publiczny token grupy `DIVE_PLAYER_GROUP`. Sterowanie wejściem, prądem świata, mnożnikiem ruchu i odczytem intencji odbywa się metodami, nie zapisem do publicznych pól ruchu. Nazwy i hierarchia `DiveLight`, `Camera2D`, `VisualEffects`, grafiki, socketów oraz emiterów pozostają prywatne dla warsztatu. Adapter może korzystać z publicznego `../scripts/diving/DiveMovementSystem.gd`, a root może instancjonować i sterować sceną; zmiana znaczenia publicznego API jest zadaniem mieszanym routowanym do root i wymaga testu integracyjnego.
- D8. Eksportowane parametry ruchu mogą być fizycznie zapisane w `runtime/DiverController.gd`, lecz ich znaczenie i balans są globalnym kontraktem gameplayowym. Lokalne zadanie graficzne, animacyjne, socketowe lub VFX nie zmienia tych wartości, API ruchu ani zachowania adaptera; taka propozycja przechodzi routing, bramkę produktu i architektury oraz testy root.
- Powód i skutek: jeden skupiony katalog pozwala agentowi rozwijać postać bez mieszania jej źródeł z konkretną mapą, zachowując jednocześnie prawdziwe ustawienia i testy projektu nadrzędnego.
- Odwołania: `../.ai/DECISIONS.md`, ARD-0105; `../docs/Ostatni_Pomost_architektura_Godot.txt`, sekcje 2, 5, 12.3 i 13.

## DIVER-ARD-0002 - Historyczna fizyczna koperta 70 × 40

- Status / aktywny zakres: Zastąpiona; brak aktywnego zakresu
- Zatwierdzenie / zastąpienie: 2026-08-26 / 2026-08-27
- Relacje: Historyczna decyzja koperty | Zastąpiona przez: DIVER-ARD-0006
- Odwołania historyczne: uszczegóławiała globalne ARD-0103 i ARD-0105/D7; punkt emisji i montaż światła uszczegółowił DIVER-ARD-0003
- D1. Collider gracza jest jedną prostą, stabilną bryłą obejmującą sztywną część postaci. Płetwy i wtórny ruch animacji nie otrzymują colliderów per klatka.
- D2. Widoczna alfa całej animacji ma docelową kopertę `70 × 40`, zgodną z obwiednią stabilnego collidera. Nie skaluje się całego korzenia `CharacterBody2D`; aktywne strojenie skali i wycentrowania gałęzi wizualnej należy do walidowanego `assets/profiles/diver_frame_envelope_profile.tres`.
- D3. Każdy aktywny klip i każda klatka podlegają pomiarowi widocznej alfy. Zmierzone granice są współdzielone przez runtime i test, a kontroler ogranicza wynikowy transform prezentacyjny — wraz z `flip_h`, obrotem, stretch, cue, holowaniem i interakcją — do zatwierdzonej koperty bez zmiany bryły fizycznej.
- D4. `InteractionRange` jest globalnie znaczącym zasięgiem gameplayowym mimo położenia w scenie avatara i nie zmienia się razem z tuningiem wizualnym.
- D5. Socket lampy należy do profilu avatara, stan i energia światła do systemów root, a zasłanianie do topologii i okluderów mapy. Odbiór koperty wymaga lokalnego pomiaru wszystkich klatek, obu odbić oraz rzeczywistego kontaktu `CharacterBody2D` z pionową i poziomą przeszkodą; capture musi pokazać jednocześnie alfę, collider i płaszczyznę kontaktu.
- D6. Model 3D może być wyłącznie źródłem offline dla finalnych klatek 2D. Dodanie runtime 3D albo drugiej sceny avatara wymaga osobnej decyzji.
- D7. Retarget istniejącego, spójnego rastra może zachować wysokorozdzielcze źródła i mipmapy, o ile wynik świata spełnia profil koperty, sockety dziedziczą dokładnie jeden transform, a rozmiary VFX są retargetowane tym samym stosunkiem. Fizyczny resampling lub crop PNG jest osobnym atomowym etapem wymagającym ponownego authoringu regionów i 288 socketów.
- Powód i skutek: stabilna bryła daje przewidywalną fizykę i proste testy, a kontrolowany envelope pozwala poprawić czytelność oraz światło bez niestabilnej kolizji zależnej od animacji.
- Odwołania: `../docs/OgolnyZarys.txt`, sekcje 6-7; `../docs/Ostatni_Pomost_architektura_Godot.txt`, sekcje 5, 9.1.2, 12.3 i 13.

## DIVER-ARD-0003 - Latarnia jest jednym centralnym światłem radialnym

- Status / aktywny zakres: Obowiązuje; D1-D6
- Zatwierdzenie: 2026-08-26
- Relacje: Zastępuje DIVER-ARD-0002/D3 wyłącznie w zakresie punktu emisji oraz DIVER-ARD-0002/D5 w zakresie montażu i stożka | Uszczegóławia globalne ARD-0105/D7 | Zastąpiona przez: brak
- D1. `runtime/Diver.tscn` posiada dokładnie jeden gameplayowy `PointLight2D`, którego lokalna pozycja pozostaje `Vector2.ZERO` względem korzenia `CharacterBody2D`. Animacja, sockety, obrót, `flip_h`, profil jakości i `reduced_motion` nie mogą go przesuwać.
- D2. Światło jest radialne i oświetla otoczenie dookoła nurka. Scena avatara nie rysuje kierunkowego stożka ani drugiego substytutu światła.
- D3. Ogólny `LightSystem`, wyposażona definicja sprzętu i `DiveSessionState` pozostają jedynymi właścicielami tekstury radialnej, promienia, energii, koloru, jakości cieni i stanu włączenia. Latarnia I pozostaje słabszym wariantem startowym, a Latarnia II mocniejszym ulepszeniem z Warsztatu I; dokładne wartości należą do walidowanych zasobów root.
- D4. Próbki `lamp` i `LampSocket` pozostają wizualnym punktem profilu oraz elementem zgodności jego bieżącego formatu 288 próbek. Nie sterują `DiveLight`, promieniem, ryzykiem ani inną mechaniką.
- D5. Okluzja pozostaje odpowiedzialnością mapy, a wpływ włączonego światła na zagrożenia odpowiedzialnością systemów root. Zmiana prezentacji nie dodaje pola zapisu, migracji kampanii ani nowego stanu sesji.
- D6. Lokalny test chroni pojedyncze centralne źródło i jego niezmienność przy zmianach prezentacji, natywny capture porównuje stan wyłączony oraz oba poziomy sprzętu, a test sprzętu root potwierdza monotoniczne zwiększenie zasięgu i energii ulepszenia.
- Powód i skutek: centralne światło odpowiada graczowemu znaczeniu latarni jako kręgu widzenia, usuwa rozjazd 19-28 jednostek przed colliderem i zachowuje jednego właściciela parametrów sprzętu bez wpływu na fizykę avatara.
- Odwołania: `../docs/OgolnyZarys.txt`, sekcje 5.4 i 6; `../docs/Ostatni_Pomost_architektura_Godot.txt`, sekcje 5.5, 9.1.2, 9.3, 12.3 i 13.

## DIVER-ARD-0004 - Wycofany pipeline offline 3D -> 2D

- Status / aktywny zakres: Zastąpiona; brak aktywnego zakresu
- Zatwierdzenie / zastąpienie: 2026-08-26 / 2026-08-26
- Relacje: Nie stanowi authority ani instrukcji wdrożeniowej | Zastąpiona przez: DIVER-ARD-0005
- Decyzja historyczna: manifest, blockout Blender, generator, renderer i staging miały poprzedzać osobną promocję klatek 2D. Etap nie został zaakceptowany ani opublikowany do aktywnego runtime.
- Skutek zastąpienia: niepromowane źródła, wyniki, narzędzia i ich testy zostały usunięte; nie wolno odtwarzać ich na podstawie tego wpisu.

## DIVER-ARD-0005 - Aktywne assety 2D są jedynym authority grafiki

- Status / aktywny zakres: Obowiązuje; D1-D5
- Zatwierdzenie: 2026-08-26
- Relacje: Zastępuje DIVER-ARD-0004 w całości | Zastąpiona przez: brak
- Odwołania kontraktowe: uszczegóławia DIVER-ARD-0001/D3-D5 oraz aktywną decyzję koperty DIVER-ARD-0006/D2-D7
- D1. Jedynym aktywnym źródłem wyglądu avatara są wersjonowane arkusze pod `assets/animation/`, `assets/animation/diver_sprite_frames.tres` oraz profile pod `assets/profiles/`. Runtime nie odczytuje modelu, manifestu ani generatora offline.
- D2. Warsztat nie utrzymuje zatwierdzonego pipeline'u 3D/AI, roboczego modelu, referencyjnych renderów ani katalogu stagingowego. Odrzucone eksperymenty nie mogą pozostawać obok aktywnego pakietu ani być użyte jako ukryty fallback.
- D3. Przyszła wymiana grafiki wymaga osobnej decyzji, kompletnego i spójnego kandydata oraz jawnej atomowej promocji PNG, `SpriteFrames`, profilu socketów, profilu koperty i sceny, zakończonej lokalnym testem oraz obejrzanym capture'em.
- D4. Zewnętrzny model, obraz albo wynik generatora jest wyłącznie materiałem wejściowym do czasu odbioru. Nie staje się authority przez samo umieszczenie w repozytorium ani przez zgodność pojedynczej klatki z kopertą.
- D5. Samo wycofanie pipeline'u nie zmienia aktywnych arkuszy, animacji, `InteractionRange`, centralnego `DiveLight`, parametrów ruchu, publicznego API ani zapisu. Aktualną kopertę i collider określa osobna aktywna decyzja fizyczna.
- Powód i skutek: usunięcie niepromowanych eksperymentów zapobiega ich pomieszaniu z lepszym aktywnym avatarem, a jednoznaczne authority 2D zachowuje działający runtime bez bocznej zmiany produktu.
- Odwołania: DIVER-ARD-0001, DIVER-ARD-0003 i DIVER-ARD-0006; `README.md`.

## DIVER-ARD-0006 - Koperta 105 × 60 przywraca czytelną obecność avatara

- Status / aktywny zakres: Obowiązuje; D1-D8
- Zatwierdzenie: 2026-08-27
- Relacje: Zastępuje DIVER-ARD-0002 w całości | Zastąpiona przez: brak
- Odwołania kontraktowe: uszczegóławia globalne ARD-0103 i ARD-0105/D7; centralny montaż światła pozostaje określony przez DIVER-ARD-0003
- D1. Collider gracza jest jedną poziomą kapsułą o promieniu `30`, wysokości `105` i obrocie `PI/2`, co daje obwiednię świata `105 × 60`. Płetwy ani wtórny ruch animacji nie otrzymują colliderów per klatka.
- D2. Widoczna alfa całej animacji ma docelową kopertę `105 × 60`. Aktywny profil ustawia wyłącznie gałąź wizualną na skalę `0.239` i pozycję `Vector2(5.497, -3.2265)`; korzeń `CharacterBody2D` pozostaje w skali `1`.
- D3. Wszystkie 48 granic źródłowej alfy pozostaje wspólnym pomiarem runtime i testu. Unia `430 × 195 px` daje po kalibracji około `102.77 × 46.61` jednostki świata, pozostawiając kontrolowany margines na shader czytelności i zmiany pozy.
- D4. Kontroler ogranicza wynikowy transform prezentacyjny wraz z `flip_h`, obrotem, stretch, cue, holowaniem i interakcją do aktywnej koperty bez animowania bryły fizycznej.
- D5. `InteractionRange=112`, kamera `zoom=1.2`, parametry ruchu i publiczne API nie zmieniają się razem z kopertą. Ich znaczenie pozostaje globalnym kontraktem root.
- D6. Profil 288 socketów dziedziczy dokładnie jeden transform grafiki. `LampSocket` pozostaje wyłącznie wizualny, a jedyny gameplayowy `DiveLight` pozostaje centralnie na originie zgodnie z DIVER-ARD-0003.
- D7. Aktywne arkusze 2D i czasy klipów pozostają authority. Retarget koperty zachowuje PNG, `SpriteFrames`, mipmapy i filtrowanie; krok rimu jest dostrojony do około jednego piksela ekranowego, a wtórny ślad płetw wzmacnia naprzemienny rytm bez wpływu na gameplay.
- D8. Odbiór lokalny wymaga pomiaru wszystkich klatek, obu kierunków, ośmiu kierunków ruchu, przejść `idle/swim/sprint`, rzeczywistego kontaktu z dwiema osiami przeszkód i obejrzanego capture'u latarni off/I/II. Lokalny PASS nie certyfikuje prześwitów ani pełnego przepłynięcia produkcyjnej mapy; sprawdzają je test integracyjny root i mapowy playtest.
- Powód i skutek: poprzednia prezentacja miała zaledwie około `82.6 × 37.4 px` na ekranie 1280×720 i traciła czytelność detali. Wariant `105 × 60` przywraca ciężar i rozpoznawalność istniejącej, preferowanej grafiki 2D bez powrotu do dawnego rozjazdu sylwetki `146 × 65` z colliderem.
- Odwołania: DIVER-ARD-0001, DIVER-ARD-0003 i DIVER-ARD-0005; `assets/profiles/diver_frame_envelope_profile.tres`; `README.md`.
