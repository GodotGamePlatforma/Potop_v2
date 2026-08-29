# Project Context — avatar nurka

Rola pliku: krótka, datowana migawka jedynego aktywnego pakietu avatara gracza, znanych niedopasowań i ostatniej weryfikacji. Trwałe reguły należą do `.ai/DECISIONS.md`, proces do `AGENTS.md`, a komendy i onboarding do `README.md`.

## Stan odniesienia — 2026-08-29

- `runtime/Diver.tscn` jest jedyną aktywną sceną avatara i pozostaje bezpośrednio instancjonowana przez `../scenes/diving/DiveScene.tscn`. Root jest jednym `CharacterBody2D` o jednostkowym transformie; nie istnieje druga scena w root ani osobny projekt Godot.
- `runtime/DiverController.gd` zachowuje istniejący adapter do rootowego `DiveMovementSystem`, orientację, przejścia animacji, sockety, montaż latarni i grupę `dive_player`. `runtime/DiverVisualEffects.gd` pozostaje wyłącznie prezentacją.
- Trzy aktywne arkusze `idle/swim/sprint` mają po `2048 × 1024` piksele i po 16 pól `512 × 256`. `assets/animation/diver_sprite_frames.tres` odtwarza je na jednym `AnimatedSprite2D`; import pozostaje liniowy z mipmapami zgodnie z przeniesionymi `.import`.
- `assets/profiles/diver_frame_envelope_profile.tres` jest aktywnym, walidowanym profilem koperty `105 × 60`. Jedynie gałąź `AnimatedSprite2D` ma authored scale `0.239` i wycentrowanie `Vector2(5.497, -3.2265)` dla kierunku prawego; root `CharacterBody2D` pozostaje w skali `1`.
- Oczyszczone rastry zachowują po jednym spójnym komponencie alfy w każdym z 48 pól oraz neutralne półprzezroczyste krawędzie. Pozy, kolejność klatek i próbki profilu socketów są niezmienione; cała gałąź wizualna korzysta z bieżącego wycentrowania profilu koperty.
- Pomiar alfy wszystkich 48 pól zachowuje globalną unię `430 × 195 px`, największą pojedynczą wysokość `192 px` oraz bazową kopertę świata około `102.77 × 46.61`. `definitions/DiverFrameEnvelope.gd` przechowuje zmierzone granice każdej klatki, a kontroler ogranicza także obrót, stretch, cue, holowanie i interakcję do `105 × 60` w obu kierunkach.
- Bieżący collider gameplayowy jest poziomą kapsułą: `radius=30`, `height=105`, obrót `PI/2`, a więc obwiednia świata `105 × 60`. Osobny `InteractionRange` pozostaje kołem o promieniu `112` i jest globalnie znaczącym kontraktem interakcji.
- `assets/profiles/diver_camera_profile.tres` jest aktywnym, walidowanym profilem prezentacji kamery przy stałym `zoom=1.2`. Kontroler zeruje look-ahead bez intencji ruchu, wyprowadza płynne wychylenie z prędkości własnej zgodnej ze sterowaniem, zwiększa je i przyspiesza dla sprintu, wygasza po puszczeniu sterowania oraz nie tworzy go dla samego prądu; tryb ograniczenia ruchu wyłącza także smoothing śledzenia. Kamera aktualizuje transform w kroku fizyki przed pochodnym HUD-em, a rzeczywisty kadr nadal respektuje granice świata.
- Profil `assets/profiles/diver_socket_profile.tres` publikuje 288 punktów: 3 klipy × 16 klatek × 6 socketów. Próbki `lamp` zachowują format i mogą służyć prezentacji, ale nie sterują emisją. Jedyny gameplayowy `DiveLight` ma lokalną pozycję `Vector2.ZERO` na originie nurka i pozostaje centralny niezależnie od animacji, obrotu oraz `flip_h`.
- Złoty okrąg widoczny na screenshotach nie jest colliderem. Tworzy go rootowy `TutorialDirectionIndicator` z `RING_RADIUS=72`; sama scena `Diver.tscn` nie rysuje debugowej obwiedni collidera.
- `DiveScene`, ogólne systemy ruchu, tlenu, ryzyka, wyposażenia, interakcji, sesji, UI i zapisu pozostają w root. Mapa, jej topologia, przeszkody i okludery pozostają w `../underwater_map_workbench/`.
- Warsztat nie zawiera roboczego modelu 3D, generatora AI ani niepromowanego stagingu. Odrzucony pipeline offline został usunięty bez publikacji; jedynym aktywnym źródłem wyglądu pozostają arkusze 2D, `SpriteFrames` i profile pod `assets/`.

## Luki

- `[PENDING_RASTER_KICK_AUTHORING]` Aktywne PNG zachowują preferowaną, realistyczną tożsamość 2D, ale sam raster nie daje jeszcze jednoznacznej antyfazy obu nóg we wszystkich klatkach. Wtórny ślad płetw wzmacnia naprzemienny rytm prezentacyjnie; finalna przebudowa PNG wymaga kompletnego, spójnego kandydata i ponownego authoringu profilu socketów.
- `[PENDING_ROOT_MAP_PLAYTEST]` Automatyczny rootowy replay potwierdza bieżące próbki prześwitów, granice mapy i działanie rzeczywistej kamery z colliderem `105 × 60`; nadal nie certyfikuje wszystkich tras ani subiektywnego odczucia sterowania.

## Ostatnia weryfikacja

- 2026-08-29, Godot 4.7.1: izolowany `DiverPresentationTest.tscn` przeszedł `1/1`. Test mierzy 48/48 klatek, potwierdza po jednym 8-spójnym komponencie alfy, format `2048 × 1024`, układ `4 × 4`, jawne granice klatek i kopertę `105 × 60`; waliduje też aktywne profile avatara i scenę, czasy pętli, fazę przejść, osiem kierunków, oba odbicia, cue oraz rzeczywisty `move_and_slide()`.
- 2026-08-28, Godot 4.7.1: rootowy `diver_clearance_integration_test.gd` przeszedł headless i native. Rzeczywisty widok dał 60,38 jednostki przewagi przy pływaniu, 95,73 przy sprincie i 0,004 po wyhamowaniu; bierny prąd nie utworzył celu wyprzedzenia, skrajne limity mapy pozostały szczelne, pierścień tutoriala miał rozjazd 0,0, a trzy kadry 1280×720 przeszły oględziny. To potwierdza integrację sceny avatara z bieżącą Mapą, ale nie zastępuje subiektywnego playtestu strojenia.
- 2026-08-29, Godot 4.7.1: natywny `DiverPresentationCapture.tscn` przeszedł `1/1` po przeniesieniu artefaktów z `res://` do izolowanego `user://`. Obejrzano macierz koperty, kluczowe klatki `idle/swim/sprint`, oba kierunki, sockety, ruch i VFX, oba kadry kontaktu oraz Latarnie off/I/II. Oczyszczone krawędzie są spójne w skali gry, alfa z rimem mieści się w profilu, kontakt odpowiada colliderowi, a jedyne światło pozostaje radialne i centralne na originie. Capture jest syntetycznym harness-em i nie zastępuje mapowego playtestu.
