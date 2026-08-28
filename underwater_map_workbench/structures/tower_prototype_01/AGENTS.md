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

Jeżeli zadanie zmienia zachowanie widoczne dla gracza, regułę kampanii, publiczną granicę Root–Mapa, schema mapy, persistence albo zapis, wróć do `../../../AGENTS.md` i dobierz pełny kontekst globalny. Zmiana lokalnego źródła może zmienić pochodny `map_gameplay_signature`; nadal jest authoringiem tego pakietu, po którym osobna zmiana Mapy odświeża pin i pochodne. Jeżeli zadanie zmienia mapowy origin, rejestrację, globalny payload lub kompozycję wielu pakietów, wróć do `../../AGENTS.md` i prowadź je jako zadanie Mapy.

## Granica odczytu i zapisu

- Domyślna allowlista zapisu obejmuje wyłącznie `underwater_map_workbench/structures/tower_prototype_01/**`.
- `../../map_manifest.json`, pozostała Mapa, root i `../../../diver_workbench/**` są zawsze zależnościami tylko do odczytu. `--seal-structure-package tower_prototype_01` może zaktualizować wyłącznie lokalny manifest; `--refresh-structure-package` należy do osobnej zmiany właściciela Mapy.
- Pakiet może konsumować publiczne typy i kontrakty nadrzędnego projektu, ale nie kopiuje ani nie poprawia ich przy okazji prywatnego zadania.
- Przed edycją wypisz planowane ścieżki i właścicieli. Po edycji porównaj pełny diff; zapis poza pakietem zatrzymuje lokalną pracę i wymaga przekierowania.
- Pakiet nie posiada własnego `project.godot`, `.godot`, `.ai`, `map_manifest.json`, `UnderwaterMap.tscn`, ARD, kampanii ani konfiguracji zapisu.

### Współbieżność

- Jeden autor pakietu pracuje w osobnym pełnym Git worktree i na własnej gałęzi `codex/structure/<task-slug>` utworzonej z aktualnego `origin/main`. Osobny CWD we wspólnym checkoutcie nie daje izolacji.
- Autor wykonuje lokalny seal, build/check i testy pakietu, sprawdza diff oraz otwiera jeden PR. Mapowy pin i wspólne pochodne zmienia później osobny PR właściciela Mapy na podstawie dokładnego SHA-256 sealed manifestu.
- Lokalny build/check i celowane testy pakietu nie odkrywają innych struktur. Runner izoluje `.godot`, `user://`, logi i capture w pełnej kopii oraz odrzuca `-InPlace`.
- Autor nie poprawia ręcznie `generated/**` ani mapowego pinu. Spójna publikacja pochodnych jest wewnętrznym obowiązkiem buildera Mapy.

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
2. Porównaj zmianę z aktywnymi MAP-ARD-0022, MAP-ARD-0026 i globalnym ARD-0106. Nie zmieniaj przy okazji mapowego placementu ani semantyki zapisu.
3. Gdy zmieniło się źródło lub jego hash, uruchom `python ..\..\tools\build_underwater_map.py --seal-structure-package tower_prototype_01`. Następnie użyj lokalnego `--build-structure tower_prototype_01` i niedestrukcyjnego `--check-structure tower_prototype_01`; mapowy refresh, pin i wspólne pochodne należą do osobnej zmiany Mapy.
4. Uruchom `tests/tower_package_contract_test.gd` oraz `tests/tower_runtime_test.gd`. Pełny mapowy build/check i smoke należą do rejestracji, zmiany originu albo publicznego montażu, a pełną integrację docelowo wykonuje merge queue. Rootowy test dobierz tylko dla publicznego montażu, resetu próby albo granicy persistence.
5. Po zmianie widocznej grafiki wykonaj natywny capture dokładnej wygenerowanej sceny i obejrzyj wynik.
6. Po zmianie topologii zachowaj ręczny playtest całego budynku i wymaganych powrotów; nie zastępuj go BFS-em.

Testy Godota uruchamiaj sekwencyjnie wspólnym runnerem w izolowanej pełnej kopii projektu. `ERROR` i `SCRIPT ERROR` oznaczają porażkę także przy kodzie wyjścia `0`. W podsumowaniu podaj zmienione źródła, build/check/testy, dokumenty przeczytane w całości, brak lub wynik oględzin oraz ewentualny następny krok.
