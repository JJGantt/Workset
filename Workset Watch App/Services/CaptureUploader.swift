import Foundation

/// Ships every recognised set to Supabase as a raw CSV.
///
/// Without this a wrong count in the gym teaches nothing — the number is all you
/// get, and the recording that produced it is gone. With it, a miscount becomes a
/// file that can be replayed against the algorithm the same day.
///
/// Objects land at `workset/sensor_capture/<session>/motion.csv`, and the column order
/// matches the reference recordings exactly, so the analysis tooling reads these with
/// no modification.
enum CaptureUploader {

    private static let base = "https://felyggqjjhltwokdfhop.supabase.co"
    private static let bucket = "workset-captures"
    /// Publishable key: designed to be shipped. Storage RLS lets it CREATE objects
    /// in this bucket and nothing else — it cannot read back what was recorded, or
    /// overwrite it, or delete it. Reading is service-role only.
    static let publishableKey = "sb_publishable_H2P7Gl1d_bGngnilIlBDsg_Bvkp_Uae"

    /// Sets that could not be uploaded yet. The gym is exactly where the watch has
    /// no useful connection, so a failed upload queues on disk and is retried rather
    /// than dropped — losing the recording defeats the point of making it.
    private static var queueDir: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("pending", isDirectory: true)
    }

    /// Persist first, then try to send. Writing to disk before attempting the network
    /// means a set survives the app being killed mid-upload.
    static func upload(_ samples: [MotionSample], verdict: CountedSet?,
                       exercise: String? = nil, weightLbs: Double? = nil) {
        guard samples.count > 8 else { return }
        let session = "unlabeled_0_\(Int(Date().timeIntervalSince1970))"
        let body = Data(CaptureFormat.csv(samples, session: session, verdict: verdict,
                                          exercise: exercise, weightLbs: weightLbs).utf8)
        if let dir = queueDir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? body.write(to: dir.appendingPathComponent("\(session).csv"))
        }
        flush()
    }

    /// Try to send everything queued. Files are removed only on a confirmed 2xx.
    static func flush() {
        guard let dir = queueDir,
              let files = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                      includingPropertiesForKeys: nil)
        else { return }
        for f in files where f.pathExtension == "csv" {
            guard let body = try? Data(contentsOf: f) else { continue }
            let session = f.deletingPathExtension().lastPathComponent
            let path = "\(bucket)/workset/sensor_capture/\(session)/motion.csv"
            guard let url = URL(string: "\(base)/storage/v1/object/\(path)") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(publishableKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
            req.setValue("text/csv", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            URLSession.shared.dataTask(with: req) { _, resp, _ in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                // 409 means this session is already stored — also a reason to stop
                // retrying, not a failure.
                if (200..<300).contains(code) || code == 409 {
                    try? FileManager.default.removeItem(at: f)
                }
            }.resume()
        }
    }
}
