# Rejestr decyzji architektonicznych (ARD)

Rola tego pliku: przechowuje trwale, normatywne rozstrzygniecia oraz ich uzasadnienie. Nie opisuje biezacego stanu implementacji, pelnych zasad gry, szczegolow implementacyjnych, instrukcji uruchamiania ani procesu pracy agentow.

Pelna macierz odpowiedzialnosci dokumentow znajduje sie w AGENTS.md. Stan runtime opisuje .ai/PROJECT_CONTEXT.md, sens widoczny dla gracza - docs/OgolnyZarys.txt, techniczne mapowanie systemow - docs/Ostatni_Pomost_architektura_Godot.txt, a onboarding - README.md.

## Kontrakt wpisu

Nowy ARD powstaje tylko wtedy, gdy rozstrzygniecie:

- zmienia wlasciciela stanu lub zachowania, granice modulow albo kolejnosc transakcji;
- zmienia kontrakt zapisu, migracji lub kompatybilnosci;
- ustanawia przekrojowy inwariant obowiazujacy kolejne wdrozenia;
- utrwala istotna odrzucona alternatywe, do ktorej zespol moglby wrocic.

ARD nie zawiera biezacego stanu realizacji, listy luk, pelnej specyfikacji mechaniki, tabel balansu, parametrow assetow lub shaderow, drzewa scen, list pol i metod, fixture'ow migracyjnych, list testow ani wynikow testow. Takie informacje trafiaja do dokumentu bedacego ich wlascicielem.

Kazdy wpis ma:

- domene;
- status: Obowiazuje, Czesciowo zastapione albo Zastapione;
- date zatwierdzenia; dla dawnych wpisow bez zachowanej daty: data nieutrwalona;
- stabilne klauzule D1, D2, ...;
- relacje Zastepuje i Zastapiona przez;
- aktywny zakres, gdy wpis jest czesciowo zastapiony;
- krotkie uzasadnienie, skutek i odwolania do dokumentow szczegolowych.

Zastapienie jest zawsze symetryczne: nowy wpis wskazuje identyfikator i klauzule poprzednika, a poprzednik wskazuje nowy wpis przy tych samych klauzulach. Zapis ARD-XXXX/Dy po obu stronach zawsze oznacza klauzule starszego, zastepowanego wpisu; dla pelnego zastapienia stosuje sie ARD-XXXX/calosc. Pelne zastapienie nie pozostawia aktywnego zakresu. Identyfikatorow usunietych lub pominietych nie wykorzystuje sie ponownie. Korekta redakcyjna nie zmienia sensu decyzji; zmiana sensu wymaga nowego ARD.

---

## ARD-0001 - Jeden kanoniczny GameState

- Domena: stan kampanii
- Status / aktywny zakres: Obowiazuje; D1-D2
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. GameState jest jedynym wlascicielem trwalego stanu kampanii.
- D2. Sceny, kontrolery i UI moga przechowywac stan prezentacyjny, lecz nie tworza konkurencyjnej kopii domeny.
- Powod i skutek: jedno zrodlo stanu zapobiega rozjazdom zapisu, UI i logiki; wszystkie zmiany kampanii przechodza przez systemy domenowe.
- Odwolania: .ai/PROJECT_CONTEXT.md; docs/Ostatni_Pomost_architektura_Godot.txt - stan kampanii i persistence.

## ARD-0002 - Granica modulu bazy i nurkowania

- Domena: granice modulow
- Status / aktywny zakres: Obowiazuje; D1-D2
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Baza i nurkowanie sa odrebnymi modulami wykonawczymi.
- D2. Publiczna granica wyprawy ma postac ExpeditionSetup -> DiveResult; modul nurkowania nie mutuje bezposrednio GameState.
- Powod i skutek: izoluje fizyke sesji od ekonomii kampanii i pozwala zatwierdzac wynik wyprawy transakcyjnie.
- Odwolania: docs/Ostatni_Pomost_architektura_Godot.txt - przeplyw wyprawy i rozliczenie wyniku.

## ARD-0003 - Resource dla danych, system dla regul

- Domena: dane i logika
- Status / aktywny zakres: Czesciowo zastapione; D1-D3
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0013/D4
- D1. Strojalne, walidowane dane domenowe naleza do Resource; algorytmiczne inwarianty naleza do wskazanego systemu.
- D2. Pelne, danymi sterowane definicje biomow pozostaja wymaganiem docelowego pionu mechanicznej tozsamosci, a nie opisem biezacego runtime.
- D3. Samo istnienie pola lub zasobu nie aktywuje mechaniki bez producenta, konsumenta i widocznego skutku.
- D4. Historyczny opis biezacej reprezentacji czterech regionow zostal zastapiony przez ARD-0013.
- Powod i skutek: oddziela dane projektowe od zachowania i nie pozwala, by martwe pola staly sie ukryta specyfikacja.
- Odwolania: ARD-0013; ARD-0027; docs/Ostatni_Pomost_architektura_Godot.txt - wlasnosc danych.

## ARD-0004 - Jeden resolver konca dnia

- Domena: transakcja dnia
- Status / aktywny zakres: Czesciowo zastapione; D1
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0044/D2
- D1. EndOfDayResolver jest jedynym wlascicielem zatwierdzenia skutkow dnia w stanie kampanii.
- D2. Historyczna kolejnosc wewnetrznych krokow zostala zastapiona pelnym kontraktem rozliczenia dnia.
- Powod i skutek: skutki dnia sa atomowe, powtarzalne i nie sa rozproszone po scenach.
- Odwolania: ARD-0044; docs/Ostatni_Pomost_architektura_Godot.txt - kolejnosc rozliczenia dnia.

## ARD-0005 - Prowadzony start na pustej platformie

- Domena: poczatek kampanii
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Kampania zaczyna sie na pustej platformie z poczatkowa zaloga i prowadzonym wprowadzeniem.
- D2. Pierwsza konstrukcja korzysta z tych samych regul domenowych co dalsza gra.
- D3. Tutorial prowadzi gracza, ale nie tworzy osobnej ekonomii ani fikcyjnego trybu kampanii.
- Powod i skutek: onboarding potwierdza rzeczywisty rdzen gry zamiast uczyc wyjatku.
- Odwolania: docs/OgolnyZarys.txt - poczatek gry; docs/Ostatni_Pomost_architektura_Godot.txt - tutorial.

## ARD-0006 - Stale sloty, prezentacja pochodna

- Domena: uklad bazy
- Status / aktywny zakres: Czesciowo zastapione; D1-D2
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0035/D3; ARD-0066/D4
- D1. Platforma ma staly zestaw typowanych slotow budowy.
- D2. Wizualizacja i obszary interakcji wynikaja z kanonicznego stanu slotow.
- D3. Historyczny szczegol reprezentacji ukladu zostal doprecyzowany przez ARD-0035.
- D4. Historyczny model prezentacji zostal zastapiony hybrydowa granica 2.5D/3D.
- Powod i skutek: uklad pozostaje deterministyczny, a wymiana warstwy wizualnej nie zmienia domeny.
- Odwolania: ARD-0035; ARD-0066; docs/Ostatni_Pomost_architektura_Godot.txt - platforma.

## ARD-0007 - Lokalna sesja nurkowania i atomowy wynik

- Domena: wyprawa
- Status / aktywny zakres: Czesciowo zastapione; D1-D2
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0050/D3
- D1. DiveSessionState jest wlascicielem zmiennego stanu pojedynczego nurkowania.
- D2. GameState zmienia sie dopiero przez zatwierdzony DiveResult po zakonczeniu sesji.
- D3. Dawna semantyka porazki tutorialowej zostala zastapiona przez jawny kontrakt ponowienia.
- Powod i skutek: przerwana lub powtarzana sesja nie pozostawia czesciowo zapisanych skutkow kampanii.
- Odwolania: ARD-0002; ARD-0050; docs/Ostatni_Pomost_architektura_Godot.txt - sesja nurkowania.

## ARD-0013 - Kanoniczna warstwowa mapa swiata

- Domena: swiat
- Status / aktywny zakres: Czesciowo zastapione; D1-D2
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: ARD-0003/D4 | Zastapiona przez: ARD-0052/D3; ARD-0059/D4
- D1. Swiat wyprawy uzywa jednego kanonicznego ukladu wspolrzednych, stalych wymiarow i warstw danych; zmiana przestrzeni lub wymiarow wymaga nowej decyzji.
- D2. Warstwa wizualna, kolizje, odkrycie i stan obiektow odnosza sie do tej samej przestrzeni.
- D3. Dawny opis fizycznej reprezentacji zostal zastapiony przez ARD-0052.
- D4. Dawne zalozenia wariantow mapy i ziarna zostaly zastapione przez ARD-0059.
- Powod i skutek: systemy nie interpretuja tej samej lokacji wedlug roznych map.
- Odwolania: ARD-0052; ARD-0059; docs/Ostatni_Pomost_architektura_Godot.txt - swiat i mapa.

## ARD-0014 - Zamkniety zestaw dokumentow projektu

- Domena: dokumentacja
- Status / aktywny zakres: Zastapione; brak
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0086/calosc
- D1. Wiedza projektowa jest utrzymywana w szesciu wskazanych plikach: AGENTS.md, .ai/PROJECT_CONTEXT.md, .ai/DECISIONS.md, docs/OgolnyZarys.txt, docs/Ostatni_Pomost_architektura_Godot.txt i README.md.
- D2. Nowa wiedza jest scalana z wlasciwym plikiem zamiast tworzenia kolejnych dokumentow.
- Powod i skutek: ograniczony zestaw zmniejsza ryzyko sprzecznych kopii.
- Odwolania: AGENTS.md - Dokumentacja.

## ARD-0015 - Trwaly ekwipunek pionu nurkowego

- Domena: ekwipunek
- Status / aktywny zakres: Obowiazuje; D1-D4
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Ekwipunek pionu nurkowego jest trwalym stanem kampanii i jest definiowany przez walidowane dane.
- D2. ExpeditionSetup zamraza wybrany zestaw na czas sesji.
- D3. Podstawowe wyposazenie zapewnia bezpieczny kontrakt startowy; ulepszenia moga podlegac utracie i odzyskaniu.
- D4. Szczegolowe parametry i balans nie sa czescia ARD.
- Powod i skutek: przygotowanie wyprawy i zapis korzystaja z jednego modelu ekwipunku.
- Odwolania: docs/OgolnyZarys.txt - ekwipunek; docs/Ostatni_Pomost_architektura_Godot.txt - przygotowanie wyprawy.

## ARD-0016 - Trwaly stan ocalalego i migawka wyprawy

- Domena: zaloga
- Status / aktywny zakres: Czesciowo zastapione; D1-D2
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0030/D3; ARD-0036/D4
- D1. Ocalaly ma jeden trwaly rekord kampanii.
- D2. Dane potrzebne w nurkowaniu sa zamrazane w ExpeditionSetup, a zmiany wracaja przez DiveResult.
- D3. Historyczny kontrakt tlenu zostal zastapiony przez ARD-0030.
- D4. Historyczny kontrakt rozwoju profesji zostal zastapiony przez ARD-0036.
- Powod i skutek: sesja nie pracuje na zywym rekordzie kampanii, a rozwoj postaci ma jawnych wlascicieli.
- Odwolania: ARD-0030; ARD-0036; docs/Ostatni_Pomost_architektura_Godot.txt - roster i setup.

## ARD-0017 - Waga i udzwig jako dwa ograniczenia

- Domena: lup i transport
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Waga przedmiotu i pojemnosc transportowa sa odrebnymi ograniczeniami domenowymi.
- D2. Obciazenie ma rzeczywisty skutek w sesji nurkowania.
- D3. Czesc lupow moze zostac przeniesiona lub pozostawiona bez utraty pozostalego stanu transakcji.
- Powod i skutek: jeden uproszczony licznik nie moze omijac kosztu decyzji logistycznej.
- Odwolania: docs/OgolnyZarys.txt - lup; docs/Ostatni_Pomost_architektura_Godot.txt - ekwipunek i wynik wyprawy.

## ARD-0018 - Plan dnia i niezmienna migawka

- Domena: planowanie
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Gracz edytuje plan dnia przed jego zatwierdzeniem.
- D2. Rozpoczecie wyprawy albo rozliczenia dnia tworzy niezmienna migawke planu.
- D3. Kolejne zmiany tworza nowy plan, nie modyfikuja rozpoczetego rozliczenia.
- Powod i skutek: wynik dnia pozostaje deterministyczny i odporny na pozne zmiany UI.
- Odwolania: docs/Ostatni_Pomost_architektura_Godot.txt - plan dnia i EndOfDayResolver.

## ARD-0019 - Atomowy, wersjonowany autosave

- Domena: zapis
- Status / aktywny zakres: Czesciowo zastapione; D1, D3-D5
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0092/D4
- D1. Zapis ma jawna wersje schematu.
- D2. Odczyt i migracja powstaja w odseparowanym kandydacie, zanim zastapia aktywny GameState.
- D3. Kandydat jest walidowany, a zapis jest zatwierdzany atomowo z mozliwoscia bezpiecznego odzyskania poprzedniej wersji.
- D4. Nieudany odczyt nie mutuje aktywnej kampanii.
- D5. Rozliczenie dnia podmienia aktywny GameState dopiero po udanym zapisie calego rozliczonego kandydata.
- Powod i skutek: awaria lub stary zapis nie pozostawia polowicznego stanu.
- Odwolania: ARD-0045; ARD-0065; docs/Ostatni_Pomost_architektura_Godot.txt - persistence.

## ARD-0020 - TutorialDirector jako jedyny wlasciciel kroku

- Domena: tutorial
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Tylko TutorialDirector zmienia krok tutorialu.
- D2. Postep wynika ze zdarzen domenowych, nie z rozproszonych flag UI.
- D3. Po wczytaniu stan tutorialu jest uzgadniany z kanonicznym stanem kampanii.
- Powod i skutek: tutorial moze byc wznowiony bez podwojonych nagrod i martwych krokow.
- Odwolania: docs/Ostatni_Pomost_architektura_Godot.txt - tutorial.

## ARD-0021 - Jedno przygotowanie wyprawy

- Domena: przygotowanie nurkowania
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Jeden system przygotowania jest wlascicielem oceny gotowosci i budowy ExpeditionSetup.
- D2. UI i komenda rozpoczecia korzystaja z tej samej analizy blokad.
- D3. Zadna scena nie sklada alternatywnego setupu z wlasnych kopii danych.
- Powod i skutek: komunikat dla gracza i faktyczna mozliwosc startu nie rozjezdzaja sie.
- Odwolania: docs/Ostatni_Pomost_architektura_Godot.txt - ExpeditionPreparation.

## ARD-0022 - Jeden szkielet kampanii

- Domena: petla kampanii
- Status / aktywny zakres: Czesciowo zastapione; D1-D6
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0050/D7
- D1. Kampania ma jeden produkcyjny szkielet bez sekundowej symulacji bazy podczas wyprawy, zamiast osobnych trybow demonstracyjnych.
- D2. Dzien dopuszcza najwyzej jedna wyprawe albo swiadome zakonczenie bez wyprawy.
- D3. Swiat i postep uzywaja miekkich bram wynikajacych z domeny.
- D4. Wybrany DifficultyProfile jest kopiowany gleboko i pieczetowany w kampanii pod stabilna tozsamoscia oraz podpisem konfiguracji; wczytanie nie reinterpretuje go wedlug biezacych danych.
- D5. Deterministyczna presja jest aktualizowana wylacznie na granicy dnia, a konsumenci czytaja zatwierdzona migawke.
- D6. Nowa mechanika przechodzi pelny pion od decyzji i danych do konsumenta, zapisu oraz pokrycia; zwykle systemy gameplayowe nie staja sie autoloadami ani pustym rusztowaniem.
- D7. Dawna semantyka resetu tutorialowej sesji zostala zastapiona przez ARD-0050.
- Powod i skutek: wszystkie mechaniki dokladaja sie do jednej grywalnej petli.
- Odwolania: docs/OgolnyZarys.txt - petla gry; docs/Ostatni_Pomost_architektura_Godot.txt - przeplyw kampanii.

## ARD-0023 - Lokalne, wykonywalne ryzyko nurkowania

- Domena: ryzyko wyprawy
- Status / aktywny zakres: Czesciowo zastapione; D1-D3
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0050/D4
- D1. Ryzyko nurkowania powstaje i jest rozliczane w lokalnej sesji.
- D2. Do kampanii wraca przez jednoznaczny DiveResult.
- D3. Aktywna konsekwencja musi miec wykonywalny lancuch przyczyna -> skutek widoczny dla gracza.
- D4. Dawna semantyka napraw po porazce tutorialowej zostala zastapiona przez ARD-0050.
- Powod i skutek: ryzyko nie jest dekoracyjna flaga ani ukryta mutacja kampanii.
- Odwolania: ARD-0007; ARD-0050; docs/Ostatni_Pomost_architektura_Godot.txt - ryzyko nurkowania.

## ARD-0024 - Jedna dzienna migawka pogody

- Domena: pogoda
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Dzien ma jeden kanoniczny WeatherState.
- D2. Pogoda jest deterministycznie wybierana i utrzymywana jako migawka dnia.
- D3. Prezentacja i skutki domenowe czytaja te sama migawke; nie wykonuja niezaleznych losowan.
- Powod i skutek: gracz widzi te same warunki, ktore faktycznie rozlicza ekonomia i wyprawa.
- Odwolania: docs/OgolnyZarys.txt - pogoda; docs/Ostatni_Pomost_architektura_Godot.txt - WeatherState.

## ARD-0025 - Transakcyjna eksploracja i WorldDelta

- Domena: swiat i eksploracja
- Status / aktywny zakres: Czesciowo zastapione; D1-D3
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0068/D4
- D1. Zmiany odkrytego swiata powstaja lokalnie w sesji i wracaja jako WorldDelta w DiveResult.
- D2. Obiekty swiata maja stabilna tozsamosc potrzebna do zapisu i migracji.
- D3. Wynik moze utrwalic czesciowy postep; Warsztat zatwierdza najwyzej jeden ciezki odzysk na dzien wedlug jednoznacznego priorytetu transakcji.
- D4. Dawne kryterium zaliczenia pracy produkcyjnej zostalo zastapione przez kontrakt rzeczywistej pracy w ARD-0068.
- Powod i skutek: eksploracja nie mutuje zapisu w polowie sesji i moze byc bezpiecznie wznowiona.
- Odwolania: ARD-0059; ARD-0068; docs/Ostatni_Pomost_architektura_Godot.txt - WorldDelta.

## ARD-0026 - Transakcyjny ratunek

- Domena: ratowanie ocalalych
- Status / aktywny zakres: Obowiazuje; D1-D5
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Kandydat do uratowania ma stabilna tozsamosc i walidowane dane.
- D2. Stan ratunku jest lokalny dla wyprawy do chwili zatwierdzenia DiveResult.
- D3. Przyjecie ocalalego do rosteru jest jedna transakcja kampanii.
- D4. Ratunek ma rzeczywisty koszt i ryzyko wyprawy; nie jest nagroda spoza systemu.
- D5. Poprawnie uratowana osoba wchodzi do rosteru przed gospodarka tego samego dnia po zastosowaniu DiveResult.
- Powod i skutek: ponowienie lub wczytanie nie duplikuje postaci i nie omija kosztu decyzji.
- Odwolania: docs/OgolnyZarys.txt - ratunek; docs/Ostatni_Pomost_architektura_Godot.txt - roster i wynik wyprawy.

## ARD-0027 - Tylko wykonywalne mechaniki sa aktywne

- Domena: granica produktu
- Status / aktywny zakres: Czesciowo zastapione; D1-D2
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0044/D3; ARD-0051/D4; ARD-0057/D5
- D1. Mechanika jest aktywna dopiero, gdy ma wejscie lub producenta, konsumenta gameplayowego, widoczny skutek i walidacje adekwatna do ryzyka.
- D2. Pole, hook, klasa, etykieta lub sekcja docelowa bez takiego lancucha nie ustanawia aktywnej funkcji.
- D3. Dawny kontrakt kategorii kosztow i kolejnosci produkcji zostal zastapiony przez ARD-0044.
- D4. Dawna gwarancja odzyskiwalnosci artefaktu zostala zastapiona przez ARD-0051.
- D5. Dawny globalny model tempa zostal zastapiony przez ARD-0057, a nastepnie ARD-0068.
- Powod i skutek: dokumenty nie obiecuja mechanik, ktorych runtime jeszcze nie wykonuje.
- Odwolania: docs/OgolnyZarys.txt - statusy; .ai/PROJECT_CONTEXT.md - potwierdzony stan.

## ARD-0028 - Test lokalny nie jest dowodem petli A-Z

- Domena: weryfikacja
- Status / aktywny zakres: Obowiazuje; D1-D2
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Test jednostkowy lub scenowy potwierdza tylko wskazany kontrakt lokalny.
- D2. Dowod grywalnej petli A-Z wymaga przejscia przez rzeczywiste granice systemow i zapisu.
- Powod i skutek: zielony test fragmentu nie moze byc raportowany jako potwierdzenie calej kampanii.
- Odwolania: docs/Ostatni_Pomost_architektura_Godot.txt - mapa ryzyka testow; .ai/PROJECT_CONTEXT.md - ostatnia weryfikacja.

## ARD-0029 - Historyczny kregoslup Projektu Swit

- Domena: postep i zakonczenie
- Status / aktywny zakres: Zastapione; brak
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0055/D5; ARD-0059/D6; ARD-0068/D3,D7; ARD-0077/calosc
- D1. CampaignProgression jest jednym wlascicielem postepu artefaktow, Projektu, kryzysu i zakonczenia kampanii.
- D2. Projekt jest wspolna osia pracy prowadzaca do mozliwosci zakonczenia; jego dokladne reguly i balans naleza do opisu produktu.
- D3. Historyczny globalny model tempa Projektu zostal zastapiony przez ARD-0068.
- D4. Kryzys i zakonczenie sa skutkami kanonicznego postepu, a nie osobnymi flagami UI.
- D5. Historyczny moment faktycznego odplyniecia zostal zastapiony przez ARD-0055.
- D6. Historyczny kontrakt wersji blueprintu zostal zastapiony przez ARD-0059.
- D7. Historyczna wersja schematu zapisu zostala zastapiona przez ARD-0068.
- Powod i skutek: cele dlugoterminowe nie tworza konkurencyjnych licznikow postepu.
- Odwolania: ARD-0055; ARD-0059; ARD-0068; docs/OgolnyZarys.txt - cel kampanii.

## ARD-0030 - Butla jako jedyne zrodlo sprzetowej czesci pojemnosci tlenu

- Domena: tlen i ekwipunek
- Status / aktywny zakres: Czesciowo zastapione; D1, D3-D4
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0016/D3 | Zastapiona przez: ARD-0064/D2
- D1. Sprzetowa czesc pojemnosci tlenu wyprawy pochodzi wylacznie z wybranej butli; osobisty tlen i modyfikatory specjalisty pozostaja odrebnymi wejsciami, poziom Stacji nie dodaje tlenu, a jeden system przygotowania oblicza finalna wartosc sesji.
- D2. Dawna reprezentacja zlecen ulepszen i zwrotu kosztu zostala zastapiona przez trwale zamowienie warsztatu.
- D3. Podstawowa butla nie moze zostawic kampanii bez wykonalnej wyprawy.
- D4. Ulepszone wyposazenie moze byc utracone i odzyskane wedlug wspolnego kontraktu ekwipunku.
- Powod i skutek: sprzetowa czesc tlenu nie ma drugiego, ukrytego zrodla w poziomie Stacji ani scenie.
- Odwolania: ARD-0021; ARD-0064; docs/Ostatni_Pomost_architektura_Godot.txt - przygotowanie wyprawy.

## ARD-0031 - Selektywny lup i trwale porzucone stosy

- Domena: lup
- Status / aktywny zakres: Obowiazuje; D1-D4
- Zatwierdzenie: data nieutrwalona
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Gracz jawnie wybiera, ktore przedmioty przenosi, a system domenowy egzekwuje ograniczenia.
- D2. Porzucony lub odlozony lup pozostaje fizycznym, trwalym stanem swiata.
- D3. Transfer do kampanii jest czescia transakcji DiveResult i jest odporny na ponowienie.
- D4. Tutorial moze wymagac konkretnego zrodla przedmiotu bez tworzenia osobnego typu lupow.
- Powod i skutek: interfejs wyraza intencje, lecz nie staje sie wlascicielem ekwipunku ani stanu swiata.
- Odwolania: ARD-0017; ARD-0025; docs/Ostatni_Pomost_architektura_Godot.txt - lup.

## ARD-0032 - Deterministyczne zdarzenie osady

- Domena: zdarzenia
- Status / aktywny zakres: Czesciowo zastapione; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0063/D4
- D1. Jeden system domenowy jest wlascicielem doboru i rozliczenia zdarzen osady.
- D2. Dla danego stanu poranka oferta jest wybierana deterministycznie i najwyzej raz.
- D3. Reguly zdarzen sa walidowanymi danymi i moga odnosic sie do kanonicznej presji kampanii.
- D4. Dawna reprezentacja migawki oferty zostala zastapiona przez ARD-0063.
- Powod i skutek: ponowne otwarcie UI lub wczytanie nie przerzuca zdarzenia i nie zmienia kosztu decyzji.
- Odwolania: ARD-0063; docs/Ostatni_Pomost_architektura_Godot.txt - zdarzenia osady.

## ARD-0034 - Dziennik misji nie jest brama

- Domena: prowadzenie gracza
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Misje i cele dziennika wynikaja z kanonicznego stanu, ale nie sa warunkiem wykonania poprawnej czynnosci domenowej.
- D2. Dziennik nie przechowuje drugiego postepu kampanii.
- D3. Sledzenie kryzysu jest prezentacja tymczasowego stanu, nie osobnym systemem zasad.
- Powod i skutek: gracz moze odkryc rozwiazanie sam, a utrata wpisu UI nie blokuje gry.
- Odwolania: docs/OgolnyZarys.txt - prowadzenie gracza; docs/Ostatni_Pomost_architektura_Godot.txt - misje.

## ARD-0035 - Staly uklad platformy

- Domena: baza
- Status / aktywny zakres: Czesciowo zastapione; D1, D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0006/D3 | Zastapiona przez: ARD-0066/D2
- D1. Platforma uzywa stalego ukladu szesciu typowanych miejsc budowy.
- D2. Dawna techniczna reprezentacja aktywnego widoku zostala zastapiona przez hybrydowy model 2.5D/3D.
- D3. Stan budynkow jest domenowy, a polozenie, hitbox i wizualizacja sa jego prezentacja.
- Powod i skutek: zmiana warstwy wizualnej nie przestawia semantyki slotow ani zapisu.
- Odwolania: ARD-0006; ARD-0066; docs/Ostatni_Pomost_architektura_Godot.txt - uklad bazy.

## ARD-0036 - Dwie osie rozwoju profesji

- Domena: zaloga i praca
- Status / aktywny zakres: Czesciowo zastapione; D1-D2
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0016/D4 | Zastapiona przez: ARD-0068/D4; ARD-0084/D3
- D1. Ocalaly ma rozwoj osobisty oraz praktyke w wykonywanej pracy jako odrebne osie.
- D2. Poza rola podstawowa moze rozwijac najwyzej jedna role dodatkowa.
- D3. Postep powstaje tylko z rzeczywiscie wykonanej pracy, a profesje musza miec wykonywalny skutek domenowy.
- D4. Dawne kryterium zaliczenia produkcji zostalo zastapione dziennikiem rzeczywistej pracy.
- Powod i skutek: sama deklaracja przydzialu nie produkuje doswiadczenia ani kompetencji.
- Odwolania: ARD-0068; docs/OgolnyZarys.txt - rozwoj zalogi.

## ARD-0037 - Archiwum siedmiu raportow

- Domena: narracja i zapis
- Status / aktywny zakres: Obowiazuje; D1-D4
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Kampania przechowuje archiwum siedmiu najnowszych zakonczonych raportow dnia.
- D2. Zapisany raport jest niezmienna migawka historyczna, a nie zywym widokiem stanu.
- D3. Raport odnosi sie do jednoznacznie rozliczonego dnia.
- D4. Przejscie dnia i utrwalenie raportu sa objete ta sama granica zapisu.
- Powod i skutek: Kronika pozostaje wiarygodna po dalszych zmianach kampanii.
- Odwolania: docs/OglnyZarys.txt - Kronika; docs/Ostatni_Pomost_architektura_Godot.txt - raport dnia.

## ARD-0038 - Trwaly roster i pochodne indeksy

- Domena: zaloga
- Status / aktywny zakres: Obowiazuje; D1-D4
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. BuildingState.assigned_survivor_ids jest kanonicznym, zwartym i trwalym rosterem obsady budynku.
- D2. SurvivorState.current_assignment jest odbudowywanym indeksem odwrotnym, a UI nie przechowuje konkurencyjnego zrodla obsady.
- D3. DayPlanState.worker_assignments jest synchronizowana podczas edycji i po zablokowaniu pozostaje niezmienna migawka obsady dnia.
- D4. Zmiany skladu i przydzialow sa uzgadniane atomowo; strojalne wartosci pracy naleza do danych.
- Powod i skutek: usuniecie, ratunek lub migracja postaci nie zostawia osieroconych powiazan.
- Odwolania: ARD-0016; docs/Ostatni_Pomost_architektura_Godot.txt - roster.

## ARD-0039 - Podglad budynku wykonuje prawdziwe reguly

- Domena: budynki i UI
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. BuildingEffectSystem jest bezstanowym prezenterem tylko do odczytu; deleguje do walidowanych definicji i kanonicznych systemow wykonujacych skutki budynku, zamiast stawac sie drugim wlascicielem regul.
- D2. Podglad odczytuje te same dane i systemy co wlasciwi konsumenci runtime.
- D3. UI pokazuje rzeczywisty brak efektu i prawdziwa przyczyne blokady.
- Powod i skutek: podglad nie obiecuje efektu, ktorego rozliczenie dnia nie wykona.
- Odwolania: docs/Ostatni_Pomost_architektura_Godot.txt - budynki i podglad.

## ARD-0040 - Minimalny, kontekstowy HUD nurkowania

- Domena: interfejs nurkowania
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. HUD pokazuje tylko informacje potrzebne do aktualnej decyzji w nurkowaniu.
- D2. Dane pochodza z ExpeditionSetup i DiveSessionState, nie z kopii utrzymywanej przez UI.
- D3. Alerty i cel prowadza gracza, lecz nie stanowia domenowej bramy czynnosci.
- Powod i skutek: interfejs jest czytelny i nie staje sie dodatkowym silnikiem sesji.
- Odwolania: docs/OgolnyZarys.txt - doswiadczenie nurkowania; docs/Ostatni_Pomost_architektura_Godot.txt - HUD.

## ARD-0041 - Animacja wynika ze stanu

- Domena: prezentacja
- Status / aktywny zakres: Czesciowo zastapione; D1-D2, D4
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0076/D3
- D1. Animacja i efekty sa pochodna kanonicznego stanu lub zatwierdzonego wyniku.
- D2. Animacja nie przesuwa postepu domenowego.
- D3. Dawny kontrakt prezentacji budowy oczekujacej na rozliczenie dnia zostal zastapiony przez ARD-0076.
- D4. Prezentacja jest deterministyczna wobec danych potrzebnych do odtworzenia znaczenia.
- Powod i skutek: przerwana animacja nie zmienia ekonomii ani wyniku kampanii.
- Odwolania: docs/Ostatni_Pomost_architektura_Godot.txt - warstwa prezentacji.

## ARD-0042 - Hierarchia zrodel i statusy dokumentacji

- Domena: dokumentacja i rozstrzyganie konfliktow
- Status / aktywny zakres: Czesciowo zastapione; D2-D3, D5-D7, D9
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0070/D1,D4,D8
- D1. AGENTS.md okresla proces pracy i nie ustanawia mechanik gry ani technicznych kontraktow systemow.
- D2. Obowiazujace ARD ustanawiaja normatywne granice; kod, sceny, dane i testy ujawniaja faktyczny runtime.
- D3. Roznica runtime wobec obowiazujacego ARD jest luka, a nie pozwoleniem na cicha reinterpretacje jednego ze zrodel.
- D4. .ai/PROJECT_CONTEXT.md podsumowuje implementacje, docs/OgolnyZarys.txt opisuje produkt, docs/Ostatni_Pomost_architektura_Godot.txt mapowanie techniczne, a README.md wejscie do projektu.
- D5. AKTYWNE oznacza potwierdzony runtime; DOCELOWE zatwierdzony kierunek bez kompletnego runtime; LEGACY element zachowany dla zgodnosci bez prawa do tworzenia nowej domeny; HISTORYCZNE fakt nieobowiazujacy i nieopisujacy biezacego stanu.
- D6. Status wpisu ARD opisuje obowiazywanie decyzji i jest odrebny od statusu funkcji produktu.
- D7. Zatwierdzenie jest osobnym metadanym wpisu i nie oznacza automatycznie wykonania decyzji w runtime.
- D8. Historycznie stan wdrozenia byl osobnym polem kazdego ARD.
- D9. Korekta redakcyjna moze poprawic zapis bez zmiany sensu; zmiana decyzji wymaga nowego ARD.
- Powod i skutek: konflikt jest widoczny i ma jawna sciezke rozstrzygniecia, bez mnozenia konkurencyjnych prawd.
- Odwolania: ARD-0070; AGENTS.md; .ai/PROJECT_CONTEXT.md.

## ARD-0043 - Aktywna granica produktu

- Domena: zakres gry
- Status / aktywny zakres: Czesciowo zastapione; D1, D3-D4, D6
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0055/D5; ARD-0102/D4
- D1. Aktywna kampania i Kronika korzystaja z jednej stalej, szescioslotowej platformy; dzielnice, przenoszenie, sasiedztwo, segmenty konstrukcji i uszkodzenia pojedynczych budynkow wymagaja osobnej decyzji oraz oceny zapisu.
- D2. Stala mapa ma jeden kanoniczny wymiar, a dostep do czterech regionow wynika z miekkich bram domenowych; zmienna przeszkoda nie moze naruszyc jedynej trasy krytycznej i wymaga trwalego WorldDelta.
- D3. Normalny powrot wymaga aktywnej liny, a Operator jest jedyna aktywna awaryjna ekstrakcja; nazwa Dzwonu glebinowego nie ustanawia drugiego wyjscia.
- D4. Artefakt i ciezki obiekt sa odrebnymi kategoriami, a nierozstrzygniete spotkanie Leona nie ma ukrytego timera.
- D5. Dawny szczegol warunku odplyniecia zostal zastapiony przez ARD-0055.
- D6. Bazowe schronienie jest zastepowane pojemnoscia aktywnego Domu, a nazwa Radiostacji nie ustanawia mechaniki radiowej bez wykonywalnego kontraktu.
- Powod i skutek: zakres aktywny pozostaje odrozniony od pomyslow docelowych.
- Odwolania: ARD-0027; ARD-0055; docs/OgolnyZarys.txt - aktywny zakres.

## ARD-0044 - Kanoniczne rozliczenie dnia

- Domena: ekonomia dnia
- Status / aktywny zakres: Czesciowo zastapione; D1, D5-D6
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0004/D2; ARD-0027/D3 | Zastapiona przez: ARD-0053/D2; ARD-0054/D3; ARD-0058/D4; ARD-0068/D7-D8
- D1. Jeden EndOfDayResolver zatwierdza skutki dnia, takze dnia bez nurkowania; szczegolowa kolejnosc nalezy do architektury.
- D2. Dawna kolejnosc smierci nurka zostala zastapiona przez ARD-0053.
- D3. Dawna kolejnosc zywienia nurka zostala zastapiona przez ARD-0054.
- D4. Dawna semantyka niedoboru racji zostala zastapiona przez ARD-0058.
- D5. Resolver rozroznia kategorie kosztow i priorytety zobowiazan.
- D6. Presja dzienna i stan kryzysu sa odrebnymi pojeciami domenowymi.
- D7. Dawne kryterium dodatniego postepu pracy zostalo zastapione przez ARD-0068.
- D8. Dawny globalny hook tempa i napiecia zostal zastapiony lokalnym modelem ARD-0068.
- Powod i skutek: wszystkie konsekwencje dnia sa rozliczane raz, w jednej transakcji i wedlug jednej kolejnosci.
- Odwolania: ARD-0053; ARD-0054; ARD-0058; ARD-0068; docs/Ostatni_Pomost_architektura_Godot.txt - rozliczenie dnia.

## ARD-0045 - Ewolucja zapisu przez wersje i migracje

- Domena: zapis i kompatybilnosc
- Status / aktywny zakres: Czesciowo zastapione; D1
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0065/D2; ARD-0068/D4; ARD-0092/D3-D4
- D1. Zmiana znaczenia trwalego pola wymaga jawnej wersji schematu i okreslonej kompatybilnosci.
- D2. Dawny kontrakt kolejnosci walidacji zostal zastapiony przez ARD-0065.
- D3. LEGACY sluzy zgodnosci; nie staje sie fundamentem nowej domeny, a bezpieczny default nie moze po cichu zmieniac znaczenia zapisu.
- D4. Dawna aktualna wersja schematu zostala zastapiona przez migracje ARD-0068.
- Powod i skutek: stary zapis ma jawna interpretacje zamiast zalezec od przypadkowego ksztaltu nowych klas.
- Odwolania: ARD-0019; ARD-0065; ARD-0068; docs/Ostatni_Pomost_architektura_Godot.txt - zapis i migracje.

## ARD-0046 - Shell gry, intro i ustawienia sa rozdzielone

- Domena: uruchomienie i ustawienia
- Status / aktywny zakres: Czesciowo zastapione; D1-D2
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0049/D3
- D1. Shell gry tworzy lub wczytuje kampanie przed przejsciem do wprowadzenia.
- D2. Intro nie jest faza ekonomii kampanii i nie moze byc warunkiem poprawnosci zapisu.
- D3. Dawny szczegol ustawien urzadzenia zostal zastapiony przez ARD-0049.
- Powod i skutek: pominiecie lub ponowne odtworzenie intro nie uszkadza kampanii, a ustawienia nie zanieczyszczaja GameState.
- Odwolania: ARD-0049; ARD-0069; docs/Ostatni_Pomost_architektura_Godot.txt - shell i intro.

## ARD-0047 - Pochodzenie osady i rola Miry

- Domena: narracja wprowadzenia
- Status / aktywny zakres: Czesciowo zastapione; D1-D2, D4
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0069/D3
- D1. Kampania rozpoczyna sie od ustalonego pochodzenia pierwszej zalogi i platformy.
- D2. Mira prowadzi wprowadzenie z perspektywy pierwszej osoby, z dostepnymi napisami.
- D3. Dawne zalozenie prezentowania zywej sceny bazy podczas intro zostalo zastapione niezaleznym prerenderem ARD-0069.
- D4. Intro ma zamkniety kontrakt narracyjny, a szczegol rytmu nalezy do dokumentu produktu.
- Powod i skutek: wprowadzenie ma spojna tozsamosc, lecz nie ustanawia konkurencyjnego stanu kampanii.
- Odwolania: ARD-0061; ARD-0069; docs/OgolnyZarys.txt - fabula.

## ARD-0048 - Testy uruchamiane bezposrednio przez Godot

- Domena: weryfikacja techniczna
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Testy projektu sa uruchamiane bezposrednio przez Godot.
- D2. W jednej kopii projektu instancje korzystajace z tego samego cache .godot dzialaja sekwencyjnie.
- D3. Rownoleglosc wymaga osobnych pelnych kopii projektu z osobnym cache importu.
- Powod i skutek: wynik nie zalezy od wyscigu importu, blokad zasobow lub wspolnego autosave.
- Odwolania: AGENTS.md - Weryfikacja; README.md - uruchamianie testow.

## ARD-0049 - Ustawienia urzadzenia maja prawdziwych konsumentow

- Domena: ustawienia
- Status / aktywny zakres: Obowiazuje; D1-D5
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0046/D3 | Zastapiona przez: brak
- D1. UserSettings jest oddzielnym, atomowo zapisywanym stanem urzadzenia, a nie czescia kampanii.
- D2. Kazde aktywne ustawienie ma rzeczywistego konsumenta i mozliwosc bezpiecznego wycofania nieudanej zmiany.
- D3. Ustawienia geometrii i trybu okna respektuja mozliwosci platformy.
- D4. Audio, sterowanie i dostepnosc zmieniaja odpowiednie systemy, nie tylko etykiete UI.
- D5. Wybor jezyka staje sie aktywny dopiero z pelnym kontraktem lokalizacji.
- Powod i skutek: menu nie obiecuje martwych opcji i nie miesza preferencji urzadzenia z zapisem kampanii.
- Odwolania: docs/Ostatni_Pomost_architektura_Godot.txt - ustawienia; README.md - uruchamianie.

## ARD-0050 - Ponowienie tutorialu i naprawa kombinezonu

- Domena: tutorialowa wyprawa
- Status / aktywny zakres: Obowiazuje; D1-D2
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0007/D3; ARD-0022/D7; ARD-0023/D4 | Zastapiona przez: brak
- D1. W tutorialowej wyprawie wyczerpanie tlenu resetuje tylko lokalna sesje; po tutorialu porazka korzysta z normalnego kontraktu smierci lub ratunku.
- D2. Naprawa jest zablokowana podczas holowania; poza holowaniem zuzywa jeden ladunek i emituje halas tylko wtedy, gdy nurek ma zestaw i ladunek, kombinezon jest uszkodzony, a naprawa faktycznie sie powiedzie. Odrzucona albo zerowa proba nie mutuje sesji.
- Powod i skutek: tutorial jest powtarzalny bez korupcji kampanii, a lokalna sesja nie nalicza kosztu ani halasu za niewykonana akcje.
- Odwolania: ARD-0007; ARD-0023; docs/Ostatni_Pomost_architektura_Godot.txt - tutorial i wynik wyprawy.

## ARD-0051 - Artefakt pozostaje odzyskiwalny

- Domena: artefakty i porazka
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0027/D4 | Zastapiona przez: brak
- D1. Obowiazkowy artefakt ma dokladnie jedna osiagalna droge odzyskania do chwili bezpiecznego zaliczenia w kampanii.
- D2. Gdy Operator przejmuje wynik wyprawy, artefakt wraca do swiata jako trwaly pakiet do odzyskania, zamiast znikac lub byc zaliczony podwojnie.
- D3. Naprawa starszego zapisu jest atomowa i idempotentna; nie tworzy dodatkowej kopii artefaktu.
- Powod i skutek: porazka zmienia koszt i droge odzyskania, ale nie moze uczynic kampanii niemozliwa do dokonczenia.
- Odwolania: docs/OgolnyZarys.txt - artefakty; docs/Ostatni_Pomost_architektura_Godot.txt - odzysk i migracja.

## ARD-0052 - Kolizja runtime jest kanonem fizycznym

- Domena: swiat i fizyka
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0013/D3 | Zastapiona przez: brak
- D1. Reprezentacja kolizji uzywana przez runtime jest kanonicznym zrodlem przejezdnosci i granic fizycznych.
- D2. Warstwa wizualna nie definiuje samodzielnie fizyki.
- D3. Zmiana geometrii lub generatora wymaga zsynchronizowania i zweryfikowania reprezentacji fizycznej.
- Powod i skutek: wyglad przejscia i mozliwosc przejscia nie moga opierac sie na roznych mapach.
- Odwolania: ARD-0013; ARD-0059; docs/Ostatni_Pomost_architektura_Godot.txt - mapa i kolizje.

## ARD-0053 - Smierc nurka przed ekonomia rozliczenia

- Domena: porazka wyprawy
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0044/D2 | Zastapiona przez: brak
- D1. Terminalna smierc nurka jest zatwierdzana przed konsumentami ekonomii dnia.
- D2. Skutek jest stosowany dokladnie raz.
- D3. Telemetria lub raport porazki nie moze zalezec od dalszego istnienia rekordu usunietej postaci.
- Powod i skutek: martwy nurek nie zuzywa zasobow ani nie wykonuje pracy w tym samym rozliczeniu.
- Odwolania: ARD-0044; docs/Ostatni_Pomost_architektura_Godot.txt - kolejnosc konca dnia.

## ARD-0054 - Priorytet racji dla nurka

- Domena: racje
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0044/D3 | Zastapiona przez: brak
- D1. Gdy wybrano polityke DIVER_PRIORITY i plan wskazuje poprawnego, zyjacego nurka, przydzial racji rozpatruje go jako pierwszego odbiorce.
- D2. W tej polityce dzien bez wyprawy albo bez poprawnego nurka korzysta z jawnego grupowego wariantu HALF, a nie z fikcyjnego odbiorcy.
- D3. Dystrybucja jest stabilna i atomowa; dokladne koszty i skutki naleza do produktu i danych.
- Powod i skutek: kolejnosc UI nie moze pozbawic nurka zasobu potrzebnego do wykonanej wyprawy.
- Odwolania: ARD-0058; docs/OgolnyZarys.txt - racje; docs/Ostatni_Pomost_architektura_Godot.txt - rozliczenie dnia.

## ARD-0055 - Historyczne zakonczenie Odejscie

- Domena: zakonczenie kampanii
- Status / aktywny zakres: Zastapione; brak
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0029/D5; ARD-0043/D5 | Zastapiona przez: ARD-0077/calosc
- D1. Osiagniecie wyniku koncowego odblokowuje mozliwosc wyjazdu, ale nie wykonuje automatycznie odplywu.
- D2. Faktyczne opuszczenie osady jest jawna decyzja gracza podjeta na granicy Kroniki.
- D3. Przy najwyzej dwoch zywych nikt nie odchodzi, a jednorazowe zatwierdzenie Kroniki nie pozostawia stanu oczekujacego ani automatycznego odplywu po pozniejszym wzroscie populacji; pozniejsze wyslanie kogos wymaga osobnej widocznej decyzji.
- Powod i skutek: gracz rozroznia gotowosc do zakonczenia od nieodwracalnego finalu kampanii.
- Odwolania: ARD-0029; docs/OgolnyZarys.txt - zakonczenie; docs/Ostatni_Pomost_architektura_Godot.txt - Kronika.

## ARD-0056 - Centralne bramy pracy i nurkowania

- Domena: dostepnosc ocalalych
- Status / aktywny zakres: Czesciowo zastapione; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0068/D4
- D1. Kanoniczne predykaty domenowe rozstrzygaja, czy ocalaly moze pracowac i nurkowac.
- D2. Wszystkie komendy i UI korzystaja z tych samych predykatow.
- D3. Dawny stan RESTING pozostaje tylko zgodnoscia starszego kontraktu i nie tworzy nowej domeny; komunikat ma odpowiadac rzeczywistej blokadzie.
- D4. Dawne kryterium odzyskania po zmeczeniu zostalo zastapione modelem rzeczywistej pracy ARD-0068.
- Powod i skutek: scena nie dopuszcza czynnosci, ktora resolver pozniej odrzuci z innej przyczyny.
- Odwolania: ARD-0068; docs/Ostatni_Pomost_architektura_Godot.txt - stan zalogi.

## ARD-0057 - Historyczny globalny model tempa

- Domena: praca
- Status / aktywny zakres: Zastapione; brak
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0027/D5 | Zastapiona przez: ARD-0068/calosc
- D1. Historycznie binarna bramka can_work byla wspolna, a ulamek work_efficiency, globalne tempo i integralnosc skalowaly tylko polow oraz automatyczna naprawe; pozostale prace byly dyskretne.
- D2. Historycznie globalne tempo zmienialo zmeczenie przydzielonych pracownikow, z osobnym wyjatkiem nurka, lecz nie ustanawialo Napiecia ani ogolnego ryzyka wypadku.
- Powod i skutek: wpis pozostaje wylacznie zapisem odrzuconej granicy; nowych funkcji nie wolno na niej budowac.
- Odwolania: ARD-0068.

## ARD-0058 - Niedobor racji nie zuzywa jedzenia

- Domena: racje i transakcje
- Status / aktywny zakres: Obowiazuje; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0044/D4 | Zastapiona przez: brak
- D1. Nieudana proba przydzialu racji nie zmniejsza zapasu jedzenia.
- D2. Grupa probuje przejsc z pelnej racji na polowiczna wedlug jednej jawnej reguly.
- D3. Polowiczny wariant jest rozliczany dla grupy atomowo, a wynik jest wspoldzielony przez konsumentow.
- Powod i skutek: brak zasobu nie pozostawia czesciowo pobranego kosztu ani roznych wersji wyniku w UI i ekonomii.
- Odwolania: ARD-0054; docs/Ostatni_Pomost_architektura_Godot.txt - racje.

## ARD-0059 - Ziarno nie zmienia geometrii gameplayowej

- Domena: mapa i kompatybilnosc
- Status / aktywny zakres: Czesciowo zastapione; D1, D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0013/D4; ARD-0029/D6 | Zastapiona przez: ARD-0092/D3,D5
- D1. Ziarno prezentacji lub sesji nie zmienia kanonicznej geometrii, tras ani osiagalnosci obiektow gameplayowych.
- D2. Migracja zachowuje znaczenie zapisanych WorldDelta i stabilnych identyfikatorow.
- D3. Zmiana topologii swiata albo semantyki ziarna wymaga osobnej decyzji o kompatybilnosci.
- Powod i skutek: ten sam zapis nie prowadzi do innego ukladu fizycznego po zmianie efektow wizualnych.
- Odwolania: ARD-0013; ARD-0052; docs/Ostatni_Pomost_architektura_Godot.txt - mapa i persistence.

## ARD-0060 - Kopia produktu nie wymysla mechanik

- Domena: tresci i zakres
- Status / aktywny zakres: Obowiazuje; D1-D2
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Teksty produktu i interfejsu opisuja tylko aktywne przyczyny, narzedzia i skutki albo jawnie oznaczony kierunek docelowy.
- D2. Nazwa narracyjna nie ustanawia sama mechaniki radia, holowania, udzwigu, loadoutu ani innego systemu.
- Powod i skutek: jezyk nie tworzy falszywej obietnicy ani konkurencyjnej specyfikacji.
- Odwolania: ARD-0027; docs/OgolnyZarys.txt - statusy funkcji.

## ARD-0061 - Glos Miry wynika z osi czasu intro

- Domena: intro i dostepnosc
- Status / aktywny zakres: Zastapione; brak
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0087/calosc
- D1. Autorytatywna os czasu intro wyzwala kwestie i napisy Miry.
- D2. Napisy sa kanonicznym tekstem; syntetyczne nagranie jest jawnie traktowane jako material produkcyjny, nie zrodlo prawdy.
- D3. Brak lub blad audio nie zatrzymuje przeplywu intro.
- Powod i skutek: narracja pozostaje zsynchronizowana i dostepna niezaleznie od warstwy dzwiekowej.
- Odwolania: ARD-0047; ARD-0069; docs/Ostatni_Pomost_architektura_Godot.txt - intro.

## ARD-0062 - Baza najpierw pokazuje swiat

- Domena: interfejs bazy
- Status / aktywny zakres: Czesciowo zastapione; D2-D4
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0068/D5; ARD-0090/D1
- D1. Glowny widok bazy zachowuje pierwszenstwo swiata nad stale otwartymi panelami.
- D2. Panel jest kontekstowy i pokazuje prawdziwy stan, skutek oraz blokade wybranego obiektu.
- D3. Zamkniecie panelu i fokus wejscia maja jeden spojny kontrakt.
- D4. UI deleguje decyzje do systemow domenowych i nie utrzymuje alternatywnego stanu.
- D5. Dawna prezentacja globalnego tempa zostala zastapiona lokalnym modelem pracy ARD-0068.
- Powod i skutek: warstwa interakcji nie zaslania podstawowej przestrzeni gry i nie dubluje logiki.
- Odwolania: ARD-0068; docs/OgolnyZarys.txt - doswiadczenie bazy; docs/Ostatni_Pomost_architektura_Godot.txt - UI bazy.

## ARD-0063 - Niezmienna migawka oferty zdarzenia

- Domena: zdarzenia i zapis
- Status / aktywny zakres: Czesciowo zastapione; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0032/D4 | Zastapiona przez: ARD-0092/D3-D4
- D1. Wylosowana oferta jest typowana, samowystarczalna i niezmienna do chwili rozliczenia.
- D2. Historia przechowuje zamrozona tozsamosc i informacje potrzebne do cooldownu.
- D3. Kazda poprawna oferta zawiera jawny, walidowany i faktycznie dostepny fallback_choice_id; niepoprawny kandydat zapisu jest odrzucany, a nie cicho rozstrzygany fallbackiem.
- D4. Migracja starego zapisu atomowo i idempotentnie zachowuje sens oferty albo odrzuca niejednoznaczny stan zamiast go zgadywac.
- Powod i skutek: zmiana danych zdarzenia po zapisie nie zmienia juz przedstawionej graczowi decyzji.
- Odwolania: ARD-0032; docs/Ostatni_Pomost_architektura_Godot.txt - zdarzenia i migracje.

## ARD-0064 - Zamowienie warsztatu jest trwalym zobowiazaniem

- Domena: warsztat
- Status / aktywny zakres: Czesciowo zastapione; D1-D3
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0030/D2 | Zastapiona przez: ARD-0068/D4
- D1. Zamowienie warsztatu jest trwalym elementem FIFO o stabilnej tozsamosci i zarezerwowanym koszcie.
- D2. Resolver wykonuje zamrozony kontrakt zamowienia, nie biezaca wersje receptury.
- D3. Blad celu lub rozliczenia zachowuje zamowienie i rezerwacje bez zmian; ewentualne anulowanie jest osobna, jawna akcja domenowa i nie moze byc niejawna sciezka obslugi bledu.
- D4. Dawne zalozenie przepustowosci bez czesciowego postepu zostalo zastapione przez ARD-0068.
- Powod i skutek: zmiana danych lub wczytanie gry nie zmienia ceny juz przyjetego zlecenia.
- Odwolania: ARD-0068; docs/Ostatni_Pomost_architektura_Godot.txt - warsztat i zapis.

## ARD-0065 - Preflight, migracja, postflight

- Domena: walidacja zapisu
- Status / aktywny zakres: Czesciowo zastapione; D1, D4
- Zatwierdzenie: 2026-08-08
- Relacje: Zastepuje: ARD-0045/D2 | Zastapiona przez: ARD-0092/D4
- D1. Jeden walidator jest wlascicielem oceny kandydata zapisu.
- D2. Preflight jest swiadomy wersji schematu i nie wymaga od starego zapisu pol, ktore dopiero ma utworzyc migracja.
- D3. Migracja pracuje na odseparowanym kandydacie, a postflight waliduje pelny graf nowego stanu.
- D4. Blad prowadzi do kontrolowanego odrzucenia lub jawnego fallbacku, nie do czesciowej mutacji GameState.
- Powod i skutek: walidator nie blokuje poprawnej migracji ani nie przepuszcza polowicznie naprawionego zapisu.
- Odwolania: ARD-0019; ARD-0045; docs/Ostatni_Pomost_architektura_Godot.txt - pipeline zapisu.

## ARD-0066 - Hybryda 2.5D/3D bez zmiany domeny

- Domena: prezentacja bazy i swiata
- Status / aktywny zakres: Obowiazuje; D1-D4
- Zatwierdzenie: 2026-08-09; zmienione: 2026-08-15
- Relacje: Zastepuje: ARD-0006/D4; ARD-0035/D2 | Zastapiona przez: brak
- D1. Swiat i obiekty bazy moga byc prezentowane przestrzennie w 3D, a interakcja i panele pozostaja warstwa 2D.
- D2. GameState, systemy domenowe i kontrakty zapisu nie zmieniaja znaczenia wskutek tej prezentacji.
- D3. Widok, hitboxy i animacje odzwierciedlaja kanoniczny stan, nie sa jego wlascicielem.
- D4. Ustawienia jakosci zmieniaja koszt prezentacji, a nie zasady gry.
- Powod i skutek: modernizacja obrazu nie wymaga drugiego modelu kampanii ani migracji bez zmiany semantyki danych.
- Odwolania: ARD-0035; ARD-0071; docs/Ostatni_Pomost_architektura_Godot.txt - warstwy 3D i 2D.

## ARD-0067 - Historyczny wyjatek schematu przed premiera

- Domena: zapis
- Status / aktywny zakres: Czesciowo zastapione; D2
- Zatwierdzenie: 2026-08-15
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0068/D1
- D1. Przed pierwszym wydaniem dopuszczono domkniecie niewydanego schematu 10 bez nowego numeru, ale tylko z zachowaniem pelnej migracji 9 -> 10, atomowosci, walidacji i wymaganego pokrycia; pozostanie przy schemacie 10 zostalo zastapione przez ARD-0068.
- D2. Przedpremierowy wyjatek nie jest precedensem: po ustanowieniu kolejnej granicy dalsza zmiana semantyki zapisu podlega zwyklemu wersjonowaniu ARD-0045.
- Powod i skutek: mozna bylo domknac niewydany pakiet bez pustej wersji, lecz nigdy kosztem ochrony wspieranych zapisow ani przyszlych zasad ewolucji.
- Odwolania: ARD-0068.

## ARD-0068 - Lokalne tempo budynku i dziennik rzeczywistej pracy

- Domena: praca, produkcja i zapis
- Status / aktywny zakres: Czesciowo zastapione; D1, D4, D6
- Zatwierdzenie: 2026-08-09
- Relacje: Zastepuje: ARD-0057/calosc; ARD-0025/D4; ARD-0029/D3,D7; ARD-0036/D4; ARD-0044/D7-D8; ARD-0045/D4; ARD-0056/D4; ARD-0062/D5; ARD-0064/D4; ARD-0067/D1 | Zastapiona przez: ARD-0084/D2-D3; ARD-0092/D3-D5
- D1. Tempo i napiecie sa stanem lokalnym budynku, a nie globalnym mnoznikiem calego dnia.
- D2. Jeden dziennik rzeczywiscie wykonanej pracy jest zrodlem skutkow dla zmeczenia, napiecia, nadziei, doswiadczenia i raportu.
- D3. Sam przydzial nie jest praca; realna prace potwierdza zdarzenie zaakceptowane przez wlasciciela domeny, bez uniwersalnego wymogu dodatniej wartosci liczbowej. Dodatni wynik jest wymagany tylko tam, gdzie stanowi kontrakt danej domeny, w szczegolnosci dla postepu produkcji.
- D4. Kolejka FIFO moze zachowywac czesciowy postep, lecz postep wymaga dodatniej pracy zaakceptowanej przez wlasciciela domeny.
- D5. Zmiana wprowadza jawna kolejna wersje schematu i migracje zachowujaca znaczenie starszego stanu.
- D6. Projekt Swit i ciezki odzysk uzywaja stalej procedury Normalnej zamiast lokalnie wybranego tempa budynku.
- Powod i skutek: kazdy budynek rozlicza wlasny postep, a wszystkie konsekwencje pracy korzystaja z jednego faktu wykonania.
- Odwolania: docs/OgolnyZarys.txt - sens pracy; docs/Ostatni_Pomost_architektura_Godot.txt - resolver, warsztat i migracja.

## ARD-0069 - Intro jako niezalezny prerender 2D

- Domena: intro
- Status / aktywny zakres: Obowiazuje; D1-D4
- Zatwierdzenie: 2026-08-09
- Relacje: Zastepuje: ARD-0047/D3 | Zastapiona przez: brak
- D1. Intro jest niezaleznym, autorsko przygotowanym prerenderem 2D.
- D2. Ma ustalony rytm i nie zalezy od biezacej sceny bazy ani ustawien jakosci swiata 3D.
- D3. Zmiana materialu intro jest jawna zmiana autorska, a nie przypadkowym skutkiem refaktoru runtime.
- D4. Kontrakty narracji, napisow, pominiecia i przejscia do kampanii pozostaja wspolne.
- Powod i skutek: wydajnosc i ewolucja widoku bazy nie zmieniaja wprowadzenia ani zapisu kampanii.
- Odwolania: ARD-0046; ARD-0047; ARD-0061; docs/OgolnyZarys.txt - intro.

## ARD-0070 - Jeden wlasciciel kazdego szczegolu dokumentacji

- Domena: role dokumentow
- Status / aktywny zakres: Czesciowo zastapione; D1-D3, D5-D6
- Zatwierdzenie: 2026-08-09
- Relacje: Zastepuje: ARD-0042/D1,D4,D8 | Zastapiona przez: ARD-0086/D4
- D1. Kazdy szczegol ma jedno kanoniczne miejsce; pozostale dokumenty moga zawierac tylko niezbedne streszczenie i odnosnik.
- D2. .ai/PROJECT_CONTEXT.md przechowuje krotka, potwierdzona migawke runtime; .ai/DECISIONS.md - trwale rozstrzygniecia i rationale.
- D3. docs/OgolnyZarys.txt jest wlascicielem znaczenia widocznego dla gracza, a docs/Ostatni_Pomost_architektura_Godot.txt - technicznego mapowania systemow, stanu, zapisu i ryzyka testowego.
- D4. README.md jest onboardingiem, a AGENTS.md opisuje proces czytania, pracy, weryfikacji i aktualizacji dokumentow.
- D5. .ai/DECISIONS.md nie przechowuje pola Wdrozenie ani biezacego statusu realizacji; potwierdzony stan wykonania nalezy do .ai/PROJECT_CONTEXT.md.
- D6. Kazdy dokument ma lokalny kontrakt wpisu; przy redakcji zastanej sekcji cudzy szczegol przenosi sie do wlasciciela, a w dawnym miejscu pozostawia tylko potrzebna konsekwencje i odwolanie.
- Powod i skutek: zmiana funkcji nie wymaga kopiowania pelnej specyfikacji do wszystkich plikow i ma jedno miejsce do aktualizacji.
- Odwolania: AGENTS.md - Dokumentacja; naglowki rol wszystkich pieciu dokumentow.

## ARD-0071 - Jedno wspolne zrodlo swiatla kierunkowego bazy

- Domena: oswietlenie bazy
- Status / aktywny zakres: Czesciowo zastapione; D2-D4
- Zatwierdzenie: 2026-08-09; zmienione: 2026-08-15
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0094/D1
- D1. Aktywny widok bazy korzysta z jednego wspolnego kierunkowego zrodla swiatla i jednego spojnego modelu cienia. Wyjatkiem sa dokladnie trzy krotkozasiegowe, bezcieniowe oprawy uslugowe `OmniLight3D`, zamocowane w wyznaczonych punktach gornej konstrukcji; po utrwalonym J-7 oswietlaja wyłącznie poklad i jego aktywne warianty. Nie powstaje drugie slonce, inny lokalny fill light ani lokalne swiatlo przed J-7.
- D2. Pogoda moze zmieniac relacje swiatla bezposredniego, otoczenia i cienia, ale zachowuje czytelnosc gameplayowa; reflektory J-7 nie zmieniaja jej parametrow ani stanu morza, deszczu i fal.
- D3. Poziom jakosci zmienia koszt renderowania, a nie znaczenie pogody, zasady gry ani stan zapisu; we wszystkich profilach pozostaje ten sam czytelny sygnal trzech reflektorow J-7.
- D4. Kontrakt nie zmienia stanu kampanii, zapisu, niezaleznego modulu nurkowania ani prerenderowanego intro.
- Powod i skutek: oswietlenie bazy nie tworzy konkurencyjnych slonc ani roznych semantyk miedzy presetami, lecz odzyskane zasilanie ma widoczny, lokalny skutek na platformie zamiast niemal niewidocznej globalnej korekty ambientu.
- Odwolania: ARD-0024; ARD-0066; ARD-0069; docs/Ostatni_Pomost_architektura_Godot.txt - oswietlenie i jakosc.

## ARD-0072 - Certyfikat pelnej drogi odzyskania zasobu

- Domena: nurkowanie, progresja i narzedzia projektowe
- Status / aktywny zakres: Zastapione w calosci
- Zatwierdzenie: 2026-08-09
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0102/D8-D9
- D1. Osiagalnosc autorskiego zasobu oznacza swiadectwo konkretnej sekwencji wejscie -> interakcje -> wymagany ladunek -> normalna aktywna lina, a nie sam dystans, wspolny komponent mapy ani ratunek Operatora.
- D2. Swiadectwo rozdziela FEASIBLE od SAFE; pierwszy wynik wymaga zywego nurka i tlenu wiekszego od zera po pelnej interakcji liny, drugi dodatkowo obowiazkowej rezerwy z walidowanej polityki.
- D3. Twardy wynik uzywa kanonicznej kolizji runtime, rzeczywistego gabarytu nurka, kierunkowych pradow, czasu, tlenu, ciezaru, slotow, narzedzi, temperatury, kombinezonu, przeszkod oraz aktywnych zagrozen. Planner moze wskazac kandydata, lecz certyfikat nadaje dopiero deterministyczny replay wspolnych regul.
- D4. Zwykly kontener gwarantuje co najmniej jedna wybrana sztuke i raportuje maksimum; pickup oraz cel tutorialowy, fabularny lub ratunkowy gwarantuja caly obiekt wymagany przez kontrakt.
- D5. Ilosciowe zapytanie projektanta jawnie okresla, czy caly zestaw ma wrocic w jednej wyprawie, czy wymagania sa niezalezne, oraz czy wolno laczyc kilka zrodel. Wynik nie moze zsumowac niezaleznych sukcesow i nazwac ich jedna wyprawa.
- D6. Najwczesniejszy profil progresji przechowuje wylacznie legalne wejscia do istniejacego buildera ExpeditionSetup: osobne poziomy Stacji i Warsztatu, sprzet, nurka, publiczne trudnosci oraz utrwalone wczesniej boje i skroty. Nie zamraza drugiej kopii tlenu, wag ani mnoznikow.
- D7. Publiczne presety easy, standard i hard sa bramka gwarancji dla przypisanego profilu; custom pozostaje pelna diagnoza bez obietnicy sukcesu. Profil nie moze tworzyc kola, w ktorym zasob wymagany do ulepszenia jest odzyskiwalny dopiero po tym ulepszeniu.
- D8. Definicje profili, zapytan, polityka, raport i swiadectwo sa danymi projektowymi poza GameState, WorldDelta, DiveResult i ExpeditionSetup; nie zmieniaja semantyki istniejacego zapisu ani wersji schematu.
- D9. Nowy lub przesuniety cel gameplayowy nie przechodzi twardej walidacji bez automatycznego pokrycia wszystkich publicznych presetow przypisanego etapu i czytelnego kodu przyczyny dla kazdej porazki.
- Powod i skutek: projektant oraz automatyczny agent moga rozmieszczac skonczone zasoby tylko w miejscach, dla ktorych istnieje powtarzalny dowod zebrania i powrotu odpowiednim etapem sprzetu, bez dublowania regul wyprawy i bez reinterpretacji zapisow.
- Odwolania: ARD-0002; ARD-0017; ARD-0021; ARD-0043; ARD-0051; ARD-0052; ARD-0059; docs/OgolnyZarys.txt - sekcja 6.3; docs/Ostatni_Pomost_architektura_Godot.txt - modul nurkowania i walidacja.

## ARD-0073 - Typowane, deterministyczne choroby i epidemie

- Domena: zdrowie mieszkancow, rozliczenie dnia i zapis
- Status / aktywny zakres: Czesciowo zastapione; D1-D7, D9-D10
- Zatwierdzenie: 2026-08-09
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0092/D3-D5
- D1. Aktywna choroba jest typowanym przypadkiem rownoleglym do urazu, przydzialu i statusu mieszkanca. Legacy `Status.SICK` oraz `disease_states` pozostaja zachowane bez reinterpretacji i nie sa fundamentem nowej domeny.
- D2. Ekspozycja, transmisja, progresja, terapia, remisja i odpornosc sa projektowane na niezmiennym snapshotcie, stabilnie sortowane i stosowane raz. Nowy przypadek nie jest zrodlem transmisji tej samej nocy, a ten sam stan, dzien i konfiguracja daja ten sam wynik po wczytaniu.
- D3. Znane przypadki korzystaja ze wspolnej opieki medycznej przed krokiem chorob, racje i zmeczenie dostarczaja fakty do progresji, a utrata zdrowia choroby poprzedza jeden centralny krok zgonow. Narażenie przyjete podczas biezacej wyprawy nie jest leczone wstecz, a nowy etap nie anuluje pracy juz wykonanej z zamrozonego planu.
- D4. Modul nurkowania moze wytworzyc wylacznie typowane narażenie w `DiveResult`; dopiero atomowe przyjecie wyniku przenosi je do kandydata kampanii. Interakcja zrodla jest jawna, opcjonalna i nie wystepuje w tutorialu.
- D5. Jeden system opieki medycznej jest wlascicielem kwalifikacji, stabilnego triage, pojemnosci, kosztu i efektu Lecznicy dla podgladu oraz wykonania. Jedna osoba zajmuje jeden slot i zuzywa najwyzej jedna dawke dziennie niezaleznie od polaczenia urazu i choroby.
- D6. Izolacja awaryjna jest decyzja planu dostepna bez budynku i leku kosztem pracy oraz nurkowania; formalna Izolatka od poziomu III usuwa transmisje w granicy swojej pojemnosci. Stan epidemii przechowuje tylko fakty niederywowalne i emituje dokladna, niemnozona przez ogolny profil delte Nadziei -6 przy rozpoczeciu oraz +4 przy opanowaniu, kazda dokladnie raz.
- D7. Osi trudnosci pozostaje osiem. Presja i zdrowienie chorob należa do osi `society`; nowy zamrozony modyfikator jest objety wersja balansu i podpisem konfiguracji.
- D8. Nowa semantyka jest granica schematu 12. Migracja tworzy pusty kanoniczny stan chorob oraz bezpieczne defaulty, zachowuje opaque legacy bez mapowania, przechodzi wspolny preflight/postflight i nie mutuje odrzuconego zrodla.
- D9. Choroba nie ma osobnego rzutu smierci. Stosuje jawna delte zdrowia, a centralny resolver terminalizuje osobe najwyzej raz. Raport jest niezmienna prezentacja przyczyn i skutkow, natomiast PressureState konsumuje typowane metryki i stan epidemii zamiast parsowac raport.
- D10. Strojalne reguly pochodza z walidowanych definicji, a aktywny przypadek zamraza wersje i podpis potrzebny do zachowania znaczenia po zmianie danych. UI deleguje do wspolnych analiz choroby oraz opieki i nie utrzymuje drugiego modelu.
- Powod i skutek: choroba tworzy czytelny lancuch ryzyka, reakcji i konsekwencji bez nocnej loterii, kaskady tej samej nocy, dublowania leczenia ani cichej zmiany wspieranych zapisow.
- Odwolania: ARD-0002; ARD-0003; ARD-0004; ARD-0019; ARD-0039; ARD-0044; ARD-0045; ARD-0053; ARD-0056; ARD-0065; ARD-0068; docs/OgolnyZarys.txt - choroby i epidemie; docs/Ostatni_Pomost_architektura_Godot.txt - choroby, resolver i schema 12.

## ARD-0074 - Wersjonowany katalog rozmieszczenia swiata V7

- Domena: swiat nurkowania, authoring i kompatybilnosc zapisu
- Status / aktywny zakres: Zastapione; brak
- Zatwierdzenie: 2026-08-09
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0075/calosc
- D1. Produkcyjny generator swiata V7 pobiera polozenia istniejacych kontenerow i wolnostojacych pickupow z dokladnie jednego walidowanego katalogu rozmieszczenia; kod generatora nie utrzymuje rownoleglych offsetow ani produkcyjnego fallbacku.
- D2. Katalog zmienia wylacznie autorski offset celu przy zachowaniu stabilnego ID, rodzaju, zawartosci i landmarku. Geometria, landmarki, polaczenia, prady, zagrozenia, ratunek, ciezkie obiekty oraz dodawanie i usuwanie celow pozostaja poza ta granica.
- D3. Fizyczna pozycja nadal wynika z kanonicznej kolizji runtime; publikacja certyfikuje finalny punkt po korekcie, a katalog zapisuje tylko pozycje autorska.
- D4. Schemat zapisu 13 ustanawia `WorldBlueprint` V7 i jawna tozsamosc rewizji layoutu. Statyczne rozmieszczenie jest wyprowadzane z certyfikowanego katalogu, natomiast trwaly stan rozliczenia celu pozostaje w `WorldDelta` pod stabilnym ID.
- D5. Migracja 12 -> 13 przyjmuje wylacznie kanoniczny V6, kompiluje V7 z tego samego seeda i zachowuje caly `WorldDelta`. Rozliczony cel nie odradza sie, a nierozliczony cel o tym samym ID moze pojawic sie w nowym miejscu.
- D6. `lost_backpacks` i `dropped_loot_piles` zachowuja dokladne zapisane wspolrzedne; rewizja katalogu nie przyciaga ich do statycznego celu ani landmarku.
- D7. W ramach V7 kolejna certyfikowana rewizja moze zmienic tylko dozwolone offsety. Wczytanie poprawnego schematu 13 uzgadnia wyprowadzony blueprint z aktualna rewizja katalogu, zachowujac D5-D6; jest to jawna semantyka schematu 13, nie naprawa nieznanego stanu.
- D8. Publikacja wymaga twardego `SAFE` dla easy, standard i hard dla kazdego zmienionego celu w przypisanym etapie oraz pelnej bramki autorskiej na wygenerowanym kandydacie. `FEASIBLE`, `FAIL`, brak celu albo niepelna macierz blokuja promocje.
- D9. Publikacja jest atomowa: walidacja, certyfikacja kandydata, promocja i ponowna certyfikacja produkcyjnego odczytu stanowia jedna granice; porazka pozostawia poprzedni katalog jako jedyne zrodlo produkcyjne.
- D10. Historyczny katalog V6 sluzy wylacznie uwierzytelnieniu migracji. Zmiana zestawu, ID, rodzaju, landmarku, zawartosci albo geometrii wymaga kolejnej wersji blueprintu, rozstrzygniecia kompatybilnosci i odpowiedniej granicy zapisu.
- Powod i skutek: projektant moze bezpiecznie poprawiac rozmieszczenie istniejacych zasobow bez dublowania pozycji i bez kasowania postepu gracza, a zmiana o wiekszym znaczeniu nie przechodzi jako niewidoczna edycja danych.
- Odwolania: ARD-0013; ARD-0019; ARD-0025; ARD-0045; ARD-0052; ARD-0059; ARD-0065; ARD-0072; docs/OgolnyZarys.txt - sekcje 6.3 i 7; docs/Ostatni_Pomost_architektura_Godot.txt - swiat, authoring i persistence.

## ARD-0075 - Scena Godot jako jedyne zrodlo swiata podwodnego

- Domena: swiat nurkowania, authoring, runtime i kompatybilnosc zapisu
- Status / aktywny zakres: Czesciowo zastapione; D3, D7-D8
- Zatwierdzenie: 2026-08-10
- Relacje: Zastepuje: ARD-0074/calosc | Zastapiona przez: ARD-0076/D9-D10; ARD-0085/D5; ARD-0102/D1-D2,D4,D6,D11-D12
- D1. `res://scenes/diving/UnderwaterMap.tscn` jest jedynym produkcyjnym zrodlem statycznego swiata podwodnego. Generator kodowy, katalog `.tres`, draft i wykonywany overview nie moga utrzymywac rownoleglej topologii ani rozmieszczenia.
- D2. Regiony, landmarki, wejscie, wyjscie, polaczenia, prady, kontenery, pickupy, zagrozenia, cele ratunkowe, ciezkie obiekty, boje, bramy skrotow, przeszkody i dekoracje sa instancjami scen authoringowych w zwyklym drzewie Godot. Projektant moze je dodawac, usuwac, przesuwac, obracac i skalowac zgodnie z walidowanym kontraktem danego typu.
- D3. Kazdy obiekt mapy ma stabilne, unikalne `Object ID`, a kazde polaczenie stabilne, unikalne `Connection ID`; przestrzenie ID obiektow i polaczen sa rozdzielone. Trwaly `WorldDelta` odnosi postep wylacznie do stabilnych ID, nie do sciezki noda, kolejnosci dziecka ani nazwy scenowej.
- D4. `UnderwaterMapSceneCompiler` deterministycznie kompiluje zapisana scene do wykonywalnego `WorldBlueprint`. Blueprint jest migawka runtime i zapisu, a nie drugim miejscem authoringu; `RuntimeDynamic` jest wylacznie kontenerem instancji sesji i nigdy nie zapisuje zmian z powrotem do sceny.
- D5. Bazowe warstwy PNG oraz `world_collision_grid.png` pozostaja wspolna makrogeometria i referencja wizualna. Edytowalne `MapObstacle` nakladaja dodatkowe wielokaty blokujace; walidator i `ContinuousDiveWorld` uzywaja dokladnie tego samego rasteryzatora transformowanych przeszkod. `MapObstacle` bez `Visual Scene` jest wylacznie jawna korekta kolizji obiektu juz narysowanego w bazowej warstwie. Widoczny prefab nie jest automatycznie kolizja.
- D6. Kazdy obiekt moze wskazac `Visual Scene` z rootem `Node2D`; dla `MapDecoration` jest ona wymagana, a dla pozostalych typow opcjonalna. Prefab wizualny jest widoczny w edytorze i instancjonowany w runtime z ta sama kolejnoscia transformacji, lecz nie moze zawierac nodow authoringu mapy ani aktywnej fizyki; kolizje sa odrzucane podczas authoringu i wylaczane defensywnie w runtime.
- D7. Dane gameplayowe, definicje i zawartosc pozostaja typowane oraz walidowane. Prefab wizualny nie zastepuje `ItemDefinition`, `ThreatDefinition`, definicji ocalego ani kontraktu interakcji; pozwala zastapic tylko prezentacje obiektu.
- D8. Podpis gameplayowy obejmuje topologie, pozycje, trasy, zawartosc, parametry interakcji, przeszkody, rozmiar swiata, rozmiar chunkow i bazowa maske nawigacji. Nazwy prezentacyjne, kolory, prefab wizualny i jego lokalna transformacja sa poza podpisem. Dekoracje nie zmieniaja podpisu.
- D9. Pelny kontrakt scenowego authoringu, wspolnego rastra, wypiekanych tras i rozdzielenia metadanych prezentacyjnych ustanawia `map_source_version = 2`. Zgodny zapis schematu 14 source-v2 moze odswiezyc pochodny blueprint do biezacej sceny bez kasowania `WorldDelta` tylko wtedy, gdy podpis gameplayowy pozostaje taki sam. Zmiana podpisu oznacza inny statyczny swiat i blokuje kontynuacje tej kampanii zamiast przesuwac dynamiczne rekordy lub reinterpretowac postep po cichu.
- D10. Schemat 14 korzysta z izolowanej przestrzeni plikow `ostatni_pomost_scene_map_*`. Zapisy schematu 13 oraz wczesne pliki schematu 14 source-v1 sa zachowywane na dysku, ale nie sa ladowane ani migrowane do source-v2: pierwsze maja statyczne zrodlo V7, a drugie powstaly przed pelnym kontraktem podpisu i kompilacji sceny. Nowa migracja wymaga osobnej decyzji oraz uwierzytelnialnego mapowania.
- D11. Kompilacja blokuje brak wymaganej grupy, prefab umieszczony poza przypisana galezia authoringu, brak lub duplikat ID, nieznane referencje, brak dokladnie jednego wejscia i wyjscia, obiekt poza mapa, niepelna albo odkotwiczona trase `Curve2D`, dekoracje bez grafiki, niepoprawny prefab, nieprzechodnia pozycje celu oraz brak drogi od wejscia na wspolnym rastrze. Twarda certyfikacja odzyskiwalnosci ARD-0072 pozostaje wymagana dla zmian celu objetych gwarancja produktu.
- D12. Standardowy workflow nie wymaga uruchamiania osobnego narzedzia ani publikacji katalogu: projektant otwiera `UnderwaterMap.tscn`, pracuje na prefabach w widoku 2D, uruchamia `Waliduj mape` w Inspectorze, zapisuje scene i przeprowadza test mapy oraz wymagane testy wyprawy.
- Powod i skutek: swiat widoczny w Godot jest tym samym swiatem, ktory wykonuje gra; projektant korzysta z normalnego authoringu scen i prefabow bez draftu, publikatora i drugiego katalogu pozycji, a postep kampanii pozostaje oddzielony od statycznej mapy.
- Odwolania: ARD-0002; ARD-0013; ARD-0019; ARD-0045; ARD-0052; ARD-0059; ARD-0065; ARD-0072; docs/OgolnyZarys.txt - sekcje 6.3 i 7; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 9, 11 i 13.

## ARD-0076 - Natychmiastowa budowa i rozbudowa

- Domena: budynki, transakcja planowania i zapis
- Status / aktywny zakres: Czesciowo zastapione; D1-D4, D6
- Zatwierdzenie: 2026-08-12
- Relacje: Zastepuje: ARD-0041/D3; ARD-0075/D9-D10 | Zastapiona przez: ARD-0092/D3-D5
- D1. Poprawna komenda budowy albo rozbudowy atomowo pobiera pelny koszt i natychmiast aktywuje docelowy poziom budynku; nie oczekuje na rozliczenie dnia.
- D2. `BuildingSystem` jest jedynym wlascicielem walidacji i tej mutacji. UI tylko wyraza intencje, a `EndOfDayResolver` nie konczy budow ani rozbudow.
- D3. Prezentacja, stanowiska i bierne capabilities odzwierciedlaja nowy poziom bezposrednio po sukcesie komendy; nie istnieje gameplayowy stan budowy oczekujacej ani procentowy postep konstrukcji.
- D4. Nieudana walidacja lub pobranie kosztu nie zmienia zasobow, slotu ani budynku.
- D5. Zmiana wprowadza schemat 15 przy zachowaniu scenowej mapy source-v2, podpisu gameplayowego, izolowanej przestrzeni plikow i odswiezania prezentacyjnego blueprintu. Migracja poprawnego schematu 14 source-v2 konczy kazda juz oplacona budowe lub rozbudowe, czysci stan oczekujacy i zachowuje pozostaly stan bez ponownego kosztu. Schemat 13 i source-v1 pozostaja zachowane, ale niewczytywane.
- D6. Natychmiastowa aktywacja nie wykonuje automatycznie pracy budynku ani skutkow dnia; te nadal wymagaja zamrozonego planu i wlasciwych systemow resolvera.
- Powod i skutek: klikniecie daje od razu jednoznaczny, widoczny rezultat bez fikcyjnego czekania, zachowujac atomowosc kosztu, jeden kanoniczny stan i bezpieczna kompatybilnosc zapisu.
- Odwolania: ARD-0001; ARD-0018; ARD-0019; ARD-0044; ARD-0045; ARD-0065; docs/OgolnyZarys.txt - sekcje 2 i 5; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 4, 6 i 11.

## ARD-0077 - Wspolna Linia jako jeden kregoslup kampanii

- Domena: kampania, tutorial, swiat nurkowania i zapis
- Status / aktywny zakres: Czesciowo zastapione; D1-D2, D4-D8
- Zatwierdzenie: 2026-08-12
- Relacje: Zastepuje: ARD-0029/calosc; ARD-0055/calosc | Zastapiona przez: ARD-0102/D3
- D1. Nowa kampania korzysta z jednego przebiegu Wspolnej Linii: trzy prowadzone dni, J-7, jawne odliczanie Czarnego Frontu, Archiwum, R-3, C-4, wybor energii i Kronika.
- D2. `CampaignProgressionSystem` pozostaje jedynym wlascicielem przejsc aktow, odliczania, finalnej dostepnosci i wyniku; misje, dialogi oraz UI sa konsumentami jego typowanego stanu.
- D3. J-7, Archiwum, R-3 i C-4 sa stalymi, typowanymi urzadzeniami sceny mapy. Ich lokalna interakcja przechodzi przez `DiveResult`, a trwaly skutek przez `WorldDelta`; nie sa przedmiotami plecaka ani luznymi flagami UI.
- D4. Trzydniowy tutorial uzywa zwyklych komend budowy, obsady, racji, Warsztatu, przygotowania wyprawy i wyniku. Natychmiastowa budowa ARD-0076 pozostaje aktywna; tutorial nie wprowadza opoznionego wyjatku konstrukcji.
- D5. Obowiazkowa informacja fabularna jest rozstrzygana przez role Glosu Przystani, Glosu technicznego, biezacego Nurka albo neutralny raport i nie zalezy od przezycia konkretnego zalozyciela po tutorialu.
- D6. Czarny Front ma jeden jawny licznik zmniejszany dokladnie raz na zakonczony dzien. Kryzys, dzien bez wyprawy i nierozstrzygnieta misja nie zatrzymuja go.
- D7. Dawne artefakty Projektu Swit, wieza, Odejscie i automatyczne nastepstwo Kroniki nie sa reinterpretowane jako etapy Wspolnej Linii.
- D8. Zmiana ustanawia nowa, izolowana granice zapisu. Starsze kampanie sa zachowywane, lecz nie sa automatycznie migrowane bez uwierzytelnialnego mapowania decyzji i urzadzen.
- Powod i skutek: gracz otrzymuje jeden czytelny cel i przeplyw od tutoriala do finalu, a kolejne piony korzystaja z tych samych granic swiata, dnia i zapisu zamiast z osobnych flag oraz wyjatkow.
- Odwolania: ARD-0001; ARD-0002; ARD-0007; ARD-0018; ARD-0019; ARD-0020; ARD-0034; ARD-0044; ARD-0059; ARD-0065; ARD-0075; ARD-0076; docs/OgolnyZarys.txt - sekcje 2, 5, 7 i 9-10; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 3, 5, 6, 9-11.

## ARD-0078 - Walka pozostaje lokalna dla wyprawy

- Domena: nurkowanie, zagrozenia i wyposazenie
- Status / aktywny zakres: Obowiazuje; D1-D5
- Zatwierdzenie: 2026-08-12
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Wybor narzedzia, amunicja, cooldown, zdrowie przeciwnika i jego pokonanie sa stanem lokalnej sesji nurkowania.
- D2. Pokonany przeciwnik nie zapisuje trwalej zmiany `WorldDelta` i jest odtwarzany przy kolejnej wyprawie; trwała eksterminacja wymaga osobnej decyzji o swiecie oraz zapisie.
- D3. Nóż pozostaje trwalym, nieutracalnym narzedziem tutorialowym, a pistolet harpunowy zwyklym wytwarzanym i utracalnym wyposazeniem kampanii.
- D4. Harpuny odnawiaja sie na granicy wyprawy i nie sa zasobem magazynu ani stanem kampanii.
- D5. UI i kontroler przekazuja intencje oraz kierunek celowania, natomiast obrazenia, amunicje i trafienie rozstrzyga modul nurkowania.
- Powod i skutek: walka daje wykonywalna obrone podczas eksploracji bez reinterpretacji trwałego swiata, ekonomii amunicji i istniejacych zapisow kampanii.
- Odwolania: ARD-0002; ARD-0007; ARD-0015; ARD-0023; docs/OgolnyZarys.txt - sekcja 6; docs/Ostatni_Pomost_architektura_Godot.txt - sekcja 5.5.

## ARD-0079 - Grywalny pion 1.0 jest rozszerzalnym punktem bazowym

- Domena: rozwój produktu i bramki jakości
- Status / aktywny zakres: Obowiazuje; D1-D5
- Zatwierdzenie: 2026-08-12
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Pion 1.0 obejmuje jeden wykonywalny przebieg od nowej kampanii przez tutorial, planowanie, nurkowanie, Wspólną Linię, wybór energii i Kronikę z możliwością dalszej gry.
- D2. Oznaczenie 1.0 nie zamraża zawartości ani balansu. Kolejne funkcje rozszerzają istniejące granice domenowe albo wymagają jawnego zastąpienia właściwego ARD; nie tworzą równoległego szkieletu kampanii.
- D3. Bramka pionu składa się z importu, szybkiej bramki krytycznych kontraktów, pełnej sekwencyjnej regresji oraz istniejącego pokrycia przepływów kampanii. Nowy długi test nie jest dodawany, jeśli tylko powiela silniejsze testy domenowe i integracyjne.
- D4. Pion można oznaczyć jako potwierdzony dopiero po pełnym przebiegu bez `ERROR`, `SCRIPT ERROR`, pominieć i wycieków raportowanych przy zamykaniu procesu.
- D5. Manualny playtest ocenia odczucie, czytelność i pacing, ale nie zastępuje automatycznych kontraktów stanu, transakcji i zapisu.
- Powod i skutek: projekt otrzymuje stabilny punkt dalszego rozwoju bez fałszywego uznania gry za ostatecznie ukończoną i bez mnożenia kosztownych, redundantnych testów.
- Odwolania: ARD-0022; ARD-0028; ARD-0048; ARD-0077; README.md - testy; docs/Ostatni_Pomost_architektura_Godot.txt - sekcja 13.

## ARD-0080 - Kompetencje sa pasywne, typowane i skladane w domenach

- Domena: rozwoj postaci, baza, nurkowanie i zapis
- Status / aktywny zakres: Czesciowo zastapione; D2-D4
- Zatwierdzenie: 2026-08-12
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0089/D1,D5
- D1. Pierwszy pion umiejetnosci obejmuje osiem pasywnych kompetencji po trzy poziomy; umiejetnosci aktywne nie sa czescia tego kontraktu.
- D2. Poziomy naleza do `SurvivorState`, a katalog ID i przeliczniki do jednego `CompetencySystem`; UI nie posiada kopii regul ani stanu.
- D3. Wydanie poziomu zuzywa istniejacy punkt rozwoju przez bramke `CareerProgressionSystem` i wymaga aktywnego Domu Wspolnoty I.
- D4. Efekty kompetencji sesji nurkowania sa zamrazane w `ExpeditionSetup`; efekty bazy skladaja sie w najmniejszym systemie domenowym z aktualna zdolnoscia osoby do pracy.
- D5. Kompetencje ustanawiaja izolowany schemat zapisu 24. Starsze zapisy pozostaja zachowane i nie sa automatycznie reinterpretowane jako postacie z nowym kontraktem rozwoju.
- Powod i skutek: rozwoj daje czytelne, deterministyczne wybory bez losowych aktywacji, drugiego modelu statystyk i powiazania sesji nurkowania z mutowalnym stanem kampanii.
- Odwolania: ARD-0001; ARD-0002; ARD-0019; ARD-0045; ARD-0065; ARD-0077; docs/OgolnyZarys.txt - sekcja 4; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 5, 8.2 i 11.

## ARD-0081 - Rotacja zalogi laczy ekspedycje lodzia z jawnym odejsciem

- Domena: mieszkancy, baza, poranek, wydarzenia i zapis
- Status / aktywny zakres: Obowiazuje; D1-D7
- Zatwierdzenie: 2026-08-12
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Docelowy pion rotacji zalogi laczy wielodniowe ekspedycje lodzia, kandydatury z powrotu oraz wybrane przez gracza trwale odejscie; system nigdy nie wybiera osoby automatycznie na podstawie kolejnosci rosteru ani porownania statystyk.
- D2. Chata Rybacka od poziomu II jest wlascicielem jednej rownoleglej ekspedycji lodzia trwajacej 2, 3 albo 4 dni. Jest to osobne zobowiazanie domeny bazy, nie `ExpeditionSetup` nurkowania, i moze wspolistniec z jednym nurkowaniem wykonywanym przez inna osobe.
- D3. Pelny prowiant jest pobierany atomowo przy wyplynieciu, a dowodca jest zywy i rezerwuje miejsce, lecz do powrotu nie uczestniczy w racjach, pracy, schronieniu nocy, leczeniu ani transmisji chorob bazy. Wynik oraz kandydatury sa deterministycznie zamrazane przy starcie i stosowane najwyzej raz rano dnia `launch_day + duration`.
- D4. Gracz moze spowodowac najwyzej jedno trwale odejscie dziennie po tutorialu; zwykle odejscie i zastapienie kandydatem zuzywaja ten sam limit. Osoba pozostaje w trwalym rosterze jako `DEPARTED`, a osobny rekord zachowuje jej stan i koszt decyzji dla Kroniki.
- D5. Aktywna ekspedycja jest jedynym wlascicielem nieobecnosci dowodcy i nie reinterpretuje historycznego `MISSING`. Zapytania o zywy roster, osoby obecne oraz zarezerwowana pojemnosc sa rozdzielone, a zadna komenda nie moze pozostawic Przystani bez obecnej osoby.
- D6. Powrot stosuje zasoby i konsekwencje dowodcy przed decyzja, nastepnie wymaga jawnego przyjecia albo odrzucenia kazdej zamrozonej kandydatury. Zwykle wydarzenie poranka jest wybierane dopiero po tej atomowej decyzji, aby presja i pojemnosc czytaly ostateczny roster.
- D7. Istniejacy szkielet typowanych kontraktow i czystych inwariantow nie aktywuje mechaniki ani nie zmienia schematu. Wlaczenie go do `GameState`, resolvera lub UI wymaga pelnego pionu, nowej wersji zapisu, walidacji, roundtripu, przypadkow odrzucenia bez mutacji oraz aktualizacji stanu potwierdzonego runtime.
- Powod i skutek: pozyskiwanie lepszych lub potrzebnych specjalistow tworzy kosztowny dylemat skladu zamiast darmowej wymiany chorych osob, a oddzielenie nieobecnosci od zwyklego nurkowania zapobiega obchodzeniu racji, schronienia, chorob i dziennego limitu odejsc.
- Odwolania: ARD-0001; ARD-0003; ARD-0004; ARD-0016; ARD-0018; ARD-0019; ARD-0026; ARD-0027; ARD-0038; ARD-0044; ARD-0045; ARD-0063; ARD-0065; ARD-0073; docs/OgolnyZarys.txt - sekcje 4, 5.2 i 5.6; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 4.7, 6, 7.3, 8.1 i 11.

## ARD-0082 - Jedna fasada obecnosci i atomowy poranek rotacji

- Domena: mieszkancy, ekspedycje lodzia, poranek, kampania i zapis
- Status / aktywny zakres: Czesciowo zastapione; D1-D6
- Zatwierdzenie: 2026-08-12
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0092/D5
- D1. `RosterRotationSystem` jest jedna fasada rozrozniajaca zyjacy roster, osoby obecne, dowodce nieobecnego na lodzi i zarezerwowana pojemnosc. Aktywna ekspedycja jest jedynym wlascicielem tej nieobecnosci; konsumenci pracy, nurkowania, racji, schronienia, leczenia, chorob, presji, odejscia i pojemnosci nie odtwarzaja jej z `Status.MISSING` ani z lokalnej listy UI.
- D2. Wyplyniecie zamraza dokladny koszt `food_per_adult * duration`, poziom Chaty, priorytet, zdrowie dowodcy, wersje i podpis balansu oraz caly wynik. Dowodca moze miec wylacznie brak aktywnego przypadku choroby albo odpornosc, nie moze przekroczyc znanego terminu Czarnego Frontu i po zastosowaniu wyniku zachowuje co najmniej 1 zdrowia.
- D3. Kazda kandydatura ma typowana decyzje: odrzucenie, przyjecie na wolne miejsce albo przyjecie z zastapieniem konkretnej obecnej osoby i wskazanym wariantem odejscia. Caly komplet decyzji jest najpierw walidowany i stosowany do odlaczonego kandydata `GameState`, a dopiero jeden udany zapis publikuje zasoby, roster, rekord odejscia, dzienny limit, presje i wydarzenie. Porazka dowolnego kroku zachowuje caly stan wejściowy.
- D4. Jedna oferta moze spowodowac najwyzej jedno zastapienie, bo korzysta ze wspolnego limitu jednego odejscia dziennie. Przy pelnej pojemnosci oznacza to najwyzej jednego przyjetego kandydata przez zastapienie; druga kandydatura wymaga niezaleznego wolnego miejsca albo zostaje odrzucona. Atomowe zastapienie ostatniej obecnej osoby jest dozwolone tylko wtedy, gdy przyjmowana osoba w tej samej transakcji natychmiast pozostawia co najmniej jedna osobe obecna.
- D5. Dobrowolne kandydatury z lodzi i wydarzen podlegaja twardej pojemnosci albo zastapieniu. Ratunek wykonany podczas nurkowania pozostaje wyjatkiem ratunkowym: moze chwilowo przeludnic schronienie i ponosi zwykla kare braku dachu, ale nie uniewaznia zarezerwowanego miejsca dowodcy lodzi.
- D6. Smierc moze pozostawic Przystan bez osoby obecnej mimo blokad komend. Jezeli zyje dowodca z zaplanowanym powrotem, kampania przechodzi w automatyczny tryb oczekiwania: nie oferuje planowania, pracy, racji ani wydarzen, lecz przesuwa dni i rozlicza pogode oraz integralnosc do powrotu. `GAME_OVER` nastepuje dopiero wtedy, gdy nie ma osoby obecnej ani zyjacej osoby zdolnej wrocic; terminalne rozstrzygniecie kampanii ma pierwszenstwo przed obietnica zwyklego powrotu.
- D7. Pelna aktywacja ustanawia schemat 25 oraz kontrolowana migracje dokladnie 24 -> 25, ktora dodaje puste pola rotacji bez zmiany dotychczasowego wyniku kampanii. Starsze schematy pozostaja izolowane. Do czasu kompletnej integracji z agregatem, resolverem, UI, preflightem, postflightem i testem roundtrip aktywnym schematem pozostaje 24, a sam szkielet nie jest mechanika runtime.
- Powod i skutek: wszystkie systemy odpowiadaja tak samo na pytanie, kto faktycznie jest w bazie, a poranny dylemat przyjecia i odejscia nie moze zapisac polowy decyzji, przekroczyc pojemnosci, ominac limitu ani zamrozic wydarzenia dla nieaktualnego rosteru.
- Odwolania: ARD-0001; ARD-0004; ARD-0018; ARD-0019; ARD-0044; ARD-0045; ARD-0063; ARD-0065; ARD-0073; ARD-0077; ARD-0081; docs/OgolnyZarys.txt - sekcje 2, 4, 5.2 i 10; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 3, 4.7, 6, 7.3, 8.1, 10, 11 i 13.

## ARD-0083 - Wspolna Linia bez warstwy zgodnosci starej fabuly

- Domena: kampania, dane, zapis, mapa, misje i testy
- Status / aktywny zakres: Czesciowo zastapione; D1-D2, D4, D7
- Zatwierdzenie: 2026-08-12; wdrozenie 2026-08-13
- Relacje: Zastepuje: ARD-0029, ARD-0051, ARD-0055, ARD-0077/D8, ARD-0080/D5 w zakresie numeru aktywnego schematu, ARD-0082/D7 | Zastapiona przez: ARD-0092/D3,D5,D8-D9
- D1. Wspolna Linia jest jedynym modelem kampanii. Kod, pola stanu, przedmioty, skrytki, misje, UI, walidacja i testy Projektu Swit oraz zakonczenia Odejscie zostaja usuniete, a nie tylko blokowane warunkiem wersji.
- D2. `StoryProgressState` przechowuje jeden etap aktywnej Wspolnej Linii i Epilog po `final_chronicle_continued`; Archiwum nie przełącza ukrytego aktu i nie tworzy kredytu artefaktu.
- D3. Aktywna granica zapisu to schemat 25 w przestrzeni `ostatni_pomost_common_line_*`. Schemat 24 i starsze nie maja wejscia migracyjnego ani odczytu; ich pliki pozostaja na dysku i nie sa nadpisywane.
- D4. Walidator sprawdza tylko aktualne inwarianty Wspolnej Linii. Wynurzenie po aktywacji Archiwum musi przechodzic ten sam postflight i roundtrip co kazdy inny bezpieczny punkt zapisu.
- D5. Usuniecie starego pionu nie usuwa aktywnych, ogolnych systemow ciezkiego odzysku, Kroniki Wspolnej Linii ani docelowego szkieletu rotacji zalogi. Przyszla aktywacja rotacji wymaga schematu pozniejszego niz 25 i osobnej decyzji migracyjnej.
- D6. Testy sluzace wyłącznie kompatybilnosci starej fabuly zostaja usuniete. Szybka bramka zachowuje test Archiwum/wynurzenia, roundtrip schematu 25, tutorial, produkcje, kompetencje i kanoniczna mape.
- D7. Dokumentacja decyzji zachowuje zastapione ARD jako audyt przyczyn, ale nie stanowi to kodu, danych ani alternatywnej trasy produktu.
- Powod i skutek: dwa rownolegle modele fabuly tworzyly sprzeczne inwarianty; po aktywacji Archiwum nowa kampania pozostawala w swoim etapie, a walidator wymagajacy starego Aktu II odrzucal zapis przy wynurzeniu. Jedna reprezentacja usuwa te klase bledu i upraszcza dalszy rozwoj.
- Odwolania: ARD-0019; ARD-0045; ARD-0065; ARD-0077; docs/OgolnyZarys.txt - sekcje 9-10; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 4.5, 10, 11 i 13.

## ARD-0084 - Ogolne PD za obsade, praktyka za realna prace

- Domena: zaloga, praca i progresja
- Status / aktywny zakres: Obowiazuje; D1-D5
- Zatwierdzenie: 2026-08-13
- Relacje: Zastepuje: ARD-0036/D3; ARD-0068/D2-D3 | Zastapiona przez: brak
- D1. Zdolna osoba zamrozona w obsadzie aktywnego budynku otrzymuje jedna dzienna nagrode ogolnych PD niezaleznie od wykonania efektu budynku.
- D2. Jeden dziennik rzeczywiscie wykonanej pracy pozostaje zrodlem skutkow dla zmeczenia, napiecia, nadziei, praktyki zawodowej i raportu; bezczynna obsada nie tworzy kompetencji zawodowej.
- D3. Sam przydzial nie jest rzeczywista praca; realna prace potwierdza zdarzenie zaakceptowane przez wlasciciela domeny. Ogolne PD za obsade sa odrebnym skutkiem, deduplikowanym per osoba i dzien; osoba nieobecna, niezdolna albo usunieta z migawki nie otrzymuje nagrody.
- D4. Nurek otrzymuje ogolne PD wylacznie z `DiveResult`, bez drugiej nagrody za stanowisko Nurka. Zdolny Operator i Technik korzystaja ze zwyklej nagrody obsady, a praktyke nurkowania dostaja tylko za wykonana wyprawe.
- D5. Praktyka kazdej wykonywanej dziedziny pozostaje widoczna i moze rosnac po wyborze drugiej specjalizacji, lecz tylko profesja glowna i najwyzej jedna dodatkowa daja efekt specjalisty.
- Powod i skutek: gracz rozwija poziom osoby przez odpowiedzialne obsadzenie stanowiska, natomiast biegłość zawodowa nadal dowodzi wykonanej pracy i nie może być farmiona przez bezczynny budynek.
- Odwolania: ARD-0036; ARD-0068; docs/OgolnyZarys.txt - sekcja 4; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 4.1, 6 i 8.2.

## ARD-0085 - Jedna semantyczna maska terenu i pochodna prezentacja

- Domena: swiat nurkowania, authoring terenu, prezentacja, fizyka i kompatybilnosc zapisu
- Status / aktywny zakres: Czesciowo zastapione; D4, D7
- Zatwierdzenie: 2026-08-13
- Relacje: Zastepuje: ARD-0075/D5 | Zastapiona przez: ARD-0092/D5; ARD-0098/D1-D4; ARD-0102/D2,D9
- D1. Bazowa maska nawigacji wskazana przez `UnderwaterMap.tscn` jest jedynym semantycznym zrodlem makrogeometrii terenu. Kontur renderowanych skal, segmenty kolizji i reprezentacja aktywnych chunkow sa deterministycznymi pochodnymi tej samej maski, a kazda pozniejsza okluzja swiatla terenu rowniez musi byc jej pochodna.
- D2. Kanoniczna kolizja runtime ARD-0052 pozostaje wlascicielem przechodniosci. Pochodny material nie moze zmieniac fizyki; scenowe `MapObstacle` nadal sa jawnymi lokalnymi nakladkami wspolnego rastra, a widoczny prefab sam nie ustanawia kolizji.
- D3. Pochodne sa odswiezane oraz walidowane z produkcyjnej sceny bez osobnego draftu, katalogu publikacyjnego ani recznego etapu wypiekania. Nody i zasoby utworzone dla aktywnego chunka sa cache'em prezentacji/runtime i nie sa zapisywane z powrotem do sceny jako drugie zrodlo.
- D4. Kafelkowy material skal, profile kolorystyczne regionow, caustics, zawiesina i postprocess sa danymi wylacznie prezentacyjnymi. Nie wchodza do podpisu gameplayowego, nie zmieniaja seedowanej topologii, tras, `WorldDelta`, `DiveResult` ani zasad kampanii.
- D5. Historyczna klauzula laczaca source-v4 ze schematem 25 zostala zastapiona przez jeden czysty format kampanii ARD-0092.
- D6. Unikalne landmarki, urzadzenia, obiekty interaktywne i dekoracje pozostaja autorskimi prefabami sceny. Generator terenu odpowiada za wspolna powierzchnie i atmosfere, nie za semantyke ani tozsamosc tych obiektow.
- D7. Profile jakosci i ograniczenie ruchu moga zmieniac liczbe czastek, koszt refrakcji, czestotliwosc detalu i miekkosc efektow, lecz nie fizyke, widocznosc wymagana przez mechanike, stan sesji ani zapis.
- Powod i skutek: jedna edycja konturu aktualizuje obraz i fizyke, usuwa koszt recznego obrysowywania tej samej jaskini oraz pozwala streamowac teren i podnosic jakosc grafiki bez drugiej mapy gameplayowej.
- Odwolania: ARD-0013; ARD-0041; ARD-0049; ARD-0052; ARD-0059; ARD-0066; ARD-0075; ARD-0092; docs/OgolnyZarys.txt - sekcje 6 i 7; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 9, 11, 12.1, 12.3 i 13.

## ARD-0086 - Kanoniczny rdzen wiedzy i repozytoryjne przewodniki wykonawcze

- Domena: dokumentacja, proces pracy i Codex skills
- Status / aktywny zakres: Czesciowo zastapione; D2-D4, D7
- Zatwierdzenie: 2026-08-13
- Relacje: Zastepuje: ARD-0014/calosc; ARD-0070/D4 | Zastapiona przez: ARD-0097/D1-D2; ARD-0099/D1,D3
- D1. Kanoniczny rdzen wiedzy projektu pozostaje w pieciu dokumentach merytorycznych oraz korzeniowym `AGENTS.md`. Kazdy szczegol produktu, runtime, architektury, zapisu, decyzji i onboardingu zachowuje jednego wlasciciela zgodnie z aktywnym zakresem ARD-0070.
- D2. Repozytorium moze utrzymywac pod `.agents/skills` wyspecjalizowane przewodniki wykonawcze: procedury zadaniowe, checklisty, referencje warsztatowe, skrypty i zasoby wielokrotnego uzycia. Nie sa one dodatkowym kanonicznym opisem gry ani biezacego runtime.
- D3. Skill musi wskazywac dokumenty kanoniczne i nie moze ustanawiac ani kopiowac regul produktu, aktywnych wartosci balansu, wlascicieli stanu, kontraktow danych, persistence, migracji lub statusu wdrozenia. Konflikt rozstrzyga sie przez aktywne ARD, dokument bedacy wlascicielem szczegolu oraz faktyczny runtime zgodnie z bramka rozbieznosci.
- D4. Korzeniowy `AGENTS.md` jest wlascicielem globalnej kolejnosci odczytu, bramki rozbieznosci, routingu dokumentacji i wyboru procedury specjalistycznej. Repozytoryjny skill posiada tylko wykonanie zadania w swoim zakresie, a `README.md` pozostaje wejsciem dla czlowieka.
- D5. Zadanie specjalistyczne jest routowane wedlug intencji opisanej w metadanych skilla albo przez jawne wywolanie `$nazwa-skilla`; zagniezdzony `AGENTS.md` zalezy od sciezki uruchomienia i nie jest semantycznym routerem promptu.
- D6. Historyczna klauzula ustanawiajaca repozytoryjny przewodnik zadan prezentacyjnych zostala zastapiona przez ARD-0097/D1-D2.
- D7. Zmiana wizualna nadal przechodzi zwykla bramke produktu i architektury, inspekcje aktywnego runtime, dowod przed/po, profile jakosci i dostepnosc. Automatyczny test lub snapshot potwierdza tylko swoj kontrakt; akceptacja artystyczna wymaga takze jawnej kontroli wzrokowej.
- Powod i skutek: rozdzielenie rdzenia prawdy od przewodnikow wykonawczych pozwala automatycznie kierowac zadania do fachowego workflow bez tworzenia drugiej specyfikacji gry.
- Odwolania: AGENTS.md; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 2, 12 i 13.

## ARD-0087 - Narracja uzywa napisow i diegetycznych znakow dzwiekowych bez voice-overu

- Domena: intro, prezentacja fabuly, audio i dostepnosc
- Status / aktywny zakres: Obowiazuje; D1-D6
- Zatwierdzenie: 2026-08-13
- Relacje: Zastepuje: ARD-0061/calosc | Zastapiona przez: brak
- D1. Kanonicznym nosnikiem wszystkich kwestii intro i kampanii jest tekst z podpisem albo bezosobowa karta; gra nie odtwarza nagranego, syntetycznego ani generowanego voice-overu. Nazwy rol narracyjnych nie ustanawiaja mowy audio.
- D2. Wybrane, obserwowalne przejscie sceny moze wskazac jeden opcjonalny, prezentacyjny znak dzwiekowy rozpoznawany przez wspolny katalog. Brak albo nieznany znak oznacza cisze tej warstwy i nigdy nie blokuje rozmowy.
- D3. Znak uruchamia sie wylacznie przy wejsciu w przypisane przejscie. Przejscie dalej przerywa poprzedni efekt, a zamkniecie, wymuszone wyczyszczenie lub zmiana sceny zatrzymuja go bez oczekiwania na koniec pliku.
- D4. Audio nie steruje kolejnoscia, czasem ani skutkiem narracji. Tekst zachowuje pelne znaczenie, a brak lub blad assetu nie moze zmienic postepu, wejscia ani dostepnosci informacji.
- D5. Identyfikator efektu, biezace odtwarzanie i deduplikacja prezentacji nie naleza do `GameState`, zapisu ani migracji; zmiana nie podnosi rewizji formatu kampanii.
- D6. Powracajace motywy urzadzen i ich swiadomy brak moga budowac pamiec fabularna, lecz nie sa dzwiekiem kazdego przycisku, mowa postaci ani drugim systemem celu. Lokalna muzyka moze byc chwilowo sciszana wylacznie przez warstwe prezentacji i zawsze wraca po zakonczeniu efektu.
- Powod i skutek: gra zachowuje czytelna, dostepna narracje bez kosztu i niespojnosci voice-overu, a krotkie dzwieki radia, pomp i starej sieci staja sie rozpoznawalnym jezykiem swiata bez zanieczyszczania stanu kampanii.
- Odwolania: ARD-0047; ARD-0049; ARD-0069; docs/OgolnyZarys.txt - sekcje 1, 9 i 10; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 12.1 i 13.

## ARD-0088 - Historyczne osiem slotow kampanii i jawne opuszczenie sesji

- Domena: powloka aplikacji, zapis kampanii i menu pauzy
- Status / aktywny zakres: Zastapione; brak
- Zatwierdzenie: 2026-08-13
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0092/calosc
- D1. Historycznie powloka udostepniala osiem logicznych slotow kampanii, kazdy z osobnym zestawem primary, pending i backup.
- D2. Wybor aktywnego slotu byl stanem sesji powloki, a nie polem `GameState`.
- D3. `NOWA GRA` i `KONTYNUUJ` przechodzily przez wspolny selektor slotow.
- D4. Zastapienie slotu bylo osobna transakcja archiwizacji poprzedniego zestawu.
- D5. Powrot do menu odrzucal biezacy runtime bez autosave, a bezposrednie wyjscie zachowywalo semantyke natychmiastowego zamkniecia.
- D6. Ustawienia urzadzenia pozostawaly poza slotem i `GameState`.
- D7. Rozszerzenie przestrzeni plikow nie zmienialo znaczenia wewnetrznego agregatu.
- Powod i skutek: wpis zachowuje audyt odrzuconej powloki wielokampanijnej; nowych funkcji nie wolno budowac na selektorze slotow ani jego sciezkach.
- Odwolania: ARD-0092; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 11.1 i 12.1.

## ARD-0089 - Hybrydowy rozwoj laczy kompetencje ogolne z talentami profesji

- Domena: rozwoj postaci, profesje, baza, nurkowanie i zapis
- Status / aktywny zakres: Czesciowo zastapione; D1-D4, D6-D7
- Zatwierdzenie: 2026-08-13
- Relacje: Zastepuje: ARD-0080/D1,D5 | Zastapiona przez: ARD-0092/D5
- D1. Katalog ogolny obejmuje pietnascie pasywnych kompetencji po trzy poziomy. Osobna warstwa obejmuje dokladnie dwanascie talentow: po dwa wzajemnie wykluczajace sie warianty dla kazdej z szesciu wykonywalnych profesji. Nie powstaje siodma profesja ani ogolny pion aktywnych umiejetnosci.
- D2. `SurvivorState.competency_levels` pozostaje jedynym wlascicielem poziomow kompetencji. Osobna typowana mapa talentow przypisuje najwyzej jeden stabilny talent do kazdej formalnej profesji osoby; pole legacy `unlocked_skill_ids` nie otrzymuje nowego znaczenia. Katalogi, opisy i przeliczniki naleza do systemow domenowych, a UI nie przechowuje kopii regul.
- D3. Poziom kompetencji nadal zuzywa istniejacy punkt rozwoju w aktywnym Domu Wspolnoty I. Talent jest darmowym, natychmiastowym i nieodwracalnym wyborem w aktywnym Domu II po osiagnieciu progu pelnej praktyki formalnej profesji glownej albo dodatkowej. Praktyka sciezki, ktorej osoba formalnie nie posiada, nie daje prawa wyboru talentu.
- D4. Efekty pozostaja deterministyczne, nie kumuluja wielokrotnie identycznego talentu w jednym rozliczeniu i skladaja sie w najmniejszym systemie bedacym wlascicielem wyniku. Podglad i wykonanie korzystaja z tej samej projekcji. Kompetencje i talenty sesji nurkowania sa zamrazane w `ExpeditionSetup`; wariant cichej naprawy jest narzedziem kontekstowym talentu Nurka, nie drugim modelem rozwoju.
- D5. Historyczna granica schematu 26 i migracja 25 -> 26 zostaly zastapione przez czysty format kampanii ARD-0092.
- D6. Granica wyboru odrzuca nieznany talent, zla pare profesja-talent, profesje nieposiadana przez osobe, brak wymaganej praktyki, brak Domu II, zablokowany plan i ponowny wybor bez czesciowej mutacji.
- D7. Dom Wspolnoty jest jedynym miejscem mutacji talentow i pokazuje oba warianty, dokladny skutek, warunek oraz zamknieta alternatywe. Inne profile zalogi, selektory i HUD wyprawy moga prezentowac wybrane talenty i ich skutek tylko do odczytu.
- Powod i skutek: rozdzielenie powtarzalnych kompetencji ogolnych od jednorazowej tozsamosci profesji zwieksza liczbe sensownych konfiguracji bez losowych aktywacji, duplikowania stanu i reinterpretacji starszych kampanii.
- Odwolania: ARD-0080; ARD-0083; ARD-0084; ARD-0092; docs/OgolnyZarys.txt - sekcje 4 i 5.6; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 5, 8.1, 8.2, 11 i 13.

## ARD-0090 - Pelnoekranowy Tryb Zarzadzania Baza

- Domena: interfejs bazy i nawigacja budynkow
- Status / aktywny zakres: Czesciowo zastapione; D2-D6
- Zatwierdzenie: 2026-08-13
- Relacje: Zastepuje: ARD-0062/D1 | Zastapiona przez: ARD-0091/D1
- D1. Swiadome otwarcie dowolnego budynku przechodzi do pelnoekranowego Trybu Zarzadzania Baza, ktory na czas pracy przykrywa i wylacza interakcje z widokiem platformy. Zwykle planowanie poza tym trybem nadal pokazuje swiat jako glowny kontekst.
- D2. Pionowa szyna nawigacyjna prezentuje dokladnie szesc kanonicznych, stalych slotow platformy. Kolejnosc, nazwa, poziom i stan kafelka sa pochodne z `GameState`, definicji budynkow oraz stanu slotu; UI nie przechowuje drugiej listy budynkow.
- D3. Wybor kafelka przelacza kontekst w tej samej przestrzeni roboczej bez zamykania trybu i bez mutacji domeny. Fokus przechodzi do zawartosci wybranego budynku, a zamkniecie oddaje go ostatnio wybranemu slotowi platformy.
- D4. `BuildingPanel` zachowuje aktywne klauzule ARD-0062/D2-D4: pokazuje prawdziwy stan, skutek i blokade, deleguje komendy do systemow domenowych i nie utrzymuje alternatywnego stanu.
- D5. Tryb jest zamykany przez `Esc` oraz jawny przycisk. Click-outside nie jest droga zamkniecia pelnoekranowej przestrzeni; warstwy potomne, takie jak selektor pracownika lub rozwoj mieszkanca, wracaja do wybranego budynku bez opuszczenia trybu.
- D6. Zmiana dotyczy prezentacji i nawigacji. Nie zmienia szesciu slotow platformy, mechanik budynkow, `GameState`, planu dnia ani formatu kampanii.
- Powod i skutek: codzienne porownywanie i obsluga szesciu budynkow wymaga szybkiego przechodzenia miedzy nimi oraz wiekszej powierzchni dla katalogow, obsady i prognoz. Jawna granica trybu pozwala zaslonic platforme tylko wtedy, gdy gracz swiadomie rozpoczyna zarzadzanie, bez tworzenia drugiego modelu stanu.
- Odwolania: ARD-0035; ARD-0039; ARD-0062; ARD-0066; ARD-0091; docs/OgolnyZarys.txt - sekcja 5; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 12.2 i 13.

## ARD-0091 - Przezroczysty Tryb Zarzadzania zachowuje aktywny HUD Bazy

- Domena: interfejs bazy, warstwy wejscia i nawigacja fokusu
- Status / aktywny zakres: Obowiazuje; D1-D6
- Zatwierdzenie: 2026-08-13
- Relacje: Zastepuje: ARD-0090/D1 | Zastapiona przez: brak
- D1. Swiadome otwarcie budynku pokazuje duza, lecz mniejsza od ekranu przestrzen robocza na przezroczystej warstwie. Widok platformy pozostaje czytelny wokol okna, ale jego sloty i pozostale kontrolki swiata nie przyjmuja wejscia do chwili zamkniecia trybu.
- D2. Caly gorny HUD Bazy oraz `ZAKONCZ DZIEN` pozostaja ponad warstwa blokujaca, sa widoczne i przyjmuja mysz oraz fokus zgodnie z istniejacymi blockerami domenowymi. Sam otwarty budynek nie ustanawia nowej blokady planu dnia ani zakonczenia dnia.
- D3. `DayPlanPopover` i `SurvivorsPanel` moga otworzyc sie nad przestrzenia budynku bez jej zamykania. Ich lokalna pulapka fokusu i pierwsze `Esc` maja pierwszenstwo; po zamknieciu fokus wraca do kontrolki gornego HUD-u, a kolejne `Esc` moze zamknac Tryb Zarzadzania.
- D4. Zakres klawiatury otwartego trybu obejmuje szesc kafelkow, `BuildingPanel`, dostepne kontrolki gornego HUD-u i `ZAKONCZ DZIEN`, ale nie sloty platformy pod przezroczysta warstwa. Pierwsze otwarcie i zmiana kafelka nadal kieruja fokus do wybranego budynku, a zamkniecie oddaje go ostatniemu slotowi.
- D5. Uzycie `ZAKONCZ DZIEN` deleguje do tej samej kanonicznej komendy co poza trybem. Jej udane przejscie do obowiazkowego raportu zamyka przestrzen budynku i oddaje priorytet raportowi; UI nie utrzymuje wlasnego wariantu rozliczenia.
- D6. Zmiana dotyczy kompozycji, routingu wejscia i fokusu. Nie zmienia mechanik budynkow, planu dnia, `GameState` ani formatu kampanii.
- Powod i skutek: calkowite zakrycie platformy usuwalo kontekst wizualny, a blokada globalnego HUD-u zmuszala do zamykania budynku przed kazda decyzja przekrojowa. Przezroczysty bloker zachowuje bezpieczna granice wejscia do swiata, natomiast mniejsze okno i aktywny HUD lacza porownywanie budynkow z planem dnia oraz jego zakonczeniem bez drugiego modelu stanu.
- Odwolania: ARD-0035; ARD-0039; ARD-0062; ARD-0066; ARD-0090; docs/OgolnyZarys.txt - sekcja 5; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 12.2 i 13.

## ARD-0092 - Jeden czysty format i jedna kampania bez importu historii

- Domena: zapis kampanii, kompatybilnosc, mapa i powloka aplikacji
- Status / aktywny zakres: Obowiazuje; D2-D4, D6-D9
- Zatwierdzenie: 2026-08-14
- Relacje: Zastepuje: ARD-0019/D2; ARD-0045/D3; ARD-0059/D2; ARD-0063/D4; ARD-0065/D2-D3; ARD-0068/D5; ARD-0073/D8; ARD-0076/D5; ARD-0082/D7; ARD-0083/D3,D5-D6; ARD-0085/D5; ARD-0088/calosc; ARD-0089/D5 | Zastapiona przez: ARD-0096/D1,D5
- D1. Zastapiona przez ARD-0096/D1.
- D2. Powloka udostepnia jedna biezaca kampanie w jednym namespace primary, pending i backup. Nie istnieje aktywny slot, selektor slotow, numerowane przestrzenie kampanii ani ukryty wybor kampanii w `GameState`.
- D3. Pliki starszych repozytoriow, dawnych schematow 25-27, przestrzeni Wspolnej Linii i dawnych slotow nie sa wejsciem. Gra ich nie importuje, nie migruje, nie usuwa i nie nadpisuje; kandydat o innej rewizji jest odrzucany bez mutacji.
- D4. Jeden walidator wykonuje preflight oraz pelny postflight kandydata dokladnie biezacej rewizji. Zapis pracuje na odseparowanym kandydacie, ponownie odczytuje pending, zachowuje tylko poprawny primary jako backup i atomowo promuje pending; nie istnieje warstwa reinterpretacji legacy.
- D5. Zastapiona przez ARD-0096/D5.
- D6. `KONTYNUUJ` jest dostepne tylko dla poprawnego kandydata biezacej kampanii. `NOWA GRA` wymaga potwierdzenia usuniecia jej namespace; powrot do menu odrzuca runtime bez zapisu, lecz nie usuwa kampanii.
- D7. `UserSettings` pozostaje osobnym stanem urzadzenia i nie nalezy do namespace kampanii ani `GameState`.
- D8. Czysta granica formatu nie usuwa aktywnych systemow Wspolnej Linii, ciezkiego odzysku ani Kroniki. Kazda przyszla aktywacja nowej domeny, w tym rotacji zalogi, musi od razu wejsc do jednego biezacego grafu i przejsc pelna walidacje oraz roundtrip bez tworzenia pobocznego numeru schematu.
- D9. Testy kompatybilnosci dawnych fabulek, slotow i migracji nie naleza do aktywnej bramki. Bramka sprawdza biezacy format, roundtrip i aktualne kontrakty domenowe; odrzucony starszy plik pozostaje bez mutacji.
- Powod i skutek: nowe repo nie dziedziczy niezweryfikowanej historii formatow, slotow ani migratorow. Jedna rewizja i jedna kampania upraszczaja atomowosc, walidacje i dalszy rozwoj, a stare pliki pozostaja nietkniete zamiast byc cicho reinterpretowane.
- Odwolania: ARD-0001; ARD-0019; ARD-0045; ARD-0065; ARD-0083; ARD-0085; ARD-0088; ARD-0089; docs/OgolnyZarys.txt - sekcje 2, 4, 5 i 7; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 3, 5, 9, 11-13.

## ARD-0093 - Historyczny Oddech Przystani jest lokalna muzyka bazy

- Domena: baza, audio i prezentacja
- Status / aktywny zakres: Obowiazuje; D1-D4
- Zatwierdzenie: 2026-08-14
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Kanonicznym lokalnym utworem bazy jest historyczny `Oddech Przystani`. `Swiatlo na Pokladzie` ani jego generator nie naleza do aktywnego produktu.
- D2. Utwor jest prezentacja lokalna dla sceny bazy: rozpoczyna sie wraz z nia, zapetla, respektuje ustawienia magistrali `Master`, pauzuje razem z drzewem i konczy sie przy zmianie sceny.
- D3. Odtwarzanie, pozycja i petla utworu nie naleza do `GameState`, formatu kampanii ani mechaniki dnia. Brak lub blad assetu nie moze zablokowac wejscia do bazy ani postepu kampanii.
- D4. Wlasnosci techniczne pliku i importu sa jednym kontraktem aktywnego assetu utrzymywanym w architekturze; dokument produktu opisuje tylko odczucie gracza.
- Powod i skutek: przywrocenie istniejacego historycznego utworu zachowuje tozsamosc Przystani bez generatora, drugiej kompozycji i zanieczyszczania trwalego stanu.
- Odwolania: ARD-0049; ARD-0087; docs/OgolnyZarys.txt - sekcja 3; docs/Ostatni_Pomost_architektura_Godot.txt - sekcja 12.2.

## ARD-0094 - Niewidoczne reflektory J-7 oswietlaja poklad z gornej konstrukcji

- Domena: oswietlenie i prezentacja bazy
- Status / aktywny zakres: Zastapione; D1
- Zatwierdzenie: 2026-08-15
- Relacje: Zastepuje: ARD-0071/D1 | Zastapiona przez: ARD-0095/D1
- D1. Aktywny widok bazy zachowuje jedno wspolne kierunkowe zrodlo swiatla i jeden model cienia. Jedynym lokalnym wyjatkiem sa dokladnie trzy niewidoczne, bezcieniowe reflektory kierunkowe na dwoch wierzcholkach gornej konstrukcji i przy zurawiu; po utrwalonym J-7 kieruja swiatlo w dol i do srodka pokladu. Przed J-7 nie wnosza energii. Nie powstaje drugie slonce ani osobny ogolny fill light; ograniczone ocieplenie ambientu pozostaje pochodna juz wybranego profilu pogody.
- Powod i skutek: proceduralne maszty i klosze tworzyly w ciemnym kadrze przypadkowe czarne sylwetki, a swiatlo dookolne rozpraszalo energie poza poklad. Niewidoczne reflektory zachowuja lokalny sygnal odzyskanego zasilania, ale prowadza wzrok po platformie bez dodawania obcych bryl.
- Odwolania: ARD-0071; docs/OgolnyZarys.txt - sekcja 5; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 12.2 i 13.

## ARD-0095 - Trzy punkty J-7 jednoznacznie rozpoczynaja kierunkowe wiazki

- Domena: oswietlenie i prezentacja bazy
- Status / aktywny zakres: Obowiazuje; D1
- Zatwierdzenie: 2026-08-15
- Relacje: Zastepuje: ARD-0094/D1 | Zastapiona przez: brak
- D1. Po utrwalonym J-7 dokladnie trzy wskazane punkty na dwoch wierzcholkach gornej konstrukcji i przy mechanizmie zurawia maja czytelny, lecz pozbawiony fizycznej oprawy poczatek swiatla. Z kazdego biegnie bezcieniowa, kierunkowa wiazka odpowiednio na lewa, srodkowa i prawa czesc pokladu. Warstwa J-7 nie dodaje swiatla dookolnego, globalnego bonusu ambientu ani emisji materialow sugerujacej zrodlo na pokladzie; przed J-7 punkty, wiazki i ich lokalny wklad sa niewidoczne oraz pozbawione energii.
- Powod i skutek: same plamy swiatla na powierzchni nie pokazywaly pochodzenia i wygladaly jak emisja z podlogi, a lokalna poswiata zurawia sugerowala swiatlo dookolne. Czytelny poczatek oraz lagodny kierunek w powietrzu lacza kazda oswietlona strefe z zatwierdzonym punktem konstrukcji bez przywracania modeli lamp.
- Odwolania: ARD-0071 i ARD-0094; docs/OgolnyZarys.txt - sekcja 5; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 12.2 i 13.

## ARD-0096 - Trwala preferencja nurka i dzienny wybor wyprawy

- Domena: przygotowanie nurkowania i zapis kampanii
- Status / aktywny zakres: Obowiazuje; D1-D6
- Zatwierdzenie: 2026-08-15
- Relacje: Zastepuje: ARD-0092/D1,D5 | Zastapiona przez: brak
- D1. Caly graf `GameState` ma jedna wspolna rewizje formatu kampanii 2; zasoby domenowe nie utrzymuja niezaleznych numerow schematu ani lancucha migracji.
- D2. Trwala preferencja nurka nalezy do stanu kampanii, a aktywny wybor nurka nalezy wylacznie do edytowalnego planu dnia. Preferencja nie jest stanowiskiem budynku ani stanem UI.
- D3. Poprawny jawny wybor nurka aktualizuje jednoczesnie aktywny wybor dnia i trwala preferencje; jawne wyczyszczenie usuwa oba te znaczenia bez mutowania obsady Stacji.
- D4. Nowy plan dnia wyprowadza aktywny wybor wylacznie z zapisanej preferencji, gdy osoba przechodzi aktualne bramki obecnosci, wolnosci, izolacji i nurkowania. Czasowa blokada pozostawia preferencje, lecz nie tworzy fikcyjnego nurka dnia.
- D5. Source-v4 mapy, pietnascie kompetencji, dwanascie talentow profesji, niezalezny wybor nurka, trwala preferencja nurka oraz opcjonalna Obsluga Stacji naleza do rewizji 2. Kandydat rewizji 1 nie jest importowany ani reinterpretowany bez osobnej decyzji z uwierzytelnialnym mapowaniem.
- D6. Smierc albo trwale odejscie preferowanej osoby usuwa preferencje przed utworzeniem kolejnego planu dnia. Obsada Stacji i jej zamrozone wsparcie wyprawy pozostaja niezalezne.
- Powod i skutek: gracz nie wybiera tej samej osoby codziennie od nowa, a kampania zachowuje jedna jawna intencje bez pomylenia nurka z pracownikiem Stacji lub bez przechowywania drugiej kopii planu w UI.
- Odwolania: ARD-0001; ARD-0018; ARD-0021; ARD-0092; docs/OgolnyZarys.txt - sekcja 5.1; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 3, 5, 11 i 13.

## ARD-0097 - Bez repozytoryjnego routera zadan prezentacyjnych

- Domena: dokumentacja, proces pracy i Codex skills
- Status / aktywny zakres: Zastapione; brak
- Zatwierdzenie: 2026-08-15
- Relacje: Zastepuje: ARD-0086/D6 | Zastapiona przez: ARD-0099/calosc
- D1. Repozytorium nie utrzymuje dedykowanego skilla ani metadanych automatycznie kierujacych zadania grafiki, animacji, VFX, shaderow, oswietlenia, map i biomow do osobnego workflow prezentacyjnego.
- D2. Zadania prezentacyjne sa wykonywane bezposrednio wedlug korzeniowego `AGENTS.md`, aktywnych ARD, dokumentu produktu, mapowania architektonicznego oraz faktycznego runtime. Nie powstaje dodatkowa repozytoryjna warstwa instrukcji miedzy tymi zrodlami a implementacja.
- D3. Usuniecie routera nie oslabia bramki rozbieznosci, wymagan dostepnosci, profili jakosci, proporcjonalnych testow ani kontroli obrazu w runtime. Ogolne klauzule ARD-0086/D1-D5,D7 pozostaja aktywne.
- D4. Zmiana procesu nie zmienia `GameState`, gameplayu, mapy semantycznej, zapisu, migracji ani podpisu swiata.
- Powod i skutek: bezposrednia praca na aktywnym rendererze i dowodzie runtime usuwa niechciana sciezke automatycznego routingu, zachowujac kanoniczne zrodla projektu oraz techniczne bramki jakosci.
- Odwolania: AGENTS.md; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 2 i 13.

## ARD-0098 - Scenowe wielokaty Godot sa zrodlem makroterenu

- Domena: swiat nurkowania, authoring mapy, topologia, fizyka i prezentacja
- Status / aktywny zakres: Zastapione w calosci
- Zatwierdzenie: 2026-08-15
- Relacje: Zastepuje: ARD-0085/D1-D3 | Zastapiona przez: ARD-0102/calosc
- D1. Jedynym semantycznym zrodlem bazowej makrogeometrii terenu jest uporzadkowany podzbior edytowalnych `Polygon2D` zapisanych w `UnderwaterMap.tscn`. Projektant zmienia ich punkty i transformacje zwyklymi uchwytami widoku 2D Godota; nie istnieje osobny edytor mapy ani drugi format authoringu.
- D2. Wielokaty deklaruja operacje otwartej wody albo pelnego terenu i sa skladane deterministycznie w kolejnosci sceny. Bazowa maska PNG, prezentacyjny SDF, segmenty kolizji, okludery i dane chunkow sa wylacznie pochodnymi tej kompozycji. Reczna edycja pochodnego PNG nie zmienia semantyki mapy, a niezgodna albo nieaktualna pochodna ma zatrzymac walidacje zamiast cicho zmienic fizyke.
- D3. Kompilator i runtime korzystaja z tego samego rasteryzatora scenowych wielokatow oraz `MapObstacle`. Pochodny raster zachowuje dotychczasowy prog przechodniosci, rozmiar swiata, deterministyczne wyprowadzanie podpisu gameplayowego i wspolna reprezentacje granic dla fizyki, renderu oraz swiatla. Identyczna geometria daje identyczny podpis, natomiast zatwierdzona zmiana topologii tworzy nowy podpis zgodnie z ARD-0100/D6.
- D4. Pierwsze przelaczenie authority wymaga deterministycznego odtworzenia dotychczasowej maski komorka w komorke. Dopoki test parytetu nie potwierdzi identycznej topologii, produkcyjny runtime pozostaje przy dotychczasowej pochodnej; migracja nie moze przesunac landmarkow, tras, stable ID ani znaczenia zapisanych postepow.
- D5. `MapObstacle` moze uzywac edytowalnego, nieregularnego wielokata zapisanego w scenie; brak wielokata zachowuje prostokatny fallback dla istniejacych instancji. Przeszkoda nadal trafia do wspolnego rastra, a `Visual Scene` pozostaje bezkolizyjna i nie ustanawia fizyki.
- D6. Bezkolizyjne wizualizacje Wspolnej Linii korzystaja z zapisanych w scenie `Path2D` i `Curve2D`. Punkty koncowe sa walidowane wobec wlascicieli gameplayowych, lecz sama krzywa wizualna nie przejmuje stanu, interakcji ani kolizji.
- D7. Artystyczne sceny biomow i landmarkow pozostaja nakladajacymi sie prefabami prezentacyjnymi. Moga korzystac z tej samej pochodnej maski/SDF do przyciecia materialu, ale nie sa zrodlem przechodniosci ani zapisu.
- D8. Zmiana authoringu nie zmienia `WorldDelta`, `DiveResult`, formatu kampanii ani zasad gracza. Kazda przyszla edycja wielokatow podlega walidacji osiagalnosci, niezmiennosci wymaganych punktow, granic chunkow, okluzji i reprezentatywnemu QA obrazu.
- Powod i skutek: cala mapa moze byc projektowana w jednym widoku 2D Godota, z edytowalnymi tunelami, nieregularnymi przeszkodami, sciezkami kabli i nakladajacymi sie scenami wizualnymi, bez rozdzielenia obrazu i fizyki na dwa recznie utrzymywane kontury.
- Odwolania: ARD-0052; ARD-0076; ARD-0085; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 9, 11, 12.3 i 13.

## ARD-0099 - Wydzielony warsztat mapy podwodnej i grafiki

- Domena: authoring mapy podwodnej, grafika swiata, dokumentacja i proces pracy
- Status / aktywny zakres: Zastapione w calosci
- Zatwierdzenie: 2026-08-16
- Relacje: Zastepuje: ARD-0086/D1,D5; ARD-0097/calosc | Zastapiona przez: ARD-0102/calosc
- D1. Repozytorium utrzymuje jeden wyspecjalizowany hub `underwater_map_workbench/` z lokalnymi `AGENTS.md`, `README.md`, `.ai/PROJECT_CONTEXT.md` i `.ai/DECISIONS.md`. Piec dokumentow korzeniowych pozostaje kanoniczne dla calego produktu, runtime, architektury, zapisu i onboardingu, a dokumenty warsztatu sa jedynym wlascicielem szczegolowego procesu produkcji grafiki mapy, lokalnego jezyka wizualnego, stanu assetow oraz akceptacji artystycznej.
- D2. Warsztat nie jest osobnym projektem Godot ani drugim formatem mapy. Nie przechowuje kopii `UnderwaterMap.tscn`, makroterenu, blueprintu, maski kolizji, `WorldDelta` ani produkcyjnych assetow; kanoniczne pliki pozostaja na istniejacych sciezkach `res://`, a warsztat kieruje praca nad nimi.
- D3. Zadania projektowania mapy, biomow, landmarkow, tla, grafiki i assetow swiata sa semantycznie routowane do `underwater_map_workbench/AGENTS.md`. Codex uruchomiony z katalogu warsztatu czyta ten blizszy plik jako punkt wejscia, a on dobiera lokalny i globalny kontekst proporcjonalnie do ryzyka; routing obowiazuje takze wtedy, gdy edytowany plik lezy poza samym katalogiem warsztatu.
- D4. Codex mapy pracuje z katalogu `underwater_map_workbench/`, majac pelny checkout projektu dostepny jako rodzica; nie dostaje samego wycietego katalogu warsztatu. Osobny pelny Git worktree i branch sa opcjonalna izolacja pracy rownoleglej, nie wymaganiem kontraktu. Integracja odbywa sie przez Git, a nie przez kopiowanie scen, pochodnych lub katalogow importu miedzy workspace'ami.
- D5. Kazde nowe albo przebudowywane szerokie tlo regionu zaczyna sie od jednej zatwierdzonej kompozycji master calego pasa. ArtCells, okna edycyjne i chunki runtime sa wylacznie deterministycznymi pochodnymi tego mastera; zestaw niezaleznie promptowanych finalnych obrazow nie moze zostac zrodlem panoramy.
- D6. Prezentacja mapy pozostaje warstwowa: dalekie sylwety i plyty, sredni plan landmarkow, skory terenu i prefaby oraz atmosfera runtime maja odrebne odpowiedzialnosci. Raster generowany lub malowany nie ustanawia przechodniosci, kolizji, stable ID ani zapisu i nie wypieka globalnej mgly, caustics, oswietlenia gameplayowego, HUD-u lub postaci.
- D7. Akceptacja panoramy wymaga jednoczesnie integralnosci technicznej, przegladu calej kompozycji, kontroli powtorzen, perspektywy, skali, palety i pustych stref oraz reprezentatywnych kadrow w runtime. Zgodny overlap, SHA, snapshot albo metryka wkładu nie sa samodzielna akceptacja artystyczna; jawne odrzucenie przez wlasciciela produktu cofa status wizualnego baseline'u bez falszowania historycznego wyniku testu.
- D8. Wydzielenie procesu nie zmienia `GameState`, `WorldDelta`, `DiveResult`, source-v4, semantycznej authority `UnderwaterMap.tscn`, formatu kampanii ani podpisu gameplayowego. Jawnie zlecona zmiana topologii lub rozmieszczenia przechodzi globalna bramke rozbieznosci, walidacje osiagalnosci i testy mapy tak samo jak praca w glownym katalogu.
- Powod i skutek: osobny Codex otrzymuje wyspecjalizowany kontekst i rygor produkcji wizualnej bez odcinania go od pelnego projektu i bez tworzenia drugiej mapy. Master-first oraz warstwowy authoring rozwiazuja problem technicznie bezszwowych, lecz kompozycyjnie niespojnych obrazow.
- Odwolania: AGENTS.md; underwater_map_workbench/AGENTS.md; underwater_map_workbench/.ai/DECISIONS.md; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 2, 9.1.2 i 13.

## ARD-0100 - Glebokosc swiata jest niezalezna od dwuwymiarowej geografii biomow

- Domena: swiat nurkowania, geografia biomow, ryzyko, prezentacja i kompatybilnosc zapisu
- Status / aktywny zakres: Czesciowo zastapione; D1, D4
- Zatwierdzenie: 2026-08-17
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0102/D2-D3,D5-D10
- D1. Fizyczna glebokosc nurka jest ciagla i monotoniczna funkcja jego bezwzglednej pozycji `Y` w kanonicznym swiecie. Nie zalezy od nazwy, prostokata ani kolejnosci regionu i nie moze skokowo zmienic sie po przekroczeniu pionowej granicy biomu na tej samej wysokosci.
- D2. Tozsamosc biomu jest dwuwymiarowa strefa authorowana w `UnderwaterMap.tscn`. Cztery stabilne ID pozostaja bez zmian, lecz tworza uklad skarpowego miasta portowego: R1 na gornym lewym tarasie, R2 na dolnym lewym tarasie, R3 jako pionowa prawa dzielnica portowo-przemyslowa, a R4 jako pelnoszeroki dolny pas.
- D3. R1 rozdziela prezentacyjna korone dachow od nizszych fasad, ulic i wnetrz bez tworzenia nowego regionu gameplayowego. R3 rozdziela gorne nabrzeze i stocznie od nizszego ciezkiego przemyslu, a R4 zachowuje podziemna i glebinowa role niezaleznie od motywow zatopionego miasta.
- D4. Efekty zalezne od cisnienia, zimna, swiatla i ryzyka probkuja wspolna fizyczna glebokosc. Paleta, material, zawiesina i tozsamosc obiektu moga dodatkowo probkowac region, lecz nie moga nadpisac ani zdublowac wlasciciela glebokosci.
- D5. `UnderwaterMap.tscn` pozostaje jedynym authority granic regionow, pozycji, tras i statycznego swiata. Wizualna maska przejsc biomow oraz mastery L00-L05 sa prezentacyjnymi pochodnymi tej sceny i nie ustanawiaja drugiej geografii.
- D6. Zatwierdzone przestawienie regionow, landmarkow, tras i obiektow zaleznch tworzy nowy `map_gameplay_signature`. Kampania ze starszym podpisem jest odrzucana bez mutacji, importu i przesuwania `WorldDelta`; nie powstaje migracja pozycyjna. Zatwierdzony clean break simple-parallax zachowuje 27 stabilnych ID landmarkow oraz rekordy 36 zwyklych polaczen i siedmiu skrotow, lecz zastepuje makroteren i przebiegi tras, dlatego stanowi nowy statyczny swiat.
- D7. Stabilne ID R1-R4, landmarkow i obiektow zachowuja znaczenie domenowe. Przeniesienie calej grupy obejmuje jej cele interaktywne, ladunek, prad, zagrozenie, trase oraz certyfikat odzyskiwalnosci, aby graf i zapis nie wskazywaly dawnej pozycji.
- D8. Mastery szerokiej grafiki zaakceptowane dla poprzedniej geografii traca status produkcyjnego authority rozmieszczenia. Po zmianie statycznego swiata wymagaja ponownego map-aware mastera, technicznej walidacji, surveyu i jawnej akceptacji przed promocja. Dotychczasowe rodziny V5-V7 oraz ich landmarkowe overlaye pozostaja wylacznie historia i provenance, nie fallbackiem produkcyjnego runtime.
- D9. Produkcyjna mapa nurkowania jest jednym ortograficznym przekrojem 2D. Plany `L00-L05` moga roznic tempo kamery i ostrosc, lecz nie tworza perspektywicznej podlogi, izometrii, sceny 2,5D ani wizualnego przejscia sprzecznego z kanoniczna maska wody.
- D10. Zabudowany landmark otrzymuje fizycznie przechodnie wnetrze wyciete w scenowym makroterenie i polaczone z grafem co najmniej jednym czytelnym wejsciem; otwarty landmark otrzymuje analogicznie osiagalna strefe centralna. Bezkolizyjny prefab pozostaje prezentacja przekroju i nie moze sam ustanawiac komory, wejscia, teleportu ani kolizji. Wnetrza naleza do tego samego swiata, podpisu mapy i certyfikacji odzyskiwalnosci.
- Powod i skutek: uklad bocznych dzielnic i dolnego rdzenia pozwala umiescic apteke, szpital, stocznie i fabryke w logicznej geografii bez falszywego skoku glebokosci na granicy koloru. Cena jest jawny clean break statycznej mapy oraz ponowna certyfikacja tras i grafiki.
- Odwolania: ARD-0052; ARD-0072; ARD-0075; ARD-0085; ARD-0092; ARD-0098; ARD-0099; docs/OgolnyZarys.txt - sekcje 6 i 7; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 5.6, 9, 11 i 13.

## ARD-0101 - Docelowy swiat nurkowania ma logiczna siatke 12 x 12 Full HD

- Domena: przestrzen swiata nurkowania, authoring mapy, balans podrozy i kompatybilnosc zapisu
- Status / aktywny zakres: Czesciowo zastapione; D1-D2
- Zatwierdzenie: 2026-08-23
- Relacje: Zastepuje: brak | Zastapiona przez: ARD-0102/D3-D9
- D1. Docelowy kanoniczny prostokat swiata ma dokladnie `23 040 x 12 960` jednostek. Jest opisywany jako logiczna siatka `12 x 12` pol kompozycyjnych Full HD po `1 920 x 1 080` jednostek; pola te nie sa klatkami kamery ani osobnymi sektorami gameplayowymi.
- D2. Rozszerzenie swiata nie zmienia kontraktu kamery: bazowy viewport pozostaje `1 280 x 720`, a staly zoom `1,20`, co pokazuje okolo `1 066,67 x 600` jednostek i daje okolo `21,6 x 21,6` rzeczywistych kadrow kamery na caly docelowy prostokat. Skala nurka, obiektow i mechanik ruchu nie jest mnozona razem z wymiarem swiata.
- D3. `UnderwaterMap.tscn` pozostaje jedynym authority calej przestrzeni. Raster makroterenu zachowuje `GRID_STEP = 8`, a indeks streamingu `chunk_size = 512`; rastry, SDF, segmenty, okludery i chunki sa ponownie wyprowadzane z nowej sceny, a nie rozciagane z poprzednich pochodnych.
- D4. Fizyczna glebokosc pozostaje jedna ciagla i monotoniczna funkcja globalnego `Y` od `8 m` przy gornej granicy do `160 m` przy dolnej granicy nowego swiata. Regiony R1-R4 zachowuja stabilne tozsamosci dwuwymiarowe i nie przejmuja authority glebokosci.
- D5. Zmiana wymiarow jest pelnym re-authoringiem statycznego swiata, a nie slepym skalowaniem `2x`. Projektant uklada na nowo makroteren, granice regionow, landmarki, portale, krzywe tras, obiekty zalezne, wejscie i wyjscie z zachowaniem dotychczasowej skali lokalnej oraz czytelnosci gameplayu.
- D6. Rdzen 27 landmarkow zachowuje stabilne ID i znaczenie domenowe. Kazdy przenoszony landmark jest authorowany i certyfikowany razem z nalezacymi do niego portalami, trasami, celami, ladunkiem, pradem, zagrozeniem oraz innymi zaleznymi rekordami; samo zachowanie ID nie jest dowodem osiagalnosci ani zgodnosci balansu.
- D7. Aktywacja nowej przestrzeni celowo tworzy nowy `map_gameplay_signature`, ale nie podnosi sama z siebie `MAP_SOURCE_VERSION = 4`, rewizji kampanii 2 ani nie zmienia modelu `WorldDelta`. Kampania z poprzednim podpisem jest odrzucana atomowo bez importu, migracji pozycyjnej, reinterpretacji lub mutacji `WorldDelta`; gracz rozpoczyna nowa kampanie dla nowego statycznego swiata.
- D8. Tlen, czas, dystans, zimno, prady, zagrozenia, ladunek, dostepne wejscia i rezerwa powrotna sa ponownie oceniane na rzeczywistych trasach. Promocja wymaga pelnej certyfikacji odzyskiwalnosci dla publicznych profili, walidacji osiagalnosci i granic, zgodnych pochodnych oraz testow persistence clean breaku.
- D9. Szeroka grafika nowego swiata powstaje master-first na docelowej geografii. Wczesniejsze mastery, cutouty i liczby elementow moga pozostac provenance lub aktywnym baseline'em starego swiata, ale nie sa automatycznie inwentarzem produkcyjnym przestrzeni `12 x 12`; szczegol akceptacji i podzialu wizualnego nalezy do warsztatu mapy.
- Powod i skutek: wiekszy swiat daje dluzsza, bardziej zroznicowana eksploracje bez pomniejszenia lokalnego gameplayu i bez pozornego zachowania kompatybilnosci zapisow. Cena jest ponowne authorowanie geografii, grafiki i tras oraz pelna recertyfikacja przed przelaczeniem runtime.
- Odwolania: ARD-0013; ARD-0052; ARD-0072; ARD-0075; ARD-0092; ARD-0098; ARD-0099; ARD-0100; docs/OgolnyZarys.txt - sekcje 6 i 7; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 9, 11 i 13; underwater_map_workbench/.ai/DECISIONS.md.

## ARD-0102 - Manifest warsztatu jest jedynym zrodlem mapy source-v5

- Domena: mapa podwodna, authoring, runtime, tutorial, zapis, testy i granice modulow
- Status / aktywny zakres: Czesciowo zastapione; D4-D7 oraz D1,D9 w zakresie mapy swiata obowiazuja, D2-D3,D8,D10 obowiazuja poza zakresem zagniezdzonych pakietow struktur; zakres avatara w D1,D9 zastapiony przez ARD-0105/D1-D5, a zakres struktur przez ARD-0106/D1-D9
- Zatwierdzenie: 2026-08-25
- Relacje: Zastepuje: ARD-0043/D2; ARD-0072/calosc; ARD-0075/D1-D2,D4,D6,D11-D12; ARD-0077/D3; ARD-0085/D6; ARD-0098/calosc; ARD-0099/calosc; ARD-0100/D2-D3,D5-D10; ARD-0101/D3-D9 | Zastapiona przez: ARD-0105/D1-D5 tylko w ARD-0102/D1,D9 w zakresie avatara gracza oraz ARD-0106/D1-D9 w ARD-0102/D2-D3,D8,D10 w zakresie zagniezdzonych pakietow struktur
- D1. `underwater_map_workbench/` jest wlascicielem calego aktywnego pakietu konkretnej mapy i jej worldowych grafik: `map_manifest.json`, deterministycznie generowanej `UnderwaterMap.tscn`, lokalnego kompilatora i cienkiego hosta w `runtime/`, `tools/build_underwater_map.py`, `tests/underwater_map_smoke_test.gd`, shaderow srodowiska oraz lokalnego `assets/`. Korzen projektu zachowuje ogolne mechaniki nurkowania, dane domenowe, integracje Godot i ogolny runner testow, a `diver_workbench/` zachowuje avatar gracza. Zaden z tych wlascicieli nie utrzymuje kopii plikow pozostalych domen.
- D2. `map_manifest.json` jest jedynym semantycznym zrodlem topologii, granic, pozycji, identyfikatorow i zawartosci konkretnej mapy. `UnderwaterMap.tscn` jest jego deterministyczna pochodna i nie podlega recznej edycji; builder ma umiec zbudowac scene oraz wykryc jej dryf wzgledem manifestu.
- D3. Promowalna mapa ma dokladnie logiczna siatke `12 x 12` pol po `1 920 x 1 080` jednostek, czyli prostokat `23 040 x 12 960`. Manifest jest jedynym wlascicielem liczby instancji, ich identyfikatorow, wspolrzednych i szczegolowej topologii; ARD nie zamraza migawki zawartosci konkretnej rewizji.
- D4. Dawne cztery regiony, 27 landmarkow, polaczenia, skroty, makroteren, maski, warianty graficzne i pipeline'y V1-V7 nie sa fallbackiem ani drugim zrodlem nowej mapy. Liczba i ksztalt stref, warstw i pozostalych rekordow sa walidowanymi danymi biezacego manifestu.
- D5. Promocja mapy wymaga przypisanej w manifeście i osiagalnej sekwencji semantycznych urzadzen `junction_j7` -> `archive_terminal` -> `r3_diagnostic_panel` -> `r3_generator` -> `c4_switchboard` -> `c4_splitter_mount`. Szczegolowe instancje, landmarki i trasy realizujace ten kontrakt nie sa okreslane w ARD.
- D6. Reset mapy nie usuwa, nie wylacza ani nie bramkuje ogolnych systemow tlenu, lootu, interakcji, ekwipunku, powrotu, tutorialu lub kampanii. J-7, Archiwum, diagnostyka i generator R-3, rozdzielnica C-4 oraz gniazdo montazu rozgaleznika pozostaja aktywnymi elementami Wspolnej Linii z dialogiem, quick-flow i logika progresji; sam montaz rozgaleznika jest wyborem opcjonalnym, ale jego osiagalne gniazdo nalezy do kontraktu promowalnej mapy. Mapa niespelniajaca sekwencji z D5 nie moze zostac promowana jako kompletna mapa kampanii.
- D7. Nowa mapa publikuje `map_source_version = 5` i stanowi celowy clean break. Zapis z poprzednim podpisem lub wersja mapy jest odrzucany atomowo bez skalowania pozycji, migracji rekordow, reinterpretacji `WorldDelta` ani uruchamiania starej mapy jako fallbacku.
- D8. Jedynym testem specyficznym dla formatu i technicznej spojnosci pakietu mapy jest lokalny `underwater_map_smoke_test.gd`; sprawdza walidacje manifestu, deterministycznosc i ladowanie sceny oraz integracje kompilatora z runtime. Jeden korzeniowy test graniczny kampania-manifest sprawdza obecnosc i unikalnosc semantycznych urzadzen z D5 oraz przypisanie kazdego z nich do istniejacego landmarku, bez nawigacji, wspolrzednych, liczby pozostalych obiektow, regionow ani grafiki. Faktyczna osiagalnosc i jakosc tras sa bramka recznego playtestu, nie automatycznym BFS-em ani warunkiem wygenerowania sceny. Pozostale testy ogolnych mechanik nurkowania, tutorialu i kampanii pozostaja w korzeniu i nie powielaja topologii manifestu.
- D9. Kazda przyszla zmiana granicy albo konkretnej instancji mapowej, w tym jej identyfikatora, roli i pozycji, przechodzi przez manifest i lokalny builder. Nowe identyfikatory landmarkow i ich pozycje pochodza wylacznie z manifestu; dawne `R1-09`, `R3-04` i `R4-06` nie sa wartosciami domyslnymi ani fallbackiem. Nowe grafiki swiata konkretnej mapy trafiaja wyłącznie do lokalnego `assets/`; grafiki avatara trafiaja wyłącznie do `diver_workbench/assets/`. Manifest wskazuje asset tylko wtedy, gdy ustanawia jego uzycie przez konkretna instancje lub warstwe mapy. Nie utrzymuje sie wersji alternatywnych, kandydatow produkcyjnych, recznie poprawianych kopii sceny ani mapowo-zaleznych testow starego swiata.
- D10. Dokumenty korzeniowe opisuja przekrojowa konsekwencje dla produktu, architektury, zapisu i integracji, a krotkie dokumenty warsztatu sa operacyjnym wejsciem dla calego pakietu konkretnej mapy. Lokalne MAP-ARD sa wlascicielem biezacego schema, osi rewizji oraz prezentacyjnego pipeline'u `L00-L10`; uszczegolawiaja ten kontrakt bez przejmowania globalnych regul gameplayu, persistence i testow domenowych.
- Powod i skutek: jedna mapa i jeden manifest usuwaja sprzeczne wersje oraz rozproszone authority, zachowujac kompletna os aktywnej kampanii jako kontrakt promocji zamiast zamrazac przejsciowa migawke odbudowy. Cena jest swiadomy brak kompatybilnosci pozycyjnej ze starym swiatem oraz ponowne authorowanie rozmieszczenia od zera.
- Odwolania: ARD-0013; ARD-0077; ARD-0092; ARD-0100/D1,D4; ARD-0101/D1-D2; underwater_map_workbench/.ai/DECISIONS.md; docs/OgolnyZarys.txt - sekcje 6-7; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 2, 9, 11 i 13.

## ARD-0103 - Liniowe filtrowanie jest domyslem widocznej grafiki 2D

- Domena: prezentacja 2D, assety i rendering
- Status / aktywny zakres: Obowiazuje; D1-D6
- Zatwierdzenie: 2026-08-25
- Relacje: Zastepuje: brak | Zastapiona przez: brak
- D1. Projektowy domyslny filtr tekstur `CanvasItem` jest liniowy. Widoczne bitmapy 2D nie uzywaja pixel artu ani filtrowania `nearest` jako wspolnego jezyka prezentacji.
- D2. Zwykly `CanvasItem` dziedziczy projektowy domysl zamiast powielac lokalny override. Jawny filtr jest dozwolony tylko wtedy, gdy konsument ma odmienny kontrakt probkowania, w szczegolnosci render target, rzeczywiste mipmapy albo wlasny sampler shadera.
- D3. Dyskretna maska techniczna, raster semantyczny lub lookup zachowuje `nearest` u swojego konsumenta, jezeli interpolacja zmienialaby granice albo znaczenie danych. Taki wyjatek nie ustanawia stylu widocznej grafiki.
- D4. Parametry `sampler2D` deklaruja filtr zgodny z rola probkowanej tekstury. Tekstury 3D nadal podlegaja ustawieniom importu i materialu, a nie globalnemu filtrowi canvas.
- D5. Mipmapowy filtr jest poprawny tylko dla zasobu, ktory rzeczywiscie ma mipmapy i jest pomniejszany w sposob uzasadniajacy ten koszt; brak mipmap oznacza zwykle filtrowanie liniowe albo korekte importu, nie fikcyjny override.
- D6. Pokrycie chroni projektowy domysl i semantycznie odmienne wyjatki. Testy scen i buildery nie wymagaja lokalnego `Linear` na kazdej bitmapie i nie tworza drugiej listy wezlow prezentacyjnych.
- Powod i skutek: jeden globalny kontrakt usuwa pozostalosci pixel-artowego skalowania i lokalne obejscia, zachowujac precyzje masek danych oraz jawne wymagania render targetow, shaderow i mipmap.
- Odwolania: docs/OgolnyZarys.txt - sekcja 1; docs/Ostatni_Pomost_architektura_Godot.txt - sekcja 12.0; underwater_map_workbench/.ai/DECISIONS.md.

## ARD-0104 - Wchodnia struktura mapy ma jeden root i rozlaczny podzial kolizji L05

- Domena: mapa podwodna, statyczna fizyka, runtime, interakcje i kompatybilnosc zapisu
- Status / aktywny zakres: Zastapiona w calosci; brak aktywnego zakresu
- Zatwierdzenie: 2026-08-25
- Relacje: Doprecyzowuje ARD-0052 i ARD-0102/D2-D3,D7-D9 | Zastapiona przez: ARD-0106/calosc
- D1. `map_manifest.json` typuje wielokrotnego uzytku szablony wchodnich struktur oraz ich niezalezne instancje. Jedna instancja ma jedno stabilne ID, jeden origin, rozmiar, lokalne sockety i opcjonalnie powiazany landmark; neutralna instancja moze nie publikowac `landmark_id`, a obecne pole musi wskazywac istniejacy rekord. Liczba instancji wynika wylacznie z manifestu i nie jest ograniczona przez kontrakt pierwszego wiezowca.
- D2. Jeden hash-pinned payload L05 nadal jest jedynym semantycznym zrodlem statycznego podzialu `solid/open_water`. Operacje struktury sa zapisane lokalnie i transformowane przez origin instancji podczas kompilacji. Kanoniczny digest identyfikuje globalna geometrie, a osobny digest partycji identyfikuje wlasciciela kazdej stalej komorki; grafika, scena ani collider runtime nie staja sie drugim zrodlem ksztaltu.
- D3. Deterministyczna `UnderwaterMap.tscn` moze zawierac generowany `StructureRoots`, poniewaz pozostaje pochodna manifestu i payloadu. Kazde dziecko instancji grupuje logiczna prezentacje w rolach L04/L05, lokalny statyczny collider oraz korzenie przyszlych obiektow dynamicznych i interaktywnych. `VisualLayers/L00-L10` pozostaja wolne od fizyki; wyjatek strukturalny znajduje sie poza nimi i nie zmienia polityki slotow.
- D4. Nawigacja uzywa jednego globalnego rastra, lecz kazda statyczna krawedz fizyki ma dokladnie jednego wlasciciela. Krawedzie `world` trafiaja do streamowanych globalnych chunkow, a krawedzie instancji do jej lokalnego `StaticBody2D`; ich zbiory sa rozlaczne, a po transformacji rootem ich unia jest dokladnie pelna granica rastra L05. Brak albo niespojna partycja jest bledem, nie zgoda na globalny fallback dublujacy collider.
- D5. Rekord gameplayowy zakotwiczony w strukturze przechowuje stable ID, `structure_id` i lokalna pozycje. Kompilator wylicza pozycje globalna dla ogolnych konsumentow, a runtime rodzicuje instancje pod wspolnym rootem. Przesuniecie struktury zmienia jeden origin, wymaga przebudowy i nowego `map_gameplay_signature`, ale nie zmienia znaczenia trwałego ID ani nie tworzy migracji pozycyjnej `WorldDelta`.
- D6. Root statycznej struktury nie porusza sie podczas sesji; jego przestawienie jest operacja authoringu manifestu. Ruchoma winda, drzwi i inne zmienne przeszkody otrzymuja osobne `AnimatableBody2D` lub wlasciwy typ dynamiczny wraz ze zgodnymi stanami grafiki i fizyki; nie sa wypiekane jako zamkniete w bazowym L05 i nie dodaja checkpointu ani nowej semantyki zapisu.
- D7. Dalekie nieblokujace L01 i L02 pozostaja niezmienione za bliska struktura. Wchodni budynek moze je naturalnie zaslaniac world-locked prezentacja, ale nie usuwa ich, nie przenosi i nie przejmuje ich paralaksy. Produkcyjna grafika struktury nadal wymaga aktualnego pakietu prawdy, odbioru proxy w faktycznej scenie i symetrycznej kontroli grafika-kolider.
- Powod i skutek: pojedynczy root pozwala przeniesc caly budynek z fizyka, prezentacja i obiektami przez jedna zmiane manifestu, a jawny podzial wlascicieli zachowuje jeden raster nawigacji bez podwojnych colliderow. Stable ID utrzymuja ogolny obieg kampanii i zapisu, natomiast nowa pozycja pozostaje swiadomym clean breakiem podpisu mapy.
- Odwolania: ARD-0052; ARD-0102; docs/OgolnyZarys.txt - sekcje 6-7; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 9.1 i 9.2; underwater_map_workbench/.ai/DECISIONS.md.

## ARD-0105 - Warsztat nurka jest jedynym authority avatara gracza

- Domena: avatar gracza, fizyka postaci, prezentacja 2D, assety, testy i routing pracy
- Status / aktywny zakres: Obowiazuje; D1-D7
- Zatwierdzenie: 2026-08-26
- Relacje: Zastepuje: ARD-0102/D1,D9 tylko w zakresie avatara gracza | Zastapiona przez: brak
- D1. `diver_workbench/` jest drugim zatwierdzonym warsztatem domenowym wewnatrz tego samego projektu Godot. Nie posiada osobnego `project.godot`, InputMap, ustawien fizyki, cache projektu ani kopii ogolnych systemow nurkowania; uruchomienie i testy zawsze korzystaja z projektu nadrzednego.
- D2. Warsztat nurka jest jedynym wlascicielem aktywnej sceny `Diver.tscn`, adaptera `DiverController`, fizycznej bryly `CharacterBody2D`, `DiverVisualEffects`, definicji i profilu socketow, arkuszy i zasobu animacji, shaderow avatara oraz lokalnych testow i capture'u tej prezentacji. Pliki sa ladowane bezposrednio spod `res://diver_workbench/`; root i warsztat mapy nie utrzymuja kopii ani posredniej sceny avatara.
- D3. Korzen projektu pozostaje wlascicielem `DiveController`, `DiveMovementSystem`, wejscia, tlenu, ryzyka, walki, ekwipunku, interakcji, `DiveSessionState`, `DiveResult`, UI, persistence i integracji z mapa. Root komunikuje sie ze scena avatara przez publiczne metody, sygnaly, transform rootu i token grupy `DiverController.DIVE_PLAYER_GROUP`; nie zapisuje prywatnych pol ruchu ani nie zamraza hierarchii prezentacji. `InteractionRange` pozostaje dzieckiem sceny avatara, lecz jego znaczenie gameplayowe jest kontraktem globalnym; zmiana zasiegu ani parametrow ruchu nie jest lokalnym tuningiem grafiki.
- D4. `underwater_map_workbench/` zachowuje jedyne authority konkretnej mapy, jej topologii, sceny pochodnej, strukturalnej grafiki i worldowych assetow gameplayowych. Nie jest wlascicielem poddrzewa grafiki nurka, nie laduje go w lokalnym smoke i nie sprawdza jego wnetrza; rootowa integracja sklada publiczne sceny obu warsztatow przez ogolny runtime.
- D5. `diver_workbench/{AGENTS.md,README.md,.ai/PROJECT_CONTEXT.md,.ai/DECISIONS.md}` jest zatwierdzonym lokalnym zestawem dokumentow. Lokalny routing moze zawęzic kontekst do avatara, ale nie moze przejac regul produktu, domeny wyprawy, persistence ani topologii mapy.
- D6. Lokalny test prezentacji chroni montaz sceny, animacje, sockety, VFX i niezmiennosc fizycznego kontraktu, a co najmniej jeden test korzeniowy zachowuje rzeczywista integracje `DiveScene -> Diver` wyłącznie przez publiczna granice. Rootowe i mapowe testy nie powielaja nazw klipow, liczby klatek, prywatnych wezlow VFX ani innych lokalnych fixture'ow avatara. Wspolny runner przyjmuje bezposrednie cele spod `diver_workbench/tests/` i nadal uruchamia wszystkie instancje Godot sekwencyjnie w izolowanej kopii projektu.
- D7. Pierwsze przeniesienie jest refaktorem bez zmiany widocznego zachowania, skali, collidera, zasiegu, socketow, oswietlenia i formatu zapisu. Nie zmienia rewizji kampanii ani podpisu mapy. Kazda pozniejsza zmiana rozmiaru, collidera, punktu emisji swiatla, zasiegu interakcji albo mechaniki ruchu musi najpierw przejsc wlasciwa bramke produktu i architektury oraz proporcjonalne testy lokalne i integracyjne.
- Powod i skutek: agent pracujacy nad nurem otrzymuje jeden skupiony katalog ze scena, fizyka, grafika, animacja i narzedziami kontroli, bez kopiowania calego projektu ani mieszania authoringu avatara z authoringiem konkretnej mapy. Cena jest jawna granica integracji z systemami root oraz obowiazek ponownej weryfikacji przy kazdej zmianie fizycznej koperty gracza.
- Odwolania: ARD-0102; ARD-0103; docs/OgolnyZarys.txt - sekcje 6-7; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 2, 5, 12.3 i 13; diver_workbench/.ai/DECISIONS.md; underwater_map_workbench/.ai/DECISIONS.md.

## ARD-0106 - Wchodnia struktura jest podrzednym pakietem mapy

- Domena: mapa podwodna, pakiety struktur, authoring, runtime, zapis i testy
- Status / aktywny zakres: Obowiazuje; D1-D9
- Zatwierdzenie: 2026-08-26
- Relacje: Zastepuje ARD-0104/calosc oraz ARD-0102/D2-D3,D8,D10 w zakresie zagniezdzonych pakietow struktur; doprecyzowuje ARD-0102/D1,D9 | Zastapiona przez: brak
- D1. Kazda wchodnia struktura z prywatnym gameplayem jest mapowym pakietem `underwater_map_workbench/structures/<structure_id>/`. Pakiet posiada `structure_manifest.json`, prywatne skrypty runtime, lokalna topologie, assety, deterministyczne pochodne, testy oraz dokladnie lokalne `AGENTS.md` i `README.md`. Nie jest osobnym projektem Godot, trzecim warsztatem domenowym ani niezalezna biblioteka.
- D2. `map_manifest.json` pozostaje jedynym wlascicielem rejestracji i globalnego placementu struktury: stable ID instancji, jednego `origin`, aktywnosci, opcjonalnego `landmark_id` oraz hash-pinned sciezki pakietu. Nie powtarza lokalnego rozmiaru, socketow, topologii, grafiki, skryptow ani konfiguracji runtime. Tozsamosc pakietu wynika z mapowego stable ID i odpowiadajacej mu nazwy katalogu; podrzedny manifest nie utrzymuje drugiego pola `structure_id`.
- D3. `structure_manifest.json` jest podrzednym authority wylacznie lokalnej zawartosci jednego budynku: formatu i szablonu, lokalnego rozmiaru, operacji kolizji, socketow, prezentacji, skryptow, danych runtime oraz deklaracji cyklu zycia proby. Nie publikuje globalnego originu, mapowego landmarku, pozycji instancji, kampanii, `WorldDelta` ani semantyki zapisu. Wzgledne sciezki sa rozwiazywane od katalogu pakietu i nie moga z niego wychodzic.
- D4. Builder sklada globalny payload swiata i lokalne operacje aktywnych pakietow w jeden raster `solid/open_water` oraz jedna rozlaczna partycje wlascicieli. Lokalna geometria jest transformowana wylacznie przez mapowy `origin`. `UnderwaterMap.tscn`, maski, collider runtime i pliki pod `generated/` pozostaja deterministycznymi pochodnymi, a nie kolejnym authority.
- D5. Wszystkie skrypty, assety, referencje produkcyjne i testy uzywane wylacznie przez jedna strukture naleza do jej pakietu. Prywatny skrypt nie publikuje globalnego `class_name`; root i mapa laduja go po hash-pinned sciezce zadeklarowanej w pakiecie i montuja przez wspolny kontrakt cyklu zycia, bez hardkodowania ID, klasy albo sciezki konkretnego budynku. Wspolny mechanizm uzywany przez wiele domen moze pozostac u ogolnego wlasciciela i jest konsumowany jako publiczna zaleznosc, nie kopiowany do pakietu.
- D6. Stan windy, drzwi, przelacznikow i zagadek obowiazuje wylacznie podczas biezacej proby. Pakiet moze deklarowac `attempt_state.persistence=none` i `attempt_state.checkpoint=none`, ale nie tworzy checkpointu, lokalnego odrodzenia ani zapisu do `DiveSessionState`, `WorldDelta` lub kampanii. Przyszly trwaly obiekt wymaga osobnej decyzji root i jawnego eksportu mapowego; nie moze zostac ukryty w prywatnym stanie pakietu.
- D7. Rozdzielenie zrodla podnosi format manifestu mapy do schema v6, pozostawiajac `map_source_version = 5`, poniewaz nie zmienia swiata ani znaczenia istniejacej kampanii. Swiezosc sceny obejmuje manifest mapy i hash-pinned zestaw pakietow. Czysta relokacja semantycznie identycznych danych nie zmienia `map_gameplay_signature`; zmiana gameplayu, lokalnej topologii, socketu, stable ID albo mapowego originu zmienia podpis, a zmiana wylacznie grafiki zmienia fingerprint prezentacji.
- D8. `AGENTS.md` pakietu okresla proces, routing i granice zapisu, a `README.md` wylacznie ownership, zrodla prawdy i komendy. Nie powtarzaja regul gameplayu, decyzji, persistence ani datowanej migawki. Globalne zachowanie widoczne dla gracza pozostaje w `docs/OgolnyZarys.txt`, techniczne mapowanie przekrojowe w architekturze, a trwale decyzje strukturalne w globalnym ARD i lokalnym MAP-ARD. Dokument lub obraz provenance moze pozostac w pakiecie tylko jako jawne `authority=false` i nie jest wejsciem implementacji.
- D9. Prywatna iteracja pakietu uzywa celowanego refresh/build/check jednej struktury oraz jej testu kontraktu i runtime. Pelny build/check i smoke Mapy sa bramka rejestracji, zmiany originu, publicznego montazu albo odbioru integracyjnego, a nie obowiazkiem po kazdej prywatnej zmianie. Rootowe testy sprawdzaja tylko publiczne zlozenie, reset proby oraz brak wejscia do persistence i nie zamrazaja lokalnych kombinacji, socketow, originu ani prywatnej hierarchii. Zmiana topologii nadal wymaga recznego przeplyniecia, a zmiana widocznej grafiki natywnego capture'u i oceny czlowieka.
- Powod i skutek: agent jednego budynku otrzymuje skupiony, samowystarczalny pakiet lokalnej geometrii, grafiki i zachowania bez powielania placementu mapy, regul produktu albo zapisu. Mapa zachowuje jedno authority globalnego ulozenia i jedna wynikowa fizyke, a kolejne budynki nie wymagaja rozbudowy root o prywatne klasy i fixture'y pierwszego wiezowca.
- Odwolania: ARD-0052; ARD-0102; docs/OgolnyZarys.txt - sekcje `[AKTYWNE] - BIEZACY NEUTRALNY PROTOTYP WIEZOWCA` i `[DOCELOWE] - ARCHIWUM W PIWNICY I DEDUKCYJNA SEKWENCJA A-D`; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 2, 9.1 i 13; underwater_map_workbench/.ai/DECISIONS.md.

## ARD-0107 - Archiwum wiezowca rozdziela prywatna probe od trwalego skutku swiata

- Domena: kampania, nurkowanie, mapa podwodna, pakiet struktury, persistence i testy
- Status / aktywny zakres: Obowiazuje; D1-D8
- Zatwierdzenie: 2026-08-26
- Relacje: Doprecyzowuje ARD-0002/D2, ARD-0102/D2,D5-D8 oraz ARD-0106/D2-D3,D6,D9 | Zastapiona przez: brak
- D1. Prywatny kontroler pierwszego wiezowca pozostaje jedynym wlascicielem stanu zagadki A-D, ruchu pustego wozka, drzwi, blokad i lokalnych skrotow podczas jednej proby. Ten stan nie przechodzi do `DiveSessionState`, `DiveResult`, `WorldDelta` ani kampanii i po resecie lub nowej instancji wraca do poczatku.
- D2. `map_manifest.json` jest jedynym wlascicielem publicznej rejestracji terminala Archiwum, trwalego skrotu piwnica-ocean, ich stable ID, zakotwiczenia w strukturze oraz globalnej topologii przejscia do podziemnych tuneli. Pakiet wiezowca zachowuje lokalne sockety, kolizje i warunek ukonczenia proby, ale nie publikuje identyfikatorow kampanii ani nie opisuje zewnetrznej sieci Mapy.
- D3. Publiczna granica kontrolera struktury moze ujawnic wylacznie generyczny stan gotowosci ukonczenia proby. Root i Mapa nie odczytuja prywatnych dzwigni, kodow, etapow D ani hierarchii wezlow, a kontroler pakietu nie wyszukuje terminala po globalnym ID i nie mutuje ogolnego stanu sesji.
- D4. Typowane powiazanie publicznego urzadzenia stalego z publicznym skrotem nalezy do rekordu Mapy i jest walidowane razem z istnieniem obu stable ID. Po spelnieniu generycznej bramki proby aktywacja terminala Archiwum dodaje do lokalnego wyniku sesji zarowno ID urzadzenia, jak i ID otwartego skrotu; prywatny pakiet nie zapisuje tego powiazania i nie wykonuje transakcji.
- D5. Dopiero bezpiecznie zakonczona wyprawa przenosi oba skutki przez `DiveResult`; ogolny system persistence dopisuje je idempotentnie do `WorldDelta.activated_fixed_devices` i `WorldDelta.opened_shortcuts`, a system kampanii wyprowadza z aktywacji terminala istniejacy postep Archiwum. Smierc, retry albo rezygnacja przed bezpiecznym powrotem nie zatwierdzaja tych skutkow.
- D6. Ponowna wyprawa odtwarza publiczny skrot jako otwarty z `WorldDelta`, ale tworzy swieza prywatna probe A-D. Trwale otwarcie nie zamienia lokalnej zagadki w checkpoint, nie dodaje lokalnego odrodzenia i nie usuwa fizycznej drogi powrotnej do aktywnej liny.
- D7. Rozszerzenie korzysta z istniejacych kolekcji `activated_fixed_devices` i `opened_shortcuts`, wiec nie dodaje pola ani migracji formatu kampanii. Zmiana stable ID, topologii, zakotwiczenia albo publicznego powiazania zmienia `map_gameplay_signature` i podlega istniejacemu clean breakowi bez reinterpretacji starszego `WorldDelta`.
- D8. Pakiet wiezowca testuje pelna prywatna dedukcje, bledy, reset, bezpieczenstwo wozka i droge powrotna bez fikcyjnej persistence. Mapa testuje rejestracje, powiazanie stable ID, zakotwiczenie i topologie tuneli, a Root testuje publiczna bramke, wynik wyprawy, idempotentny zapis i odtworzenie skrotu bez kopiowania prywatnych fixture'ow A-D. Odbior konczy reczne przeplyniecie pelnej petli prawdziwym nurkiem.
- Powod i skutek: Archiwum moze byc kampanijnym skutkiem prywatnego budynku bez oddawania pakietowi kontroli nad zapisem i bez hardkodowania jego zagadki w Root albo Mapie. Rozdzielone authority pozwala agentom rozwijac Tower, Mape i kampanie rownolegle, a wspolna integracja sklada sie dopiero przez male, publiczne kontrakty.
- Odwolania: ARD-0002; ARD-0102; ARD-0106; docs/OgolnyZarys.txt - sekcja `[DOCELOWE] - ARCHIWUM W PIWNICY I DEDUKCYJNA SEKWENCJA A-D`; docs/Ostatni_Pomost_architektura_Godot.txt - sekcje 9.1, 9.2, 10 i 13.

## ARD-0108 - Historyczny lokalny model integratora i receiptow

- Domena: proces wytwarzania
- Status / aktywny zakres: Zastapione; brak aktywnego zakresu
- Zatwierdzenie / zastapienie: 2026-08-26 / 2026-08-28
- Relacje: Historycznie doprecyzowywalo ARD-0099, ARD-0102, ARD-0105 i ARD-0106 | Zastapiona przez: ARD-0111/calosc
- D1. Wpis historycznie wymagal lokalnego integratora, receiptow, LKG, immutable hand-offow i lokalnej promocji; mechanizmy te nie sa juz kontraktem pracy.
- Powod i skutek zastapienia: model chronil wspolny checkout kosztem rozbudowanej obslugi procesu. ARD-0111 zachowuje worktrees, galezie, izolacje testow i zielone `main`, przenoszac pelna bramke do merge queue.
- Odwolania: ARD-0111; AGENTS.md.

## ARD-0109 - Historyczny assignment i ACK

- Domena: koordynacja agentow
- Status / aktywny zakres: Zastapione; brak aktywnego zakresu
- Zatwierdzenie / zastapienie: 2026-08-27 / 2026-08-28
- Relacje: Historycznie doprecyzowywalo ARD-0108 | Zastapiona przez: ARD-0111/calosc
- D1. Wpis historycznie wymagal bundle'a assignmentu, ACK, write-setu, redispatchu i close; zadne z nich nie jest juz warunkiem rozpoczecia, zakonczenia ani scalenia zadania.
- Powod i skutek zastapienia: koordynacja pochlaniala uwage autora bez poprawy samego wdrozenia. Rozdzielne worktrees i zwykly przeplyw PR zapewniaja potrzebna izolacje.
- Odwolania: ARD-0111; AGENTS.md.

## ARD-0110 - Historyczny shardowany control-plane z attesterem

- Domena: CI i integracja agentow
- Status / aktywny zakres: Zastapione; brak aktywnego zakresu
- Zatwierdzenie / zastapienie: 2026-08-27 / 2026-08-28
- Relacje: Historycznie doprecyzowywalo ARD-0108 i ARD-0109 | Zastapiona przez: ARD-0111/calosc
- D1. Wpis historycznie wymagal receiptow shardow, agregatora, App attestera, auto-integratora i osobnego audytu po merge; szczegoly te nie sa juz kontraktem CI.
- Powod i skutek zastapienia: ochrona `main` ma wynikac z pelnego testu merge group przed scaleniem, a nie z wlasnego protokolu dowodowego i testu finalnego kodu dopiero po merge.
- Odwolania: ARD-0111; docs/Ostatni_Pomost_architektura_Godot.txt - integracja i testy.

## ARD-0111 - Merge queue chroni main, a builder publikuje grywalne current

- Domena: integracja zmian, CI i publikacja buildow
- Status / aktywny zakres: Obowiazuje; D1-D9
- Zatwierdzenie: 2026-08-28
- Relacje: Zastepuje ARD-0108/calosc, ARD-0109/calosc i ARD-0110/calosc | Zastapiona przez: brak
- D1. Jedno zadanie ma jeden pelny Git worktree, jedna galaz `codex/<owner>/<task-slug>` i jeden logiczny PR. Autor wdraza zmiane w swojej domenie, uruchamia proporcjonalne testy lokalne i nie pushuje bezposrednio do `main`.
- D2. `fast-check` daje szybka informacje zwrotna dla PR, ale nie certyfikuje `main`. Pelna bramka `integration-green` uruchamia sie w merge queue na merge group skladajacej aktualny `main` i dany PR.
- D3. PR jest scalany metoda squash dopiero po pelnym `PASS` merge group. Czerwony wynik wraca do autora i nie trafia do `main`; dzieki temu `main` zawsze oznacza najnowszy kod po pelnej regresji.
- D4. Lokalny czysty mirror `main` wykonuje kolejno sprawdzenie czystosci, `fetch`, fast-forward do `origin/main` i pobranie Git LFS. Dirty stan zatrzymuje synchronizacje; automat nie uzywa `reset --hard` ani nie usuwa zmian.
- D5. Builder dziala dopiero po scaleniu i bierze exact finalne SHA `main`. Pobiera Git LFS, wykonuje finalny build oraz smoke i publikuje niezmienny artefakt pod `builds/by-sha/<SHA>`.
- D6. Wskaznik `builds/current` przesuwa sie atomowo tylko po poprawnym buildzie i smoke exact SHA. Porazka pozostawia poprzednie `current`; `current` oznacza wiec najnowszy pelnozielony `main`, ktory dodatkowo poprawnie sie zbudowal.
- D7. GitHub chroni workflowy, narzedzia CI, konfiguracje `integration-green` i control-plane buildera. Zwykly PR nie zmienia tych sciezek, a rzadka zmiana korzysta z osobnego PR i recznej zgody wlasciciela; nie wymaga drugiego agenta oceniajacego pierwszego.
- D8. Worktrees, lokalne testy i procesy Godota zachowuja osobne `.godot`, `user://`, cache, build, temp, logi, porty i capture. Rownoleglosc nie moze wspoldzielic zapisywalnego workspace ani danych uzytkownika.
- D9. Assignmenty, ACK, lokalne LKG, candidate/run receipty, FROZEN hand-offy, App attester, auto-integrator, agenci-audytorzy i rozmowy miedzy agentami nie naleza do procesu. Szczegoly wykonania CI pozostaja wymienne, o ile zachowuja D2-D8.
- Powod i skutek: autor skupia sie na implementacji oraz adekwatnych testach, merge queue chroni kod zrodlowy przed efektem domina, a prosty builder chroni grywalny artefakt. Powstaja dwa czytelne poziomy stabilnosci: pelnozielony `main` i dodatkowo zbudowane `current`.
- Odwolania: AGENTS.md; README.md; docs/Ostatni_Pomost_architektura_Godot.txt - integracja, runner i builder; .ai/PROJECT_CONTEXT.md - stan wdrozenia.
