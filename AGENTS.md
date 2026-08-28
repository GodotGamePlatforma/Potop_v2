# Instrukcje dla agenta

Jesteś programistą Godot pracującym w tym repozytorium. Stosuj konwencje Godot oraz istniejącą strukturę scen, skryptów, zasobów i ustawień `project.godot`.

`AGENTS.md` określa wyłącznie proces pracy: kolejność poznawania kontekstu, sposób weryfikacji i routing dokumentacji. Nie ustanawia mechanik gry, bieżącego stanu implementacji ani technicznych kontraktów systemów.

## Kontekst przed pracą

Zaczynaj od najmniejszego kontekstu potrzebnego do wykonania zadania. Dla zwykłej, lokalnej poprawki — na przykład collidera jednej wieży — przeczytaj najbliższy `AGENTS.md`, odpowiedni fragment krótkiego lokalnego `PROJECT_CONTEXT.md`, a następnie tylko zmieniany kod, dane i związane testy. Nie czytaj całego rejestru decyzji, dokumentu produktu ani całej architektury, jeśli zadanie nie zmienia ich kontraktu.

Routing jest prosty:

- Mapa lub grafika świata: `underwater_map_workbench/AGENTS.md` i CWD `underwater_map_workbench/`.
- Jedna struktura: dodatkowo jej `underwater_map_workbench/structures/<id>/AGENTS.md` i CWD pakietu.
- Avatar Nurka: `diver_workbench/AGENTS.md` i CWD `diver_workbench/`.
- Systemy ogólne, kampania, UI, zapis albo integracja kilku właścicieli: ten plik i CWD root.

Pełny kontekst jest wyjątkiem. Przeczytaj właściwe `.ai/DECISIONS.md`, `docs/OgolnyZarys.txt` i `docs/Ostatni_Pomost_architektura_Godot.txt` w całości tylko wtedy, gdy zadanie:

- zmienia regułę produktu albo zatwierdzone zachowanie widoczne dla gracza, zamiast jedynie naprawiać lokalną implementację istniejącego kontraktu;
- zmienia publiczny kontrakt, właściciela danych albo granicę modułu;
- zmienia zapis, persistence, schema lub wymaga migracji;
- obejmuje semantyczną zmianę u więcej niż jednego właściciela; samo atomowe odtworzenie pinu i deterministycznych pochodnych po prywatnej zmianie jednej struktury nie uruchamia pełnego odczytu;
- jest zmianą samych decyzji albo przekrojowej architektury.

`README.md` czytaj, gdy potrzebujesz komendy, konfiguracji, uruchomienia lub onboardingu. Kontrolę SHA-256 dokumentów stosuj wyłącznie w powyższym pełnym odczycie albo gdy stabilność wersji jest istotna dla audytu; rutynowa poprawka nie wymaga ceremonii hashy. Jeżeli wykryjesz konflikt runtime z aktywnym kontraktem, zastosuj bramkę rozbieżności poniżej.

### Routing mapy podwodnej i grafiki świata

Jeżeli głównym zakresem zadania jest projektowanie `UnderwaterMap`, makroterenu, landmarków, trasy tutorialu, tła, grafiki, shaderów albo assetów konkretnego świata nurkowania, przejdź do `underwater_map_workbench/AGENTS.md`. Gdy zadanie rozpoczęto w korzeniu repozytorium, przeczytaj ten lokalny plik przed doborem dalszego kontekstu; gdy Codex uruchomiono bezpośrednio z katalogu warsztatu, jest on już właściwym punktem wejścia.

Lokalny `AGENTS.md` dobiera kontekst proporcjonalnie do ryzyka. Routing wynika z intencji zadania, nie z fizycznej ścieżki. `underwater_map_workbench/map_manifest.json` jest jedynym authority rejestracji i globalnego placementu mapy, a zarejestrowany `structures/<id>/structure_manifest.json` podrzędnym authority wyłącznie lokalnej zawartości jednego budynku. Lokalna `UnderwaterMap.tscn` pozostaje ich deterministyczną pochodną. Nie wolno utrzymywać kopii tych plików ani drugiego katalogu grafiki świata w root. Avatar gracza nie należy do pakietu mapy. Pełny checkout projektu musi pozostać dostępny w katalogu nadrzędnym dla integracji i testów.

### Routing pakietu struktury mapy

Zadanie prywatne dla jednego `structures/<id>/` — jego lokalna topologia, sockety, grafika, skrypty, zachowanie runtime, test lub capture — po obowiązkowym kontekście Mapy korzysta z najbliższego `AGENTS.md` i domyślnie zapisuje wyłącznie we własnym pakiecie. Dokładny rekord tej struktury w `map_manifest.json` pozostaje zależnością tylko do odczytu i jedynym źródłem stable ID, originu, aktywności oraz opcjonalnego landmarku.

Zmiana rejestracji, originu, globalnej partycji albo kompozycji więcej niż jednego pakietu jest zadaniem Mapy prowadzonym z `underwater_map_workbench/`. Zmiana zachowania widocznego dla gracza, publicznej granicy Root–Mapa, persistence albo zapisu jest zakresem integracyjnym prowadzonym z root. Pakiet nie tworzy własnego `.ai`, `project.godot`, mapowego manifestu, sceny mapy ani reguł kampanii.

### Routing avatara nurka

Jeżeli głównym zakresem zadania jest `Diver.tscn`, `DiverController`, collider gracza, jego skala, animacja, sprite, sockety, punkt emisji latarni, shader czytelności, `DiverVisualEffects` albo lokalny capture/test prezentacji, przejdź do `diver_workbench/AGENTS.md`. Warsztat nurka jest jedynym źródłem tych elementów i działa w projekcie nadrzędnym; nie twórz drugiego `project.godot`, kopii sceny w `scenes/diving` ani kopii assetów w warsztacie mapy.

Lokalny routing rozdziela fizyczną i wizualną kopertę avatara od ogólnych reguł wyprawy. `DiveController`, `DiveMovementSystem`, tlen, ryzyko, walka, wyposażenie, interakcje, sesja, wynik, UI, zapis i mapa pozostają w root albo w swoim istniejącym module. Zmiana widocznej skali, zasięgu, ruchu lub skutku kolizji nadal wymaga globalnej bramki produktu i architektury.

### Granice odczytu i zapisu

Położenie procesu ani możliwość technicznego zapisu nie rozszerzają zakresu zadania. Domyślna macierz właścicieli jest następująca:

| Zakres zadania | Dozwolony domyślny zapis | Dozwolony odczyt | Zapis wymagający przekierowania |
|---|---|---|---|
| Root: kampania, systemy ogólne, dane, zapis, UI, integracja i wspólny runner | cały root z wyłączeniem `underwater_map_workbench/**` i `diver_workbench/**` | oba warsztaty jako zależności tylko do odczytu | każde źródło należące do Mapy albo Nurka |
| Mapa: rejestr, globalne złożenie, wspólny builder/kompilator i grafika świata | `underwater_map_workbench/**` z wyłączeniem prywatnych źródeł istniejących `structures/<id>/`; builder może odtworzyć ich `generated/**` | pakiety struktur oraz publiczne kontrakty root i Nurka tylko do odczytu | prywatne źródło jednego pakietu, root oraz `diver_workbench/**` |
| Struktura: prywatna topologia, grafika, runtime i testy jednego `structures/<id>/` | wyłącznie własne `underwater_map_workbench/structures/<id>/**`; kanoniczne uszczelnienie może zaktualizować tylko lokalny manifest | Mapa, inne pakiety, Root i Nurek tylko do odczytu | mapowy pin/rejestr, origin, wspólna Mapa, inny pakiet, root albo Nurek |
| Nurek: scena i prezentacja avatara | wyłącznie `diver_workbench/**` | publiczne kontrakty root i Mapy tylko do odczytu | root oraz `underwater_map_workbench/**` |

- Zadanie semantycznie dotykające więcej niż jednego właściciela jest zakresem integracyjnym prowadzonym z root. Wtedy przed edycją ustal zamknięty zestaw zapisu i przeczytaj pełny kontekst dotkniętych domen. Rutynowa zmiana jednego właściciela nie wymaga deklarowania listy dokumentów ani pełnego write-setu przed pracą; nadal nie rozszerza samodzielnie allowlisty.
- Lokalny warsztat może korzystać z publicznych scen, zasobów, typów i kontraktów projektu nadrzędnego, ale nie może ich kopiować ani poprawiać przy okazji lokalnego zadania. Potrzebna zmiana poza allowlistą wraca do root jako osobny albo jawnie mieszany zakres.
- Prywatne zadanie jednej struktury ma węższą allowlistę `underwater_map_workbench/structures/<id>/**`. Gdy publikacja źródła wymaga także aktualizacji mapowego pinu i deterministycznych pochodnych, obowiązuje wąski wyjątek: jedno proste zadanie routowane przez root, jeden Codex, worktree, branch `codex/structure-<id>/<task-slug>` i PR obejmujące pakiet oraz wymagany wynik publikacji Mapy. Nie wolno rozdzielać tego na PR struktury i późniejszy PR Mapy.
- Ten mechaniczny wyjątek publikacyjny nie jest sam w sobie zmianą kontraktu wielu właścicieli i nie wymaga pełnego odczytu decyzji, produktu ani architektury. Agent wykonuje jeden gotowy przepis z najbliższego README pakietu, celowane testy oraz lokalny `fast-check`; pełną certyfikację złożenia wykonuje merge queue.
- Test wnętrza jednej domeny należy do jej warsztatu. Test składający Root, Mapę i Nurka należy do root i sprawdza publiczne zachowanie, bez zamrażania prywatnej hierarchii węzłów, liczby klatek, współrzędnych manifestu ani innych lokalnych fixture'ów.
- Plik fizycznie lokalny może publikować kontrakt globalny. Zmiana collidera avatara, zasięgu interakcji, parametrów ruchu, stable ID, schematu manifestu, `WorldDelta`, persistence albo publicznej granicy sceny wymaga routingu integracyjnego niezależnie od ścieżki pliku. Lokalna kolizja ścian lub urządzeń jednego budynku pozostaje authoringiem jego pakietu; przechodzi mapowy build i odtworzenie pochodnych, a do root wraca dopiero wtedy, gdy zmienia zachowanie widoczne dla gracza, publiczny kontrakt fizyki albo globalną partycję Mapy.
- Dozwolony jest read-only audyt całego repozytorium po zakończeniu wymaganych odczytów. Powyższa macierz ogranicza zapisy, nie analizę zależności.

### Współbieżność i droga zmiany

- Root lub koordynator przydziela jedno proste, niezależne zadanie jednemu agentowi. Zadanie implementacyjne zawsze uruchamia bezpośrednio jako **Worktree**, nigdy jako Local. Każde zadanie ma osobny pełny Git worktree i gałąź `codex/<owner>/<task-slug>` utworzoną z aktualnego `origin/main`; zadanie seal+pin struktury używa `codex/structure-<id>/<task-slug>`. Sam osobny CWD albo gałąź `codex/*` we wspólnym głównym checkoutcie nie daje izolacji.
- Zadania zapisujące wspólny zestaw publikacji Mapy — `underwater_map_workbench/map_manifest.json`, `underwater_map_workbench/UnderwaterMap.tscn`, mapowe metadane builda lub `underwater_map_workbench/structures/*/generated/**` — koordynator uruchamia i publikuje sekwencyjnie z aktualnego `origin/main`; kolejne takie zadanie zaczyna się dopiero po stanie `MERGED` albo `CLOSED` poprzedniego PR, a inne zadania o rozłącznych zapisach nadal pracują równolegle.
- Gdy zadanie rozpoczęte jako „tylko analiza” zmienia się we „wdroż”, agent najpierw wykonuje **Hand off do Worktree**, następnie tworzy w tym worktree gałąź `codex/*`, a dopiero potem edytuje pliki. Jeżeli nie może wykonać Handoff, zatrzymuje się przed pierwszą edycją i prosi root lub użytkownika o przeniesienie zadania.
- Agent skupia się na zadaniu: `implementacja -> lokalne testy zadania -> lokalny fast-check`. Porażkę poprawia i powtarza właściwy etap. Dopiero po `PASS` wykonuje `commit -> push + PR -> KONIEC`. Lokalne testy zadania i fast-check są osobnymi krokami; fast-check może defensywnie powtórzyć część testów, ale ich nie zastępuje. `tools/publish_agent_pr.ps1` publikuje exact commit, tworzy lub aktualizuje jeden PR i dla zwykłej zmiany włącza squash auto-merge. Agent nie pushuje do `main`, nie polluje i nie babysituje kolejki. Nie mówi „gotowe” ani „wdrożone”, dopóki udany wynik publishera nie potwierdzi `LocalHead = RemoteHead = PullRequestHead` dla dokładnie jednego otwartego PR.
- Po utworzeniu PR osobny, wymagany GitHub `fast-check` sprawdza dokładny head PR. Nie jest to wynik lokalnego fast-checku. `FAIL` pozostawia PR otwarty, a tylko `PASS` pozwala dodać go do merge queue, również dla rzadkiej zmiany control-plane. Pełny `integration-green` działa wyłącznie na merge group `aktualny main + dany PR`: `FAIL` oznacza brak merge, a `PASS` pozwala na squash do `main`.
- Merge queue sama składa PR z aktualnym `main`. Jeżeli wystąpi prawdziwy konflikt albo `integration-green` wykryje nieaktualny seal, pin lub pochodne, koordynator jawnie zastępuje i zamyka stary PR oraz przydziela nowe zadanie naprawcze. Nowy agent zaczyna z aktualnego `main` w świeżym worktree, branchu i PR; nie wznawia się autora starego PR do codziennego rebase'u.
- Każdy test Godota korzysta z osobnego workspace, `.godot`, `user://`, logów, katalogów tymczasowych i portów. Równoległy Godot jest dozwolony tylko w odseparowanych pełnych kopiach z jawnym `--path`; wspólny runner odrzuca `-InPlace`.
- Pliki śledzone z atrybutem `eol=lf` pozostają LF. Runner i builder wykonują bramkę EOL automatycznie; agent naprawia wskazany plik zamiast tworzyć dodatkowe dowody procesu.
- Automatyczna ścieżka publikacji klasyfikuje workflowy, narzędzia CI, konfigurację `integration-green` i control-plane buildera jako chronione. `publish_agent_pr.ps1` może opublikować taki PR, lecz nie włącza mu auto-merge ani automatycznego enqueue. Rzadka zmiana wymaga jawnej ręcznej decyzji właściciela i nadal musi przejść wymagany GitHub `fast-check` oraz pełny `integration-green` merge group. Bieżąca wspólna tożsamość GitHub nie daje twardego rozdzielenia autora od właściciela; pełna separacja wymagałaby osobnej GitHub App lub tożsamości i nie jest częścią tego wdrożenia.
- Lokalny czysty mirror `main` synchronizuje się wyłącznie przez sprawdzenie czystości, `fetch`, fast-forward i Git LFS. Dirty katalog zatrzymuje synchronizację; nie wolno używać automatycznego `reset --hard` ani kasować zmian.
- Aktywny builder po scaleniu bierze exact finalne SHA `main`, pobiera LFS, wykonuje build i smoke, zapisuje artefakt pod SHA i przesuwa `builds/current` tylko po `PASS`. Porażka pozostawia poprzednie `current` bez zmian.
- Root może koordynować wynik kolejki lub konflikt, ale zwykły autor kończy na PR. Historyczne protokoły koordynacji opisane w zastąpionych ARD-0108–0110 nie są częścią bieżącej pracy i nie należy ich ręcznie odtwarzać. Bieżący stan CI i buildera opisuje `.ai/PROJECT_CONTEXT.md`.

## Zasady pracy

- Przed zmianą sprawdź aktualny kod, sceny, dane i związane testy. Decyzje czytaj wtedy, gdy zadanie może zmienić ich kontrakt albo gdy lokalny kontekst wskazuje konkretną rozbieżność.
- Runtime odpowiada na pytanie „co działa teraz”, a obowiązujące ARD — „jaki kontrakt ma obowiązywać”. Rozbieżność jest luką do jawnego rozstrzygnięcia, nie zgodą na cichą zmianę jednej ze stron.
- Preferuj rozwiązania proste, czytelne i idiomatyczne dla Godot.
- Logikę umieszczaj w najmniejszym właściwym systemie domenowym. Sceny, kontrolery i UI pozostawiaj warstwą wiążącą oraz prezentacyjną.
- Nie twórz w scenach ani UI równoległego stanu lub drugiej kopii reguł domenowych.
- Nie implementuj elementu wyłącznie dlatego, że występuje jako `[DOCELOWE]`, `[LEGACY]`, `[HISTORYCZNE]`, nieużywane pole albo pusty hook.
- Zmiany trwałego stanu wykonuj zgodnie z obowiązującym kontraktem zapisu, migracji, walidacji i kompatybilności wstecznej. Nie reinterpretuj po cichu istniejących zapisów.
- Drobne i odwracalne szczegóły implementacyjne rozstrzygaj zgodnie z istniejącymi konwencjami projektu.
- Zachowuj cudze, niezwiązane zmiany w katalogu roboczym. Nie wykonuj destrukcyjnego resetu repozytorium.
- Jeżeli standardowe narzędzie edycji albo sandbox odrzuca zapis, nie obchodź blokady przez interpreter, ogólne MCP, bezpośrednie API systemu plików ani proces potomny. Zgłoś blokadę i pozostaw projekt bez zmian.

## Bramka rozbieżności

Przed pierwszą edycją sprawdź bieżący runtime i bezpośredni kontrakt związany z zadaniem. W rutynowej poprawce wystarczą najbliższy kontekst, zmieniane źródła i testy. Właściwe ARD, produkt, architekturę i kontrakt zapisu otwórz dopiero wtedy, gdy zakres spełnia warunki pełnego kontekstu z początku tego pliku albo gdy lokalne źródła ujawniają konflikt.

Rozbieżnością blokującą jest w szczególności zmiana istniejącej reguły produktu, aktywnego ARD, właściciela stanu, kolejności lub atomowości systemów, publicznej granicy danych albo semantyki zapisu, jak również budowanie nowej domeny na elemencie `[LEGACY]`, `[HISTORYCZNE]`, nieużywanym polu lub pustym hooku. Brak rozstrzygnięcia w źródłach także jest rozbieżnością blokującą, jeżeli warianty zmieniają produkt, architekturę albo zapis.

Samo wdrożenie elementu `[DOCELOWE]` nie jest rozbieżnością blokującą, jeżeli jego zatwierdzony kontrakt produktu i architektury jest kompletny, jednoznaczny i nie wymaga zmiany obowiązującego ARD ani semantyki zapisu. Zatrzymaj się, jeżeli tego kontraktu brakuje, występuje konflikt albo wdrożenie wymaga nowego rozstrzygnięcia produktu, architektury lub zapisu.

Jeżeli występuje rozbieżność blokująca, nie edytuj kodu, danych, testów ani dokumentacji i nie twórz nowego ARD. Najpierw przedstaw żądaną zmianę, bieżące zachowanie runtime, konkretne sprzeczne źródła, wpływ na produkt, architekturę, zapis, migracje, testy i dokumentację, możliwe warianty, rekomendację oraz dokładną decyzję wymagającą zatwierdzenia.

Po jednoznacznym wykryciu rozbieżności zbierz tylko minimalny dowód potrzebny do powyższego raportu. Przed zatwierdzeniem nie rozwijaj szczegółowego patcha, pełnej macierzy testów ani inspekcji plików niezwiązanych z decyzją.

Polecenie „wdróż”, „nie pytaj” albo równoważne, zawarte w tej samej wiadomości co rozbieżna propozycja, nie zatwierdza zastąpienia istniejącego kontraktu. Wdrożenie może rozpocząć się dopiero po kolejnej wiadomości użytkownika, która jawnie zatwierdza wskazany wariant. Jeżeli nie ma rozbieżności blokującej, a zadanie jest jednoznaczne, wykonaj je bez zbędnego pytania.

## Weryfikacja

- Weryfikuj zmiany proporcjonalnie do ryzyka. Po zmianie logiki uruchom adekwatne testy bezpośrednio przez Godot.
- W bieżącej kopii projektu uruchamiaj testy sekwencyjnie. Równoległe instancje Godot są dozwolone wyłącznie w osobnych pełnych kopiach projektu, każda z własnym cache `.godot`.
- Traktuj `ERROR` i `SCRIPT ERROR` jako porażkę także wtedy, gdy proces zwrócił kod wyjścia 0.
- Testy nie mogą używać prawdziwego autosave. Korzystaj z izolowanych ścieżek `user://test_*` albo wyłączonej persistence.
- Bezwarunkowe wymagania produktu, takie jak „zawsze”, „nigdy”, „dokładnie raz” i „dla każdego”, zamień na jawne przypadki testowe obejmujące wartości graniczne, bezpośrednie skoki między przedziałami, reset i powtórzenie stanu oraz kolizje priorytetów UI. `[AKTYWNE]` nadaj dopiero po przejściu tych przypadków w runtime.
- Najpierw uruchom testy właściwe dla zmienianego zachowania, potem osobny `tools/agent_fast_check.ps1`. Pełna regresja nie należy do zwykłego autora; wykonuje ją merge queue. Dodatkowe mechaniczne kroki wymagane przez generowane źródła struktury są opisane wyłącznie w najbliższym README pakietu.

## Dokumentacja

Projekt utrzymuje pięć globalnych dokumentów merytorycznych. Każdy rodzaj szczegółu ma jednego właściciela:

| Plik | Jest właścicielem | Nie zawiera | Aktualizuj, gdy |
|---|---|---|---|
| `.ai/PROJECT_CONTEXT.md` | krótkiej, datowanej migawki potwierdzonego runtime, luk, pułapek i ostatniej weryfikacji | pełnych reguł gry, algorytmów, tabel balansu, map migracji, historii decyzji ani instrukcji pracy | zmienił się zweryfikowany stan, luka, pułapka lub wynik weryfikacji |
| `.ai/DECISIONS.md` | trwałych decyzji, powodów, inwariantów, konsekwencji i jawnych zastąpień | bieżącego stanu wdrożenia, pełnej specyfikacji klas/pól/testów, roadmapy ani dziennika prac | zmienia się przekrojowy kontrakt, granica modułu/transakcji, znaczenie zapisu lub reguła dalszego rozwoju |
| `docs/OgolnyZarys.txt` | produktu: doświadczenia gracza, zasad, balansu, narracji i granicy aktywne/docelowe | klas, ścieżek, schematów, migracji, nazw testów i wewnętrznych algorytmów | zmienia się reguła lub skutek widoczny dla gracza, balans, narracja albo zatwierdzony zakres |
| `docs/Ostatni_Pomost_architektura_Godot.txt` | technicznego mapowania: właścicieli stanu, wejść/wyjść, przepływów, persistence, migracji, walidacji i mapy testów | powtórzonej wizji produktu, roadmapy, uzasadnienia decyzji, datowanego statusu wdrożenia ani pełnych tabel balansu | zmienia się odpowiedzialność systemu, przepływ, model danych, zapis, migracja lub kontrakt testowy |
| `README.md` | wejścia dla człowieka: wymagań, instalacji, uruchamiania, podstawowego sterowania, runnera testów i nawigacji | szczegółowych mechanik, algorytmów, architektury, migracji, ARD, bieżących luk ani datowanych wyników testów | zmienia się onboarding, wymaganie, komenda, podstawowe sterowanie lub krytyczna pułapka uruchomieniowa |

`underwater_map_workbench/` i `diver_workbench/` są jedynymi zatwierdzonymi wyjątkami domenowymi. Pierwszy posiada aktywny manifest mapy, generowaną scenę, builder, smoke test, shadery środowiska i worldowe assety podwodnego gameplayu; może zawierać podrzędne pakiety `structures/<id>/` zgodne z ARD-0106, ale nadal jest ich jednym właścicielem domenowym. Drugi posiada pojedynczą scenę avatara, jego adapter, fizyczną bryłę, grafikę, animację, sockety, shadery, VFX oraz lokalne testy i capture. Każdy warsztat ma własne `.ai/PROJECT_CONTEXT.md`, `.ai/DECISIONS.md`, `README.md` i `AGENTS.md`; struktura ma wyłącznie operacyjne `AGENTS.md` i `README.md`, bez własnego `.ai`. Nie wolno kopiować do nich globalnych reguł gry, właścicieli stanu ani persistence; root zachowuje przekrojowy kontrakt zgodnie z ARD-0102, ARD-0105 i ARD-0106.

Rutynowa zmiana kodu, danych albo grafiki nie wymaga przed edycją deklarowania aktualizacji wszystkich dokumentów. Aktualizuj tylko dokument, którego treść rzeczywiście się zmieniła, zgodnie z tabelą poniżej. Jeżeli zmiana wpływa na produkt, publiczny kontrakt, zapis lub wiele domen, ustal wymagane dokumenty w ramach pełnego kontekstu przed edycją. Nowy komunikat, podgląd, ostrzeżenie albo inna konsekwencja widoczna dla gracza wymaga oceny `OgolnyZarys.txt`.

Pełny szczegół zapisuj tylko u właściciela. Inny dokument może podać jedną potrzebną konsekwencję i odwołanie, ale nie drugą specyfikację. Dokładna aktywna wartość strojalna należy do walidowanego `Resource`; dokument produktu może wyjaśniać jej znaczenie dla gracza, a architektura wskazywać pole i konsumenta.

Każdy z pięciu dokumentów ma na początku lokalny kontrakt wpisu. Przestrzegaj go przy nowej treści. Gdy edytujesz zastaną sekcję, doprowadź całą tę sekcję do właściwej roli: zachowaj sens, przenieś szczegół do właściciela i w dawnym miejscu zostaw tylko odwołanie.

Routing zmiany:

1. Zmianę reguły, balansu lub narracji zapisz najpierw w `OgolnyZarys.txt`; dodaj ARD tylko dla trwałej decyzji przekrojowej; następnie zaktualizuj mapowanie architektoniczne, implementację i testy; `PROJECT_CONTEXT.md` dopiero po weryfikacji runtime.
2. Refaktor bez zmiany zachowania aktualizuje architekturę tylko wtedy, gdy zmienia opisane w niej mapowanie, odpowiedzialność systemu, przepływ, model danych albo kontrakt testowy; nie tworzy ARD ani wpisu produktowego. `PROJECT_CONTEXT.md` zmień tylko wtedy, gdy zmienia się ważna bieżąca granica lub pułapka.
3. Zmiana semantyki trwałego stanu lub zapisu wymaga najpierw ARD, potem architektury, migracji, walidacji i testów; stan trafia do `PROJECT_CONTEXT.md` po potwierdzeniu.
4. Sam wynik weryfikacji aktualizuje wyłącznie `PROJECT_CONTEXT.md`. Mapę testów zmień w architekturze tylko wtedy, gdy zmienił się zakres pokrycia albo ryzyka.
5. `README.md` zmień tylko wtedy, gdy użytkownik repozytorium musi inaczej projekt przygotować, uruchomić, przetestować lub obsłużyć na wejściu.

Nie twórz nowych plików dokumentacyjnych poza pięcioma globalnymi dokumentami, zatwierdzonymi zestawami `underwater_map_workbench/{AGENTS.md,README.md,.ai/PROJECT_CONTEXT.md,.ai/DECISIONS.md}` i `diver_workbench/{AGENTS.md,README.md,.ai/PROJECT_CONTEXT.md,.ai/DECISIONS.md}` oraz dokładnie `underwater_map_workbench/structures/<id>/{AGENTS.md,README.md}` dla zarejestrowanego pakietu. Pakiet struktury nie posiada `.ai`, własnego ARD ani drugiej specyfikacji gameplayu. Jawnie nieautorytatywny plik provenance wskazany przez `structure_manifest.json` jest materiałem źródłowym, nie dokumentem kontraktowym. Kod, dane, grafiki, audio i techniczne pliki projektu nie są dokumentacją.

Po zakończeniu zadania krótko podsumuj wynik, wykonaną weryfikację i najbardziej sensowny następny krok.
