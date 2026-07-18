import Foundation

/// 过滤/匹配规则。决定某条推送是否转发给某个目标。
public struct ForwardRule: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    /// 当匹配此规则时，转发到这些目标 ID。空表示转发给所有启用目标。
    public var targetIDs: [UUID]
    /// 标题包含的关键字（任一命中即匹配，留空表示不限）。
    public var titleKeywords: [String]
    /// 正文包含的关键字。
    public var bodyKeywords: [String]
    /// 仅匹配来自这些 bundleID 的 App 推送（留空表示不限）。
    public var sourceBundleIDs: [String]
    /// 大小写敏感。
    public var caseSensitive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        targetIDs: [UUID] = [],
        titleKeywords: [String] = [],
        bodyKeywords: [String] = [],
        sourceBundleIDs: [String] = [],
        caseSensitive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.targetIDs = targetIDs
        self.titleKeywords = titleKeywords
        self.bodyKeywords = bodyKeywords
        self.sourceBundleIDs = sourceBundleIDs
        self.caseSensitive = caseSensitive
    }

    /// 判断一条推送是否命中此规则。
    public func matches(title: String, body: String, sourceBundleID: String?) -> Bool {
        if !sourceBundleIDs.isEmpty {
            guard let bid = sourceBundleID, sourceBundleIDs.contains(bid) else { return false }
        }
        if !titleKeywords.isEmpty, !containsAny(text: title, keywords: titleKeywords) { return false }
        if !bodyKeywords.isEmpty, !containsAny(text: body, keywords: bodyKeywords) { return false }
        return true
    }

    private func containsAny(text: String, keywords: [String]) -> Bool {
        let haystack = caseSensitive ? text : text.lowercased()
        for kw in keywords {
            let needle = caseSensitive ? kw : kw.lowercased()
            if haystack.contains(needle) { return true }
        }
        return false
    }
}

/// 推送事件载荷。转发给目标时使用这个统一结构。
public struct PushEventPayload: Codable {
    public var title: String
    public var body: String
    public var subtitle: String
    public var badge: Int?
    public var sound: String?
    public var userInfo: [String: String]
    public var receivedAt: Date
    public var sourceBundleID: String?
    /// 推送附带的图片/视频/文件。详见 PushAttachment。
    public var attachments: [PushAttachment]

    public init(
        title: String,
        body: String,
        subtitle: String,
        badge: Int? = nil,
        sound: String? = nil,
        userInfo: [String: String] = [:],
        receivedAt: Date = Date(),
        sourceBundleID: String? = nil,
        attachments: [PushAttachment] = []
    ) {
        self.title = title
        self.body = body
        self.subtitle = subtitle
        self.badge = badge
        self.sound = sound
        self.userInfo = userInfo
        self.receivedAt = receivedAt
        self.sourceBundleID = sourceBundleID
        self.attachments = attachments
    }

    /// 是否有附件。
    public var hasAttachments: Bool { !attachments.isEmpty }
}
