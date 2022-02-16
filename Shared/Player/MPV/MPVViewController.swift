import UIKit

final class MPVViewController: UIViewController {
    var client: MPVClient!
    var glView: MPVOGLView!

    init() {
        client = MPVClient()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.loadView()

        glView = client.create(frame: view.frame)

        view.addSubview(glView)

        super.viewDidLoad()
    }
}
