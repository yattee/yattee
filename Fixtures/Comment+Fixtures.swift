import Foundation

extension Comment {
    static var fixture: Comment {
        Comment(
            id: UUID().uuidString,
            author: "The Author",
            authorAvatarURL: "https://pipedproxy-ams-2.kavin.rocks/Si7ZhtmpX84wj6MoJYLs8kwALw2Hm53wzbrPamoU-z3qvCKs2X3zPNYKMSJEvPDLUHzbvTfLcg=s176-c-k-c0x00ffffff-no-rw?host=yt3.ggpht.com",
            time: "2 months ago",
            pinned: true,
            hearted: true,
            likeCount: 30032,
            text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ut luctus feugiat mi, suscipit pharetra lectus dapibus vel. Vivamus orci erat, sagittis sit amet dui vel, feugiat cursus ante. Pellentesque eget orci tortor. Suspendisse pulvinar orci tortor, eu scelerisque neque consequat nec. Aliquam sit amet turpis et nunc placerat finibus eget sit amet justo. Nullam tincidunt ornare neque. Donec ornare, arcu at elementum pulvinar, urna elit pharetra diam, vel ultrices lacus diam at lorem. Sed vel maximus dolor. Morbi massa est, interdum quis justo sit amet, dapibus bibendum tellus. Integer at purus nec neque tincidunt convallis sit amet eu odio. Duis et ante vitae sem tincidunt facilisis sit amet ac mauris. Quisque varius non nisi vel placerat. Nulla orci metus, imperdiet ac accumsan sed, pellentesque eget nisl. Praesent a suscipit lacus, ut finibus orci. Nulla ut eros commodo, fermentum purus at, porta leo. In finibus luctus nulla, eget posuere eros mollis vel. ",
            repliesPage: "some url",
            channel: .init(id: "", name: "")
        )
    }
}
