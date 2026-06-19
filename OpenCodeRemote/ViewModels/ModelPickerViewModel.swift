import Foundation

@MainActor
class ModelPickerViewModel: ObservableObject {
    @Published var providers: [OCProvider] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedProvider: String?
    @Published var selectedModel: String?
    @Published var hideUnusedModels: Bool = UserDefaults.standard.object(forKey: "hide_unused_models") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hideUnusedModels, forKey: "hide_unused_models") }
    }
    @Published var favoriteModelIDs: Set<String> = []

    private let api: OpenCodeAPI

    init() {
        let config = ServerConfig.load()
        self.api = OpenCodeAPI(config: config)
        loadSavedSelection()
        loadFavorites()
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

    func toggleFavorite(modelID: String) {
        if favoriteModelIDs.contains(modelID) {
            favoriteModelIDs.remove(modelID)
        } else {
            favoriteModelIDs.insert(modelID)
        }
        saveFavorites()
    }

    func isSelected(provider: String, model: String) -> Bool {
        selectedProvider == provider && selectedModel == model
    }

    var filteredProviders: [OCProvider] {
        if !hideUnusedModels {
            return providers
        }
        
        // Filter: Only keep providers that have at least one favorite model
        let filtered = providers.compactMap { provider -> OCProvider? in
            let favModels = provider.models.filter { favoriteModelIDs.contains($0.id) }
            if favModels.isEmpty { return nil }
            return OCProvider(id: provider.id, name: provider.name, models: favModels)
        }
        
        return filtered.isEmpty ? providers : filtered
    }

    private func loadSavedSelection() {
        selectedProvider = UserDefaults.standard.string(forKey: "selected_provider")
        selectedModel = UserDefaults.standard.string(forKey: "selected_model")
    }

    private func loadFavorites() {
        if let saved = UserDefaults.standard.stringArray(forKey: "favorite_model_ids") {
            favoriteModelIDs = Set(saved)
        }
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteModelIDs), forKey: "favorite_model_ids")
    }
}
