# Technical art i integracja z Godot

Używaj tego dokumentu przy zmianach aktywów, animacji, scen, importu, shaderów, materiałów, oświetlenia i VFX.

## Spis treści

- [Zidentyfikuj aktywny łańcuch](#zidentyfikuj-aktywny-łańcuch)
- [Raster 2D, atlas i ilustracja](#raster-2d-atlas-i-ilustracja)
- [Nurek](#nurek)
- [Mapa i biom](#mapa-i-biom)
- [Model, budynek i animacja 3D](#model-budynek-i-animacja-3d)
- [VFX, shader i światło](#vfx-shader-i-światło)
- [Profile jakości i inicjalizacja](#profile-jakości-i-inicjalizacja)
- [Zasady aktywów](#zasady-aktywów)
- [Granica prezentacji](#granica-prezentacji)
- [Integracja minimalna, ale kompletna](#integracja-minimalna-ale-kompletna)
- [Wydajność](#wydajność)

## Zidentyfikuj aktywny łańcuch

Prześledź:

`plik źródłowy -> import Godot -> Resource -> scena -> skrypt lub dane -> stan runtime -> kadr wynikowy`

Sprawdź wszystkie ogniwa przed edycją. W projekcie mogą istnieć warianty niepodpięte do gry. Zanotuj myląco podobne, nieaktywne warianty i nie migruj na nie bez potwierdzenia konsumenta.

Przed zmianą zapisz manifest aktywnego łańcucha:

- edytowalne źródło albo jawny brak źródła;
- eksport runtime i jego UID lub referencję;
- istotne ustawienia importu;
- `Resource`, node sceny i konsument kodu lub danych;
- stan wyzwalający oraz dowód z uruchomionego runtime;
- podobne, lecz nieaktywne warianty.

Każdy wpis potwierdź z bieżącego repozytorium. Nie utrwalaj zmiennych ścieżek lub wartości tego manifestu w skillu.

### Raster 2D, atlas i ilustracja

Ustal pochodzenie źródła, rozmiar płótna, przeznaczenie w kamerze, siatkę atlasu i kolejność klatek lub regionów. Sprawdź:

- prostą albo premultiplikowaną alfę, przezroczysty padding i obwód bez obcego koloru;
- pivot, marginesy, regiony oraz stałość płótna między wariantami;
- `filter`, mipmaps, repeat, kompresję i zgodność sRGB dla koloru albo przestrzeni liniowej dla tekstur danych;
- bleeding atlasu, ostrość po skali runtime i artefakty po kompresji;
- rozmiar po dekodowaniu, liczbę kopii i sposób streamingu lub cullingu dużych warstw;
- dla animacji: czas klatek, pętlę, flip, przejścia i zgodność tempa obrazu z ruchem świata.

Wynik generatora obrazu przeprowadź przez ten sam pipeline co ręcznie tworzony raster. Usuń znaki wodne, błędną anatomię, niespójne detale i szwy; sprawdź tileability, jeśli tekstura ma się powtarzać. Nie promuj pliku tylko dlatego, że wygląda dobrze poza Godot.

### Nurek

Punktem wejścia jest aktywna scena postaci. Ustal:

- jaki `SpriteFrames` jest przypisany;
- które zestawy klatek i prędkości obsługują idle, pływanie oraz sprint;
- gdzie ustawione są scale, offset, flip i pivot;
- który skrypt wybiera animację;
- czy collider pozostaje niezależny od grafiki.

Zmiana liczby klatek lub nazw animacji wymaga aktualizacji wszystkich konsumentów. Oceniaj pętlę na tle docelowego biomu, nie tylko w podglądzie zasobu.

### Mapa i biom

Rozdziel duże masy terenu i nawigację, materiał powierzchni, obiekty środowiskowe, światło/mgłę/tło, efekty lokalne oraz dane profilu wizualnego biomu. Nie wypalaj informacji domenowej w bitmapie, jeśli runtime potrzebuje jej osobno. Zachowaj dane mapy i kolizji niezależnie od dekoracji.

Przed zmianą ustal, czy asset należy do jednego regionu, czy jest współdzielony przez całą mapę. Dla „biomu nr N” potwierdź nazwę w kanonicznej kolejności produktu i w produkcyjnej scenie, nie przez pozycję w tablicy runtime. Po zmianie wyłącznie prezentacyjnej potwierdź, że istniejąca sygnatura gameplayowa mapy pozostała niezmieniona.

### Model, budynek i animacja 3D

Zacznij od instancji aktywnej w scenie i prześledź ją do importowanego GLTF/GLB oraz edytowalnego źródła. Przed eksportem ustal kontrakt nazw nodów, meshy i slotów materiałów, skalę i jednostki, osie, origin, transformy oraz sposób zachowania kolizji.

Sprawdź:

- sylwetkę i czytelność modelu z kamery runtime;
- topologię, triangulację, UV, spójną gęstość texeli, szwy i nakładanie;
- normalne, tangenty, smoothing i artefakty po imporcie;
- materiały PBR, przestrzeń kolorów tekstur, kanały ORM, emisję i przezroczystość;
- liczbę surfaces, draw calls, rozmiary tekstur oraz istniejący LOD albo budżet widoczności;
- hierarchię kości, bind pose, wagi, maksymalne deformacje i retargeting, jeśli model ma rig;
- nazwy klipów, zakresy, root motion, pętle oraz przejścia animacji szkieletowej.

Nie zastępuj collision mesh wyglądem renderowanym ani nie zmieniaj stabilnego kontraktu nazw bez prześledzenia wszystkich konsumentów. Po eksporcie sprawdź import w Godot, aktywne materiały, transformy, warianty stanu i fallback.

Znajdź istniejący preset lub skrypt eksportu i jego zależności. Eksportuj najpierw do kandydata poza aktywnym plikiem, porównaj inwentarz sceny i dopiero po zaliczeniu kontroli promuj wynik. Porównanie obejmuje jednostki i osie, transformy i modyfikatory, hierarchię i nazwy, surfaces i sloty materiałów, skeleton, bind pose, skinning, klipy oraz ustawienia importu Godot. Nie nadpisuj dobrego eksportu nieodtwarzalnym ręcznym wariantem.

### VFX, shader i światło

Ustal przestrzeń efektu, kolejność rysowania, blending, źródło czasu oraz zachowanie przy pauzie. Dobierz:

- shader do ciągłych transformacji pikseli lub materiału;
- particles do wielu krótkotrwałych elementów;
- animację klatkową do ręcznie kontrolowanej sylwetki;
- proceduralny renderer do skalowalnej geometrii z danych;
- bitmapę do unikalnego, malarskiego detalu.

Zapisz mapę passów: backend i rendering method, Canvas lub spatial, viewport/warstwę/z-order, depth/cull/blend, odczyt screen/depth/normal texture, kolejność kompozycji, właściciela uniformów i czasu oraz fallback dla niewspieranego wariantu. Sprawdź stan zerowy, typowy i maksymalny, zimny start, pauzę/wznowienie, snapshot oraz zmianę profilu w runtime.

Każdą warstwę ruchu sklasyfikuj jako informację konieczną, feedback akcji albo dekorację. Dla każdej określ wariant normalny i `reduced_motion`. Zachowaj ruch niezbędny do sterowania i stanu postaci; ograniczaj ruch dekoracyjny, wtórny i pełnoekranowy. Ograniczenie ruchu obejmuje także gwałtowne pulsowanie i błyski, nie tylko przesunięcie obrazu.

Kontroluj przestrzeń barw, HDR/SDR, tonemapping, ekspozycję, bloom i precyzję gradientów. Światło ma jednego potwierdzonego właściciela; nie dodawaj lokalnego fill light ani drugiego postprocessu, zanim nie prześledzisz istniejącego modelu i kolejności kompozycji.

## Profile jakości i inicjalizacja

Odnajdź pełną drogę ustawienia `low/medium/high` od konfiguracji użytkownika do budowy zasobów GPU. Zastosuj profil przed alokacją ciężkich viewportów, tekstur, geometrii i pul cząstek, aby wariant low lub medium nie tworzył przejściowo zasobów high. Koszt powinien być monotoniczny `low <= medium <= high`, a informacja, sylwetka i intencja artystyczna równoważne na każdym profilu.

Sprawdź start sceny z zapisanym profilem, zmianę profilu, ponowne wejście do sceny oraz `reduced_motion` w połączeniu z każdym profilem. Profil jakości i ograniczenie ruchu nie mogą wpływać na fizykę, seed, kolejność domenową ani wynik kampanii.

## Zasady aktywów

- Zachowaj edytowalne źródło, jeśli istnieje, oraz eksport runtime w przewidywalnym miejscu.
- Używaj nazw opisujących domenę i wariant, nie oceny typu `final_final`.
- Zachowaj przezroczyste marginesy, pivot i rozmiar płótna pomiędzy klatkami.
- Sprawdź filter, mipmaps, repeat, kompresję, przestrzeń kolorów i artefakty alfa.
- Nie skaluj rastra ponad jakość widoczną w docelowej kamerze.
- Przy zmianie atlasu sprawdź regiony, separację i bleeding.
- Nie usuwaj starszego aktywnego źródła przed potwierdzeniem migracji wszystkich referencji.

## Granica prezentacji

Grafika może odczytywać stan domenowy i go prezentować. Nie może:

- obliczać wyniku mechaniki na podstawie koloru, klatki lub widoczności;
- przechowywać drugiej kopii stanu rozgrywki;
- zmieniać kolizji lub zasięgu wyłącznie przez zmianę sprite'a;
- modyfikować trwałego zapisu jako efekt animacji;
- uzależniać logiki od częstotliwości renderowania.

## Integracja minimalna, ale kompletna

1. Dodaj lub zmień źródło.
2. Sprawdź import i wygenerowany `.import` przez Godot, jeśli to konieczne.
3. Podepnij Resource i scenę.
4. Zaktualizuj sterowanie prezentacją.
5. Uruchom reprezentatywny stan.
6. Sprawdź brak brakujących referencji i ostrzeżeń shaderów.
7. Dopiero potem usuń osierocony wariant, jeśli zakres to obejmuje i usunięcie jest bezpieczne.

## Wydajność

Oceniaj koszt w docelowym kadrze, przy maksymalnej przewidywanej liczbie emiterów i warstw. Najpierw redukuj pracę niewidoczną, redundantną i pełnoekranową.

Porównaj przed/po co najmniej:

- wymiary, format, mipmaps, kompresję, liczbę warstw i przybliżony rozmiar tekstur po dekodowaniu;
- współdzielenie, duplikację, streaming i rezydencję dużych zasobów;
- liczbę pełnoekranowych passów, duże przezroczystości i overdraw;
- emitery, maksymalną liczbę cząstek, draw calls, prymitywy i węzły tworzone dynamicznie;
- alokacje na klatkę oraz dostępne percentyle CPU/GPU i VRAM z istniejącego harnessu.

Szacunek rastra zacznij od `szerokość × wysokość × bajty na piksel × warstwy` i dolicz mipy oraz kopie, lecz nie przedstawiaj go jako dokładnej rezydencji GPU bez pomiaru. Sprawdź każdy profil `low/medium/high` oraz najcięższy reprezentatywny kadr. Użyj obowiązującego budżetu i istniejącego harnessu projektu; nie kopiuj jego zmiennych progów do skilla. Gdy zatwierdzonego budżetu lub pomiaru brakuje, podaj liczby i oznacz bramkę wydajności jako niedomkniętą zamiast ogłaszać pełne QA.
