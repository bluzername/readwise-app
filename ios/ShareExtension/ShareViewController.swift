// ios/ShareExtension/ShareViewController.swift
// iOS Share Extension for saving URLs to ReadZero - instant save with animation

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground
        view.layer.cornerRadius = 16
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.15
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let checkmarkView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)
        let image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor(red: 99/255, green: 102/255, blue: 241/255, alpha: 1)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.alpha = 0
        imageView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        return imageView
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Saved to ReadZero"
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alpha = 0
        return label
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        extractAndSaveUrl()
    }

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)

        view.addSubview(containerView)
        containerView.addSubview(checkmarkView)
        containerView.addSubview(statusLabel)
        containerView.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 200),
            containerView.heightAnchor.constraint(equalToConstant: 140),

            checkmarkView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            checkmarkView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 28),
            checkmarkView.widthAnchor.constraint(equalToConstant: 50),
            checkmarkView.heightAnchor.constraint(equalToConstant: 50),

            statusLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: checkmarkView.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            loadingIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
        ])

        // Start with loading state
        loadingIndicator.startAnimating()

        // Animate container in
        containerView.alpha = 0
        containerView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)

        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            self.containerView.alpha = 1
            self.containerView.transform = .identity
        }
    }

    private func extractAndSaveUrl() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            showError()
            return
        }

        for attachment in attachments {
            // Try URL type first
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] data, error in
                    DispatchQueue.main.async {
                        if let url = data as? URL {
                            self?.saveAndDismiss(url: url.absoluteString)
                        } else {
                            self?.showError()
                        }
                    }
                }
                return
            }

            // Try plain text (might contain URL)
            if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] data, error in
                    DispatchQueue.main.async {
                        if let text = data as? String, let url = self?.extractUrlFromText(text) {
                            self?.saveAndDismiss(url: url)
                        } else {
                            self?.showError()
                        }
                    }
                }
                return
            }
        }

        showError()
    }

    private func extractUrlFromText(_ text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        if let match = matches?.first, let range = Range(match.range, in: text) {
            return String(text[range])
        }
        return nil
    }

    private func saveAndDismiss(url: String) {
        // Save URL to shared UserDefaults (App Group)
        let saved = saveUrlToAppGroup(url)

        if !saved {
            showError()
            return
        }

        // Show success animation
        loadingIndicator.stopAnimating()

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8) {
            self.checkmarkView.alpha = 1
            self.checkmarkView.transform = .identity
            self.statusLabel.alpha = 1
        } completion: { _ in
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Auto-dismiss after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.dismiss()
            }
        }
    }

    private func showError() {
        loadingIndicator.stopAnimating()

        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)
        checkmarkView.image = UIImage(systemName: "xmark.circle.fill", withConfiguration: config)
        checkmarkView.tintColor = .systemRed
        statusLabel.text = "Couldn't save"

        UIView.animate(withDuration: 0.3) {
            self.checkmarkView.alpha = 1
            self.checkmarkView.transform = .identity
            self.statusLabel.alpha = 1
        } completion: { _ in
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.dismiss()
            }
        }
    }

    private func saveUrlToAppGroup(_ url: String) -> Bool {
        guard let userDefaults = UserDefaults(suiteName: "group.live.bluzername.readzero.app") else {
            print("[ReadZero ShareExt] ERROR: Failed to access App Group - check entitlements configuration")
            return false
        }

        var pendingUrls = userDefaults.stringArray(forKey: "pendingUrls") ?? []
        pendingUrls.append(url)
        userDefaults.set(pendingUrls, forKey: "pendingUrls")

        // Verify the save succeeded
        let verifyUrls = userDefaults.stringArray(forKey: "pendingUrls") ?? []
        let success = verifyUrls.contains(url)

        if success {
            print("[ReadZero ShareExt] Saved URL to App Group: \(url) (queue size: \(verifyUrls.count))")
        } else {
            print("[ReadZero ShareExt] ERROR: Failed to save URL to App Group")
        }

        return success
    }

    private func dismiss() {
        UIView.animate(withDuration: 0.2) {
            self.view.alpha = 0
            self.containerView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
