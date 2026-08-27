# Project Context — avatar nurka

Rola pliku: krótka, datowana migawka jedynego aktywnego pakietu avatara gracza, znanych niedopasowań i ostatniej weryfikacji. Trwałe reguły należą do `.ai/DECISIONS.md`, proces do `AGENTS.md`, a komendy i onboarding do `README.md`.

## Stan odniesienia — 2026-08-27

- `runtime/Diver.tscn` jest jedyną aktywną sceną avatara i pozostaje bezpośrednio instancjonowana przez `../scenes/diving/DiveScene.tscn`. Root jest jednym `CharacterBody2D` o jednostkowym transformie; nie istnieje druga scena w root ani osobny projekt Godot.
- `runtime/DiverController.gd` zachowuje istniejący adapter do rootowego `DiveMovementSystem`, orientację, przejścia animacji, sockety, montaż latarni i grupę `dive_player`. `runtime/DiverVisualEffects.gd` pozostaje wyłącznie prezentacją.
- Trzy aktywne arkusze `idle/swim/sprint` mają po `2048 × 1024` piksele i po 16 pól `512 × 256`. Stabilny korpus jest zarejestrowany jednakowo w 48 klatkach, a dwie kompletne nogi zachowują stałą tożsamość i wykonują czytelną przeciwfazę. `assets/animation/diver_sprite_frames.tres` odtwarza je na jednym `AnimatedSprite2D`; import pozostaje liniowy z mipmapami.
- `assets/profiles/diver_frame_envelope_profile.tres` jest aktywnym, walidowanym profilem koperty `105 × 60`. Jedynie gałąź `AnimatedSprite2D` otrzymuje po `_ready()` authored scale `0.239` i wycentrowanie `Vector2(-0.717, -4.1825)` dla kierunku prawego; root `CharacterBody2D` pozostaje w skali `1`.
- Pomiar alfy wszystkich 48 pól daje globalną unię `420 × 199 px`, największą pojedynczą wysokość `199 px` oraz bazową kopertę świata około `100.38 × 47.56`. Każda klatka ma jedną połączoną sylwetkę przy progach alfy `1/255` i `8/255` oraz co najmniej 10 px paddingu. `definitions/DiverFrameEnvelope.gd` przechowuje granice, a kontroler ogranicza także obrót, stretch, cue, holowanie i interakcję do `105 × 60` w obu kierunkach.
- Bieżący collider gameplayowy jest poziomą kapsułą: `radius=30`, `height=105`, obrót `PI/2`, a więc obwiednia świata `105 × 60`. Osobny `InteractionRange` pozostaje kołem o promieniu `112` i jest globalnie znaczącym kontraktem interakcji; kamera nadal ma `zoom=1.2`.
- Profil `assets/profiles/diver_socket_profile.tres` publikuje 288 punktów: 3 klipy × 16 klatek × 6 socketów. `fin_upper` stale śledzi bliższą nogę oznaczoną miedzią, `fin_lower` dalszą nogę oznaczoną cyjanem, a sockety korpusu nie dryfują z kopnięciem. Próbki `lamp` nie sterują emisją. Jedyny gameplayowy `DiveLight` ma lokalną pozycję `Vector2.ZERO` na originie nurka i pozostaje centralny niezależnie od animacji, obrotu oraz `flip_h`.
- Złoty okrąg widoczny na screenshotach nie jest colliderem. Tworzy go rootowy `TutorialDirectionIndicator` z `RING_RADIUS=72`; sama scena `Diver.tscn` nie rysuje debugowej obwiedni collidera.
- `DiveScene`, ogólne systemy ruchu, tlenu, ryzyka, wyposażenia, interakcji, sesji, UI i zapisu pozostają w root. Mapa, jej topologia, przeszkody i okludery pozostają w `../underwater_map_workbench/`.
- Warsztat nie zawiera roboczego modelu 3D, generatora AI ani niepromowanego stagingu. Odrzucony pipeline offline został usunięty bez publikacji; jedynym aktywnym źródłem wyglądu pozostają arkusze 2D, `SpriteFrames` i profile pod `assets/`.

## Luki

- `[PENDING_ROOT_MAP_INTEGRATION]` Collider `105 × 60` zmienia publiczną kopertę fizyczną. Integrator musi dostroić globalną certyfikację prześwitów/nawigacji i wykonać rzeczywiste przepłynięcie ciasnych przejść mapy; lokalny harness nie certyfikuje topologii świata ani odczucia sterowania.

## Ostatnia weryfikacja

- 2026-08-27, Godot 4.7.1: izolowany `DiverPresentationTest.tscn` przeszedł `1/1`. Test mierzy 48/48 klatek, mapping atlasu, higienę i spójność alfy, niezależną unię źródłową, miedziany/cyjanowy marker tożsamości w 16/16 klatek `swim/sprint`, dwie rzeczywiste masy płetw oraz ich odwrócenie przy fazach `0.25/0.75`, profil 288 socketów, czasy pętli, zachowanie fazy przejść, osiem kierunków i ciągłe sweepy przez pion, oba odbicia, cue oraz rzeczywisty `move_and_slide()` przeciw dwóm osiom przeszkód.
- Natywny `DiverPresentationCapture.tscn` przeszedł `1/1`. Obejrzano skrajne klatki naprzemiennego kopnięcia `swim/sprint`, oba kierunki, macierz niezależnego targetu `105 × 60`, osobno narysowaną kapsułę, oba kadry kontaktu, VFX i Latarnie off/I/II. Alfa mieści się w kopercie, tożsamości nóg pozostają czytelne, kontakt odpowiada colliderowi, a jedyne światło pozostaje radialne i centralne. Capture jest syntetycznym harness-em i nie zastępuje mapowego playtestu; exact receipt rewizji pozostaje artefaktem handoffu poza repozytorium.
