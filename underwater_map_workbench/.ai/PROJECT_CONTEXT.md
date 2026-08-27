# Project Context — mapa podwodna

Rola pliku: krótka, datowana migawka bieżącego pakietu mapy, luk i ostatniej weryfikacji. Reguły trwałe należą do `.ai/DECISIONS.md`, a proces i komendy do `AGENTS.md` oraz `README.md`.

## Stan odniesienia — 2026-08-27

- `map_manifest.json` używa schema v6 i jest jedynym authority rejestracji, globalnego placementu oraz kompozycji `UnderwaterMap`. Świat ma `23040 × 12960` jednostek, a lokalna `UnderwaterMap.tscn` jest wyłącznie deterministyczną pochodną buildera.
- Aktywna kompozycja zawiera proceduralne tło wody L00, natywne bitmapy 1:1 na planach L01/L02, globalną topologię i grunt L05 oraz stabilne korzenie L00–L10. L01/L02 korzystają z asynchronicznej rezydencji okna kamery z budżetem, prefetch, retencją i telemetrią; warstwy wizualne nie posiadają fizyki, a ograniczenie ruchu wynika wyłącznie z topologii.
- Payload L05 schema v2 opisuje jeden globalny raster ownerów. Builder rozdziela granice `world` i zarejestrowanych pakietów struktur bez podwójnej ściany na styku; globalna fizyka świata oraz lokalne kolidery pakietów pozostają osobnymi właścicielami.
- Rejestr zawiera obecnie dwa aktywne pakiety struktur. Mapa posiada ich stable ID, origin, aktywność i hash-pinned referencje. Lokalne manifesty pakietów posiadają rozmiar, topologię, sockety, grafikę, runtime i testy, a ich prywatne ID, pozycje i pozostałe wartości celowo nie są kopiowane do tej ogólnej migawki.
- Builder, kompilator i smoke odkrywają pakiety dynamicznie. Wspólna warstwa zna tylko publiczną kopertę pakietu, deklarowany skrypt kontrolera oraz cykl `configure(...)` / `reset_attempt()`; prywatny gameplay budynku pozostaje nieprzezroczysty.
- Mapowy visual survey jest manifest-driven i wiąże plan z hashowanym snapshotem przechodnich zależności renderu. Obejmuje każdy landmark, oba kierunki każdego otworu aktywnej struktury, pełne pasma pionowe, dynamicznie wykryte luki tła oraz world-locked, kafelkowy overview; kadry wnętrza i stanów prywatnego runtime nadal należą do danego pakietu.
- L05 ma pierwszy mapowy pass prezentacyjny: maska szczegółu rozdziela osad, szwy ownerów i zużycie ram wejść, a shader nakłada stonowaną wariację materiału i tłumienie wraz z głębokością bez zmiany topologii ani sygnatury gameplayu.
- Avatar gracza jest zewnętrznym konsumentem mapy. Jego scena, grafika, animacje, sockety, VFX i authoring znajdują się w `../diver_workbench/`; złożenie Mapy z Nurkiem oraz regułami kampanii sprawdzają testy integracyjne root.

## Bieżące okno integracyjne

- Źródła pakietów i Nurka mogą powstawać równolegle w osobnych linked worktrees z rozłącznymi allowlistami. Prywatne `--build-structure` i `--check-structure` tworzą per-ID kandydatów wyłącznie w lokalnym `.godot`, bez discovery innego pakietu i bez zapisu do authority Mapy.
- Każdy tryb buildera i wspólny runner przed pracą odrzuca tracked `w/crlf` albo `w/mixed` przy `eol=lf`; legalne dirty źródło zapisane LF pozostaje dozwolone. Candidate receipt dodatkowo porównuje surowe bajty czystego tracked tree z exact HEAD/index.
- `map_manifest.json`, `UnderwaterMap.tscn`, mapowe metadane builda i `structures/*/generated/**` pozostają jednym szeregowym punktem promocji obsługiwanym przez integratora. Gdy zmienia się kilka pinów, wszystkie exact sealed SHA są odświeżane jednym batchem i publikowane z pełnym build/check; pojedyncze częściowe przejście nie może pozostawić mieszanej rewizji.
- Piny obu odebranych pakietów są zgodne z ich manifestami. Runner nie zdobywa `map-promotion` ani nie wykonuje refreshu; testuje niezmienną kopię Git-zamkniętego źródła z osobnym `.godot`, `user://`, logami i portami. Nowy pakiet nie staje się częścią Mapy przed jawną rejestracją i integracyjną promocją.

## Luki

- `[PENDING_NEXT_REVISION]` Każda kolejna stabilna zmiana pakietu wymaga nowej, krótkiej promocji. Producent nie musi kończyć zadania: po zamrożeniu kopii może od razu rozwijać następną rewizję, a wynik Godota pozostaje przypisany do digestu testowanego workspace.
- `[PENDING_USER_ACCEPTANCE]` Automatyczny capture nie zastępuje ręcznego przepłynięcia tras, odbioru skali, czytelności wejść, kolizji Nurka, atmosfery ani wydajności pełnego `DiveScene`.
- `[PENDING_ART]` Złożenie i placement drugiego zarejestrowanego budynku są technicznie poprawne. Generowane `PROXY` i pełnokadrowy backwall zostały usunięte; pozostałe szerokie, twarde powierzchnie należą do produkcyjnego assetu W02 i ich ewentualny polish jest prywatną rewizją tego pakietu bez zmiany alfy lub topologii.
- `[PENDING_PERFORMANCE_ACCEPTANCE]` Rezydencja L01/L02 przechodzi test skrajnych pozycji, stale requestów i budżetu, lecz końcowe hitching/VRAM należy jeszcze potwierdzić w ręcznym przebiegu pełnego `DiveScene`.

## Ostatnia weryfikacja

- 2026-08-27, oficjalny pełny `--build` odtworzył authority po normalizacji LF, a po podpięciu preflightu EOL niedestrukcyjny `--check` przeszedł dla buildera SHA `a487057d34934ab32e8899d84a1d4cb8209b4edda75d72a37972525aaf50e023`, manifestu SHA `5c1065e5562ab41b883e0cf18386870603971155297f3c682821417f964c6754` i sceny SHA `a2095c9c206a5147a5001bdd7e479150baba9a012cb1b9e73f9e40b53fdca1d3`. Sygnatura gameplayu `bf7e949f…` i fingerprint prezentacji `433da29c…` pozostały bez zmiany.
- Źródło `l05_ground_mask_source.json` jest byte-identycznym blobem LF SHA `75b8bf49…`; manifest, scena i truth package pinują ten sam SHA. Map atomic przeszedł `20/20`, a isolated map smoke, `base_environment_test` i kontrakt kampanii zakończyły się po `1/1 PASS`; diff prywatnych źródeł W01/W02 pozostał pusty.
- Zbiorcza promocja przypięła dokładne sealed manifesty W01 `f1e37a8f…cc626` i W02 `c20e87fb…f28cf`; unit test atomowej publikacji przeszedł `20/20`. Końcowy diff buildera miał wyłącznie oczekiwane pochodne, zero zmian prywatnych i zero nieoczekiwanych plików.
- Finalny FROZEN smoke przeszedł `1 PASS / 0 FAIL / 0 SKIP`, receipt `14d105f843cc8061df91c519ef1cc861f1e575a9b72d2a44b25804090f29ba00`. Preserved native survey przeszedł z receiptem `2fb75867d55bff20c1f47bf745d19283182565789838aa4a94394cd189b59677`.
- Survey zapisał 686 rekordów, w tym 576/576 kafli overview; world-lock i stitch przeszły, brak błędów oraz brakujących tekstur. Kadry W02 nie zawierają napisu `PROXY` ani pełnego backwallu, a L01/L02 są widoczne przez open-water. Capture jest technicznym dowodem renderu, nie certyfikacją osiągalności i odczucia ręcznego przepłynięcia.
- Historyczny pełny FROZEN runner zakończył się `53 PASS / 0 FAIL / 0 SKIP`, lecz green baseline dla nowych worktrees wymaga przenośnej pary candidate/full-run z tego samego czystego exact HEAD/tree; oba receipty pozostają zewnętrznymi artefaktami workflow/bootstrapu.
