import Foundation

extension Instance {
    static var fixture: Instance {
        Instance(name: "Home", url: "https://invidious.home.net", accounts: [
            .init(id: UUID(), name: "Evelyn", url: "https://invidious.home.net", sid: "abc"),
            .init(id: UUID(), name: "Jake", url: "https://invidious.home.net", sid: "xyz")
        ])
    }
}
