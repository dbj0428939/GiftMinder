import Foundation
import FirebaseAuth
import FirebaseFirestore

final class AuthUserSyncService {
    static let shared = AuthUserSyncService()

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()

    private init() {}

    func start() {
        guard authStateHandle == nil else { return }

        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self, let user else { return }
            self.ensureUserDocument(for: user)
        }
    }

    private func ensureUserDocument(for user: User) {
        let userRef = db.collection("users").document(user.uid)
        let fallbackName = defaultDisplayName(for: user)

        userRef.getDocument { [weak self] snapshot, error in
            guard self != nil else { return }

            if let error = error {
                print("AuthUserSyncService: failed reading user doc: \(error.localizedDescription)")
                return
            }

            let existingData = snapshot?.data() ?? [:]
            let existingDisplayName = (existingData["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let existingName = (existingData["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let resolvedName: String
            if let existingDisplayName, !existingDisplayName.isEmpty {
                resolvedName = existingDisplayName
            } else if let existingName, !existingName.isEmpty {
                resolvedName = existingName
            } else {
                resolvedName = fallbackName
            }

            var payload: [String: Any] = [
                "uid": user.uid,
                "displayName": resolvedName,
                "name": resolvedName,
                "updatedAt": FieldValue.serverTimestamp(),
                "lastSeenAt": FieldValue.serverTimestamp()
            ]

            if !(snapshot?.exists ?? false) || existingData["createdAt"] == nil {
                payload["createdAt"] = FieldValue.serverTimestamp()
            }

            userRef.setData(payload, merge: true) { error in
                if let error = error {
                    print("AuthUserSyncService: failed writing user doc: \(error.localizedDescription)")
                }
            }
        }
    }

    private func defaultDisplayName(for user: User) -> String {
        if let displayName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
            return displayName
        }

        return "GiftMinder User"
    }
}
