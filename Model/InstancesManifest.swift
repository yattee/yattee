import Defaults
import Foundation
import Siesta
import SwiftyJSON

final class InstancesManifest: Service, ObservableObject {
    static let builtinManifestUrl = "https://r.yattee.stream/manifest.json"
    static let shared = InstancesManifest()

    @Published var instances = [ManifestedInstance]()

    init() {
        super.init()

        configure {
            $0.pipeline[.parsing].add(SwiftyJSONTransformer, contentTypes: ["*/json"])
        }

        configureTransformer(
            manifestURL,
            requestMethods: [.get]
        ) { (content: Entity<JSON>
        ) -> [ManifestedInstance] in
            guard let instances = content.json.dictionaryValue["instances"] else { return [] }

            return instances.arrayValue.compactMap(self.extractInstance)
        }
    }

    func setPublicAccount(_ country: String?, accounts: AccountsModel, asCurrent: Bool = true) {
        guard let country = country else {
            accounts.publicAccount = nil
            if asCurrent {
                accounts.configureAccount()
            }
            return
        }

        instancesList.load().onSuccess { response in
            if let instances: [ManifestedInstance] = response.typedContent() {
                guard let instance = instances.filter { $0.country == country }.randomElement() else { return }
                let account = instance.anonymousAccount
                accounts.publicAccount = account
                if asCurrent {
                    accounts.setCurrent(account)
                }
            }
        }
    }

    func changePublicAccount(_ accounts: AccountsModel, settings: SettingsModel) {
        instancesList.load().onSuccess { response in
            if let instances: [ManifestedInstance] = response.typedContent() {
                let countryInstances = instances.filter { $0.country == Defaults[.countryOfPublicInstances] }
                let region = countryInstances.first?.region ?? "Europe"
                var regionInstances = instances.filter { $0.region == region }

                if let publicAccountUrl = accounts.publicAccount?.url {
                    regionInstances = regionInstances.filter { $0.url.absoluteString != publicAccountUrl }
                }

                guard let instance = regionInstances.randomElement() else {
                    settings.presentAlert(title: "Could not change location", message: "No locations available at the moment")
                    return
                }

                let account = instance.anonymousAccount
                accounts.publicAccount = account
                accounts.setCurrent(account)
            }
        }
    }

    func extractInstance(from json: JSON) -> ManifestedInstance? {
        guard let app = json["app"].string,
              let videosApp = VideosApp(rawValue: app.lowercased()),
              let region = json["region"].string,
              let country = json["country"].string,
              let flag = json["flag"].string,
              let url = json["url"].url else { return nil }

        return ManifestedInstance(
            app: videosApp,
            country: country,
            region: region,
            flag: flag,
            url: url
        )
    }

    var manifestURL: String {
        var url = Defaults[.instancesManifest]

        if url.isEmpty {
            url = Self.builtinManifestUrl
        }

        return url
    }

    var instancesList: Resource {
        resource(absoluteURL: manifestURL)
    }
}
