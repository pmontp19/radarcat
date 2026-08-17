# Ajust de `RadarCompositor.invertedForDarkAppearance`

Historial de mesures i raonament darrere de la corba tonal que dona l'aparença
fosca a la capa de base. El codi (`RadarCompositor.swift`) només en conserva
la conclusió operativa; aquest document és la referència per si algú ha de
tornar a ajustar-la.

## Per què no n'hi ha prou amb invertir

Una inversió pura deixa el mar MÉS CLAR que la terra, al revés del que un mode
fosc necessita: el mar és, als tiles de Meteocat, un gris pla força fosc
(~19% de luminància) i la terra un gris més clar amb ombrejat de relleu molt
variable (~35-45%). En invertir, el mar (~81%) queda per sobre de la terra
(~59%), i com que el mar ocupa una franja grossa del retall (tota la banda
sud-est), és un bloc clar gros dominant en un popover que hauria de ser fosc.

Mesurat de veritat (mitjana de mostres, escala 0...1, sobre el frame real
abans de corregir): mar 0.807, terra 0.594.

## Per què `CIToneCurve` i no una màscara mar/terra

`CIToneCurve` és una única funció monòtona aplicada píxel a píxel: no sap
distingir mar de terra, només veu un valor de luminància d'entrada i en treu
un de sortida. Amb això n'hi ha prou per baixar el mar cap a la banda fosca i
pujar la terra cap a una banda mitjana-fosca on el relleu torni a ser visible,
sense enfonsar les fronteres/etiquetes (que inverteixen a gairebé blanc pur,
~95-100%, i han de seguir-se llegint), però NO pot capgirar quin dels dos
queda més clar: com que el mar invertit (~0.81) ja entra a la corba per sobre
de la terra invertida (~0.55-0.65) per a qualsevol relleu real, i una funció
monòtona preserva l'ordre dels valors d'entrada, el mar surt sempre una mica
per sobre de la terra també a la sortida.

Apple Maps en fosc pot capgirar aquesta relació (terra fosca, mar més clar)
perquè parteix de capes semàntiques separades amb colors assignats a mà; aquí
no hi ha cap capa semàntica que distingeixi mar de terra, només un PNG ja
renderitzat pel giny de Meteocat. Fer-ho de debò exigiria una màscara mar/
terra que aquest pipeline no té. El que sí fa la corba és treure-li
protagonisme al mar (comprimint-lo) alhora que aixeca la terra, no invertir-ne
la relació. Compromís conscient, no un descuit.

## Mesures de l'ajust actual

Mesurat amb un arnès aïllat (`swiftc` fora del paquet, aplicant la mateixa
cadena de filtres als tiles reals de base, no a ull):

- Abans d'aquest ajust: mar 0.373 / terra 0.143 (el relleu quedava gairebé
  negre, només es llegien les fronteres blanques).
- Després: mar ~0.356 (ja anava bé, no calia baixar-lo més) / terra ~0.21
  (dins la franja 0,19-0,22 buscada, el relleu ja es distingeix).

El mar segueix sent més clar que la terra, com calia esperar del raonament de
dalt, però ara per un marge molt més petit i sense enfonsar la terra a negre.

Els 5 punts de la corba (`inputPoint0`...`inputPoint4`) estan triats a partir
dels percentils reals del frame invertit (mar ~0.81, terra ~0.59, fronteres/
etiquetes ~0.95-1.0): el mar baixa a ~0.36 i les fronteres/etiquetes es
mantenen prou clares (~0.88) per seguir-se llegint. `inputPoint2` és el canvi
clau d'aquest ajust: abans (0.65, 0.16) queia lluny del valor real de la
terra (~0.59) i la deixava gairebé negra (~0.14 mesurat); ara està clavat
pràcticament sobre el valor real de la terra i apunta al mig de la franja
0,19-0,22 buscada. `inputPoint1` (abans 0.49/0.08) baixa a (0.35, 0.05) perquè
les ombres de relleu més fosques (per sota de la terra "plana") segueixin
fent una transició suau cap a `inputPoint0`, en lloc d'un salt brusc ara que
`inputPoint2` s'ha mogut.

## Si cal tornar a ajustar-la

Repetir el mateix arnès aïllat (renderitzar la base real, aplicar la cadena
de filtres, mesurar percentils de mar/terra/fronteres) abans de tocar els
punts de la corba a cegues. No fiar-se de com es veu a ull: els valors
mesurats aquí ja van revelar que un primer intent (abans d'aquest ajust)
enfonsava la terra molt més del que semblava a primera vista.
