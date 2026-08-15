import Testing
@testable import RadarCat

/// `RadarStore.locationShouldBeActive` is the pure predicate behind the
/// shared location lifecycle between rain alerts and Meteocat alerts
/// (docs/plans/avisos-meteocat.md, decision 2): `location.stop()` must only
/// ever be reached when BOTH toggles are off, so enabling one after
/// disabling the other never cuts location out from under the one still on.
@Suite struct RadarStoreLocationLifecycleTests {
    @Test func bothDisabledMeansLocationShouldStop() {
        #expect(RadarStore.locationShouldBeActive(rainAlertsEnabled: false, meteocatAlertsEnabled: false) == false)
    }

    @Test func onlyRainEnabledKeepsLocationActive() {
        #expect(RadarStore.locationShouldBeActive(rainAlertsEnabled: true, meteocatAlertsEnabled: false) == true)
    }

    @Test func onlyMeteocatEnabledKeepsLocationActive() {
        #expect(RadarStore.locationShouldBeActive(rainAlertsEnabled: false, meteocatAlertsEnabled: true) == true)
    }

    @Test func bothEnabledKeepsLocationActive() {
        #expect(RadarStore.locationShouldBeActive(rainAlertsEnabled: true, meteocatAlertsEnabled: true) == true)
    }
}
