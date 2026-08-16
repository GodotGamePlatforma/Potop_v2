# Decyzje warsztatu mapy podwodnej

Rola tego pliku: trwałe, lokalne rozstrzygnięcia dotyczące kompozycji, produkcji i akceptacji grafiki mapy. Nie ustanawia zasad gry, topologii, właścicieli stanu, persistence, migracji ani bieżącego statusu implementacji. Konflikt rozstrzygają aktywne ARD w `../../.ai/DECISIONS.md`, dokument będący globalnym właścicielem szczegółu oraz faktyczny runtime.

Każdy nowy wpis otrzymuje stabilny identyfikator `MAP-ARD-XXXX`, status, datę, klauzule i relacje. Zmiana sensu wymaga nowego wpisu i symetrycznego zastąpienia; wpisów historycznych nie usuwa się.

Proces Codexa, CWD, allowlista i kolejność pracy należą wyłącznie do `../AGENTS.md`; komendy i onboarding do `../README.md`; bieżący stan assetów do `PROJECT_CONTEXT.md`. Ten rejestr nie powtarza tych treści.

## Indeks aktywnych decyzji

| ID | Właściciel szczegółu | Najważniejszy inwariant |
|---|---|---|
| MAP-ARD-0001 | szeroka kompozycja | Jeden zatwierdzony master poprzedza finalny detal i podział na pochodne. |
| MAP-ARD-0002 | granica grafika-fizyka | Warstwa wizualna nie ustanawia topologii, kolizji ani zapisu. |
| MAP-ARD-0003 | akceptacja | Integralność techniczna i odbiór artystyczny są niezależnymi bramkami. |
| MAP-ARD-0004 | provenance | Źródła i operacje pozwalają prześledzić zaakceptowaną rewizję; pochodne nie są ręcznie poprawiane. |

---

## MAP-ARD-0001 - Jedna kompozycja master poprzedza podział panoramy

- Status / aktywny zakres: Obowiązuje; D1-D4
- Zatwierdzenie: 2026-08-16
- Relacje: Zastępuje: brak | Zastąpiona przez: brak
- D1. Każde szerokie tło regionu ma jedną zatwierdzoną kompozycję master obejmującą cały docelowy pas i jego relację z kanonicznym terenem.
- D2. Master blokuje co najmniej horyzont, trzy plany głębi, skalę form, rytm gęstości, miejsca oddechu, strefę czytelności oraz przebieg kluczowych motywów przed produkcją finalnego detalu.
- D3. ArtCells, okna inpaint/outpaint i chunki runtime są pochodnymi jednego mastera. Nie wolno przyjąć zestawu niezależnie wygenerowanych finalnych obrazów jako źródła panoramy.
- D4. Po każdej większej edycji ocenia się ponownie cały złożony pas. Lokalnie poprawny kadr nie może zostać przyjęty, jeżeli psuje kompozycję globalną.
- Powód i skutek: wspólna, niskoczęstotliwościowa kompozycja usuwa szwy perspektywy, skali i rytmu, których nie wykrywa identyczny overlap pikselowy.

## MAP-ARD-0002 - Grafika mapy jest warstwowa i nie ustanawia fizyki

- Status / aktywny zakres: Obowiązuje; D1-D4
- Zatwierdzenie: 2026-08-16
- Relacje: Zastępuje: brak | Zastąpiona przez: brak
- D1. Dalekie sylwety i panoramy, średni plan landmarków, skóry terenu/prefaby oraz atmosfera runtime są osobnymi warstwami z odrębną odpowiedzialnością.
- D2. Raster źródłowy może sugerować głębię i materiał, ale nie definiuje przechodniości, kolizji, stable ID, rozmieszczenia gameplayowego ani zapisu.
- D3. Globalna mgła, caustics, refrakcja, ruch wody, cząstki i światło gameplayowe pozostają w Godot. Nie wypieka się ich do neutralnych płyt, które mają działać w różnych profilach jakości i oświetleniu.
- D4. Płyta albo prefab wizualny nie zawiera nurka, HUD-u, celu, interakcji ani powierzchni sugerującej inną topologię niż kanoniczna scena.
- Powód i skutek: warstwowość pozwala poprawiać grafikę bez rozjazdu z fizyką, zapisem i wspólną atmosferą świata.

## MAP-ARD-0003 - Integralność techniczna i odbiór artystyczny są dwiema bramkami

- Status / aktywny zakres: Obowiązuje; D1-D4
- Zatwierdzenie: 2026-08-16
- Relacje: Zastępuje: brak | Zastąpiona przez: brak
- D1. Bramka techniczna obejmuje w szczególności rozmiary, hashe, pochodne, brak szczelin, streaming, budżety i niezmienność gameplayu.
- D2. Bramka artystyczna obejmuje całą panoramę, perspektywę, skalę, paletę, rytm, powtórzenia, hierarchię planów, oddech kompozycyjny i czytelność w reprezentatywnym runtime.
- D3. Snapshot, metryka wkładu, zgodny overlap albo zielony test nie zastępują jawnej kontroli wzrokowej. Akceptacja wymaga obu bramek.
- D4. Jawne odrzucenie przez użytkownika cofa status wizualnego baseline'u, ale nie zmienia historycznego wyniku wąskich testów technicznych.
- Powód i skutek: pipeline nie może ponownie uznać za gotowy obrazu, który jest bezszwowy w bajtach, lecz niespójny jako świat.

## MAP-ARD-0004 - Źródła grafiki zachowują reprodukowalne provenance

- Status / aktywny zakres: Obowiązuje; D1-D4
- Zatwierdzenie: 2026-08-16
- Relacje: Zastępuje: brak | Zastąpiona przez: brak
- D1. Wersjonowany zestaw źródłowy zachowuje master, layout guide, maski głębi/zasłonięcia, paletę oraz manifest operacji prowadzących do zaakceptowanej rewizji.
- D2. Manifest zapisuje użyte narzędzie i wersję/model, parametry lub seed, prompty, identyfikatory i SHA-256 referencji, geometrię okna, kolejność operacji oraz SHA-256 wyniku, o ile dane narzędzie je udostępnia.
- D3. Brak dostępnego parametru jest zapisywany jawnie jako niedostępny; nie wolno deklarować reprodukowalności na podstawie samego finalnego PNG.
- D4. Pochodne ArtCells i chunki są odtwarzane deterministycznie ze źródeł i manifestu. Nie otrzymują ręcznych zmian, które nie wróciły do mastera.
- Powód i skutek: kolejny Codex może kontynuować ten sam obraz i zdiagnozować zmianę bez zgadywania promptów, referencji i historii ręcznych poprawek.
