//
//  DeepLinkManager.swift
//  airmeishi
//
//  Manages deep linking and URL handling for business card sharing
//

import Foundation
import Combine

/// Protocol for deep link handling operations
protocol DeepLinkManagerProtocol {
    func handleIncomingURL(_ url: URL) -> Bool
    func createShareURL(for card: BusinessCard, sharingLevel: SharingLevel) -> URL?
    func createAppClipURL(for card: BusinessCard, sharingLevel: SharingLevel) -> URL?
}

/// Manages deep linking and URL handling for the app
class DeepLinkManager: DeepLinkManagerProtocol, ObservableObject {
    static let shared = DeepLinkManager()
    
    @Published var lastReceivedCard: BusinessCard?
    @Published var pendingAction: DeepLinkAction?
    
    private let baseURL = "https://airmeishi.app"
    private let appClipURL = "https://airmeishi.app/clip"
    
    private let cardManager = CardManager.shared
    @MainActor private let contactRepository = ContactRepository.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotifications()
    }
    
    // MARK: - Public Methods
    
    /// Handle incoming URL from various sources
    func handleIncomingURL(_ url: URL) -> Bool {
        print("Handling incoming URL: \(url)")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            print("Invalid URL format")
            return false
        }
        
        // Determine the type of URL and handle accordingly
        if isBusinessCardURL(components) {
            return handleBusinessCardURL(components)
        } else if isShareLinkURL(components) {
            return handleShareLinkURL(components)
        } else if isAppClipURL(components) {
            return handleAppClipURL(components)
        }
        
        return false
    }
    
    /// Create a shareable URL for a business card
    func createShareURL(for card: BusinessCard, sharingLevel: SharingLevel) -> URL? {
        do {
            // Filter card based on sharing level
            let filteredCard = card.filteredCard(for: sharingLevel)
            
            // Encode card data
            let cardData = try JSONEncoder().encode(filteredCard)
            let base64Data = cardData.base64EncodedString()
            
            // Create URL components
            var components = URLComponents(string: baseURL)
            components?.path = "/share"
            components?.queryItems = [
                URLQueryItem(name: "card", value: base64Data),
                URLQueryItem(name: "level", value: sharingLevel.rawValue),
                URLQueryItem(name: "v", value: "1") // Version for future compatibility
            ]
            
            return components?.url
            
        } catch {
            print("Failed to create share URL: \(error)")
            return nil
        }
    }
    
    /// Create an App Clip URL for a business card
    func createAppClipURL(for card: BusinessCard, sharingLevel: SharingLevel) -> URL? {
        do {
            // Filter card based on sharing level
            let filteredCard = card.filteredCard(for: sharingLevel)
            
            // Encode card data
            let cardData = try JSONEncoder().encode(filteredCard)
            let base64Data = cardData.base64EncodedString()
            
            // Create App Clip URL components
            var components = URLComponents(string: appClipURL)
            components?.queryItems = [
                URLQueryItem(name: "card", value: base64Data),
                URLQueryItem(name: "level", value: sharingLevel.rawValue),
                URLQueryItem(name: "source", value: "qr") // Track source
            ]
            
            return components?.url
            
        } catch {
            print("Failed to create App Clip URL: \(error)")
            return nil
        }
    }
    
    /// Create a temporary share link with expiration
    func createTemporaryShareLink(for card: BusinessCard, sharingLevel: SharingLevel, expirationHours: Int = 24) -> URL? {
        // In a real implementation, this would create a server-side share link
        // For now, we'll create a local URL with expiration info
        
        do {
            let filteredCard = card.filteredCard(for: sharingLevel)
            let cardData = try JSONEncoder().encode(filteredCard)
            let base64Data = cardData.base64EncodedString()
            
            let expirationDate = Date().addingTimeInterval(TimeInterval(expirationHours * 3600))
            let expirationTimestamp = Int(expirationDate.timeIntervalSince1970)
            
            var components = URLComponents(string: baseURL)
            components?.path = "/temp"
            components?.queryItems = [
                URLQueryItem(name: "card", value: base64Data),
                URLQueryItem(name: "level", value: sharingLevel.rawValue),
                URLQueryItem(name: "expires", value: String(expirationTimestamp))
            ]
            
            return components?.url
            
        } catch {
            print("Failed to create temporary share link: \(error)")
            return nil
        }
    }
    
    /// Handle QR code scan result
    func handleQRCodeScan(_ qrContent: String) -> Bool {
        guard let url = URL(string: qrContent) else {
            // Try to handle as direct card data
            return handleDirectCardData(qrContent)
        }
        
        return handleIncomingURL(url)
    }
    
    /// Clear pending actions
    func clearPendingAction() {
        pendingAction = nil
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        // Listen for URL scheme notifications
        NotificationCenter.default.publisher(for: .NSExtensionHostDidBecomeActive)
            .sink { [weak self] _ in
                // Handle any pending actions when app becomes active
                self?.processPendingActions()
            }
            .store(in: &cancellables)
    }
    
    private func isBusinessCardURL(_ components: URLComponents) -> Bool {
        return components.path.contains("/card") || components.path.contains("/share")
    }
    
    private func isShareLinkURL(_ components: URLComponents) -> Bool {
        return components.path.contains("/share") || components.path.contains("/temp")
    }
    
    private func isAppClipURL(_ components: URLComponents) -> Bool {
        return components.path.contains("/clip") || components.host?.contains("clip") == true
    }
    
    private func handleBusinessCardURL(_ components: URLComponents) -> Bool {
        guard let queryItems = components.queryItems else { return false }
        
        // Extract card data
        var cardData: Data?
        var expirationTimestamp: Int?
        
        for item in queryItems {
            switch item.name {
            case "card", "data":
                if let value = item.value {
                    cardData = Data(base64Encoded: value)
                }
            case "expires":
                if let value = item.value {
                    expirationTimestamp = Int(value)
                }
            default:
                break
            }
        }
        
        // Check expiration
        if let expiration = expirationTimestamp {
            let expirationDate = Date(timeIntervalSince1970: TimeInterval(expiration))
            if Date() > expirationDate {
                pendingAction = .showError("This share link has expired")
                return false
            }
        }
        
        // Process card data
        guard let data = cardData else {
            pendingAction = .showError("Invalid card data")
            return false
        }
        
        return processReceivedCardData(data, source: .qrCode)
    }
    
    private func handleShareLinkURL(_ components: URLComponents) -> Bool {
        // Similar to business card URL but with additional share link logic
        return handleBusinessCardURL(components)
    }
    
    private func handleAppClipURL(_ components: URLComponents) -> Bool {
        // App Clip URLs are handled by the App Clip itself
        // The main app might receive these when the App Clip hands off to the main app
        return handleBusinessCardURL(components)
    }
    
    private func handleDirectCardData(_ qrContent: String) -> Bool {
        // Try to decode as direct JSON
        guard let data = qrContent.data(using: .utf8) else { return false }
        
        return processReceivedCardData(data, source: .qrCode)
    }
    
    private func processReceivedCardData(_ data: Data, source: ContactSource) -> Bool {
        do {
            let card = try JSONDecoder().decode(BusinessCard.self, from: data)
            
            // Save to contacts on main thread
            Task { @MainActor in
                let contact = Contact(
                    businessCard: card,
                    source: source,
                    verificationStatus: .unverified
                )
                
                let result = contactRepository.addContact(contact)
                
                switch result {
                case .success:
                    lastReceivedCard = card
                    pendingAction = .showReceivedCard(card)
                    
                case .failure(let error):
                    pendingAction = .showError("Failed to save card: \(error.localizedDescription)")
                }
            }
            
            // Return true immediately since we're processing async
            return true
            
        } catch {
            print("Failed to decode business card: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.pendingAction = .showError("Invalid business card format")
            }
            return false
        }
    }
    
    private func processPendingActions() {
        // Process any pending actions when the app becomes active
        // This could trigger UI updates or navigation
    }
}

// MARK: - Supporting Types

/// Types of deep link actions that can be triggered
enum DeepLinkAction {
    case showReceivedCard(BusinessCard)
    case showError(String)
    case navigateToSharing
    case navigateToContacts
}

/// URL scheme configuration
struct URLSchemeConfig {
    static let scheme = "airmeishi"
    static let host = "share"
    
    /// Create a custom URL scheme URL
    static func createSchemeURL(path: String, parameters: [String: String] = [:]) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        
        if !parameters.isEmpty {
            components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        return components.url
    }
}

/// Universal link configuration
struct UniversalLinkConfig {
    static let domain = "airmeishi.app"
    static let basePath = "/share"
    
    /// Validate if URL is a valid universal link
    static func isValidUniversalLink(_ url: URL) -> Bool {
        return url.host == domain && url.path.hasPrefix(basePath)
    }
}