import UIKit
import SwiftUI
import MobileCoreServices
import UniformTypeIdentifiers

class ActionViewController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var textField: UITextField!
    var latitudeDouble: Double = 0.0
    var longitudeDouble: Double = 0.0
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    // Helper method to extract query parameters from URL
    private func getParameter(from url: URL, key: String) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            return nil
        }
        
        return queryItems.first { $0.name == key }?.value
    }

    @IBAction func saveButtonPressed(_ sender: UIButton) {
        guard let sharedItems = extensionContext?.inputItems as? [NSExtensionItem],
              let firstItem = sharedItems.first,
              let provider = firstItem.attachments?.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
              }) else {
            done()
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let url = item as? URL,
                      let location = self.getParameter(from: url, key: "ll")?
                        .split(separator: ",", maxSplits: 1)
                        .map(String.init),
                      location.count == 2,
                      let latitude = Double(location[0].trimmingCharacters(in: .whitespaces)),
                      let longitude = Double(location[1].trimmingCharacters(in: .whitespaces)) else {
                    self.done()
                    return
                }

                let bookmarkName = self.textField.text ?? ""
                _ = self.BookMarkSave(lat: latitude, long: longitude, name: bookmarkName)
                self.done()
            }
        }
    }

    @IBAction func done() {
        guard let extensionContext else { return }
        extensionContext.completeRequest(returningItems: extensionContext.inputItems, completionHandler: nil)
    }
    
    let sharedUserDefaultsSuiteName = "group.live.cclerc.geraniumBookmarks"

    func BookMarkSave(lat: Double, long: Double, name: String) -> Bool {
        var bookmarks = BookMarkRetrieve()
        guard lat.isFinite, long.isFinite,
              (-90.0...90.0).contains(lat),
              (-180.0...180.0).contains(long) else {
            return false
        }
        guard !bookmarks.contains(where: { existing in
            guard let existingLat = existing["lat"] as? Double,
                  let existingLong = existing["long"] as? Double else { return false }
            return abs(existingLat - lat) < 0.00001 && abs(existingLong - long) < 0.00001
        }) else {
            return false
        }

        let bookmark: [String: Any] = ["name": name, "lat": lat, "long": long]
        bookmarks.append(bookmark)
        let sharedUserDefaults = UserDefaults(suiteName: sharedUserDefaultsSuiteName)
        sharedUserDefaults?.set(bookmarks, forKey: "bookmarks")
        successVibrate()
        return true
    }

    func BookMarkRetrieve() -> [[String: Any]] {
        let sharedUserDefaults = UserDefaults(suiteName: sharedUserDefaultsSuiteName)
        if let bookmarks = sharedUserDefaults?.array(forKey: "bookmarks") as? [[String: Any]] {
            return bookmarks
        } else {
            return []
        }
    }
}

// shortened vibrate object
func successVibrate() {
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.success)
}
