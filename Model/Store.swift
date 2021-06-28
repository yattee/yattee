import Foundation
import Siesta

final class Store<Data>: ResourceObserver, ObservableObject {
    @Published private var all: Data?

    var collection: Data { all ?? ([] as! Data) }
    var item: Data? { all }

    func resourceChanged(_ resource: Resource, event _: ResourceEvent) {
        if let items: Data = resource.typedContent() {
            replace(items)
        }
    }

    func replace(_ items: Data) {
        all = items
    }
}
