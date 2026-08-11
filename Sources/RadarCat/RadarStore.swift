import Foundation
import Observation

/// Model observable: fa polling de les metadades del radar cada 6 min i manté
/// l'estat (darrera imatge disponible, errors, refresc manual).
@MainActor
@Observable
final class RadarStore {
    private(set) var latestTimestamp: Date?
    private(set) var systemDate: Date?
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    let animator = RadarAnimator()

    private var timer: Timer?
    private let session: URLSession
    private let refreshInterval: TimeInterval

    init(refreshInterval: TimeInterval = 6 * 60) {
        self.refreshInterval = refreshInterval
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: cfg)
        Task { await refresh() }
        startTimer()
    }

    /// "Està" si fa més de 12 min que no tenim dades fresques.
    var isStale: Bool {
        guard let latestTimestamp, let lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 12 * 60 ||
               Date().timeIntervalSince(latestTimestamp) > 20 * 60
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
        defer { isRefreshing = false }
        do {
            var req = URLRequest(url: RadarAPI.metadataURL, cachePolicy: .reloadIgnoringLocalCacheData)
            req.timeoutInterval = 15
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let meta = try JSONDecoder().decode(RadarMeta.self, from: data)
            let newLatest = meta.ultimaImatgeDate
            let isNew = newLatest != latestTimestamp
            latestTimestamp = newLatest
            systemDate = meta.sistemaDate
            lastUpdated = Date()
            lastError = nil
            if isNew, let latest = newLatest {
                await animator.build(latest: latest)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
