import Foundation
import SwiftSignalKit
import Postbox

private let messageNotificationKeyExpr = try? NSRegularExpression(pattern: "m([-\\d]+):([-\\d]+):([-\\d]+)_?", options: [])

enum NotificationManagedNotificationRequestId: Hashable {
    case messageId(MessageId)
    case globallyUniqueId(Int64, PeerId?)
    
    init?(string: String) {
        if string.hasPrefix("m") {
            let matches = messageNotificationKeyExpr!.matches(in: string, options: [], range: NSRange(location: 0, length: string.count))
            if let match = matches.first {
                let nsString = string as NSString
                let peerIdString = nsString.substring(with: match.range(at: 1))
                let namespaceString = nsString.substring(with: match.range(at: 2))
                let idString = nsString.substring(with: match.range(at: 3))
                
                guard let peerId = Int64(peerIdString) else {
                    return nil
                }
                guard let namespace = Int32(namespaceString) else {
                    return nil
                }
                guard let id = Int32(idString) else {
                    return nil
                }
                self = .messageId(MessageId(peerId: PeerId(peerId), namespace: namespace, id: id))
                return
            }
        }
        return nil
    }
}

final class ClearNotificationIdsCompletion {
    let f: ([(String, NotificationManagedNotificationRequestId)]) -> Void
    
    init(f: @escaping ([(String, NotificationManagedNotificationRequestId)]) -> Void) {
        self.f = f
    }
}

final class ClearNotificationsManager {
    private let getNotificationIds: (ClearNotificationIdsCompletion) -> Void
    private let getPendingNotificationIds: (ClearNotificationIdsCompletion) -> Void
    private let removeNotificationIds: ([String]) -> Void
    private let removePendingNotificationIds: ([String]) -> Void
    
    private var ids: [PeerId: MessageId] = [:]
    
    private var timer: SwiftSignalKit.Timer?
    
    init(getNotificationIds: @escaping (ClearNotificationIdsCompletion) -> Void, removeNotificationIds: @escaping ([String]) -> Void, getPendingNotificationIds: @escaping (ClearNotificationIdsCompletion) -> Void, removePendingNotificationIds: @escaping ([String]) -> Void) {
        self.getNotificationIds = getNotificationIds
        self.removeNotificationIds = removeNotificationIds
        self.getPendingNotificationIds = getPendingNotificationIds
        self.removePendingNotificationIds = removePendingNotificationIds
    }
    
    deinit {
        self.timer?.invalidate()
    }
    
    func append(_ id: MessageId) {
        if let current = self.ids[id.peerId] {
            if current < id {
                self.ids[id.peerId] = id
            }
        } else {
            self.ids[id.peerId] = id
        }
        self.timer?.invalidate()
        let timer = SwiftSignalKit.Timer(timeout: 2.0, repeat: false, completion: { [weak self] in
            self?.commitNow()
        }, queue: Queue.mainQueue())
        self.timer = timer
        timer.start()
    }
    
    func commitNow() {
        self.timer?.invalidate()
        self.timer = nil
        
        let ids = self.ids
        self.ids.removeAll()
        
        self.getNotificationIds(ClearNotificationIdsCompletion { [weak self] result in
            Queue.mainQueue().async {
                var removeKeys: [String] = []
                for (identifier, requestId) in result {
                    if case let .messageId(messageId) = requestId {
                        if let maxId = ids[messageId.peerId], messageId <= maxId {
                            removeKeys.append(identifier)
                        }
                    }
                }
                
                if let strongSelf = self, !removeKeys.isEmpty {
                    strongSelf.removeNotificationIds(removeKeys)
                }
            }
        })
        
        self.getPendingNotificationIds(ClearNotificationIdsCompletion { [weak self] result in
            Queue.mainQueue().async {
                var removeKeys: [String] = []
                for (identifier, requestId) in result {
                    if case let .messageId(messageId) = requestId {
                        if let maxId = ids[messageId.peerId], messageId <= maxId {
                            removeKeys.append(identifier)
                        }
                    }
                }
                
                if let strongSelf = self, !removeKeys.isEmpty {
                    strongSelf.removePendingNotificationIds(removeKeys)
                }
            }
        })
    }
}
