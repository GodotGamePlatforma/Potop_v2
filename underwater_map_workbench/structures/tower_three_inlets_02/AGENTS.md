# Instrukcje pakietu struktury `tower_three_inlets_02`

Ten katalog jest podrzędnym pakietem Mapy, nie osobnym projektem Godot ani dodatkowym warsztatem domenowym. Ustaw CWD narzędzi na `underwater_map_workbench/structures/tower_three_inlets_02/`; pełny projekt pozostaje w `../../..`, a nadrzędny warsztat Mapy w `../..`.

`AGENTS.md` określa wyłącznie proces, routing, granice zapisu i weryfikację. Nie ustanawia zachowania gracza, pozycji globalnej, persistence ani technicznej migawki implementacji.

## Kontekst przed pracą

Przed inwentaryzacją, analizą albo zmianą przeczytaj w całości, z SHA-256 przed i po, w tej kolejności:

1. `../../.ai/PROJECT_CONTEXT.md`;
2. `../../.ai/DECISIONS.md`;
3. `../../README.md`;
4. lokalny `README.md`.

Stosuj wymagania kompletności z `../../AGENTS.md` i `../../../AGENTS.md`. Dopiero po tych odczytach przeczytaj w całości `structure_manifest.json`, a po przypięciu pakietu także dokładny rekord `tower_three_inlets_02` w `../../map_manifest.json`. Rekord mapowy jest jedynym źródłem stable ID, originu, aktywności, opcjonalnego landmarku i referencji pakietu; manifest pakietu celowo nie powtarza pola `structure_id` ani globalnego originu. Jeżeli rekordu mapowego jeszcze nie ma, pakiet pozostaje prywatnym stagingiem i nie wolno samodzielnie wymyślać jego placementu.

Jeżeli zadanie zmienia zachowanie widoczne dla gracza, regułę kampanii, publiczną granicę Root–Mapa, schemat Mapy, persistence albo zapis, wróć do `../../../AGENTS.md` i dobierz pełny kontekst globalny. Zmiana mapowego originu, rejestracji, globalnego payloadu lub kompozycji wielu pakietów należy do zadania Mapy z CWD `../..`.

## Granica odczytu i zapisu

- Domyślna allowlista zapisu obejmuje wyłącznie `underwater_map_workbench/structures/tower_three_inlets_02/**`.
- W czysto lokalnej iteracji `../../map_manifest.json`, `../../UnderwaterMap.tscn`, pozostała Mapa, root, inne pakiety struktur i `../../../diver_workbench/**` są tylko do odczytu. Jeżeli seal zmienia manifest i wymaga nowego pinu, zatrzymaj lokalny routing i przejdź do jednego root-routed zadania z jawnym write-setem pakietu oraz wymaganych plików Mapy; nie twórz package-only PR.
- Pakiet może konsumować publiczne typy i kontrakty projektu nadrzędnego, ale nie kopiuje ani nie poprawia ich przy okazji prywatnego zadania.
- Przed edycją wypisz planowane ścieżki i właścicieli. Po edycji porównaj pełny diff; zapis poza pakietem zatrzymuje lokalną pracę i wymaga przekierowania.
- Pakiet nie posiada własnego `project.godot`, `.godot`, `.ai`, `map_manifest.json`, `UnderwaterMap.tscn`, ARD, kampanii ani konfiguracji zapisu.

### Współbieżność

- Jeden autor zmiany seal+pin pracuje w osobnym pełnym Git worktree i na gałęzi `codex/structure-tower_three_inlets_02/<task-slug>` utworzonej z aktualnego `origin/main`. Ten sam branch i PR zawiera źródła pakietu, sealed manifest, mapowy pin/refresh oraz pochodne.
- Autor wykonuje pełny seal, build/check i oba testy pakietu, następnie mapowy refresh, pełny build/check i pełne testy Mapy. Tylko `fast-check PASS` pozwala enqueue PR; nie powstaje drugi PR Mapy.
- Lokalny build/check nie odkrywa innych struktur. Runner używa pełnej kopii z osobnym `.godot`, `user://`, logami i capture. Jeżeli konkurencyjny PR zmieni `main`, autor aktualizuje bazę i powtarza seal/refresh, builder oraz pełne testy pakietu i Mapy.

## Authority i pochodne

- `structure_manifest.json` jest jedynym authority lokalnego rozmiaru, szablonu, operacji kolizji, socketów, assetów, skryptów, konfiguracji runtime oraz cyklu życia próby tego budynku.
- Prywatne skrypty z `scripts/` są ładowane po zadeklarowanych, hash-pinned ścieżkach i nie publikują globalnego `class_name`.
- Wszystkie współrzędne pakietu są lokalne. Globalny placement istnieje wyłącznie w nadrzędnym `map_manifest.json`.
- `generated/**` jest deterministyczną pochodną. Nie poprawiaj masek, prowadnic, kart socketów, sceny struktury ani truth package ręcznie.
- Pliki w `references/` są provenance wskazanym przez manifest jako `authority=false`. Nie definiują topologii, aktywnego gameplayu, checkpointu, zapisu ani persistence i nie są wejściem kompilatora.
- Aktualne zachowanie odczytuj z manifestu, prywatnego runtime i testów, a zatwierdzoną regułę widoczną dla gracza z globalnego dokumentu produktu.

## Dokumentacja

Pakiet posiada dokładnie dwa dokumenty kontraktowe:

- `AGENTS.md` — ten proces i granice;
- `README.md` — operacyjny indeks źródeł i komendy.

Nie twórz innych plików `.md`, `.txt`, lokalnego kontekstu ani rejestru decyzji. Załączone DOCX, PNG, JSON i plik kontroli integralności w `references/` są nieautorytatywnym materiałem wejściowym, nie równoległą dokumentacją produktu.

## Wykonanie i weryfikacja

1. Ustal edytowalne źródło z `structure_manifest.json` i sprawdź wskazane skrypty, assety oraz lokalne testy.
2. Porównaj zmianę z aktywnymi decyzjami Mapy i globalnymi. Nie zmieniaj przy okazji placementu ani semantyki zapisu.
3. Po zmianie źródła w jednym root-routed worktree uruchom `--seal-structure-package tower_three_inlets_02`, `--build-structure tower_three_inlets_02`, `--check-structure tower_three_inlets_02`, oba testy pakietu, a następnie `--refresh-structure-package tower_three_inlets_02` z dokładnym SHA-256, pełny mapowy `--build`/`--check` i pełne testy Mapy.
4. Jeden PR musi zawierać źródła, seal, mapowy pin i wszystkie pochodne. Po zmianie bazy powtórz cały builder i zestaw testów.
5. Po zmianie widocznej grafiki wykonaj natywny capture dokładnej wygenerowanej sceny i obejrzyj wynik.
6. ImageGen pozostaje zablokowany, dopóki proxy nie zostanie obejrzane w dokładnej wygenerowanej `UnderwaterMap.tscn` i jawnie zaakceptowane przez użytkownika. Produkcyjny wynik musi zachować natywne `2400 × 3840`, `scale = Vector2.ONE` i mapowanie jeden piksel na jedną jednostkę lokalną.
7. Po zmianie topologii zachowaj ręczny playtest całej struktury. Automatyczna kontrola osiągalności nie zastępuje przepłynięcia.

`ERROR` i `SCRIPT ERROR` oznaczają porażkę także przy kodzie wyjścia `0`. W podsumowaniu podaj zmienione źródła, build/check/testy, dokumenty przeczytane w całości, wynik oględzin oraz następny krok.
