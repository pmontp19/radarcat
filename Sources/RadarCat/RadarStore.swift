import Foundation
import AppKit
import CoreLocation
import CoreGraphics
import Observation

/// Model observable pel popover: fa polling de les metadades del radar cada
/// 6 min, compon els frames (`RadarAnimator`) i deriva tot el que la vista
/// necessita sobre pluja/ubicació. La vista NOMÉS hi llegeix superfície
/// pública (vegeu la secció "Model per a la vista" de l'spec del redisseny),
/// mai `RadarCompositor`/`RainDetector`/`LocationProvider` directament -
/// l'única excepció és `location.authorizationDenied`, que els Ajustos
/// necessiten per oferir un botó cap a Configuració del Sistema.
@MainActor
@Observable
final class RadarStore {
    private(set) var latestTimestamp: Date?
    private(set) var systemDate: Date?
    private(set) var lastUpdated: Date?
    /// Marca de temps de CADA intent de refresc, l'hagi encertat o no - a
    /// diferència de `lastUpdated` (només s'actualitza si l'intent té èxit).
    /// `isStale` hi llegeix únicament perquè Observation la consideri
    /// "depenent" d'aquesta propietat i la torni a avaluar a cada cicle:
    /// sense res que canviï en un refresc fallit, la vista no tindria cap
    /// motiu per redibuixar-se i la píndola "obsolet" es podria quedar
    /// congelada encara que el temps real vagi avançant.
    private(set) var lastRefreshAttempt: Date?
    private(set) var isRefreshing = false

    /// Missatge d'error ja humanitzat en català per a la vista - mai
    /// `error.localizedDescription`, que ve en l'idioma del sistema (sovint
    /// anglès) i desentonaria en una interfície en català.
    private(set) var errorMessage: String?

    /// Severitat de l'eco al voltant de la ubicació de l'usuari (radi
    /// d'`AlertPreferences.shared.radiusKm`), recalculada cada cop que
    /// s'executa `updateRainState` (cicle de `refresh()`, `enableAlerts()`,
    /// canvi de radi, o arribada d'una coordenada nova - vegeu
    /// `enqueueRainStateUpdate`). `.none` si els avisos estan desactivats,
    /// encara no hi ha coordenada, o l'usuari cau fora del retall.
    private(set) var severityHere: RainSeverity = .none
    /// Severitat màxima enlloc del frame més recent, independentment de la
    /// ubicació de l'usuari - base de la línia d'estat per defecte ("Pluja
    /// activa a Catalunya"/"Sense pluja a Catalunya", segons el nivell) quan
    /// els avisos no estan actius. `nil` vol dir NO HO SABEM (cap frame
    /// compositat encara, p.ex. arrencada freda o error de xarxa/compositat)
    /// - mai s'ha de presentar com "sense pluja". Es calcula sempre a
    /// `updateRainState`, no només quan `alertsEnabled`.
    private(set) var catalunyaSeverity: RainSeverity?
    /// Nom del municipi de l'usuari (geocodificació inversa). `nil` si els
    /// avisos no estan actius, encara no hi ha coordenada, o la
    /// geocodificació ha fallat - la vista ja té text alternatiu per aquest
    /// cas, no cal que aquí es distingeixi el motiu.
    private(set) var placeName: String?

    /// Avís oficial de Meteocat més sever vigent ara mateix a la comarca de
    /// l'usuari, o `nil` si `meteocatAlertsEnabled` és fals, encara no hi ha
    /// coordenada/comarca resolta, no hi ha cap avís vigent, o l'última
    /// consulta ha fallat (fallback graciós sempre - vegeu
    /// `docs/plans/avisos-meteocat.md`, mai toca `errorMessage`, exclusiu
    /// del radar). Recalculat des de `enqueueMeteocatAlertUpdate`.
    private(set) var currentMeteocatWarning: MeteocatCurrentWarning?
    /// Comarca resolta de la coordenada actual, `nil` en les mateixes
    /// condicions que `currentMeteocatWarning` (excepte que una resolució de
    /// comarca correcta però sense avís vigent el deixa amb valor). Exposat
    /// perquè la vista de detall pugui mostrar el nom de la comarca sense
    /// que `MeteocatCurrentWarning` l'hagi de dur ell mateix.
    private(set) var userComarcaId: Int?

    /// Aparença amb què s'han compost els frames vigents. Es llegeix del
    /// sistema ja a l'`init` (vegeu `currentSystemAppearance`) en lloc de
    /// començar sempre en `.light`: `setAppearance` és qui la canvia després,
    /// quan `colorScheme` canviï en calent.
    private(set) var appearance: FrameAppearance

    /// Debouncer de l'alarma de pluja al punt de l'usuari - vegeu
    /// `RainAlertTracker` per la lògica d'histèresi/silenci.
    private var rainAlert = RainAlertTracker()

    let animator = RadarAnimator()
    /// Inert en crear-se (vegeu `LocationProvider`): no demana cap permís
    /// fins que `enableAlerts()` el crida explícitament. Es manté amb
    /// aquest nom perquè `SettingsView` hi llegeix
    /// `store.location.authorizationDenied` directament.
    let location = LocationProvider()

    /// `AlertPreferences.shared`, exposat amb aquest nom perquè la vista hi
    /// programi (`store.alerts.alertsEnabled`, etc.) sense haver de conèixer
    /// el singleton pel seu compte.
    var alerts: AlertPreferences { AlertPreferences.shared }

    /// Posició de l'usuari dins el frame (normalitzada, dalt-esquerra, y
    /// avall - espai de SwiftUI). `nil` si els avisos estan desactivats,
    /// encara no hi ha coordenada, o cau fora del retall de Catalunya.
    var locationNormalized: CGPoint? {
        guard AlertPreferences.shared.alertsEnabled, let coord = location.coordinate else { return nil }
        return RadarFrameGeometry.normalized(lat: coord.latitude, lon: coord.longitude)
    }

    /// Si plou ara mateix al punt de l'usuari (ja passat pel debouncer, no
    /// la lectura instantània) - per la icona de la barra de menú.
    var isRainingHere: Bool { rainAlert.isRaining }

    /// "Obsolet" si fa més de 12 min que no tenim dades fresques.
    var isStale: Bool {
        // Llegim `lastRefreshAttempt` tot i no fer-lo servir al càlcul: només
        // cal perquè Observation torni a avaluar aquesta propietat a cada
        // intent de refresc - vegeu el comentari de la propietat.
        _ = lastRefreshAttempt
        guard let latestTimestamp, let lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 12 * 60 ||
               Date().timeIntervalSince(latestTimestamp) > 20 * 60
    }

    private var timer: Timer?
    private let session: URLSession
    private let refreshInterval: TimeInterval

    /// Cua d'una posició per a `RadarAnimator.build` - vegeu `enqueueRebuild`.
    private var pendingRebuild: Task<Void, Never>?
    /// Cua d'una posició per a `updateRainState` - mateix patró, vegeu
    /// `enqueueRainStateUpdate`.
    private var pendingRainState: Task<Void, Never>?
    /// Cua d'una posició per a `updateMeteocatState` - mateix patró, vegeu
    /// `enqueueMeteocatAlertUpdate`.
    private var pendingMeteocatUpdate: Task<Void, Never>?

    /// Geocodificació inversa del municipi - vegeu `updatePlaceNameIfNeeded`.
    private let geocoder = CLGeocoder()
    private var lastGeocodedLocation: CLLocation?
    /// Distància mínima abans de tornar a geocodificar: a l'escala d'un
    /// municipi uns pocs km de moviment no en canvien el nom, i geocodificar
    /// a cada cicle de refresc (6 min) seria una crida de xarxa gairebé
    /// sempre innecessària.
    private let geocodeMinDistanceMeters: CLLocationDistance = 3000

    init(refreshInterval: TimeInterval = 6 * 60) {
        self.refreshInterval = refreshInterval
        // Llegida ABANS del primer `refresh()` (i, doncs, abans del primer
        // `enqueueRebuild`), no esperant que la vista cridi `setAppearance`
        // en aparèixer: amb el sistema en fosc, sense això es compondrien els
        // 10 primers frames en clar (flaix de mapa blanc en obrir el
        // popover) i tot seguit es tornarien a compondre en fosc en quant la
        // vista arribés - el doble de feina de compositat i un parpelleig
        // visible que un usuari real amb macOS en mode fosc pateix sempre.
        self.appearance = Self.currentSystemAppearance()

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: cfg)

        // Forat de privacitat tancat aquí (P0 de l'spec): `RainNotifier.
        // requestAuthorization()` ja no es crida mai des de l'`init`, i
        // `location` és inert (vegeu `LocationProvider`) fins que algú
        // crida `requestPermissionAndStart()` explícitament. L'únic camí
        // cap a qualsevol permís és `enableAlerts()`, enganxat a
        // `AlertPreferences.onEnabledChange` just a sota - amb els avisos
        // desactivats (per defecte) no hi ha, doncs, cap crida que acabi en
        // un diàleg de permís durant tot aquest `init`.
        AlertPreferences.shared.onEnabledChange = { [weak self] enabled in
            // `[weak self]`: `AlertPreferences.shared` viu tot el procés, i
            // una referència forta aquí convertiria aquesta instància de
            // `RadarStore` en immortal per a la resta de l'execució.
            Task { @MainActor in
                guard let self else { return }
                if enabled {
                    await self.enableAlerts()
                } else {
                    self.disableAlerts()
                }
            }
        }
        // Mateix patró que `onEnabledChange`, per al toggle independent dels
        // avisos de Meteocat (docs/plans/avisos-meteocat.md). `[weak self]`
        // pel mateix motiu.
        AlertPreferences.shared.onMeteocatEnabledChange = { [weak self] enabled in
            Task { @MainActor in
                guard let self else { return }
                if enabled {
                    await self.enableMeteocatAlerts()
                } else {
                    self.disableMeteocatAlerts()
                }
            }
        }
        // El primer fix de GPS no arriba mai de manera síncrona (vegeu
        // `LocationProvider.onCoordinateChange`): sense aquest enganxall,
        // `enableAlerts()` es quedaria cridant `updateRainState`/
        // `updatePlaceNameIfNeeded` amb `coordinate` encara `nil` i l'usuari
        // no veuria severitat ni municipi fins al pròxim cicle de refresc
        // (fins a 6 min) tot i que el punt ja hagués aparegut al mapa.
        // `[weak self]` pel mateix motiu que `onEnabledChange`: `location`
        // és propietat de `self`, així que una referència forta aquí seria
        // un cicle de retenció directe (self -> location -> closure -> self).
        location.onCoordinateChange = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updatePlaceNameIfNeeded()
                await self.enqueueRainStateUpdate()
                await self.enqueueMeteocatAlertUpdate()
            }
        }
        // Canviar el radi als Ajustos ha de recalcular la severitat a
        // l'instant amb el frame que ja hi ha, no esperar el pròxim cicle de
        // refresc (fins a 6 min) - vegeu `AlertPreferences.onRadiusChange`.
        AlertPreferences.shared.onRadiusChange = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.enqueueRainStateUpdate()
            }
        }
        // Si els avisos ja estaven actius d'una sessió anterior, cal
        // reengegar la ubicació: `requestPermissionAndStart()` amb el
        // permís ja concedit no ensenya cap diàleg (vegeu
        // `LocationProvider`), però sí cal cridar-lo perquè el
        // `CLLocationManager`, novament creat en aquest procés, torni a
        // emetre actualitzacions. NO es torna a demanar autorització de
        // notificacions aquí: `UNUserNotificationCenter` recorda la decisió
        // de l'usuari entre llançaments, així que repetir-la no mostraria
        // cap diàleg nou i només seria una crida buida.
        // Igual que abans, però comprovant els DOS toggles (vegeu
        // `locationShouldBeActive`): si només els avisos de Meteocat estaven
        // actius d'una sessió anterior, la ubicació també ha de reengegar-se
        // en arrencar, encara que els avisos de pluja segueixin desactivats.
        if Self.locationShouldBeActive(
            rainAlertsEnabled: AlertPreferences.shared.alertsEnabled,
            meteocatAlertsEnabled: AlertPreferences.shared.meteocatAlertsEnabled
        ) {
            location.requestPermissionAndStart()
        }

        Task { await refresh() }
        startTimer()
    }

    /// Aparença del sistema en aquest instant, llegida d'AppKit directament
    /// (no de l'entorn de SwiftUI, que encara no existeix en aquest punt de
    /// l'`init`) - vegeu el comentari a la crida des de l'`init`.
    private static func currentSystemAppearance() -> FrameAppearance {
        let match = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? .dark : .light
    }

    func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastRefreshAttempt = Date()
        defer { isRefreshing = false }
        do {
            var req = URLRequest(url: RadarAPI.metadataURL, cachePolicy: .reloadIgnoringLocalCacheData)
            req.timeoutInterval = 15
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let meta = try JSONDecoder().decode(RadarMeta.self, from: data)
            // `RadarMeta.parse` és tolerant (retorna `nil` en lloc de
            // llançar) si el format de data canvia: cal comprovar-ho aquí
            // explícitament i llançar, perquè si no, `latestTimestamp`
            // s'acabaria sobreescrivint amb `nil` en sec (sense error ni
            // avís) i la vista perdria l'última hora bona coneguda.
            guard let newLatest = meta.ultimaImatgeDate else {
                throw UnreadableMetadataError()
            }
            let isNew = newLatest != latestTimestamp
            latestTimestamp = newLatest
            systemDate = meta.sistemaDate
            lastUpdated = Date()
            errorMessage = nil
            if isNew {
                await enqueueRebuild(latest: newLatest)
            }
        } catch {
            errorMessage = Self.humanize(error)
        }
        // Sempre, encertat o no el refresc: amb error de xarxa cal seguir
        // servint la severitat/nom calculats sobre el darrer frame vàlid en
        // lloc de deixar-los congelats des d'abans, exactament com feia
        // l'antic `checkRain()`.
        await enqueueRainStateUpdate()
        updatePlaceNameIfNeeded()
        // Mateixa cadència que la pluja, sense timer nou (docs/plans/
        // avisos-meteocat.md): un error de xarxa/parsing aquí es tracta amb
        // el mateix fallback graciós, mai toca `errorMessage`.
        await enqueueMeteocatAlertUpdate()
    }

    /// La vista la crida amb `.onChange(of: colorScheme)` (i un cop en
    /// aparèixer). Recompon els frames NOMÉS si l'aparença canvia de veritat
    /// - si no, no fa res (evita recompondre en cada aparició de la vista;
    /// amb `appearance` ja correcta des de l'`init`, vegeu
    /// `currentSystemAppearance`, la primera crida en aparèixer sol ser
    /// exactament aquest cas de no-res).
    func setAppearance(_ newAppearance: FrameAppearance) async {
        guard newAppearance != appearance else { return }
        appearance = newAppearance
        guard let latest = latestTimestamp else { return }
        await enqueueRebuild(latest: latest)
    }

    /// Únic punt que demana permisos (P0 de l'spec): ubicació primer, que és
    /// la que cal per situar el punt i calcular severitat/municipi;
    /// notificacions després, per poder avisar quan comenci a ploure.
    /// `RainAlertTracker` es reinicia perquè una activació nova no arrossegui
    /// histèresi d'una sessió anterior amb els avisos desactivats. La crida a
    /// `enqueueRainStateUpdate` d'aquí NOMÉS reseteja `severityHere` amb el
    /// frame que ja hi ha - `CLLocationManager` mai dona una posició de
    /// manera síncrona, així que `location.coordinate` encara és `nil` en
    /// aquest punt; el recàlcul de veritat amb la posició real arriba via
    /// `location.onCoordinateChange` (vegeu l'`init`) en quant CoreLocation
    /// entregui el primer fix.
    func enableAlerts() async {
        updateLocationLifecycle()
        RainNotifier.requestAuthorization()
        rainAlert = RainAlertTracker()
        await enqueueRainStateUpdate()
        updatePlaceNameIfNeeded()
    }

    /// Contrari d'activar: para la ubicació NOMÉS si els avisos de Meteocat
    /// tampoc l'estan fent servir (vegeu `updateLocationLifecycle`),
    /// cancel·la qualsevol geocodificació en vol (sense això s'esperaria una
    /// resposta de xarxa que ja no es farà servir) i buida tot el que en
    /// depenia perquè la vista deixi de mostrar dades d'ubicació a l'instant,
    /// sense esperar el pròxim cicle de refresc.
    func disableAlerts() {
        updateLocationLifecycle()
        geocoder.cancelGeocode()
        rainAlert = RainAlertTracker()
        severityHere = .none
        placeName = nil
        lastGeocodedLocation = nil
    }

    /// Activa el banner d'avisos de Meteocat: assegura que la ubicació
    /// estigui activa (compartida amb els avisos de pluja, vegeu
    /// `updateLocationLifecycle`) i força un primer càlcul amb el que ja hi
    /// hagi - com `enableAlerts()`, la coordenada real pot no haver arribat
    /// encara (`CLLocationManager` mai la dona de manera síncrona), el
    /// recàlcul de veritat arriba via `location.onCoordinateChange`.
    func enableMeteocatAlerts() async {
        updateLocationLifecycle()
        await enqueueMeteocatAlertUpdate()
    }

    /// Contrari d'activar: para la ubicació NOMÉS si els avisos de pluja
    /// tampoc l'estan fent servir, i buida l'estat a l'instant en lloc
    /// d'esperar el pròxim cicle de refresc.
    func disableMeteocatAlerts() {
        updateLocationLifecycle()
        currentMeteocatWarning = nil
        userComarcaId = nil
    }

    /// Cicle de vida compartit de la ubicació entre els avisos de pluja i els
    /// de Meteocat (docs/plans/avisos-meteocat.md, decisió 2):
    /// `location.stop()` només es crida quan CAP dels dos toggles està
    /// actiu - activar Meteocat i després desactivar la pluja (o al revés)
    /// no ha de tallar la ubicació sota els peus de l'altra funcionalitat.
    private func updateLocationLifecycle() {
        if Self.locationShouldBeActive(
            rainAlertsEnabled: AlertPreferences.shared.alertsEnabled,
            meteocatAlertsEnabled: AlertPreferences.shared.meteocatAlertsEnabled
        ) {
            location.requestPermissionAndStart()
        } else {
            location.stop()
        }
    }

    /// Funció pura (testejable sense `CLLocationManager` ni `@MainActor`,
    /// per això `nonisolated`): la ubicació ha d'estar activa si QUALSEVOL
    /// dels dos toggles ho està.
    nonisolated static func locationShouldBeActive(rainAlertsEnabled: Bool, meteocatAlertsEnabled: Bool) -> Bool {
        rainAlertsEnabled || meteocatAlertsEnabled
    }

    /// Encadena crides a `RadarAnimator.build`: `refresh()` (timestamp nou) i
    /// `setAppearance()` (canvi de tema) hi passen totes dues. Com que
    /// `RadarStore` és `@MainActor` però `await` és un punt de reentrada,
    /// dues crides gairebé simultànies (p.ex. el timer de 6 min disparant
    /// just quan `colorScheme` canvia) podrien entrellaçar-se dins
    /// `RadarAnimator.build` si es cridessin directament - `frames`/
    /// `currentIndex` quedarien escrits a mitges per totes dues alhora.
    /// Encadenar la nova crida darrere de l'anterior (llegint i assignant
    /// `pendingRebuild` sense cap `await` entremig, així que mai hi ha una
    /// finestra de reentrada en aquest punt concret) garanteix que mai n'hi
    /// ha dues executant-se a la vegada.
    private func enqueueRebuild(latest: Date) async {
        let previous = pendingRebuild
        let currentAppearance = appearance
        let task = Task {
            await previous?.value
            await animator.build(latest: latest, appearance: currentAppearance)
        }
        pendingRebuild = task
        await task.value
    }

    /// Mateix patró que `enqueueRebuild`, aplicat a `updateRainState`:
    /// `refresh()`, `enableAlerts()`, i els avisos de canvi de radi/
    /// coordenada hi passen tots quatre, i sense serialitzar-los una crida
    /// que resol de seguida (p.ex. amb el frame ja cachejat) podria acabar
    /// ABANS que una altra de més antiga encara esperant xarxa, deixant
    /// `severityHere`/`catalunyaSeverity` amb el resultat vell si aquesta
    /// escriu la seva després.
    private func enqueueRainStateUpdate() async {
        let previous = pendingRainState
        let task = Task {
            await previous?.value
            await self.updateRainState()
        }
        pendingRainState = task
        await task.value
    }

    /// Recalcula `catalunyaSeverity` (sempre) i `severityHere`/l'alarma de
    /// l'usuari (només amb avisos actius) sobre el frame més recent. Es
    /// demana amb el mateix timestamp+aparença que `enqueueRebuild` acaba de
    /// compondre, així que `RadarCompositor` el serveix de la seva cache en
    /// lloc de tornar a descarregar res. NOMÉS es crida via
    /// `enqueueRainStateUpdate` (vegeu), mai directament.
    private func updateRainState() async {
        guard let latest = latestTimestamp,
              let cg = await RadarCompositor.shared.compositeFrame(timestamp: latest, appearance: appearance)
        else {
            // Sense frame compositat NO SABEM si plou o no: `catalunyaSeverity`
            // es queda a `nil` (mai s'ha de llegir com "sense pluja" per manca
            // de dades) i `rainAlert` NO es toca - tractar un error de xarxa/
            // compositat com un cicle sec confirmat podria netejar l'alarma de
            // l'usuari sense cap prova real que hagi deixat de ploure.
            catalunyaSeverity = nil
            if AlertPreferences.shared.alertsEnabled {
                severityHere = .none
            }
            return
        }
        catalunyaSeverity = RainDetector.maxSeverityOverFrame(in: cg)

        // Sense avisos actius `severityHere` es queda tal com l'ha deixat
        // `disableAlerts()` (.none): no té sentit ni ubicació a mirar.
        guard AlertPreferences.shared.alertsEnabled else { return }

        let severity: RainSeverity
        if let coord = location.coordinate,
           let normalized = RadarFrameGeometry.normalized(lat: coord.latitude, lon: coord.longitude) {
            severity = RainDetector.maxSeverity(in: cg, aroundNormalized: normalized, radiusKm: AlertPreferences.shared.radiusKm)
        } else {
            // Encara sense posició (o l'usuari cau fora del retall): es
            // tracta com "sense eco", subjecte a la mateixa histèresi que un
            // aclariment real - vegeu el raonament a `RainAlertTracker`.
            severity = .none
        }
        severityHere = severity
        if rainAlert.update(severity: severity) {
            RainNotifier.notifyRainStarted()
        }
    }

    /// Mateix patró que `enqueueRainStateUpdate`, aplicat a
    /// `updateMeteocatState`: `refresh()`, `location.onCoordinateChange`, i
    /// `enableMeteocatAlerts()` hi passen tots tres, serialitzats perquè una
    /// consulta que resol de seguida no pugui acabar abans que una altra més
    /// antiga encara esperant xarxa.
    private func enqueueMeteocatAlertUpdate() async {
        let previous = pendingMeteocatUpdate
        let task = Task {
            await previous?.value
            await self.updateMeteocatState()
        }
        pendingMeteocatUpdate = task
        await task.value
    }

    /// Resol la comarca de la coordenada actual i, si n'hi ha, l'avís
    /// vigent - o buida totes dues coses si els avisos de Meteocat estan
    /// desactivats, encara no hi ha coordenada, o la coordenada cau fora de
    /// Catalunya. Qualsevol error de xarxa/parsing de
    /// `MeteocatAlertsFetcher` ja arriba aquí com a `nil` (fallback graciós
    /// sempre, mai toca `errorMessage`) - es manté l'últim avís bo conegut
    /// NOMÉS mentre la comarca resolta sigui la mateixa; si la comarca ha
    /// canviat, un avís de la comarca antiga no té sentit per a la nova.
    private func updateMeteocatState() async {
        guard AlertPreferences.shared.meteocatAlertsEnabled,
              let coord = location.coordinate,
              let comarca = ComarcaResolver.comarca(at: coord.latitude, lon: coord.longitude)
        else {
            currentMeteocatWarning = nil
            userComarcaId = nil
            return
        }
        userComarcaId = comarca.idComarca
        currentMeteocatWarning = await MeteocatAlertsFetcher.currentWarning(
            session: session, idComarca: comarca.idComarca, now: Date()
        )
    }

    /// Geocodificació inversa del municipi de l'usuari - cachejada per
    /// coordenada (vegeu `geocodeMinDistanceMeters`) perquè no calgui
    /// tornar-la a demanar a cada cicle de refresc si l'usuari no s'ha
    /// mogut. Silenciosa en cas d'error: `placeName` es queda a `nil` i la
    /// vista ja té text alternatiu per aquest cas.
    private func updatePlaceNameIfNeeded() {
        guard AlertPreferences.shared.alertsEnabled, let coord = location.coordinate else {
            placeName = nil
            lastGeocodedLocation = nil
            return
        }
        let current = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        if let last = lastGeocodedLocation, current.distance(from: last) < geocodeMinDistanceMeters {
            return
        }
        lastGeocodedLocation = current
        Task {
            guard let placemark = try? await geocoder.reverseGeocodeLocation(current).first,
                  let name = placemark.locality ?? placemark.subAdministrativeArea
            else { return }
            // Comprova que la ubicació no hagi tornat a canviar (o els
            // avisos no s'hagin desactivat) mentre esperàvem la resposta:
            // si ha passat, aquest resultat ja és obsolet i no s'aplica.
            guard AlertPreferences.shared.alertsEnabled,
                  let stillCoord = location.coordinate,
                  CLLocation(latitude: stillCoord.latitude, longitude: stillCoord.longitude)
                      .distance(from: current) < geocodeMinDistanceMeters
            else { return }
            placeName = name
        }
    }

    /// Missatges d'error propis en català - mai `error.localizedDescription`
    /// (ve en l'idioma del sistema, sovint anglès, i desentonaria en una
    /// interfície en català). Els casos de `URLError` cobreixen el gruix
    /// real (sense connexió, timeout, resposta HTTP no-200 que `refresh()`
    /// ja converteix en `.badServerResponse`); la resta (JSON il·legible o
    /// qualsevol altra cosa inesperada) cau al missatge genèric.
    private static func humanize(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
                return "Sense connexió a internet."
            case .timedOut:
                return "El servidor de Meteocat ha trigat massa a respondre."
            case .badServerResponse:
                return "Resposta inesperada del servidor de Meteocat."
            default:
                return "No s'ha pogut actualitzar el radar. Torna-ho a provar."
            }
        }
        if error is DecodingError || error is UnreadableMetadataError {
            return "Les dades del radar no s'han pogut llegir."
        }
        return "No s'ha pogut actualitzar el radar. Torna-ho a provar."
    }
}

/// Llançat quan les metadades arriben com a JSON vàlid però amb una data que
/// `RadarMeta.parse` no sap interpretar - vegeu `refresh()`, on evita que
/// `latestTimestamp` s'acabi sobreescrivint amb `nil` en sec.
private struct UnreadableMetadataError: Error {}
