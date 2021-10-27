import Foundation

extension Instance {
    static var fixture: Instance {
        Instance(app: .invidious, name: "Home", apiURL: "https://invidious.home.net")
    }
}
