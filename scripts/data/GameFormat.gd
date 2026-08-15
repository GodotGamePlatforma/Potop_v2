class_name GameFormat
extends RefCounted

## Jedyny numer formatu trwałej kampanii.
##
## Obejmuje cały graf `GameState`, w tym migawkę mapy, ekwipunek, kolejki i
## wszystkie zagnieżdżone Resource. Zmiana znaczenia któregokolwiek z tych
## danych wymaga podbicia tej jednej wartości i odcięcia poprzednich kampanii.
const CAMPAIGN_FORMAT_REVISION := 2
