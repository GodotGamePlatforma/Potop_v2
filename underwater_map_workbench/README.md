# Underwater Map Workbench

Ten katalog zawiera jedyny aktywny pakiet konkretnej mapy podwodnej. Nie jest osobnym projektem Godot: używa `../project.godot`, ogólnych systemów runtime i wspólnego runnera z katalogu nadrzędnego.

Po wejściu do warsztatu wszystkie ścieżki w tym pliku są liczone od `underwater_map_workbench/`. Wartość przekazana do `-Target` lub `-NativeTarget` pozostaje ścieżką `res://` projektu, dlatego zaczyna się od `underwater_map_workbench/` albo `tests/`.

## Własność pakietu

| Ścieżka | Rola |
|---|---|
| `map_manifest.json` | jedyne authority rejestracji, stable ID i globalnego placementu mapy |
| `structures/<id>/structure_manifest.json` | podrzędne authority lokalnej topologii, socketów, grafiki, skryptów i runtime jednego budynku |
| `structures/<id>/AGENTS.md` i `README.md` | węższy routing oraz operacyjny onboarding pakietu, bez kopii gameplayu i decyzji |
| `assets/topology/` i `assets/visual/` | edytowalne źródła wskazane przez manifest |
| `UnderwaterMap.tscn`, `assets/generated/` i `structures/<id>/generated/` | deterministyczne pochodne; nie edytuj ręcznie |
| `runtime/` | lokalny kompilator i cienki host pakietu |
| `tools/build_underwater_map.py` | jedyny builder i niedestrukcyjny check |
| `tests/underwater_map_smoke_test.gd` | techniczny test wnętrza Mapy |
| `tests/underwater_map_visual_residency_test.gd` | kontrakt okna, budżetu i kolejki asynchronicznej grafiki L01/L02 |
| `tests/underwater_map_proxy_capture_test.gd` | natywny render wygenerowanej sceny do oględzin |

Root zachowuje kampanię, ogólne mechaniki nurkowania, dane, zapis, UI i testy integracyjne. `../diver_workbench/` zachowuje jedyną scenę oraz prezentację avatara. Warsztat mapy może z tych publicznych kontraktów korzystać, ale ich nie kopiuje ani nie edytuje w zadaniu lokalnym.

Aktualne rewizje, format schema, globalne pozycje, liczności, podpisy i wynik ostatniej weryfikacji znajdują się w `map_manifest.json` oraz `.ai/PROJECT_CONTEXT.md`. Lokalna zawartość budynku pochodzi z jego `structure_manifest.json`; trwałe zasady topologii, warstw i pakietów struktur znajdują się w `.ai/DECISIONS.md`.

## Szybki start

Z CWD `underwater_map_workbench/`:

```powershell
Test-Path ..\project.godot
git -C .. rev-parse --show-toplevel
python .\tools\build_underwater_map.py --check
..\tests\run_all_tests.ps1 -Target underwater_map_workbench/tests/underwater_map_smoke_test.gd
..\tests\run_all_tests.ps1 -Target underwater_map_workbench/tests/underwater_map_visual_residency_test.gd
```

Pełna kontrola granic Root–Mapa–Struktury–Nurek:

```powershell
..\tests\run_all_tests.ps1 -Target tests/workbench_boundary_test.gd
```

Szybka kontrola dowolnego prywatnego pakietu:

```powershell
python .\tools\build_underwater_map.py --build-structure <id>
python .\tools\build_underwater_map.py --check-structure <id>
```

Dokładne nazwy dwóch lokalnych testów i komendy celowane publikuje wyłącznie `structures/<id>/README.md`. Wspólny szybki runner odkrywa kontraktowe testy wszystkich zarejestrowanych pakietów dynamicznie, a pełny runner także ich testy runtime.

Natywny capture mapy:

```powershell
..\tests\run_all_tests.ps1 -NativeTarget underwater_map_workbench/tests/underwater_map_proxy_capture_test.gd
```

Capture zapisuje `visual_survey.json`, kafelkowe `overview.png` oraz kadry celów w izolowanym `user://test_underwater_map_visual_survey`. Otwórz obrazy i oceń pełną kompozycję, podejścia do landmarków i wejść struktur, sektory pionowe oraz wykryte luki tła; sam `PASS` potwierdza wykonanie harnessu, nie jakość artystyczną ani osiągalność trasy. Prywatne kadry konkretnego budynku należą do jego `structures/<id>/tests/` i są opisane wyłącznie w lokalnym README pakietu.

## Przepisy zmian

Zmiana mapowego manifestu, globalnego payloadu albo mapowej grafiki bez zmiany topologii:

```powershell
python .\tools\build_underwater_map.py --build
python .\tools\build_underwater_map.py --check
..\tests\run_all_tests.ps1 -Target underwater_map_workbench/tests/underwater_map_smoke_test.gd
```

Po zmianie źródła topologii najpierw ustaw wymagane rewizje zgodnie z aktywnym MAP-ARD, a następnie:

```powershell
python .\tools\build_underwater_map.py --refresh-l05-source
python .\tools\build_underwater_map.py --build
python .\tools\build_underwater_map.py --check
..\tests\run_all_tests.ps1 -Target underwater_map_workbench/tests/underwater_map_smoke_test.gd
```

Prywatny producent jednego zarejestrowanego pakietu używa lżejszego loopu we własnym worktree. Pierwszą komendę uruchom tylko po zmianie źródła albo hasha:

```powershell
python .\tools\build_underwater_map.py --seal-structure-package <id>
python .\tools\build_underwater_map.py --build-structure <id>
python .\tools\build_underwater_map.py --check-structure <id>
```

Następnie uruchom dwa cele wskazane w lokalnym `structures/<id>/README.md` i przekaż niezmienny commit albo zweryfikowaną rewizję FROZEN. Ich prywatnych nazw nie kopiuje się do dokumentacji Mapy.

Integrator Mapy, w osobnym czystym worktree i dla dokładnego sealed hasha, wykonuje dopiero:

```powershell
python .\tools\build_underwater_map.py --refresh-structure-package <id> --sealed-package-sha256 <SHA256>
python .\tools\build_underwater_map.py --build
python .\tools\build_underwater_map.py --check
..\tests\run_all_tests.ps1 -Target underwater_map_workbench/tests/underwater_map_smoke_test.gd
```

Jeżeli dwa lub więcej odebranych manifestów zmieniło się od ostatniej promocji, integrator przekazuje wszystkie pary w jednej komendzie. Builder najpierw rehashuje cały zamknięty batch, nakłada wszystkie piny na jednego kandydata, a dopiero potem waliduje i publikuje jednym CAS:

```powershell
python .\tools\build_underwater_map.py `
  --refresh-structure-package <id-a> --sealed-package-sha256 <SHA256-a> `
  --refresh-structure-package <id-b> --sealed-package-sha256 <SHA256-b>
```

`--seal-structure-package <id>` zapisuje wyłącznie lokalne hashe i digesty prywatnego manifestu; nie dotyka mapowego pinu ani wspólnych pochodnych. Prywatne `--build-structure` i `--check-structure` rozwiązują tylko wskazany pakiet i korzystają z ignorowanego, rozłącznego outputu danego worktree pod `.godot/underwater_map_structure_builds/<id>/generated`; nie zapisują authority `structures/<id>/generated/**` i nie zdobywają `map-promotion`. `--refresh-l05-source` służy wyłącznie zmianie złożonego źródła topologii; dla aktualnych źródeł jest byte-no-op. Powtarzalne pary `--refresh-structure-package <id> --sealed-package-sha256 <SHA256>` należą do Mapy: wymagają dokładnych hashy z immutable/FROZEN hand-offów, aktualizują w jednym kandydacie tylko mapowe piny i pochodne deklaracje, nigdy prywatne źródło. Pełny mapowy build/check i smoke są wymagane przy rejestracji, zmianie originu, publicznym montażu albo przed odbiorem integracyjnym, nie po każdej prywatnej iteracji. Po zmianie publicznej granicy uruchom także właściwy test root. Po zmianie widocznej prezentacji wykonaj i obejrzyj natywny capture. Po zmianie topologii ręcznie przepłyń wymagane trasy — builder i smoke nie certyfikują ich jakości.

Wspólna blokada `map-promotion` obejmuje tylko krótki rehash i publikację zestawu Mapy; prywatny seal, check i test pakietu jej nie zdobywają. Celowany runner nie odkrywa niezwiązanych pakietów, a każdy przebieg izoluje `.godot`, `user://`, logi i capture.

Nigdy nie poprawiaj ręcznie `UnderwaterMap.tscn`, masek ani innych pochodnych. Nie twórz plików `candidate`, `final`, drugiego `map_manifest.json`, manifestu wariantu, alternatywnej sceny, dodatkowego projektu ani kopii avatara. `structure_manifest.json` jest dozwolonym źródłem podrzędnym: nie może zawierać globalnego placementu ani trwałego stanu, a cykl próby deklaruje jawnie przez `attempt_state.persistence=none` i `checkpoint=none`.

## Dokumentacja

- `AGENTS.md` — proces, routing i granice zapisu;
- `.ai/PROJECT_CONTEXT.md` — krótki aktualny stan oraz ostatnia weryfikacja;
- `.ai/DECISIONS.md` — trwałe decyzje mapy i ich zastąpienia;
- `README.md` — ten onboarding i komendy;
- `structures/<id>/AGENTS.md` — proces i węższa granica zapisu jednego pakietu;
- `structures/<id>/README.md` — lokalne źródła prawdy i komendy bez powtarzania zachowania gracza.

Globalne reguły produktu, architektury i persistence pozostają w dokumentach root. Pakiety nie mają własnego `.ai`, MAP-ARD ani drugiej specyfikacji gameplayu. DOCX lub obraz wskazany w manifeście jako `authority=false` pozostaje wyłącznie provenance i nie steruje implementacją. Poza powyższym zatwierdzonym zestawem w warsztacie nie tworzy się innych plików dokumentacyjnych.
