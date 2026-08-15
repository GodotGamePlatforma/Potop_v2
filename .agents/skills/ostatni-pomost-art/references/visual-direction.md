# Kierunek wizualny

Używaj tego dokumentu do budowy briefu i oceny jakości artystycznej. Nie traktuj go jako zamkniętego style guide'u ani źródła nowych zasad produktu.

## Zacznij od funkcji obrazu

Każdy element powinien wspierać przynajmniej jeden cel:

- orientację i czytelność rozgrywki;
- atmosferę samotnej podwodnej eksploracji;
- rozpoznawalność miejsca, postaci lub stanu;
- informację zwrotną o akcji;
- emocjonalny rytm sceny.

Jeżeli element nie realizuje żadnego celu, uprość go albo usuń.

## Buduj hierarchię

1. Zapewnij czytelną sylwetkę i główny punkt zainteresowania.
2. Rozdziel plany wartością tonalną, nasyceniem, ostrością i ruchem.
3. Użyj światła i koloru do prowadzenia wzroku.
4. Dodaj materiał i mikrodetal dopiero po sprawdzeniu obrazu w docelowym powiększeniu.
5. Ogranicz jednoczesne akcenty. Najsilniejszy kontrast należy do informacji najważniejszej.

## Utrzymuj spójność

- Wyprowadź nowe kolory z palety aktywnej sceny, chyba że kontrast ma znaczenie fabularne lub funkcjonalne.
- Utrzymuj wspólną logikę kierunku światła, głębokości i zamglenia.
- Powtarzaj język kształtów świadomie: obłe formy mogą oznaczać organiczność, ostre — zagrożenie lub konstrukcję.
- Zachowuj skalę tekstur i gęstość detalu odpowiednią dla kamery.
- W animacji utrzymuj masę, bezwładność i opór wody; unikaj równomiernego, mechanicznego tempa bez intencji.

## Projektuj od ogółu do wariantu

Dla nowego kierunku albo kosztownego redesignu przygotuj najpierw małą planszę referencyjną z aktywnych assetów projektu oraz nazwanych cech, które mają zostać zachowane lub zmienione. Zewnętrzne referencje traktuj jako analizę światła, materiału, kompozycji albo rytmu — nie jako źródło do kopiowania rozpoznawalnej pracy. Potwierdź prawa i pochodzenie każdego importowanego fontu, tekstury, modelu lub obrazu.

Przed finalnym wykonaniem porównaj 2–3 tanie warianty: miniatury kompozycji, color keys, blockouty, sylwetki albo krótkie blockingi animacji. Oceń je w docelowym kadrze według tej samej listy: funkcja, hierarchia, spójność z projektem, koszt integracji i ryzyko czytelności. Drobna korekta pojedynczego artefaktu nie wymaga sztucznego mnożenia wariantów.

## Kotwice projektu

Przed projektowaniem obejrzyj aktywną scenę i sąsiednie, zaakceptowane elementy. Dla zadań podwodnych sprawdź w szczególności:

- aktywną scenę nurka i jej `SpriteFrames`;
- materiały, shadery i profile w `assets/diving/world/` oraz `data/diving_visuals/`;
- aktualne efekty środowiska, oświetlenie i kamerę;
- portrety lub ilustracje, jeśli nowy obraz pojawia się obok nich.

Nazwy plików typu `final`, `v2` lub `new` nie dowodzą, że zasób jest aktywną kotwicą.

## Rozwiń język właściwy dla zakresu

### Mapa i biom

Zdefiniuj rozpoznawalność regionu przez co najmniej: duże sylwetki, zakres wartości tonalnych, rodzinę materiałów, jeden charakterystyczny landmark, rytm dekoracji oraz ruch atmosfery. Sprawdź wejście, główną trasę, punkt kulminacyjny i przejścia do sąsiadów. Nie używaj koloru, roślinności ani efektu do sugerowania toksyczności, interakcji lub zagrożenia, którego nie ma w domenie.

### Postać i animacja

Zapisz inwentarz wymaganych klipów i przejść. Dla każdego ustal kluczowe pozy, linię akcji, czas, spacing, łuki, overlap, stałość pivota lub root, warunek pętli i relację do rzeczywistego ruchu w świecie. Dla większej zmiany przejdź przez `blocking -> timing/spacing -> polish`; oceń kilka pełnych pętli, zmianę kierunku i przejścia na tle docelowej sceny. Nie używaj animacji do ukrytej zmiany prędkości, zasięgu albo kolizji.

### Portret i ilustracja

Ustal niezmienniki tożsamości: proporcje twarzy i sylwetki, wiek, cechy charakterystyczne, ubiór, paletę, kierunek światła i sposób kadrowania. Porównaj nowy obraz z planszą wszystkich istniejących przedstawień tej postaci oraz z sąsiednimi portretami w rzeczywistym UI. Zachowaj twarz i ważne rekwizyty w bezpiecznym kadrze, unikaj tekstu wypalonego w obrazie i odrzuć drift tożsamości między wariantami.

### VFX, światło i postprocess

Rozdziel sygnał główny, odpowiedź wtórną i atmosferę. Dla zdarzenia ustal wejście, szczyt, wybrzmienie i stan po efekcie; dla warstwy ciągłej — częstotliwość, skalę oraz momenty rzeczywistego zera. Kontroluj ekspozycję, black crush, clipping, banding, częste błyski i konkurencję z HUD-em. Grading i bloom nie mogą zastępować czytelnej wartości tonalnej u źródła.

### UI polish

Wyprowadź z aktywnego theme lokalne tokeny typografii, kolorów, odstępów, promieni i ikon zamiast tworzyć drugi design system. Sprawdź pełną macierz `normal/hover/focus/pressed/selected/disabled/error`, najdłuższe teksty, skalowanie i wszystkie obsługiwane proporcje. Hierarchia musi działać w skali szarości i bez znaczenia opartego wyłącznie na kolorze; poprawa wizualna nie może zmieniać zachowania, fokusu ani właściciela stanu kontrolki.

## Szablon briefu

- **Cel:** co gracz ma zauważyć lub poczuć?
- **Kadr:** jaka kamera, skala i tło są reprezentatywne?
- **Hierarchia:** co jest planem 1/2/3?
- **Ruch:** co porusza się, z jakim rytmem i dlaczego?
- **Materiał i światło:** jak reagują powierzchnie i głębia?
- **Ograniczenia:** czytelność, `reduced_motion`, wydajność, istniejące kontrakty.
- **Akceptacja:** dla każdego dowodu podaj scenę/kadr, stan, profil, rozdzielczość, kryterium wizualne lub techniczne i źródło obowiązującego budżetu; nie używaj samego „wygląda lepiej”.

## Sygnały odrzucenia

Odrzuć wariant, jeżeli występuje:

- przypadkowy detal bez czytelnej dużej formy;
- paleta odklejona od sąsiedniej sceny;
- brak separacji postaci od tła;
- równy kontrast i ruch we wszystkich warstwach;
- efektowność okupiona utratą informacji;
- niezamierzony plastikowy materiał, halo, szum, banding lub migotanie;
- animacja nieprzekazująca ciężaru, kierunku albo fazy działania;
- drift twarzy, stroju, proporcji albo kierunku światła między przedstawieniami tej samej postaci;
- generyczne artefakty generatywne, znaki wodne lub detal sugerujący cudzą, rozpoznawalną pracę;
- interfejs czytelny tylko dzięki kolorowi albo nieposiadający kompletnego stanu fokusu i blokady.
