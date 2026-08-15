---
name: ostatni-pomost-art
description: "Profesjonalnie twórz, poprawiaj, integruj i oceniaj grafikę, animację oraz efekty w projekcie Ostatni Pomost. Używaj, gdy głównym rezultatem ma być jakość prezentacji: mapy i biomy, środowisko 2D/3D, sprite'y i postacie, modele i rigging, animacje, portrety, intro, UI polish, materiały, shadery, światło, cząsteczki, VFX lub postprocess. Nie używaj jako głównego workflow dla topologii, kolizji, gameplayu, persistence ani zachowania UI."
---

# Ostatni Pomost Art

Prowadź zadanie jak senior art director, animator i technical artist Godot: ustal aktywny łańcuch źródło–import–zasób–scena–runtime, zaprojektuj spójny rezultat, wykonaj najmniejszą kompletną integrację i oceń ją na obrazie, w ruchu oraz w realnym kadrze gry. Nie uznawaj jakości na podstawie samego promptu, izolowanego assetu ani poprawnej kompilacji.

## Ustal właścicieli źródeł

Nie traktuj dokumentów jak jednej liniowej listy pierwszeństwa. Każde źródło odpowiada na inne pytanie:

- główny `AGENTS.md` — jaki proces, bramka rozbieżności i routing obowiązują;
- `.ai/PROJECT_CONTEXT.md` — jaki stan runtime, luka i wynik weryfikacji są potwierdzone;
- `docs/OgolnyZarys.txt` — jaki rezultat i skutek widzi gracz;
- aktywne ARD w `.ai/DECISIONS.md` — jakie trwałe rozstrzygnięcia i inwarianty obowiązują;
- `docs/Ostatni_Pomost_architektura_Godot.txt` — jak produkt mapuje się na systemy, dane, zasoby i testy;
- potwierdzony runtime — co rzeczywiście działa i który zasób jest aktywny;
- ten skill — jak profesjonalnie wykonać i ocenić pracę artystyczną.

Nie ustanawiaj tutaj mechaniki, balansu, narracji, właściciela stanu ani semantyki zapisu. Jeśli źródła są sprzeczne albo runtime realizuje element oznaczony w dokumentacji inaczej, nie wybieraj samowolnie zwycięzcy i nie zmieniaj statusu. Zastosuj bramkę rozbieżności z głównego `AGENTS.md`.

W zadaniu mieszanym prowadź tym skillem część prezentacyjną. Każdą potrzebną zmianę kolizji, topologii, zachowania, danych domenowych albo zapisu wydziel jako osobny zakres i przepuść przez zwykły proces projektu. Jeśli użytkownik prosi wyłącznie o ocenę, zakończ na dowodzie i priorytetyzowanych ustaleniach bez edycji.

## Dobierz trasę

| Zakres | Najpierw ustal | Typowe miejsca |
|---|---|---|
| Nurek lub inna postać | aktywny `SpriteFrames`, klipy, skala, pivot, kolizja, stan sterujący animacją | `assets/diving/diver/`, scena i kontroler postaci |
| Baza, budynek lub model 3D | aktywny GLTF/mesh, źródło authoringowe, rig, materiały, import, instancje i kontrakt nazw | `assets/base_3d/`, `assets/base/`, scena i renderer 3D |
| Mapa, biom, tło | warstwy świata, materiał terenu, obiekty, światło, kamera, profil wizualny biomu | `assets/diving/world/`, `data/diving_visuals/`, sceny świata |
| Efekt, shader, światło | emiter, przestrzeń współrzędnych, kolejność rysowania, budżet, `reduced_motion` | shadery, materiały, particles, kontrolery środowiska |
| Portret lub ilustracja | konsument UI, kadrowanie, rozdzielczość i warianty stanu | `assets/ui/portraits/`, `assets/intro/`, sceny UI |
| UI polish | hierarchię informacji, temat, stany interakcji, skalowanie i czytelność | sceny `Control`, themes, ikony i fonty |

Przed edycją prześledź referencje od aktywnej sceny do źródła. Nie poprawiaj osieroconego wariantu tylko dlatego, że ma obiecującą nazwę. W raporcie wskaż podobnie nazwane, nieaktywne warianty, jeśli mogą zmylić następną osobę.

Gdy prompt mówi o „biomie nr N”, rozwiąż numer według kanonicznej kolejności regionów w dokumencie produktu i produkcyjnej scenie, nigdy według przypadkowego indeksu tablicy. Dla assetu mapy ustal także, czy jest regionalny, czy współdzielony przez wszystkie regiony, i odpowiednio rozszerz zakres kontroli regresji.

## Załaduj potrzebne odniesienia

- Zawsze przeczytaj `references/visual-direction.md`.
- Dla integracji z Godot, importu, animacji, shaderów, materiałów albo VFX przeczytaj `references/technical-art.md`.
- Przed briefem, manifestem akceptacji i pierwszą edycją przeczytaj `references/visual-qa.md`; dla zadania oceny przeczytaj je przed wydaniem werdyktu.

## Wykonaj workflow

### 1. Zdefiniuj wynik

Przełóż prośbę na krótki brief: cel emocjonalny i funkcjonalny, hierarchię planów, ograniczenia stylu i czytelności, zachowania których nie wolno zmienić, kryteria akceptacji oraz ujęcia przed/po. Drobne decyzje wyprowadź z aktywnej gry. Pytaj tylko wtedy, gdy wybór zmieniłby produkt, architekturę albo zapis.

Dobierz skalę procesu:

- dla korekty artefaktu napraw konkretną przyczynę i sprawdź regresję;
- dla polishu porównaj kontrolowany wariant z bazą;
- dla nowego kierunku, hero assetu albo istotnego redesignu przygotuj 2–3 tanie warianty kompozycji lub języka wizualnego, oceń je względem briefu i integruj tylko zwycięski kierunek.

Przed pierwszą edycją zamroź receptę dowodową: stan lub save, seed, kamera, rozdzielczość, profil jakości, `reduced_motion` i moment osi prezentacji. Jeżeli istniejący harness nie kontroluje któregoś elementu, jawnie zanotuj ograniczenie zamiast dopasowywać ujęcia ręcznie.

### 2. Zbadaj aktywny łańcuch

Znajdź scenę uruchamianą w grze, jej zasoby, ustawienia importu, źródła grafiki, kod sterujący oraz profile danych. Obejrzyj bieżący rezultat, jeśli można go bezpiecznie uruchomić lub wyrenderować. Zapisz punkt odniesienia. Znajdź istniejący harness, scenę snapshotową lub procedurę podglądu dla tego zakresu, zanim zaprojektujesz nową.

Zbuduj krótki rejestr łańcucha: edytowalne źródło, eksport runtime, import Godot, `Resource`, aktywny konsument, stan wyzwalający i kadr wynikowy. Potwierdź każde ogniwo referencją z projektu; podobna nazwa lub nowszy numer wersji nie są dowodem aktywności.

### 3. Zaprojektuj język wizualny

Ustal sylwetkę, wartości tonalne, paletę, głębię, materiał, rytm ruchu i hierarchię efektów. Dodawaj detal dopiero po uzyskaniu czytelnej kompozycji. Każdy efekt ma komunikować środowisko, akcję albo stan — nie tylko dekorować ekran. Oceniaj kierunek w docelowej skali kamery i obok sąsiednich, zaakceptowanych assetów.

### 4. Dobierz metodę produkcji

- Edytuj repozytorium dla scen, zasobów Godot, shaderów, materiałów, proceduralnych rendererów i animacji.
- Użyj ImageGen dla nowych lub przerabianych bitmap, tekstur, sprite'ów, portretów i ilustracji, gdy raster jest właściwym artefaktem.
- Zachowaj spójność wariantów przez wspólne referencje, płótno, pivot, oświetlenie i paletę.
- Nie zastępuj grafiki docelowej przypadkowym placeholderem bez jawnego oznaczenia.

Traktuj wynik generatora obrazu jako kandydata źródłowego, nie gotowy asset produkcyjny. Przed promocją sprawdź anatomię i ciągłość form, krawędzie alfa, szwy, skalę detalu, spójność wariantów, możliwość legalnego użycia oraz wynik po imporcie i w runtime. Zachowaj odtwarzalne źródło albo informację o pochodzeniu w raporcie zadania, bez tworzenia nowego kanonicznego dokumentu.

### 5. Zintegruj najmniejszy kompletny wycinek

Zmień źródło, import, zasób i konsumenta tylko w zakresie koniecznym do działania rezultatu. Zachowaj osobno prezentację i logikę domenową. Nie wiąż kolizji, obrażeń, prędkości ani zapisu z liczbą klatek, nazwą tekstury czy intensywnością efektu.

Zachowaj ten sam komunikat wizualny na `low/medium/high`: profil może redukować próbki, geometrię, liczbę cząstek i detal wtórny, lecz nie może usuwać kluczowej sylwetki, informacji ani intencji artystycznej. `reduced_motion` ogranicza ruch dekoracyjny i pełnoekranowy, zachowując ruch potrzebny do sterowania, orientacji i odczytania stanu.

### 6. Zweryfikuj i iteruj

Przeprowadź bramki z `references/visual-qa.md`. Porównaj przed/po w identycznym kadrze i stanie. Sprawdź wynik w ruchu, skrajnych stanach i rozdzielczościach. Dla każdej zmiany ruchu, animacji albo VFX sprawdź także `reduced_motion`; dla statycznego konsumenta odnotuj, że wariant nie ma zastosowania.

Dla istotnej zmiany wykonaj co najmniej jedną pełną pętlę `capture -> krytyka -> korekta -> ponowny capture`. Jeśli dostępny jest niezależny agent, zleć mu końcową ocenę na podstawie briefu i surowych kadrów lub klipu, bez podawania oczekiwanej diagnozy. Brak niezależnego recenzenta nie zwalnia z własnej drugiej oceny po przerwie kontekstowej.

Nie kończ zadania, gdy:

- runtime nadal wskazuje stary lub inny zasób;
- grafika jest efektowna w izolacji, ale osłabia czytelność;
- animacja ma poprawne klatki, lecz zły rytm, pivot lub przejścia;
- efekt zasłania informacje, migocze, powoduje banding albo źle skaluje się z kamerą;
- nowa bitmapa wygląda dobrze tylko w podglądzie generatora, lecz nie przeszła czyszczenia i importu;
- profil niższej jakości lub `reduced_motion` traci istotny sygnał albo charakter sceny;
- nie wykonano porównania wizualnego lub próby reprezentatywnego stanu.

### 7. Zaktualizuj właściwego właściciela

Stosuj routing dokumentacji z głównego `AGENTS.md`. Ten skill nie jest dziennikiem zmian ani drugim dokumentem produktu. Na końcu podaj cel i rezultat, aktywny łańcuch plików, pochodzenie nowych assetów, sposób weryfikacji, obejrzane stany, wynik bramek jakości, ograniczenia oraz najlepszą kolejną iterację.

## Przykładowe wywołania

- „Użyj `$ostatni-pomost-art` i popraw grafikę oraz animację nurka.”
- „Popraw graficznie mapę i efekty biomu nr 2.”
- „Ujednolić portrety z estetyką podwodnej eksploracji.”
- „Oceń shader wody i VFX bąbelków pod kątem jakości, czytelności i wydajności.”
