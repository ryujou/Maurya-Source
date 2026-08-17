import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute]

    init(path: [AppRoute] = []) {
        self.path = path
    }

    func showDevice(id: String) {
        path.append(.deviceDetail(id: id))
    }

    func showShareImport(token: String? = nil) {
        path.append(.shareImport(token: token))
    }

    func show(_ route: AppRoute) {
        path.append(route)
    }

    func showRoot() {
        path.removeAll()
    }

    func select(_ route: AppRoute) {
        path = [route]
    }

    @discardableResult
    func handle(url: URL) -> Bool {
        guard let route = DeepLinkParser.route(from: url) else {
            return false
        }

        path = [route]
        return true
    }
}
