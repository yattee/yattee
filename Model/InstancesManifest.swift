import Defaults
import Foundation
import Siesta
import SwiftyJSON

final class InstancesManifest: Service, ObservableObject {
    static let shared = InstancesManifest()

    @Published var instances = [ManifestedInstance]()

    init() {
        super.init()

        configure()
    }

    func configure() {
        invalidateConfiguration()

        configure {
            $0.pipeline[.parsing].add(SwiftyJSONTransformer, contentTypes: ["*/json"])
        }

        if let manifestURL {
            configureTransformer(
                manifestURL,
                requestMethods: [.get]
            ) { (content: Entity<JSON>
            ) -> [ManifestedInstance] in
                guard let instances = content.json.dictionaryValue["instances"] else { return [] }

                return instances.arrayValue.compactMap(self.extractInstance)
            }
        }
    }

    func setPublicAccount(_ country: String?, asCurrent: Bool = true) {
        guard let country else {
            AccountsModel.shared.publicAccount = nil
            if asCurrent {
                AccountsModel.shared.configureAccount()
            }
            return
        }

        instancesList?.load().onSuccess { response in
            if let instances: [ManifestedInstance] = response.typedContent() {
                let countryInstances = instances.filter { $0.country == country }
                guard let instance = countryInstances.randomElement() else { return }
                let account = instance.anonymousAccount
                AccountsModel.shared.publicAccount = account
                if asCurrent {
                    AccountsModel.shared.setCurrent(account)
                }
            }
        }
    }

    func changePublicAccount() {
        instancesList?.load().onSuccess { response in
            if let instances: [ManifestedInstance] = response.typedContent() {
                var countryInstances = instances.filter { $0.country == Defaults[.countryOfPublicInstances] }
                let region = countryInstances.first?.region ?? "Europe"
                var regionInstances = instances.filter { $0.region == region }

                if let publicAccountUrl = AccountsModel.shared.publicAccount?.url {
                    countryInstances = countryInstances.filter { $0.url != publicAccountUrl }
                    regionInstances = regionInstances.filter { $0.url != publicAccountUrl }
                }

                var instance: ManifestedInstance?

                if AccountsModel.shared.current?.isPublic ?? false {
                    instance = regionInstances.randomElement()
                } else {
                    instance = countryInstances.randomElement() ?? regionInstances.randomElement()
                }

                guard let instance else {
                    SettingsModel.shared.presentAlert(title: "Could not change location", message: "No locations available at the moment")
                    return
                }

                let account = instance.anonymousAccount
                AccountsModel.shared.publicAccount = account
                AccountsModel.shared.setCurrent(account)
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

    var manifestURL: String? {
        Defaults[.instancesManifest].isEmpty ? nil : Defaults[.instancesManifest]
    }

    var instancesList: Resource? {
        guard let manifestURL else { return nil }
        return resource(absoluteURL: manifestURL)
    }
}
