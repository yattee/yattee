import Siesta
import SwiftyJSON

extension TypedContentAccessors {
    var json: JSON { typedContent(ifNone: JSON.null) }
}
