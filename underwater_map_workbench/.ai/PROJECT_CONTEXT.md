# Project Context — mapa podwodna

Rola pliku: krótka, datowana migawka bieżącego pakietu mapy, luk i ostatniej weryfikacji. Reguły trwałe należą do `.ai/DECISIONS.md`, a proces i komendy do `AGENTS.md` oraz `README.md`.

## Stan odniesienia — 2026-08-25

- Aktywny `map_manifest.json` używa schema v2 i rewizji `reset-a-common-line-v1` / `open-world-1` / `campaign-markers-1`. Jest jedynym edytowanym źródłem authoringu; lokalna `UnderwaterMap.tscn` jest jedyną sceną mapy runtime i byte-exact pochodną buildera.
- Bieżący kontrakt mapy wymaga dokładnie `12 × 12` komórek po `1920 × 1080`, czyli świata `23040 × 12960`; builder i kompilator odrzucają inne wymiary nawet wtedy, gdy są wewnętrznie spójne. Cztery bieżące regiony oraz liczby landmarków, obiektów i assetów pozostają danymi rewizji, nie ograniczeniami schema.
- Cztery landmarki kampanii to `dive_station` `[2880, 1400]`, `flooded_archive` `[8640, 4400]`, `generator_r3` `[14400, 7400]` i `switchboard_c4` `[20160, 10100]`.
- Sześć urządzeń tworzy strukturalną kolejność `junction_j7` `[2880, 3900]` → `archive_terminal` `[8640, 4400]` → `r3_diagnostic_panel` `[13920, 7200]` → `r3_generator` `[14880, 7600]` → `c4_switchboard` `[19680, 9900]` → `c4_splitter_mount` `[20520, 10300]`. Każde wskazuje jeden z czterech bieżących landmarków; dawne fizyczne ID `R1-09`, `R3-04` i `R4-06` nie są authority.
- Topologia jest jawnym foundation `open_world`: `collision_source.format = none`, brak authorowanego terenu i payloadu L05 oraz brak chronionych korytarzy. Nie jest to zatwierdzony finalny kolider ani dowód rzeczywistej osiągalności.
- Wygenerowana scena publikuje stabilne korzenie `L00-L10`. L05 jest world-locked kotwicą przyszłego `collider_authority`, L10 wyłączoną rezerwą, a `visual.assets` pozostaje puste do wdrożenia typowanego renderera. Drzewo wizualne nie zawiera węzłów fizyki.
- Lokalny runtime obsługuje `reduced_motion` dla wszystkich bieżących `Parallax2D`, bezpiecznie zapamiętuje skalę autorską i nie odczytuje brakującego metadata bez `has_meta()`.
- Builder i smoke walidują strukturę kampanii, unikalność oraz referencje, lecz nie wykonują blokującego BFS, flood-fill, testu komórki, dystansu ani certyfikacji trasy. Przyszły kolider L05 ocenia użytkownik przez ręczne przepłynięcie pełnej sekwencji kampanii.

## Luki

- `[DOCELOWE]` Zbudować konkretny, hash-pinned payload L05 i wyprowadzać z niego fizykę oraz prowadnice grafiki. Ustalona semantyka pliku to `solid = 0`, `open_water = 255`; przyszły adapter musi jawnie mapować `255` na otwartą komórkę runtime, ponieważ legacy `MapNavigationRaster.build(image)` interpretuje jasny piksel odwrotnie.
- `[DOCELOWE]` Wdrożyć typowany renderer `visual.assets` ze źródłem, socketem, finalnym transformem, SHA topologii i maską bariery, a następnie authorować grafikę pod zamrożone L05 tak, aby żadna warstwa nie sugerowała ściany w przechodniej wodzie.
- `[DOCELOWE]` Po powstaniu L05 wykonać ręczny playtest J-7 → Archiwum → R-3 → C-4 oraz osobny pełnomapowy odbiór wizualny. Obecna rewizja nie zawiera produkcyjnej grafiki ani finalnego kolidera, więc nie ma jeszcze wyniku odbioru artystycznego.

## Ostatnia weryfikacja

- 2026-08-25: builder oraz niedestrukcyjny `--check` potwierdziły synchronizację sceny z surowym SHA manifestu `822c1660f17b4ec96b9e6671cabf5a402799dc6fee38ad60d9dd320e98a52847`, podpisem `manifest-v2:bf0d9ecb711177f1170e6d7dca144c3de62f921af34043643ea7f2d5985442f9` i fingerprintem `presentation-v2:4f4b443cbae0f8a9ca94d57c4cae0336931ebb513368069525176b4b355f3cec`. Osobne fixture'y buildera potwierdziły, że fizyczne przypisanie etapu kampanii pochodzi z manifestu oraz że spójna wewnętrznie mapa o innym rozmiarze jest odrzucana.
- Izolowany Godot 4.7.1: lokalny smoke `1/1` z przypadkami granicznymi wymiarów i manifest-owned przypisaniem kampanii, rootowy kontrakt kampanii `1/1`, quick runner `15/15` oraz pełny runner `46/46` — bez `ERROR`, `SCRIPT ERROR`, pominięć i timeoutów. Nie uruchamiano visual survey, ponieważ ta rewizja ustanawia foundation danych/runtime bez produkcyjnej grafiki i konkretnego L05.
