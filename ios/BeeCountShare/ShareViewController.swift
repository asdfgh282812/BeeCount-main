import UIKit
import UniformTypeIdentifiers

/// 系統分享選單的「蜜蜂記帳」擴充功能:把分享進來的圖片(通常是剛截的圖)
/// 交給主 App,由主 App 跑既有的圖片記帳流程(ImageBillingHelper)。
///
/// 圖片怎麼傳給主 App:直接編碼進喚起 App 的網址
/// `beecount://share-image#<base64url 編碼的 JPEG>`。
/// - 不用 App Group:本專案以免費個人開發者帳號簽署,免費帳號不支援 App Group,
///   擴充功能與主 App 沒有共用資料夾。
/// - 不用具名剪貼簿(`UIPasteboard(name:create:)`):文件說同 Team ID 共用,
///   但實測(iOS 26.5 模擬器,已用開發憑證簽上 Team ID)主 App 完全讀不到,不可靠。
/// - 不用一般剪貼簿:會蓋掉使用者剪貼簿內容,主 App 讀取時還會跳「允許貼上」提示。
/// 主 App 在 URL 進 Flutter 之前就先攔截、解碼成暫存檔(見 SceneDelegate.swift
/// 的 `interceptSharedImageURL`),Flutter 只會收到不帶資料的 `beecount://share-image`。
///
/// 擴充功能本身不跑 AI:AI 設定、帳本、分類都在 Flutter 端,這裡只負責
/// 「取圖 → 壓成 JPEG → 編進網址喚起主 App」。
class ShareViewController: UIViewController {
  /// 與 ImagePicker 相簿記帳的 maxWidth/maxHeight 一致,
  /// 讓 AI 視覺辨識拿到的圖片規格跟相簿記帳相同
  private static let maxDimension: CGFloat = 1920
  /// 依序嘗試的 JPEG 品質:第一個與相簿記帳的 imageQuality 一致,畫面很花的
  /// 截圖編出來太大時才往下降,讓網址長度維持在 [maxEncodedLength] 內
  private static let jpegQualities: [CGFloat] = [0.85, 0.7, 0.5, 0.35]
  /// 網址資料長度上限(base64 後的字元數)。iOS 沒有公開文件寫 openURL 的長度
  /// 上限;實測約 2.1M 字元(1.56MB 的高雜訊 JPEG)仍能正常喚起,上限取在驗證
  /// 過的範圍內。一般 App 截圖編完只有一兩百 KB,不會碰到。
  private static let maxEncodedLength = 2_000_000

  private let statusLabel = UILabel()
  private let spinner = UIActivityIndicatorView(style: .large)
  private var didStart = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    spinner.hidesWhenStopped = true
    spinner.startAnimating()

    statusLabel.text = Self.localized("sending")
    statusLabel.font = .preferredFont(forTextStyle: .body)
    statusLabel.textColor = .secondaryLabel
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0

    let stack = UIStackView(arrangedSubviews: [spinner, statusLabel])
    stack.axis = .vertical
    stack.spacing = 16
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // 必須等畫面出現後才喚起主 App:responder chain 在 viewDidLoad 時還接不到
    // UIApplication,openURL 會找不到對象。
    guard !didStart else { return }
    didStart = true
    Task { await handleSharedItems() }
  }

  @MainActor
  private func handleSharedItems() async {
    guard let image = await loadFirstImage(), let url = Self.shareURL(for: image) else {
      finish(withError: Self.localized("noImage"))
      return
    }

    openMainApp(url) { [weak self] opened in
      guard let self else { return }
      if opened {
        self.extensionContext?.completeRequest(returningItems: nil)
      } else {
        self.finish(withError: Self.localized("openFailed"))
      }
    }
  }

  // MARK: - 讀取分享內容

  /// 依序找第一個能轉成圖片的附件。分享來源可能給 URL(相簿/檔案)、
  /// UIImage(截圖後的標記編輯畫面)或 Data,三種都要接。
  private func loadFirstImage() async -> UIImage? {
    let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    let imageType = UTType.image.identifier

    for provider in providers where provider.hasItemConformingToTypeIdentifier(imageType) {
      guard let item = try? await provider.loadItem(forTypeIdentifier: imageType) else {
        continue
      }
      var image: UIImage?
      if let url = item as? URL, let data = try? Data(contentsOf: url) {
        image = UIImage(data: data)
      } else if let uiImage = item as? UIImage {
        image = uiImage
      } else if let data = item as? Data {
        image = UIImage(data: data)
      }
      if let image { return image }
    }
    return nil
  }

  /// 縮圖後依 [jpegQualities] 逐級壓縮,編成 base64url 放進網址 fragment
  private static func shareURL(for image: UIImage) -> URL? {
    let scaled = downscaled(image)
    for quality in jpegQualities {
      guard let jpeg = scaled.jpegData(compressionQuality: quality) else { continue }
      let encoded = jpeg.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
      if encoded.count <= maxEncodedLength {
        return URL(string: "beecount://share-image#\(encoded)")
      }
    }
    return nil
  }

  private static func downscaled(_ image: UIImage) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > maxDimension else { return image }
    let scale = maxDimension / longest
    let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
  }

  // MARK: - 喚起主 App

  /// 擴充功能不能用 `UIApplication.shared`(extension 內不可用),只能沿
  /// responder chain 找到 UIApplication 實例再呼叫 openURL。
  ///
  /// iOS 18 起舊的 `openURL:` 單參數 selector 已失效(呼叫不報錯但什麼都不做),
  /// 必須改用 `openURL:options:completionHandler:`。它在 extension 內被標為
  /// unavailable,Swift 不能直接呼叫,所以用 Objective-C runtime 取 IMP 呼叫。
  private func openMainApp(_ url: URL, completion: @escaping (Bool) -> Void) {
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication, application.responds(to: selector) {
        typealias OpenURLFunction = @convention(c) (
          AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
        ) -> Void
        let implementation = application.method(for: selector)
        let openURL = unsafeBitCast(implementation, to: OpenURLFunction.self)
        let handler: @convention(block) (Bool) -> Void = { success in
          DispatchQueue.main.async { completion(success) }
        }
        openURL(application, selector, url as NSURL, NSDictionary(), handler)
        return
      }
      responder = current.next
    }
    completion(false)
  }

  // MARK: - 結束

  private func finish(withError message: String) {
    statusLabel.text = message
    spinner.stopAnimating()
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      self?.extensionContext?.completeRequest(returningItems: nil)
    }
  }

  /// 擴充功能不共用 Flutter 的 arb 翻譯,這裡只有三句話,直接內建。
  private static func localized(_ key: String) -> String {
    let language = Locale.preferredLanguages.first ?? "en"
    let isTraditional = language.hasPrefix("zh-Hant") || language.hasPrefix("zh-TW")
      || language.hasPrefix("zh-HK") || language.hasPrefix("zh-MO")
    let isSimplified = language.hasPrefix("zh") && !isTraditional
    switch key {
    case "sending":
      return isTraditional ? "正在傳送到蜜蜂記帳…" : isSimplified ? "正在发送到蜜蜂记账…" : "Sending to BeeCount…"
    case "noImage":
      return isTraditional ? "沒有可記帳的圖片" : isSimplified ? "没有可记账的图片" : "No image to process"
    default:
      return isTraditional
        ? "無法自動打開蜜蜂記帳，請改用 App 內的相簿記帳"
        : isSimplified ? "无法自动打开蜜蜂记账，请改用 App 内的相册记账" : "Couldn't open BeeCount. Please use photo billing inside the app."
    }
  }
}
