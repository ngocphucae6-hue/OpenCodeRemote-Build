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

    /// Providers đã lọc theo hideUnusedModels
    var filteredProviders: [OCProvider] {
        if !hideUnusedModels {
            return providers
        }
        guard let selectedProvider = selectedProvider,
              let selectedModel = selectedModel else {
            return providers
        }
        // Chỉ giữ provider đã chọn và chỉ giữ model đã chọn trong provider đó
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
