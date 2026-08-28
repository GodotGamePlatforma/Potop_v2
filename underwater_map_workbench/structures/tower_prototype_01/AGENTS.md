# Instrukcje pakietu struktury `tower_prototype_01`

Ten katalog jest podrzędnym pakietem Mapy, nie osobnym projektem Godot ani trzecim warsztatem domenowym. Ustaw CWD narzędzi na `underwater_map_workbench/structures/tower_prototype_01/`; pełny projekt pozostaje w `../../..`, a nadrzędny warsztat Mapy w `../..`.

`AGENTS.md` określa wyłącznie proces, routing, granice zapisu i weryfikację. Nie ustanawia zachowania gracza, pozycji globalnej, persistence ani technicznej migawki implementacji.

## Kontekst przed pracą

Dla zwykłej poprawki tego budynku przeczytaj ten plik, lokalny `README.md`, `structure_manifest.json`, dokładny rekord `tower_prototype_01` w `../../map_manifest.json` oraz wyłącznie związane źródła i testy. W `.ai/PROJECT_CONTEXT.md` Mapy przeczytaj tylko punkt dotyczący bieżącej struktury lub otwartej luki. Nie czytaj pełnych decyzji, produktu ani architektury, jeżeli nie zmieniasz ich kontraktu.

Pełny routing root jest wymagany dopiero przy zmianie reguły produktu, publicznej granicy, schema, persistence, zapisu albo semantycznego kontraktu kilku właścicieli. Mechaniczne opublikowanie lokalnej poprawki razem z nowym sealem, mapowym pinem i pochodnymi nie uruchamia pełnego odczytu dokumentów: pozostaje jednym prostym, root-routed zadaniem według lokalnego README. Zmiana samego originu, rejestracji lub globalnego payloadu bez prywatnego źródła jest zadaniem Mapy.

## Granica odczytu i zapisu

- Domyślna allowlista zapisu obejmuje wyłącznie `underwater_map_workbench/structures/tower_prototype_01/**`.
- W czysto lokalnej iteracji `../../map_manifest.json`, pozostała Mapa, root i `../../../diver_workbench/**` są tylko do odczytu. Jeżeli seal wymaga nowego pinu, użyj jednego root-routed zadania obejmującego pakiet i wymagane pochodne Mapy; nie twórz package-only PR.
- Pakiet może konsumować publiczne typy i kontrakty nadrzędnego projektu, ale nie kopiuje ani nie poprawia ich przy okazji prywatnego zadania.
- Rutynowa poprawka nie wymaga predeklaracji dokumentów ani pełnego write-setu. Po edycji porównaj diff z allowlistą; nieplanowany zapis poza nią zatrzymuje pracę.
- Pakiet nie posiada własnego `project.godot`, `.godot`, `.ai`, `map_manifest.json`, `UnderwaterMap.tscn`, ARD, kampanii ani konfiguracji zapisu.

### Współbieżność

- Root lub koordynator przydziela zmianę seal+pin jako jedno proste zadanie jednemu autorowi w osobnym pełnym Git worktree i na gałęzi `codex/structure-tower_prototype_01/<task-slug>` utworzonej z aktualnego `origin/main`. Ten sam branch i PR zawiera źródła pakietu, sealed manifest, mapowy pin/refresh oraz pochodne.
- Po implementacji autor wykonuje mechaniczne kroki z lokalnego README, lokalne testy zadania, a następnie osobny lokalny fast-check. Obecny fast-check nie wykonuje seala ani odtworzenia pochodnych. Po `PASS` autor wykonuje `commit -> push + PR -> KONIEC`; osobny GitHub `fast-check` decyduje o enqueue, a pełny `integration-green` wykonuje merge queue. Nie powstaje drugi PR Mapy.
- Lokalny build/check i celowane testy pakietu nie odkrywają innych struktur. Runner izoluje `.godot`, `user://`, logi i capture w pełnej kopii oraz odrzuca `-InPlace`.
- Autor nie poprawia ręcznie `generated/**` ani mapowego pinu i nie babysituje starego PR. Prawdziwy konflikt albo nieaktualny seal, pin lub pochodna wykryta w merge queue wraca do root jako nowe zadanie naprawcze dla nowego agenta startującego z aktualnego `main`; koordynator zastępuje i zamyka stary PR. Spójna publikacja pochodnych jest wewnętrznym obowiązkiem buildera.

## Authority i pochodne

- `structure_manifest.json` jest jedynym authority lokalnego rozmiaru, szablonu, operacji kolizji, socketów, assetów, skryptów, konfiguracji runtime i deklaracji cyklu życia próby tego budynku. Prywatne skrypty są ładowane po zadeklarowanej, hash-pinned ścieżce i nie publikują globalnego `class_name`.
- Wszystkie współrzędne pakietu są lokalne. Globalny placement istnieje wyłącznie w nadrzędnym `map_manifest.json`; nie kopiuj originu do pakietu, kodu, testu ani dokumentacji.
- `generated/**` jest deterministyczną pochodną. Nie poprawiaj masek, prowadnic, kart socketów ani truth package ręcznie.
- `references/Wiezowiec_2D_Analiza_i_Dokumentacja_POPRAWIONA.docx` jest provenance wskazanym przez manifest jako `authority=false`. Nie definiuje topologii, gameplayu, checkpointu, zapisu, punktu bez powrotu ani porażki konstrukcji i nie jest wejściem implementacji.
- Aktualne zachowanie gracza odczytuj wyłącznie z globalnego dokumentu produktu wskazanego w `README.md`; lokalne dane techniczne odczytuj z manifestu, runtime i testu.

## Dokumentacja

Pakiet posiada dokładnie dwa dokumenty kontraktowe:

- `AGENTS.md` — ten proces i granice;
- `README.md` — operacyjny indeks źródeł i komendy.

Nie twórz innych plików `.md`, `.txt`, lokalnego kontekstu ani rejestru decyzji. Nie kopiuj tu kombinacji, sekwencji progresji, reguł śmierci, persistence ani pełnej architektury. Rutynowa zmiana nie wymaga aktualizacji dokumentacji ani deklarowania jej zakresu przed edycją.

## Wykonanie i weryfikacja

1. Ustal edytowalne źródło z `structure_manifest.json` i sprawdź wskazane pliki runtime, assety oraz lokalny test.
2. Nie zmieniaj przy okazji mapowego placementu ani semantyki zapisu. Jeżeli zadanie wymaga zmiany kontraktu, dopiero wtedy przeczytaj właściwe ARD i wróć do routingu root.
3. Gdy zmieniło się źródło lub jego hash, wykonaj jeden przepis „Zmiana pakietu” z lokalnego README. Zawiera on wymagane seal/refresh/build/check, lecz agent nie musi projektować tych kroków.
4. Uruchom dwa lokalne testy zadania, a potem osobny fast-check. Po `PASS` utwórz commit i opublikuj jeden PR helperem wskazanym w README; zakończ bez pollingu. Pełną regresję wykonuje merge queue.
5. Po zmianie widocznej grafiki wykonaj natywny capture dokładnej wygenerowanej sceny i obejrzyj wynik.
6. Po zmianie topologii zachowaj ręczny playtest całego budynku i wymaganych powrotów; nie zastępuj go BFS-em.

Testy Godota uruchamiaj sekwencyjnie wspólnym runnerem w izolowanej pełnej kopii projektu. `ERROR` i `SCRIPT ERROR` oznaczają porażkę także przy kodzie wyjścia `0`. W podsumowaniu podaj zmienione źródła, testy i fast-check, brak lub wynik oględzin oraz ewentualny następny krok.
