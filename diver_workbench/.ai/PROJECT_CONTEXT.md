# Project Context — avatar nurka

Rola pliku: krótka, datowana migawka jedynego aktywnego pakietu avatara gracza, znanych niedopasowań i ostatniej weryfikacji. Trwałe reguły należą do `.ai/DECISIONS.md`, proces do `AGENTS.md`, a komendy i onboarding do `README.md`.

## Stan odniesienia — 2026-08-26

- `runtime/Diver.tscn` jest jedyną aktywną sceną avatara i pozostaje bezpośrednio instancjonowana przez `../scenes/diving/DiveScene.tscn`. Root jest jednym `CharacterBody2D` o jednostkowym transformie; nie istnieje druga scena w root ani osobny projekt Godot.
- `runtime/DiverController.gd` zachowuje istniejący adapter do rootowego `DiveMovementSystem`, orientację, przejścia animacji, sockety, montaż latarni i grupę `dive_player`. `runtime/DiverVisualEffects.gd` pozostaje wyłącznie prezentacją.
- Trzy aktywne arkusze `idle/swim/sprint` mają po `2048 × 1024` piksele i po 16 pól `512 × 256`. `assets/animation/diver_sprite_frames.tres` odtwarza je na jednym `AnimatedSprite2D`; import pozostaje liniowy z mipmapami zgodnie z przeniesionymi `.import`.
- `assets/profiles/diver_frame_envelope_profile.tres` jest aktywnym, walidowanym profilem koperty `70 × 40`. Jedynie gałąź `AnimatedSprite2D` ma authored scale `0.16` i wycentrowanie `Vector2(3.68, -2.16)` dla kierunku prawego; root `CharacterBody2D` pozostaje w skali `1`.
- Pomiar alfy wszystkich 48 pól daje globalną unię `430 × 195 px`, największą pojedynczą wysokość `192 px` oraz bazową kopertę świata `68.8 × 31.2`. `definitions/DiverFrameEnvelope.gd` przechowuje zmierzone granice każdej klatki, a kontroler ogranicza także obrót, stretch, cue, holowanie i interakcję do `70 × 40` w obu kierunkach.
- Bieżący collider gameplayowy jest poziomą kapsułą: `radius=20`, `height=70`, obrót `PI/2`, a więc obwiednia świata `70 × 40`. Nie został zmieniony podczas relokacji. Osobny `InteractionRange` pozostaje kołem o promieniu `112` i jest globalnie znaczącym kontraktem interakcji.
- Profil `assets/profiles/diver_socket_profile.tres` publikuje 288 punktów: 3 klipy × 16 klatek × 6 socketów. Próbki `lamp` zachowują format i mogą służyć prezentacji, ale nie sterują emisją. Jedyny gameplayowy `DiveLight` ma lokalną pozycję `Vector2.ZERO` na originie nurka i pozostaje centralny niezależnie od animacji, obrotu oraz `flip_h`.
- Złoty okrąg widoczny na screenshotach nie jest colliderem. Tworzy go rootowy `TutorialDirectionIndicator` z `RING_RADIUS=72`; sama scena `Diver.tscn` nie rysuje debugowej obwiedni collidera.
- `DiveScene`, ogólne systemy ruchu, tlenu, ryzyka, wyposażenia, interakcji, sesji, UI i zapisu pozostają w root. Mapa, jej topologia, przeszkody i okludery pozostają w `../underwater_map_workbench/`.
- Warsztat nie zawiera roboczego modelu 3D, generatora AI ani niepromowanego stagingu. Odrzucony pipeline offline został usunięty bez publikacji; jedynym aktywnym źródłem wyglądu pozostają arkusze 2D, `SpriteFrames` i profile pod `assets/`.

## Luki

- `[PENDING_ALPHA_CLEANUP]` W źródłach pozostają drobne odłączone wyspy alfy, kolorowe frędzle i nierówna ciemna krawędź. Mipmapy ograniczają ich widoczność w runtime, lecz finalny raster powinien zostać oczyszczony i ponownie zmierzony przed uznaniem grafiki za produkcyjnie finalną.
- `[PENDING_MANUAL_PLAYTEST]` Trzeba ręcznie sprawdzić avatar w ciasnych przejściach mapy, przy ruchomej geometrii oraz podczas pełnego obrotu i odbicia. Automatyczne testy nie certyfikują odczucia sterowania.

## Ostatnia weryfikacja

- 2026-08-26, cleanup wariantu 1: usunięto cały niepromowany pipeline 3D/AI, jego staging, narzędzia, testy i cache. Audyt referencji nie znalazł żadnej zależności aktywnej sceny, kontrolerów, profili, `SpriteFrames`, lokalnego testu ani capture'u od usuniętych plików; aktywne ścieżki runtime pozostały bez zmian.
- Próba uruchomienia izolowanego `DiverPresentationTest.tscn` przez wspólny runner zatrzymała się przed startem Godota na niezwiązanej, niespójnej bramce rejestru Mapy. Wynik nie jest nowym `PASS`; test Nurka wymaga ponowienia po uzgodnieniu rejestru Mapy przez jej właściciela.
- 2026-08-26, Godot 4.7.1: lokalny `DiverPresentationTest.tscn` przeszedł `1/1`. Test mierzy 48/48 źródłowych klatek, waliduje profil i scenę, sprawdza oba kierunki oraz wszystkie cue, a następnie wykonuje rzeczywisty `move_and_slide()` przeciw pionowemu i poziomemu `StaticBody2D`. Collider pozostał `70 × 40`, `InteractionRange=112`, root ma skalę `1`, a `DiveLight` pozostaje centralny.
- Natywny `DiverPresentationCapture.tscn` przeszedł `1/1`; obejrzano macierz koperty, oba kadry kontaktu, ruch/VFX i Latarnie I–II. Alfa nie przekracza płaszczyzn kontaktu, oba odbicia są wycentrowane, a radialne światło nadal pochodzi z originu.
