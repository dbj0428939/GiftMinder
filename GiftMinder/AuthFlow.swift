import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

enum AuthState: String {
    case unauthenticated
    case authenticated
    case guest
}

private enum UserIdAvailability {
    case idle
    case checking
    case available
    case taken
    case invalid
}

// Wave effect for the gift icon
struct WaveEffect: ViewModifier {
    @State private var waveOffset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .offset(y: sin(waveOffset) * 3)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 3.0)
                    .repeatForever(autoreverses: true)
                ) {
                    waveOffset = .pi * 2
                }
            }
    }
}

extension View {
    func wave() -> some View {
        modifier(WaveEffect())
    }
}

struct LoginView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("authState") private var authStateRaw: String = AuthState.unauthenticated.rawValue
    @AppStorage("userName") private var storedUserName: String = ""
    @AppStorage("userId") private var storedUserId: String = ""
    @AppStorage("lastSyncedAuthUid") private var lastSyncedAuthUid: String = ""

    @State private var isCreateAccount = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var profileDisplayName = ""
    @State private var userId = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var userIdAvailability: UserIdAvailability = .idle
    @State private var userIdCheckWorkItem: DispatchWorkItem?
    @State private var showContent = false
    @State private var showIcon = false
    @State private var showTitle = false

    private var authState: AuthState {
        get { AuthState(rawValue: authStateRaw) ?? .unauthenticated }
        nonmutating set { authStateRaw = newValue.rawValue }
    }

    @ViewBuilder
    private var loginBackground: some View {
        if colorScheme == .light {
            LinearGradient(
                colors: [
                    Color(UIColor.systemBackground),
                    Color.brand.opacity(0.20),
                    Color.brand.opacity(0.20)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        } else {
            AppBackground()
        }
    }

    private var titleColor: Color {
        .white
    }

    private var subtitleColor: Color {
        colorScheme == .dark ? .secondary : .white.opacity(0.88)
    }

    private var authCardBackground: Color {
        colorScheme == .dark
            ? Color(UIColor.systemBackground).opacity(0.10)
            : Color(UIColor.systemBackground).opacity(0.78)
    }

    private var authCardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    private var guestButtonBackground: Color {
        colorScheme == .dark
            ? Color(UIColor.secondarySystemBackground).opacity(0.60)
            : Color(UIColor.systemBackground).opacity(0.94)
    }

    private var guestButtonTextColor: Color {
        colorScheme == .dark ? .secondary : .primary.opacity(0.72)
    }

    private var logoGradient: LinearGradient {
        if colorScheme == .light {
            return LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.38, blue: 0.82),
                    Color(red: 0.42, green: 0.30, blue: 0.82),
                    Color(red: 0.56, green: 0.24, blue: 0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.35, green: 0.55, blue: 1.0),
                Color(red: 0.6, green: 0.45, blue: 1.0),
                Color(red: 0.75, green: 0.35, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            loginBackground

            VStack {
                Spacer()

                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(logoGradient)
                            .shadow(color: Color.brand.opacity(0.6), radius: 20, x: 0, y: 0)
                            .shadow(color: Color.brandEnd.opacity(0.5), radius: 30, x: 0, y: 0)
                            .wave()
                            .scaleEffect(showIcon ? 1 : 0.3)
                            .opacity(showIcon ? 1 : 0)

                        HStack(spacing: 2) {
                            Text("GiftMinder")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .tracking(0.4)
                                .foregroundColor(titleColor)

                            Text("™")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .baselineOffset(14)
                                .foregroundColor(titleColor.opacity(0.95))
                        }
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(colorScheme == .light ? 0.16 : 0.08))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(colorScheme == .light ? 0.24 : 0.12), lineWidth: 1)
                        )
                        .offset(y: showTitle ? 0 : 20)
                        .opacity(showTitle ? 1 : 0)

                        if !isCreateAccount {
                            Text("Sign in to sync your reminders, or continue as a guest.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(subtitleColor)
                                .padding(.horizontal, 18)
                                .opacity(showContent ? 1 : 0)
                        }
                    }

                    VStack(spacing: 14) {
                        Picker("Mode", selection: $isCreateAccount) {
                            Text("Sign In").tag(false)
                            Text("Create Account").tag(true)
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 12) {
                            if isCreateAccount {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Profile Display Name")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(subtitleColor)

                                    TextField("Enter your name", text: $profileDisplayName)
                                        .textInputAutocapitalization(.words)
                                        .autocorrectionDisabled()
                                        .padding(14)
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .cornerRadius(12)
                                }

                                TextField("User ID", text: $userId)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(14)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(12)
                                    .onChange(of: userId) { newValue in
                                        scheduleUserIdCheck(newValue)
                                    }
                            }

                            TextField("Email", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(12)

                            SecureField("Password", text: $password)
                                .textInputAutocapitalization(.never)
                                .padding(14)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(12)

                            if isCreateAccount {
                                SecureField("Confirm Password", text: $confirmPassword)
                                    .textInputAutocapitalization(.never)
                                    .padding(14)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(12)
                            }
                        }

                        if isCreateAccount {
                            HStack(spacing: 6) {
                                if let icon = userIdStatusIcon {
                                    Image(systemName: icon)
                                        .font(.caption)
                                }
                                Text(userIdStatusText)
                                    .font(.caption)
                            }
                            .foregroundColor(userIdStatusColor)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: handlePrimaryAction) {
                            HStack(spacing: 10) {
                                if isWorking {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isCreateAccount ? "Create Account" : "Sign In")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.brand)
                            .cornerRadius(12)
                        }
                        .disabled(isWorking)

                        Button(action: handleGoogleSignIn) {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                Text("Continue with Google")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.26, green: 0.52, blue: 0.96))
                            .cornerRadius(12)
                        }
                        .disabled(isWorking)

                        if !isCreateAccount {
                            Button(action: continueAsGuest) {
                                Text("Continue as Guest")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(guestButtonTextColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(guestButtonBackground)
                                    .cornerRadius(12)
                            }
                            .disabled(isWorking)
                        }
                    }
                    .padding(18)
                    .background(authCardBackground)
                    .cornerRadius(18)
                    .shadow(
                        color: colorScheme == .dark ? Color.black.opacity(0.16) : Color.black.opacity(0.10),
                        radius: colorScheme == .dark ? 14 : 18,
                        x: 0,
                        y: colorScheme == .dark ? 6 : 10
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(authCardBorder, lineWidth: 1)
                    )
                    .scaleEffect(showContent ? 1 : 0.95)
                    .opacity(showContent ? 1 : 0)

                    if !isCreateAccount {
                        Text("Guest mode keeps your data on this device.")
                            .font(.footnote)
                            .foregroundColor(subtitleColor)
                            .opacity(showContent ? 1 : 0)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                    showIcon = true
                }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3)) {
                    showTitle = true
                }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.5)) {
                    showContent = true
                }
            }
            .onChange(of: isCreateAccount) { newValue in
                if newValue {
                    scheduleUserIdCheck(userId)
                } else {
                    userIdAvailability = .idle
                }
            }
        }
    }

    private func handlePrimaryAction() {
        if isWorking {
            return
        }

        errorMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty || password.isEmpty {
            errorMessage = "Enter an email and password to continue."
            return
        }

        if isCreateAccount {
            let trimmedDisplayName = profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedDisplayName.isEmpty {
                errorMessage = "Enter a profile display name."
                return
            }

            let normalizedUserId = normalizeUserId(userId)
            if !isValidUserId(normalizedUserId) {
                errorMessage = "User ID must be 3-20 letters, numbers, or underscore."
                return
            }

            if userIdAvailability == .checking {
                errorMessage = "Checking user ID availability..."
                return
            }

            if userIdAvailability == .taken {
                errorMessage = "User ID is already taken."
                return
            }

            if password != confirmPassword {
                errorMessage = "Passwords do not match."
                return
            }

            isWorking = true
            Auth.auth().createUser(withEmail: trimmedEmail, password: password) { result, error in
                if let error = error {
                    DispatchQueue.main.async {
                        errorMessage = error.localizedDescription
                        isWorking = false
                    }
                    return
                }

                guard let user = result?.user else {
                    DispatchQueue.main.async {
                        errorMessage = "Unable to create account."
                        isWorking = false
                    }
                    return
                }

                let profileChange = user.createProfileChangeRequest()
                profileChange.displayName = trimmedDisplayName
                profileChange.commitChanges { _ in
                    reserveUserId(uid: user.uid, userId: normalizedUserId, displayName: trimmedDisplayName) { reservationResult in
                        DispatchQueue.main.async {
                            switch reservationResult {
                            case .success:
                                storedUserName = trimmedDisplayName
                                storedUserId = normalizedUserId
                                lastSyncedAuthUid = user.uid
                                persistScopedIdentity(uid: user.uid, displayName: trimmedDisplayName, userId: normalizedUserId)
                                authState = .authenticated
                                NotificationService.shared.setupFCMToken()
                            case .failure(let error):
                                user.delete { _ in
                                    try? Auth.auth().signOut()
                                    DispatchQueue.main.async {
                                        errorMessage = userFacingSignUpError(error)
                                        isWorking = false
                                    }
                                }
                                return
                            }
                            isWorking = false
                        }
                    }
                }
            }
        } else {
            isWorking = true
            Auth.auth().signIn(withEmail: trimmedEmail, password: password) { result, error in
                DispatchQueue.main.async {
                    if let error = error {
                        errorMessage = error.localizedDescription
                        isWorking = false
                        return
                    }
                    if let user = result?.user {
                        storedUserName = ""
                        storedUserId = ""
                        hydrateLocalIdentity(for: user)
                    }
                    authState = .authenticated
                    NotificationService.shared.setupFCMToken()
                    isWorking = false
                }
            }
        }
    }

    private func normalizeUserId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidUserId(_ value: String) -> Bool {
        let pattern = "^[a-z0-9_]{3,20}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private func scheduleUserIdCheck(_ value: String) {
        userIdCheckWorkItem?.cancel()

        let normalized = normalizeUserId(value)
        if normalized.isEmpty {
            userIdAvailability = .idle
            return
        }

        if !isValidUserId(normalized) {
            userIdAvailability = .invalid
            return
        }

        userIdAvailability = .checking
        let workItem = DispatchWorkItem { [normalized] in
            checkUserIdAvailability(normalized)
        }
        userIdCheckWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func checkUserIdAvailability(_ value: String) {
        let db = Firestore.firestore()
        db.collection("usernames").document(value).getDocument { snapshot, error in
            DispatchQueue.main.async {
                if value != normalizeUserId(userId) {
                    return
                }

                if error != nil {
                    userIdAvailability = .idle
                    return
                }

                if snapshot?.exists == true {
                    userIdAvailability = .taken
                } else {
                    userIdAvailability = .available
                }
            }
        }
    }

    private var userIdStatusText: String {
        switch userIdAvailability {
        case .idle:
            return "User ID is public. Use 3-20 letters, numbers, or underscore."
        case .checking:
            return "Checking availability..."
        case .available:
            return "User ID is available"
        case .taken:
            return "User ID is taken"
        case .invalid:
            return "User ID must be 3-20 letters, numbers, or underscore."
        }
    }

    private var userIdStatusColor: Color {
        switch userIdAvailability {
        case .available:
            return .green
        case .taken, .invalid:
            return .red
        case .checking:
            return .secondary
        case .idle:
            return .secondary
        }
    }

    private var userIdStatusIcon: String? {
        switch userIdAvailability {
        case .available:
            return "checkmark.circle.fill"
        case .taken, .invalid:
            return "xmark.octagon.fill"
        case .checking:
            return "clock"
        case .idle:
            return nil
        }
    }

    private func reserveUserId(uid: String, userId: String, displayName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let db = Firestore.firestore()
        let handleRef = db.collection("usernames").document(userId)
        let userRef = db.collection("users").document(uid)

        db.runTransaction({ transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(handleRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            if snapshot.exists {
                errorPointer?.pointee = NSError(
                    domain: "GiftMinder",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "User ID is already taken."]
                )
                return nil
            }

            transaction.setData(
                [
                    "uid": uid,
                    "userId": userId,
                    "createdAt": FieldValue.serverTimestamp()
                ],
                forDocument: handleRef
            )

            transaction.setData(
                [
                    "uid": uid,
                    "userId": userId,
                    "displayName": displayName,
                    "name": displayName,
                    "updatedAt": FieldValue.serverTimestamp()
                ],
                forDocument: userRef,
                merge: true
            )

            return nil
        }) { _, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    private func hydrateLocalIdentity(for user: User) {
        lastSyncedAuthUid = user.uid
        let authDisplayName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !authDisplayName.isEmpty {
            storedUserName = authDisplayName
            persistScopedIdentity(uid: user.uid, displayName: authDisplayName, userId: nil)
        }

        let db = Firestore.firestore()
        db.collection("users").document(user.uid).getDocument { snapshot, _ in
            DispatchQueue.main.async {
                let data = snapshot?.data() ?? [:]
                if let displayName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
                    storedUserName = displayName
                    persistScopedIdentity(uid: user.uid, displayName: displayName, userId: nil)
                } else if let name = (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    storedUserName = name
                    persistScopedIdentity(uid: user.uid, displayName: name, userId: nil)
                }

                if let profileUserId = (data["userId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !profileUserId.isEmpty {
                    let normalized = normalizeUserId(profileUserId)
                    storedUserId = normalized
                    persistScopedIdentity(uid: user.uid, displayName: nil, userId: normalized)
                }
            }
        }

        db.collection("usernames")
            .whereField("uid", isEqualTo: user.uid)
            .limit(to: 1)
            .getDocuments { snapshot, _ in
                DispatchQueue.main.async {
                    guard let doc = snapshot?.documents.first else { return }
                    let mappedUserId = (doc.data()["userId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? doc.documentID
                    if !mappedUserId.isEmpty {
                        let normalized = normalizeUserId(mappedUserId)
                        storedUserId = normalized
                        persistScopedIdentity(uid: user.uid, displayName: nil, userId: normalized)
                    }
                }
            }
    }

    private func persistScopedIdentity(uid: String, displayName: String?, userId: String?) {
        let defaults = UserDefaults.standard
        if let displayName {
            defaults.set(displayName, forKey: scopedIdentityKey(uid: uid, suffix: "displayName"))
        }
        if let userId {
            defaults.set(userId, forKey: scopedIdentityKey(uid: uid, suffix: "userId"))
        }
    }

    private func scopedIdentityKey(uid: String, suffix: String) -> String {
        "identity_\(uid)_\(suffix)"
    }

    private func continueAsGuest() {
        errorMessage = nil
        authState = .guest
    }

    private func userFacingSignUpError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "Account could not be completed due to Firestore permissions. Deploy updated firestore.rules and try again."
        }
        return error.localizedDescription
    }
    
    private func handleGoogleSignIn() {
        errorMessage = nil
        // TODO: Implement Google Sign-In
        // 1. Add GoogleSignIn SDK via Swift Package Manager
        // 2. Configure OAuth client in Firebase Console
        // 3. Add URL scheme to Info.plist
        // 4. Use GIDSignIn.sharedInstance.signIn() to get credentials
        // 5. Use Auth.auth().signIn(with: credential) to authenticate with Firebase
        errorMessage = "Google Sign-In not configured yet. Please use email sign-in or guest mode."
    }
}
