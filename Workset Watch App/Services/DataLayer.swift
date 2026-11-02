import Foundation

/// The watch's one way into the data layer: the `workset` edge function (data-layer
/// `supabase/functions/workset`). The app holds no Supabase key. It sends its own device
/// token, which the function checks before acting with the service role, so nothing in
/// this public source authorises a write.
///
/// The token is the build setting `WORKSET_DEVICE_TOKEN`, from the gitignored
/// `Config/Secrets.xcconfig`, carried into Info.plist as `WorksetDeviceToken`.
enum DataLayer {

    private static let base = "https://felyggqjjhltwokdfhop.supabase.co/functions/v1/workset"
    private static let token = Bundle.main.object(forInfoDictionaryKey: "WorksetDeviceToken") as? String ?? ""

    /// `route` is `report`, `watcher` or `capture`, with any query string.
    static func request(_ route: String, _ method: String, contentType: String = "application/json",
                        body: Data? = nil) -> URLRequest? {
        guard !token.isEmpty, let url = URL(string: "\(base)/\(route)") else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(token, forHTTPHeaderField: "X-Device-Token")
        r.setValue(contentType, forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        return r
    }

    static func request(_ route: String, _ method: String, json: [String: Any]) -> URLRequest? {
        request(route, method, body: try? JSONSerialization.data(withJSONObject: json))
    }
}
