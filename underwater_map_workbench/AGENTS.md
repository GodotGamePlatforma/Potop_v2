# Instrukcje warsztatu mapy podwodnej

Ten katalog jest jedynym miejscem authoringu konkretnej mapy podwodnej. Ustaw CWD narzędzi na `underwater_map_workbench/`; dla prywatnego zadania jednej struktury najbliższy routing może następnie zawęzić CWD do `structures/<id>/`. Pełny projekt Godot pozostaje w `..`.

`AGENTS.md` opisuje wyłącznie proces, routing i weryfikację. Bieżący stan należy do `.ai/PROJECT_CONTEXT.md`, trwałe kontrakty do `.ai/DECISIONS.md`, a komendy i onboarding do `README.md`.

## Kontekst przed pracą

Dla zwykłej zmiany Mapy przeczytaj ten plik, właściwy fragment `.ai/PROJECT_CONTEXT.md`, zmieniany rekord manifestu oraz związany kod i testy. `README.md` otwórz po potrzebną komendę. Nie czytaj całego `.ai/DECISIONS.md` ani dokumentów root, jeżeli zadanie zachowuje istniejące authority, schema i zachowanie gracza.

Dla prywatnej zmiany jednej struktury przejdź od razu do `structures/<id>/AGENTS.md`, ustaw CWD na pakiet i zastosuj jego krótszy routing. Odczytaj tylko dokładny rekord tej struktury w `map_manifest.json`, jej `structure_manifest.json`, związane źródła i testy.

Pełny lokalny rejestr decyzji oraz właściwe dokumenty root są wymagane dopiero przy zmianie schema, globalnej reguły topologii lub placementu, publicznego kontraktu, produktu, persistence, zapisu albo przy semantycznej zmianie u więcej niż jednego właściciela. Mechaniczne opublikowanie źródła jednej struktury razem z wymaganym pinem i pochodnymi nie uruchamia tego pełnego odczytu. Zadanie avatara przechodzi do `../diver_workbench/AGENTS.md`.

## Granica odczytu i zapisu

- Domyślna allowlista zapisu zadania mapowego obejmuje wyłącznie `underwater_map_workbench/**`.
- Prywatne zadanie jednej struktury ma węższą allowlistę `underwater_map_workbench/structures/<id>/**`. Gdy publikacja zmienia lokalny manifest i wymaga nowego mapowego pinu, obowiązuje wąski wyjątek root-routed: jeden Codex, worktree, branch `codex/structure-<id>/<task-slug>` oraz PR obejmuje źródła pakietu i wymagane pochodne Mapy. Stable ID, origin, aktywność, landmark, globalny payload i kompozycja wielu struktur pozostają authority Mapy.
- W zadaniu Mapy prywatne źródła istniejącego pakietu — jego `structure_manifest.json`, `runtime/`, `assets/`, `references/` i `tests/` — są tylko do odczytu. Agent Mapy może edytować rejestrację, wspólny builder, kompilator i mapowe źródła oraz pozwolić builderowi deterministycznie odtworzyć pakietowe `generated/**`; zmiana prywatnego źródła wymaga osobnego zadania przekierowanego do `structures/<id>/`.
- Root pod `../` i `../diver_workbench/**` są dla lokalnego agenta tylko do odczytu. Wolno korzystać z ich publicznych kontraktów oraz wspólnego projektu i runnera.
- Zadanie wymagające zapisu poza warsztatem jest zakresem integracyjnym prowadzonym z root. Nie rozszerzaj samodzielnie allowlisty.
- Lokalny test sprawdza wnętrze pakietu mapy. Test składający Mapę z Nurkiem albo z regułami kampanii należy do root i korzysta z publicznych granic.
- Rutynowa zmiana jednego właściciela nie wymaga predeklaracji dokumentów ani pełnego write-setu. Po edycji zawsze porównaj diff z allowlistą; nieplanowany zapis poza nią zatrzymuje pracę.
- Wszystkie trwałe ścieżki względne licz od CWD warsztatu. `../` oznacza root projektu. Nie zapisuj absolutnej ścieżki konkretnego checkoutu.

### Współbieżna praca w warsztacie

- Root lub koordynator przydziela jedno proste zadanie jednemu agentowi. Zadanie wyłącznie Mapy używa gałęzi `codex/map/<task-slug>`, a zmiana struktury wymagająca nowego seala i pinu jednego root-routed zadania na `codex/structure-<id>/<task-slug>`; oba rodzaje startują z aktualnego `origin/main` w osobnym pełnym worktree.
- Root-routed autor zmiany struktury zapisuje w jednym branchu i PR właściwe źródła pakietu, sealed manifest, mapowy refresh/pin oraz wszystkie pochodne. Kolejność autora jest stała: `implementacja -> lokalne testy zadania -> lokalny fast-check`; po `PASS` wykonuje `commit -> push + PR -> KONIEC`. Mechaniczne kroki seala i odtworzenia pochodnych pozostają w najbliższym README, ponieważ obecny fast-check ich nie wykonuje. Nie powstaje drugi PR Mapy ani osobny agent-integrator.
- Po PR osobny wymagany GitHub `fast-check` sprawdza dokładny head. Native merge queue sama składa go z aktualnym `main` i uruchamia pełny `integration-green`. Prawdziwy konflikt albo nieaktualny seal, pin lub pochodna wykryta w kolejce powoduje zamknięcie starego PR przez koordynatora i nowe zadanie naprawcze dla nowego agenta startującego z aktualnego `main`; autor starego PR nie babysituje kolejki.
- `map_manifest.json`, `UnderwaterMap.tscn`, mapowe metadane builda i `structures/*/generated/**` pozostają jednym spójnym zestawem. Builder publikuje go dopiero po walidacji wszystkich wejść; CAS/rollback, jeżeli jest używany, jest wewnętrzną ochroną zapisu buildera, nie protokołem współpracy agentów.
- Builder i runner automatycznie egzekwują LF dla tracked plików z `eol=lf`. Celowany build/check i test nie odkrywają innych struktur.
- Każdy przebieg Godota używa izolowanej pełnej kopii z prywatnym `.godot`, `user://`, logami, temp, portami i capture. `-InPlace` pozostaje odrzucane. Lokalny fast-check przed commitem i wymagany GitHub `fast-check` po PR są osobnymi przebiegami; dopiero GitHub `fast-check PASS` pozwala enqueue, a pełna integracja złożenia należy docelowo do merge queue zgodnie z rootowym ARD-0113.

## Authority i pliki generowane

- `map_manifest.json` jest jedynym authority rejestracji, stable ID i globalnego placementu konkretnej mapy. Zarejestrowany `structures/<id>/structure_manifest.json` jest podrzędnym authority wyłącznie lokalnego rozmiaru, topologii, socketów, grafiki, skryptów i runtime tego budynku; nie jest drugim manifestem mapy.
- `UnderwaterMap.tscn`, mapowe `assets/generated/**` oraz pakietowe `structures/<id>/generated/**` są pochodnymi. Nie poprawiaj ich ręcznie; zmień właściwe źródło i uruchom builder.
- Nie twórz drugiego `map_manifest.json`, manifestu wariantu, sceny-kandydata, alternatywnego generatora, kopii mapy w root ani kopii avatara w warsztacie. Pakiet struktury nie może zawierać globalnego originu, mapowego landmarku, kampanii, persistence ani checkpointu innego niż jawna deklaracja `none`.
- Bieżące rewizje, liczności, pozycje, format payloadu, obsługiwane typy assetów i status testów odczytuj z manifestu, lokalnego kontekstu i runtime. Nie utrzymuj ich w tym pliku.

## Bramka rozbieżności

Przed pierwszą edycją sprawdź bieżące lokalne źródła, manifest i test zadania. Aktywne MAP-ARD oraz źródła globalne otwórz dopiero dla zakresu spełniającego warunki pełnego kontekstu albo po wykryciu możliwego konfliktu. Konflikt właściciela, publicznej granicy, globalnej topologii, podpisu mapy, semantyki zapisu albo zatwierdzonego kontraktu jest rozbieżnością blokującą obsługiwaną według `../AGENTS.md`.

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

Rutynowa zmiana nie wymaga deklarowania przed edycją, które dokumenty zostaną zaktualizowane. Zmień tylko dokument będący właścicielem faktycznie zmienionej treści. Kontekst aktualizuj dopiero po weryfikacji stanu.

## Wykonanie i weryfikacja

1. Ustal edytowalne źródła z manifestu i sprawdź aktualny kod, scenę, builder oraz testy związane z zadaniem.
2. Dla zmiany semantyki lub topologii najpierw rozstrzygnij wymagane decyzje i rewizje; dla samej prezentacji nie zmieniaj podpisu gameplayu.
3. Po zmianie źródła wygeneruj pochodne przez lokalny builder. `--check` musi pozostać niedestrukcyjny.
4. Uruchom lokalny smoke. Dobierz rootowy test integracyjny wyłącznie wtedy, gdy zmiana dotyka publicznej granicy lub ogólnego runtime.
5. Po zmianie widocznej grafiki wykonaj natywny capture dokładnie wygenerowanej sceny i obejrzyj wynik; techniczny `PASS` nie jest odbiorem artystycznym ani certyfikacją trasy.
6. Po zmianie topologii zachowaj ręczny playtest rzeczywistej osiągalności. Nie zastępuj go blokującym BFS-em.

Dla zmiany jednej struktury użyj jednego przepisu z jej lokalnego README. Obecny helper fast-check nie wykonuje seala, refreshu ani publikacji pochodnych, więc wymagane kroki buildera pozostają jawne tylko tam. Potem uruchom lokalne testy zadania, a następnie osobny fast-check. Rootowy test dodaj tylko dla publicznego montażu, resetu próby albo granicy persistence. Pełny zestaw integracyjny uruchamia merge group.

Testy Godota uruchamiaj sekwencyjnie wspólnym runnerem w izolowanej pełnej kopii projektu. `ERROR` i `SCRIPT ERROR` oznaczają porażkę również przy kodzie wyjścia `0`.

Przy grafice strukturalnej używaj wyłącznie aktualnego pakietu prawdy wygenerowanego z zarejestrowanego `structure_manifest.json` i mapowego placementu. Obraz, screenshot, DOCX provenance albo prompt nie definiuje położenia, fizyki ani gameplayu. Szczegółowe inwarianty warstw, masek, invalidacji i authoringu należą do aktywnych MAP-ARD, nie do procesu.

W podsumowaniu podaj zmienione źródła, wykonane testy i fast-check, ograniczenia ręcznej oceny oraz ewentualny następny krok.
