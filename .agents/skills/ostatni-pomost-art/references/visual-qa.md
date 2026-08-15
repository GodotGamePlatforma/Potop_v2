# Wizualne QA

Uznaj zmianę za gotową dopiero po przejściu trzech bramek: semantycznej, technicznej i artystycznej. Najpierw znajdź istniejący harness, snapshot lub scenę podglądu dla zmienianego zakresu; nie twórz równoległej metody dowodowej bez potrzeby.

## Zamroź manifest akceptacji

Przed edycją zapisz w briefie wiersze dowodu. Każdy wiersz zawiera:

- scenę, kadr albo klip;
- stan gry i wyzwalacz;
- kamerę, rozdzielczość i moment osi prezentacji;
- profil `low/medium/high` oraz stan `reduced_motion`, albo uzasadnione `N/D`, gdy aktywny konsument nie ma takiego wariantu;
- kryterium funkcjonalne i artystyczne;
- metrykę techniczną oraz źródło progu, jeśli projekt taki próg posiada;
- wynik `PASS`, `FAIL`, `NIEZWERYFIKOWANE` albo `N/D` z krótkim uzasadnieniem.

Nie wymyślaj liczbowego budżetu tylko po to, aby wypełnić tabelę. Brak obowiązującego progu nie blokuje eksperymentu, ale blokuje deklarację pełnego zaliczenia wydajności.

Klasyfikuj ustalenia jako:

- **blocker** — błędny aktywny asset, utrata informacji, zmiana mechaniki, błąd importu/shadera, brak wymaganego profilu lub niebezpieczne migotanie;
- **major** — niespójny kierunek, słaba sylwetka, widoczny artefakt, zły rytm/przejście albo istotna regresja kosztu;
- **polish** — detal, który nie podważa celu, czytelności ani kontraktu.

Nie kończ z blockerem. Rozwiąż wszystkie majory wprowadzone zmianą i te, które dotyczą głównego celu użytkownika; pozostały polish jawnie wypisz.

## 1. Bramka semantyczna

- Czy rezultat realizuje cel użytkownika i obowiązujący produkt?
- Czy nie zmieniono po cichu mechaniki, balansu, narracji, zapisu ani właściciela stanu?
- Czy efekt komunikuje właściwą informację i nie sugeruje nieistniejącej reguły?
- Czy wariant z `reduced_motion` zachowuje informację bez zbędnego ruchu?
- Czy postać, portret i ilustracja zachowują ustaloną tożsamość, a UI nie opiera znaczenia wyłącznie na kolorze?
- Czy nowe źródła mają znane pochodzenie i prawo użycia oraz nie zawierają znaków wodnych ani skopiowanej, rozpoznawalnej pracy?

## 2. Bramka techniczna

- Czy aktywna scena rzeczywiście wskazuje nowy zasób?
- Czy import nie zgłasza braków, a shader i materiały kompilują się bez błędów?
- Czy pivot, skala, region, filtr i alfa są poprawne?
- Czy przejścia animacji nie przeskakują, nie resetują się przypadkowo i nie gubią kierunku?
- Czy efekt działa przy pauzie, zmianie kamery, granicy mapy i skrajnym zagęszczeniu?
- Czy nie powstała zależność logiki domenowej od grafiki?
- Czy wynik i koszt sprawdzono dla wszystkich istniejących profili `low/medium/high` w najcięższym reprezentatywnym kadrze, używając dostępnego pomiaru lub harnessu?
- Czy profil zastosowano przed budową ciężkich zasobów GPU i czy koszt jest monotoniczny bez przejściowej alokacji high na niższym ustawieniu?
- Czy porównano rozmiar rastrów po dekodowaniu, overdraw, passy pełnoekranowe, emitery oraz dostępne CPU/GPU/VRAM przed i po?
- Dla mapy: czy sygnatura gameplayowa pozostała identyczna po zmianie prezentacyjnej i czy współdzielony asset sprawdzono we wszystkich regionach?

## 3. Bramka artystyczna

Porównaj przed/po w identycznych warunkach: ten sam stan gry, kamera, rozdzielczość i moment animacji. Obejrzyj kadr typowy, ciemny/jasny, spokojny i obciążony efektami, na pełnym ekranie oraz w docelowym powiększeniu.

Oceń:

- hierarchię pierwszego, drugiego i trzeciego planu;
- sylwetkę i odseparowanie postaci od tła;
- spójność palety, światła, materiału i głębi;
- rytm, ciężar, pętlę i przejścia animacji;
- czytelność informacji podczas ruchu;
- migotanie, halo, banding, bleeding, tearing, szum i nagłe skoki;
- widoczność detalu w realnej skali.

Wykonaj także szybkie kontrole pomocnicze: obraz w skali szarości, małą miniaturę oraz powiększenie krawędzi. Dla sygnałów UI i gameplayu sprawdź rozróżnialność bez samej barwy. Dla światła, VFX i postprocessu obejrzyj jasny i ciemny kadr pod kątem black crush, clippingu, gwałtownych zmian luminancji i częstego błysku. Nie deklaruj bezpieczeństwa obrazu na podstawie jednego nieruchomego kadru.

## Macierz według zakresu

### Postać i animacja

Sprawdź inwentarz klipów, idle, start, stały ruch, zmianę kierunku, sprint, zatrzymanie, granice ekranu i każde przejście między stanami. Obejrzyj kilka pełnych pętli. Zweryfikuj kluczowe pozy, timing/spacing, łuki, overlap, stałość pivota lub root, brak ślizgu i zgodność tempa z ruchem w świecie. Dla większej zmiany zachowaj osobny dowód blockingu i finalnego polishu.

### Mapa i biom

Sprawdź punkt wejścia, główną trasę, charakterystyczny landmark, beat kulminacyjny, krawędzie biomu, miejsca kolizji, najciemniejszy obszar i kadr z największą liczbą dekoracji. Porównaj gęstość oraz przejścia z regionami sąsiednimi. Postać, zagrożenie i element interaktywny muszą pozostać odróżnialne.

### Model i animacja 3D

Sprawdź model z kamery runtime, na turntable i w skrajnych pozach. Obejrzyj sylwetkę, wireframe, shading normalnych, UV i materiały, wszystkie warianty stanu, LOD oraz przejścia widoczności. Porównaj inwentarz aktywnego eksportu z kandydatem. Dla rigu sprawdź bind pose, pętle, root motion, przejścia klipów i deformacje barków, łokci, dłoni, bioder oraz kolan; szukaj zapadania siatki, ślizgania stóp, przeskoku korzenia i zmiany skali.

### VFX i postprocess

Sprawdź brak efektu, typową i maksymalną intensywność, nakładanie emiterów, zimny start, pauzę/wznowienie, zmianę rozdzielczości, każdy profil i `reduced_motion`. Obejrzyj pełny przebieg wejście–szczyt–wybrzmienie oraz ekspozycję w jasnym i ciemnym kadrze. Efekt nie może stale konkurować z głównym celem, maskować UI ani tworzyć szybkich pełnoekranowych błysków.

### UI, portret i ilustracja

Sprawdź docelowe kadrowanie, mały i duży rozmiar, najdłuższe teksty, skalowanie oraz pełne stany `normal/hover/focus/pressed/selected/disabled/error`. Przejdź nawigację klawiaturą i obsługiwane proporcje. Dla portretu porównaj planszę wszystkich przedstawień postaci oraz wszystkich portretów w rzeczywistym konsumencie; sprawdź niezmienniki twarzy, wieku, ubioru, światła i palety. Nie opieraj znaczenia wyłącznie na kolorze.

## Dowód i raport

Zachowaj odtwarzalny pakiet dowodowy wszędzie, gdzie pozwala na to istniejący harness:

- identyczne kadry przed/po dla zmiany statycznej;
- klip A/B albo sekwencję klatek dla animacji, VFX, światła i postprocessu;
- manifest ustawień dowodu i ścieżki wyników;
- komendę istniejącego harnessu uruchomioną zgodnie z głównym `AGENTS.md`;
- osobno wynik techniczny, pomiar wydajności i ręczną ocenę artystyczną;
- listę obejrzanych stanów, rezultat wszystkich wierszy akceptacji i znane ograniczenia.

Dla istotnej zmiany wykonaj niezależny przegląd lub drugi, odseparowany pass krytyczny na surowych dowodach. Brak możliwości obejrzenia aktywnego rezultatu albo ruchu oznacza `NIEZWERYFIKOWANE`, nie pełne zaliczenie QA; wskaż dokładny krok potrzebny do domknięcia. Gotowość wymaga braku blockerów, rozwiązania właściwych majorów i jawnego ręcznego sign-offu obrazu w runtime.
