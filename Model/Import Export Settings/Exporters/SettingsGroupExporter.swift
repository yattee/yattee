import Foundation
import SwiftyJSON

class SettingsGroupExporter { // swiftlint:disable:this final_class
    var globalJSON: JSON {
        []
    }

    var platformJSON: JSON {
        []
    }

    var exportJSON: JSON {
        var json = globalJSON

        if !platformJSON.isEmpty {
            try? json.merge(with: platformJSON)
        }

        return json
    }

    func jsonFromString(_ string: String?) -> JSON? {
        if let data = string?.data(using: .utf8, allowLossyConversion: false),
           let json = try? JSON(data: data)
        {
            return json
        }

        return nil
    }
}
