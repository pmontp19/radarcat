import SwiftUI
import AppKit
import CoreLocation

/// Contingut del popover: capçalera amb timestamp del frame actual, radar
/// animat compositat, i controls de reproducció (play/pausa + cronològic).
struct MenuBarContentView: View {
    @Environment(RadarStore.self) private var store

    var body: some View {
        let animator = store.animator
        VStack(spacing: 0) {
            header(animator: animator)
            Divider()
            radarStage(animator: animator)
            Divider()
            controls(animator: animator)
            footer
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Capçalera

    private func header(animator: RadarAnimator) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "cloud.rain.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Radar Catalunya").font(.headline)
                if store.isRefreshing && animator.isEmpty {
                    Text("Connectant…").font(.caption).foregroundStyle(.secondary)
                } else if let err = store.lastError, animator.isEmpty {
                    Text(err).font(.caption).foregroundStyle(.red).lineLimit(1)
                } else if let ts = animator.currentTimestamp ?? store.latestTimestamp {
                    Text("Darrera imatge: \(ts.shortLabel)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if animator.isBuilding {
                ProgressView(value: animator.buildProgress)
                    .frame(width: 44)
            }
            Button {
                Task { await store.refresh() }
            } label: { Image(systemName: "arrow.clockwise") }
            .buttonStyle(.borderless).help("Refresca")
            .disabled(store.isRefreshing)
        }
        .padding(10)
    }

    // MARK: - Escenari del radar

    /// Amplada del contingut del popover. `RadarCatApp` fa servir la
    /// mateixa constant pel seu `.frame(width:)` perquè mai puguin quedar
    /// desincronitzades.
    static let stageWidth: CGFloat = 380

    private func radarStage(animator: RadarAnimator) -> some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.04))
            if let img = animator.currentImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .padding(4)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(animator.isBuilding ? "Composant radar…" : "Sense dades")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let pos = locationMarkerPosition {
                LocationMarker().position(pos)
            }
        }
        // Alçada calculada explícitament a partir de l'amplada i de
        // l'aspecte real del frame compositat
        // (`RadarCompositor.catalunyaCropAspectRatio`), en lloc d'un
        // `maxHeight: .infinity` (que s'expandia a qualsevol alçada que li
        // deixés la finestra fixada a mà, deixant bandes negres buides a
        // dalt/baix) o d'un `.aspectRatio(.fit)` sol (que, provat en viu,
        // no derivava l'alçada de manera fiable dins d'aquest VStack -
        // acabava amb la mida intrínseca petita del contingut placeholder).
        // Calcular-ho a mà és més verbós però determinista.
        .frame(width: Self.stageWidth, height: Self.stageWidth / RadarCompositor.catalunyaCropAspectRatio)
    }

    /// Posició del punt "la meva ubicació" dins `radarStage`, en l'espai
    /// local de la vista (origen dalt-esquerra, y avall, com SwiftUI).
    /// `nil` si no hi ha ubicació coneguda o si cau fora del retall de
    /// Catalunya - en aquest cas s'amaga el punt en lloc de clavar-lo a
    /// una vora, ja que pot passar legítimament si l'usuari és fora de
    /// Catalunya.
    private var locationMarkerPosition: CGPoint? {
        guard let coord = store.location.coordinate,
              let px = GeoPosition.pixel(lat: coord.latitude, lon: coord.longitude)
        else { return nil }
        let crop = RadarCompositor.catalunyaCrop
        let stageHeight = Self.stageWidth / RadarCompositor.catalunyaCropAspectRatio
        // La imatge composada omple exactament (4,4)...(stageWidth-4,
        // stageHeight-4) dins l'escenari (exact-fit, vegeu `radarStage`).
        // `px`/`py` són en l'espai natiu del retall (origen baix-esquerra, y
        // amunt) - cal invertir la y per l'espai de SwiftUI (dalt-esquerra,
        // y avall).
        let nx = px.x / crop.width
        let ny = 1 - px.y / crop.height
        return CGPoint(
            x: 4 + nx * (Self.stageWidth - 8),
            y: 4 + ny * (stageHeight - 8)
        )
    }

    // MARK: - Controls

    private func controls(animator: RadarAnimator) -> some View {
        HStack(spacing: 10) {
            Button {
                animator.toggle()
            } label: {
                Image(systemName: animator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22)
            }
            .buttonStyle(.borderless)
            .disabled(animator.frames.count < 2)

            if animator.frames.count > 1 {
                Slider(
                    value: Binding(
                        get: { Double(animator.currentIndex) },
                        set: { animator.seek(to: Int($0.rounded())); animator.pause() }
                    ),
                    in: 0...Double(animator.frames.count - 1)
                )
            }
            Text("\(animator.currentIndex + 1)/\(max(1, animator.frames.count))")
                .font(.caption2).foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    // MARK: - Peu

    private var footer: some View {
        HStack {
            if store.isStale {
                Label("Obsolet", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.orange)
            }
            Spacer()
            Link("meteo.cat", destination: RadarAPI.meteoCatURL).font(.caption2)
            Button("Surt") { NSApp.terminate(nil) }
                .buttonStyle(.borderless).font(.caption2)
        }
        .padding(8)
    }
}

/// Punt "la meva ubicació" a l'estil Maps: cercle blau amb vora blanca.
private struct LocationMarker: View {
    var body: some View {
        ZStack {
            Circle().fill(.white).frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.3), radius: 1)
            Circle().fill(Color.blue).frame(width: 9, height: 9)
        }
    }
}
