import Foundation
import SwiftUI

struct Help: View {
    static let wikiURL = URL(string: "https://github.com/yattee/yattee/wiki")!
    static let matrixURL = URL(string: "https://tinyurl.com/matrix-yattee")!
    static let discordURL = URL(string: "https://yattee.stream/discord")!
    static let issuesURL = URL(string: "https://github.com/yattee/yattee/issues")!
    static let milestonesURL = URL(string: "https://github.com/yattee/yattee/milestones")!
    static let donationsURL = URL(string: "https://github.com/yattee/yattee/wiki/Donations")!
    static let contributingURL = URL(string: "https://github.com/yattee/yattee/wiki/Contributing")!
    static let translationsURL = URL(string: "https://hosted.weblate.org/engage/yattee/")!

    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Section {
                        header("I am lost".localized())

                        Text("You can find information about using Yattee in the Wiki pages.")
                            .padding(.bottom, 8)

                        helpItemLink("Wiki".localized(), url: Self.wikiURL, systemImage: "questionmark.circle")
                            .padding(.bottom, 8)
                    }

                    Spacer()

                    Section {
                        header("I want to ask a question".localized())

                        Text("Discussions take place in Discord and Matrix. It's a good spot for general questions.")
                            .padding(.bottom, 8)

                        helpItemLink("Discord Server".localized(), url: Self.discordURL, systemImage: "message")
                            .padding(.bottom, 8)
                        helpItemLink("Matrix Channel".localized(), url: Self.matrixURL, systemImage: "message")
                            .padding(.bottom, 8)
                    }

                    Spacer()

                    Section {
                        header("I found a bug /".localized())
                        header("I have a feature request".localized())

                        Text("Bugs and great feature ideas can be sent to the GitHub issues tracker. ")
                        Text("If you are reporting a bug, include all relevant details (especially: app\u{00a0}version, used device and system version, steps to reproduce).")
                        Text("If you are interested what's coming in future updates, you can track project Milestones.")
                            .padding(.bottom, 8)

                        VStack(alignment: .leading, spacing: 8) {
                            helpItemLink("Issues Tracker".localized(), url: Self.issuesURL, systemImage: "ladybug")
                            helpItemLink("Milestones".localized(), url: Self.milestonesURL, systemImage: "list.star")
                        }
                        .padding(.bottom, 8)
                    }

                    Spacer()

                    Section {
                        header("I like this app!".localized())

                        Text("That's nice to hear. It is fun to deliver apps other people want to use. You can consider donating to the project or help by contributing to new features development.")
                        Text("If you want this app to be available in your language, join translation project.")
                            .padding(.bottom, 8)

                        VStack(alignment: .leading, spacing: 8) {
                            helpItemLink("Donations".localized(), url: Self.donationsURL, systemImage: "dollarsign.circle")
                            helpItemLink("Contributing".localized(), url: Self.contributingURL, systemImage: "hammer")
                            helpItemLink("Translations".localized(), url: Self.translationsURL, systemImage: "flag")
                        }
                        .padding(.bottom, 8)
                    }
                }
                #if os(iOS)
                .padding(.horizontal)
                #endif
            }
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #else
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        .navigationTitle("Help")
    }

    func header(_ text: String) -> some View {
        Text(text)
            .fontWeight(.bold)
            .font(.title3)
            .padding(.bottom, 6)
    }

    func helpItemLink(_ label: String, url: URL, systemImage: String) -> some View {
        Group {
            #if os(tvOS)
                VStack {
                    Button {} label: {
                        HStack(spacing: 8) {
                            Image(systemName: systemImage)
                            Text(label)
                        }
                        .font(.system(size: 25).bold())
                    }

                    Text(url.absoluteString)
                }
                .frame(maxWidth: .infinity)
            #else
                Button {
                    openURL(url)
                } label: {
                    Label(label, systemImage: systemImage)
                }
            #endif
        }
    }
}

struct Help_Previews: PreviewProvider {
    static var previews: some View {
        Help()
    }
}
