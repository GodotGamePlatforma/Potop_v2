# Instrukcje pakietu struktury `tower_prototype_01`

Ten katalog jest podrzędnym pakietem Mapy, nie osobnym projektem Godot ani trzecim warsztatem domenowym. Ustaw CWD narzędzi na `underwater_map_workbench/structures/tower_prototype_01/`; pełny projekt pozostaje w `../../..`, a nadrzędny warsztat Mapy w `../..`.

`AGENTS.md` określa wyłącznie proces, routing, granice zapisu i weryfikację. Nie ustanawia zachowania gracza, pozycji globalnej, persistence ani technicznej migawki implementacji.

## Kontekst przed pracą

Przed inwentaryzacją, analizą albo zmianą przeczytaj w całości, z SHA-256 przed i po, w tej kolejności:

1. `../../.ai/PROJECT_CONTEXT.md`;
2. `../../.ai/DECISIONS.md`;
3. `../../README.md`;
4. lokalny `README.md`.

Stosuj wymagania kompletności z `../../AGENTS.md` i `../../../AGENTS.md`. Dopiero po tych odczytach przeczytaj w całości `structure_manifest.json`, a następnie dokładny rekord `tower_prototype_01` w `../../map_manifest.json`. Rekord mapowy jest jedynym źródłem stable ID, originu, aktywności, opcjonalnego landmarku i referencji pakietu; manifest pakietu celowo nie powtarza pola `structure_id`.

Jeżeli zadanie zmienia zachowanie widoczne dla gracza, regułę kampanii, publiczną granicę Root–Mapa, schema mapy, persistence albo zapis, wróć do `../../../AGENTS.md` i dobierz pełny kontekst globalny. Zmiana lokalnego źródła wymagająca nowego seala i mapowego pinu jest jednym root-routed zadaniem obejmującym pakiet oraz pochodne Mapy. Jeżeli zadanie zmienia mapowy origin, rejestrację, globalny payload lub kompozycję wielu pakietów bez zmiany prywatnego źródła, wróć do `../../AGENTS.md` i prowadź je jako zadanie Mapy.

## Granica odczytu i zapisu

- Domyślna allowlista zapisu obejmuje wyłącznie `underwater_map_workbench/structures/tower_prototype_01/**`.
- W czysto lokalnej iteracji `../../map_manifest.json`, pozostała Mapa, root i `../../../diver_workbench/**` są tylko do odczytu. Jeżeli `--seal-structure-package tower_prototype_01` zmienia manifest i wymaga nowego pinu, zatrzymaj lokalny routing i przejdź do jednego root-routed zadania z jawnym write-setem pakietu oraz wymaganych plików Mapy; nie twórz package-only PR.
- Pakiet może konsumować publiczne typy i kontrakty nadrzędnego projektu, ale nie kopiuje ani nie poprawia ich przy okazji prywatnego zadania.
- Przed edycją wypisz planowane ścieżki i właścicieli. Po edycji porównaj pełny diff; zapis poza pakietem zatrzymuje lokalną pracę i wymaga przekierowania.
- Pakiet nie posiada własnego `project.godot`, `.godot`, `.ai`, `map_manifest.json`, `UnderwaterMap.tscn`, ARD, kampanii ani konfiguracji zapisu.

### Współbieżność

- Jeden autor zmiany seal+pin pracuje w osobnym pełnym Git worktree i na gałęzi `codex/structure-tower_prototype_01/<task-slug>` utworzonej z aktualnego `origin/main`. Ten sam branch i PR zawiera źródła pakietu, sealed manifest, mapowy pin/refresh oraz pochodne.
- Autor wykonuje pełny seal, build/check i oba testy pakietu, następnie mapowy refresh, pełny build/check i pełne testy Mapy. Tylko `fast-check PASS` pozwala enqueue PR; nie powstaje drugi PR Mapy.
- Lokalny build/check i celowane testy pakietu nie odkrywają innych struktur. Runner izoluje `.godot`, `user://`, logi i capture w pełnej kopii oraz odrzuca `-InPlace`.
- Autor nie poprawia ręcznie `generated/**` ani mapowego pinu. Jeżeli konkurencyjny PR zmieni `main`, aktualizuje bazę, ponownie uruchamia seal/refresh, builder oraz pełne testy pakietu i Mapy. Spójna publikacja pochodnych jest wewnętrznym obowiązkiem buildera.

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

Nie twórz innych plików `.md`, `.txt`, lokalnego kontekstu ani rejestru decyzji. Nie kopiuj tu kombinacji, sekwencji progresji, reguł śmierci, persistence ani pełnej architektury. Przed edycją dokumentacji oceń oba dokumenty pakietu, cztery dokumenty warsztatu Mapy oraz wymagane dokumenty globalne zgodnie z routingiem nadrzędnym.

## Wykonanie i weryfikacja

1. Ustal edytowalne źródło z `structure_manifest.json` i sprawdź wskazane pliki runtime, assety oraz lokalny test.
2. Porównaj zmianę z aktywnymi MAP-ARD-0022, MAP-ARD-0027 i globalnym ARD-0106. Nie zmieniaj przy okazji mapowego placementu ani semantyki zapisu.
3. Gdy zmieniło się źródło lub jego hash, w jednym root-routed worktree uruchom `--seal-structure-package tower_prototype_01`, `--build-structure tower_prototype_01`, `--check-structure tower_prototype_01`, oba testy pakietu, a następnie `--refresh-structure-package tower_prototype_01` z dokładnym SHA-256, pełny mapowy `--build`/`--check` i pełne testy Mapy.
4. Jeden PR musi zawierać źródła, seal, mapowy pin i wszystkie pochodne. Rootowy test dobierz dodatkowo tylko dla publicznego montażu, resetu próby albo granicy persistence; po zmianie bazy powtórz cały builder i zestaw testów.
5. Po zmianie widocznej grafiki wykonaj natywny capture dokładnej wygenerowanej sceny i obejrzyj wynik.
6. Po zmianie topologii zachowaj ręczny playtest całego budynku i wymaganych powrotów; nie zastępuj go BFS-em.

Testy Godota uruchamiaj sekwencyjnie wspólnym runnerem w izolowanej pełnej kopii projektu. `ERROR` i `SCRIPT ERROR` oznaczają porażkę także przy kodzie wyjścia `0`. W podsumowaniu podaj zmienione źródła, build/check/testy, dokumenty przeczytane w całości, brak lub wynik oględzin oraz ewentualny następny krok.
