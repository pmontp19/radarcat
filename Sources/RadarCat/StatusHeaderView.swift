import SwiftUI

/// Primera línia del popover: substitueix la capçalera d'app d'abans (nom +
/// icona pròpia, que no aportava res que l'usuari no sabés ja) per l'ESTAT
/// real del radar, que és la informació que ve a buscar. Vegeu
/// `popover-ui-spec.md` secció 1.
///
/// Punt crític (el defecte més greu del disseny anterior): l'hora d'aquí
/// SEMPRE és `store.latestTimestamp` (la darrera imatge disponible), mai la
/// del frame que `RadarAnimator` estigui reproduint en aquell instant -
/// aquesta última només es mostra a `TimelineView`.
struct StatusHeaderView: View {
    @Environment(RadarStore.self) private var store

    private var hasAnyFrame: Bool { !store.animator.frames.isEmpty }
    private var isFirstLoad: Bool { store.animator.isBuilding && !hasAnyFrame }
    private var isErrorWithoutFrame: Bool { store.errorMessage != nil && !hasAnyFrame && !store.animator.isBuilding }
    /// "Error amb frames antics" (secció 4 de l'spec): el darrer refresc ha
    /// fallat però encara tenim un frame per mostrar. A diferència
    /// d'`isStale`, que només es dispara passat un llindar de temps (12-20
    /// min), això s'ha de saber a l'instant: sense connexió just després
    /// d'un refresc bo, l'usuari no ha d'esperar el llindar per veure'n cap
    /// senyal.
    private var hasErrorWithFrame: Bool { store.errorMessage != nil && hasAnyFrame }
    private var hasLocationFix: Bool { store.locationNormalized != nil }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            statusGroup
            Spacer(minLength: 8)
            MoreActionsMenu()
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    /// Glif + títol + subtítol com un sol element per VoiceOver ("Plou a
    /// Reus. Moderada, última imatge 8:12.") en lloc de tres de solts. El
    /// `.combine` es queda NOMÉS a aquest subgrup i no a tot l'`HStack`: si
    /// englobés també `MoreActionsMenu`, el menú "⋯" quedaria fos dins
    /// aquest mateix element combinat i deixaria de ser un control propi
    /// activable per VoiceOver.
    private var statusGroup: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: glyphName)
                .font(.system(size: 15))
                .foregroundStyle(isWarning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))
            VStack(alignment: .leading, spacing: 1) {
                Text(titleText)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitleText)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(subtitleIsWarning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var isWarning: Bool {
        isErrorWithoutFrame
            || hasErrorWithFrame
            || (!isFirstLoad && store.isStale)
            || (!isFirstLoad && !hasLocationFix && store.catalunyaSeverity == nil)
    }

    private var glyphName: String {
        if isFirstLoad { return "cloud.fill" }
        if isWarning { return "exclamationmark.triangle.fill" }
        if hasLocationFix && store.isRainingHere { return "umbrella.fill" }
        if let severity = store.catalunyaSeverity, severity > .none { return "cloud.rain.fill" }
        return "cloud.fill"
    }

    private var titleText: String {
        if isFirstLoad { return "Carregant el radar…" }
        if isErrorWithoutFrame { return "Sense dades de meteo.cat" }
        if hasLocationFix {
            if store.isRainingHere {
                if let place = store.placeName { return "Plou a \(place)" }
                return "Plou a la teva ubicació"
            }
            return "Sense pluja a la teva zona"
        }
        // `store.catalunyaSeverity` és opcional: `nil` vol dir que encara no
        // hem pogut comprovar-ho (cap frame compositat), no que no plogui -
        // NO es desunifica silenciosament cap a "Sense pluja". Es desempaqueta
        // abans del `switch` (en lloc d'un `switch` directe sobre l'opcional)
        // perquè `RainSeverity` ja té un cas propi anomenat `.none`: un
        // `switch` sobre `RainSeverity?` faria que `case .none` es referís al
        // `nil` de l'`Optional`, no al valor `RainSeverity.none` ("sense
        // eco") que volem distingir-ne.
        guard let severity = store.catalunyaSeverity else { return "Sense dades del radar" }
        switch severity {
        case .none: return "Sense pluja a Catalunya"
        case .weak: return "Pluja feble a Catalunya"
        case .moderate, .strong, .hail: return "Pluja activa a Catalunya"
        }
    }

    private var subtitleIsWarning: Bool { !isFirstLoad && (store.isStale || hasErrorWithFrame) }

    private var subtitleText: String {
        // Durant la construcció inicial dels frames `animator.frames` encara
        // és buit (per definició d'`isFirstLoad`), així que no hi ha cap
        // recompte real de "quants en falten" a llegir enlloc - mostrar
        // "N de 10" exigiria assumir un total fix que ningú garanteix
        // (`RadarAnimator.build` el rep com a paràmetre, no és una constant
        // pública). `buildProgress` sí és un senyal real, per això el
        // percentatge ve d'ell directament.
        if isFirstLoad {
            return "Carregant les imatges… \(Int((store.animator.buildProgress * 100).rounded()))%"
        }
        if isErrorWithoutFrame {
            return store.errorMessage ?? "Sense connexió"
        }
        guard let latest = store.latestTimestamp else { return "Sense dades" }
        if store.isStale {
            let minutes = max(0, Int(Date().timeIntervalSince(latest) / 60))
            return "Dades de fa \(minutes) min · pot haver canviat"
        }
        if hasErrorWithFrame {
            // Encara no fa prou estona com per considerar-se `isStale`, però
            // ja sabem que el darrer refresc ha fallat: cal dir-ho igualment
            // en lloc d'esperar el llindar de temps per avisar.
            return "Sense connexió · pot haver canviat"
        }
        let time = latest.hourMinuteLabel
        if hasLocationFix && store.isRainingHere {
            return "\(severityLabel) · última imatge \(time)"
        }
        return "Última imatge \(time)"
    }

    private var severityLabel: String {
        switch store.severityHere {
        case .none: return "Sense eco"
        case .weak: return "Feble"
        case .moderate: return "Moderada"
        case .strong: return "Forta"
        case .hail: return "Calamarsa"
        }
    }
}
