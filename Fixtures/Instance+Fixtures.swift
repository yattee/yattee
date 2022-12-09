import Foundation

extension Instance {
    static var fixture: Instance {
        Instance(app: .invidious, name: "Home", apiURLString: "https://invidious.home.net")
    }
}
