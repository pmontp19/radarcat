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
        // Canviar de tema al menú "⋯" ha de recompondre els frames a
        // l'instant, amb el popover ja obert - vegeu el comentari a
        // `AppearancePreference.onModeChange` sobre per què calia aquest
        // ganxo explícit en lloc de confiar només en
        // `MenuBarContentView.onChange(of: colorScheme)` (que no es
        // dispara amb la vista ja muntada quan qui canvia l'aparença és
        // codi imperatiu fora de SwiftUI, `NSApp.appearance`). "Sistema" es
        // resol contra l'aparença REAL del sistema en aquest instant
        // (`currentSystemAppearance()`, mateixa font que a l'`init`) -
        // `FrameAppearance` només té `.light`/`.dark`, mai un tercer cas
        // "segueix el sistema".
        AppearancePreference.shared.onModeChange = { [weak self] mode in
            Task { @MainActor in
                guard let self else { return }
                let resolved: FrameAppearance
                switch mode {
                case .system: resolved = Self.currentSystemAppearance()
                case .light: resolved = .light
                case .dark: resolved = .dark
                }
                await self.setAppearance(resolved)
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
        if AlertPreferences.shared.alertsEnabled {
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

    /// Interval mínim entre refrescos disparats per OBRIR el popover
    /// (`refreshIfNeededOnAppear`, no pas el timer periòdic de dalt de 6
    /// min): prou curt perquè obrir el popover després d'una estona mostri
    /// dades fresques a l'instant en lloc d'esperar el cicle sencer, prou
    /// llarg perquè obrir/tancar-lo diverses vegades seguides (o un doble
    /// clic per accident a la icona de la barra de menú) no dispari una
    /// crida de xarxa nova cada cop.
    private static let openRefreshMinInterval: TimeInterval = 90

    /// Crida des de `MenuBarContentView` cada cop que el popover apareix
    /// (dins el mateix `.task` que ja crida `setAppearance`): refresca NOMÉS
    /// si ha passat prou estona des de l'últim intent, encertat o no
    /// (`lastRefreshAttempt`, no `lastUpdated` - un refresc que ha fallat fa
    /// 10 segons no s'ha de reintentar a l'instant només perquè l'usuari ha
    /// tornat a obrir el popover). `nil` (mai s'ha intentat cap refresc)
    /// sempre en dispara un.
    func refreshIfNeededOnAppear() async {
        if let lastRefreshAttempt, Date().timeIntervalSince(lastRefreshAttempt) < Self.openRefreshMinInterval {
            return
        }
        await refresh()
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
        guard latestTimestamp != nil else { return }
        // `enqueueAppearanceUpdate`, NO `enqueueRebuild`: no hi ha cap
        // timestamp nou, només un canvi d'aparença sobre els mateixos 10
        // frames - `RadarAnimator.recolor` mostra el frame vigent a
        // l'instant en lloc d'esperar que es recomponguin tots deu (vegeu el
        // comentari allà).
        await enqueueAppearanceUpdate(newAppearance)
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
        location.requestPermissionAndStart()
        RainNotifier.requestAuthorization()
        rainAlert = RainAlertTracker()
        await enqueueRainStateUpdate()
        updatePlaceNameIfNeeded()
    }

    /// Contrari d'activar: para la ubicació, cancel·la qualsevol
    /// geocodificació en vol (sense això s'esperaria una resposta de xarxa
    /// que ja no es farà servir) i buida tot el que en depenia perquè la
    /// vista deixi de mostrar dades d'ubicació a l'instant, sense esperar el
    /// pròxim cicle de refresc.
    func disableAlerts() {
        location.stop()
        geocoder.cancelGeocode()
        rainAlert = RainAlertTracker()
        severityHere = .none
        placeName = nil
        lastGeocodedLocation = nil
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

    /// Mateix encadenament que `enqueueRebuild`, sobre la mateixa cua
    /// (`pendingRebuild`): un canvi de tema i un refresc de dades gairebé
    /// simultanis també podrien entrellaçar-se escrivint `animator.frames` a
    /// mitges si no compartissin la mateixa serialització.
    private func enqueueAppearanceUpdate(_ newAppearance: FrameAppearance) async {
        let previous = pendingRebuild
        let task = Task {
            await previous?.value
            await animator.recolor(appearance: newAppearance)
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
