// AuthExtractionHandler.swift
// Handles authenticated content extraction using WKWebView with stored cookies

import Foundation
import WebKit
import Flutter

class AuthExtractionHandler: NSObject {
    private var webView: WKWebView?
    private var extractionCompletion: ((Result<[String: Any], Error>) -> Void)?
    private var currentProvider: String?

    // Safari on iPhone User Agent
    private let safariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "extractContent":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String,
                  let cookies = args["cookies"] as? String,
                  let provider = args["provider"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
                return
            }

            extractContent(url: url, cookies: cookies, provider: provider) { extractResult in
                switch extractResult {
                case .success(let content):
                    result(content)
                case .failure(let error):
                    result(["error": error.localizedDescription])
                }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func extractContent(url: String, cookies: String, provider: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.extractionCompletion = completion
            self.currentProvider = provider

            // Create WebView configuration
            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

            // Set cookies
            let cookieStore = config.websiteDataStore.httpCookieStore
            self.setCookies(cookies, for: url, in: cookieStore) {
                // Create WebView
                let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 812), configuration: config)
                webView.navigationDelegate = self
                webView.customUserAgent = self.safariUserAgent
                self.webView = webView

                // Load URL
                if let requestUrl = URL(string: url) {
                    var request = URLRequest(url: requestUrl)
                    request.setValue(self.safariUserAgent, forHTTPHeaderField: "User-Agent")
                    webView.load(request)

                    // Timeout after 30 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                        if self?.extractionCompletion != nil {
                            self?.extractionCompletion?(.failure(NSError(domain: "AuthExtraction", code: -1, userInfo: [NSLocalizedDescriptionKey: "Extraction timed out"])))
                            self?.cleanup()
                        }
                    }
                } else {
                    completion(.failure(NSError(domain: "AuthExtraction", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
                }
            }
        }
    }

    private func setCookies(_ cookieString: String, for urlString: String, in store: WKHTTPCookieStore, completion: @escaping () -> Void) {
        guard let url = URL(string: urlString) else {
            completion()
            return
        }

        let domain = url.host ?? ""
        let cookies = parseCookies(cookieString, domain: domain)

        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion()
        }
    }

    private func parseCookies(_ cookieString: String, domain: String) -> [HTTPCookie] {
        var cookies: [HTTPCookie] = []

        // Parse cookie string (format: "name=value; name2=value2")
        let pairs = cookieString.components(separatedBy: "; ")
        for pair in pairs {
            let parts = pair.components(separatedBy: "=")
            if parts.count >= 2 {
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)

                if let cookie = HTTPCookie(properties: [
                    .name: name,
                    .value: value,
                    .domain: domain.hasPrefix(".") ? domain : ".\(domain)",
                    .path: "/",
                    .secure: "TRUE",
                ]) {
                    cookies.append(cookie)
                }
            }
        }

        return cookies
    }

    private func extractPageContent() {
        guard let provider = currentProvider else { return }

        let script: String
        switch provider {
        case "linkedin":
            script = linkedInExtractionScript
        case "twitter":
            script = twitterExtractionScript
        default:
            script = genericExtractionScript
        }

        webView?.evaluateJavaScript(script) { [weak self] result, error in
            if let error = error {
                self?.extractionCompletion?(.failure(error))
            } else if let content = result as? [String: Any] {
                self?.extractionCompletion?(.success(content))
            } else {
                self?.extractionCompletion?(.failure(NSError(domain: "AuthExtraction", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract content"])))
            }
            self?.cleanup()
        }
    }

    private func cleanup() {
        webView?.stopLoading()
        webView = nil
        extractionCompletion = nil
        currentProvider = nil
    }

    // MARK: - Extraction Scripts

    private var linkedInExtractionScript: String {
        """
        (function() {
            var result = {
                title: null,
                content: null,
                imageUrl: null,
                author: null,
                error: null
            };

            try {
                // Try to get post content
                var postContent = document.querySelector('.feed-shared-update-v2__description');
                if (!postContent) {
                    postContent = document.querySelector('.update-components-text');
                }
                if (!postContent) {
                    postContent = document.querySelector('[data-test-id="main-feed-activity-content"]');
                }
                if (!postContent) {
                    postContent = document.querySelector('.break-words');
                }

                if (postContent) {
                    result.content = postContent.innerText.trim();
                }

                // Get author name
                var authorEl = document.querySelector('.update-components-actor__name');
                if (!authorEl) {
                    authorEl = document.querySelector('.feed-shared-actor__name');
                }
                if (authorEl) {
                    result.author = authorEl.innerText.trim();
                }

                // Get image
                var imageEl = document.querySelector('.feed-shared-image__image');
                if (!imageEl) {
                    imageEl = document.querySelector('.update-components-image__image');
                }
                if (!imageEl) {
                    imageEl = document.querySelector('img[data-delayed-url]');
                }
                if (imageEl) {
                    result.imageUrl = imageEl.src || imageEl.getAttribute('data-delayed-url');
                }

                // Generate title from author + first line
                if (result.author && result.content) {
                    var firstLine = result.content.split('\\n')[0].substring(0, 100);
                    result.title = result.author + ': ' + firstLine + (result.content.length > 100 ? '...' : '');
                }

                if (!result.content) {
                    result.error = 'Could not find post content';
                }
            } catch (e) {
                result.error = e.message;
            }

            return result;
        })();
        """
    }

    private var twitterExtractionScript: String {
        """
        (function() {
            var result = {
                title: null,
                content: null,
                imageUrl: null,
                author: null,
                error: null
            };

            try {
                // Get tweet text
                var tweetText = document.querySelector('[data-testid="tweetText"]');
                if (tweetText) {
                    result.content = tweetText.innerText.trim();
                }

                // Get author
                var authorEl = document.querySelector('[data-testid="User-Name"]');
                if (authorEl) {
                    result.author = authorEl.innerText.split('\\n')[0].trim();
                }

                // Get image
                var imageEl = document.querySelector('[data-testid="tweetPhoto"] img');
                if (imageEl) {
                    result.imageUrl = imageEl.src;
                }

                // Generate title
                if (result.author && result.content) {
                    var preview = result.content.substring(0, 100);
                    result.title = result.author + ': ' + preview + (result.content.length > 100 ? '...' : '');
                }

                if (!result.content) {
                    result.error = 'Could not find tweet content';
                }
            } catch (e) {
                result.error = e.message;
            }

            return result;
        })();
        """
    }

    private var genericExtractionScript: String {
        """
        (function() {
            var result = {
                title: document.title,
                content: null,
                imageUrl: null,
                author: null,
                error: null
            };

            try {
                // Try common article selectors
                var article = document.querySelector('article') ||
                              document.querySelector('[role="main"]') ||
                              document.querySelector('.post-content') ||
                              document.querySelector('.entry-content');

                if (article) {
                    result.content = article.innerText.trim();
                } else {
                    result.content = document.body.innerText.substring(0, 5000);
                }

                // Get og:image
                var ogImage = document.querySelector('meta[property="og:image"]');
                if (ogImage) {
                    result.imageUrl = ogImage.content;
                }
            } catch (e) {
                result.error = e.message;
            }

            return result;
        })();
        """
    }
}

// MARK: - WKNavigationDelegate

extension AuthExtractionHandler: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait a moment for dynamic content to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.extractPageContent()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        extractionCompletion?(.failure(error))
        cleanup()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        extractionCompletion?(.failure(error))
        cleanup()
    }
}
