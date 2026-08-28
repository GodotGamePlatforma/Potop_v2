# Project Context

Ten dokument jest krótką, datowaną migawką potwierdzonego runtime. Odpowiada na pytanie „co działa teraz?”; nie ustanawia reguł produktu, architektury ani procesu pracy.

Routing pracy określa `AGENTS.md`. Decyzje normatywne są w `.ai/DECISIONS.md`, reguły widoczne dla gracza w `docs/OgolnyZarys.txt`, a mapowanie techniczne w `docs/Ostatni_Pomost_architektura_Godot.txt`. Szczegóły Bazy, Mapy i Nurka należą do ich lokalnych `PROJECT_CONTEXT.md`.

## Kontrakt wpisu i edycji

Dozwolone są wyłącznie: wersje i punkty wejścia potrzebne do pracy, zwięzła granica grywalnego zakresu, najważniejsi właściciele runtime, duże obszary łatwe do pomylenia z gotową funkcją, potwierdzone luki, istotne pułapki oraz jeden aktualny wynik weryfikacji.

Nie umieszczaj tutaj pełnych reguł, balansu, algorytmów, pól, migracji, assetów, shaderów, macierzy testów, procedur CI, receiptów, uzasadnień ani historii prac. Zastępuj je odsyłaczem do właściciela i aktualizuj istniejący fakt zamiast dopisywać kolejną warstwę.

Cały plik ma mieć najwyżej 12 000 znaków. Każdy zwykły wpis listy, liczony łącznie z liniami kontynuacji, ma najwyżej 300 znaków; wyjątkiem jest pojedynczy wpis ostatniej weryfikacji. `[AKTYWNE]` oznacza zachowanie potwierdzone w runtime; `[DOCELOWE]` — zatwierdzony, ale niewdrożony kierunek.

## Stan odniesienia

- Data migawki: 2026-08-29.
- Potwierdzony stan runtime: kandydat wydzielenia Bazy oparty na `origin/main` `015c9e0f199076251fa54fe0ab2f44c9b4b1a5d4`.
- Projekt deklaruje Godot 4.7; ostatnia pełna bramka korzystała z Godot 4.7.1.
- Główna scena: `res://scenes/main/GameRoot.tscn`.
- Autoloady: `SaveManager` i `GameDatabase`.
- Kampania ma jeden agregat `GameState` i jedną bieżącą rewizję formatu.
- Zapis używa zestawu `primary/pending/backup` i promuje wyłącznie zwalidowany agregat. Starsze rewizje oraz mapy sprzed `source-v5` są odrzucane bez cichego importu lub migracji pozycji. Szczegóły: architektura 11.

## Potwierdzony zakres runtime

- `[AKTYWNE]` Kampania prowadzi przez menu, intro, tutorial, planowanie Przystani, wyprawę albo dzień bez nurkowania, rozliczenie, raport i autosave. Produkt: sekcje 1–2; architektura: 3–6 i 12.
- `[AKTYWNE]` Retry tutorialowego nurkowania odtwarza odłączony baseline, a wynik trafia na zwalidowanego kandydata kampanii dopiero przed autosave. Kontrakty: ARD-0020 i ARD-0077.
- `[AKTYWNE]` Baza ma sześć stałych, typowanych slotów. Budowa i rozbudowa natychmiast aktywują opłacony poziom, natomiast praca dnia korzysta z uprzednio zamrożonego planu. Kontrakty: ARD-0018 i ARD-0076.
- `[AKTYWNE]` Obsada, produkcja, praca budynków, opieka medyczna i rozwój mieszkańców delegują mutacje do systemów domenowych; UI nie utrzymuje równoległego modelu stanu. Architektura: 4, 8.2 i 12.
- `[AKTYWNE]` Wyprawa ma granicę `ExpeditionSetup -> DiveSessionState -> DiveResult`; działają tlen, sprint, obciążenie, prąd, loot, interakcje, wyposażenie, ryzyko, powrót i śmierć. Architektura: 5.
- `[AKTYWNE]` Wspólna Linia prowadzi od tutoriala i J-7 przez Archiwum, R-3 i C-4 do trzech wyników energii, Kroniki oraz kontynuacji na tym samym zapisie. Produkt: 7 i 9–10.
- `[AKTYWNE]` Scena, UI, lokalne systemy, definicje, dane, assety i testy Bazy należą do `base_workbench`; Root zachowuje trwały stan, koniec dnia i integrację. Kontrakt: ARD-0114.
- `[AKTYWNE]` Mapa powstaje z `underwater_map_workbench/map_manifest.json`, a scena jest deterministyczną pochodną. Root nie przechowuje kopii mapowej semantyki ani worldowych assetów. Kontrakty: ARD-0102 i ARD-0106.
- `[AKTYWNE]` Avatar należy do `diver_workbench`; root korzysta z publicznej granicy `DiverController`, a ogólne systemy wyprawy pozostają poza pakietem avatara. Kontrakt: ARD-0105.

## Najważniejsze granice runtime

| Zakres | Właściciel | Publiczna granica |
|---|---|---|
| Kampania | `GameState` | jeden trwały agregat |
| Aplikacja | `GameRoot` | fazy, sceny, pauza i commit |
| Dzień | `DayPlanState`, `EndOfDayResolver` | plan -> zamrożona migawka -> kandydat stanu |
| Baza | `base_workbench` | `BaseScene` -> publiczny stan i komendy Root |
| Nurkowanie | moduł nurkowania | setup -> sesja -> wynik |
| Zapis | `SaveManager` i centralny validator | walidacja -> atomowa promocja |
| Mapa | `underwater_map_workbench` | manifest -> scena pochodna -> publiczny runtime |
| Avatar | `diver_workbench` | `Diver.tscn` -> `DiverController` |
| UI | kontrolery prezentacji | stan -> komendy domenowe, bez drugiego modelu |

Szczegółowe kontrakty właścicieli opisują `.ai/DECISIONS.md` i architektura, sekcje 3–6, 9, 11 i 12.

## Ważne luki i granice nieaktywne

- `[LUKA IMPLEMENTACYJNA]` Typowany system Gorączki Zalewowej, Lecznica, izolacja i odporność działają, ale mapa `source-v5` nie ma producenta narażenia. Ścieżka nowych zakażeń mapowych jest więc obecnie nieosiągalna. Kontrakty: ARD-0073 i ARD-0102.
- `[DOCELOWE]` Rotacja załogi ma izolowany, typowany szkielet, lecz nie jest podłączona do `GameState`, resolvera, budynków, UI ani zapisu kampanii. Kontrakty: ARD-0081, ARD-0082 i ARD-0092/D8.
- `[DOCELOWE]` Relacje, konflikty, prawa i sabotaż nie mają kompletnego pionu runtime.
- `[DOCELOWE]` Selektor języka pozostaje ukryty do czasu pełnej lokalizacji widocznego i utrwalanego tekstu.
- `[OGRANICZENIE DOWODU]` Automatyczny replay potwierdza wskazane gardła i fizyczny collider Nurka, lecz nie pełną osiągalność, jakość wszystkich tras, widoczną kopertę avatara ani subiektywne odczucie sterowania. Szczegóły są w lokalnych kontekstach Mapy i Nurka.

## Stan procesu zmian

- `[AKTYWNE]` Autor wykonuje lokalne testy i fast-check; GitHub sprawdza PR, a pełny `integration-green` działa na merge group przed squash do `main`. Builder publikuje exact SHA i przesuwa `builds/current` tylko po buildzie oraz smoke `PASS`. Procedura: `AGENTS.md`, `README.md`, ARD-0113.

## Ważne pułapki

- Pole, hook, klasa, test albo szkielet nie czyni mechaniki aktywną. Kontrakt: ARD-0027.
- Test i snapshot potwierdzają tylko własny kontrakt; nie dowodzą wszystkich tras, kombinacji trudności ani jakości prezentacji. Kontrakty: ARD-0028 i ARD-0079.
- Root nie jest drugim authority Bazy, Mapy ani Nurka. Prywatne dane, assety, sockety, pochodne i lokalne wyniki należy czytać w dokumentach właściwego warsztatu.
- Zapis obcej rewizji albo mapy o starszym podpisie jest odrzucany; nie wolno interpretować go według bieżącego schematu.

## Ostatnia weryfikacja

- `[OSTATNIA WERYFIKACJA]` 2026-08-29, Godot 4.7.1, kandydat na bazie `015c9e0f199076251fa54fe0ab2f44c9b4b1a5d4`: celowane testy Bazy, runner isolation i lokalny fast-check zakończyły się `33/33 PASS`, w tym boundary, smoke i persistence przypisań.
  Zakres był celowany dla relokacji Bazy; pełna regresja i certyfikacja merge group pozostają zadaniem kolejki.
