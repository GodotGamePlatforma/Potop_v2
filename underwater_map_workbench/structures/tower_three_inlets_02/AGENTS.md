# Instrukcje pakietu struktury `tower_three_inlets_02`

Ten katalog jest podrzędnym pakietem Mapy, nie osobnym projektem Godot ani dodatkowym warsztatem domenowym. Ustaw CWD narzędzi na `underwater_map_workbench/structures/tower_three_inlets_02/`; pełny projekt pozostaje w `../../..`, a nadrzędny warsztat Mapy w `../..`.

`AGENTS.md` określa wyłącznie proces, routing, granice zapisu i weryfikację. Nie ustanawia zachowania gracza, pozycji globalnej, persistence ani technicznej migawki implementacji.

## Kontekst przed pracą

Dla zwykłej poprawki tego budynku przeczytaj ten plik, lokalny `README.md`, `structure_manifest.json`, dokładny rekord `tower_three_inlets_02` w `../../map_manifest.json` oraz wyłącznie związane źródła i testy. W `.ai/PROJECT_CONTEXT.md` Mapy przeczytaj tylko punkt dotyczący bieżącej struktury lub otwartej luki. Nie czytaj pełnych decyzji, produktu ani architektury, jeżeli nie zmieniasz ich kontraktu. Jeżeli rekordu mapowego nie ma, nie wymyślaj placementu.

Pełny routing root jest wymagany dopiero przy zmianie reguły produktu, publicznej granicy, schema, persistence, zapisu albo semantycznego kontraktu kilku właścicieli. Mechaniczne opublikowanie lokalnej poprawki razem z nowym sealem, mapowym pinem i pochodnymi nie uruchamia pełnego odczytu dokumentów: pozostaje jednym prostym, root-routed zadaniem według lokalnego README. Zmiana samego originu, rejestracji lub globalnego payloadu jest zadaniem Mapy.

## Granica odczytu i zapisu

- Domyślna allowlista zapisu obejmuje wyłącznie `underwater_map_workbench/structures/tower_three_inlets_02/**`.
- W czysto lokalnej iteracji `../../map_manifest.json`, `../../UnderwaterMap.tscn`, pozostała Mapa, root, inne pakiety struktur i `../../../diver_workbench/**` są tylko do odczytu. Jeżeli seal wymaga nowego pinu, użyj jednego root-routed zadania obejmującego pakiet i wymagane pochodne Mapy; nie twórz package-only PR.
- Pakiet może konsumować publiczne typy i kontrakty projektu nadrzędnego, ale nie kopiuje ani nie poprawia ich przy okazji prywatnego zadania.
- Rutynowa poprawka nie wymaga predeklaracji dokumentów ani pełnego write-setu. Po edycji porównaj diff z allowlistą; nieplanowany zapis poza nią zatrzymuje pracę.
- Pakiet nie posiada własnego `project.godot`, `.godot`, `.ai`, `map_manifest.json`, `UnderwaterMap.tscn`, ARD, kampanii ani konfiguracji zapisu.

### Współbieżność

- Root lub koordynator przydziela zmianę seal+pin jako jedno proste zadanie jednemu autorowi w osobnym pełnym Git worktree i na gałęzi `codex/structure-tower_three_inlets_02/<task-slug>` utworzonej z aktualnego `origin/main`. Ten sam branch i PR zawiera źródła pakietu, sealed manifest, mapowy pin/refresh oraz pochodne.
- Po implementacji autor wykonuje mechaniczne kroki z lokalnego README, lokalne testy zadania, a następnie osobny lokalny fast-check. Obecny fast-check nie wykonuje seala ani odtworzenia pochodnych. Po `PASS` autor wykonuje `commit -> push + PR -> KONIEC`; osobny GitHub `fast-check` decyduje o enqueue, a pełny `integration-green` wykonuje merge queue. Nie powstaje drugi PR Mapy.
- Lokalny build/check nie odkrywa innych struktur. Runner używa pełnej kopii z osobnym `.godot`, `user://`, logami i capture. Autor nie babysituje starego PR: prawdziwy konflikt albo nieaktualny seal, pin lub pochodna wykryta w kolejce wraca do root jako nowe zadanie dla nowego agenta startującego z aktualnego `main`, a koordynator zastępuje i zamyka stary PR.

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
2. Nie zmieniaj przy okazji placementu ani semantyki zapisu. Jeżeli zadanie wymaga zmiany kontraktu, dopiero wtedy przeczytaj właściwe ARD i wróć do routingu root.
3. Gdy zmieniło się źródło lub jego hash, wykonaj jeden przepis „Zmiana pakietu” z lokalnego README. Zawiera on wymagane seal/refresh/build/check, lecz agent nie musi projektować tych kroków.
4. Uruchom dwa lokalne testy zadania, a potem osobny fast-check. Po `PASS` utwórz commit i opublikuj jeden PR helperem wskazanym w README; zakończ bez pollingu. Pełną regresję wykonuje merge queue.
5. Po zmianie widocznej grafiki wykonaj natywny capture dokładnej wygenerowanej sceny i obejrzyj wynik.
6. ImageGen pozostaje zablokowany, dopóki proxy nie zostanie obejrzane w dokładnej wygenerowanej `UnderwaterMap.tscn` i jawnie zaakceptowane przez użytkownika. Produkcyjny wynik musi zachować natywne `2400 × 3840`, `scale = Vector2.ONE` i mapowanie jeden piksel na jedną jednostkę lokalną.
7. Po zmianie topologii zachowaj ręczny playtest całej struktury. Automatyczna kontrola osiągalności nie zastępuje przepłynięcia.

`ERROR` i `SCRIPT ERROR` oznaczają porażkę także przy kodzie wyjścia `0`. W podsumowaniu podaj zmienione źródła, testy i fast-check, wynik oględzin oraz następny krok.
