import SwiftUI

// MARK: - Lege toestand

/// Eén stijl voor alle lege toestanden: icoon in een zacht vlak, korte titel,
/// uitleg wat hier komt te staan, en de logische volgende stap.
struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var primary: (String, () -> Void)? = nil
    var secondary: (String, () -> Void)? = nil
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            Image(systemName: icon)
                .font(.system(size: compact ? 20 : 28, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: compact ? 44 : 64, height: compact ? 44 : 64)
                .background(accent.opacity(0.1), in: Circle())
            Text(title)
                .font(compact ? .headline : .title3.weight(.semibold))
            Text(message)
                .font(compact ? .callout : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
            if primary != nil || secondary != nil {
                HStack(spacing: 10) {
                    if let secondary { Button(secondary.0, action: secondary.1) }
                    if let primary { Button(primary.0, action: primary.1).buttonStyle(.borderedProminent) }
                }
                .controlSize(compact ? .small : .regular)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 16 : 40)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Laadtoestand

/// Skelet van een pagina terwijl de gegevens worden ingelezen. Verschijnt pas na een korte
/// vertraging, zodat er bij snel laden niets knippert. Bij lang laden komt er uitleg bij.
struct LoadingState: View {
    enum Layout { case dashboard, table, form }
    let layout: Layout
    @EnvironmentObject var store: Store
    @Local private var visible = false
    @Local private var slow = false

    init(layout: Layout) { self.layout = layout }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Skeleton(width: 260, height: 34)
                    Skeleton(width: 340, height: 16)
                }
                .padding(.bottom, 8)

                switch layout {
                case .dashboard:
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            HStack(spacing: 16) { tileSkeleton; tileSkeleton }
                            HStack(spacing: 16) { tileSkeleton; tileSkeleton }
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            Skeleton(width: 140, height: 20)
                            Skeleton(height: 210)
                        }
                        .card()
                    }
                    rowsCard(4)
                case .table:
                    rowsCard(8)
                case .form:
                    VStack(alignment: .leading, spacing: 14) {
                        Skeleton(width: 160, height: 20)
                        Skeleton(height: 32); Skeleton(height: 32); Skeleton(height: 32)
                    }
                    .card()
                    rowsCard(3)
                }

                if slow {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Gegevens worden geladen uit \(store.folderKind.name)… Dit kan even duren als ze nog gedownload worden.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 28).padding(.top, 6)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .canvas()
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gegevens worden geladen")
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeOut(duration: 0.2)) { visible = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeOut(duration: 0.3)) { slow = true }
            }
        }
    }

    private var tileSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            Skeleton(width: 22, height: 22)
            Spacer(minLength: 24)
            Skeleton(width: 150, height: 28)
            Skeleton(width: 100, height: 14)
        }
        .frame(minHeight: 120)
        .card()
    }

    private func rowsCard(_ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Skeleton(width: 180, height: 20)
            ForEach(0..<n, id: \.self) { i in
                HStack(spacing: 12) {
                    Skeleton(width: 28, height: 28).clipShape(Circle())
                    Skeleton(height: 14).frame(maxWidth: CGFloat(220 + (i % 3) * 60))
                    Spacer()
                    Skeleton(width: 90, height: 14)
                    Skeleton(width: 70, height: 20)
                }
            }
        }
        .card()
    }
}

/// Grijs blok met een zachte glans die eroverheen loopt (statisch bij ‘Verminder beweging’).
struct Skeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Local private var phase: CGFloat = -1

    init(width: CGFloat? = nil, height: CGFloat = 14) { self.width = width; self.height = height }

    var body: some View {
        RoundedRectangle(cornerRadius: min(height / 2, 8), style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Color.primary.opacity(0.06), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width * 1.6)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: min(height / 2, 8), style: .continuous))
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}
