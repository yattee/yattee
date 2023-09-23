import Foundation
import Siesta

final class Store<Data>: ResourceObserver, ObservableObject {
    @Published private var all: Data?

    var collection: Data { all ?? ([item].compactMap { $0 } as! Data) }
    var item: Data? { all }

    init(_ data: Data? = nil) {
        if data != nil {
            replace(data!)
        }
    }

    func resourceChanged(_ resource: Resource, event _: ResourceEvent) {
        if let items: Data = resource.typedContent() {
            replace(items)
        }
    }

    func replace(_ items: Data) {
        all = items
    }

    func clear() {
        all = nil
    }
}
