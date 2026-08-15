class_name NarrativeContent
extends RefCounted

const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const NarrativeAudioCatalogScript := preload("res://scripts/ui/NarrativeAudioCatalog.gd")

const ROLE_HARBOR_VOICE := "harbor_voice"
const ROLE_TECHNICAL_VOICE := "technical_voice"


static func tutorial_message(step: int) -> Dictionary:
	var interact_prompt := InputPromptScript.action_text(&"dive_interact")
	var sprint_prompt := InputPromptScript.action_text(&"dive_sprint")
	var inventory_prompt := InputPromptScript.action_text(&"dive_inventory")
	var message := {
		"key": "tutorial_%d" % step,
		"kind": "tutorial",
		"scene": "base",
		"speaker_id": "mira",
		"speaker_name": "Mira Boruta",
		"speaker_role": "GŁOS PRZYSTANI",
		"compact_title": "SAMOUCZEK",
		"dialogue_title": "BIEŻĄCY CEL",
		"narrative_title": "GŁOS PRZYSTANI",
		"narrative_body": "",
		"body": "",
		"callout_layout": "left_top",
	}
	match step:
		TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE:
			message.compact_title = "DZIEŃ 1  •  PIERWSZY DACH"
			message.dialogue_title = "ODBUDUJ DOM WSPÓLNOTY I"
			message.narrative_title = "PIERWSZY DACH"
			message.narrative_body = "Nie utrzymamy tych ludzi samą nadzieją. Potrzebujemy miejsca, w którym znów będziemy wspólnotą — choćby na razie były to tylko cztery suche ściany."
			message.body = "Otwórz podświetloną ruinę Domu Wspólnoty i wybierz odbudowę poziomu I. Dom jest centrum załogi: po odbudowie przydzielisz tu mieszkańca do pracy."
		TutorialStateScript.Step.BUILD_DIVING_STATION:
			message.compact_title = "DZIEŃ 1  •  DROGA W DÓŁ"
			message.dialogue_title = "ODBUDUJ STACJĘ NURKOWĄ I"
			message.narrative_title = "DROGA W DÓŁ"
			message.narrative_body = "Na powierzchni zostały nam ruiny. Pod wodą leży wszystko, co morze zabrało światu — zapasy, narzędzia i odpowiedzi. Musimy znaleźć bezpieczną drogę w dół."
			message.body = "Otwórz podświetloną ruinę Stacji Nurkowej i odbuduj poziom I. Stacja służy do wyboru nurka, przygotowania sprzętu i rozpoczynania wypraw pod wodę."
			message.callout_layout = "right_top"
		TutorialStateScript.Step.ASSIGN_COMMUNITY_WORKER:
			message.speaker_id = "anka"
			message.speaker_name = "Anka Ryl"
			message.speaker_role = "GŁOS TECHNICZNY"
			message.compact_title = "DZIEŃ 1  •  OBSADA"
			message.dialogue_title = "PRZYDZIEL PRACOWNIKA"
			message.narrative_title = "KTOŚ MUSI ZOSTAĆ"
			message.narrative_body = "Budynek bez człowieka jest tylko kolejnym pustym kadłubem. Jeśli to miejsce ma żyć, ktoś musi wziąć za nie odpowiedzialność."
			message.body = "Otwórz Dom Wspólnoty, przejdź do zakładki OBSADA i przydziel jednego zdolnego mieszkańca. Odbudowany budynek potrzebuje obsady, aby wykonywać swoją codzienną pracę."
			message.callout_layout = "right_top"
		TutorialStateScript.Step.SET_RATIONS:
			message.compact_title = "DZIEŃ 1  •  RACJE"
			message.dialogue_title = "USTAW RACJE NA DZISIAJ"
			message.narrative_title = "CENA JUTRA"
			message.narrative_body = "Zapasów jest mniej, niż mówią nasze puste żołądki. Każda dzisiejsza porcja jest decyzją o tym, w jakim stanie obudzimy się jutro."
			message.body = "Otwórz PLAN DNIA i wybierz politykę racji. Racje określają dzisiejsze zużycie jedzenia oraz wpływ niedożywienia na mieszkańców; wybór zostanie rozliczony po zakończeniu dnia."
			message.callout_layout = "right_top"
		TutorialStateScript.Step.END_FIRST_DAY:
			message.compact_title = "DZIEŃ 1  •  GOTOWE"
			message.dialogue_title = "ZAKOŃCZ DZIEŃ"
			message.narrative_title = "PIERWSZA NOC"
			message.narrative_body = "Zrobiliśmy tyle, ile mogliśmy. Teraz noc policzy nasze błędy, a rano pokaże, czy ten kawałek stali naprawdę może stać się Przystanią."
			message.body = "Kliknij ZAKOŃCZ DZIEŃ. Gra rozliczy zatwierdzony plan, pracę budynków, racje i skutki pogody, a następnie pokaże obowiązkowy raport przed kolejnym porankiem."
			message.callout_layout = "right_bottom"
		TutorialStateScript.Step.BUILD_WORKSHOP:
			message.speaker_id = "anka"
			message.speaker_name = "Anka Ryl"
			message.speaker_role = "GŁOS TECHNICZNY"
			message.compact_title = "DZIEŃ 2  •  WARSZTAT"
			message.dialogue_title = "ODBUDUJ WARSZTAT ODZYSKU I"
			message.narrative_title = "DRUGIE ŻYCIE ZŁOMU"
			message.narrative_body = "Morze oddaje nam głównie złom. To wystarczy — jeśli damy mu warsztat, narzędzia i czyjeś sprawne ręce."
			message.body = "Odbuduj podświetlony Warsztat Odzysku I. Warsztat naprawia Przystań i wytwarza wyposażenie potrzebne podczas wypraw, ale do działania wymaga pracownika."
			message.callout_layout = "right_top"
		TutorialStateScript.Step.ASSIGN_DIVER_FIRST:
			message.compact_title = "DZIEŃ 2  •  NUREK"
			message.dialogue_title = "WYBIERZ IGORA DO WYPRAWY"
			message.narrative_title = "CZŁOWIEK OD GŁĘBIN"
			message.narrative_body = "Igor zna wodę lepiej niż ktokolwiek z nas. Nie proszę go o odwagę — proszę, żeby wrócił i powiedział nam, dokąd prowadzi ten czarny kabel."
			message.body = "Otwórz Stację Nurkową i wybierz Igora Sowę w kolumnie Załoga wyprawy. Nurek nie musi obsadzać Stacji."
			message.callout_layout = "right_top"
		TutorialStateScript.Step.START_FIRST_DIVE:
			message.speaker_id = "igor"
			message.speaker_name = "Igor Sowa"
			message.speaker_role = "NUREK"
			message.compact_title = "DZIEŃ 2  •  PIERWSZE ZEJŚCIE"
			message.dialogue_title = "ROZPOCZNIJ PIERWSZĄ WYPRAWĘ"
			message.narrative_title = "POD POMOSTEM"
			message.narrative_body = "Kabel znika prosto w ciemności. Jeśli na jego końcu coś jeszcze działa, znajdę to. Jeśli nie — przynajmniej przyniosę nam coś, co pozwoli przeżyć kolejny dzień."
			message.body = "W Stacji Nurkowej przejdź do zakładki WYPRAWA, sprawdź wybranego nurka i kliknij NURKUJ. Plan dnia zostanie zablokowany, a dzień zakończy się dopiero po wyniku wyprawy."
			message.callout_layout = "right_top"
		TutorialStateScript.Step.DIVE_MOVEMENT:
			message.scene = "dive"
			message.speaker_id = "igor"
			message.speaker_name = "Igor Sowa"
			message.speaker_role = "NUREK"
			message.compact_title = "1/6  RUCH  •  %s  •  %s: SPRINT" % [_movement_prompt(1), sprint_prompt]
			message.dialogue_title = "NAUCZ SIĘ PORUSZAĆ"
			message.narrative_title = "POD POWIERZCHNIĄ"
			message.narrative_body = "Tu wszystko porusza się inaczej. Prąd łapie za przewody, wrak zasłania drogę, a ciemność odbiera poczucie kierunku. Spokojnie, Igor. Najpierw rytm oddechu."
			message.body = "Płyń klawiszami %s. Przytrzymaj %s, aby przyspieszyć, ale pamiętaj: sprint zużywa tlen szybciej. Bursztynowa strzałka wskazuje następny cel tutoriala." % [_movement_prompt(), sprint_prompt]
		TutorialStateScript.Step.DIVE_OXYGEN:
			message.scene = "dive"
			message.speaker_id = "igor"
			message.speaker_name = "Igor Sowa"
			message.speaker_role = "NUREK"
			message.compact_title = "2/6  TLEN  •  PILNUJ TURKUSOWEGO PASKA"
			message.dialogue_title = "TLEN OGRANICZA CZAS WYPRAWY"
			message.narrative_title = "KAŻDY ODDECH"
			message.narrative_body = "Manometr odmierza drogę powrotną, nie czas na dnie. Głębia zawsze namawia, żeby zostać jeszcze chwilę — i właśnie dlatego zabiera ludzi."
			message.body = "Turkusowy pasek pokazuje pozostały tlen. Ruch, sprint, ciężki plecak i walka z prądem zwiększają zużycie, dlatego zawsze zachowaj zapas na drogę do głównej liny."
		TutorialStateScript.Step.DIVE_OPEN_CONTAINER:
			message.scene = "dive"
			message.speaker_id = "igor"
			message.speaker_name = "Igor Sowa"
			message.speaker_role = "NUREK"
			message.compact_title = "3/6  SKRZYNIA  •  PRZYTRZYMAJ %s" % interact_prompt
			message.dialogue_title = "OTWÓRZ OZNACZONĄ SKRZYNIĘ"
			message.narrative_title = "ŚLADY PO INNYCH"
			message.narrative_body = "Ktoś zamknął tę skrzynię, zanim woda wdarła się tutaj na dobre. Nie wiem, czy planował wrócić. Dziś jej zawartość może wrócić ze mną."
			message.body = "Podążaj za strzałką, podpłyń do oznaczonej skrzyni i przytrzymaj %s. Otwarcie pojemnika nie zabiera wszystkiego automatycznie — za chwilę sam wybierzesz ładunek." % interact_prompt
		TutorialStateScript.Step.DIVE_INVENTORY:
			message.scene = "dive"
			message.speaker_id = "igor"
			message.speaker_name = "Igor Sowa"
			message.speaker_role = "NUREK"
			message.compact_title = "4/6  ŁUP  •  %s: PLECAK" % inventory_prompt
			message.dialogue_title = "ZBIERZ OBOWIĄZKOWE MINIMUM"
			message.narrative_title = "NIE UNIOSĘ WSZYSTKIEGO"
			message.narrative_body = "Na dnie wszystko wydaje się potrzebne. Dopiero ciężar plecaka przypomina, że ocalenie jednej rzeczy zawsze oznacza pozostawienie innej."
			message.body = "Zabierz łącznie co najmniej: 1 żywność, 1 deskę, 3 złomu oraz 2 tkaniny i gumy. Każdy rodzaj zajmuje jeden slot, wszystkie sztuki mają wagę, a %s otwiera plecak. Resztę możesz zostawić pod wodą." % inventory_prompt
		TutorialStateScript.Step.DIVE_BLOCKED_PASSAGE:
			message.scene = "dive"
			message.speaker_id = "igor"
			message.speaker_name = "Igor Sowa"
			message.speaker_role = "NUREK"
			message.compact_title = "5/6  ZABLOKOWANE PRZEJŚCIE"
			message.dialogue_title = "SPRAWDŹ ZABLOKOWANE PRZEJŚCIE"
			message.narrative_title = "DROGA PRZECIĘTA"
			message.narrative_body = "Kabel biegnie dalej, ale przejście zarosło siecią grubą jak cumy. Gołymi rękami jej nie pokonam. Muszę zapamiętać to miejsce i wrócić przygotowany."
			message.body = "Podążaj za kablem i strzałką do blokady. Sieci wymagają Noża ratowniczego, więc podczas tej wyprawy nie przejdziesz dalej; obejrzenie przeszkody wyznaczy następny cel przy głównej linie."
		TutorialStateScript.Step.DIVE_RETURN_TO_LINE:
			message.scene = "dive"
			message.speaker_id = "igor"
			message.speaker_name = "Igor Sowa"
			message.speaker_role = "NUREK"
			message.compact_title = "6/6  POWRÓT  •  PRZYTRZYMAJ %s PRZY LINIE" % interact_prompt
			message.dialogue_title = "WRÓĆ BEZPIECZNIE DO LINY"
			message.narrative_title = "NAJWAŻNIEJSZY ŁADUNEK"
			message.narrative_body = "Znalazłem drogę i coś, z czego Przystań zrobi użytek. Wystarczy. Najważniejszym ładunkiem z każdej wyprawy nadal jest człowiek, który wraca na powierzchnię."
			message.body = "Wróć do głównej liny wejściowej i przytrzymaj %s. Tylko bezpieczny powrót przenosi łup do Przystani i kończy wyprawę; samo dopłynięcie do krawędzi mapy nie wystarczy." % interact_prompt
		TutorialStateScript.Step.STAFF_WORKSHOP:
			message.speaker_id = "anka"
			message.speaker_name = "Anka Ryl"
			message.speaker_role = "GŁOS TECHNICZNY"
			message.compact_title = "DZIEŃ 3  •  OBSADA WARSZTATU"
			message.dialogue_title = "PRZYDZIEL PRACOWNIKA DO WARSZTATU"
			message.narrative_title = "NARZĘDZIE, NIE CUD"
			message.narrative_body = "Wiemy już, co zatrzymało Igora. Sieć nie ustąpi przed odwagą ani siłą — potrzebujemy narzędzia i kogoś, kto potrafi je wykonać."
			message.body = "Otwórz podświetlony Warsztat, przejdź do zakładki OBSADA i przydziel jednego zdolnego pracownika. Bez obsady nie można wykonać Noża ratowniczego potrzebnego przy sieciach."
			message.callout_layout = "right_top"
		TutorialStateScript.Step.CRAFT_RESCUE_KNIFE:
			message.speaker_id = "anka"
			message.speaker_name = "Anka Ryl"
			message.speaker_role = "GŁOS TECHNICZNY"
			message.compact_title = "DZIEŃ 3  •  NÓŻ RATOWNICZY"
			message.dialogue_title = "WYKONAJ NÓŻ RATOWNICZY"
			message.narrative_title = "STAL PRZECIW SIECIOM"
			message.narrative_body = "Nie będzie piękny, ale krawędź wytrzyma. Ten nóż ma przeciąć drogę do kabla — i dać nurkowi drugą szansę, jeśli coś złapie go pod wodą."
			message.body = "W otwartym Warsztacie przejdź do DZIAŁANIA i wybierz „Wykonaj natychmiast: Nóż ratowniczy”. Koszt to 3 złomu oraz 2 tkaniny i gumy; wykonanie trwale odblokuje narzędzie do przecinania sieci."
			message.callout_layout = "right_top"
		TutorialStateScript.Step.START_FINAL_DIVE:
			message.speaker_id = "igor"
			message.speaker_name = "Igor Sowa"
			message.speaker_role = "NUREK"
			message.compact_title = "DZIEŃ 3  •  ZAŁĄCZENIE"
			message.dialogue_title = "WRÓĆ POD WODĘ Z NOŻEM"
			message.narrative_title = "ZA CZARNYM KABLEM"
			message.narrative_body = "Tym razem sieć mnie nie zatrzyma. Za nią musi być powód, dla którego Pomost 7 wciąż trzymał ten kabel podłączony do martwego świata."
			message.body = "Nóż jest już stałym wyposażeniem. Otwórz Stację Nurkową, przejdź do WYPRAWY, wybierz Igora i kliknij NURKUJ. Tym razem celem jest Węzeł J-7 za wcześniejszą blokadą."
			message.callout_layout = "right_top"
		TutorialStateScript.Step.ACTIVATE_JUNCTION_J7:
			message.scene = "dive"
			message.speaker_id = "igor"
			message.speaker_name = "Igor Sowa"
			message.speaker_role = "NUREK"
			message.compact_title = "DZIEŃ 3  •  CEL: WĘZEŁ J-7"
			message.dialogue_title = "NAJPIERW URUCHOM WĘZEŁ J-7"
			message.narrative_title = "WĘZEŁ J-7"
			message.narrative_body = "Czarny kabel kończy się tutaj. J-7 nie zgasł przez przypadek — ktoś odciął zasilanie i zostawił cały układ w uśpieniu. Jeśli go obudzę, Przystań pozna prawdę."
			message.body = "Powrót jest zablokowany przy głównej linie do czasu wykonania celu tutoriala. Użyj Noża do przecięcia sieci, podążaj za strzałką i kablem, a przy Węźle J-7 przytrzymaj %s, aby go uruchomić." % interact_prompt
		TutorialStateScript.Step.FINAL_RETURN_TO_LINE:
			message.scene = "dive"
			message.speaker_id = "igor"
			message.speaker_name = "Igor Sowa"
			message.speaker_role = "NUREK"
			message.compact_title = "DZIEŃ 3  •  BEZPIECZNY POWRÓT"
			message.dialogue_title = "J-7 DZIAŁA — WRÓĆ DO LINY"
			message.narrative_title = "LINIA OŻYŁA"
			message.narrative_body = "Słyszę prąd w przewodzie. J-7 wysłał sygnał dalej, daleko poza tę zatokę. Cokolwiek odpowiedziało po drugiej stronie, dowiemy się tego na powierzchni."
			message.body = "Strzałka wskazuje już główną linę. Wróć do niej i przytrzymaj %s; dopiero bezpieczny powrót zapisze aktywację J-7, zakończy dzień i zamknie tutorial." % interact_prompt
		_:
			return {}
	return message


static func tutorial_conversation(step: int) -> Dictionary:
	match step:
		TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE:
			return _conversation(
				"tutorial_dialogue_day_1",
				"PIERWSZY DACH",
				[
					_stage_direction("Deszcz przeciska się przez wyrwy w poszyciu. Troje ocalałych stoi nad planem prowizorycznej Przystani."),
					_line("mira", "Mira Boruta", "GŁOS PRZYSTANI", "left", "Najpierw suchy dach. Ludzie potrzebują miejsca, w którym znów usiądą razem — inaczej pozostaniemy tylko trojgiem na wraku."),
					_line("anka", "Anka Ryl", "GŁOS TECHNICZNY", "right", "Dach kupi nam noc. Jeszcze dzisiaj postawmy też Stację Nurkową. Pod powierzchnią zostały zapasy i części, których nie odtworzę z niczego."),
					_line("mira", "Mira Boruta", "GŁOS PRZYSTANI", "left", "Najpierw Dom Wspólnoty. Potem droga w dół. Zróbmy z tej platformy miejsce, do którego warto wracać."),
				],
				"DZIEŃ 1  •  PRZYSTAŃ  •  PIERWSZY PORANEK"
			)
		TutorialStateScript.Step.BUILD_WORKSHOP:
			return _conversation(
				"tutorial_dialogue_day_2",
				"CZARNY KABEL",
				[
					_stage_direction("W Domu Wspólnoty znaleziono martwą tablicę elektryczną. Gruby czarny kabel znika przez pokład pod wodą."),
					_line("anka", "Anka Ryl", "GŁOS TECHNICZNY", "left", "Tablica jest martwa. Oznaczenie mówi: „Pomost 7 — magistrala serwisowa”. Punkt załączenia musi być pod wodą."),
					_line("igor", "Igor Sowa", "NUREK", "right", "Stacja jest gotowa. Przydziel mnie do niej, a zejdę za przewodem. Najpierw sprawdzę drogę; bohaterów na dnie nie potrzebujemy."),
					_line("anka", "Anka Ryl", "GŁOS TECHNICZNY", "left", "Najpierw odbudujemy Warsztat. Jeśli morze postawi ci przeszkodę, chcę móc dać ci właściwe narzędzie, zanim zejdziesz drugi raz."),
					_line("igor", "Igor Sowa", "NUREK", "right", "Umowa stoi. Wrócę z odpowiedzią albo z czymś, co pomoże nam jej poszukać."),
				],
				"DZIEŃ 2  •  PRZYSTAŃ  •  STÓŁ WARSZTATOWY"
			)
		TutorialStateScript.Step.STAFF_WORKSHOP:
			return _conversation(
				"tutorial_dialogue_day_3",
				"DROGA PRZECIĘTA",
				[
					_stage_direction("Igor zdejmuje maskę. Z klamry przy pasie zwisa kawałek grubej, czarnej sieci."),
					_line("igor", "Igor Sowa", "NUREK", "left", "Kabel prowadzi dalej, ale przejście jest oplecione siecią grubą jak cumy. Przywiozłem próbkę. Reszty bez ostrza nie ruszę."),
					_line("anka", "Anka Ryl", "GŁOS TECHNICZNY", "right", "Nie będziesz próbował rękami. Obsadzimy Warsztat i zrobię Nóż ratowniczy — prosty, mocny, bez szarpania przewodów."),
					_line("igor", "Igor Sowa", "NUREK", "left", "Dobrze. Kiedy będzie gotowy, wrócę do blokady."),
					_line("anka", "Anka Ryl", "GŁOS TECHNICZNY", "right", "I wrócisz na powierzchnię. Kabel może poczekać; ty nie jesteś częścią zamienną."),
				],
				"DZIEŃ 3  •  PRZYSTAŃ  •  PO POWROCIE"
			)
	return {}


static func story_conversations(state) -> Array[Dictionary]:
	var conversations: Array[Dictionary] = []
	if state == null or state.story_flags == null:
		return conversations
	var story = state.story_flags
	if bool(story.final_chronicle_continued) or not str(story.final_outcome_id).is_empty():
		return conversations
	conversations.append_array(_current_day_milestone_conversations(state))
	if bool(story.energy_choice_pending) or bool(story.black_front_arrived):
		return conversations
	if bool(story.junction_j7_active) and not bool(story.archive_map_transmitted):
		conversations.append(_conversation(
			"story_j7_first_contact",
			"GŁOS Z PÓŁNOCY",
			[
				_stage_direction("Główny bezpiecznik opada z oporem. Przekaźnik uderza w obudowę; zapalają się lampy i moduł radiowy. Na tablicy miga: „J-7 — odłączenie serwisowe”. W głośniku budzi się szum obcego kanału — pierwszy od pięciu lat.", NarrativeAudioCatalogScript.CUE_LINE_ENGAGE),
				_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Pomost Siedem? Potwierdźcie. Kto załączył linię?", NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN),
				_role_line(ROLE_HARBOR_VOICE, "left", "Tu Przystań. Węzeł był odłączony. Właśnie go uruchomiliśmy.", "PRZYSTAŃ: połączenie J-7 zostało przywrócone."),
				_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Klara Wysocka, Platforma Północna. W tej samej chwili nasze napięcie spadło, a pompy przeszły na zasilanie awaryjne. Ciągniemy z jednego banku.", NarrativeAudioCatalogScript.CUE_PUMPS_EMERGENCY),
				_role_line(ROLE_HARBOR_VOICE, "left", "Jeśli się odłączymy, znów zostaniemy bez światła i łączności. Jeśli zostaniemy — zabieramy wam czas.", "J-7 zasila światło i łączność Przystani; wspólny bank zasila pompy Północnej."),
				_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Front za %d dni. Pomost przetrwa tylko przy 100%% integralności — nie 99%%. Wysyłam współrzędne Archiwum. Tam jest mapa sieci." % int(story.black_front_days_remaining)),
			],
			"PRZYSTAŃ  •  DOM WSPÓLNOTY  •  PO POWROCIE Z J-7"
		))
		return conversations
	var message := _story_message(state, false)
	if message.is_empty():
		return conversations
	conversations.append(message)
	return conversations


static func ending_prelude_conversations(state) -> Array[Dictionary]:
	if state == null or state.story_flags == null or not bool(state.story_flags.energy_choice_pending):
		return []
	return _current_day_milestone_conversations(state)


static func story_message(state) -> Dictionary:
	return _story_message(state, true)


static func _story_message(state, include_current_day_milestones: bool) -> Dictionary:
	if state == null or state.story_flags == null:
		return {}
	var story = state.story_flags
	var resolved_day := maxi(int(state.day) - 1, 0)
	if bool(story.final_chronicle_continued) or not str(story.final_outcome_id).is_empty() or bool(story.energy_choice_pending) or bool(story.black_front_arrived):
		return {}
	if bool(story.crisis_active):
		return _conversation(
			"story_crisis_%d" % int(story.crisis_started_day),
			"KRYZYS W PRZYSTANI",
			[
				_stage_direction("Na tablicy planu ktoś przekreślił słowo „jutro”. W Domu Wspólnoty rozmowy urywają się, zanim ktokolwiek proponuje następny krok."),
				_role_line(ROLE_HARBOR_VOICE, "left", "Nie chodzi już o jeden zły dzień. Ludzie nie wierzą, że wspólny wysiłek ma sens.", "RAPORT WSPÓLNOTY: Nadzieja spadła do poziomu kryzysowego."),
				_stage_direction("Kawałek kredy pozostaje na środku stołu. Nikt nie dopisuje kolejnego punktu planu."),
				_role_line(ROLE_HARBOR_VOICE, "left", "Otworzymy drzwi Domu Wspólnoty. Najpierw wysłuchamy gniewu, potem pokażemy plan. Nikt nie odzyska wiary od samego rozkazu.", "Dom Wspólnoty pozostaje otwarty; plan odbudowy Nadziei oczekuje na obsadę."),
			],
			"PRZYSTAŃ  •  DOM WSPÓLNOTY  •  PORANEK"
		)
	if bool(story.black_front_active) and int(story.black_front_days_remaining) == 1:
		return _conversation(
			"story_black_front_last_day",
			"OSTATNI PEŁNY DZIEŃ",
			[
				_world_event("Morze ucichło. Barometr nadal spada, a na horyzoncie czernieje nieruchoma ściana chmur.", NarrativeAudioCatalogScript.CUE_FRONT_PRESSURE),
				_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Pomost Siedem, potwierdźcie. Pompy pracują. Przygotowania zakończone.", NarrativeAudioCatalogScript.CUE_PUMPS_STABLE),
				_role_line(ROLE_HARBOR_VOICE, "left", "Tu Przystań. Odbieramy. Kończymy obchód; na poprawki przed Frontem nie będzie już jutra.", "OSTATNI DZIEŃ: brak kolejnej doby przygotowań przed Frontem."),
				_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Jeśli kanał zgaśnie, wołajcie dalej. My zrobimy to samo."),
				_stage_direction("Transmisję połyka szum. Nad wodą przetacza się pierwszy grzmot.", NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_FADE),
			],
			"PRZYSTAŃ  •  OSTATNI PORANEK PRZED FRONTEM"
		)
	if bool(story.common_line_splitter_installed) and (include_current_day_milestones or int(story.common_line_splitter_installed_day) != resolved_day):
		return _splitter_installed_conversation()
	if bool(story.common_line_splitter_ready):
		return _conversation(
			"story_splitter_ready",
			"ROZDZIELACZ JEST GOTOWY",
			[
				_stage_direction("Warsztat cichnie. Na stole leży ciężki rozdzielacz, jeszcze ciepły od spawania."),
				_role_line(ROLE_TECHNICAL_VOICE, "right", "Styki trzymają, izolacja jest szczelna. Nie da więcej prądu; tylko podzieli przeciążenie.", "RAPORT TECHNICZNY: Rozdzielacz ukończony; styki i izolacja przeszły próbę."),
				_stage_direction("Rozdzielacz zostaje zablokowany w stelażu transportowym. Na uchwytach wciąż stygną ślady spawania.", NarrativeAudioCatalogScript.CUE_SPLITTER_BENCH_LATCH),
			],
			"PRZYSTAŃ  •  WARSZTAT ODZYSKU"
		)
	if bool(story.c4_switchboard_active) and (include_current_day_milestones or int(story.c4_switchboard_activated_day) != resolved_day):
		return _c4_active_conversation()
	if bool(story.r3_generator_active) and (include_current_day_milestones or int(story.r3_generator_activated_day) != resolved_day):
		return _r3_active_conversation()
	if bool(story.r3_regulator_ready):
		return _conversation(
			"story_r3_regulator_ready",
			"REGULATOR R-3 JEST GOTOWY",
			[
				_stage_direction("Przewody pomiarowe zostają odłączone. Nowy regulator odpowiada równym zielonym pulsem."),
				_role_line(ROLE_TECHNICAL_VOICE, "right", "Parametry zgadzają się z zapisem R-3. Brakująca część jest gotowa.", "RAPORT TECHNICZNY: Regulator R-3 ukończony i zgodny z odczytem generatora."),
				_stage_direction("Regulator zostaje zamknięty w uszczelnionym stelażu. Zielony puls znika pod pokrywą."),
			],
			"PRZYSTAŃ  •  WARSZTAT ODZYSKU"
		)
	if bool(story.r3_diagnosed):
		return _conversation(
			"story_r3_diagnosed",
			"DIAGNOSTYKA R-3 ZAKOŃCZONA",
			[
				_world_event("Pakiet diagnostyczny z R-3 dociera do Warsztatu. Na schemacie czerwieni się tylko jeden moduł."),
				_role_line(ROLE_TECHNICAL_VOICE, "right", "Generator odpowiada. Spalił się regulator; reszta układu przetrwała.", "RAPORT DIAGNOSTYCZNY R-3: uszkodzony regulator; pozostałe układy odpowiadają."),
				_stage_direction("Odczyty zostają przypięte nad stołem Warsztatu. Na czystej kartce pojawia się obrys brakującego modułu."),
			],
			"PRZYSTAŃ  •  WARSZTAT ODZYSKU"
		)
	if bool(story.archive_map_transmitted):
		return _conversation(
			"story_archive_transmitted",
			"DLACZEGO NAS ODŁĄCZONO",
			[
				_world_event("Transmisja kończy się. Na mapie zapalają się Pomost 7, Platforma Północna, Generator R-3 i Rozdzielnia C-4 — jedna sieć, jeden wspólny bank."),
				_stage_direction("Na ekran wypływa ostatni wpis operatora: „POMOST 7 — OBSADA: 0. PRIORYTET BANKU: POMPY PÓŁNOCNEJ. ODŁĄCZYĆ”.", NarrativeAudioCatalogScript.CUE_ARCHIVE_RELAY_READ),
				_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "To nasi operatorzy odłączyli Pomost Siedem. Wtedy był pusty, a przełączenie banku utrzymało nasze pompy."),
				_role_line(ROLE_HARBOR_VOICE, "left", "Nie odcięli osady. Odcięli pusty pomost. A teraz jesteśmy.", "STAN AKTUALNY: POMOST 7 — OBSADA OBECNA."),
				_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Właśnie dlatego mamy problem."),
			],
			"PRZYSTAŃ  •  STÓŁ Z MAPĄ WSPÓLNEJ LINII"
		)
	return {}


static func _current_day_milestone_conversations(state) -> Array[Dictionary]:
	var conversations: Array[Dictionary] = []
	if state == null or state.story_flags == null:
		return conversations
	var story = state.story_flags
	var resolved_day := maxi(int(state.day) - 1, 0)
	if bool(story.r3_generator_active) and int(story.r3_generator_activated_day) == resolved_day:
		conversations.append(_r3_active_conversation())
	if bool(story.c4_switchboard_active) and int(story.c4_switchboard_activated_day) == resolved_day:
		conversations.append(_c4_active_conversation())
	if bool(story.common_line_splitter_installed) and int(story.common_line_splitter_installed_day) == resolved_day:
		conversations.append(_splitter_installed_conversation())
	return conversations


static func _splitter_installed_conversation() -> Dictionary:
	return _conversation(
		"story_splitter_installed",
		"OBIE KONTROLKI",
		[
			_stage_direction("Nurek stawia na stole pusty stelaż transportowy. Rozdzielacz został przy C-4, dokładnie tam, gdzie miał trafić."),
			_world_event("Na tablicy Wspólnej Linii kontrolki PRZYSTAŃ i PÓŁNOCNA pozostają zapalone jednocześnie.", NarrativeAudioCatalogScript.CUE_C4_DUAL_LINE_TEST),
			_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Widzę oba odczyty. Pierwszy raz żadna platforma nie znika z tablicy, kiedy druga bierze prąd."),
			_role_line(ROLE_HARBOR_VOICE, "left", "To jeszcze nie Front.", "TEST ROZDZIELACZA: stabilny poza obciążeniem Czarnego Frontu."),
			_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Nie. Ale pierwszy raz nie musimy zaczynać od wyboru, kogo zgasić."),
		],
		"PRZYSTAŃ  •  PO POWROCIE Z C-4"
	)


static func _c4_active_conversation() -> Dictionary:
	return _conversation(
		"story_c4_active",
		"JEDNA LINIA PRIORYTETOWA",
		[
			_world_event("Na panelu C-4 zapalają się oznaczenia: PRZYSTAŃ, PÓŁNOCNA, OBCIĄŻENIE. Pomiędzy nimi pulsuje alarm: „JEDNA LINIA PRIORYTETOWA”.", NarrativeAudioCatalogScript.CUE_C4_SINGLE_LINE),
			_role_line(ROLE_TECHNICAL_VOICE, "left", "Sterowanie działa. To nie usterka — zabezpieczenia od początku miały wybrać jedną linię.", "RAPORT C-4: podczas przeciążenia zabezpieczenia dopuszczają jedną linię priorytetową."),
			_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Jeśli zabraknie wam czasu, skierujcie zasilanie do Przystani."),
			_role_line(ROLE_TECHNICAL_VOICE, "left", "Nie prosiliśmy cię, żebyś wybierała za nas.", "PRZYSTAŃ: wybór pojedynczej linii nie został zatwierdzony."),
			_stage_direction("Obok odczytu z C-4 pojawia się szkic prowizorycznego rozdzielacza obciążenia."),
			_role_line(ROLE_TECHNICAL_VOICE, "left", "Nie da więcej prądu. Może rozłożyć przeciążenie na obie linie. Zapłacimy materiałami, pracą Warsztatu i jeszcze jednym zejściem.", "ANALIZA TECHNICZNA: prowizoryczny rozdzielacz może rozłożyć przeciążenie kosztem materiałów, pracy i kolejnej wyprawy."),
		],
		"PRZYSTAŃ  •  PO POWROCIE Z CZARNEGO SERCA"
	)


static func _r3_active_conversation() -> Dictionary:
	return _conversation(
		"story_r3_active",
		"MASZYNY, NIE ALARM",
		[
			_world_event("R-3 szarpie dwa razy, potem przechodzi w równy, niski rytm. Światła Przystani przestają przygasać.", NarrativeAudioCatalogScript.CUE_R3_STARTUP),
			_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Przystań, zostańcie chwilę na linii. Chcę, żebyście to usłyszeli.", NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN),
			_stage_direction("Przez radio przebija się miarowa praca pomp Północnej. Po raz pierwszy nie zagłusza jej alarm.", NarrativeAudioCatalogScript.CUE_PUMPS_STABLE),
			_role_line(ROLE_HARBOR_VOICE, "left", "Pierwszy raz słyszymy u was maszyny, nie alarm.", "Odbiornik Przystani rejestruje równy rytm pomp bez sygnału alarmowego."),
			_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Generator kupił nam czas. C-4 nadal utrzyma podczas Frontu tylko jedną linię. Tym razem po obu stronach są ludzie."),
		],
		"PRZYSTAŃ  •  PO URUCHOMIENIU R-3"
	)


static func ending_conversation(state) -> Dictionary:
	if state == null or state.story_flags == null:
		return {}
	match str(state.story_flags.final_outcome_id):
		"quiet_after_storm":
			return _conversation(
				"ending_quiet_after_storm",
				"CISZA PO BURZY",
				[
					_stage_direction("O świcie Pomost 7 nadal unosi się na wodzie. Z odbiornika kapie woda, a pierwsze lampy wracają do życia."),
					_role_line(ROLE_HARBOR_VOICE, "left", "Północna, tu Przystań. Potwierdźcie.", "Wywołanie Platformy Północnej zostaje nadane.", NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN),
					_world_event("Radio odpowiada wyłącznie szumem. Nie słychać nawet rytmu pomp; częstotliwość Platformy Północnej pozostaje martwa."),
					_stage_direction("Czyjaś dłoń zatrzymuje się na wyłączniku radia."),
					_role_line(ROLE_HARBOR_VOICE, "left", "Nie wyłączaj. Jeszcze raz.", "Wywołanie Północnej zostaje powtórzone. Odbiornik pozostaje włączony.", NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN),
				],
			"POMOST 7  •  ŚWIT PO CZARNYM FRONCIE"
			)
		"debt_repaid":
			return _conversation(
				"ending_debt_repaid",
				"DŁUG SPŁACONY",
				[
					_world_event("Przez całą noc Przystań pozostaje bez głównego zasilania. Mieszkańcy ręcznie zabezpieczają konstrukcję, aż wiatr zaczyna słabnąć."),
					_stage_direction("O świcie podstawowy moduł radiowy odzyskuje moc. Zielona lampka rozcina ciemność Domu Wspólnoty.", NarrativeAudioCatalogScript.CUE_LINE_ENGAGE),
					_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Przystań, potwierdźcie.", NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN),
					_role_line(ROLE_HARBOR_VOICE, "left", "Jesteśmy.", "PRZYSTAŃ: potwierdzona obecność."),
					_stage_direction("W tle transmisji pompy Północnej przechodzą w równy, spokojny rytm.", NarrativeAudioCatalogScript.CUE_PUMPS_STABLE),
					_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "U nas też."),
				],
			"POMOST 7  •  ŚWIT PO NOCY BEZ ZASILANIA"
			)
		"last_bridge":
			return _conversation(
				"ending_last_bridge",
				"OSTATNI POMOST",
				[
					_world_event("Przez całą noc obie osady wymieniają odczyty. Gdy jedna ogranicza pobór, druga odzyskuje dość mocy, by utrzymać pompy i światła awaryjne.", NarrativeAudioCatalogScript.CUE_C4_DUAL_LINE_STORM),
					_line("klara", "Klara Wysocka", "PLATFORMA PÓŁNOCNA", "right", "Północna do Przystani. Pompy trzymają.", NarrativeAudioCatalogScript.CUE_PUMPS_STABLE),
					_role_line(ROLE_HARBOR_VOICE, "left", "Przystań do Północnej. Pokład trzyma.", "PRZYSTAŃ: integralność utrzymana."),
					_world_event("Przez szum przebija się trzeci, słaby sygnał: „…Pomost Siedem… czy ktoś…”.", NarrativeAudioCatalogScript.CUE_RADIO_DISTANT_CHANNEL),
					_role_line(ROLE_HARBOR_VOICE, "left", "Tu Przystań, Pomost Siedem. Słyszymy. Mów dalej.", "PRZYSTAŃ: sygnał odebrany. Kanał pozostaje otwarty."),
					_stage_direction("Nikt nie wyłącza radia. Na dalekiej wodzie odpowiada pojedyncze światło."),
				],
			"WSPÓLNA LINIA  •  ŚWIT PO CZARNYM FRONCIE"
			)
	return {}


static func _conversation(key: String, title: String, lines: Array, scene_context: String) -> Dictionary:
	return {
		"key": key,
		"kind": "conversation",
		"scene": "base",
		"scene_context": scene_context,
		"title": title,
		"lines": lines,
	}


static func _line(speaker_id: String, speaker_name: String, speaker_role: String, side: String, body: String, cue_id: String = "") -> Dictionary:
	return _with_cue({
		"line_type": "dialogue",
		"speaker_id": speaker_id,
		"speaker_name": speaker_name,
		"speaker_role": speaker_role,
		"external_speaker": speaker_id == "klara",
		"side": side,
		"body": body,
	}, cue_id)


static func _role_line(role_id: String, side: String, body: String, fallback_body: String = "", cue_id: String = "") -> Dictionary:
	var line := {
		"line_type": "dialogue",
		"speaker_role_id": role_id,
		"side": side,
		"body": body,
	}
	if not fallback_body.is_empty():
		line["fallback_body"] = fallback_body
	return _with_cue(line, cue_id)


static func _stage_direction(body: String, cue_id: String = "") -> Dictionary:
	return _with_cue({
		"line_type": "stage_direction",
		"body": body,
	}, cue_id)


static func _world_event(body: String, cue_id: String = "") -> Dictionary:
	return _with_cue({
		"line_type": "world_event",
		"body": body,
	}, cue_id)


static func _with_cue(line: Dictionary, cue_id: String) -> Dictionary:
	var normalized_cue_id := cue_id.strip_edges()
	if not normalized_cue_id.is_empty():
		line["cue_id"] = normalized_cue_id
	return line


static func _movement_prompt(max_bindings: int = 2) -> String:
	return "%s / %s / %s / %s" % [
		InputPromptScript.action_text(&"dive_up", max_bindings),
		InputPromptScript.action_text(&"dive_left", max_bindings),
		InputPromptScript.action_text(&"dive_down", max_bindings),
		InputPromptScript.action_text(&"dive_right", max_bindings),
	]
