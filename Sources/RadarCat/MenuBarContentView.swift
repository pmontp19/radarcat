import SwiftUI
import AppKit

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
