import Foundation

/// Fetches the Meteocat SMP page and resolves the warning vigent for one
/// comarca. Same client shape as `RadarStore.refresh()` (GET, decode,
/// tolerant failure), reusing `RadarStore`'s own `URLSession` rather than
/// creating a second one (docs/plans/avisos-meteocat.md, decision 3).
enum MeteocatAlertsFetcher {
    /// Primary page: same one `ha-avisoscat`'s `PublicPageSource` prefers,
    /// falling back to the plain homepage (`RadarAPI.meteoCatURL`) only if
    /// that fetch or its parse fails - both pages carry the same payload, so
    /// the fallback exists for availability, not to complete a partial
    /// result.
    private static let primaryURL = URL(string: "https://www.meteo.cat/observacions/radar")!

    /// Resolves the most severe warning vigent for `idComarca` at `now`, or
    /// `nil` on ANY failure along the way: network error, an HTML shape the
    /// parser cannot read, or simply no warning applying right now. The
    /// caller (`RadarStore`) treats all of these identically - the banner
    /// just does not appear, never an intrusive error UI
    /// (docs/plans/avisos-meteocat.md, decision 8).
    static func currentWarning(session: URLSession, idComarca: Int, now: Date) async -> MeteocatCurrentWarning? {
        guard let episodis = await fetchEpisodis(session: session) else { return nil }
        return MeteocatAvisosVigencia.avisVigent(episodis: episodis, idComarca: idComarca, now: now)
    }

    private static func fetchEpisodis(session: URLSession) async -> [MeteocatEpisodi]? {
        if let episodis = await fetchAndParse(session: session, url: primaryURL) {
            return episodis
        }
        return await fetchAndParse(session: session, url: RadarAPI.meteoCatURL)
    }

    private static func fetchAndParse(session: URLSession, url: URL) async -> [MeteocatEpisodi]? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 15
        // `RadarStore.session` fixes `Accept: application/json` for the
        // radar metadata endpoint; this request needs the page's HTML, so it
        // overrides that header explicitly on the request itself rather than
        // standing up a second `URLSession`.
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let avisosRaw = try MeteocatAvisosParser.extractAvisos(fromHTML: html)
            return MeteocatAvisos.parseSnapshot(avisosRaw)
        } catch {
            return nil
        }
    }
}
