# Instrukcje dla agenta

Jesteś programistą Godot pracującym w tym repozytorium. Stosuj konwencje Godot oraz istniejącą strukturę scen, skryptów, zasobów i ustawień `project.godot`.

`AGENTS.md` określa wyłącznie proces pracy: kolejność poznawania kontekstu, sposób weryfikacji i routing dokumentacji. Nie ustanawia mechanik gry, bieżącego stanu implementacji ani technicznych kontraktów systemów.

## Kontekst przed pracą

Jeżeli główny zakres zadania dotyczy konkretnej mapy podwodnej albo jej worldowych grafik, niezależnie od początkowego katalogu roboczego najpierw przeczytaj `underwater_map_workbench/AGENTS.md`, ustaw katalog roboczy narzędzi na `underwater_map_workbench/` i zastosuj jego routing. Gdy zakres dotyczy prywatnej topologii, grafiki, assetów albo runtime jednej zarejestrowanej struktury, po mapowym punkcie wejścia przejdź także do `underwater_map_workbench/structures/<id>/AGENTS.md` i ustaw CWD na ten pakiet. Jeżeli zakres dotyczy avatara gracza — sceny nurka, jego fizycznej bryły, grafiki, animacji, socketów, światła lub VFX — analogicznie przejdź najpierw do `diver_workbench/AGENTS.md` i ustaw katalog roboczy na `diver_workbench/`. Mapa i Nurek pozostają dwoma zatwierdzonymi wyjątkami domenowymi od poniższego protokołu pełnego odczytu; pakiet struktury jest podrzędną granicą Mapy, nie trzecim warsztatem. Routing nie osłabia globalnej bramki rozbieżności, ochrony zapisu ani zasad testów.

Przed analizą repozytorium, planem zmian lub edycją przeczytaj w całości, w tej kolejności:

1. `.ai/PROJECT_CONTEXT.md`;
2. `.ai/DECISIONS.md`.

Następnie, nadal przed pracą merytoryczną, przeczytaj w całości dokumenty wymagane przez zakres zadania:

3. `docs/OgolnyZarys.txt` — zasady gry, balans, narracja, zakres funkcji i doświadczenie gracza;
4. `docs/Ostatni_Pomost_architektura_Godot.txt` — kod, sceny, dane, zapis, migracje, kolejność systemów i testy;
5. `README.md` — instalacja, uruchamianie, sterowanie, runner testów lub onboarding.

Zadanie łączące produkt z implementacją wymaga obu dokumentów z punktów 3 i 4, zawsze w tej kolejności. Zadanie dotyczące samych dokumentów wymaga wszystkich pięciu dokumentów merytorycznych.

Samo żądanie wskazania, które dokumenty będą lub nie będą aktualizowane, nie czyni zadania dokumentacyjnym; zakres odczytu wynika z głównej zmiany produktu lub implementacji. `README.md` czytaj tylko wtedy, gdy zadanie może wpłynąć na onboarding, wymagania, uruchamianie, runner testów albo podstawowe sterowanie, i przed jego treścią krótko podaj to uzasadnienie.

„Przeczytaj w całości” oznacza przekazanie całej treści do kontekstu agenta. Wynik ucięty przez limit, wspólny odczyt kilku plików z uciętym wyjściem, wyszukiwanie słów kluczowych ani odczyt przekierowany do `Out-Null` nie spełniają tego warunku. Długie pliki czytaj w kolejnych, jawnych fragmentach. Przed i po odczycie porównaj SHA-256. Jeżeli hash jest niedostępny, użyj rozmiaru i czasu modyfikacji jako słabszego fallbacku i zaznacz to w podsumowaniu. Gdy plik zmienił się w trakcie, przeczytaj jego aktualną wersję ponownie w całości.

Kolejność dotyczy pierwszego skutecznego, pełnego i widocznego dla modelu odczytu. Późniejszy ponowny odczyt nie naprawia wcześniejszego rozpoczęcia analizy. Do zakończenia wymaganych odczytów nie wykonuj inwentaryzacji repozytorium (`rg`, `rg --files`), nie czytaj kodu ani dokumentu z dalszego punktu — w tym README przed jego kolejnością. Jeżeli mechanizm odczytu lub metadanych jest blokowany, zmień go wyłącznie dla aktualnie wymaganego pliku; nie testuj dostępu przez inne źródło. Nie deklaruj spełnienia protokołu, jeśli nie potwierdziłeś kompletności i stabilności wersji.

W podsumowaniu zadania wymień dokumenty przeczytane w całości. Nie deklaruj pełnego odczytu, jeżeli wyjście było ucięte lub treść nie trafiła do kontekstu.

`README.md` jest punktem wejścia dla człowieka, ale nie zastępuje dokumentów wymaganych powyżej.

### Routing mapy podwodnej i grafiki świata

Jeżeli głównym zakresem zadania jest projektowanie `UnderwaterMap`, makroterenu, landmarków, trasy tutorialu, tła, grafiki, shaderów albo assetów konkretnego świata nurkowania, przejdź do `underwater_map_workbench/AGENTS.md`. Gdy zadanie rozpoczęto w korzeniu repozytorium, przeczytaj ten lokalny plik przed doborem dalszego kontekstu; gdy Codex uruchomiono bezpośrednio z katalogu warsztatu, jest on już właściwym punktem wejścia.

Lokalny `AGENTS.md` dobiera następnie lokalną migawkę, decyzje, README oraz potrzebne sekcje dokumentów globalnych proporcjonalnie do ryzyka zadania. Do każdego wskazanego tam odczytu stosuj wymagania kompletności i SHA-256. Routing wynika z intencji zadania, nie z fizycznej ścieżki. `underwater_map_workbench/map_manifest.json` jest jedynym authority rejestracji i globalnego placementu mapy, a zarejestrowany `structures/<id>/structure_manifest.json` podrzędnym authority wyłącznie lokalnej zawartości jednego budynku. Lokalna `UnderwaterMap.tscn` pozostaje ich deterministyczną pochodną. Nie wolno utrzymywać kopii tych plików ani drugiego katalogu grafiki świata w root. Avatar gracza nie należy do pakietu mapy. Pełny checkout projektu musi pozostać dostępny w katalogu nadrzędnym dla integracji i testów.

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
| Struktura: prywatna topologia, grafika, runtime i testy jednego `structures/<id>/` | wyłącznie własne `underwater_map_workbench/structures/<id>/**`; `--seal-structure-package <id>` może zaktualizować tylko lokalny manifest | Mapa, inne pakiety, Root i Nurek tylko do odczytu | mapowy pin/rejestr, origin, wspólna Mapa, inny pakiet, root albo Nurek |
| Nurek: scena i prezentacja avatara | wyłącznie `diver_workbench/**` | publiczne kontrakty root i Mapy tylko do odczytu | root oraz `underwater_map_workbench/**` |

- Zadanie dotykające więcej niż jednego właściciela jest zakresem integracyjnym prowadzonym z root. Przed edycją trzeba wymienić planowane ścieżki zapisu, przypisać im właścicieli i przeczytać pełny kontekst każdej dotkniętej domeny. Sam lokalny agent nie rozszerza sobie allowlisty.
- Lokalny warsztat może korzystać z publicznych scen, zasobów, typów i kontraktów projektu nadrzędnego, ale nie może ich kopiować ani poprawiać przy okazji lokalnego zadania. Potrzebna zmiana poza allowlistą wraca do root jako osobny albo jawnie mieszany zakres.
- Prywatne zadanie jednej struktury ma węższą allowlistę `underwater_map_workbench/structures/<id>/**`. `--seal-structure-package <id>` może zaktualizować wyłącznie hashe i digesty jego lokalnego `structure_manifest.json`; nie zapisuje mapowego pinu, rejestru, originu, globalnego payloadu, buildera ani innego pakietu. `--refresh-structure-package <id>` jest osobnym krokiem właściciela Mapy lub integratora i nigdy nie przepisuje prywatnego manifestu.
- Test wnętrza jednej domeny należy do jej warsztatu. Test składający Root, Mapę i Nurka należy do root i sprawdza publiczne zachowanie, bez zamrażania prywatnej hierarchii węzłów, liczby klatek, współrzędnych manifestu ani innych lokalnych fixture'ów.
- Plik fizycznie lokalny może publikować kontrakt globalny. Zmiana collidera avatara, zasięgu interakcji, parametrów ruchu, stable ID, schematu manifestu, `WorldDelta`, persistence albo publicznej granicy sceny wymaga routingu integracyjnego niezależnie od ścieżki pliku. Lokalna kolizja ścian lub urządzeń jednego budynku pozostaje authoringiem jego pakietu; przechodzi mapowy build/promocję, a do root wraca dopiero wtedy, gdy zmienia zachowanie widoczne dla gracza, publiczny kontrakt fizyki albo globalną partycję Mapy.
- Dozwolony jest read-only audyt całego repozytorium po zakończeniu wymaganych odczytów. Powyższa macierz ogranicza zapisy, nie analizę zależności.

### Współbieżność agentów

- Jednocześnie zapisujący agenci Rootu, Mapy, Nurka i każdego `structures/<id>/` pracują w osobnych pełnych Git worktrees oraz na gałęziach `codex/<owner>/<task-slug>` z jawnego commita integracyjnego potwierdzonego candidate receiptem i zgodnym pełnym run receiptem `PASS`. Sam osobny CWD nie izoluje wspólnego checkoutu. Bieżącego dirty checkoutu nie wolno automatycznie uznać za baseline ani kopiować do worktrees; nie blokuje on jednak materializacji exact HEAD/tree już wystawionego immutable receiptu.
- Przed pierwszym zapisem agent deklaruje ownera i zamknięty write-set oraz uruchamia `python tools/workbench_contract.py doctor --owner <owner> --intent author`; przed hand-offem wykonuje `python tools/workbench_contract.py validate --owner <owner> --diff` i porównuje pełny diff z allowlistą. Ten sam plik lub owner wymaga osobnej gałęzi i zwykłego scalenia źródeł; nie wolno uzgadniać kolizji przez ostatni zapis ani scalać ręcznie wygenerowanych pochodnych.
- Worktree producenta może pozostawać czerwone. Przed hand-offem autor wykonuje `git fetch --prune`, owner doctor/diff i celowane testy, po czym przekazuje exact commit SHA oraz receipt. Pushuje wyłącznie własną gałąź `codex/*`, nigdy `main`; po przekazaniu SHA nie rebase'uje ani nie force-pushuje tej rewizji. Integrator konsumuje niezmienny commit albo zweryfikowaną rewizję FROZEN i nigdy nie czyta ruchomego katalogu autora. Zależność od cudzego zadania wskazuje exact SHA albo stacked PR po `fetch`, nie live worktree ani ruchomy tip gałęzi.
- `underwater_map_workbench/map_manifest.json`, `UnderwaterMap.tscn`, mapowe metadane builda oraz `structures/*/generated/**` są wspólnym zestawem publikacji Mapy. Obliczenia kandydata odbywają się poza blokadą ze sealed inputu; tylko ponowny hash i per-path CAS/rollback z markerem kompletności zapisanym na końcu zajmują krótką blokadę `map-promotion` wyprowadzoną ze wspólnego katalogu Git. Nie jest to filesystemowa atomowość wieloplikowa dla czytelników ignorujących lock; mapowe authority czyta i publikuje wyłącznie integrator respektujący tę blokadę.
- `--refresh-structure-package <id>` i pełny mapowy build należą do integratora Mapy. Gdy od ostatniej promocji zmieniło się kilka sealed manifestów, integrator przekazuje wszystkie pary `<id>, <SHA256>` w jednej komendzie batch, aby powstał jeden walidowany kandydat i jeden CAS zamiast niemożliwej mieszanej rewizji. Prywatny `--seal-structure-package`, `--build-structure`, `--check-structure` i test jednego pakietu nie wykonują globalnego discovery ani nie blokują innych struktur. Celowany test Nurka lub Rootu również nie odkrywa niezwiązanych pakietów.
- Domyślny runner kopiuje pliki śledzone oraz niesledzone, których nie wykluczają standardowe reguły Git, i potwierdza `źródło przed == źródło po == kopia`. Każdy isolated run ma własne `.godot`, `user://`, logi, porty procesu i capture; równoległy Godot jest dozwolony tylko w osobnych pełnych workspace z jawnym `--path`. Runner odrzuca `-InPlace`, ponieważ nie tworzy ono kompletnej granicy snapshotu i danych użytkownika. Candidate/publication receipt potwierdza pliki, a osobny run receipt wiąże HEAD/tree, snapshot, overlay, runner, Godot, cele i wyniki; tylko ich zgodność oraz pełny `PASS` może potwierdzić `last-green`.
- `main` ani ref ostatniego zielonego stanu nie przyjmuje czerwonego kandydata. Osobny worktree integracyjny składa jawny zestaw rewizji na najnowszej bazie i publikuje go dopiero po build/check, imporcie oraz wymaganych testach; porażka nie blokuje producentów i nie odbiera im zielonej podstawy. Lokalny pre-push guard blokuje agentom bezpośredni push do `main`; zdalna branch protection/required checks jest obowiązkowa tam, gdzie pozwala na nią hosting i plan, a bez niej jeden integrator egzekwuje kolejkę proceduralnie.
- Producent przekazujący pakiet poza aktywnym authority może opublikować niezmienny katalog poleceniem `python tools/freeze_workbench_revision.py freeze --source <working> --target <revision>` i dalej pracować w innym katalogu. Integrator wykonuje `verify --target <revision>`; `FROZEN_RECEIPT.json` jest dowodem zestawu i SHA, nie dokumentacją ani zgodą na promocję.

## Zasady pracy

- Przed zmianą sprawdź aktualny kod, sceny, dane, testy oraz obowiązujące decyzje dotyczące zadania.
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

Przed pierwszą edycją porównaj żądaną zmianę z bieżącym runtime i obowiązującymi ARD oraz — zależnie od zakresu zadania — z dokumentem produktu, architekturą i kontraktem zapisu.

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
- Prywatna iteracja `structures/<id>/` po zmianie źródła lub hasha używa `--seal-structure-package <id>`, następnie lokalnych `--build-structure <id>`, `--check-structure <id>` oraz testów kontraktu i runtime pakietu. Integrator Mapy wykonuje `--refresh-structure-package <id>` dla przyjętej sealed rewizji. Pełny mapowy build/check i smoke uruchamiaj przy rejestracji, zmianie originu, publicznym montażu albo przed odbiorem integracyjnym, nie po każdej prywatnej zmianie.

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

Przed pierwszą edycją przedstaw użytkownikowi w krótkiej wiadomości roboczej decyzję `aktualizuję / nie aktualizuję` z uzasadnieniem dla każdego z pięciu globalnych dokumentów merytorycznych; uwzględnij także `AGENTS.md`, jeżeli zmienia się proces pracy. Dla zadania routowanego do mapy albo avatara oceń w tym samym komunikacie trzy lokalne dokumenty merytoryczne właściwego warsztatu oraz jego lokalny `AGENTS.md`. Dla zadania jednej struktury oceń dodatkowo jej `AGENTS.md` i `README.md`, bez tworzenia lokalnego rejestru decyzji lub kontekstu. Nowy komunikat, podgląd, ostrzeżenie, informacja zwrotna albo prezentowana konsekwencja widoczna dla gracza jest zmianą produktu i wymaga oceny `OgolnyZarys.txt`, nawet gdy algorytm domenowy pozostaje bez zmian.

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
