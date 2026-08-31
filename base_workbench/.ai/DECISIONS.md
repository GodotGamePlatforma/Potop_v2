# Lokalne decyzje warsztatu Bazy

Ten plik przechowuje wyłącznie trwałe decyzje prywatne dla implementacji Bazy. Nie ustanawia zasad produktu, trwałego stanu, persistence, kampanii ani publicznej architektury Root–Baza. Ich właścicielem pozostaje globalny rejestr decyzji i dokumenty root.

## Kontrakt wpisu

Nowy BASE-ARD powstaje tylko dla trwałego lokalnego inwariantu, do którego kolejne zmiany Bazy muszą się stosować. Zmiana zachowania widocznego dla gracza, stanu, zapisu, kolejności dnia albo granicy właściciela wymaga globalnej decyzji i nie może zostać zatwierdzona wyłącznie tutaj. Wpis zawiera status, datę, klauzule, relacje, powód i odwołania; nie zawiera dziennika prac ani wyniku testu.

## Indeks aktywnych decyzji

| ID | Zakres |
|---|---|
| BASE-ARD-0001 | Jeden pakiet Bazy i jeden projekt nadrzędny |
| BASE-ARD-0002 | Prezentacja Bazy konsumuje publiczny stan Root |

## BASE-ARD-0001 - Jeden pakiet Bazy i jeden projekt nadrzędny

- Status / aktywny zakres: Obowiązuje; D1-D5
- Zatwierdzenie: 2026-08-29
- Relacje: Uszczegóławia ARD-0114 | Zastąpiona przez: brak
- D1. `base_workbench/` jest jedynym pakietem lokalnej domeny i prezentacji Bazy; nie istnieje jego druga kopia w root.
- D2. `runtime/BaseScene.tscn` jest jedyną aktywną sceną Bazy. Lokalne sceny budynków znajdują się w `ui/` i nie ustanawiają osobnego grafu uruchomieniowego.
- D3. Warsztat używa wyłącznie nadrzędnego `project.godot`, InputMapu, ustawień, importera i runnera. Nie posiada lokalnego projektu ani zapisywalnego cache w repozytorium.
- D4. `runtime/`, `ui/`, `systems/`, `definitions/`, `data/`, `assets/`, `tools/` i `tests/` są zamkniętymi rodzinami lokalnego authority. Zależności ogólne są konsumowane z root, nie kopiowane.
- D5. Dokładnie cztery lokalne dokumenty stanowią dozwolony zestaw dokumentacji: `AGENTS.md`, `README.md`, `.ai/PROJECT_CONTEXT.md` i `.ai/DECISIONS.md`.
- Powód i skutek: jeden katalog daje agentowi kompletny kontekst Bazy bez drugiego projektu, drugiego stanu ani rozproszonego authority.
- Odwołania: ARD-0114; `../AGENTS.md`; `../README.md`.

## BASE-ARD-0002 - Prezentacja Bazy konsumuje publiczny stan Root

- Status / aktywny zakres: Obowiązuje; D1-D4
- Zatwierdzenie: 2026-08-29
- Relacje: Uszczegóławia ARD-0114/D2-D3,D6-D7 | Zastąpiona przez: brak
- D1. Kontroler, UI i systemy Bazy mogą czytać publiczne typy oraz wywoływać publiczne komendy root, ale nie przechowują równoległego `GameState`, planu dnia ani stanu persistence.
- D2. Podgląd i wykonanie lokalnej reguły korzystają z tego samego systemu domenowego Bazy; scena i UI nie tworzą drugiej kopii wzoru.
- D3. Test lokalny chroni wnętrze Bazy, natomiast persistence, kampania, atomowy koniec dnia i publiczne złożenie pozostają testami root.
- D4. Relokacja do warsztatu zachowuje zachowanie, UID, stable ID i nie aktywuje plików z `systems/inactive/`.
- Powód i skutek: Baza pozostaje skupionym właścicielem swojej prezentacji i lokalnych reguł bez przejmowania globalnej transakcji oraz zapisu.
- Odwołania: ARD-0002; ARD-0066; ARD-0114; `../../docs/Ostatni_Pomost_architektura_Godot.txt`.
