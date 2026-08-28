# Project Context — mapa podwodna

Rola pliku: krótka, datowana migawka bieżącego pakietu mapy, luk i ostatniej weryfikacji. Rutynowy agent czyta tylko sekcję lub punkt związany ze swoim zadaniem. Reguły trwałe należą do `.ai/DECISIONS.md`, a proces i komendy do `AGENTS.md` oraz `README.md`.

## Stan odniesienia — 2026-08-27

- `map_manifest.json` używa schema v6 i jest jedynym authority rejestracji, globalnego placementu oraz kompozycji `UnderwaterMap`. Świat ma `23040 × 12960` jednostek, a lokalna `UnderwaterMap.tscn` jest wyłącznie deterministyczną pochodną buildera.
- Aktywna kompozycja zawiera proceduralne tło wody L00, natywne bitmapy 1:1 na planach L01/L02, globalną topologię i grunt L05 oraz stabilne korzenie L00–L10. L01/L02 korzystają z asynchronicznej rezydencji okna kamery z budżetem, prefetch, retencją i telemetrią; warstwy wizualne nie posiadają fizyki, a ograniczenie ruchu wynika wyłącznie z topologii.
- Payload L05 schema v2 opisuje jeden globalny raster ownerów. Builder rozdziela granice `world` i zarejestrowanych pakietów struktur bez podwójnej ściany na styku; globalna fizyka świata oraz lokalne kolidery pakietów pozostają osobnymi właścicielami.
- Rejestr zawiera obecnie dwa aktywne pakiety struktur. Mapa posiada ich stable ID, origin, aktywność i hash-pinned referencje. Lokalne manifesty pakietów posiadają rozmiar, topologię, sockety, grafikę, runtime i testy, a ich prywatne ID, pozycje i pozostałe wartości celowo nie są kopiowane do tej ogólnej migawki.
- W01 jest przypięty do sealed manifestu `934cb681…2ac84`. Rewizja N+3 zmienia wyłącznie bitmapę konstrukcji oraz jej pin na bazie zachowanego wnętrza N+2; mapowa `presentation_revision` została naturalnie podniesiona z v18 do `center-station-right-city-two-tower-production-v19`, a lokalny digest topologii struktury, globalna topologia i sygnatura gameplayu pozostają bez zmian.
- Builder, kompilator i smoke odkrywają pakiety dynamicznie. Wspólna warstwa zna tylko publiczną kopertę pakietu, deklarowany skrypt kontrolera oraz cykl `configure(...)` / `reset_attempt()`; prywatny gameplay budynku pozostaje nieprzezroczysty.
- Mapowy visual survey jest manifest-driven i wiąże plan z hashowanym snapshotem przechodnich zależności renderu. Obejmuje każdy landmark, oba kierunki każdego otworu aktywnej struktury, pełne pasma pionowe, dynamicznie wykryte luki tła oraz world-locked, kafelkowy overview; kadry wnętrza i stanów prywatnego runtime nadal należą do danego pakietu.
- `PortalBackdropClearances` tworzy dla każdego anonimowo wykrytego, traversable biegu otworu granicznego jedną wizualną szczelinę w tle nad L01/L02 i pod L03/L04. Geometria i digest nie zależą od ID, nazwy ani ścieżki pakietu; rdzeń i ograniczony feather używają pełnych kolorów wyprowadzonych z `visual.water_color`, a węzły nie mają kolizji, `Area2D`, stanu ani wpływu na topologię.
- L05 ma pierwszy mapowy pass prezentacyjny: maska szczegółu rozdziela osad, szwy ownerów i zużycie ram wejść, a shader nakłada stonowaną wariację materiału i tłumienie wraz z głębokością bez zmiany topologii ani sygnatury gameplayu.
- Avatar gracza jest zewnętrznym konsumentem mapy. Jego scena, grafika, animacje, sockety, VFX i authoring znajdują się w `../diver_workbench/`; złożenie Mapy z Nurkiem oraz regułami kampanii sprawdzają testy integracyjne root.

## Granica pracy

- Pakiety struktur, Mapa i Nurek mogą powstawać równolegle w osobnych worktrees i na osobnych gałęziach. Prywatne `--build-structure` i `--check-structure` pracują tylko na wskazanym ID i lokalnym `.godot`; nie zapisują authority Mapy ani innego pakietu.
- Zmiana struktury wymagająca nowego seala i pinu jest jednym root-routed PR obejmującym źródła pakietu, mapowy pin oraz pochodne. Pozostałe zmiany `map_manifest.json`, `UnderwaterMap.tscn`, metadanych builda i `structures/*/generated/**` należą do zwykłego zakresu Mapy. Przy kilku nowych sealed manifestach builder może odświeżyć dokładne SHA-256 jednym batchem i musi pozostawić spójny zestaw.
- Builder i runner odrzucają niezgodne EOL oraz izolują `.godot`, `user://`, logi i porty. Zatwierdzona kolejność to `implementacja -> lokalne testy zadania -> lokalny fast-check`; po `PASS` następuje `commit -> push + PR -> KONIEC`. Osobny wymagany GitHub `fast-check PASS` oraz pełne testy złożenia w merge queue przed scaleniem działają zgodnie z ARD-0113; stan finalnego buildera opisuje globalny `.ai/PROJECT_CONTEXT.md`.

## Luki

- `[PENDING_BUILDER_COPY]` Aktywne komunikaty help/error buildera nadal używają historycznej terminologii osobnego hand-offu. Obowiązujący kontrakt wymaga jednego root-routed PR seal+pin; uproszczenie tekstu w kodzie należy do osobnego map-owned PR.
- `[PENDING_USER_ACCEPTANCE]` Automatyczny capture nie zastępuje ręcznego przepłynięcia tras, odbioru skali, czytelności wejść, kolizji Nurka, atmosfery ani wydajności pełnego `DiveScene`.
- `[PENDING_MAP_POLISH]` W true-map `target_0020/0021` pozostaje widoczna ograniczona, ciemna granica mapowego `PortalBackdropClearance` po lewej stronie wejścia W01. Jest to odziedziczony, visual-only artefakt compositingu Mapy, a nie część bitmap W01 N+2/N+3 ani regresja kolizji; wymaga osobnego polishu mapowego.
- `[PENDING_PERFORMANCE_ACCEPTANCE]` Rezydencja L01/L02 przechodzi test skrajnych pozycji, stale requestów i budżetu, lecz końcowe hitching/VRAM należy jeszcze potwierdzić w ręcznym przebiegu pełnego `DiveScene`.

## Ostatnia weryfikacja

- 2026-08-27: W01 przyjął sealed manifest `934cb681…2ac84`; pełny mapowy `--build` i niedestrukcyjny `--check` odtworzyły presentation v19 bez zmiany lokalnej lub globalnej topologii ani sygnatury gameplayu.
- Na jednej izolowanej migawce map smoke, boundary, kontrakt i runtime W01, natywny capture oraz survey prawdziwego `UnderwaterMap.tscn` przeszły po `1/1 PASS`, bez `ERROR` i `SCRIPT ERROR`. Ręczne oględziny overview, obu podejść do wejścia, B/C/D, szybu, piwnicy i drzwi zakończyły się `ART PASS`; ciemna granica po zachodniej stronie wejścia pozostaje opisaną wyżej luką Mapy.
- Portal contract przeszedł `6/6`, map atomic `23/23`, a map smoke, `base_environment_test` i kontrakt kampanii po `1/1 PASS`. Preflight EOL oraz izolacja runnera zostały sprawdzone w Windows PowerShell 5.1 i PowerShell 7.
- Survey zapisał 686 rekordów i 576/576 kafli overview; world-lock i stitch przeszły bez błędów oraz brakujących tekstur. Kadry W02 nie zawierają napisu `PROXY` ani pełnego backwallu, a L01/L02 pozostają widoczne przez open-water. Capture dowodzi renderu, lecz nie zastępuje ręcznego przepłynięcia ani odbioru wydajności.
