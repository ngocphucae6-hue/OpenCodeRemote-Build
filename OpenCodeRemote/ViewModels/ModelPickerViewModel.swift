import Foundation

@MainActor
class ModelPickerViewModel: ObservableObject {
    @Published var providers: [OCProvider] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedProvider: String?
    @Published var selectedModel: String?
    @Published var hideUnusedModels: Bool = false

    private let api: OpenCodeAPI

    init() {
        let config = ServerConfig.load()
        self.api = OpenCodeAPI(config: config)
        loadSavedSelection()
    }

    func loadProviders() async {
        isLoading = true
        error = nil
        do {
            let response = try await api.listProviders()
            providers = response
            isLoading = false
        } catch {
            self.error = "Không thể tải danh sách: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func select(provider: String, model: String) {
        selectedProvider = provider
        selectedModel = model
        UserDefaults.standard.set(provider, forKey: "selected_provider")
        UserDefaults.standard.set(model, forKey: "selected_model")
    }

    func isSelected(provider: String, model: String) -> Bool {
        selectedProvider == provider && selectedModel == model
    }

    /// Providers đã lọc theo hideUnusedModels
    var filteredProviders: [OCProvider] {
        if !hideUnusedModels {
            return providers
        }
        guard let selectedProvider = selectedProvider,
              let selectedModel = selectedModel else {
            return providers
        }
        if let provider = providers.first(where: { $0.id == selectedProvider }) {
            let filteredModels = provider.models.filter { $0.id == selectedModel }
            if !filteredModels.isEmpty {
                return [OCProvider(id: provider.id, name: provider.name, models: filteredModels)]
            }
        }
        return providers
    }

    private func loadSavedSelection() {
        selectedProvider = UserDefaults.standard.string(forKey: "selected_provider")
        selectedModel = UserDefaults.standard.string(forKey: "selected_model")
    }
}
