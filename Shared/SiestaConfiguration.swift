import Siesta
import SwiftyJSON

let SwiftyJSONTransformer =
    ResponseContentTransformer(transformErrors: true) { JSON($0.content as AnyObject) }
