# Project Context — avatar nurka

Rola pliku: krótka, datowana migawka jedynego aktywnego pakietu avatara gracza, znanych niedopasowań i ostatniej weryfikacji. Trwałe reguły należą do `.ai/DECISIONS.md`, proces do `AGENTS.md`, a komendy i onboarding do `README.md`.

## Stan odniesienia — 2026-08-27

- `runtime/Diver.tscn` jest jedyną aktywną sceną avatara i pozostaje bezpośrednio instancjonowana przez `../scenes/diving/DiveScene.tscn`. Root jest jednym `CharacterBody2D` o jednostkowym transformie; nie istnieje druga scena w root ani osobny projekt Godot.
- `runtime/DiverController.gd` zachowuje istniejący adapter do rootowego `DiveMovementSystem`, orientację, przejścia animacji, sockety, montaż latarni i grupę `dive_player`. `runtime/DiverVisualEffects.gd` pozostaje wyłącznie prezentacją.
- Trzy aktywne arkusze `idle/swim/sprint` mają po `2048 × 1024` piksele i po 16 pól `512 × 256`. `assets/animation/diver_sprite_frames.tres` odtwarza je na jednym `AnimatedSprite2D`; import pozostaje liniowy z mipmapami zgodnie z przeniesionymi `.import`.
- `assets/profiles/diver_frame_envelope_profile.tres` jest aktywnym, walidowanym profilem koperty `105 × 60`. Jedynie gałąź `AnimatedSprite2D` ma authored scale `0.239` i wycentrowanie `Vector2(5.497, -3.2265)` dla kierunku prawego; root `CharacterBody2D` pozostaje w skali `1`.
- Pomiar alfy wszystkich 48 pól daje globalną unię `430 × 195 px`, największą pojedynczą wysokość `192 px` oraz bazową kopertę świata około `102.77 × 46.61`. `definitions/DiverFrameEnvelope.gd` przechowuje zmierzone granice każdej klatki, a kontroler ogranicza także obrót, stretch, cue, holowanie i interakcję do `105 × 60` w obu kierunkach.
- Bieżący collider gameplayowy jest poziomą kapsułą: `radius=30`, `height=105`, obrót `PI/2`, a więc obwiednia świata `105 × 60`. Osobny `InteractionRange` pozostaje kołem o promieniu `112` i jest globalnie znaczącym kontraktem interakcji; kamera nadal ma `zoom=1.2`.
- Profil `assets/profiles/diver_socket_profile.tres` publikuje 288 punktów: 3 klipy × 16 klatek × 6 socketów. Próbki `lamp` zachowują format i mogą służyć prezentacji, ale nie sterują emisją. Jedyny gameplayowy `DiveLight` ma lokalną pozycję `Vector2.ZERO` na originie nurka i pozostaje centralny niezależnie od animacji, obrotu oraz `flip_h`.
- Złoty okrąg widoczny na screenshotach nie jest colliderem. Tworzy go rootowy `TutorialDirectionIndicator` z `RING_RADIUS=72`; sama scena `Diver.tscn` nie rysuje debugowej obwiedni collidera.
- `DiveScene`, ogólne systemy ruchu, tlenu, ryzyka, wyposażenia, interakcji, sesji, UI i zapisu pozostają w root. Mapa, jej topologia, przeszkody i okludery pozostają w `../underwater_map_workbench/`.
- Warsztat nie zawiera roboczego modelu 3D, generatora AI ani niepromowanego stagingu. Odrzucony pipeline offline został usunięty bez publikacji; jedynym aktywnym źródłem wyglądu pozostają arkusze 2D, `SpriteFrames` i profile pod `assets/`.

## Luki

- `[PENDING_ALPHA_CLEANUP]` W źródłach pozostają drobne odłączone wyspy alfy, kolorowe frędzle i nierówna ciemna krawędź. Mipmapy ograniczają ich widoczność w runtime, lecz finalny raster powinien zostać oczyszczony i ponownie zmierzony przed uznaniem grafiki za produkcyjnie finalną.
- `[PENDING_RASTER_KICK_AUTHORING]` Aktywne PNG zachowują preferowaną, realistyczną tożsamość 2D, ale sam raster nie daje jeszcze jednoznacznej antyfazy obu nóg we wszystkich klatkach. Wtórny ślad płetw wzmacnia naprzemienny rytm prezentacyjnie; finalna przebudowa PNG wymaga kompletnego, spójnego kandydata i ponownego authoringu profilu socketów.
- `[PENDING_ROOT_MAP_INTEGRATION]` Collider `105 × 60` zmienia publiczną kopertę fizyczną. Integrator musi dostroić globalną certyfikację prześwitów/nawigacji i wykonać rzeczywiste przepłynięcie ciasnych przejść mapy; lokalny harness nie certyfikuje topologii świata ani odczucia sterowania.

## Ostatnia weryfikacja

- 2026-08-27, Godot 4.7.1: izolowany `DiverPresentationTest.tscn` przeszedł `1/1`. Test mierzy 48/48 klatek, waliduje kopertę `105 × 60`, profil i scenę, czasy trzech 16-klatkowych pętli, zachowanie fazy przejść, osiem kierunków ruchu, oba odbicia, cue oraz rzeczywisty `move_and_slide()` przeciw pionowemu i poziomemu `StaticBody2D`. Exact receipt bieżącej rewizji jest przekazywany poza repozytorium wraz z niezmiennym SHA commita.
- Natywny `DiverPresentationCapture.tscn` przeszedł `1/1`. Obejrzano macierz koperty, kluczowe klatki `idle/swim/sprint`, oba kierunki, sockety, oba kadry kontaktu oraz Latarnie off/I/II. Alfa mieści się w zatwierdzonej kopercie, kontakt odpowiada colliderowi, a jedyne światło pozostaje radialne i centralne na originie. Capture jest lokalnym syntetycznym harness-em i nie zastępuje mapowego playtestu; exact receipt bieżącej rewizji pozostaje artefaktem handoffu poza repozytorium.
