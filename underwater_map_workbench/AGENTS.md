# Instrukcje warsztatu mapy podwodnej

Ten katalog jest jedynym miejscem authoringu konkretnej mapy podwodnej. Ustaw CWD narzędzi na `underwater_map_workbench/`; dla prywatnego zadania jednej struktury najbliższy routing może następnie zawęzić CWD do `structures/<id>/`. Pełny projekt Godot pozostaje w `..`.

`AGENTS.md` opisuje wyłącznie proces, routing i weryfikację. Bieżący stan należy do `.ai/PROJECT_CONTEXT.md`, trwałe kontrakty do `.ai/DECISIONS.md`, a komendy i onboarding do `README.md`.

## Kontekst przed pracą

Przed inwentaryzacją, analizą albo zmianą przeczytaj w całości, z kontrolą SHA-256 przed i po:

1. `.ai/PROJECT_CONTEXT.md`;
2. `.ai/DECISIONS.md`;
3. `README.md`.

Do pełnego odczytu, stabilności wersji i kolejności stosuj wymagania z `../AGENTS.md`. Dopiero po tych odczytach wolno użyć `rg`, czytać kod lub planować edycje.

Jeżeli zadanie dotyczy prywatnej topologii, grafiki, assetów, runtime albo testu jednej zarejestrowanej struktury, po powyższych trzech pełnych odczytach przeczytaj jej `structures/<id>/AGENTS.md`, a następnie w całości lokalny `structures/<id>/README.md`, i ustaw CWD narzędzi na katalog pakietu. Dopiero wtedy przeczytaj `structure_manifest.json` oraz dokładny rekord instancji w mapowym `map_manifest.json`. Pakietowy routing dziedziczy kontrolę SHA-256 i bramkę rozbieżności z tego pliku oraz `../AGENTS.md`.

Jeżeli zadanie zmienia ogólną regułę gracza, kampanię, gameplay poza rozmieszczeniem konkretnej mapy, integrację Root–Mapa, publiczny kontrakt danych, persistence albo zapis poza warsztatem, przejdź do `../AGENTS.md` i dobierz wymagane dokumenty globalne. Jeżeli głównym zakresem jest avatar gracza, przejdź do `../diver_workbench/AGENTS.md`.

## Granica odczytu i zapisu

- Domyślna allowlista zapisu zadania mapowego obejmuje wyłącznie `underwater_map_workbench/**`.
- Prywatne zadanie jednej struktury ma węższą allowlistę `underwater_map_workbench/structures/<id>/**`. Rekord mapowy jest zawsze tylko do odczytu. `--seal-structure-package <id>` może zaktualizować wyłącznie lokalne hashe i digesty `structure_manifest.json`; `--refresh-structure-package <id>` należy do późniejszego kroku Mapy i nie przepisuje prywatnego manifestu. Stable ID, origin, aktywność, landmark, globalny payload i kompozycja wielu struktur pozostają zadaniem Mapy prowadzonym z CWD warsztatu.
- W zadaniu Mapy prywatne źródła istniejącego pakietu — jego `structure_manifest.json`, `runtime/`, `assets/`, `references/` i `tests/` — są tylko do odczytu. Agent Mapy może edytować rejestrację, wspólny builder, kompilator i mapowe źródła oraz pozwolić builderowi deterministycznie odtworzyć pakietowe `generated/**`; zmiana prywatnego źródła wymaga osobnego zadania przekierowanego do `structures/<id>/`.
- Root pod `../` i `../diver_workbench/**` są dla lokalnego agenta tylko do odczytu. Wolno korzystać z ich publicznych kontraktów oraz wspólnego projektu i runnera.
- Zadanie wymagające zapisu poza warsztatem jest zakresem integracyjnym prowadzonym z root. Nie rozszerzaj samodzielnie allowlisty.
- Lokalny test sprawdza wnętrze pakietu mapy. Test składający Mapę z Nurkiem albo z regułami kampanii należy do root i korzysta z publicznych granic.
- Przed edycją wypisz planowane pliki i właścicieli. Po edycji porównaj pełny diff z tą listą; nieplanowany zapis poza allowlistą zatrzymuje pracę.
- Wszystkie trwałe ścieżki względne licz od CWD warsztatu. `../` oznacza root projektu. Nie zapisuj absolutnej ścieżki konkretnego checkoutu.

### Współbieżna praca w warsztacie

- Każdy równoległy producent Mapy, Nurka i `structures/<id>/` pracuje w osobnym pełnym Git worktree i na gałęzi `codex/<owner>/<task-slug>` z commita integracyjnego potwierdzonego candidate receiptem oraz zgodnym pełnym run receiptem `PASS`. Rozłączna allowlista nadal jest obowiązkowa; osobny CWD we wspólnym worktree nie wystarcza.
- Producent struktury uszczelnia i testuje prywatną rewizję bez globalnego locka. Hand-offem jest niezmienny commit albo zweryfikowana rewizja FROZEN z dwoma zgodnymi hashami manifestu; autor może potem natychmiast rozwijać N+1.
- `map_manifest.json`, `UnderwaterMap.tscn`, mapowe metadane builda i `structures/*/generated/**` są jednym zestawem publikacji. Integrator oblicza kandydata poza blokadą ze sealed inputu, a wyłącznie rehash i per-path CAS/rollback z markerem kompletności zapisanym na końcu wykonuje pod krótką blokadą `map-promotion` wspólną dla linked worktrees przez wspólny katalog Git. Czytelnik ignorujący lock nie ma gwarancji wieloplikowej atomowości i nie może konsumować authority w trakcie publikacji.
- Prywatny build/check i celowany test nie odkrywają innych pakietów. Pełny build/check, smoke, visual survey oraz dynamiczne discovery wszystkich struktur należą wyłącznie do osobnego worktree integracyjnego.
- Runner tworzy FROZEN kopię z plików śledzonych i niesledzonych, których nie wykluczają standardowe reguły Git, oraz izoluje `.godot`, `user://`, logi i capture. Późniejsza praca producentów nie unieważnia wyniku kopii; `-InPlace` jest odrzucane, ponieważ nie zapewnia tej granicy.

## Authority i pliki generowane

- `map_manifest.json` jest jedynym authority rejestracji, stable ID i globalnego placementu konkretnej mapy. Zarejestrowany `structures/<id>/structure_manifest.json` jest podrzędnym authority wyłącznie lokalnego rozmiaru, topologii, socketów, grafiki, skryptów i runtime tego budynku; nie jest drugim manifestem mapy.
- `UnderwaterMap.tscn`, mapowe `assets/generated/**` oraz pakietowe `structures/<id>/generated/**` są pochodnymi. Nie poprawiaj ich ręcznie; zmień właściwe źródło i uruchom builder.
- Nie twórz drugiego `map_manifest.json`, manifestu wariantu, sceny-kandydata, alternatywnego generatora, kopii mapy w root ani kopii avatara w warsztacie. Pakiet struktury nie może zawierać globalnego originu, mapowego landmarku, kampanii, persistence ani checkpointu innego niż jawna deklaracja `none`.
- Bieżące rewizje, liczności, pozycje, format payloadu, obsługiwane typy assetów i status testów odczytuj z manifestu, lokalnego kontekstu i runtime. Nie utrzymuj ich w tym pliku.

## Bramka rozbieżności

Przed pierwszą edycją porównaj żądanie z runtime, aktywnymi MAP-ARD i — dla zakresu integracyjnego — źródłami globalnymi. Konflikt właściciela, publicznej granicy, topologii, podpisu mapy, semantyki zapisu albo zatwierdzonego kontraktu jest rozbieżnością blokującą obsługiwaną według `../AGENTS.md`.

Po wykryciu rozbieżności nie poprawiaj równolegle kodu, danych, testów ani dokumentacji. Zbierz minimalny dowód, opisz warianty i poczekaj na decyzję użytkownika.

## Routing dokumentacji

| Plik | Właściciel treści |
|---|---|
| `.ai/PROJECT_CONTEXT.md` | krótka, datowana migawka aktywnego pakietu, luk i ostatniej weryfikacji |
| `.ai/DECISIONS.md` | trwałe decyzje mapy, inwarianty i jawne zastąpienia |
| `README.md` | wejście dla człowieka: układ pakietu, komendy i przepisy uruchomieniowe |
| `AGENTS.md` | proces pracy, routing, granice zapisu i dobór weryfikacji |
| `structures/<id>/README.md` | operacyjny indeks lokalnych źródeł i komendy jednego pakietu, bez opisu reguł gameplayu |
| `structures/<id>/AGENTS.md` | proces i węższa granica zapisu jednego zarejestrowanego pakietu |

Nie kopiuj do lokalnych dokumentów globalnych reguł produktu, właścicieli stanu, persistence ani pełnej architektury. Zapisz najwyżej jedną konsekwencję integracyjną i odwołanie do właściciela w root. Poza czterema dokumentami warsztatu i dokładnie `structures/<id>/{AGENTS.md,README.md}` nie twórz innych plików dokumentacyjnych, niezależnie od rozszerzenia. Pakiet struktury nie posiada własnego `.ai`, MAP-ARD ani datowanej migawki; jawnie hash-pinned plik provenance wskazany w `references` jako `authority=false` jest dopuszczonym materiałem źródłowym, lecz nie kontraktem i nie może sterować implementacją.

Przed edycją dokumentacji przedstaw użytkownikowi decyzję `aktualizuję / nie aktualizuję` dla czterech dokumentów lokalnych oraz wymaganych dokumentów globalnych. Dla zadania jednej struktury oceń dodatkowo jej `AGENTS.md` i `README.md`. Po zmianie bieżącego stanu aktualizuj kontekst dopiero po weryfikacji.

## Wykonanie i weryfikacja

1. Ustal edytowalne źródła z manifestu i sprawdź aktualny kod, scenę, builder oraz testy związane z zadaniem.
2. Dla zmiany semantyki lub topologii najpierw rozstrzygnij wymagane decyzje i rewizje; dla samej prezentacji nie zmieniaj podpisu gameplayu.
3. Po zmianie źródła wygeneruj pochodne przez lokalny builder. `--check` musi pozostać niedestrukcyjny.
4. Uruchom lokalny smoke. Dobierz rootowy test integracyjny wyłącznie wtedy, gdy zmiana dotyka publicznej granicy lub ogólnego runtime.
5. Po zmianie widocznej grafiki wykonaj natywny capture dokładnie wygenerowanej sceny i obejrzyj wynik; techniczny `PASS` nie jest odbiorem artystycznym ani certyfikacją trasy.
6. Po zmianie topologii zachowaj ręczny playtest rzeczywistej osiągalności. Nie zastępuj go blokującym BFS-em.

Dla prywatnej zmiany jednej struktury po zmianie źródła lub hasha użyj `--seal-structure-package <id>`, następnie lokalnego `--build-structure <id>`, niedestrukcyjnego `--check-structure <id>` oraz obu lokalnych testów: kontraktu pakietu i runtime. Po hand-offie integrator Mapy uruchamia `--refresh-structure-package <id>` dla dokładnej sealed rewizji; kilka odebranych rewizji przekazuje jako powtarzalne pary `<id>, <SHA256>` w jednej komendzie batch i jednym CAS. Pełny mapowy build/check i smoke są wymagane przy rejestracji, zmianie originu, publicznym montażu albo przed odbiorem integracyjnym, nie w zwykłej prywatnej iteracji. Rootowy test jest wymagany tylko dla publicznego montażu, resetu próby albo granicy persistence; nie powinien powtarzać lokalnych kombinacji, socketów czy originu. Zmiana package manifestu nie upoważnia do edycji mapowego rekordu placementu.

Testy Godota uruchamiaj sekwencyjnie wspólnym runnerem w izolowanej pełnej kopii projektu. `ERROR` i `SCRIPT ERROR` oznaczają porażkę również przy kodzie wyjścia `0`.

Przy grafice strukturalnej używaj wyłącznie aktualnego pakietu prawdy wygenerowanego z zarejestrowanego `structure_manifest.json` i mapowego placementu. Obraz, screenshot, DOCX provenance albo prompt nie definiuje położenia, fizyki ani gameplayu. Szczegółowe inwarianty warstw, masek, invalidacji i authoringu należą do aktywnych MAP-ARD, nie do procesu.

W podsumowaniu podaj zmienione źródła i właścicieli, wykonane build/check/testy, dokumenty przeczytane w całości, ograniczenia ręcznej oceny oraz ewentualny następny krok.
