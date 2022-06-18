import UIKit

final class MPVViewController: UIViewController {
    var client: MPVClient!

    init() {
        client = MPVClient()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.loadView()

        client.create(frame: view.frame)

        view.addSubview(client.glView)

        super.viewDidLoad()
    }
}
