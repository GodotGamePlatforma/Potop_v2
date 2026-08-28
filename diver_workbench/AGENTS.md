# Instrukcje warsztatu avatara nurka

Ten katalog jest jedynym miejscem authoringu sceny, fizycznej bryły, grafiki, animacji, socketów, shaderów i VFX avatara gracza. Pracuj z `diver_workbench/` jako katalogiem roboczym; wszystkie ścieżki w tym pliku są względem tego katalogu, a właściwy projekt Godot i ogólne systemy wyprawy pozostają w `..`.

## Start i routing kontekstu

Dla zwykłego zadania w jednej prywatnej części avatara przeczytaj tylko:

1. ten najbliższy `AGENTS.md`;
2. właściwy punkt `.ai/PROJECT_CONTEXT.md`;
3. odpowiednią sekcję `README.md` z granicą i komendami;
4. zmieniany kod, scenę, asset i bezpośredni test lub capture.

Nie czytaj całego rejestru `.ai/DECISIONS.md`, produktu ani architektury tylko dlatego, że istnieją. Pełny lokalny rejestr decyzji oraz wymagany kontekst root otwórz, gdy zadanie zmienia widoczną skalę, collider, punkt emisji światła, `InteractionRange`, ruch, sterowanie, zasięg, czytelny feedback, publiczne API albo skutek kontaktu. To samo dotyczy zmiany produktu, zapisu, migracji lub zakresu przekraczającego właściciela Nurka. Kontrole SHA-256 są wymagane tylko w zadaniu audytowym lub gdy dokładna rewizja dokumentu jest częścią dowodu.

Zmiana tlenu, ryzyka, walki, wyposażenia, interakcji, sesji, wyniku, UI, persistence lub mapy nie jest lokalnym zadaniem warsztatu.

## Granica odczytu i zapisu

- Domyślną allowlistą zapisu lokalnego zadania jest wyłącznie `diver_workbench/**`, czyli ścieżki pod `.` z katalogu roboczego warsztatu. Root pod `../` oraz `../underwater_map_workbench/**` są dla lokalnego agenta tylko do odczytu.
- Warsztat może konsumować publiczne kontrakty root i mapy, lecz nie poprawia ich plików, testów ani dokumentacji jako efektu ubocznego zadania avatara. Nie sięga także do wnętrza pakietu mapy poza jej publiczną integracją runtime.
- Jeżeli poprawne rozwiązanie wymaga zapisu poza `diver_workbench/**`, zadanie staje się mieszane. Przed pierwszym takim zapisem przeroutuj je do root, zastosuj globalny protokół i przypisz każdą zmianę właścicielowi domeny. Test integracyjny obejmujący jednocześnie avatara, root i mapę należy do root.
- Rutynowe zadanie jednego właściciela nie wymaga przed edycją deklaracji wszystkich plików ani dokumentów. Po edycji sprawdź pełny diff repozytorium; obecność nieplanowanego zapisu poza allowlistą oznacza przerwanie lokalnej pracy, a nie zgodę na rozszerzenie zakresu.

### Współbieżność

- Root lub koordynator przydziela jedno proste zadanie jednemu agentowi Nurka. Agent używa osobnego pełnego Git worktree i gałęzi `codex/diver/<task-slug>` utworzonej z aktualnego `origin/main`. Osobny CWD we wspólnym checkoutcie nie daje izolacji; lokalna allowlista nadal obejmuje wyłącznie `diver_workbench/**`.
- Zmiana aktywnych `assets/animation/`, `assets/profiles/`, `definitions/` albo `runtime/` ma jednego autora na gałęzi. Kolejność jest stała: implementacja -> właściwy lokalny test zadania i potrzebny capture -> osobny lokalny `agent_fast_check.ps1`. `FAIL` oznacza poprawę i powtórzenie; po `PASS` autor tworzy commit i uruchamia `publish_agent_pr.ps1`, który pushuje branch, otwiera jeden PR i dla zwykłej zmiany włącza squash auto-merge. Na tym agent kończy bez pollingu. Osobny wymagany GitHub `fast-check` sprawdza exact head PR, a pełny `integration-green` działa dopiero w merge queue.
- Celowany test Nurka nie wykonuje discovery, refreshu ani walidacji prywatnych pakietów Mapy. Runner używa pełnej izolowanej kopii z osobnym `.godot`, `user://`, logami i capture; równoległy Godot działa tylko w osobnych workspace z jawnym `--path`. `-InPlace` jest odrzucane.

## Granica odpowiedzialności

Warsztat utrzymuje jeden aktywny pakiet avatara:

- `runtime/Diver.tscn` — jedyna scena `CharacterBody2D` gracza;
- `runtime/DiverController.gd` — adapter wejścia, ogólnego kroku ruchu, orientacji, animacji i socketów;
- `runtime/DiverVisualEffects.gd` — wyłącznie prezentacyjne VFX;
- `definitions/DiverSocketProfile.gd` i aktywny profil w `assets/profiles/`;
- `assets/animation/` — arkusze i jeden zasób `SpriteFrames`;
- `assets/shaders/` — shadery wyłącznie avatara;
- `tests/` — lokalny test i natywny capture prezentacji.

Katalog nadrzędny zachowuje `DiveScene`, `DiveController`, `DiveMovementSystem`, InputMap, tlen, ryzyko, walkę, wyposażenie, interakcje, `DiveSessionState`, `DiveResult`, UI, persistence i wspólny runner. `underwater_map_workbench/` zachowuje mapę, teren, okludery i worldowe grafiki gameplayowe. Nie kopiuj żadnej z tych odpowiedzialności do warsztatu nurka.

## Słownik authority

| Element | Rola | Czy wolno mieć kopię? |
|---|---|---|
| `runtime/Diver.tscn` | Jedyna kompozycja avatara, collidera, `InteractionRange`, kamery, socketów i prezentacji latarni. | Nie. |
| `assets/animation/diver_sprite_frames.tres` | Jedyny aktywny katalog klipów i klatek. | Nie. |
| `assets/profiles/diver_socket_profile.tres` | Jedyny aktywny zestaw dyskretnych socketów klatek. | Nie. |
| PNG i ich `.import` | Aktywne źródła rastra wraz z UID i ustawieniami importu. | Nie; przenoś parami. |
| `DiveMovementSystem` i systemy sesji w root | Ogólne reguły gameplayu konsumowane przez adapter. | Nie przenoś. |
| Mapa i jej okludery | Świat, z którym zderza się i w którym świeci avatar. | Nie przenoś. |

Kierunek własności i kompozycji:

`źródła grafiki + profil socketów -> jedna scena avatara -> DiveScene i ogólne systemy root -> jedna mapa runtime`

Ten zapis nie jest grafem wszystkich zależności runtime ani uprawnieniem do edycji sąsiedniej domeny. Adapter avatara korzysta z publicznego `DiveMovementSystem` w root, a root instancjonuje i steruje publiczną sceną avatara, więc zależności runtime są w tych dwóch kierunkach. Są dozwolone wyłącznie przez jawną granicę `runtime/Diver.tscn` i `DiverController`; mapa może konsumować tę samą publiczną scenę tylko na granicy integracyjnej. Grafika nie definiuje collidera, a mapa nie definiuje avatara.

## Twarde bramki fizyki i prezentacji

- Nie skaluj korzenia `CharacterBody2D` w celu zmniejszenia grafiki. Root skaluje również collider, `InteractionRange`, światło, sockety i dzieci kamery.
- Collider gameplayowy pozostaje jedną stabilną, prostą bryłą. Nie dodawaj collidera per klatka ani collidera animowanego razem z płetwami.
- `InteractionRange` znajduje się w scenie, ale jego wartość i znaczenie należą do globalnego kontraktu interakcji. Nie zmieniaj go jako efektu ubocznego pracy nad grafiką.
- Zmiana sprite'a albo skali wymaga pomiaru widocznej alfy wszystkich klatek, jawnej tolerancji tylnego zwisu płetw oraz kontroli przodu głowy, góry i dołu względem bryły fizycznej.
- `LampSocket` jest wyłącznie wizualnym punktem profilu. Jedyny gameplayowy `DiveLight` pozostaje centralnie na originie `CharacterBody2D`; nie przesuwaj go razem z animacją, socketem, obrotem ani `flip_h` i nie dodawaj kierunkowego stożka.
- Stan, promień, energia, kolor, cienie i wpływ radialnej latarni na zagrożenia pozostają w ogólnych systemach root. Warsztat kontroluje jej pojedynczy centralny montaż oraz czytelność avatara.
- VFX nie zmieniają ruchu, tlenu, hałasu, czasu, obrażeń, collidera ani zapisu.
- Profil `low/medium/high` i `reduced_motion` zmienia wyłącznie budżet i wtórny ruch prezentacji.

Obecna scena zachowuje bryłę zatwierdzoną w aktywnym ARD i walidowanym profilu koperty, root w skali `1` oraz kalibrację grafiki opisaną w `.ai/PROJECT_CONTEXT.md`. Każda przyszła zmiana koperty albo collidera pozostaje osobnym zadaniem produktu i integracji.

## Authoring aktywnej grafiki 2D

Widoczny wynik runtime pozostaje realistycznym/rysunkowym 2D zgodnie z globalnym ARD-0103. Jedynymi authority grafiki są aktywne PNG, `SpriteFrames` i profile pod `assets/`; warsztat nie utrzymuje zatwierdzonego modelu 3D, generatora AI ani roboczego stagingu. Dodanie nowego źródła offline, generatora albo równoległej sceny wymaga osobnej decyzji i nie może bocznie zmieniać aktywnego runtime.

Nowy raster musi zostać odebrany jako spójny komplet w docelowej natywnej rozdzielczości. Nie przyjmuj niezależnie wygenerowanych klatek, dużego pustego canvasu z małą sylwetką ani wyniku, którego zgodność uzyskano przez przypadkowe skalowanie całego roota. Zachowuj przezroczystość, kierunek, liczbę klatek, UID i ustawienia mipmap wymagane przez aktywny zasób.

## Workflow zmiany

1. Zaklasyfikuj zmianę jako: organizacja bez zmiany zachowania, raster/animacja, socket/VFX, fizyczna koperta albo integracja root/mapa.
2. Dla nowej grafiki przygotuj kompletny kandydat poza aktywnymi ścieżkami, przeprowadź osobny odbiór i dopiero potem wykonaj atomową promocję obejmującą PNG, `SpriteFrames`, profil socketów, profil koperty i scenę w tej kolejności. Roboczy model, generator i odrzucone rendery nie należą do pakietu runtime.
3. Nie poprawiaj `.godot/imported`, cache UID ani plików pochodnych. Przenoś PNG razem z wersjonowanym `.import`; po zmianie ścieżki pozwól izolowanemu importowi potwierdzić wynik.
4. Narzędzia zewnętrzne nie zapisują do `assets/animation/`, `assets/profiles/`, `assets/shaders/`, `definitions/` ani `runtime/` bez jawnego zadania promocji. Nie używaj automatycznego nadpisania jako skrótu etapu review.
5. Uruchom lokalny test, odpowiednie testy root i — dla zmiany widocznej — natywny capture. Capture trzeba obejrzeć; samo `PASS` nie zatwierdza grafiki.
6. Zmiana collidera, światła przy ścianie albo wymiarów wymaga również rzeczywistego kontaktu z pionową i poziomą przeszkodą oraz ponownej oceny tras mapy proporcjonalnie do wpływu.

## Build, testy i zapis

Dokładne komendy należą do `README.md`. Zawsze używaj wspólnego runnera z katalogu nadrzędnego; nie twórz lokalnego `project.godot`, autoloadu, runnera ani cache `.godot`. Testy Godot uruchamiaj sekwencyjnie. `ERROR`, `SCRIPT ERROR`, timeout albo niezerowy kod oznaczają porażkę.

Testy nie mogą korzystać z prawdziwego autosave. Avatar nie jest częścią trwałego formatu kampanii; sama zmiana ścieżki albo prezentacji nie podnosi rewizji zapisu ani podpisu mapy. Jeżeli proponowana zmiana zaczyna wymagać nowego trwałego pola, zatrzymaj się i wróć do globalnej bramki.

## Dokumentacja i wspólny checkout

Lokalne `.ai/PROJECT_CONTEXT.md` przechowuje tylko bieżącą migawkę avatara, luki i wynik weryfikacji. Lokalne `.ai/DECISIONS.md` przechowuje trwałe decyzje authoringu. `README.md` jest onboardingiem, a ten plik wyłącznie procesem. Nie twórz innych plików dokumentacyjnych.

Po każdej edycji sprawdź `git -C .. diff --name-only` i `git -C .. status --short`. Zachowuj niezwiązane zmiany użytkownika. Nie resetuj, nie odtwarzaj starej sceny w root i nie przenoś systemów mapy albo sesji tylko po to, aby katalog wyglądał na samowystarczalny.
