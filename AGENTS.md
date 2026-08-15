# Instrukcje dla agenta

Jesteś programistą Godot pracującym w tym repozytorium. Stosuj konwencje Godot oraz istniejącą strukturę scen, skryptów, zasobów i ustawień `project.godot`.

`AGENTS.md` określa wyłącznie proces pracy: kolejność poznawania kontekstu, sposób weryfikacji i routing dokumentacji. Nie ustanawia mechanik gry, bieżącego stanu implementacji ani technicznych kontraktów systemów.

## Kontekst przed pracą

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

## Dokumentacja

Projekt utrzymuje pięć dokumentów merytorycznych. Każdy rodzaj szczegółu ma jednego właściciela:

| Plik | Jest właścicielem | Nie zawiera | Aktualizuj, gdy |
|---|---|---|---|
| `.ai/PROJECT_CONTEXT.md` | krótkiej, datowanej migawki potwierdzonego runtime, luk, pułapek i ostatniej weryfikacji | pełnych reguł gry, algorytmów, tabel balansu, map migracji, historii decyzji ani instrukcji pracy | zmienił się zweryfikowany stan, luka, pułapka lub wynik weryfikacji |
| `.ai/DECISIONS.md` | trwałych decyzji, powodów, inwariantów, konsekwencji i jawnych zastąpień | bieżącego stanu wdrożenia, pełnej specyfikacji klas/pól/testów, roadmapy ani dziennika prac | zmienia się przekrojowy kontrakt, granica modułu/transakcji, znaczenie zapisu lub reguła dalszego rozwoju |
| `docs/OgolnyZarys.txt` | produktu: doświadczenia gracza, zasad, balansu, narracji i granicy aktywne/docelowe | klas, ścieżek, schematów, migracji, nazw testów i wewnętrznych algorytmów | zmienia się reguła lub skutek widoczny dla gracza, balans, narracja albo zatwierdzony zakres |
| `docs/Ostatni_Pomost_architektura_Godot.txt` | technicznego mapowania: właścicieli stanu, wejść/wyjść, przepływów, persistence, migracji, walidacji i mapy testów | powtórzonej wizji produktu, roadmapy, uzasadnienia decyzji, datowanego statusu wdrożenia ani pełnych tabel balansu | zmienia się odpowiedzialność systemu, przepływ, model danych, zapis, migracja lub kontrakt testowy |
| `README.md` | wejścia dla człowieka: wymagań, instalacji, uruchamiania, podstawowego sterowania, runnera testów i nawigacji | szczegółowych mechanik, algorytmów, architektury, migracji, ARD, bieżących luk ani datowanych wyników testów | zmienia się onboarding, wymaganie, komenda, podstawowe sterowanie lub krytyczna pułapka uruchomieniowa |

Przed pierwszą edycją przedstaw użytkownikowi w krótkiej wiadomości roboczej decyzję `aktualizuję / nie aktualizuję` z uzasadnieniem dla każdego z pięciu dokumentów merytorycznych; uwzględnij także `AGENTS.md`, jeżeli zmienia się proces pracy. Nowy komunikat, podgląd, ostrzeżenie, informacja zwrotna albo prezentowana konsekwencja widoczna dla gracza jest zmianą produktu i wymaga oceny `OgolnyZarys.txt`, nawet gdy algorytm domenowy pozostaje bez zmian.

Pełny szczegół zapisuj tylko u właściciela. Inny dokument może podać jedną potrzebną konsekwencję i odwołanie, ale nie drugą specyfikację. Dokładna aktywna wartość strojalna należy do walidowanego `Resource`; dokument produktu może wyjaśniać jej znaczenie dla gracza, a architektura wskazywać pole i konsumenta.

Każdy z pięciu dokumentów ma na początku lokalny kontrakt wpisu. Przestrzegaj go przy nowej treści. Gdy edytujesz zastaną sekcję, doprowadź całą tę sekcję do właściwej roli: zachowaj sens, przenieś szczegół do właściciela i w dawnym miejscu zostaw tylko odwołanie.

Routing zmiany:

1. Zmianę reguły, balansu lub narracji zapisz najpierw w `OgolnyZarys.txt`; dodaj ARD tylko dla trwałej decyzji przekrojowej; następnie zaktualizuj mapowanie architektoniczne, implementację i testy; `PROJECT_CONTEXT.md` dopiero po weryfikacji runtime.
2. Refaktor bez zmiany zachowania aktualizuje architekturę tylko wtedy, gdy zmienia opisane w niej mapowanie, odpowiedzialność systemu, przepływ, model danych albo kontrakt testowy; nie tworzy ARD ani wpisu produktowego. `PROJECT_CONTEXT.md` zmień tylko wtedy, gdy zmienia się ważna bieżąca granica lub pułapka.
3. Zmiana semantyki trwałego stanu lub zapisu wymaga najpierw ARD, potem architektury, migracji, walidacji i testów; stan trafia do `PROJECT_CONTEXT.md` po potwierdzeniu.
4. Sam wynik weryfikacji aktualizuje wyłącznie `PROJECT_CONTEXT.md`. Mapę testów zmień w architekturze tylko wtedy, gdy zmienił się zakres pokrycia albo ryzyka.
5. `README.md` zmień tylko wtedy, gdy użytkownik repozytorium musi inaczej projekt przygotować, uruchomić, przetestować lub obsłużyć na wejściu.

Nie twórz nowych plików dokumentacyjnych. Kod, dane, grafiki, audio i techniczne pliki projektu nie są dokumentacją.

Po zakończeniu zadania krótko podsumuj wynik, wykonaną weryfikację i najbardziej sensowny następny krok.
