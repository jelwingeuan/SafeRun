import AppKit
import SwiftUI

enum SafeRunTheme {
    static let accent = Color(red: 0.20, green: 0.55, blue: 0.94)
    static let accentSoft = accent.opacity(0.14)
    static let safe = Color(red: 0.20, green: 0.66, blue: 0.53)
    static let caution = Color(red: 0.90, green: 0.58, blue: 0.19)
    static let danger = Color(red: 0.86, green: 0.28, blue: 0.25)
    static let surfaceRadius: CGFloat = 16
    static let floatingRadius: CGFloat = 20
    static let pageWidth: CGFloat = 1_140
}

enum SafeRunMotion {
    static let quick = Animation.spring(response: 0.24, dampingFraction: 0.86)
    static let gentle = Animation.spring(response: 0.38, dampingFraction: 0.88)
}

struct SafeRunAtmosphere: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            RadialGradient(
                colors: [
                    SafeRunTheme.accent.opacity(colorScheme == .dark ? 0.13 : 0.075),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 540
            )

            RadialGradient(
                colors: [
                    SafeRunTheme.safe.opacity(colorScheme == .dark ? 0.055 : 0.032),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}

private struct SafeRunGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let tint: Color?
    let cornerRadius: CGFloat
    let interactive: Bool
    let elevated: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if #available(macOS 26.0, *), !reduceTransparency {
                if interactive {
                    content
                        .glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    content
                        .glassEffect(.regular.tint(tint), in: shape)
                }
            } else {
                content
                    .background {
                        ZStack {
                            if reduceTransparency {
                                shape.fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
                            } else {
                                shape.fill(.regularMaterial)
                            }
                            if let tint {
                                shape.fill(tint.opacity(reduceTransparency ? 0.10 : 0.055))
                            }
                        }
                    }
            }
        }
        .overlay {
            shape
                .strokeBorder(.primary.opacity(reduceTransparency ? 0.16 : 0.09), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(elevated ? (reduceTransparency ? 0.12 : 0.07) : 0.025),
            radius: elevated ? 16 : 8,
            y: elevated ? 6 : 3
        )
    }
}

extension View {
    func safeRunGlassSurface(
        tint: Color? = nil,
        cornerRadius: CGFloat = SafeRunTheme.surfaceRadius,
        interactive: Bool = false,
        elevated: Bool = false
    ) -> some View {
        modifier(
            SafeRunGlassSurfaceModifier(
                tint: tint,
                cornerRadius: cornerRadius,
                interactive: interactive,
                elevated: elevated
            )
        )
    }

    @ViewBuilder
    func safeRunGlassEffectID(_ id: String?, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func safeRunGlassTransition() -> some View {
        if #available(macOS 26.0, *) {
            glassEffectTransition(.matchedGeometry)
        } else {
            self
        }
    }
}

struct GlassEffectGroup<Content: View>: View {
    let spacing: CGFloat?
    private let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: spacing) {
                    content
                }
            } else {
                content
            }
        }
    }
}

struct GlassCard<Content: View>: View {
    private let content: Content
    var padding: CGFloat = 20
    var tint: Color?

    init(padding: CGFloat = 20, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .safeRunGlassSurface(tint: tint)
    }
}

struct InteractiveGlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private let content: Content
    var padding: CGFloat = 18
    var tint: Color?

    init(padding: CGFloat = 18, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .safeRunGlassSurface(tint: tint, interactive: true, elevated: isHovering)
            .scaleEffect(isHovering && !reduceMotion ? 1.008 : 1)
            .animation(reduceMotion ? nil : SafeRunMotion.quick, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

struct FloatingGlassPanel<Content: View>: View {
    private let content: Content
    var padding: CGFloat = 22
    var tint: Color?

    init(padding: CGFloat = 22, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .safeRunGlassSurface(
                tint: tint,
                cornerRadius: SafeRunTheme.floatingRadius,
                elevated: true
            )
    }
}

struct GlassStatusPill: View {
    let title: String
    let systemImage: String
    var tint: Color = SafeRunTheme.accent

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .safeRunGlassSurface(tint: tint.opacity(0.36), cornerRadius: 999)
            .accessibilityElement(children: .combine)
    }
}

enum GlassButtonProminence {
    case standard
    case prominent
}

struct GlassButton<Label: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let action: () -> Void
    let prominence: GlassButtonProminence
    let tint: Color
    let isDisabled: Bool
    private let label: Label

    init(
        prominence: GlassButtonProminence = .standard,
        tint: Color = SafeRunTheme.accent,
        isDisabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.prominence = prominence
        self.tint = tint
        self.isDisabled = isDisabled
        self.label = label()
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *), !reduceTransparency {
                if prominence == .prominent {
                    Button(action: action) {
                        label
                    }
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                } else {
                    Button(action: action) {
                        label
                    }
                    .buttonStyle(.glass)
                    .tint(tint)
                }
            } else {
                if prominence == .prominent {
                    Button(action: action) {
                        label
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                } else {
                    Button(action: action) {
                        label
                    }
                    .buttonStyle(.bordered)
                    .tint(tint)
                }
            }
        }
        .disabled(isDisabled)
    }
}

struct GlassToolbar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .safeRunGlassSurface(cornerRadius: 12)
    }
}

struct GlassActionBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    let actionCount: Int
    let risk: RiskLevel
    let simulationResult: SimulationResult?
    let isSimulating: Bool
    let isExecuting: Bool
    let isExecuted: Bool
    let executionProgress: Double
    let isApproved: Bool
    let onCancel: () -> Void
    let onEditPlan: () -> Void
    let onPrimaryAction: () -> Void

    private var isComplete: Bool { simulationResult != nil }

    private var primaryTitle: String {
        if isSimulating { return "Simulating…" }
        if isExecuting { return "Executing…" }
        if isExecuted { return "Completed" }
        if isApproved { return "Approved" }
        return isComplete ? "Run Safely" : "Simulate"
    }

    private var primarySymbol: String {
        if isExecuting { return "arrow.triangle.2.circlepath" }
        if isExecuted { return "checkmark.circle.fill" }
        if isApproved { return "checkmark.shield.fill" }
        return isComplete ? "play.shield.fill" : "play.fill"
    }

    private var canRun: Bool {
        simulationResult?.canExecute == true
    }

    var body: some View {
        GlassEffectGroup(spacing: 14) {
            HStack(spacing: 14) {
                if isComplete {
                    GlassButton(isDisabled: isExecuting || isSimulating, action: onEditPlan) {
                        Label("Edit Plan", systemImage: "slider.horizontal.3")
                    }
                    .safeRunGlassEffectID("plan-secondary-action", in: glassNamespace)
                } else {
                    GlassButton(isDisabled: isExecuting || isSimulating, action: onCancel) {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .safeRunGlassEffectID("plan-secondary-action", in: glassNamespace)
                }

                GlassStatusPill(
                    title: isExecuted ? "Completed" : (isExecuting ? "Executing…" : (isComplete ? (isApproved ? "Approved" : (canRun ? "Ready to Run" : "Needs Review")) : "\(actionCount) Actions · \(risk.title) Risk")),
                    systemImage: isExecuted ? "checkmark.circle" : (isExecuting ? "arrow.triangle.2.circlepath" : (isComplete ? (isApproved || canRun ? "checkmark.shield" : "exclamationmark.shield") : risk.systemImage)),
                    tint: isExecuted ? SafeRunTheme.safe : (isExecuting ? SafeRunTheme.accent : (isComplete ? (isApproved || canRun ? SafeRunTheme.safe : SafeRunTheme.caution) : risk.tint))
                )
                .safeRunGlassEffectID("plan-status", in: glassNamespace)

                Spacer(minLength: 8)

                GlassButton(
                    prominence: .prominent,
                    tint: isComplete ? SafeRunTheme.safe : SafeRunTheme.accent,
                    isDisabled: isSimulating || isExecuting || isExecuted || isApproved || actionCount == 0 || (isComplete && !canRun),
                    action: onPrimaryAction
                ) {
                    HStack(spacing: 7) {
                        if isSimulating || isExecuting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Label(primaryTitle, systemImage: primarySymbol)
                    }
                }
                .help(isComplete && !canRun ? "Resolve simulation conflicts before SafeRun can be approved." : "")
                .safeRunGlassEffectID("plan-primary-action", in: glassNamespace)
            }
            .padding(10)
            .safeRunGlassSurface(
                tint: isComplete ? SafeRunTheme.safe.opacity(0.24) : SafeRunTheme.accent.opacity(0.18),
                cornerRadius: 18,
                elevated: true
            )
            .safeRunGlassTransition()
        }
        .animation(reduceMotion ? nil : SafeRunMotion.gentle, value: isComplete)
        .accessibilityValue(isExecuting ? "\(Int(executionProgress * 100)) percent complete" : primaryTitle)
    }
}

extension RiskLevel {
    var tint: Color {
        switch self {
        case .low: SafeRunTheme.safe
        case .medium: SafeRunTheme.caution
        case .high: .orange
        case .critical: SafeRunTheme.danger
        }
    }
}
