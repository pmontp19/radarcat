# Historial de `RainDetector.maxSeverityOverFrame`

`maxSeverityOverFrame` alimenta la línia d'estat sense ubicació ("Pluja activa
a Catalunya" / "Sense pluja a Catalunya"). El codi (`RainDetector.swift`)
conserva només l'algorisme actual; aquest document explica per què ha passat
per tres versions.

## v1: recompte acumulatiu de tot el frame

Es sumava el recompte de mostres "aquest nivell o pitjor" de TOT el frame
(acumulatiu de `.hail` cap avall), sense mirar si eren contigües.

Massa permissiu a la mida real d'un frame: una dotzena de taques febles i
disperses arreu de Catalunya (cap d'elles, per separat, prou gran per dir
res) sumaven prou mostres com per arribar al llindar total, i la línia
d'estat deia "Pluja feble a Catalunya" amb un cel pràcticament net.

## v2: només el clúster més gran

Correcció: només comptava el component connex (8-connectat) més gran de cada
nivell.

Massa estricta en sentit contrari: dues o tres cèl·lules de pluja REALS i
separades (cadascuna per sota del llindar tota sola) deixaven de comptar del
tot, quan plegades sí representen un fenomen prou gran per dir-ho.

## v3 (actual): suma de clústers qualificats

Es busca el component connex de cada nivell (`sumOfQualifyingClusters`) i es
descarten els clústers massa petits per ser un eco de veritat
(`minClusterSize`, soroll puntual), però els que sobreviuen aquest filtre se
sumen entre ells, no es queda només el més gran. Resol els dos problemes de
cop:

- Un artefacte de vora o un únic píxel de compressió classificat per atzar
  com `.hail` no compta: un clúster per sota de `minClusterSize` es descarta
  abans de sumar-se, igual si n'hi ha 1 com si n'hi ha 50 d'escampats arreu
  del frame.
- Diverses cèl·lules de pluja reals i separades SÍ se sumen entre elles: cap
  necessita arribar sola al llindar, com passava a v2.

Efecte de retruc: la insígnia exclosa (`RadarCompositor.attributionRectNormalized`)
pot, en teoria, partir un eco real en dos trossos si l'eco travessa just
aquella cantonada. Com que ara se sumen tots els clústers que passin
`minClusterSize` (no només el més gran), els dos trossos partits encara
compten junts sempre que cap dels dos quedi per sota d'aquell mínim.

## Límit acceptat, no resolt

Si la partició per la insígnia deixa un (o tots dos) trossos per SOTA de
`minClusterSize`, aquella part es perd. Donat que la insígnia és una
cantonada fixa i petita sobre mar obert (vegeu
`RadarCompositor.attributionRectNormalized`; la llegenda també viu en aquesta
cantonada perquè és sistemàticament mar obert), la probabilitat real que un
eco s'hi centri i es parteixi exactament així és baixa. Una màscara de
connectivitat conscient de la insígnia seria una solució completa, però no
val la pena la complexitat per a aquest racó concret.
