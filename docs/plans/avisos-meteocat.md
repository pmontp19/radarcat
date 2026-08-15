# Pla: avisos SMP de Meteocat a RadarCat (banner + toggle)

> Pla d'implementació per a més endavant. Sorgeix d'una exploració (14/08/2026): es va
> confirmar en viu un avís de calor vigent, es va provar que `~/Developer/ha-avisoscat` ja
> extreu els avisos de Meteocat de forma estructurada i estable, i es va revisar la UX amb
> l'usuari via un artifact a Lavish. No implementat encara.

## Context

RadarCat mostra només el radar de precipitació. Explorant si val la pena creuar-ho amb els
avisos oficials de perill del Meteocat (SMP: calor, vent, pluja, neu...), es va confirmar que
`ha-avisoscat` ja extreu aquestes dades de forma estructurada i estable, i es va revisar la UX
amb l'usuari. Decisió presa i confirmada: **banner condicional al popover (B) + toggle opt-in
a Ajustos (D)**, descartant icona pròpia a la barra de menú i pestanya fixa al popover.

Aquest pla desglossa la implementació d'aquesta decisió, reutilitzant al màxim els patrons ja
existents a RadarCat per a "Avisos de pluja" (preferència opt-in + tracker + orquestració a
`RadarStore`), i portant a Swift la lògica de parsing/geometria/vigència ja provada a
`ha-avisoscat`, sense dependre'n en temps d'execució.

## Font de dades i model

`GET https://www.meteo.cat/observacions/radar` (fallback `https://www.meteo.cat/`), HTML públic
sense autenticació, amb el JSON dels avisos incrustat en una crida `Meteocat.avisosSMP({...})`.
v1 processa només `avis`/`vigilancia` amb `afectacions[]` normals (no `preavis`, no
`temps_violent`), sense filtrar per tipus de meteor. Grau de perill 0-6 → categoria: 0 cap
(verd `#B4C828`), 1-2 moderat (groc `#fff200`), 3-4 alt (taronja `#e99b15`), 5-6 molt alt
(vermell `#cf0920`) — colors oficials, tractats com a excepció literal igual que ja fa
`LegendView`.

## Decisions d'arquitectura

1. **Geometria de comarques pre-processada, no decodificada en runtime.** Un script Python
   nou (`Scripts/generate_comarques_geometry.py`) decodifica una sola vegada el TopoJSON oficial
   (`comarquesAmbMar.json`, mateixa font que `ha-avisoscat`) cap a
   `Sources/RadarCat/Resources/comarques.json`: `[{idComarca, nom, rings: [[[lat, lon], ...]]}]`,
   només les 43 comarques terrestres (sense zones marítimes, RadarCat sempre corre a terra).
   Swift només necessita un ray-casting point-in-polygon senzill sobre coordenades planes, mai
   un decodificador d'arcs TopoJSON.
2. **Cicle de vida de la ubicació compartit.** Avui només `alertsEnabled` (pluja) controla
   `LocationProvider`. Amb un segon toggle independent, `location.stop()` només s'ha de cridar
   quan **tots dos** toggles estan desactivats — si no, activar Meteocat i després desactivar
   pluja (o al revés) tallaria la ubicació sota els peus de l'altra funcionalitat. Solució:
   `RadarStore.updateLocationLifecycle()`, alimentat per una funció pura
   `locationShouldBeActive(rainAlertsEnabled:meteocatAlertsEnabled:) -> Bool`, cridada des dels
   dos `onEnabledChange`.
3. **Reutilitzar la sessió HTTP existent** (`RadarStore.session`), sobreescrivint
   `Accept: text/html` a la petició concreta (la sessió ja fixa `Accept: application/json` per
   l'endpoint de metadades del radar).
4. **Mateixa cadència de refresc (6 min)**, sense timer nou — ja per sota del `cache-control`
   real de Meteocat per aquesta pàgina.
5. **Sense insígnia "BETA"**: a diferència dels avisos de pluja (heurística de color de píxel),
   els avisos de Meteocat són dades oficials directes.
6. **Posició del banner**: `StalePillView` ja ocupa dalt-dreta de la targeta; el banner de
   Meteocat viu dalt-esquerra per no col·lidir-hi quan totes dues condicions coincideixen.
7. **Vista de detall** (en clicar el banner): popover senzill amb meteor, categoria (color+text),
   comarca, vigència, comentari — prou per a v1, ampliable després.
8. **Fallback graciós sempre**: qualsevol error de xarxa/parsing (HTML canviat, resposta
   inesperada) fa que el banner simplement no aparegui; mai toca `RadarStore.errorMessage`
   (exclusiu del radar) ni mostra una UI d'error intrusiva.

Fora d'abast d'aquesta v1, deliberadament: API oficial amb `x-api-key`, notificacions push
d'avisos de Meteocat, filtratge per tipus de meteor, `preavis`/`temps_violent`, zones marítimes.

## Patrons reutilitzats (ja existents, no es reinventen)

- **Preferència opt-in**: `AlertPreferences.swift` (`didSet` + `UserDefaults` + closure) — es
  clona per `meteocatAlertsEnabled`.
- **Orquestració amb cua anti-reentrada**: `RadarStore.enqueueRainStateUpdate`/
  `pendingRainState` (línies 332-340) — mateix patró per `enqueueMeteocatAlertUpdate`.
- **Client HTTP**: `RadarStore.refresh()` (línies 217-255) i `RadarAPI.swift` — mateix esquema
  try/catch per `MeteocatAlertsFetcher`.
- **Overlay condicional**: `RadarStageView.overlays(...)` (línies 76-99) i `StalePillView` a
  `MapOverlays.swift` — patró clonat pel nou banner.
- **Toggle**: `SettingsView.swift` i `MoreActionsMenu.swift`, secció "Avisos de pluja" — clonada
  per "Avisos de Meteocat".
- **Tests de lògica pura**: com `RainDetector`/`RainAlertTracker` (26 tests actuals) — cada peça
  nova de lògica pura (parsing, geometria, vigència) porta els seus propis tests analògament.

## Llista de tasques

### Fase 0 — Geometria de comarques
- **T1** Script `Scripts/generate_comarques_geometry.py`: decodifica el TopoJSON oficial cap a
  `Sources/RadarCat/Resources/comarques.json` (43 comarques, anells `[lat, lon]` tancats).
  Auto-verificació al mateix script amb 2 punts de control (Barcelona → Barcelonès, Vic →
  Osona). *Mida S.*
- **T2** `Package.swift`: `resources: [.copy("Resources/comarques.json")]`. *Mida S.*
- **T3** `Sources/RadarCat/ComarcaResolver.swift`: model `Comarca`, càrrega des de
  `Bundle.module`, `static func comarca(at:) -> Comarca?` (ray-casting even-odd). Tests:
  Barcelona, Vic, un punt fora de Catalunya (Fraga) → `nil`, un polígon amb forat. *Mida M.*

**Checkpoint 1**: `swift build`/`swift test` en verd, comarca resolta correctament per
coordenades reals conegudes.

### Fase 1 — Model i parsing (pot anar en paral·lel amb la Fase 0)
- **T4** `Sources/RadarCat/MeteocatAvisosModel.swift`: `MeteocatAfectacio/Evolucio/Avis/Episodi`,
  `MeteocatDangerCategory(perill:)`. Parsing tolerant (`perill` com a Float, llistes `null` com
  a buides, tipus desconeguts no trenquen res). Fixture JSON real d'un avís d'avui. *Mida M.*
- **T5** `Sources/RadarCat/MeteocatAvisosParser.swift`: extreu el JSON incrustat a
  `Meteocat.avisosSMP(...)` d'un HTML (comptador de claudàtors fora de strings, mai regex
  glotó); si n'hi ha diverses còpies, la més rica. `MeteocatParseError` només si la crida no hi
  és. Fixture HTML real. *Mida M.*

**Checkpoint 2**: `swift build`/`swift test` en verd, es pot analitzar un HTML real i obtenir
episodis tipats, sense xarxa ni geometria encara.

### Fase 2 — Vigència, preferències, cicle de vida
- **T6** `Sources/RadarCat/MeteocatAvisosVigencia.swift`: bandes de 6h UTC, `estat` mai comparat
  per igualtat exacta, `avisVigent(episodis:idComarca:now:) -> MeteocatCurrentWarning?`,
  descartant `preavis`/`temps_violent`. *Mida M.*
- **T7** `AlertPreferences.meteocatAlertsEnabled`: mateix patró que `alertsEnabled`, clau
  `UserDefaults` pròpia, closure `onMeteocatEnabledChange`. *Mida S.*
- **T8** `RadarStore.updateLocationLifecycle()` + `locationShouldBeActive(...)` (pura,
  testejable). Enganxa `onMeteocatEnabledChange` a l'`init`, estén la condició de reengegada
  (línia ~192) a `alertsEnabled || meteocatAlertsEnabled`. *Mida M.*

**Checkpoint 2b**: 4 combinacions de toggles provades (unitàriament la funció pura; manualment
el start/stop real amb `compile_and_run.sh` — sense fix GPS real en build ad-hoc, només es pot
confirmar el start/stop, no l'arribada de coordenada, vegeu Riscos).

### Fase 3 — Xarxa i orquestració (encara sense UI)
- **T9** `RadarAPI.swift` + `MeteocatAlertsFetcher.swift`: `GET` amb `Accept: text/html`
  explícit, fallback a `meteoCatURL` si falla. Mock amb `URLProtocol` (primer ús d'aquest
  patró al projecte). *Mida S.*
- **T10** Cablejat a `RadarStore`: `currentMeteocatWarning`, `userComarcaId`,
  `enqueueMeteocatAlertUpdate()` (mateix patró de cua que `enqueueRainStateUpdate`), cridat des
  de `refresh()`, `location.onCoordinateChange`, i `enableMeteocatAlerts()`. Error de xarxa
  manté l'últim valor bo, mai toca `errorMessage`. *Mida M.*

**Checkpoint 3**: pipeline complet (comarca → HTTP → parsing → vigència) verificable per
composició dels tests unitaris de cada peça; encara cap canvi visible (toggle a `false` per
defecte).

### Fase 4 — UI (B + D)
- **T11** `MeteocatWarningBannerView` a `MapOverlays.swift` (patró `StalePillView`), afegit a
  `RadarStageView.overlays(...)`, dalt-esquerra. *Mida S.*
- **T12** `MeteocatAlertDetailView.swift`: popover en clicar el banner. *Mida S.*
- **T13** Toggle a `SettingsView.swift`, patró exacte d'"Avisos de pluja" (sense BETA). *Mida S.*
- **T14** Toggle equivalent a `MoreActionsMenu.swift`. *Mida S.*

**Checkpoint 4**: flux activable des de tots dos punts d'entrada, sincronitzats.

### Fase 5 — Polish
- **T15** Confirmar (test + revisió) que cap error de Meteocat es propaga com a UI intrusiva.
  *Mida S.*
- **T16** `CLAUDE.md`: com regenerar `comarques.json`, i la limitació de verificació manual
  sense build signat. *Mida S.*

**Checkpoint final**: `swift build`/`swift test` en verd (26 tests actuals + nous), tots els
criteris d'acceptació complerts, `CLAUDE.md` actualitzat.

## Fitxers crítics

- `Sources/RadarCat/RadarStore.swift` (orquestració, cicle de vida de la ubicació)
- `Sources/RadarCat/AlertPreferences.swift` (nou toggle)
- `Package.swift` (recurs empaquetat)
- `Sources/RadarCat/RadarStageView.swift` + `MapOverlays.swift` (banner)
- `Sources/RadarCat/SettingsView.swift` + `MoreActionsMenu.swift` (toggle)
- Nous: `ComarcaResolver.swift`, `MeteocatAvisosModel.swift`, `MeteocatAvisosParser.swift`,
  `MeteocatAvisosVigencia.swift`, `MeteocatAlertsFetcher.swift`, `MeteocatAlertDetailView.swift`
- Referència de port (no es toquen): `~/Developer/ha-avisoscat/custom_components/avisoscat/`
  (`comarques.py`, `parser.py`, `vigencia.py`)

## Riscos

| Risc | Mitigació |
|---|---|
| Scraping sense contracte: Meteocat pot canviar l'HTML | `MeteocatParseError` delimitat, fallback graciós (T15), tests fixen el comportament davant HTML trencat |
| `CLLocationManager` no dona fix GPS real amb signatura ad-hoc (`compile_and_run.sh`) — ja documentat a `CLAUDE.md` per `RainNotifier`, afecta igual la resolució de comarca i el banner | Lògica pura 100% testejable amb `swift test`; integració real només verificable amb build signat (Developer ID). Documentat a T8/T10/T11/T12 i a `CLAUDE.md` (T16) |
| TopoJSON de comarques queda desactualitzat si Meteocat toca límits administratius | Poc freqüent; regeneració manual documentada (T16) |

## Verificació end-to-end

1. `swift build` net a cada checkpoint.
2. `swift test` en verd: 26 tests existents + nous (ComarcaResolver, MeteocatAvisosModel,
   MeteocatAvisosParser, MeteocatAvisosVigencia, MeteocatAlertsFetcher, AlertPreferences,
   RadarStore.locationShouldBeActive).
3. Manual amb `Scripts/compile_and_run.sh` (`--scratch-path` si hi ha altres agents actius):
   activar/desactivar tots dos toggles per separat i junts, confirmar persistència entre
   reinicis, confirmar que desactivar un no talla l'altre.
4. Verificació visual del banner: com que aquest entorn no dona mai un fix GPS real amb
   signatura ad-hoc (limitació ja coneguda del projecte), forçar temporalment
   `currentMeteocatWarning` a un valor de mostra (mai comitejat) per revisar disseny/posició, i
   deixar la verificació completa end-to-end (amb ubicació real) pendent d'un build amb
   Developer ID, tal com ja passa amb `RainNotifier`.
