import SwiftUI

struct ModelPickerView: View {
    @ObservedObject var viewModel: ModelPickerViewModel
    @Environment(\.dismiss) private var dismiss
    var onSelect: (OCProvider, OCModel) -> Void

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                        Text("Đang tải danh sách mô hình...")
                            .font(.system(size: 13))
                            .foregroundColor(SpaceTheme.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundColor(SpaceTheme.busy)
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(SpaceTheme.secondary)
                            .multilineTextAlignment(.center)
                        Button("Thử lại") {
                            Task { await viewModel.loadProviders() }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(SpaceTheme.accentGradient)
                        .clipShape(Capsule())
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    providerList
                }
            }
            .spaceBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Chọn mô hình")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .onAppear { Task { await viewModel.loadProviders() } }
        }
    }

    private var providerList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.filteredProviders) { provider in
                        providerSection(provider)
                    }
                }
                .padding(.bottom, 24)
            }

            // Toggle hide unused models
            Toggle(isOn: $viewModel.hideUnusedModels) {
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 14))
                    Text("Chỉ hiện model đang dùng")
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(SpaceTheme.surface)
            .overlay(
                Rectangle()
                    .fill(SpaceTheme.cardBorder)
                    .frame(height: 0.5),
                alignment: .top
            )
        }
    }

    @ViewBuilder
    private func providerSection(_ provider: OCProvider) -> some View {
        let hue = SpaceTheme.providerHue(provider.name)

        // Header with planet badge
        HStack(spacing: 10) {
            ProviderPlanet(name: provider.name)
                .frame(width: 22, height: 22)

            Text(provider.name)
                .font(.system(size: 15, weight: .bold))
                .tracking(0.5)
                .foregroundColor(SpaceTheme.primary)

            Spacer()

            Text("\(provider.models.count) mô hình")
                .font(.system(size: 12))
                .foregroundColor(SpaceTheme.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)

        VStack(spacing: 6) {
            ForEach(provider.models) { model in
                modelRow(provider: provider, model: model, hue: hue)
            }
        }
        .padding(.horizontal, 16)
    }

    private func modelRow(provider: OCProvider, model: OCModel, hue: Color) -> some View {
        let selected = viewModel.isSelected(provider: provider.id, model: model.id)
        return Button {
            onSelect(provider, model)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                // Small accent dot
                Circle()
                    .fill(hue)
                    .frame(width: 6, height: 6)
                    .shadow(color: hue.opacity(0.7), radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                    if let desc = model.description {
                        Text(desc)
                            .font(.system(size: 13))
                            .foregroundColor(SpaceTheme.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(hue)
                        .shadow(color: hue.opacity(0.5), radius: 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(
            selected
                ? AnyView(LinearGradient(
                    colors: [hue.opacity(0.10), hue.opacity(0.04)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                : AnyView(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    selected ? hue.opacity(0.3) : SpaceTheme.cardBorder,
                    lineWidth: 0.7
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// Hành tinh nhỏ đại diện cho provider
struct ProviderPlanet: View {
    let name: String

    var body: some View {
        Circle()
            .fill(SpaceTheme.providerGradient(name))
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.5), .clear],
                            center: UnitPoint(x: 0.3, y: 0.25),
                            startRadius: 0,
                            endRadius: 8
                        )
                    )
            )
            .shadow(color: SpaceTheme.providerHue(name).opacity(0.5), radius: 6)
    }
}
