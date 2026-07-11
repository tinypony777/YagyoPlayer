#if DEBUG
import SwiftUI

/// Step 4専用の決定論的な表示fixture。再生・ライブラリには接続しない。
struct ParadePreviewHarness: View {
    @State private var scenario = Scenario.normal
    @State private var residentSpriteID = "kasa"
    @State private var isUshimitsu = false
    @State private var previewReduceMotion = false

    var body: some View {
        NavigationStack {
            ZStack {
                YagyoBackdrop(isUshimitsu: isUshimitsu)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("夜行絵巻 2.0 表示検証")
                            .font(.system(.title2, design: .serif).weight(.semibold))
                            .foregroundStyle(YagyoColor.geppaku)

                        YagyoParadeView(
                            signal: scenario.snapshot,
                            residentSpriteID: residentSpriteID,
                            isUshimitsu: isUshimitsu,
                            onMoonTap: { isUshimitsu.toggle() }
                        )
                        .environment(\.accessibilityReduceMotion, previewReduceMotion)

                        controls

                        Text(
                            scenario.snapshot.accessibilityValue(
                                residentName: residentName,
                                isUshimitsu: isUshimitsu
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(YagyoColor.dim)
                        .accessibilityHidden(true)
                    }
                    .padding(18)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Picker("信号", selection: $scenario) {
                ForEach(Scenario.allCases) { scenario in
                    Text(scenario.label).tag(scenario)
                }
            }
            .accessibilityIdentifier("step4.preview.scenario")

            Picker("先導", selection: $residentSpriteID) {
                ForEach(YokaiResidency.stableSpriteIDs, id: \.self) { spriteID in
                    Text(YokaiGallery.sprite(withID: spriteID)?.name ?? spriteID)
                        .tag(spriteID)
                }
            }
            .accessibilityIdentifier("step4.preview.resident")

            Toggle("丑三つ時", isOn: $isUshimitsu)
                .accessibilityIdentifier("step4.preview.ushimitsu")
            Toggle("Reduce Motion", isOn: $previewReduceMotion)
                .accessibilityIdentifier("step4.preview.reduce-motion")
        }
        .pickerStyle(.menu)
        .tint(YagyoColor.chochin)
        .foregroundStyle(YagyoColor.geppaku)
        .ritualPanel(radius: 20, padding: 16)
    }

    private var residentName: String? {
        YokaiGallery.sprite(withID: residentSpriteID)?.name
    }
}

private enum Scenario: String, CaseIterable, Identifiable {
    case stopped
    case unavailable
    case quiet
    case normal
    case strong

    var id: Self { self }

    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .unavailable: "Unavailable"
        case .quiet: "Quiet proxy"
        case .normal: "Normal"
        case .strong: "Strong open"
        }
    }

    var snapshot: ParadeSignalSnapshot {
        switch self {
        case .stopped:
            .preview(activity: .stopped)
        case .unavailable:
            .preview(activity: .unavailable)
        case .quiet:
            .preview(activity: .quietProxy)
        case .normal:
            .preview(activity: .normal, level: 0.5)
        case .strong:
            .preview(
                activity: .normal,
                level: 0.82,
                strongPhase: .open,
                strongSequence: 1
            )
        }
    }
}
#endif
