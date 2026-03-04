import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import MapKit
import Contacts
import UIKit
internal import Combine

enum EventVisibility: String, CaseIterable, Codable, Identifiable {
    case inviteOnly = "Invite-only"
    case friends = "Friends"
    case `public` = "Public"

    static var allCases: [EventVisibility] { [.inviteOnly, .public] }

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inviteOnly: return "lock.fill"
        case .friends: return "person.2.fill"
        case .public: return "globe"
        }
    }
}

enum InviteResponseStatus: String, CaseIterable, Codable {
    case pending
    case accepted
    case maybe
    case declined
    case removed

    var title: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .maybe: return "Maybe"
        case .declined: return "Declined"
        case .removed: return "Removed"
        }
    }
}

enum AddInviteHandleResult {
    case added
    case alreadyInvited
    case invalidHandle
    case failed
}

enum PublicJoinMode: String, CaseIterable, Codable, Identifiable {
    case autoApprove = "Auto-approve joins"
    case requestApproval = "Require approval"

    var id: String { rawValue }
}

struct NetworkEvent: Identifiable, Codable, Hashable {
    let id: String
    var organizerId: String
    var organizerName: String
    var title: String
    var details: String
    var theme: String
    var startAt: Date
    var locationName: String
    var headerImageURL: String?
    var visibility: EventVisibility
    var publicJoinModeRaw: String
    var invitedUserHandles: [String]
    var removedInviteHandles: [String]
    var inviteContactNames: [String: String]
    var inviteContactPhones: [String: String]
    var inviteStatuses: [String: String]
    var attendingUserIds: [String]
    var attendingNames: [String]
    var joinRequestUserIds: [String]
    var joinRequestNames: [String]
    var removedForUserIds: [String]
    var allowInviteesToAddBringItems: Bool
    var bringItems: [EventBringItem]
    var isCanceled: Bool
    var canceledAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var attendeeCount: Int { attendingUserIds.count }
    var publicJoinMode: PublicJoinMode {
        PublicJoinMode(rawValue: publicJoinModeRaw) ?? .requestApproval
    }
}

struct EventBringItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var claimedByUserId: String?
    var claimedByName: String?
    var photoURL: String? = nil

    var isClaimed: Bool {
        let value = claimedByUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !value.isEmpty
    }
}

struct NetworkEventMessage: Identifiable, Hashable {
    let id: String
    let authorName: String
    let authorUserId: String?
    let text: String
    let createdAt: Date
}

struct EventParticipant: Identifiable, Hashable {
    enum Role: String {
        case organizer
        case attendee
        case invitee
    }

    let id: String
    var displayName: String
    var role: Role
    var userId: String?
    var userHandle: String?
    var photoURL: String?

    var isGiftMinderUser: Bool {
        let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !uid.isEmpty
    }
}

struct NetworkUserProfile: Identifiable, Hashable {
    let id: String
    var displayName: String
    var userHandle: String?
    var photoURL: String?
    var subtitle: String?
    var bio: String?
    var interests: [String]
    var profileFontStyle: String?
    var profileAnimationsEnabled: Bool?
}

@MainActor
final class EventsNetworkService: ObservableObject {
    static let shared = EventsNetworkService()

    @Published var events: [NetworkEvent] = []
    @Published var messagesByEventId: [String: [NetworkEventMessage]] = [:]

    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var isLoaded = false
    private var eventsListener: ListenerRegistration?

    private init() {}

    deinit {
        eventsListener?.remove()
        eventsListener = nil
    }

    func loadEvents() {
        guard !isLoaded else { return }
        isLoaded = true
        startEventsListenerIfNeeded()
    }

    func refreshEvents() {
        startEventsListenerIfNeeded()
    }

    private func startEventsListenerIfNeeded() {
        guard eventsListener == nil else { return }

        eventsListener = db.collection("networkEvents")
            .order(by: "startAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let snapshot {
                    let mapped = snapshot.documents.compactMap { self.mapEvent(document: $0) }
                    DispatchQueue.main.async {
                        let visibleWindowStart = Date().addingTimeInterval(-86_400 * 30)
                        self.events = mapped.filter {
                            $0.startAt >= visibleWindowStart
                                && self.canView($0)
                        }
                        if self.events.isEmpty {
                            self.events = self.sampleEvents()
                        }
                    }
                    return
                }

                if let error {
                    print("Failed to listen for network events: \(error)")
                }

                DispatchQueue.main.async {
                    if self.events.isEmpty {
                        self.events = self.sampleEvents()
                    }
                }
            }
    }

    func createEvent(
        title: String,
        details: String,
        theme: String,
        startAt: Date,
        locationName: String,
        visibility: EventVisibility,
        publicJoinMode: PublicJoinMode,
        invitedHandlesText: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let organizerId = authenticatedUserId() else {
            completion(false, nil)
            return
        }
        let organizerName = currentUserName()
        let safeVisibility = sanitizeVisibility(visibility)
        let invitedHandles = invitedHandlesText
            .split(separator: ",")
            .map { normalizeHandle(String($0)) }
            .filter { !$0.isEmpty }

        let inviteStatuses = Dictionary(uniqueKeysWithValues: invitedHandles.map { ($0, InviteResponseStatus.pending.rawValue) })

        let payload: [String: Any] = [
            "organizerId": organizerId,
            "organizerName": organizerName,
            "title": title,
            "details": details,
            "theme": theme,
            "startAt": Timestamp(date: startAt),
            "locationName": locationName,
            "headerImageURL": "",
            "visibility": safeVisibility.rawValue,
            "publicJoinMode": publicJoinMode.rawValue,
            "invitedUserHandles": invitedHandles,
            "removedInviteHandles": [],
            "inviteContactNames": [:],
            "inviteContactPhones": [:],
            "inviteStatuses": inviteStatuses,
            "attendingUserIds": [organizerId],
            "attendingNames": [organizerName],
            "joinRequestUserIds": [],
            "joinRequestNames": [],
            "removedForUserIds": [],
            "allowInviteesToAddBringItems": true,
            "bringItems": [],
            "isCanceled": false,
            "canceledAt": NSNull(),
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]

        let docRef = db.collection("networkEvents").document()
        docRef.setData(payload) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to create event: \(error)")
                    completion(false, nil)
                } else {
                    self?.refreshEvents()
                    completion(true, docRef.documentID)
                }
            }
        }
    }

    func addBringItem(eventId: String, title: String, completion: @escaping (Bool) -> Void) {
        guard let uid = authenticatedUserId(),
              let event = events.first(where: { $0.id == eventId }),
              canContribute(to: event) else {
            completion(false)
            return
        }

        let isOrganizerForEvent = event.organizerId == uid
        if !isOrganizerForEvent && !event.allowInviteesToAddBringItems {
            completion(false)
            return
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(false)
            return
        }

        let ref = db.collection("networkEvents").document(eventId)
        let itemId = UUID().uuidString
        db.runTransaction({ transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            var bringItems = snapshot.data()?["bringItems"] as? [[String: Any]] ?? []
            let normalizedNew = trimmed.lowercased()
            let alreadyExists = bringItems.contains { row in
                let existing = String(describing: row["title"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return existing == normalizedNew
            }

            if alreadyExists {
                errorPointer?.pointee = NSError(domain: "EventBringItems", code: 409, userInfo: [NSLocalizedDescriptionKey: "Bring item already exists"])
                return nil
            }

            bringItems.append([
                "id": itemId,
                "title": trimmed,
                "claimedByUserId": "",
                "claimedByName": "",
                "photoURL": ""
            ])

            transaction.updateData([
                "bringItems": bringItems,
                "updatedAt": Timestamp(date: Date())
            ], forDocument: ref)

            return nil
        }) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to add bring item: \(error)")
                    completion(false)
                } else {
                    if let index = self?.events.firstIndex(where: { $0.id == eventId }) {
                        self?.events[index].bringItems.append(
                            EventBringItem(id: itemId, title: trimmed, claimedByUserId: nil, claimedByName: nil, photoURL: nil)
                        )
                    }
                    self?.sendSystemMessage(eventId: eventId, text: "Checklist updated: added \(trimmed).")
                    self?.loadMessages(eventId: eventId)
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func toggleBringItemClaim(eventId: String, itemId: String, completion: @escaping (Bool) -> Void) {
        guard let me = authenticatedUserId(),
              let event = events.first(where: { $0.id == eventId }),
              canContribute(to: event) else {
            completion(false)
            return
        }

        let ref = db.collection("networkEvents").document(eventId)
        let meName = currentUserName()

        db.runTransaction({ transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            var bringItems = snapshot.data()?["bringItems"] as? [[String: Any]] ?? []
            guard let index = bringItems.firstIndex(where: {
                (String(describing: $0["id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == itemId)
            }) else {
                errorPointer?.pointee = NSError(domain: "EventBringItems", code: 404, userInfo: [NSLocalizedDescriptionKey: "Bring item not found"])
                return nil
            }

            var item = bringItems[index]
            let currentClaimer = String(describing: item["claimedByUserId"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if currentClaimer.isEmpty {
                item["claimedByUserId"] = me
                item["claimedByName"] = meName
            } else if currentClaimer == me {
                item["claimedByUserId"] = ""
                item["claimedByName"] = ""
            } else {
                errorPointer?.pointee = NSError(domain: "EventBringItems", code: 409, userInfo: [NSLocalizedDescriptionKey: "Item already claimed"])
                return nil
            }

            bringItems[index] = item
            transaction.updateData([
                "bringItems": bringItems,
                "updatedAt": Timestamp(date: Date())
            ], forDocument: ref)

            return nil
        }) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to toggle bring item claim: \(error)")
                    completion(false)
                } else {
                    var actionText = "updated a checklist item"
                    if let eventIndex = self?.events.firstIndex(where: { $0.id == eventId }),
                       let itemIndex = self?.events[eventIndex].bringItems.firstIndex(where: { $0.id == itemId }) {
                        let current = self?.events[eventIndex].bringItems[itemIndex]
                        let itemTitle = current?.title ?? "an item"
                        let isMine = current?.claimedByUserId == self?.currentUserId()
                        if isMine {
                            self?.events[eventIndex].bringItems[itemIndex].claimedByUserId = nil
                            self?.events[eventIndex].bringItems[itemIndex].claimedByName = nil
                            actionText = "unclaimed \(itemTitle)"
                        } else {
                            self?.events[eventIndex].bringItems[itemIndex].claimedByUserId = self?.currentUserId()
                            self?.events[eventIndex].bringItems[itemIndex].claimedByName = self?.currentUserName()
                            actionText = "claimed \(itemTitle)"
                        }
                    }
                    self?.sendSystemMessage(eventId: eventId, text: "\(self?.currentUserName() ?? "A user") \(actionText).")
                    self?.loadMessages(eventId: eventId)
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func removeBringItem(eventId: String, itemId: String, completion: @escaping (Bool) -> Void) {
        guard authenticatedUserId() != nil,
              let event = events.first(where: { $0.id == eventId }),
              canContribute(to: event) else {
            completion(false)
            return
        }

        let ref = db.collection("networkEvents").document(eventId)

        db.runTransaction({ transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            var bringItems = snapshot.data()?["bringItems"] as? [[String: Any]] ?? []
            guard let index = bringItems.firstIndex(where: {
                String(describing: $0["id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == itemId
            }) else {
                errorPointer?.pointee = NSError(domain: "EventBringItems", code: 404, userInfo: [NSLocalizedDescriptionKey: "Bring item not found"])
                return nil
            }

            bringItems.remove(at: index)
            transaction.updateData([
                "bringItems": bringItems,
                "updatedAt": Timestamp(date: Date())
            ], forDocument: ref)

            return nil
        }) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to remove bring item: \(error)")
                    completion(false)
                } else {
                    if let eventIndex = self?.events.firstIndex(where: { $0.id == eventId }) {
                        self?.events[eventIndex].bringItems.removeAll { $0.id == itemId }
                    }
                    self?.sendSystemMessage(eventId: eventId, text: "Checklist updated: removed an item.")
                    self?.loadMessages(eventId: eventId)
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func setAllowInviteesToAddBringItems(eventId: String, enabled: Bool, completion: @escaping (Bool) -> Void) {
        guard authenticatedUserId() != nil,
              let event = events.first(where: { $0.id == eventId }),
              isOrganizer(event) else {
            completion(false)
            return
        }

        db.collection("networkEvents").document(eventId).updateData([
            "allowInviteesToAddBringItems": enabled,
            "updatedAt": Timestamp(date: Date())
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to update bring-item add setting: \(error)")
                    completion(false)
                } else {
                    if let eventIndex = self?.events.firstIndex(where: { $0.id == eventId }) {
                        self?.events[eventIndex].allowInviteesToAddBringItems = enabled
                    }
                    self?.sendSystemMessage(
                        eventId: eventId,
                        text: enabled ? "Organizer enabled invitee checklist additions." : "Organizer disabled invitee checklist additions."
                    )
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func updateBringItemPhoto(eventId: String, itemId: String, image: UIImage, completion: @escaping (Bool) -> Void) {
        guard authenticatedUserId() != nil,
              let event = events.first(where: { $0.id == eventId }),
              canContribute(to: event) else {
            completion(false)
            return
        }

        guard let imageData = image.jpegData(compressionQuality: 0.82) else {
            completion(false)
            return
        }

        let ref = storage.reference().child("eventBringItems/\(eventId)/\(itemId).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        ref.putData(imageData, metadata: meta) { [weak self] _, error in
            if let error {
                print("Failed to upload bring item photo: \(error)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            ref.downloadURL { url, error in
                guard let self, let photoURL = url?.absoluteString, error == nil else {
                    if let error {
                        print("Failed to fetch bring item photo URL: \(error)")
                    }
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                let docRef = self.db.collection("networkEvents").document(eventId)
                self.db.runTransaction({ transaction, errorPointer in
                    let snapshot: DocumentSnapshot
                    do {
                        snapshot = try transaction.getDocument(docRef)
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }

                    var bringItems = snapshot.data()?["bringItems"] as? [[String: Any]] ?? []
                    guard let index = bringItems.firstIndex(where: {
                        (String(describing: $0["id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == itemId)
                    }) else {
                        errorPointer?.pointee = NSError(domain: "EventBringItems", code: 404, userInfo: [NSLocalizedDescriptionKey: "Bring item not found"])
                        return nil
                    }

                    var item = bringItems[index]
                    item["photoURL"] = photoURL
                    bringItems[index] = item

                    transaction.updateData([
                        "bringItems": bringItems,
                        "updatedAt": Timestamp(date: Date())
                    ], forDocument: docRef)

                    return nil
                }) { [weak self] _, error in
                    DispatchQueue.main.async {
                        if let error {
                            print("Failed to persist bring item photo: \(error)")
                            completion(false)
                        } else {
                            if let eventIndex = self?.events.firstIndex(where: { $0.id == eventId }),
                               let itemIndex = self?.events[eventIndex].bringItems.firstIndex(where: { $0.id == itemId }) {
                                self?.events[eventIndex].bringItems[itemIndex].photoURL = photoURL
                            }
                            self?.sendSystemMessage(eventId: eventId, text: "Checklist updated: added a photo to an item.")
                            self?.loadMessages(eventId: eventId)
                            self?.refreshEvents()
                            completion(true)
                        }
                    }
                }
            }
        }
    }

    func updateEventHeaderImage(eventId: String, image: UIImage, completion: @escaping (Bool, String?) -> Void) {
        guard let event = events.first(where: { $0.id == eventId }), isOrganizer(event) else {
            completion(false, nil)
            return
        }

        guard let imageData = image.jpegData(compressionQuality: 0.84) else {
            completion(false, nil)
            return
        }

        let ref = storage.reference().child("eventHeaders/\(eventId).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        ref.putData(imageData, metadata: meta) { [weak self] _, error in
            if let error {
                print("Failed to upload event header image: \(error)")
                DispatchQueue.main.async { completion(false, nil) }
                return
            }

            ref.downloadURL { url, error in
                guard let self, let headerURL = url?.absoluteString, error == nil else {
                    if let error {
                        print("Failed to fetch event header image URL: \(error)")
                    }
                    DispatchQueue.main.async { completion(false, nil) }
                    return
                }

                self.db.collection("networkEvents").document(eventId).updateData([
                    "headerImageURL": headerURL,
                    "updatedAt": Timestamp(date: Date())
                ]) { [weak self] error in
                    DispatchQueue.main.async {
                        if let error {
                            print("Failed to save event header image URL: \(error)")
                            completion(false, nil)
                        } else {
                            if let index = self?.events.firstIndex(where: { $0.id == eventId }) {
                                self?.events[index].headerImageURL = headerURL
                            }
                            self?.refreshEvents()
                            completion(true, headerURL)
                        }
                    }
                }
            }
        }
    }

    func clearEventHeaderImage(eventId: String, completion: @escaping (Bool) -> Void) {
        guard let event = events.first(where: { $0.id == eventId }), isOrganizer(event) else {
            completion(false)
            return
        }

        db.collection("networkEvents").document(eventId).updateData([
            "headerImageURL": "",
            "updatedAt": Timestamp(date: Date())
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to clear event header image URL: \(error)")
                    completion(false)
                } else {
                    if let index = self?.events.firstIndex(where: { $0.id == eventId }) {
                        self?.events[index].headerImageURL = nil
                    }
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func updateEvent(
        eventId: String,
        title: String,
        details: String,
        theme: String,
        startAt: Date,
        locationName: String,
        visibility: EventVisibility,
        publicJoinMode: PublicJoinMode,
        invitedHandlesText: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard authenticatedUserId() != nil else {
            completion(false)
            return
        }

        let safeVisibility = sanitizeVisibility(visibility)
        let invitedHandles = invitedHandlesText
            .split(separator: ",")
            .map { normalizeHandle(String($0)) }
            .filter { !$0.isEmpty }

        let inviteStatuses = Dictionary(uniqueKeysWithValues: invitedHandles.map { ($0, InviteResponseStatus.pending.rawValue) })

        let payload: [String: Any] = [
            "title": title,
            "details": details,
            "theme": theme,
            "startAt": Timestamp(date: startAt),
            "locationName": locationName,
            "visibility": safeVisibility.rawValue,
            "publicJoinMode": publicJoinMode.rawValue,
            "invitedUserHandles": invitedHandles,
            "inviteStatuses": inviteStatuses,
            "updatedAt": Timestamp(date: Date())
        ]

        db.collection("networkEvents").document(eventId).updateData(payload) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to update event: \(error)")
                    completion(false)
                } else {
                    self?.sendSystemMessage(eventId: eventId, text: "The organizer updated event details.")
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func setAttendance(event: NetworkEvent, attending: Bool) {
        guard let userId = authenticatedUserId() else { return }
        let userName = currentUserName()
        let handle = normalizeHandle(currentUserHandle())
        let ref = db.collection("networkEvents").document(event.id)

        if attending && !isOrganizer(event) && !isInvited(event) && !canCurrentUserDirectlyJoin(event) {
            requestToJoin(event: event) { _ in }
            return
        }

        var updates: [AnyHashable: Any] = [
            "updatedAt": Timestamp(date: Date())
        ]

        if attending {
            updates["attendingUserIds"] = FieldValue.arrayUnion([userId])
            updates["attendingNames"] = FieldValue.arrayUnion([userName])
            updates["joinRequestUserIds"] = FieldValue.arrayRemove([userId])
            updates["joinRequestNames"] = FieldValue.arrayRemove([userName])
        } else {
            updates["attendingUserIds"] = FieldValue.arrayRemove([userId])
            updates["attendingNames"] = FieldValue.arrayRemove([userName])
            if isInvited(event) && !handle.isEmpty {
                updates[FieldPath(["inviteStatuses", handle])] = InviteResponseStatus.declined.rawValue
            }
        }

        ref.updateData(updates) { [weak self] error in
            if let error {
                print("Failed to update attendance: \(error)")
            } else {
                if attending {
                    self?.sendSystemMessage(eventId: event.id, text: "\(userName) is going.")
                } else {
                    self?.sendSystemMessage(eventId: event.id, text: "\(userName) left the event.")
                }
                self?.loadMessages(eventId: event.id)
                self?.refreshEvents()
            }
        }
    }

    func loadMessages(eventId: String) {
        if let event = events.first(where: { $0.id == eventId }), !canContribute(to: event) {
            messagesByEventId[eventId] = []
            return
        }

        db.collection("networkEvents")
            .document(eventId)
            .collection("messages")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments { [weak self] snapshot, error in
                guard let self else { return }
                if let snapshot {
                    let mapped = snapshot.documents.compactMap { self.mapMessage(document: $0) }
                    DispatchQueue.main.async {
                        self.messagesByEventId[eventId] = mapped
                    }
                } else if let error {
                    print("Failed to load messages: \(error)")
                }
            }
    }

    func sendMessage(eventId: String, text: String, completion: @escaping (Bool) -> Void) {
        guard authenticatedUserId() != nil else {
            completion(false)
            return
        }

        if let event = events.first(where: { $0.id == eventId }), !canContribute(to: event) {
            completion(false)
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(false)
            return
        }

        let payload: [String: Any] = [
            "authorName": currentUserName(),
            "authorUserId": currentUserId(),
            "text": trimmed,
            "createdAt": Timestamp(date: Date())
        ]

        db.collection("networkEvents")
            .document(eventId)
            .collection("messages")
            .addDocument(data: payload) { [weak self] error in
                DispatchQueue.main.async {
                    if let error {
                        print("Failed to send event message: \(error)")
                        completion(false)
                    } else {
                        self?.loadMessages(eventId: eventId)
                        completion(true)
                    }
                }
            }
    }

    func isOrganizer(_ event: NetworkEvent) -> Bool {
        event.organizerId == currentUserId()
    }

    func isInvited(_ event: NetworkEvent) -> Bool {
        let handle = normalizeHandle(currentUserHandle())
        return event.invitedUserHandles.map { normalizeHandle($0) }.contains(handle)
    }

    func wasRemovedFromInvite(_ event: NetworkEvent) -> Bool {
        let handle = normalizeHandle(currentUserHandle())
        guard !handle.isEmpty else { return false }
        if event.removedInviteHandles.map({ normalizeHandle($0) }).contains(handle) {
            return true
        }
        return inviteStatus(for: event) == .removed
    }

    func inviteStatus(for event: NetworkEvent) -> InviteResponseStatus {
        let handle = normalizeHandle(currentUserHandle())
        guard !handle.isEmpty else { return .pending }

        if event.removedInviteHandles.map({ normalizeHandle($0) }).contains(handle) {
            return .removed
        }

        let raw = event.inviteStatuses[handle] ?? InviteResponseStatus.pending.rawValue
        return InviteResponseStatus(rawValue: raw) ?? .pending
    }

    func pendingInviteEvents() -> [NetworkEvent] {
        events
            .filter {
                isInvited($0)
                    && !isOrganizer($0)
                    && !isRemovedForCurrentUser($0)
                    && inviteStatus(for: $0) == .pending
            }
            .sorted { $0.startAt < $1.startAt }
    }

    func removeInvitee(event: NetworkEvent, participant: EventParticipant, completion: @escaping (Bool) -> Void) {
        guard isOrganizer(event) else {
            completion(false)
            return
        }

        let handle = normalizeHandle(participant.userHandle ?? participant.displayName)
        guard !handle.isEmpty else {
            completion(false)
            return
        }

        var updates: [AnyHashable: Any] = [
            "invitedUserHandles": FieldValue.arrayRemove([handle]),
            "removedInviteHandles": FieldValue.arrayUnion([handle]),
            FieldPath(["inviteContactNames", handle]): FieldValue.delete(),
            FieldPath(["inviteContactPhones", handle]): FieldValue.delete(),
            "updatedAt": Timestamp(date: Date())
        ]
        updates[FieldPath(["inviteStatuses", handle])] = InviteResponseStatus.removed.rawValue

        if let participantUserId = participant.userId?.trimmingCharacters(in: .whitespacesAndNewlines), !participantUserId.isEmpty {
            updates["attendingUserIds"] = FieldValue.arrayRemove([participantUserId])
        }

        let displayName = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty {
            updates["attendingNames"] = FieldValue.arrayRemove([displayName])
            updates["joinRequestNames"] = FieldValue.arrayRemove([displayName])
        }

        if let participantUserId = participant.userId?.trimmingCharacters(in: .whitespacesAndNewlines), !participantUserId.isEmpty {
            updates["joinRequestUserIds"] = FieldValue.arrayRemove([participantUserId])
        }

        db.collection("networkEvents").document(event.id).updateData(updates) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to remove invitee: \(error)")
                    completion(false)
                } else {
                    self?.sendSystemMessage(eventId: event.id, text: "Organizer removed @\(handle) from this event.")
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func isRemovedForCurrentUser(_ event: NetworkEvent) -> Bool {
        let uid = currentUserId().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { return false }
        return event.removedForUserIds.contains(uid)
    }

    func removeCanceledEventForCurrentUser(event: NetworkEvent, completion: @escaping (Bool) -> Void) {
        guard event.isCanceled, isInvited(event), !isOrganizer(event) else {
            completion(false)
            return
        }

        let uid = currentUserId().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else {
            completion(false)
            return
        }

        db.collection("networkEvents").document(event.id).updateData([
            "removedForUserIds": FieldValue.arrayUnion([uid]),
            "updatedAt": Timestamp(date: Date())
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to remove canceled event for user: \(error)")
                    completion(false)
                } else {
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func cancelEvent(eventId: String, completion: @escaping (Bool) -> Void) {
        guard authenticatedUserId() != nil else {
            completion(false)
            return
        }

        let ref = db.collection("networkEvents").document(eventId)
        ref.updateData([
            "isCanceled": true,
            "canceledAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to cancel event: \(error)")
                    completion(false)
                } else {
                    self?.sendSystemMessage(eventId: eventId, text: "This event was canceled by the organizer.")
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func pendingJoinRequestEventsForCurrentUser() -> [NetworkEvent] {
        let uid = currentUserId()
        return events
            .filter { event in
                event.joinRequestUserIds.contains(uid)
                    && !event.attendingUserIds.contains(uid)
                    && !isOrganizer(event)
            }
            .sorted { $0.startAt < $1.startAt }
    }

    func respondToInvite(event: NetworkEvent, status: InviteResponseStatus, completion: @escaping (Bool) -> Void) {
        guard authenticatedUserId() != nil, isInvited(event) else {
            completion(false)
            return
        }

        guard !event.isCanceled else {
            completion(false)
            return
        }

        guard status != .removed else {
            completion(false)
            return
        }

        let handle = normalizeHandle(currentUserHandle())
        guard !handle.isEmpty else {
            completion(false)
            return
        }

        let userId = currentUserId()
        let userName = currentUserName()
        let ref = db.collection("networkEvents").document(event.id)

        var updates: [AnyHashable: Any] = [
            "updatedAt": Timestamp(date: Date())
        ]

        updates[FieldPath(["inviteStatuses", handle])] = status.rawValue

        switch status {
        case .accepted:
            updates["attendingUserIds"] = FieldValue.arrayUnion([userId])
            updates["attendingNames"] = FieldValue.arrayUnion([userName])
            updates["joinRequestUserIds"] = FieldValue.arrayRemove([userId])
            updates["joinRequestNames"] = FieldValue.arrayRemove([userName])
        case .declined, .maybe:
            updates["attendingUserIds"] = FieldValue.arrayRemove([userId])
            updates["attendingNames"] = FieldValue.arrayRemove([userName])
        case .pending:
            break
        case .removed:
            break
        }

        ref.updateData(updates) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to respond to invite: \(error)")
                    completion(false)
                } else {
                    self?.sendSystemMessage(eventId: event.id, text: "\(userName) responded: \(status.title).")
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func addInviteHandle(event: NetworkEvent, handle: String, completion: @escaping (AddInviteHandleResult) -> Void) {
        guard authenticatedUserId() != nil else {
            completion(.failed)
            return
        }

        let normalizedHandle = normalizeInviteHandle(handle)
        guard !normalizedHandle.isEmpty else {
            completion(.invalidHandle)
            return
        }

        let existing = Set(event.invitedUserHandles.map { normalizeHandle($0) })
        guard !existing.contains(normalizedHandle) else {
            completion(.alreadyInvited)
            return
        }

        let ref = db.collection("networkEvents").document(event.id)
        var updates: [AnyHashable: Any] = [
            "invitedUserHandles": FieldValue.arrayUnion([normalizedHandle]),
            "removedInviteHandles": FieldValue.arrayRemove([normalizedHandle]),
            "updatedAt": Timestamp(date: Date())
        ]
        updates[FieldPath(["inviteContactNames", normalizedHandle])] = FieldValue.delete()
        updates[FieldPath(["inviteContactPhones", normalizedHandle])] = FieldValue.delete()
        updates[FieldPath(["inviteStatuses", normalizedHandle])] = InviteResponseStatus.pending.rawValue

        ref.updateData(updates) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to add invite handle: \(error)")
                    completion(.failed)
                } else {
                    self?.sendSystemMessage(eventId: event.id, text: "Organizer invited @\(normalizedHandle).")
                    self?.refreshEvents()
                    completion(.added)
                }
            }
        }
    }

    func canCurrentUserDirectlyJoin(_ event: NetworkEvent) -> Bool {
        if isOrganizer(event) || isInvited(event) { return true }
        guard event.visibility == .public else { return false }
        return event.publicJoinMode == .autoApprove
    }

    func addExternalInvitee(event: NetworkEvent, contactName: String, phoneNumber: String?, completion: @escaping (AddInviteHandleResult) -> Void) {
        addExternalInvitee(
            eventId: event.id,
            existingInvitedHandles: event.invitedUserHandles,
            contactName: contactName,
            phoneNumber: phoneNumber,
            completion: completion
        )
    }

    func addExternalInvitee(eventId: String, existingInvitedHandles: [String], contactName: String, phoneNumber: String?, completion: @escaping (AddInviteHandleResult) -> Void) {
        guard authenticatedUserId() != nil else {
            completion(.failed)
            return
        }

        let normalizedPhone = (phoneNumber ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        let nameToken = contactName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        let baseToken = normalizedPhone.isEmpty ? nameToken : normalizedPhone
        let safeToken = normalizeInviteHandle("contact_\(baseToken)")
        guard !safeToken.isEmpty else {
            completion(.invalidHandle)
            return
        }

        let existing = Set(existingInvitedHandles.map { normalizeHandle($0) })
        if existing.contains(safeToken) {
            completion(.alreadyInvited)
            return
        }

        var updates: [AnyHashable: Any] = [
            "invitedUserHandles": FieldValue.arrayUnion([safeToken]),
            "removedInviteHandles": FieldValue.arrayRemove([safeToken]),
            "updatedAt": Timestamp(date: Date())
        ]
        updates[FieldPath(["inviteStatuses", safeToken])] = InviteResponseStatus.pending.rawValue
        updates[FieldPath(["inviteContactNames", safeToken])] = contactName
        updates[FieldPath(["inviteContactPhones", safeToken])] = normalizedPhone

        db.collection("networkEvents").document(eventId).updateData(updates) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to add external invitee: \(error)")
                    completion(.failed)
                } else {
                    self?.sendSystemMessage(eventId: eventId, text: "Organizer invited \(contactName).")
                    self?.refreshEvents()
                    completion(.added)
                }
            }
        }
    }

    func setInviteeStatus(event: NetworkEvent, participant: EventParticipant, status: InviteResponseStatus, completion: @escaping (Bool) -> Void) {
        guard isOrganizer(event) else {
            completion(false)
            return
        }

        let handle = normalizeHandle(participant.userHandle ?? "")
        guard !handle.isEmpty else {
            completion(false)
            return
        }

        var updates: [AnyHashable: Any] = [
            "updatedAt": Timestamp(date: Date())
        ]
        updates[FieldPath(["inviteStatuses", handle])] = status.rawValue

        let displayName = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let participantUserId = participant.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch status {
        case .accepted:
            if !participantUserId.isEmpty {
                updates["attendingUserIds"] = FieldValue.arrayUnion([participantUserId])
            }
            if !displayName.isEmpty {
                updates["attendingNames"] = FieldValue.arrayUnion([displayName])
            }
        case .maybe, .declined, .pending, .removed:
            if !participantUserId.isEmpty {
                updates["attendingUserIds"] = FieldValue.arrayRemove([participantUserId])
            }
            if !displayName.isEmpty {
                updates["attendingNames"] = FieldValue.arrayRemove([displayName])
            }
        }

        db.collection("networkEvents").document(event.id).updateData(updates) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to set invitee status: \(error)")
                    completion(false)
                } else {
                    self?.sendSystemMessage(eventId: event.id, text: "Organizer marked \(displayName.isEmpty ? "an invitee" : displayName) as \(status.title).")
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func canCurrentUserRequestToJoin(_ event: NetworkEvent) -> Bool {
        if isOrganizer(event) || isInvited(event) { return false }
        guard event.visibility == .public else { return false }
        guard event.publicJoinMode == .requestApproval else { return false }
        let uid = currentUserId()
        return !event.attendingUserIds.contains(uid) && !event.joinRequestUserIds.contains(uid)
    }

    func hasPendingJoinRequest(event: NetworkEvent) -> Bool {
        event.joinRequestUserIds.contains(currentUserId())
    }

    func joinRequests(for event: NetworkEvent) -> [(userId: String, displayName: String)] {
        event.joinRequestUserIds.enumerated().map { index, userId in
            let name = index < event.joinRequestNames.count
                ? event.joinRequestNames[index]
                : "Guest"
            return (userId: userId, displayName: name)
        }
    }

    func requestToJoin(event: NetworkEvent, completion: @escaping (Bool) -> Void) {
        guard authenticatedUserId() != nil else {
            completion(false)
            return
        }

        guard canCurrentUserRequestToJoin(event) else {
            completion(false)
            return
        }

        let userId = currentUserId()
        let userName = currentUserName()
        db.collection("networkEvents").document(event.id).updateData([
            "joinRequestUserIds": FieldValue.arrayUnion([userId]),
            "joinRequestNames": FieldValue.arrayUnion([userName]),
            "updatedAt": Timestamp(date: Date())
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to request join: \(error)")
                    completion(false)
                } else {
                    self?.sendSystemMessage(eventId: event.id, text: "\(userName) requested to join this event.")
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func reviewJoinRequest(event: NetworkEvent, userId: String, displayName: String, approve: Bool, completion: @escaping (Bool) -> Void) {
        guard authenticatedUserId() != nil, isOrganizer(event) else {
            completion(false)
            return
        }

        let ref = db.collection("networkEvents").document(event.id)
        var updates: [String: Any] = [
            "joinRequestUserIds": FieldValue.arrayRemove([userId]),
            "joinRequestNames": FieldValue.arrayRemove([displayName]),
            "updatedAt": Timestamp(date: Date())
        ]

        if approve {
            updates["attendingUserIds"] = FieldValue.arrayUnion([userId])
            updates["attendingNames"] = FieldValue.arrayUnion([displayName])
        }

        ref.updateData(updates) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to review join request: \(error)")
                    completion(false)
                } else {
                    let resultText = approve ? "approved" : "declined"
                    self?.sendSystemMessage(eventId: event.id, text: "\(displayName)'s join request was \(resultText).")
                    self?.refreshEvents()
                    completion(true)
                }
            }
        }
    }

    func canView(_ event: NetworkEvent) -> Bool {
        if isOrganizer(event) { return true }
        if isRemovedForCurrentUser(event) { return false }

        if isInvited(event) {
            let status = inviteStatus(for: event)
            return status != .declined && status != .removed
        }

        if wasRemovedFromInvite(event) {
            return false
        }

        switch event.visibility {
        case .public: return !event.isCanceled
        case .friends, .inviteOnly: return false
        }
    }

    func loadParticipants(for event: NetworkEvent, completion: @escaping ([EventParticipant]) -> Void) {
        var participants: [EventParticipant] = []

        let organizer = EventParticipant(
            id: "organizer-\(event.organizerId)",
            displayName: event.organizerName,
            role: .organizer,
            userId: event.organizerId,
            userHandle: nil,
            photoURL: nil
        )
        participants.append(organizer)

        for (index, attendeeUserId) in event.attendingUserIds.enumerated() {
            let trimmedUid = attendeeUserId.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedUid.isEmpty || trimmedUid == event.organizerId { continue }

            let fallbackName = index < event.attendingNames.count
                ? event.attendingNames[index]
                : "Guest"

            participants.append(
                EventParticipant(
                    id: "attendee-\(trimmedUid)-\(index)",
                    displayName: fallbackName,
                    role: .attendee,
                    userId: trimmedUid,
                    userHandle: nil,
                    photoURL: nil
                )
            )
        }

        if event.attendingNames.count > event.attendingUserIds.count {
            for index in event.attendingUserIds.count..<event.attendingNames.count {
                let attendeeName = event.attendingNames[index]
                participants.append(
                    EventParticipant(
                        id: "attendee-name-\(attendeeName)-\(index)",
                        displayName: attendeeName,
                        role: .attendee,
                        userId: nil,
                        userHandle: nil,
                        photoURL: nil
                    )
                )
            }
        }

        for (index, handle) in event.invitedUserHandles.enumerated() {
            let normalized = normalizeHandle(handle)
            let alreadyPresent = participants.contains { normalizeHandle($0.userHandle ?? "") == normalized }
            if alreadyPresent { continue }

            let mappedDisplayName = String(event.inviteContactNames[normalized] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = mappedDisplayName.isEmpty ? "@\(normalized)" : mappedDisplayName

            participants.append(
                EventParticipant(
                    id: "invitee-\(normalized)-\(index)",
                    displayName: displayName,
                    role: .invitee,
                    userId: nil,
                    userHandle: normalized,
                    photoURL: nil
                )
            )
        }

        enrichParticipantsWithProfiles(participants) { enriched in
            completion(enriched)
        }
    }

    private func enrichParticipantsWithProfiles(_ participants: [EventParticipant], completion: @escaping ([EventParticipant]) -> Void) {
        var updated = participants
        let group = DispatchGroup()

        let handles = Set<String>(updated.compactMap { participant in
            guard let handle = participant.userHandle else { return nil }
            let normalized = normalizeHandle(handle)
            return normalized.isEmpty ? nil : normalized
        })

        var handleToUid: [String: String] = [:]
        for handle in handles {
            group.enter()
            db.collection("usernames").document(handle).getDocument { snapshot, _ in
                defer { group.leave() }
                if let uid = snapshot?.data()?["uid"] as? String, !uid.isEmpty {
                    handleToUid[handle] = uid
                }
            }
        }

        group.notify(queue: .main) {
            for index in updated.indices {
                if let handle = updated[index].userHandle,
                   updated[index].userId == nil,
                   let uid = handleToUid[self.normalizeHandle(handle)] {
                    updated[index].userId = uid
                }
            }

            self.attachUserDocs(updated, completion: completion)
        }
    }

    private func attachUserDocs(_ participants: [EventParticipant], completion: @escaping ([EventParticipant]) -> Void) {
        var updated = participants
        let group = DispatchGroup()

        let userIds = Set(updated.compactMap { participant in
            let trimmed = participant.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        })

        var userDocsById: [String: [String: Any]] = [:]

        for userId in userIds {
            group.enter()
            db.collection("users").document(userId).getDocument { snapshot, _ in
                defer { group.leave() }
                if let data = snapshot?.data() {
                    userDocsById[userId] = data
                }
            }
        }

        group.notify(queue: .main) {
            for index in updated.indices {
                guard let uid = updated[index].userId,
                      let data = userDocsById[uid] else { continue }

                if let userIdHandle = data["userId"] as? String,
                   !userIdHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updated[index].userHandle = userIdHandle
                }

                if let displayName = data["displayName"] as? String,
                   !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updated[index].displayName = displayName
                } else if let fallbackName = data["userName"] as? String,
                          !fallbackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updated[index].displayName = fallbackName
                }

                let profileImageURL = String(
                    (data["profileImageURL"] as? String)
                        ?? (data["photoURL"] as? String)
                        ?? (data["imageUrl"] as? String)
                        ?? ""
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !profileImageURL.isEmpty {
                    updated[index].photoURL = profileImageURL
                }
            }

            completion(self.deduplicatedParticipants(updated))
        }
    }

    private func deduplicatedParticipants(_ participants: [EventParticipant]) -> [EventParticipant] {
        var seenUserIds: Set<String> = []
        var seenHandles: Set<String> = []
        var result: [EventParticipant] = []

        for participant in participants {
            let uid = participant.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let handle = normalizeHandle(participant.userHandle ?? "")

            if !uid.isEmpty {
                if seenUserIds.contains(uid) { continue }
                seenUserIds.insert(uid)
                if !handle.isEmpty { seenHandles.insert(handle) }
                result.append(participant)
                continue
            }

            if !handle.isEmpty {
                if seenHandles.contains(handle) { continue }
                seenHandles.insert(handle)
                result.append(participant)
                continue
            }

            result.append(participant)
        }

        return result
    }

    private func currentUserHandle() -> String {
        if let uid = Auth.auth().currentUser?.uid {
            let scoped = UserDefaults.standard.string(forKey: scopedIdentityKey(uid: uid, suffix: "userId")) ?? ""
            if !scoped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return scoped
            }
        }

        let stored = UserDefaults.standard.string(forKey: "userId") ?? ""
        if !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        if let email = Auth.auth().currentUser?.email {
            return email
        }
        return currentUserName()
    }

    private func normalizeHandle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizeInviteHandle(_ value: String) -> String {
        let base = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()

        let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let allowed = base.unicodeScalars.filter { scalar in
            allowedCharacterSet.contains(scalar)
        }
        return String(String.UnicodeScalarView(allowed))
    }

    private func sanitizeVisibility(_ visibility: EventVisibility) -> EventVisibility {
        visibility
    }

    private func authenticatedUserId() -> String? {
        let uid = (Auth.auth().currentUser?.uid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return uid.isEmpty ? nil : uid
    }

    private func canContribute(to event: NetworkEvent) -> Bool {
        guard !event.isCanceled else { return false }
        guard let uid = authenticatedUserId() else { return false }
        if event.organizerId == uid { return true }
        if event.attendingUserIds.contains(uid) { return true }
        if isInvited(event) { return true }
        return false
    }

    private func currentUserName() -> String {
        if let uid = Auth.auth().currentUser?.uid {
            let scoped = UserDefaults.standard.string(forKey: scopedIdentityKey(uid: uid, suffix: "displayName")) ?? ""
            if !scoped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return scoped
            }
        }

        let stored = UserDefaults.standard.string(forKey: "userName") ?? ""
        if !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }

        if let display = Auth.auth().currentUser?.displayName, !display.isEmpty {
            return display
        }

        return "You"
    }

    private func scopedIdentityKey(uid: String, suffix: String) -> String {
        "identity_\(uid)_\(suffix)"
    }

    private func currentUserId() -> String {
        if let uid = Auth.auth().currentUser?.uid {
            return uid
        }
        let key = "guestUserId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newValue = UUID().uuidString
        UserDefaults.standard.set(newValue, forKey: key)
        return newValue
    }

    private func mapEvent(document: QueryDocumentSnapshot) -> NetworkEvent? {
        let data = document.data()
        guard let organizerId = data["organizerId"] as? String,
              let organizerName = data["organizerName"] as? String,
              let title = data["title"] as? String,
              let details = data["details"] as? String,
              let theme = data["theme"] as? String,
              let startAt = (data["startAt"] as? Timestamp)?.dateValue(),
              let locationName = data["locationName"] as? String,
              let visibilityRaw = data["visibility"] as? String,
              let visibility = EventVisibility(rawValue: visibilityRaw) else {
            return nil
        }

        let invitedUserHandles = data["invitedUserHandles"] as? [String] ?? []
        let removedInviteHandles = data["removedInviteHandles"] as? [String] ?? []
        let inviteContactNames = data["inviteContactNames"] as? [String: String] ?? [:]
        let inviteContactPhones = data["inviteContactPhones"] as? [String: String] ?? [:]
        let inviteStatuses = data["inviteStatuses"] as? [String: String] ?? [:]
        let attendingUserIds = data["attendingUserIds"] as? [String] ?? []
        let attendingNames = data["attendingNames"] as? [String] ?? []
        let publicJoinModeRaw = data["publicJoinMode"] as? String ?? PublicJoinMode.requestApproval.rawValue
        let headerImageURL = String(data["headerImageURL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let joinRequestUserIds = data["joinRequestUserIds"] as? [String] ?? []
        let joinRequestNames = data["joinRequestNames"] as? [String] ?? []
        let removedForUserIds = data["removedForUserIds"] as? [String] ?? []
        let allowInviteesToAddBringItems = data["allowInviteesToAddBringItems"] as? Bool ?? true
        let bringItems = mapBringItems(from: data["bringItems"] as? [[String: Any]] ?? [])
        let isCanceled = data["isCanceled"] as? Bool ?? false
        let canceledAt = (data["canceledAt"] as? Timestamp)?.dateValue()
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

        return NetworkEvent(
            id: document.documentID,
            organizerId: organizerId,
            organizerName: organizerName,
            title: title,
            details: details,
            theme: theme,
            startAt: startAt,
            locationName: locationName,
            headerImageURL: headerImageURL.isEmpty ? nil : headerImageURL,
            visibility: visibility,
            publicJoinModeRaw: publicJoinModeRaw,
            invitedUserHandles: invitedUserHandles,
            removedInviteHandles: removedInviteHandles,
            inviteContactNames: inviteContactNames,
            inviteContactPhones: inviteContactPhones,
            inviteStatuses: inviteStatuses,
            attendingUserIds: attendingUserIds,
            attendingNames: attendingNames,
            joinRequestUserIds: joinRequestUserIds,
            joinRequestNames: joinRequestNames,
            removedForUserIds: removedForUserIds,
            allowInviteesToAddBringItems: allowInviteesToAddBringItems,
            bringItems: bringItems,
            isCanceled: isCanceled,
            canceledAt: canceledAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func mapBringItems(from rows: [[String: Any]]) -> [EventBringItem] {
        rows.compactMap { row in
            let id = String(describing: row["id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(describing: row["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !title.isEmpty else { return nil }

            let claimedByUserId = String(describing: row["claimedByUserId"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let claimedByName = String(describing: row["claimedByName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let photoURL = String(describing: row["photoURL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            return EventBringItem(
                id: id,
                title: title,
                claimedByUserId: claimedByUserId.isEmpty ? nil : claimedByUserId,
                claimedByName: claimedByName.isEmpty ? nil : claimedByName,
                photoURL: photoURL.isEmpty ? nil : photoURL
            )
        }
    }

    private func mapMessage(document: QueryDocumentSnapshot) -> NetworkEventMessage? {
        let data = document.data()
        guard let authorName = data["authorName"] as? String,
              let text = data["text"] as? String else {
            return nil
        }
        let authorUserId = (data["authorUserId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        return NetworkEventMessage(
            id: document.documentID,
            authorName: authorName,
            authorUserId: (authorUserId?.isEmpty == false) ? authorUserId : nil,
            text: text,
            createdAt: createdAt
        )
    }

    private func sendSystemMessage(eventId: String, text: String) {
        db.collection("networkEvents")
            .document(eventId)
            .collection("messages")
            .addDocument(data: [
                "authorName": "GiftMinder",
                "text": text,
                "createdAt": Timestamp(date: Date())
            ])
    }

    private func sampleEvents() -> [NetworkEvent] {
        let now = Date()
        let calendar = Calendar.current
        let hostId = "sample-host-1"

        return [
            NetworkEvent(
                id: UUID().uuidString,
                organizerId: hostId,
                organizerName: "Maya",
                title: "Rooftop Birthday Dinner",
                details: "Sunset dinner and games. Bring warm layers.",
                theme: "Neon + Casual",
                startAt: calendar.date(byAdding: .day, value: 3, to: now) ?? now,
                locationName: "Skyline Terrace, Downtown",
                headerImageURL: nil,
                visibility: .inviteOnly,
                publicJoinModeRaw: PublicJoinMode.requestApproval.rawValue,
                invitedUserHandles: ["alex", "sam"],
                removedInviteHandles: [],
                inviteContactNames: [:],
                inviteContactPhones: [:],
                inviteStatuses: ["alex": InviteResponseStatus.pending.rawValue, "sam": InviteResponseStatus.pending.rawValue],
                attendingUserIds: [hostId, "u2", "u3"],
                attendingNames: ["Maya", "Liam", "Nina"],
                joinRequestUserIds: [],
                joinRequestNames: [],
                removedForUserIds: [],
                allowInviteesToAddBringItems: true,
                bringItems: [
                    EventBringItem(id: UUID().uuidString, title: "Drinks", claimedByUserId: nil, claimedByName: nil),
                    EventBringItem(id: UUID().uuidString, title: "Paper plates", claimedByUserId: "u2", claimedByName: "Liam")
                ],
                isCanceled: false,
                canceledAt: nil,
                createdAt: now,
                updatedAt: now
            ),
            NetworkEvent(
                id: UUID().uuidString,
                organizerId: "sample-host-2",
                organizerName: "Andre",
                title: "Game Night + Gift Swap",
                details: "Budget cap $25. Secret draw happens in chat.",
                theme: "Board Games",
                startAt: calendar.date(byAdding: .day, value: 6, to: now) ?? now,
                locationName: "Andre's Loft",
                headerImageURL: nil,
                visibility: .friends,
                publicJoinModeRaw: PublicJoinMode.requestApproval.rawValue,
                invitedUserHandles: [normalizeHandle(currentUserHandle()), "maria"],
                removedInviteHandles: [],
                inviteContactNames: [:],
                inviteContactPhones: [:],
                inviteStatuses: [normalizeHandle(currentUserHandle()): InviteResponseStatus.pending.rawValue, "maria": InviteResponseStatus.pending.rawValue],
                attendingUserIds: ["sample-host-2", currentUserId()],
                attendingNames: ["Andre", currentUserName()],
                joinRequestUserIds: [],
                joinRequestNames: [],
                removedForUserIds: [],
                allowInviteesToAddBringItems: true,
                bringItems: [
                    EventBringItem(id: UUID().uuidString, title: "Snacks", claimedByUserId: nil, claimedByName: nil),
                    EventBringItem(id: UUID().uuidString, title: "Ice", claimedByUserId: nil, claimedByName: nil)
                ],
                isCanceled: false,
                canceledAt: nil,
                createdAt: now,
                updatedAt: now
            )
        ]
    }
}

struct CreateEventSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var eventsService = EventsNetworkService.shared
    var onEventCreated: ((String) -> Void)? = nil

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var theme: String = ""
    @State private var startAt: Date = Date().addingTimeInterval(86400)
    @State private var locationName: String = ""
    @State private var visibility: EventVisibility = .inviteOnly
    @State private var inviteHandleInput: String = ""
    @State private var invitedHandles: [String] = []
    @State private var inviteSearchText: String = ""
    @State private var inviteSearchResults: [InviteSearchUser] = []
    @State private var isSearchingInviteUsers = false
    @State private var inviteSearchError: String?
    @State private var inviteSearchWorkItem: DispatchWorkItem?
    @State private var showFailure = false

    private let db = Firestore.firestore()
    private let inviteSearchLimit = 50

    private struct InviteSearchUser: Identifiable {
        let uid: String
        let userId: String
        let displayName: String
        let photoURL: String?

        var id: String { uid }
    }

    var body: some View {
        AppNavigationView {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    TextField("Theme", text: $theme)
                    DatePicker("Date & Time", selection: $startAt)
                }

                Section("Location (Optional)") {
                    TextField("Location", text: $locationName)

                    HStack(spacing: 10) {
                        Button("Apple Maps") {
                            openCreateLocationInAppleMaps()
                        }
                        .buttonStyle(.bordered)

                        Button("Google Maps") {
                            openCreateLocationInGoogleMaps()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Type a location, then open Maps to confirm or refine it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Details") {
                    TextField("Add details", text: $details, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        ForEach(EventVisibility.allCases) { option in
                            Label(option.rawValue, systemImage: option.icon).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Invites") {
                    HStack(spacing: 8) {
                        TextField("Add @username", text: $inviteHandleInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit {
                                addInviteHandleFromInput()
                            }

                        Button("Add") {
                            addInviteHandleFromInput()
                        }
                        .disabled(inviteHandleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    TextField("Search users by name or @username", text: $inviteSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: inviteSearchText) { value in
                            scheduleInviteUserSearch(query: value)
                        }

                    if isSearchingInviteUsers {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.9)
                            Text("Searching users...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let inviteSearchError {
                        Text(inviteSearchError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    if !inviteSearchResults.isEmpty {
                        ForEach(inviteSearchResults) { user in
                            HStack(spacing: 8) {
                                AvatarView(name: user.displayName, photoURL: user.photoURL, imageData: nil, size: 34)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    Text("@\(user.userId)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Add") {
                                    addInviteHandle(user.userId)
                                }
                                .buttonStyle(.bordered)
                                .disabled(invitedHandles.contains(user.userId))
                            }
                        }
                    }

                    if invitedHandles.isEmpty {
                        Text("No invitees added yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(invitedHandles, id: \.self) { handle in
                            HStack {
                                Text("@\(handle)")
                                    .font(.subheadline)
                                Spacer()
                                Button(role: .destructive) {
                                    invitedHandles.removeAll { $0 == handle }
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }

                    Text("Invitees can RSVP and join event chat.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Create Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") { submit() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Couldn’t Create Event", isPresented: $showFailure) {
                Button("OK") {}
            } message: {
                Text("Please try again.")
            }
        }
    }

    private func submit() {
        let normalizedLocation = locationName.trimmingCharacters(in: .whitespacesAndNewlines)

        eventsService.createEvent(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            theme: theme.trimmingCharacters(in: .whitespacesAndNewlines),
            startAt: startAt,
            locationName: normalizedLocation.isEmpty ? "Location TBD" : normalizedLocation,
            visibility: visibility,
            publicJoinMode: .requestApproval,
            invitedHandlesText: invitedHandles.joined(separator: ",")
        ) { success, eventId in
            if success {
                dismiss()
                if let eventId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onEventCreated?(eventId)
                    }
                }
            } else {
                showFailure = true
            }
        }
    }

    private func normalizeInviteHandle(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        return trimmed
    }

    private func addInviteHandleFromInput() {
        let candidates = inviteHandleInput
            .split(separator: ",")
            .map { normalizeInviteHandle(String($0)) }
            .filter { !$0.isEmpty }

        guard !candidates.isEmpty else { return }

        for handle in candidates where !invitedHandles.contains(handle) {
            invitedHandles.append(handle)
        }
        inviteHandleInput = ""
    }

    private func addInviteHandle(_ value: String) {
        let normalized = normalizeInviteHandle(value)
        guard !normalized.isEmpty else { return }
        guard !invitedHandles.contains(normalized) else { return }
        invitedHandles.append(normalized)
    }

    private func scheduleInviteUserSearch(query: String) {
        inviteSearchWorkItem?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            inviteSearchResults = []
            inviteSearchError = nil
            isSearchingInviteUsers = false
            return
        }

        let workItem = DispatchWorkItem {
            performInviteUserSearch(query: trimmed)
        }
        inviteSearchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func performInviteUserSearch(query: String) {
        let normalizedQuery = query.lowercased()
        isSearchingInviteUsers = true
        inviteSearchError = nil

        db.collection("users")
            .order(by: "userId")
            .limit(to: inviteSearchLimit)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isSearchingInviteUsers = false

                    if normalizedQuery != inviteSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                        return
                    }

                    if let error {
                        inviteSearchResults = []
                        inviteSearchError = error.localizedDescription
                        return
                    }

                    let currentUid = Auth.auth().currentUser?.uid
                    let docs = snapshot?.documents ?? []

                    let mapped: [InviteSearchUser] = docs.compactMap { doc in
                        let data = doc.data()
                        let uid = ((data["uid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                            ? (data["uid"] as? String ?? doc.documentID)
                            : doc.documentID

                        if uid == currentUid {
                            return nil
                        }

                        let userId = normalizeInviteHandle((data["userId"] as? String) ?? "")
                        let displayName = ((data["displayName"] as? String)
                            ?? (data["name"] as? String)
                            ?? userId)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let photoURL = String(
                            (data["photoURL"] as? String)
                            ?? (data["imageUrl"] as? String)
                            ?? (data["profileImageURL"] as? String)
                            ?? ""
                        ).trimmingCharacters(in: .whitespacesAndNewlines)

                        guard !userId.isEmpty else { return nil }
                        guard !invitedHandles.contains(userId) else { return nil }

                        let haystackName = displayName.lowercased()
                        let haystackUserId = userId.lowercased()
                        guard haystackName.contains(normalizedQuery) || haystackUserId.contains(normalizedQuery) else {
                            return nil
                        }

                        return InviteSearchUser(
                            uid: uid,
                            userId: userId,
                            displayName: displayName.isEmpty ? userId : displayName,
                            photoURL: photoURL.isEmpty ? nil : photoURL
                        )
                    }

                    inviteSearchResults = mapped.sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                }
            }
    }

    private func openCreateLocationInAppleMaps() {
        let query = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "http://maps.apple.com/?q=\(encoded)") else { return }
        openURL(url)
    }

    private func openCreateLocationInGoogleMaps() {
        let query = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(encoded)") else { return }
        openURL(url)
    }
}

struct InviteInboxSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var eventsService = EventsNetworkService.shared
    let onOpenEvent: (NetworkEvent) -> Void

    @State private var isSubmittingForEventId: String?
    @State private var showResponseToast = false
    @State private var responseToastText = ""
    @State private var organizerPhotoURLs: [String: String] = [:]
    @State private var organizerLocalPhotoData: [String: Data] = [:]
    @State private var loadingOrganizerAvatarIds: Set<String> = []

    private var pending: [NetworkEvent] {
        eventsService.pendingInviteEvents()
    }

    private var responded: [NetworkEvent] {
        eventsService.events
            .filter {
                eventsService.isInvited($0)
                    && !eventsService.isOrganizer($0)
                    && !eventsService.isRemovedForCurrentUser($0)
                    && {
                        let status = eventsService.inviteStatus(for: $0)
                        return (status == .accepted || status == .maybe) || $0.isCanceled
                    }($0)
            }
            .sorted { $0.startAt < $1.startAt }
    }

    var body: some View {
        AppNavigationView {
            List {
                if pending.isEmpty {
                    Section("Pending") {
                        Text("No pending invites right now")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section("Pending") {
                        ForEach(pending) { event in
                            inviteRow(event)
                        }
                    }
                }

                if !responded.isEmpty {
                    Section("Responded") {
                        ForEach(responded) { event in
                            inviteRow(event)
                        }
                    }
                }

            }
            .navigationTitle("Invites")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .top) {
                if showResponseToast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(responseToastText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.brand.opacity(0.18), lineWidth: 1)
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                    }
                }
            }
        }
    }

    private func inviteRow(_ event: NetworkEvent) -> some View {
        let status = eventsService.inviteStatus(for: event)
        let isCanceled = event.isCanceled
        let isRemovedInvite = status == .removed
        let statusTitle = isCanceled ? "Canceled" : status.title
        let statusColor = isCanceled ? Color.red : Color.brand

        return VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                if isRemovedInvite { return }
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onOpenEvent(event)
                }
            }) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        AvatarView(
                            name: event.organizerName,
                            photoURL: organizerPhotoURLs[event.organizerId],
                            imageData: organizerLocalPhotoData[event.organizerId],
                            size: 30
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(event.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(statusTitle)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(statusColor.opacity(0.12))
                                    .foregroundColor(statusColor)
                                    .clipShape(Capsule())
                            }

                            Text("Host: \(event.organizerName)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(formattedDate(event.startAt))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isRemovedInvite)
            .onAppear {
                loadOrganizerAvatarIfNeeded(event)
            }

            if status == .pending && !isCanceled {
                HStack(spacing: 8) {
                    inviteActionButton("Accept", event: event, status: .accepted, tint: .green)
                    inviteActionButton("Maybe", event: event, status: .maybe, tint: Color.brand)
                    inviteActionButton("Decline", event: event, status: .declined, tint: .red)
                }
            } else if isCanceled {
                Button(role: .destructive) {
                    isSubmittingForEventId = event.id
                    eventsService.removeCanceledEventForCurrentUser(event: event) { success in
                        isSubmittingForEventId = nil
                        if success {
                            responseToastText = "Canceled event removed"
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                showResponseToast = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showResponseToast = false
                                }
                            }
                        }
                    }
                } label: {
                    if isSubmittingForEventId == event.id {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Remove")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSubmittingForEventId != nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func inviteActionButton(_ title: String, event: NetworkEvent, status: InviteResponseStatus, tint: Color) -> some View {
        Button(action: {
            isSubmittingForEventId = event.id
            eventsService.respondToInvite(event: event, status: status) { success in
                isSubmittingForEventId = nil
                if success {
                    responseToastText = "Invite marked \(status.title.lowercased())"
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        showResponseToast = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showResponseToast = false
                        }
                    }
                }
            }
        }) {
            if isSubmittingForEventId == event.id {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity)
            } else {
                Text(title)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .disabled(isSubmittingForEventId != nil)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func loadOrganizerAvatarIfNeeded(_ event: NetworkEvent) {
        let organizerId = event.organizerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !organizerId.isEmpty else { return }
        guard !loadingOrganizerAvatarIds.contains(organizerId) else { return }

        let hasRemote = organizerPhotoURLs[organizerId] != nil
        let hasLocal = organizerLocalPhotoData[organizerId] != nil
        if hasRemote || hasLocal {
            return
        }

        loadingOrganizerAvatarIds.insert(organizerId)

        Firestore.firestore().collection("users").document(organizerId).getDocument { snapshot, _ in
            let remote = String(
                ((snapshot?.data()? ["profileImageURL"] as? String) ?? "")
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            if !remote.isEmpty {
                DispatchQueue.main.async {
                    organizerPhotoURLs[organizerId] = remote
                    loadingOrganizerAvatarIds.remove(organizerId)
                }
                return
            }

            loadLocalContactPhoto(displayName: event.organizerName) { data in
                DispatchQueue.main.async {
                    if let data {
                        organizerLocalPhotoData[organizerId] = data
                    }
                    loadingOrganizerAvatarIds.remove(organizerId)
                }
            }
        }
    }

    private func loadLocalContactPhoto(displayName: String, completion: @escaping (Data?) -> Void) {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            completion(nil)
            return
        }

        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(nil)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
            ]

            do {
                let contacts = try store.unifiedContacts(
                    matching: CNContact.predicateForContacts(matchingName: trimmed),
                    keysToFetch: keys
                )
                completion(contacts.first?.thumbnailImageData)
            } catch {
                completion(nil)
            }
        }
    }
}

struct EventDetailSheetView: View {
    let event: NetworkEvent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var eventsService = EventsNetworkService.shared
    @StateObject private var locationSearch = EventLocationSearchService()
    @State private var messageText: String = ""

    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedDetails: String = ""
    @State private var editedTheme: String = ""
    @State private var editedStartAt: Date = Date()
    @State private var editedLocation: String = ""
    @State private var editedVisibility: EventVisibility = .inviteOnly
    @State private var editedInvites: String = ""
    @State private var showUpdateSuccess = false
    @State private var participants: [EventParticipant] = []
    @State private var selectedProfile: NetworkUserProfile?
    @State private var selectedProfileSharedEvents: [NetworkEvent] = []
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
    )
    @State private var resolvedCoordinate: CLLocationCoordinate2D?
    @State private var isResolvingLocation = false
    @State private var showMapOptions = false
    @State private var showCancelEventConfirm = false
    @State private var isCancelingEvent = false
    @State private var isSendingForumMessage = false
    @State private var showAllForumMessages = false
    @State private var showForumSendError = false
    @State private var isEditingInvitees = false
    @State private var isEditingInviteStatuses = false
    @State private var pendingUninviteParticipant: EventParticipant?
    @State private var pendingStatusParticipant: EventParticipant?
    @State private var showUninviteSuccess = false
    @State private var showUninviteError = false
    @State private var showStatusUpdateError = false
    @State private var localParticipantPhotoData: [String: Data] = [:]
    @State private var bringItemPhotoURLs: [String: String] = [:]
    @State private var loadingBringItemPhotoUserIds: Set<String> = []
    @State private var resolvedAddressText: String = ""
    @State private var editedMapAddress: String = ""
    @State private var isUpdatingLocation = false
    @State private var bringItemInput: String = ""
    @State private var isUpdatingBringItems = false
    @State private var isUploadingBringItemPhoto = false
    @State private var isUpdatingBringItemsSetting = false
    @State private var bringItemErrorText: String?
    @State private var pendingBringItemPhotoTarget: EventBringItem?
    @State private var bringItemPhotoInputImage: UIImage?
    @State private var showBringItemPhotoPicker = false
    @State private var showingHeaderImagePicker = false
    @State private var headerInputImage: UIImage?
    @State private var headerBackgroundImage: UIImage?
    @State private var isUploadingHeaderImage = false
    @State private var isForumMutedForEvent = false
    @State private var isUpdatingForumMutePreference = false
    @AppStorage("forumNotificationsEnabled") private var forumNotificationsEnabled: Bool = true

    private var latestEvent: NetworkEvent {
        eventsService.events.first(where: { $0.id == event.id }) ?? event
    }

    private var messages: [NetworkEventMessage] {
        eventsService.messagesByEventId[event.id] ?? []
    }

    private var canEdit: Bool {
        eventsService.isOrganizer(latestEvent)
    }

    private var canClaimBringItems: Bool {
        if latestEvent.isCanceled { return false }
        if canEdit { return true }
        if latestEvent.attendingUserIds.contains(currentUserId()) { return true }
        return eventsService.isInvited(latestEvent) && eventsService.inviteStatus(for: latestEvent) == .accepted
    }

    private var canAddBringItems: Bool {
        if latestEvent.isCanceled { return false }
        if canEdit { return true }
        return latestEvent.allowInviteesToAddBringItems && canViewPrivateEventDetails
    }

    private var isAttending: Bool {
        latestEvent.attendingUserIds.contains { $0 == currentUserId() }
    }

    private var canManageInvitees: Bool {
        canEdit && participants.contains(where: { $0.role == .invitee })
    }

    private var canViewPrivateEventDetails: Bool {
        if canEdit { return true }
        if isAttending { return true }
        return eventsService.isInvited(latestEvent)
    }

    private var canManageInviteStatuses: Bool {
        canEdit && participants.contains(where: { $0.role == .invitee })
    }

    private var currentUserHandle: String {
        if let uid = Auth.auth().currentUser?.uid {
            let scoped = UserDefaults.standard.string(forKey: "identity_\(uid)_userId") ?? ""
            let normalizedScoped = scoped.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalizedScoped.isEmpty {
                return normalizedScoped
            }
        }

        let stored = UserDefaults.standard.string(forKey: "userId") ?? ""
        return stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var forumBottomAnchorId: String {
        "forum-bottom-\(latestEvent.id)"
    }

    private let forumPreviewCount = 5

    private var displayedForumMessages: [NetworkEventMessage] {
        if showAllForumMessages { return messages }
        return Array(messages.prefix(forumPreviewCount))
    }

    private var hasMoreForumMessages: Bool {
        messages.count > forumPreviewCount
    }

    private var isShowingUninviteAlert: Binding<Bool> {
        Binding(
            get: { pendingUninviteParticipant != nil },
            set: { newValue in
                if !newValue {
                    pendingUninviteParticipant = nil
                }
            }
        )
    }

    private var uninviteAlertMessage: String {
        if let participant = pendingUninviteParticipant {
            return "\(participant.displayName) will be removed from the event and receive a removal notice in Invites."
        }
        return "This invitee will be removed from the event."
    }

    private var isShowingStatusDialog: Binding<Bool> {
        Binding(
            get: { pendingStatusParticipant != nil },
            set: { newValue in
                if !newValue {
                    pendingStatusParticipant = nil
                }
            }
        )
    }

    private var isShowingBringItemsAlert: Binding<Bool> {
        Binding(
            get: { bringItemErrorText != nil },
            set: { newValue in
                if !newValue {
                    bringItemErrorText = nil
                }
            }
        )
    }

    private var eventMainContent: some View {
        Group {
            if isEditing {
                Form {
                    Section("Edit Event") {
                        TextField("Title", text: $editedTitle)
                        TextField("Theme", text: $editedTheme)
                        DatePicker("Date & Time", selection: $editedStartAt)
                        TextField("Location", text: $editedLocation)
                        TextField("Details", text: $editedDetails, axis: .vertical)
                            .lineLimit(3...8)
                        Picker("Visibility", selection: $editedVisibility) {
                            ForEach(EventVisibility.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        TextField("Invite handles", text: $editedInvites)
                    }
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        eventHeaderCover

                        VStack(alignment: .leading, spacing: 14) {
                            eventHeroCard
                            mapSection
                            participantsSection
                            bringItemsSection
                            forumSection
                        }
                        .padding()
                    }
                }
                .background(Color(UIColor.systemGroupedBackground))
            }
        }
    }

    var body: some View {
        _configuredEventContent()
    }

    private func _configuredEventContent() -> some View {
        let chromeApplied = applyEventChrome(eventMainContent)
        let alertsApplied = applyEventAlerts(chromeApplied)
        let dialogsAndSheetsApplied = applyEventDialogsAndSheets(alertsApplied)
        return applyEventLifecycleHandlers(dialogsAndSheetsApplied)
    }

    private func applyEventChrome<Content: View>(_ content: Content) -> some View {
        content
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        if isEditing {
                            Button("Save") {
                                saveEdits()
                            }
                        } else {
                            Menu {
                                Button("Edit") {
                                    startEditMode()
                                }

                                if !latestEvent.isCanceled {
                                    Button(role: .destructive) {
                                        showCancelEventConfirm = true
                                    } label: {
                                        Label("Cancel Event", systemImage: "xmark.circle")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.headline)
                            }
                        }
                    }
                }

                if isCancelingEvent {
                    ToolbarItem(placement: .status) {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
            }
    }

    private func applyEventAlerts<Content: View>(_ content: Content) -> some View {
        content
            .alert("Updated", isPresented: $showUpdateSuccess) {
                Button("OK") { isEditing = false }
            } message: {
                Text("Event details saved. Invitees will be notified in event chat.")
            }
            .alert("Cancel Event?", isPresented: $showCancelEventConfirm) {
                Button("Keep Event", role: .cancel) {}
                Button("Cancel Event", role: .destructive) {
                    cancelCurrentEvent()
                }
            } message: {
                Text("Invitees will see this event as canceled in their invite tab.")
            }
            .alert("Uninvite this person?", isPresented: isShowingUninviteAlert) {
                Button("Cancel", role: .cancel) {
                    pendingUninviteParticipant = nil
                }
                Button("Uninvite", role: .destructive) {
                    confirmUninviteParticipant()
                }
            } message: {
                Text(uninviteAlertMessage)
            }
            .alert("Invitee Removed", isPresented: $showUninviteSuccess) {
                Button("OK") {}
            } message: {
                Text("The invitee has been removed and notified in their Invites center.")
            }
            .alert("Couldn’t Remove Invitee", isPresented: $showUninviteError) {
                Button("OK") {}
            } message: {
                Text("Please try again.")
            }
            .alert("Couldn’t Update Status", isPresented: $showStatusUpdateError) {
                Button("OK") {}
            } message: {
                Text("Please try again.")
            }
            .alert("Message Not Sent", isPresented: $showForumSendError) {
                Button("OK") {}
            } message: {
                Text("Please try again. We couldn't post your forum message.")
            }
            .alert("Bring Items", isPresented: isShowingBringItemsAlert) {
                Button("OK") {}
            } message: {
                Text(bringItemErrorText ?? "")
            }
    }

    private func applyEventDialogsAndSheets<Content: View>(_ content: Content) -> some View {
        content
            .confirmationDialog("Set invite status", isPresented: isShowingStatusDialog, titleVisibility: .visible) {
                Button("Going") { confirmSetStatus(.accepted) }
                Button("Maybe") { confirmSetStatus(.maybe) }
                Button("Not Going") { confirmSetStatus(.declined) }
                Button("Cancel", role: .cancel) {
                    pendingStatusParticipant = nil
                }
            }
            .confirmationDialog("Open in Maps", isPresented: $showMapOptions, titleVisibility: .visible) {
                Button("Apple Maps") {
                    openInAppleMaps()
                }
                Button("Google Maps") {
                    openInGoogleMaps()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $selectedProfile) { profile in
                NetworkUserProfileSheetView(profile: profile, sharedEvents: selectedProfileSharedEvents)
            }
            .sheet(isPresented: $showBringItemPhotoPicker) {
                ImagePicker(image: $bringItemPhotoInputImage)
            }
            .sheet(isPresented: $showingHeaderImagePicker) {
                ImagePicker(image: $headerInputImage)
            }
    }

    private func applyEventLifecycleHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                if canViewPrivateEventDetails {
                    eventsService.loadMessages(eventId: event.id)
                    loadParticipants()
                } else {
                    participants = []
                }
                loadForumMutePreference()
                resolveLocationIfNeeded()
                editedMapAddress = latestEvent.locationName
                loadHeaderBackgroundImage()
                locationSearch.updateQuery(editedMapAddress)
            }
            .onChange(of: latestEvent.updatedAt) { _ in
                if canViewPrivateEventDetails {
                    loadParticipants()
                    eventsService.loadMessages(eventId: latestEvent.id)
                } else {
                    participants = []
                }
                resolveLocationIfNeeded()
                editedMapAddress = latestEvent.locationName
                locationSearch.updateQuery(editedMapAddress)
            }
            .onChange(of: editedMapAddress) { value in
                locationSearch.updateQuery(value)
            }
            .onChange(of: headerInputImage) { image in
                if let image {
                    uploadHeaderBackgroundImage(image)
                }
            }
            .onChange(of: bringItemPhotoInputImage) { image in
                guard let image else { return }
                uploadBringItemPhoto(image)
            }
    }

    private var eventHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(latestEvent.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                Spacer()
                if canEdit {
                    Menu {
                        Button {
                            showingHeaderImagePicker = true
                        } label: {
                            Label("Add / Change Header Photo", systemImage: "photo.badge.plus")
                        }

                        if headerBackgroundImage != nil {
                            Button(role: .destructive) {
                                removeHeaderBackgroundImage()
                            } label: {
                                Label("Remove Header Photo", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text(latestEvent.visibility.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.brand.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Label(dateFormatter.string(from: latestEvent.startAt), systemImage: "calendar")
                if canViewPrivateEventDetails {
                    Label("\(latestEvent.attendeeCount) attending", systemImage: "person.3.fill")
                } else {
                    Label("Attendees hidden", systemImage: "lock.fill")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text(latestEvent.theme.isEmpty ? "No theme set" : latestEvent.theme)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.brand)
                Spacer()
                if latestEvent.isCanceled {
                    Text("Canceled")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.14))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                } else if !canEdit {
                    if isAttending {
                        Button("Leave") {
                            eventsService.setAttendance(event: latestEvent, attending: false)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else if eventsService.isInvited(latestEvent) {
                        Button("RSVP") {
                            eventsService.setAttendance(event: latestEvent, attending: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.brand)
                    }
                }
            }

            Text(latestEvent.details.isEmpty ? "No details added yet." : latestEvent.details)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.brand.opacity(0.14), Color(UIColor.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.brand.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var eventHeaderCover: some View {
        let remoteURL = latestEvent.headerImageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if headerBackgroundImage != nil || !remoteURL.isEmpty {
            ZStack(alignment: .bottom) {
                Group {
                    if let headerBackgroundImage {
                        Image(uiImage: headerBackgroundImage)
                            .resizable()
                            .scaledToFill()
                    } else if let url = URL(string: remoteURL), remoteURL.hasPrefix("http") {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Color.brand.opacity(0.14)
                            }
                        }
                    } else {
                        Color.brand.opacity(0.14)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipped()

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color(UIColor.systemGroupedBackground).opacity(0.45),
                        Color(UIColor.systemGroupedBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 210)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipped()
        }
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("People")
                    .font(.headline)
                Spacer()

                if canManageInvitees {
                    Button(isEditingInvitees ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingInvitees.toggle()
                            if isEditingInvitees {
                                isEditingInviteStatuses = false
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color.brand)
                    .buttonStyle(.plain)
                }

                if canManageInviteStatuses {
                    Button(isEditingInviteStatuses ? "RSVP Done" : "RSVP") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingInviteStatuses.toggle()
                            if isEditingInviteStatuses {
                                isEditingInvitees = false
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color.brand)
                    .buttonStyle(.plain)
                }

                if canEdit {
                    Button(action: goToContactsFromEvent) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(Color.brand)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if !canViewPrivateEventDetails {
                lockedEventSection(
                    title: "Attendee list is private",
                    message: "Join or get invited to see who is attending."
                )
            } else {
                if participants.isEmpty {
                    Text("No participants yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(participants.enumerated()), id: \.element.id) { index, participant in
                                participantChip(
                                    participant,
                                    for: latestEvent,
                                    editingInvitees: isEditingInvitees,
                                    editingStatuses: isEditingInviteStatuses
                                )
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(
                                        .spring(response: 0.34, dampingFraction: 0.82)
                                            .delay(Double(index) * 0.02),
                                        value: participants
                                    )
                            }

                            if canEdit {
                                inviteContactChip
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
    }

    private var inviteContactChip: some View {
        Button(action: goToContactsFromEvent) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.brand.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.brand)
                }

                Text("Invite")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(height: 16)

                Text("Open Contacts")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 92)
            .padding(.vertical, 8)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.brand.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func participantChip(_ participant: EventParticipant, for event: NetworkEvent, editingInvitees: Bool, editingStatuses: Bool) -> some View {
        let isOrganizer = participant.userId == event.organizerId
        let inviteStatus = getInviteStatus(for: participant, in: event)
        let statusColor = statusColor(for: inviteStatus)
        let canUninvite = canEdit && editingInvitees && participant.role == .invitee
        let canEditStatus = canEdit && editingStatuses && participant.role == .invitee

        return Button(action: {
            if canUninvite {
                pendingUninviteParticipant = participant
                return
            }

            if canEditStatus {
                pendingStatusParticipant = participant
                return
            }

            guard participant.isGiftMinderUser else { return }
            openProfile(for: participant)
        }) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    AvatarView(
                        name: participant.displayName,
                        photoURL: participant.photoURL,
                        imageData: participant.userId.flatMap { cachedUserProfileImageData(for: $0) } ?? localParticipantPhotoData[participant.id],
                        size: 46
                    )
                    .onAppear {
                        loadLocalParticipantPhotoIfNeeded(participant)
                    }

                    if isOrganizer {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                            .offset(x: 6, y: -6)
                    }
                }

                Text(participant.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if isOrganizer {
                        Text("Organizer")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(inviteStatusTitle(inviteStatus))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.15))
                            .foregroundColor(statusColor)
                            .clipShape(Capsule())
                    }
                    if participant.isGiftMinderUser {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundColor(Color.brand)
                    }
                }
            }
            .frame(width: 92)
            .padding(.vertical, 8)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        canUninvite
                            ? Color.red.opacity(0.35)
                            : (canEditStatus
                                ? Color.brand.opacity(0.35)
                                : (participant.isGiftMinderUser ? Color.brand.opacity(0.2) : Color.clear)),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if canUninvite {
                    Image(systemName: "minus.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .background(Circle().fill(Color(UIColor.systemBackground)))
                        .offset(x: 4, y: -4)
                } else if canEditStatus {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2)
                        .foregroundColor(Color.brand)
                        .padding(4)
                        .background(Circle().fill(Color(UIColor.systemBackground)))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!canUninvite && !canEditStatus && !participant.isGiftMinderUser)
    }

    private func inviteStatusTitle(_ status: String) -> String {
        switch status.lowercased() {
        case "accepted", "going": return "Going"
        case "declined", "not_going": return "Not Going"
        case "maybe": return "Maybe"
        case "removed": return "Removed"
        default: return "Pending"
        }
    }

    private func getInviteStatus(for participant: EventParticipant, in event: NetworkEvent) -> String {
        guard let handle = participant.userHandle else { return "pending" }
        
        if event.attendingUserIds.contains(participant.userId ?? "") {
            return "going"
        }
        
        return event.inviteStatuses[handle.lowercased()] ?? "pending"
    }

    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "going", "accepted":
            return .green
        case "not_going", "declined":
            return .red
        case "maybe":
            return .orange
        case "removed":
            return .red
        default:
            return .gray
        }
    }

    private func confirmUninviteParticipant() {
        guard let participant = pendingUninviteParticipant else { return }
        pendingUninviteParticipant = nil

        eventsService.removeInvitee(event: latestEvent, participant: participant) { success in
            if success {
                showUninviteSuccess = true
            } else {
                showUninviteError = true
            }
        }
    }

    private func confirmSetStatus(_ status: InviteResponseStatus) {
        guard let participant = pendingStatusParticipant else { return }
        pendingStatusParticipant = nil

        eventsService.setInviteeStatus(event: latestEvent, participant: participant, status: status) { success in
            if !success {
                showStatusUpdateError = true
            }
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Location")
                    .font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    Button("Apple") {
                        openInAppleMaps()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Google") {
                        openInGoogleMaps()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if canEdit && !latestEvent.isCanceled {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Search address or place", text: $editedMapAddress)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.brand.opacity(0.12), lineWidth: 1)
                    )

                    Button {
                        updateEventLocation()
                    } label: {
                        if isUpdatingLocation {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text("Update")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(editedMapAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUpdatingLocation)
                }

                Text("Choose a suggestion or tap Update to save your typed location.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if !locationSearch.results.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(locationSearch.results.prefix(5)) { suggestion in
                            Button {
                                editedMapAddress = suggestion.fullText
                                locationSearch.clearResults()
                                updateEventLocation(using: suggestion.fullText)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.subheadline)
                                        .foregroundColor(Color.brand)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.title)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)

                                        if !suggestion.subtitle.isEmpty {
                                            Text(suggestion.subtitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if suggestion.id != locationSearch.results.prefix(5).last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(12)
                }
            }

            if let coordinate = resolvedCoordinate {
                Map(coordinateRegion: $mapRegion, annotationItems: [MapPinPoint(coordinate: coordinate)] as [MapPinPoint]) { point in
                    MapMarker(coordinate: point.coordinate, tint: Color.brand)
                }
                .frame(height: 190)
                .cornerRadius(12)
            } else if isResolvingLocation {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Locating event address…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Text(latestEvent.locationName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(latestEvent.locationName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                if !resolvedAddressText.isEmpty && resolvedAddressText != latestEvent.locationName {
                    Text(resolvedAddressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
    }

    private var bringItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("To Bring")
                    .font(.headline)
                Spacer()
                if canViewPrivateEventDetails {
                    Text("\(latestEvent.bringItems.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Locked")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }

            if !canViewPrivateEventDetails {
                lockedEventSection(
                    title: "Checklist is private",
                    message: "Join or get invited to view and claim to-bring items."
                )
            } else {
                Text("Only the organizer and accepted attendees can claim items.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if canEdit {
                    Toggle("Allow invitees to add checklist items", isOn: Binding(
                        get: { latestEvent.allowInviteesToAddBringItems },
                        set: { updateAllowInviteesToAddBringItems($0) }
                    ))
                    .disabled(isUpdatingBringItemsSetting)
                }

                if canAddBringItems {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet.circle")
                                .foregroundColor(Color.brand)

                            TextField("Add item (food, cups, chairs, drinks…)", text: $bringItemInput)
                                .textFieldStyle(.plain)

                            Button {
                                addBringItem()
                            } label: {
                                if isUpdatingBringItems {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else {
                                    Text("Add")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(bringItemInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUpdatingBringItems)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(12)

                        Text("Tip: Try short labels like Drinks, Cups, Ice, or Snacks.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if latestEvent.bringItems.isEmpty {
                    Text("No items added yet. Organizers can add a checklist for invitees.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(latestEvent.bringItems) { item in
                            bringItemRow(item)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
    }

    private func bringItemRow(_ item: EventBringItem) -> some View {
        let claimedByMe = item.claimedByUserId == currentUserId()
        let claimedBySomeoneElse = item.isClaimed && !claimedByMe
        let canToggle = canClaimBringItems && (!claimedBySomeoneElse || canEdit)
        let canAddPhoto = canAddBringItems

        return HStack(spacing: 10) {
            Button {
                toggleBringItemClaim(item)
            } label: {
                Image(systemName: item.isClaimed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(item.isClaimed ? .green : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canToggle || isUpdatingBringItems)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))

                if let raw = item.photoURL,
                   let url = URL(string: raw),
                   raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("http") {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.brand.opacity(0.12))
                                Image(systemName: "photo")
                                    .foregroundColor(Color.brand)
                            }
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.brand.opacity(0.2), lineWidth: 1)
                    )
                }

                if let name = item.claimedByName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 6) {
                        if let uid = item.claimedByUserId?.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty {
                            AvatarView(
                                name: name,
                                photoURL: bringItemPhotoURLs[uid],
                                imageData: cachedUserProfileImageData(for: uid),
                                size: 18
                            )
                        }

                        Text("Bringing: \(name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Unclaimed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if claimedByMe {
                Text("Mine")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.14))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
            }

            if canEdit {
                Button(role: .destructive) {
                    removeBringItem(item)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.red)
                        .padding(6)
                        .background(Circle().fill(Color.red.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isUpdatingBringItems)
            }

            if canAddPhoto {
                Button {
                    pendingBringItemPhotoTarget = item
                    showBringItemPhotoPicker = true
                } label: {
                    if isUploadingBringItemPhoto && pendingBringItemPhotoTarget?.id == item.id {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .padding(6)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color.brand)
                            .padding(6)
                            .background(Circle().fill(Color.brand.opacity(0.12)))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isUpdatingBringItems || isUploadingBringItemPhoto)
            }
        }
        .padding(10)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(10)
        .onAppear {
            loadBringItemPhotoIfNeeded(item)
        }
    }

    private func loadBringItemPhotoIfNeeded(_ item: EventBringItem) {
        guard let uid = item.claimedByUserId?.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else { return }
        guard bringItemPhotoURLs[uid] == nil else { return }
        guard !loadingBringItemPhotoUserIds.contains(uid) else { return }

        loadingBringItemPhotoUserIds.insert(uid)
        Firestore.firestore().collection("users").document(uid).getDocument { snapshot, _ in
            let remote = String((snapshot?.data()? ["profileImageURL"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                if !remote.isEmpty {
                    bringItemPhotoURLs[uid] = remote
                }
                loadingBringItemPhotoUserIds.remove(uid)
            }
        }
    }

    private func cachedUserProfileImageData(for uid: String) -> Data? {
        UserDefaults.standard.data(forKey: "userProfileImage_\(uid)")
    }

    private var forumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Forum")
                    .font(.headline)
                Spacer()
                Button {
                    toggleForumMutePreference()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isForumMutedForEvent ? "bell.slash.fill" : "bell.fill")
                        Text(isForumMutedForEvent ? "Muted" : "Following")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isForumMutedForEvent ? .secondary : Color.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isForumMutedForEvent ? Color.secondary.opacity(0.15) : Color.brand.opacity(0.12)).cornerRadius(8))
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingForumMutePreference || !forumNotificationsEnabled)
            }

            if !forumNotificationsEnabled {
                Text("Forum push notifications are disabled in Settings.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !canViewPrivateEventDetails {
                lockedEventSection(
                    title: "Forum is private",
                    message: "Join or get invited to read and post messages."
                )
            } else {
                if messages.isEmpty {
                    Text("No messages yet. Start the thread.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(displayedForumMessages) { message in
                            ForumMessageRow(message: message)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: messages.count)

                    if hasMoreForumMessages {
                        Button(showAllForumMessages ? "Show less" : "See more") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllForumMessages.toggle()
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.brand)
                        .buttonStyle(.plain)
                    }
                }

                forumComposer
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
    }

    private func lockedEventSection(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "lock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)

            if latestEvent.visibility == .public && !latestEvent.isCanceled && !canViewPrivateEventDetails {
                if eventsService.canCurrentUserDirectlyJoin(latestEvent) {
                    Button("Join Event") {
                        eventsService.setAttendance(event: latestEvent, attending: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brand)
                } else if eventsService.canCurrentUserRequestToJoin(latestEvent) {
                    Button("Request to Join") {
                        eventsService.requestToJoin(event: latestEvent) { _ in }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brand)
                } else if eventsService.hasPendingJoinRequest(event: latestEvent) {
                    Text("Join request pending approval")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(10)
    }

    private var forumComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(Color.brand)

                TextField("Write a forum message", text: $messageText)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .onSubmit {
                        submitForumMessage()
                    }

                Button {
                    submitForumMessage()
                } label: {
                    if isSendingForumMessage {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Send")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingForumMessage)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(12)
        }
    }

    private func submitForumMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSendingForumMessage else { return }

        isSendingForumMessage = true
        eventsService.sendMessage(eventId: latestEvent.id, text: trimmed) { success in
            isSendingForumMessage = false
            if success {
                messageText = ""
                showAllForumMessages = false
            } else {
                showForumSendError = true
            }
        }
    }

    private func loadParticipants() {
        eventsService.loadParticipants(for: latestEvent) { loaded in
            participants = loaded
        }
    }

    private func loadLocalParticipantPhotoIfNeeded(_ participant: EventParticipant) {
        guard participant.photoURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else { return }
        guard localParticipantPhotoData[participant.id] == nil else { return }

        if let uid = participant.userId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !uid.isEmpty,
           let cached = cachedUserProfileImageData(for: uid) {
            localParticipantPhotoData[participant.id] = cached
            return
        }

        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return }

        let name = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
        ]

        DispatchQueue.global(qos: .userInitiated).async {
            let store = CNContactStore()
            let data: Data?
            do {
                let contacts = try store.unifiedContacts(
                    matching: CNContact.predicateForContacts(matchingName: name),
                    keysToFetch: keys
                )
                data = contacts.first?.thumbnailImageData
            } catch {
                data = nil
            }

            if let data {
                DispatchQueue.main.async {
                    localParticipantPhotoData[participant.id] = data
                }
            }
        }
    }

    private func resolveLocationIfNeeded() {
        let address = latestEvent.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        resolveLocation(address)
    }

    private func resolveLocation(_ address: String) {
        guard !address.isEmpty else {
            resolvedCoordinate = nil
            resolvedAddressText = ""
            return
        }

        isResolvingLocation = true
        CLGeocoder().geocodeAddressString(address) { placemarks, _ in
            DispatchQueue.main.async {
                isResolvingLocation = false
                if let placemark = placemarks?.first,
                   let coordinate = placemark.location?.coordinate {
                    resolvedCoordinate = coordinate
                    mapRegion = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                    )
                    resolvedAddressText = formatAddress(from: placemark)
                } else {
                    resolvedCoordinate = nil
                    resolvedAddressText = ""
                }
            }
        }
    }

    private func updateEventLocation(using overrideAddress: String? = nil) {
        let address = (overrideAddress ?? editedMapAddress).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        guard !latestEvent.isCanceled else { return }

        isUpdatingLocation = true
        eventsService.updateEvent(
            eventId: latestEvent.id,
            title: latestEvent.title,
            details: latestEvent.details,
            theme: latestEvent.theme,
            startAt: latestEvent.startAt,
            locationName: address,
            visibility: latestEvent.visibility,
            publicJoinMode: latestEvent.publicJoinMode,
            invitedHandlesText: latestEvent.invitedUserHandles.joined(separator: ",")
        ) { success in
            isUpdatingLocation = false
            if success {
                editedMapAddress = address
                resolveLocation(address)
                locationSearch.clearResults()
            }
        }
    }

    private func cancelCurrentEvent() {
        guard !latestEvent.isCanceled else { return }
        isCancelingEvent = true
        eventsService.cancelEvent(eventId: latestEvent.id) { _ in
            isCancelingEvent = false
        }
    }

    private func goToContactsFromEvent() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            NotificationCenter.default.post(name: .openContactsFromEvent, object: nil)
        }
    }

    private func formatAddress(from placemark: CLPlacemark) -> String {
        let parts = [
            placemark.name,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        return parts.joined(separator: ", ")
    }

    private func openInAppleMaps() {
        let query = latestEvent.locationName
        if let coordinate = resolvedCoordinate {
            let placemark = MKPlacemark(coordinate: coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = latestEvent.title
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
            return
        }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
            openURL(url)
        }
    }

    private func openInGoogleMaps() {
        let query = latestEvent.locationName
        if let coordinate = resolvedCoordinate {
            let appURL = URL(string: "comgooglemaps://?q=\(coordinate.latitude),\(coordinate.longitude)")
            if let appURL {
                openURL(appURL)
                return
            }
        }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let webURL = URL(string: "https://www.google.com/maps/search/?api=1&query=\(encoded)") {
            openURL(webURL)
        }
    }

    private func openProfile(for participant: EventParticipant) {
        guard let uid = participant.userId else { return }

        selectedProfile = NetworkUserProfile(
            id: uid,
            displayName: participant.displayName,
            userHandle: participant.userHandle,
            photoURL: participant.photoURL,
            subtitle: nil,
            bio: nil,
            interests: [],
            profileFontStyle: nil,
            profileAnimationsEnabled: nil
        )
        selectedProfileSharedEvents = sharedEvents(with: participant)
    }

    private func sharedEvents(with participant: EventParticipant) -> [NetworkEvent] {
        let participantHandle = participant.userHandle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return eventsService.events.filter { networkEvent in
            let currentUserIncluded = isCurrentUserIncluded(in: networkEvent)
            let participantIncluded = isParticipantIncluded(participant, handle: participantHandle, in: networkEvent)
            return currentUserIncluded && participantIncluded
        }
        .sorted { $0.startAt < $1.startAt }
    }

    private func isCurrentUserIncluded(in networkEvent: NetworkEvent) -> Bool {
        if networkEvent.organizerId == currentUserId() { return true }
        if networkEvent.attendingUserIds.contains(currentUserId()) { return true }
        if !currentUserHandle.isEmpty {
            return networkEvent.invitedUserHandles.map { $0.lowercased() }.contains(currentUserHandle)
        }
        return false
    }

    private func isParticipantIncluded(_ participant: EventParticipant, handle: String?, in networkEvent: NetworkEvent) -> Bool {
        if let uid = participant.userId,
           (networkEvent.organizerId == uid || networkEvent.attendingUserIds.contains(uid)) {
            return true
        }

        if let handle,
           networkEvent.invitedUserHandles.map({ $0.lowercased() }).contains(handle) {
            return true
        }

        return networkEvent.attendingNames.contains(participant.displayName)
    }

    private func startEditMode() {
        editedTitle = latestEvent.title
        editedDetails = latestEvent.details
        editedTheme = latestEvent.theme
        editedStartAt = latestEvent.startAt
        editedLocation = latestEvent.locationName
        editedVisibility = latestEvent.visibility
        editedInvites = latestEvent.invitedUserHandles.joined(separator: ", ")
        isEditing = true
    }

    private func addBringItem() {
        let title = bringItemInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let normalized = title.lowercased()
        let exists = latestEvent.bringItems.contains {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
        if exists {
            bringItemErrorText = "That item is already on the checklist."
            return
        }

        isUpdatingBringItems = true
        eventsService.addBringItem(eventId: latestEvent.id, title: title) { success in
            isUpdatingBringItems = false
            if success {
                bringItemInput = ""
            } else {
                bringItemErrorText = "Couldn’t add this item right now. Please try again."
            }
        }
    }

    private func toggleBringItemClaim(_ item: EventBringItem) {
        isUpdatingBringItems = true
        eventsService.toggleBringItemClaim(eventId: latestEvent.id, itemId: item.id) { success in
            isUpdatingBringItems = false
            if !success {
                bringItemErrorText = "This item may already be claimed. Refresh and try again."
            }
        }
    }

    private func removeBringItem(_ item: EventBringItem) {
        isUpdatingBringItems = true
        eventsService.removeBringItem(eventId: latestEvent.id, itemId: item.id) { success in
            isUpdatingBringItems = false
            if !success {
                bringItemErrorText = "Couldn’t remove this item right now. Please try again."
            }
        }
    }

    private func updateAllowInviteesToAddBringItems(_ enabled: Bool) {
        guard canEdit else { return }
        isUpdatingBringItemsSetting = true
        eventsService.setAllowInviteesToAddBringItems(eventId: latestEvent.id, enabled: enabled) { success in
            isUpdatingBringItemsSetting = false
            if !success {
                bringItemErrorText = "Couldn’t update checklist permissions right now."
            }
        }
    }

    private func uploadBringItemPhoto(_ image: UIImage) {
        guard let target = pendingBringItemPhotoTarget else { return }
        isUploadingBringItemPhoto = true
        eventsService.updateBringItemPhoto(eventId: latestEvent.id, itemId: target.id, image: image) { success in
            isUploadingBringItemPhoto = false
            pendingBringItemPhotoTarget = nil
            bringItemPhotoInputImage = nil
            showBringItemPhotoPicker = false
            if !success {
                bringItemErrorText = "Couldn’t upload this item photo right now. Please try again."
            }
        }
    }

    private func forumMutedEventIdsKey() -> String {
        let uid = Auth.auth().currentUser?.uid ?? "guest"
        return "forumMutedEventIds_\(uid)"
    }

    private func loadForumMutePreference() {
        let muted = UserDefaults.standard.stringArray(forKey: forumMutedEventIdsKey()) ?? []
        isForumMutedForEvent = muted.contains(latestEvent.id)
    }

    private func toggleForumMutePreference() {
        guard forumNotificationsEnabled else { return }
        isUpdatingForumMutePreference = true

        var muted = UserDefaults.standard.stringArray(forKey: forumMutedEventIdsKey()) ?? []
        if isForumMutedForEvent {
            muted.removeAll { $0 == latestEvent.id }
            isForumMutedForEvent = false
        } else {
            muted.append(latestEvent.id)
            isForumMutedForEvent = true
        }
        let uniqueMuted = Array(Set(muted))
        UserDefaults.standard.set(uniqueMuted, forKey: forumMutedEventIdsKey())

        guard let uid = Auth.auth().currentUser?.uid else {
            isUpdatingForumMutePreference = false
            return
        }

        Firestore.firestore().collection("users").document(uid).setData([
            "notificationPreferences": [
                "forumUpdatesEnabled": forumNotificationsEnabled,
                "mutedForumEventIds": uniqueMuted
            ],
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true) { _ in
            DispatchQueue.main.async {
                isUpdatingForumMutePreference = false
            }
        }
    }

    private func eventHeaderImageKey() -> String {
        "eventHeaderImage_\(latestEvent.id)"
    }

    private func loadHeaderBackgroundImage() {
        let remoteURL = latestEvent.headerImageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !remoteURL.isEmpty {
            headerBackgroundImage = nil
            UserDefaults.standard.removeObject(forKey: eventHeaderImageKey())
            return
        }

        let key = eventHeaderImageKey()
        guard let data = UserDefaults.standard.data(forKey: key),
              let image = UIImage(data: data) else {
            headerBackgroundImage = nil
            return
        }
        headerBackgroundImage = image
    }

    private func uploadHeaderBackgroundImage(_ image: UIImage) {
        guard canEdit else { return }
        isUploadingHeaderImage = true
        headerBackgroundImage = image
        eventsService.updateEventHeaderImage(eventId: latestEvent.id, image: image) { success, _ in
            DispatchQueue.main.async {
                isUploadingHeaderImage = false
                if success {
                    if let data = image.jpegData(compressionQuality: 0.8) {
                        UserDefaults.standard.set(data, forKey: eventHeaderImageKey())
                    }
                } else {
                    headerBackgroundImage = nil
                }
            }
        }
    }

    private func removeHeaderBackgroundImage() {
        guard canEdit else { return }
        isUploadingHeaderImage = true
        eventsService.clearEventHeaderImage(eventId: latestEvent.id) { success in
            DispatchQueue.main.async {
                isUploadingHeaderImage = false
                if success {
                    headerBackgroundImage = nil
                    UserDefaults.standard.removeObject(forKey: eventHeaderImageKey())
                }
            }
        }
    }

    private func saveEdits() {
        eventsService.updateEvent(
            eventId: latestEvent.id,
            title: editedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            details: editedDetails.trimmingCharacters(in: .whitespacesAndNewlines),
            theme: editedTheme.trimmingCharacters(in: .whitespacesAndNewlines),
            startAt: editedStartAt,
            locationName: editedLocation.trimmingCharacters(in: .whitespacesAndNewlines),
            visibility: editedVisibility,
            publicJoinMode: .requestApproval,
            invitedHandlesText: editedInvites
        ) { success in
            if success {
                showUpdateSuccess = true
                eventsService.loadMessages(eventId: latestEvent.id)
            }
        }
    }

    private func currentUserId() -> String {
        if let uid = Auth.auth().currentUser?.uid {
            return uid
        }
        let key = "guestUserId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newValue = UUID().uuidString
        UserDefaults.standard.set(newValue, forKey: key)
        return newValue
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }


    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }
}

private struct MapPinPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

private final class EventLocationSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String

        var fullText: String {
            let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedSubtitle.isEmpty { return title }
            return "\(title), \(trimmedSubtitle)"
        }
    }

    @Published var results: [Suggestion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clearResults() {
        results = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results.map { completion in
            let id = "\(completion.title)-\(completion.subtitle)"
            return Suggestion(id: id, title: completion.title, subtitle: completion.subtitle)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}

private struct ForumMessageRow: View {
    let message: NetworkEventMessage
    @State private var remotePhotoURL: String?
    @State private var localProfileData: Data?
    @State private var localPhotoData: Data?
    @State private var didAttemptPhotoLookup = false
    @State private var didAttemptRemoteProfileLookup = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if isSystemGiftMinderMessage {
                    ZStack {
                        Circle()
                            .fill(Color.brand.opacity(0.16))
                            .frame(width: 34, height: 34)
                        Image(systemName: "gift.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.brand)
                    }
                } else {
                    AvatarView(name: message.authorName, photoURL: remotePhotoURL, imageData: localProfileData ?? localPhotoData, size: 34)
                        .onAppear {
                            loadRemoteProfilePhotoIfNeeded()
                            loadLocalContactPhotoIfNeeded()
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.authorName)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(relativeDate(message.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .padding(10)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.brand.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private var isSystemGiftMinderMessage: Bool {
        message.authorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "giftminder"
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadLocalContactPhotoIfNeeded() {
        guard !didAttemptPhotoLookup else { return }
        didAttemptPhotoLookup = true

        guard remotePhotoURL == nil else { return }
        if localProfileData != nil { return }

        guard localPhotoData == nil else { return }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return }

        let trimmed = message.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
            ]

            let data: Data?
            do {
                let contacts = try store.unifiedContacts(
                    matching: CNContact.predicateForContacts(matchingName: trimmed),
                    keysToFetch: keys
                )
                data = contacts.first?.thumbnailImageData
            } catch {
                data = nil
            }

            guard let data else { return }
            DispatchQueue.main.async {
                localPhotoData = data
            }
        }
    }

    private func loadRemoteProfilePhotoIfNeeded() {
        guard !didAttemptRemoteProfileLookup else { return }
        didAttemptRemoteProfileLookup = true

        guard !isSystemGiftMinderMessage else { return }
        guard let uid = message.authorUserId?.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else { return }

        if let cached = UserDefaults.standard.data(forKey: "userProfileImage_\(uid)") {
            localProfileData = cached
        }

        Firestore.firestore().collection("users").document(uid).getDocument { snapshot, _ in
            let remote = String((snapshot?.data()? ["profileImageURL"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remote.isEmpty else { return }

            DispatchQueue.main.async {
                remotePhotoURL = remote
            }
        }
    }
}

private struct AvatarView: View {
    let name: String
    let photoURL: String?
    let imageData: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let imageData,
               let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let photoURL,
               let url = URL(string: photoURL),
               photoURL.starts(with: "http") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsCircle
                    }
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill(Color.brand.opacity(0.2))
            Text(initials(from: name))
                .font(.caption.weight(.bold))
                .foregroundColor(Color.brand)
        }
    }

    private func initials(from value: String) -> String {
        let parts = value.split(separator: " ")
        let first = parts.first.map { String($0.prefix(1)) } ?? "?"
        let last = parts.count > 1 ? String(parts.last?.prefix(1) ?? "") : ""
        return (first + last).uppercased()
    }
}

struct NetworkUserProfileSheetView: View {
    let profile: NetworkUserProfile
    let sharedEvents: [NetworkEvent]

    @Environment(\.dismiss) private var dismiss
    @State private var liveProfile: NetworkUserProfile
    @State private var profileListener: ListenerRegistration?
    @State private var avatarPulse = false
    @State private var showReportOptions = false
    @State private var reportToastMessage: String?

    init(profile: NetworkUserProfile, sharedEvents: [NetworkEvent]) {
        self.profile = profile
        self.sharedEvents = sharedEvents
        _liveProfile = State(initialValue: profile)
    }

    var body: some View {
        AppNavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [Color.brandStart, Color.brandEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 110)

                        VStack(spacing: 8) {
                            AvatarView(name: liveProfile.displayName, photoURL: liveProfile.photoURL, imageData: nil, size: 72)
                                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                                .offset(y: -36)
                                .padding(.bottom, -28)
                                .scaleEffect(1.0)

                            Text(liveProfile.displayName)
                                .font(.title3.weight(.bold))

                            if let handle = liveProfile.userHandle,
                               !handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("@\(handle)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            if let subtitle = liveProfile.subtitle,
                               !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                    }
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bio")
                            .font(.headline)

                        if let bio = liveProfile.bio,
                           !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(bio)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineSpacing(2)
                        } else {
                            Text("No bio added yet.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interests")
                            .font(.headline)

                        if liveProfile.interests.isEmpty {
                            Text("No interests added yet.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(liveProfile.interests, id: \.self) { interest in
                                        Text(interest)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.brand.opacity(0.12))
                                            .foregroundColor(Color.brand)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Info")
                            .font(.headline)

                        if sharedEvents.isEmpty {
                            Text("No shared events with this user yet.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(sharedEvents) { shared in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Event: \(shared.title)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(dateLine(for: shared.startAt))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
                .padding()
            }
            .fontDesign(profileFontDesign)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showReportOptions = true
                    } label: {
                        Image(systemName: "exclamationmark.bubble")
                    }
                }
            }
            .confirmationDialog("Report Profile", isPresented: $showReportOptions, titleVisibility: .visible) {
                Button("Inappropriate photo") { submitProfileReport(reason: "inappropriate_photo") }
                Button("Inappropriate bio") { submitProfileReport(reason: "inappropriate_bio") }
                Button("Harassment") { submitProfileReport(reason: "harassment") }
                Button("Impersonation") { submitProfileReport(reason: "impersonation") }
                Button("Cancel", role: .cancel) {}
            }
            .overlay(alignment: .top) {
                if let reportToastMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(reportToastMessage)
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.brand.opacity(0.18), lineWidth: 1)
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear {
                startProfileListener()
                avatarPulse = false
            }
            .onDisappear {
                profileListener?.remove()
                profileListener = nil
            }
        }
    }

    private var profileFontDesign: Font.Design {
        switch liveProfile.profileFontStyle {
        case "rounded":
            return .rounded
        case "serif":
            return .serif
        case "monospaced":
            return .monospaced
        default:
            return .default
        }
    }

    private func startProfileListener() {
        profileListener?.remove()
        profileListener = Firestore.firestore()
            .collection("users")
            .document(profile.id)
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data() else { return }

                let displayName = String(
                    (data["displayName"] as? String) ??
                    (data["name"] as? String) ??
                    liveProfile.displayName
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                let handle = String((data["userId"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let photoURL = String(
                    (data["photoURL"] as? String) ??
                    (data["imageUrl"] as? String) ?? ""
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                let subtitle = String((data["subtitle"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let bio = String((data["bio"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let interests = (data["interests"] as? [String] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let profileFontStyle = String((data["profileFontStyle"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                liveProfile.displayName = displayName.isEmpty ? liveProfile.displayName : displayName
                liveProfile.userHandle = handle.isEmpty ? nil : handle
                liveProfile.photoURL = photoURL.isEmpty ? nil : photoURL
                liveProfile.subtitle = subtitle.isEmpty ? nil : subtitle
                liveProfile.bio = bio.isEmpty ? nil : bio
                liveProfile.interests = interests
                liveProfile.profileFontStyle = profileFontStyle.isEmpty ? nil : profileFontStyle
                liveProfile.profileAnimationsEnabled = false
                avatarPulse = false
            }
    }

    private func startAvatarAnimationIfNeeded() {
        avatarPulse = false
    }

    private func dateLine(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func submitProfileReport(reason: String) {
        let callable = Functions.functions().httpsCallable("reportProfile")
        callable.call([
            "reportedUid": profile.id,
            "reason": reason,
        ]) { _, error in
            if let error {
                reportToastMessage = "Unable to send report"
                print("reportProfile failed: \(error.localizedDescription)")
            } else {
                reportToastMessage = "Report submitted"
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    reportToastMessage = nil
                }
            }
        }
    }
}

