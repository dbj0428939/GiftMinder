//
//  ContentView.swift
//  GiftMinder
//
//  Created by David Johnson on 11/7/25.
//

import Foundation
import SwiftUI
import UIKit
import Contacts
import ContactsUI
import MapKit
import CoreLocation
import EventKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseFunctions
import UserNotifications
import StoreKit
internal import Combine

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension Notification.Name {
    static let openShopFromHome = Notification.Name("openShopFromHome")
    static let openContactsFromEvent = Notification.Name("openContactsFromEvent")
}

extension Color {
    // Brand: bright blue gradient
    static let brandStart = Color(red: 0.22, green: 0.46, blue: 0.98)
    static let brandEnd = Color(red: 0.52, green: 0.38, blue: 0.96)
    static let brand = Color(red: 0.32, green: 0.52, blue: 0.98)
    static var brandGradient: LinearGradient { LinearGradient(colors: [brandStart, brandEnd], startPoint: .topLeading, endPoint: .bottomTrailing) }
    static var appBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(UIColor.systemBackground),
                Color.brand.opacity(0.20),
                Color(UIColor.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct AppBackground: View {
    var body: some View {
        Color.appBackgroundGradient
            .ignoresSafeArea()
    }
}

// Navigation wrapper to keep a single-column layout on iPad.
struct AppNavigationView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationView {
            content
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// PreferenceKey used to report vertical scroll offset from list/scroll views
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private func activeProfileScopedKey(_ suffix: String) -> String {
    let uid = Auth.auth().currentUser?.uid ?? "guest"
    return "profile_\(uid)_\(suffix)"
}

private func loadScopedUserDOBTime() -> Double {
    let defaults = UserDefaults.standard
    let key = activeProfileScopedKey("dobTime")
    guard defaults.object(forKey: key) != nil else { return 0 }
    return defaults.double(forKey: key)
}

private func saveScopedUserDOBTime(_ value: Double) {
    UserDefaults.standard.set(value, forKey: activeProfileScopedKey("dobTime"))
}

private func loadScopedUserAnniversaryTime() -> Double {
    let defaults = UserDefaults.standard
    let key = activeProfileScopedKey("anniversaryTime")
    guard defaults.object(forKey: key) != nil else { return 0 }
    return defaults.double(forKey: key)
}

private func saveScopedUserAnniversaryTime(_ value: Double) {
    UserDefaults.standard.set(value, forKey: activeProfileScopedKey("anniversaryTime"))
}

private func loadScopedUserOtherDatesRaw() -> String {
    UserDefaults.standard.string(forKey: activeProfileScopedKey("otherDatesRaw")) ?? "[]"
}

private func saveScopedUserOtherDatesRaw(_ value: String) {
    UserDefaults.standard.set(value, forKey: activeProfileScopedKey("otherDatesRaw"))
}

private struct PersonalDateRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String
    var time: TimeInterval
}

private enum PersonalDateStore {
    static func load(from raw: String) -> [PersonalDateRecord] {
        guard let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PersonalDateRecord].self, from: data)) ?? []
    }

    static func encode(_ entries: [PersonalDateRecord]) -> String? {
        guard let data = try? JSONEncoder().encode(entries) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func merge(reminders: [EKReminder], into existing: [PersonalDateRecord]) -> (entries: [PersonalDateRecord], importedCount: Int) {
        var merged = existing
        var importedCount = 0
        let calendar = Calendar.current

        for reminder in reminders {
            guard let due = reminder.dueDateComponents,
                  let date = calendar.date(from: due) else {
                continue
            }

            let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = title.isEmpty ? "Reminder" : title
            let dayKey = calendar.startOfDay(for: date)

            let exists = merged.contains {
                calendar.isDate(Date(timeIntervalSince1970: $0.time), inSameDayAs: dayKey)
                    && $0.label.caseInsensitiveCompare(label) == .orderedSame
            }

            if exists { continue }
            merged.append(PersonalDateRecord(label: label, time: date.timeIntervalSince1970))
            importedCount += 1
        }

        merged.sort { $0.time < $1.time }
        return (merged, importedCount)
    }
}

private enum ReminderImportError: Error {
    case accessDenied
    case accessFailure(String)
}

private func fetchIncompleteRemindersFromNativeApp(completion: @escaping (Result<[EKReminder], ReminderImportError>) -> Void) {
    let store = EKEventStore()
    let afterAccess: (Bool, Error?) -> Void = { granted, error in
        if let error {
            completion(.failure(.accessFailure(error.localizedDescription)))
            return
        }

        guard granted else {
            completion(.failure(.accessDenied))
            return
        }

        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { reminders in
            completion(.success(reminders ?? []))
        }
    }

    if #available(iOS 17.0, *) {
        store.requestFullAccessToReminders(completion: afterAccess)
    } else {
        store.requestAccess(to: .reminder, completion: afterAccess)
    }
}

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
}

struct OnboardingFlowView: View {
    var onComplete: () -> Void
    @State private var pageIndex = 0
    @State private var hasAnimatedGiftIcon = false
    @State private var giftIconScale: CGFloat = 0.65
    @State private var giftIconOpacity: Double = 0.0
    @State private var giftIconRotation: Double = -18
    @State private var floatingGlow = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to GiftMinder",
            subtitle: "Track important dates, shop gifts, create events, and send invites to your circle.",
            icon: "gift.fill"
        ),
        OnboardingPage(
            title: "Start with Contacts",
            subtitle: "Add people first so birthdays, anniversaries, and shared events stay organized in one place.",
            icon: "person.2.fill"
        ),
        OnboardingPage(
            title: "Set Reminder Timing",
            subtitle: "Choose how many days in advance to be notified in Settings > Notifications.",
            icon: "bell.badge.fill"
        ),
        OnboardingPage(
            title: "Use Home as Your Hub",
            subtitle: "From Home, add contacts, create all kinds of events, send invites, and review responses.",
            icon: "house.fill"
        ),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.brandStart.opacity(0.95),
                    Color.brand.opacity(0.85),
                    Color.brandEnd.opacity(0.95),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 10)
                .offset(x: -130, y: -240)
                .scaleEffect(floatingGlow ? 1.06 : 0.94)

            Circle()
                .fill(Color.purple.opacity(0.25))
                .frame(width: 280, height: 280)
                .blur(radius: 14)
                .offset(x: 140, y: 260)
                .scaleEffect(floatingGlow ? 0.94 : 1.08)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.12), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .ignoresSafeArea()

            VStack(spacing: 18) {
                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, page in
                        VStack(spacing: 18) {
                            Spacer()
                            Image(systemName: page.icon)
                                .font(.system(size: 56, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(20)
                                .background(Circle().fill(Color.white.opacity(0.14)))
                                .shadow(color: Color.white.opacity(0.22), radius: 12, x: 0, y: 4)
                                .scaleEffect(idx == 0 ? giftIconScale : 1)
                                .opacity(idx == 0 ? giftIconOpacity : 1)
                                .rotationEffect(.degrees(idx == 0 ? giftIconRotation : 0))
                                .onAppear {
                                    if idx == 0 && !hasAnimatedGiftIcon {
                                        hasAnimatedGiftIcon = true
                                        withAnimation(.spring(response: 0.58, dampingFraction: 0.62)) {
                                            giftIconScale = 1.0
                                            giftIconOpacity = 1.0
                                            giftIconRotation = 0
                                        }
                                    }
                                }

                            Text(page.title)
                                .font(.title2.weight(.bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Text(page.subtitle)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Spacer()
                        }
                        .tag(idx)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))

                VStack(spacing: 10) {
                    if pageIndex < pages.count - 1 {
                        Button("Next") {
                            withAnimation(.easeInOut) {
                                pageIndex += 1
                            }
                        }
                        .font(.headline)
                        .foregroundColor(Color.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Button("Get Started") {
                            onComplete()
                        }
                        .font(.headline)
                        .foregroundColor(Color.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button("Skip") {
                        onComplete()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                floatingGlow = true
            }
        }
    }
}

struct ProductsView: View {
    @EnvironmentObject var contactStore: ContactStore
    @State private var products: [Product] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var showStores = false
    @State private var showLocal = false
    @State private var showFilter = false
    @State private var showCategoryBubble = false
    @State private var pressedCategory: String? = nil
    @State private var handBounce = false
    @State private var menuMode: ShopMenuMode = .root
    @State private var showShopForPicker = false
    @State private var selectedContactId: UUID? = nil // nil == Me
    @State private var selectedStore: String? = nil
    private let api = ProductAPI()
    private let storeNames: [String] = ["Nike", "Adidas", "Apple", "Target", "Best Buy", "Etsy", "Amazon"]

    private enum ShopMenuMode {
        case root
        case categories
    }

    private var categories: [String] {
        Array(Set(products.map { $0.category })).sorted()
    }

    private var filteredProducts: [Product] {
        var results = products
        if let cat = selectedCategory {
            results = results.filter { $0.category == cat }
        }

        if !searchText.isEmpty {
            results = results.filter { p in
                p.title.localizedCaseInsensitiveContains(searchText)
                    || p.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        return results
    }

    private var selectedRecipientName: String {
        if let id = selectedContactId,
           let contact = contactStore.contacts.first(where: { $0.id == id }) {
            return contact.name
        }
        return "Me"
    }

    var body: some View {
        AppNavigationView {
            ZStack(alignment: .topTrailing) {
                AppBackground()
                VStack(spacing: 14) {
                    // Top search bar (mic inside) and filter button
                    HStack(spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(Color.brand.opacity(0.8))

                            TextField("Search shop items...", text: $searchText)
                                .textFieldStyle(PlainTextFieldStyle())

                            Button(action: { /* voice/search action */ }) {
                                Image(systemName: "mic.fill")
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 7)
                            .background(Circle().fill(Color(UIColor.tertiarySystemBackground)))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.brand.opacity(0.14), lineWidth: 1)
                        )

                        Button(action: { toggleCategoryBubble() }) {
                            Image(systemName: "line.horizontal.3.decrease")
                                .foregroundColor(.primary)
                                .padding(12)
                                .background(Circle().fill(Color(UIColor.tertiarySystemBackground)))
                        }
                    }
                    .padding(.horizontal)

                    // Shop For selector (moved below search bar) - dynamic text when contact selected
                    Button(action: { showShopForPicker = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "gift.fill")
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Circle().fill(Color.white.opacity(0.12)))

                            if let id = selectedContactId, let c = contactStore.contacts.first(where: { $0.id == id }) {
                                Text("Shopping for \(c.name)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            } else {
                                Text("Shop for me")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }

                            Spacer()

                            // display current recipient avatar
                            if let id = selectedContactId, let c = contactStore.contacts.first(where: { $0.id == id }) {
                                if let data = c.photoData, let ui = UIImage(data: data) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 30, height: 30)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 30, height: 30)
                                        .overlay(Text(initials(for: c.name)).font(.subheadline).foregroundColor(.primary))
                                }
                            } else {
                                if let ui = loadUserProfileImage() {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 30, height: 30)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 30, height: 30)
                                        .overlay(Image(systemName: "person.fill").foregroundColor(.white).font(.system(size: 16)))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(LinearGradient(colors: [Color.brandStart, Color.brandEnd], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .padding(.horizontal)
                    }

                    // Results
                    if filteredProducts.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)

                            Text("No Results Found")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("Try another keyword, remove a filter, or choose a different recipient.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        List(filteredProducts) { product in
                            NavigationLink(
                                destination: ProductDetailView(
                                    product: product,
                                    recipientName: selectedRecipientName,
                                    preferredStore: selectedStore
                                )
                            ) {
                                ProductRowView(product: product)
                            }
                        }
                        .listStyle(PlainListStyle())
                        .scrollContentBackground(.hidden)
                        .coordinateSpace(name: "productsList")
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("productsList")).minY)
                        })
                    }
                }

                if showCategoryBubble {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { closeCategoryBubble() }

                    categoryBubbleMenu
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: menuMode == .root ? .topTrailing : .center)
                        .padding(.trailing, menuMode == .root ? 18 : 0)
                        .padding(.top, menuMode == .root ? 62 : 0)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .simultaneousGesture(TapGesture().onEnded { UIApplication.shared.endEditing() })
            .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { _ in
                UIApplication.shared.endEditing()
            })
            .sheet(isPresented: $showStores) {
                StorePickerSheetView(selectedStore: $selectedStore, storeNames: storeNames)
            }
            .sheet(isPresented: $showShopForPicker) {
                AppNavigationView {
                    VStack(spacing: 12) {
                        // Me
                        Button(action: {
                            selectedContactId = nil
                            showShopForPicker = false
                        }) {
                            HStack(spacing: 12) {
                                if let ui = loadUserProfileImage() {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 46, height: 46)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 46, height: 46)
                                        .overlay(Image(systemName: "person.fill").foregroundColor(Color.brand))
                                }

                                VStack(alignment: .leading) {
                                    Text("Me").font(.headline)
                                    Text("Shop for yourself").font(.caption).foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding()
                        }

                        Divider().padding(.horizontal)

                        // Contacts list
                        List {
                            ForEach(contactStore.contacts) { c in
                                Button(action: {
                                    selectedContactId = c.id
                                    showShopForPicker = false
                                }) {
                                    HStack(spacing: 12) {
                                        if let d = c.photoData, let ui = UIImage(data: d) {
                                            Image(uiImage: ui)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 44, height: 44)
                                                .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(Color.gray.opacity(0.2))
                                                .frame(width: 44, height: 44)
                                                .overlay(Text(initials(for: c.name)).font(.subheadline).foregroundColor(Color.brand))
                                        }

                                        VStack(alignment: .leading) {
                                            Text(c.name).font(.headline)
                                            Text(c.relationship.rawValue).font(.caption).foregroundColor(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }
                    .navigationTitle("Choose Recipient")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showShopForPicker = false } } }
                }
                .tint(Color.brand)
            }
            .sheet(isPresented: $showLocal) {
                LocalBusinessSheetView()
            }
            .sheet(isPresented: $showFilter) {
                ProductsFilterView(isPresented: $showFilter, categories: ["Stores","Support Local Shops"] + categories, selectedCategory: $selectedCategory, showStores: $showStores, showLocal: $showLocal)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openShopFromHome)) { notification in
                if let rawStore = notification.userInfo?["store"] as? String {
                    let trimmed = rawStore.trimmingCharacters(in: .whitespacesAndNewlines)
                    selectedStore = trimmed.isEmpty ? nil : trimmed
                }

                if let rawContactId = notification.userInfo?["contactId"] as? String,
                   let uuid = UUID(uuidString: rawContactId) {
                    selectedContactId = uuid
                } else {
                    selectedContactId = nil
                }

                selectedCategory = nil
            }
            
            .onAppear(perform: loadProducts)
        }
    }

    private var categoryBubbleMenu: some View {
        let itemCount = menuItemCount
        let shouldExpand = itemCount > 5
        let maxHeight: CGFloat = min(UIScreen.main.bounds.height * 0.7, 520)
        let isCategories = menuMode == .categories
        let bubbleWidth: CGFloat = isCategories ? 300 : (shouldExpand ? 240 : 190)
        let bubbleHeight: CGFloat = isCategories ? maxHeight : (shouldExpand ? min(UIScreen.main.bounds.height * 0.6, 420) : 190)

        return ZStack {
            Group {
                if isCategories {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.brand.opacity(0.22), lineWidth: 1)
                        )
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(Color.brand.opacity(0.22), lineWidth: 1))
                }
            }
            .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)

            VStack(spacing: 12) {
                if menuMode != .root {
                    HStack(spacing: 8) {
                        Button(action: { withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) { menuMode = .root } }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color.brand)

                        Text(menuTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .center, spacing: isCategories ? 12 : 10) {
                        switch menuMode {
                        case .root:
                            menuActionButton(title: "Stores", icon: "bag") { openStoresPicker() }
                            menuActionButton(title: "Categories", icon: "square.grid.2x2") { menuMode = .categories }
                            menuActionButton(title: "Local Shops", icon: "house") { openLocalShops() }
                        case .categories:
                            categoryButton(title: "All", value: nil)
                            ForEach(categories, id: \.self) { category in
                                categoryButton(title: category.capitalized, value: category)
                            }
                        }
                    }
                    .padding(.horizontal, isCategories ? 16 : 10)
                    .padding(.vertical, isCategories ? 10 : 6)
                    .padding(.top, menuMode == .root ? 22 : 10)
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                if shouldExpand && menuMode != .root {
                    Image(systemName: "hand.point.down.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.brand.opacity(0.7))
                        .offset(y: handBounce ? 6 : 0)
                        .opacity(handBounce ? 1 : 0.5)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                handBounce = true
                            }
                        }
                }
            }
        }
        .frame(width: bubbleWidth, height: bubbleHeight)
    }

    private var menuTitle: String {
        switch menuMode {
        case .root:
            return ""
        case .categories:
            return "Categories"
        }
    }

    private var menuItemCount: Int {
        switch menuMode {
        case .root:
            return 3
        case .categories:
            return categories.count + 1
        }
    }

    private var shouldCenterBubble: Bool {
        switch menuMode {
        case .categories:
            return true
        default:
            return false
        }
    }

    private func menuActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color(UIColor.secondarySystemBackground).opacity(0.9)))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func categoryButton(title: String, value: String?) -> some View {
        let isSelected = selectedCategory == value
        return Button(action: { applyCategory(value) }) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Group {
                        if isSelected {
                            Capsule().fill(Color.brandGradient)
                        } else {
                            Capsule().fill(Color(UIColor.secondarySystemBackground).opacity(0.9))
                        }
                    }
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .scaleEffect(pressedCategory == title ? 0.94 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pressedCategory)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func toggleCategoryBubble() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            if showCategoryBubble == false { menuMode = .root }
            showCategoryBubble.toggle()
        }
    }

    private func closeCategoryBubble() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showCategoryBubble = false
            menuMode = .root
        }
    }

    private func applyCategory(_ value: String?) {
        let pressedLabel = value ?? "All"
        pressedCategory = pressedLabel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            pressedCategory = nil
            selectedCategory = value
            closeCategoryBubble()
        }
    }

    private func openStoresPicker() {
        pressedCategory = "Stores"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            pressedCategory = nil
            showStores = true
            closeCategoryBubble()
        }
    }

    private func openLocalShops() {
        pressedCategory = "Local Shops"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            pressedCategory = nil
            showLocal = true
            closeCategoryBubble()
        }
    }

    private func loadProducts() {
        guard products.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        api.getAllProducts { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let products):
                    self.products = products
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first.map { String($0.prefix(1)) } ?? ""
        let last = parts.count > 1 ? String(parts.last!.prefix(1)) : ""
        return (first + last).uppercased()
    }

    private func loadUserProfileImage() -> UIImage? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        if let data = UserDefaults.standard.data(forKey: "userProfileImage_\(uid)"), let ui = UIImage(data: data) {
            return ui
        }
        return nil
    }
}

// MARK: - Models

enum Relationship: String, CaseIterable, Codable {
    case family = "Family"
    case friend = "Friend"
    case colleague = "Colleague"
    case partner = "Partner"
    case other = "Other"

    var icon: String {
        switch self {
        case .family: return "house.fill"
        case .friend: return "person.2.fill"
        case .colleague: return "briefcase.fill"
        case .partner: return "heart.fill"
        case .other: return "person.circle.fill"
        }
    }
}

struct GiftHistory: Identifiable, Codable {
    var id = UUID()
    let giftName: String
    let giftDescription: String?
    let price: Double?
    let purchaseDate: Date
    let occasion: String
    let retailer: String?
    let rating: Int?
    let notes: String?

    init(
        giftName: String, giftDescription: String? = nil, price: Double? = nil, occasion: String,
        retailer: String? = nil, rating: Int? = nil, notes: String? = nil
    ) {
        self.giftName = giftName
        self.giftDescription = giftDescription
        self.price = price
        self.purchaseDate = Date()
        self.occasion = occasion
        self.retailer = retailer
        self.rating = rating
        self.notes = notes
    }
}

struct ContactEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var isYearKnown: Bool

    init(title: String, date: Date, isYearKnown: Bool = false) {
        self.title = title
        self.date = date
        self.isYearKnown = isYearKnown
    }
}

struct Contact: Identifiable, Codable {
    var id = UUID()
    var sourceIdentifier: String?
    var phoneNumber: String?
    var name: String
    var dateOfBirth: Date
    var isBirthYearKnown: Bool
    var hasBirthday: Bool
    var anniversaryDate: Date?
    var isAnniversaryYearKnown: Bool
    var customEvents: [ContactEvent]
    var relationship: Relationship
    var interests: [String]
    var notes: String
    var photoData: Data?
    var giftHistory: [GiftHistory]
    var createdAt: Date
    var updatedAt: Date

    init(
        name: String, dateOfBirth: Date, relationship: Relationship, interests: [String] = [],
        notes: String = "", isBirthYearKnown: Bool = false, anniversaryDate: Date? = nil,
        isAnniversaryYearKnown: Bool = false, customEvents: [ContactEvent] = [],
        hasBirthday: Bool = true, sourceIdentifier: String? = nil, phoneNumber: String? = nil
    ) {
        self.sourceIdentifier = sourceIdentifier
        self.phoneNumber = phoneNumber
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.isBirthYearKnown = isBirthYearKnown
        self.hasBirthday = hasBirthday
        self.anniversaryDate = anniversaryDate
        self.isAnniversaryYearKnown = isAnniversaryYearKnown
        self.customEvents = customEvents
        self.relationship = relationship
        self.interests = interests
        self.notes = notes
        self.giftHistory = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var age: Int {
        guard isBirthYearKnown else { return 0 }
        return Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
    }

    var nextBirthday: Date {
        guard hasBirthday else { return .distantFuture }
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)

        var nextBirthday =
            calendar.date(
                byAdding: .year, value: currentYear - calendar.component(.year, from: dateOfBirth),
                to: dateOfBirth) ?? dateOfBirth

        if nextBirthday < now {
            nextBirthday = calendar.date(byAdding: .year, value: 1, to: nextBirthday) ?? dateOfBirth
        }

        return nextBirthday
    }

    var daysUntilBirthday: Int {
        guard hasBirthday else { return Int.max }
        return Calendar.current.dateComponents([.day], from: Date(), to: nextBirthday).day ?? 0
    }
}

struct Gift: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let price: PriceRange
    let category: GiftCategory
    let interests: [String]
    let retailer: String
    let imageURL: String?
    let isSponsored: Bool
    let rating: Double

    init(
        name: String, description: String, price: PriceRange, category: GiftCategory,
        interests: [String], retailer: String, isSponsored: Bool = false, rating: Double = 4.0,
        imageURL: String? = nil
    ) {
        self.name = name
        self.description = description
        self.price = price
        self.category = category
        self.interests = interests.map { $0.lowercased() }
        self.retailer = retailer
        self.isSponsored = isSponsored
        self.rating = rating
        self.imageURL = imageURL
    }

    func matchScore(for contact: Contact) -> Double {
        var score: Double = 0

        let matchingInterests = interests.filter { interest in
            contact.interests.contains { contactInterest in
                contactInterest.lowercased().contains(interest)
                    || interest.contains(contactInterest.lowercased())
            }
        }
        score += Double(matchingInterests.count) * 3.0
        score += rating * 0.5

        return score
    }

    var formattedPrice: String {
        switch price {
        case .exact(let amount):
            return "$\(String(format: "%.2f", amount))"
        case .range(let min, let max):
            return "$\(String(format: "%.0f", min)) - $\(String(format: "%.0f", max))"
        case .free:
            return "Free"
        }
    }
}

// MARK: - Contact Gift Model (Firestore)
struct ContactGift: Identifiable, Codable, Equatable {
    var id: String  // Firestore document ID
    let title: String
    let price: Double?
    let url: String?
    let status: String  // "wishlist" or "purchased"
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, price, url, status, notes, createdAt, updatedAt
    }

    init(id: String, title: String, price: Double? = nil, url: String? = nil, status: String = "wishlist", notes: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.price = price
        self.url = url
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func == (lhs: ContactGift, rhs: ContactGift) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.updatedAt == rhs.updatedAt
    }
}

enum PriceRange {
    case exact(Double)
    case range(Double, Double)
    case free

    var minPrice: Double {
        switch self {
        case .exact(let amount): return amount
        case .range(let min, _): return min
        case .free: return 0
        }
    }

    var maxPrice: Double {
        switch self {
        case .exact(let amount): return amount
        case .range(_, let max): return max
        case .free: return 0
        }
    }
}
// MARK: - Models
// MARK: - Models
enum GiftCategory: String, CaseIterable, Codable {
    case electronics = "Electronics"
    case books = "Books"
    case clothing = "Clothing"
    case homeDecor = "Home & Decor"
    case sports = "Sports & Fitness"
    case beauty = "Beauty & Personal Care"
    case food = "Food & Beverage"
    case jewelry = "Jewelry & Accessories"
    case art = "Art & Crafts"
    case music = "Music"

    var icon: String {
        switch self {
        case .electronics: return "iphone"
        case .books: return "book"
        case .clothing: return "tshirt"
        case .homeDecor: return "house"
        case .sports: return "sportscourt"
        case .beauty: return "paintbrush"
        case .food: return "fork.knife"
        case .jewelry: return "crown"
        case .art: return "paintpalette"
        case .music: return "music.note"
        }
    }
}

// MARK: - ViewModels

@MainActor
class ContactStore: ObservableObject {
    @Published var contacts: [Contact] = [] {
        didSet {
            guard !isHydratingContacts else { return }
            persistContactsForCurrentScope()
        }
    }
    private let birthYearScrubKey = "didScrubBirthYearsV1"
    private let legacyContactsKey = "contacts"
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var activeContactsScopeKey: String = ""
    private var isHydratingContacts = false

    init() {
        activeContactsScopeKey = contactsStorageKeyForCurrentUser()
        hydrateContactsForCurrentScope()
        scrubBirthYearsIfNeeded()

        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor in
                self?.handleAuthScopeChangeIfNeeded()
            }
        }
    }

    deinit {
        if let authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
    }

    func addContact(_ contact: Contact) {
        contacts.append(contact)
    }

    func deleteContact(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
    }

    func searchContacts(query: String) -> [Contact] {
        if query.isEmpty {
            return contacts
        }
        return contacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains(query)
                || contact.interests.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func contactsWithUpcomingBirthdays(within days: Int = 30) -> [Contact] {
        return contacts.filter { $0.hasBirthday && $0.daysUntilBirthday <= days && $0.daysUntilBirthday >= 0 }
            .sorted { $0.daysUntilBirthday < $1.daysUntilBirthday }
    }

    private func scrubBirthYearsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: birthYearScrubKey) else { return }
        scrubBirthYears()
        defaults.set(true, forKey: birthYearScrubKey)
    }

    private func scrubBirthYears() {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        contacts = contacts.map { contact in
            var updated = contact
            guard updated.hasBirthday else { return updated }
            updated.isBirthYearKnown = false
            updated.dateOfBirth = normalizedMonthDay(from: updated.dateOfBirth, year: currentYear)
            return updated
        }

        persistContactsForCurrentScope()
    }

    private func normalizedMonthDay(from date: Date, year: Int) -> Date {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.month, .day], from: date)
        comps.year = year
        if let normalized = calendar.date(from: comps) {
            return normalized
        }

        let month = comps.month ?? 1
        let day = comps.day ?? 1
        var safeComps = DateComponents()
        safeComps.year = year
        safeComps.month = month
        let reference = calendar.date(from: safeComps) ?? Date()
        let dayRange = calendar.range(of: .day, in: .month, for: reference) ?? 1..<29
        safeComps.day = min(day, dayRange.count)
        return calendar.date(from: safeComps) ?? Date()
    }

    private func handleAuthScopeChangeIfNeeded() {
        let newScopeKey = contactsStorageKeyForCurrentUser()
        guard newScopeKey != activeContactsScopeKey else { return }
        activeContactsScopeKey = newScopeKey
        hydrateContactsForCurrentScope()
        scrubBirthYearsIfNeeded()
    }

    private func contactsStorageKeyForCurrentUser() -> String {
        let uid = Auth.auth().currentUser?.uid.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = (uid?.isEmpty == false) ? uid! : "guest"
        return "contacts_\(scope)"
    }

    private func hydrateContactsForCurrentScope() {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()

        if let data = defaults.data(forKey: activeContactsScopeKey),
           let decoded = try? decoder.decode([Contact].self, from: data) {
            isHydratingContacts = true
            contacts = decoded
            isHydratingContacts = false
            return
        }

        if let legacyData = defaults.data(forKey: legacyContactsKey),
           let decodedLegacy = try? decoder.decode([Contact].self, from: legacyData) {
            isHydratingContacts = true
            contacts = decodedLegacy
            isHydratingContacts = false
            persistContactsForCurrentScope()
            defaults.removeObject(forKey: legacyContactsKey)
            return
        }

        isHydratingContacts = true
        contacts = []
        isHydratingContacts = false
    }

    private func persistContactsForCurrentScope() {
        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(contacts) {
            defaults.set(encoded, forKey: activeContactsScopeKey)
        }
    }
}

@MainActor
class GiftService: ObservableObject {
    @Published var availableGifts: [Gift] = []

    private let productAPI = ProductAPI()

    init() {
        // populate quick sample data so UI isn't empty while API loads
        loadSampleGifts()
        fetchProductsFromAPI()
    }

    func getRecommendations(for contact: Contact) -> [Gift] {
        return
            availableGifts
            .map { gift in (gift, gift.matchScore(for: contact)) }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    func searchGifts(query: String, category: GiftCategory? = nil) -> [Gift] {
        var results = availableGifts

        if let category = category {
            results = results.filter { $0.category == category }
        }

        if !query.isEmpty {
            results = results.filter { gift in
                gift.name.localizedCaseInsensitiveContains(query)
                    || gift.description.localizedCaseInsensitiveContains(query)
                    || gift.interests.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }

        return results.sorted { $0.isSponsored && !$1.isSponsored }
    }
    private func loadSampleGifts() {
        availableGifts = [
            Gift(
                name: "Wireless Bluetooth Headphones",
                description:
                    "Premium noise-cancelling wireless headphones with 30-hour battery life",
                price: .range(50, 200),
                category: .electronics,
                interests: ["music", "technology", "travel"],
                retailer: "TechWorld",
                isSponsored: true,
                rating: 4.3
            ),
            Gift(
                name: "Smart Fitness Watch",
                description: "Track your health and fitness with this feature-packed smartwatch",
                price: .range(100, 400),
                category: .electronics,
                interests: ["fitness", "technology", "health"],
                retailer: "FitTech",
                rating: 4.1
            ),
            Gift(
                name: "Photography Guide Book",
                description: "Comprehensive guide to mastering digital photography",
                price: .exact(29.99),
                category: .books,
                interests: ["photography", "art", "learning"],
                retailer: "BookHaven",
                rating: 4.5
            ),
            Gift(
                name: "Yoga Mat Premium Set",
                description: "High-quality yoga mat with accessories for home practice",
                price: .range(30, 80),
                category: .sports,
                interests: ["yoga", "fitness", "wellness"],
                retailer: "YogaLife",
                rating: 4.4
            ),
            Gift(
                name: "Gourmet Coffee Sample Set",
                description: "Selection of premium coffee beans from around the world",
                price: .range(20, 50),
                category: .food,
                interests: ["coffee", "gourmet", "tasting"],
                retailer: "CoffeeRoasters",
                rating: 4.3
            ),
            Gift(
                name: "Art Supply Kit",
                description: "Complete set of high-quality art supplies for drawing and painting",
                price: .range(40, 100),
                category: .art,
                interests: ["art", "painting", "creativity"],
                retailer: "ArtSupplies",
                rating: 4.5
            ),
            Gift(
                name: "Hiking Backpack",
                description: "Durable and comfortable backpack perfect for day hikes",
                price: .range(60, 150),
                category: .sports,
                interests: ["hiking", "outdoor", "travel"],
                retailer: "OutdoorGear",
                rating: 4.7
            ),
            Gift(
                name: "Cooking Class Voucher",
                description: "Learn new culinary skills with professional chef instruction",
                price: .range(75, 150),
                category: .food,
                interests: ["cooking", "learning", "culinary"],
                retailer: "CulinarySchool",
                isSponsored: true,
                rating: 4.8
            ),
        ]
    }

    private func fetchProductsFromAPI() {
        productAPI.getAllProducts { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let products):
                    // map Product -> Gift
                    let mapped: [Gift] = products.map { p in
                        Gift(
                            name: p.title,
                            description: p.description,
                            price: .exact(p.price),
                            category: Self.mapCategory(from: p.category),
                            interests: [],
                            retailer: "",
                            isSponsored: false,
                            rating: 4.0,
                            imageURL: p.image
                        )
                    }

                    // replace available gifts with API results
                    self.availableGifts = mapped
                case .failure:
                    // keep sample gifts as fallback
                    break
                }
            }
        }
    }

    private static func mapCategory(from raw: String) -> GiftCategory {
        let s = raw.lowercased()
        if s.contains("elect") { return .electronics }
        if s.contains("jewel") { return .jewelry }
        if s.contains("book") { return .books }
        if s.contains("cloth") || s.contains("men") || s.contains("women") { return .clothing }
        if s.contains("sport") || s.contains("hike") { return .sports }
        if s.contains("food") || s.contains("coffee") { return .food }
        if s.contains("beauty") || s.contains("personal") { return .beauty }
        if s.contains("art") { return .art }
        if s.contains("music") { return .music }
        return .homeDecor
    }
}

// MARK: - Main App

struct ContentView: View {
    @Binding var animateEntrance: Bool
    @StateObject private var contactStore = ContactStore()
    @StateObject private var giftService = GiftService()
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var selectedTab: Tab = .home
    @State private var showMainContent: Bool = false
    @State private var showTabBar: Bool = false
    @State private var tabBarHidden: Bool = false
    @State private var selectedContactForDetail: Contact? = nil
    @State private var showContactDetailFromNotification: Bool = false
    @AppStorage("themeMode") private var themeModeRaw: String = ThemeMode.system.rawValue
    @AppStorage("hasCompletedOnboardingV1") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    enum Tab {
        case home, network, products, lists, profile, settings
    }

    @Namespace private var animationNamespace
    @State private var lastScrollOffset: CGFloat = 0

    var body: some View {
        let preferred: ColorScheme? = ThemeMode(rawValue: themeModeRaw)?.colorScheme

        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    HomeView()
                        .environmentObject(contactStore)
                        .environmentObject(giftService)
                case .network:
                    ContactsView()
                        .environmentObject(contactStore)
                        .environmentObject(giftService)
                case .products:
                    ProductsView()
                        .environmentObject(contactStore)
                        .environmentObject(giftService)
                case .lists:
                    PlansHubView()
                        .environmentObject(contactStore)
                        .environmentObject(giftService)
                case .profile:
                    ProfileView()
                        .environmentObject(contactStore)
                        .environmentObject(giftService)
                case .settings:
                    SettingsView()
                }
            }
            .animation(.easeInOut, value: selectedTab)
            .opacity(showMainContent ? 1 : 0)
            .offset(y: showMainContent ? 0 : 18)
            .scaleEffect(showMainContent ? 1 : 0.995)
            .padding(.bottom, 16)
            .safeAreaInset(edge: .bottom) {
                Color.appBackgroundGradient.frame(height: 65)
            }
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                let delta = offset - lastScrollOffset
                let threshold: CGFloat = 8
                if delta < -threshold {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tabBarHidden = true }
                } else if delta > threshold {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tabBarHidden = false }
                }
                lastScrollOffset = offset
            }

            Color(UIColor.systemBackground)
                .frame(height: 90)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)

            BottomBar(selectedTab: $selectedTab, namespace: animationNamespace, isHidden: $tabBarHidden)
                .padding(.bottom, 24)
                .opacity(showTabBar ? 1 : 0)
                .offset(y: showTabBar ? 0 : 24)
            
            // Contact detail modal from notification
            if let contact = selectedContactForDetail, showContactDetailFromNotification {
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showContactDetailFromNotification = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    selectedContactForDetail = nil
                                }
                            }
                        }
                    
                    ContactDetailView(contact: contact)
                        .environmentObject(contactStore)
                        .environmentObject(giftService)
                        .transition(.move(edge: .trailing))
                }
                .ignoresSafeArea()
            }
        }
        .background(AppBackground())
        .preferredColorScheme(preferred)
        .onAppear {
            startEntranceIfNeeded()
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: animateEntrance) { new in
            if new {
                startEntranceIfNeeded()
            }
        }
        .onChange(of: notificationManager.shouldNavigateToContactDetail) { shouldNavigate in
            if shouldNavigate, let contactId = notificationManager.selectedContactId {
                // Find the contact in the store
                if let contact = contactStore.contacts.first(where: { $0.id == contactId }) {
                    selectedContactForDetail = contact
                    showContactDetailFromNotification = true
                }
                notificationManager.resetContactNavigation()
            }
        }
        .onChange(of: notificationManager.shouldNavigateToNetworkEvent) { shouldNavigate in
            if shouldNavigate {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .home
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openShopFromHome)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .products
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openContactsFromEvent)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .network
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingFlowView {
                hasCompletedOnboarding = true
                showOnboarding = false
            }
        }
    }

    private func startEntranceIfNeeded() {
        guard !showMainContent else { return }
        // staggered entrance: main content then tab bar
        withAnimation(.interpolatingSpring(stiffness: 220, damping: 26)) {
            showMainContent = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                showTabBar = true
            }
        }
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: ContentView.Tab
    var namespace: Namespace.ID
    @Binding var isHidden: Bool

    @GestureState private var dragOffset: CGSize = .zero
    private let hideThreshold: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            HStack { Spacer()

                HStack(spacing: 0) {
                    TabBarItem(tab: .home, selectedTab: $selectedTab, icon: "house.fill", assetName: "tab_home", namespace: namespace)
                    TabBarItem(tab: .network, selectedTab: $selectedTab, icon: "person.2.fill", assetName: nil, namespace: namespace)
                    TabBarItem(tab: .products, selectedTab: $selectedTab, icon: "gift.fill", assetName: nil, namespace: namespace)
                    TabBarItem(tab: .lists, selectedTab: $selectedTab, icon: "list.bullet.rectangle.fill", assetName: nil, namespace: namespace)
                    TabBarItem(tab: .profile, selectedTab: $selectedTab, icon: "person.crop.circle", assetName: "tab_profile", namespace: namespace)
                    TabBarItem(tab: .settings, selectedTab: $selectedTab, icon: "gearshape.fill", assetName: "tab_settings", namespace: namespace)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    VisualEffectBlur(blurStyle: .systemMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
                .shadow(color: Color.black.opacity(0.22), radius: 20, x: 0, y: 10)
                .frame(width: max(geo.size.width - 24, 340))
                .scaleEffect(isHidden ? 0.98 : 1.0)
                .offset(y: isHidden ? 120 : 0)
                .offset(y: dragOffset.height)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isHidden)
                .gesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .local)
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            let vertical = value.translation.height
                            if vertical > hideThreshold {
                                // swipe down -> hide
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isHidden = true }
                            } else if vertical < -hideThreshold {
                                // swipe up -> show
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isHidden = false }
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isHidden = isHidden }
                            }
                        }
                )

                Spacer() }
        }
        .frame(height: 56)
        .padding(.horizontal, 0)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isHidden = false }
        }
    }
}

struct TabBarItem: View {
    let tab: ContentView.Tab
    @Binding var selectedTab: ContentView.Tab
    let icon: String
    var assetName: String? = nil
    var namespace: Namespace.ID

    var body: some View {
        Button(action: { withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { selectedTab = tab } }) {
            ZStack {
                if selectedTab == tab {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.brandGradient)
                        .frame(width: 50, height: 34)
                        .matchedGeometryEffect(id: "tabBackground", in: namespace)
                        .shadow(color: Color.brandStart.opacity(0.18), radius: 8, x: 0, y: 6)
                }

                Group {
                    if let asset = assetName, let ui = UIImage(named: asset) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                }
                .foregroundColor(selectedTab == tab ? .white : .primary)
                .scaleEffect(selectedTab == tab ? 1.22 : 1.0)
                .rotationEffect(.degrees(selectedTab == tab ? 6 : 0))
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .buttonStyle(PlainButtonStyle())
    }
}

// Floating bottom bar with a soft material background. Hides on scroll via `isHidden`.
struct BottomBar: View {
    @Binding var selectedTab: ContentView.Tab
    var namespace: Namespace.ID
    @Binding var isHidden: Bool
    @State private var barBounce: Bool = false

    private func makeButton(tab: ContentView.Tab, icon: String, label: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(selectedTab == tab ? .white : Color.primary.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
            .background(
                Group {
                    if selectedTab == tab {
                        Circle()
                            .fill(Color.brandGradient)
                            .shadow(color: Color.brandStart.opacity(0.28), radius: 8, x: 0, y: 6)
                    } else {
                        Circle()
                            .fill(Color.clear)
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    var body: some View {
        HStack(spacing: 6) {
            makeButton(tab: .home, icon: "house.fill", label: "Home")
            makeButton(tab: .network, icon: "person.2.fill", label: "Network")
            makeButton(tab: .products, icon: "gift.fill", label: "Shop")
            makeButton(tab: .lists, icon: "list.bullet.rectangle.fill", label: "Plans")
            makeButton(tab: .profile, icon: "person.crop.circle", label: "Profile")
            makeButton(tab: .settings, icon: "gearshape.fill", label: "Settings")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            VisualEffectBlur(blurStyle: .systemUltraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.brand.opacity(0.2), lineWidth: 1)
                )
        )
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
        .frame(maxWidth: .infinity)
        .scaleEffect(barBounce ? 1.02 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: barBounce)
        .onChange(of: selectedTab) { _ in
            barBounce = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                barBounce = false
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 0)
        .offset(y: isHidden ? 120 : 0)
        .opacity(isHidden ? 0 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isHidden)
    }
}

// Small VisualEffectBlur to provide material background on macOS/iOS
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}

struct PublicPost: Identifiable {
    let id: String
    let authorName: String
    let title: String
    let body: String
    let tags: [String]
    let postType: String
    let productTitle: String?
    let imageData: String?
    let createdAt: Date
    let likeCount: Int
    let commentCount: Int
}

struct PublicComment: Identifiable {
    let id: String
    let authorName: String
    let text: String
    let createdAt: Date
}

@MainActor
final class FeedService: ObservableObject {
    @Published var posts: [PublicPost] = []
    @Published var comments: [String: [PublicComment]] = [:]
    @Published var hasMoreComments: [String: Bool] = [:]

    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var isLoaded = false
    private var commentPageSize = 6

    func loadPosts() {
        guard !isLoaded else { return }
        isLoaded = true
        refreshPosts()
    }

    func refreshPosts() {
        db.collection("publicPosts")
            .order(by: "createdAt", descending: true)
            .getDocuments { [weak self] snapshot, error in
                guard let self else { return }
                if let snapshot = snapshot {
                    let mapped = snapshot.documents.compactMap { self.mapPost(from: $0) }
                    DispatchQueue.main.async {
                        self.posts = mapped.isEmpty ? self.samplePosts() : mapped
                    }
                } else {
                    DispatchQueue.main.async {
                        self.posts = self.samplePosts()
                    }
                    if let error {
                        print("Failed to load public posts: \(error)")
                    }
                }
            }
    }

    func loadComments(for postId: String) {
        db.collection("publicPosts")
            .document(postId)
            .collection("comments")
            .order(by: "createdAt", descending: false)
            .limit(to: commentPageSize)
            .getDocuments { [weak self] snapshot, error in
                guard let self else { return }
                if let snapshot = snapshot {
                    let mapped = snapshot.documents.compactMap { self.mapComment(from: $0) }
                    DispatchQueue.main.async {
                        self.comments[postId] = mapped
                        self.hasMoreComments[postId] = mapped.count >= self.commentPageSize
                    }
                } else if let error {
                    print("Failed to load comments: \(error)")
                }
            }
    }
    
    func loadMoreComments(for postId: String) {
        guard let existingComments = comments[postId], !existingComments.isEmpty else { return }
        
        let lastComment = existingComments.last!
        
        db.collection("publicPosts")
            .document(postId)
            .collection("comments")
            .order(by: "createdAt", descending: false)
            .start(after: [lastComment.createdAt])
            .limit(to: commentPageSize)
            .getDocuments { [weak self] snapshot, error in
                guard let self else { return }
                if let snapshot = snapshot {
                    let mapped = snapshot.documents.compactMap { self.mapComment(from: $0) }
                    DispatchQueue.main.async {
                        self.comments[postId]?.append(contentsOf: mapped)
                        self.hasMoreComments[postId] = mapped.count >= self.commentPageSize
                    }
                } else if let error {
                    print("Failed to load more comments: \(error)")
                }
            }
    }

    func createPost(
        authorName: String,
        title: String,
        body: String,
        tags: [String],
        postType: String,
        productTitle: String?,
        image: UIImage?,
        completion: @escaping (Bool) -> Void
    ) {
        if let image = image {
            uploadImage(image) { [weak self] imageURL in
                guard let self else { return }
                self.createPostDocument(
                    authorName: authorName,
                    title: title,
                    body: body,
                    tags: tags,
                    postType: postType,
                    productTitle: productTitle,
                    imageURL: imageURL,
                    completion: completion
                )
            }
        } else {
            createPostDocument(
                authorName: authorName,
                title: title,
                body: body,
                tags: tags,
                postType: postType,
                productTitle: productTitle,
                imageURL: nil,
                completion: completion
            )
        }
    }
    
    private func createPostDocument(
        authorName: String,
        title: String,
        body: String,
        tags: [String],
        postType: String,
        productTitle: String?,
        imageURL: String?,
        completion: @escaping (Bool) -> Void
    ) {
        let payload: [String: Any] = [
            "authorName": authorName,
            "title": title,
            "body": body,
            "tags": tags,
            "postType": postType,
            "productTitle": productTitle as Any,
            "imageURL": imageURL as Any,
            "createdAt": Timestamp(date: Date()),
            "likeCount": 0,
            "commentCount": 0
        ]

        db.collection("publicPosts").addDocument(data: payload) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to create post: \(error)")
                    completion(false)
                } else {
                    self?.refreshPosts()
                    completion(true)
                }
            }
        }
    }
    
    private func uploadImage(_ image: UIImage, completion: @escaping (String?) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(nil)
            return
        }

        let ref = storage.reference().child("postImages/\(UUID().uuidString).jpg")
        ref.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                print("Failed to upload image: \(error)")
                completion(nil)
                return
            }

            ref.downloadURL { url, error in
                if let error = error {
                    print("Failed to get download URL: \(error)")
                    completion(nil)
                } else {
                    completion(url?.absoluteString)
                }
            }
        }
    }

    func toggleLike(post: PublicPost) {
        let userId = currentUserId()
        let ref = db.collection("publicPosts").document(post.id)

        db.runTransaction({ transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(ref)
                let likedBy = snapshot.data()?["likedBy"] as? [String] ?? []
                var newLikedBy = likedBy
                var newLikeCount = snapshot.data()?["likeCount"] as? Int ?? 0

                if likedBy.contains(userId) {
                    newLikedBy.removeAll { $0 == userId }
                    newLikeCount = max(0, newLikeCount - 1)
                } else {
                    newLikedBy.append(userId)
                    newLikeCount += 1
                }

                transaction.updateData([
                    "likedBy": newLikedBy,
                    "likeCount": newLikeCount
                ], forDocument: ref)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            return nil
        }) { [weak self] _, error in
            if let error {
                print("Failed to toggle like: \(error)")
            } else {
                self?.refreshPosts()
            }
        }
    }

    func addComment(post: PublicPost, text: String, authorName: String, completion: @escaping (Bool) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(false)
            return
        }

        let commentRef = db.collection("publicPosts").document(post.id).collection("comments").document()
        let postRef = db.collection("publicPosts").document(post.id)

        db.runTransaction({ transaction, errorPointer in
            transaction.setData([
                "authorName": authorName,
                "text": trimmed,
                "createdAt": Timestamp(date: Date())
            ], forDocument: commentRef)

            let snapshot = try? transaction.getDocument(postRef)
            let currentCount = snapshot?.data()?["commentCount"] as? Int ?? 0
            transaction.updateData(["commentCount": currentCount + 1], forDocument: postRef)
            return nil
        }) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    print("Failed to add comment: \(error)")
                    completion(false)
                } else {
                    self?.loadComments(for: post.id)
                    self?.refreshPosts()
                    completion(true)
                }
            }
        }
    }

    private func mapPost(from document: QueryDocumentSnapshot) -> PublicPost? {
        let data = document.data()
        guard let authorName = data["authorName"] as? String,
              let title = data["title"] as? String,
              let body = data["body"] as? String,
              let postType = data["postType"] as? String else {
            return nil
        }

        let tags = data["tags"] as? [String] ?? []
        let productTitle = data["productTitle"] as? String
        let imageData = data["imageURL"] as? String ?? data["imageData"] as? String
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let likeCount = data["likeCount"] as? Int ?? 0
        let commentCount = data["commentCount"] as? Int ?? 0

        return PublicPost(
            id: document.documentID,
            authorName: authorName,
            title: title,
            body: body,
            tags: tags,
            postType: postType,
            productTitle: productTitle,
            imageData: imageData,
            createdAt: createdAt,
            likeCount: likeCount,
            commentCount: commentCount
        )
    }

    private func mapComment(from document: QueryDocumentSnapshot) -> PublicComment? {
        let data = document.data()
        guard let authorName = data["authorName"] as? String,
              let text = data["text"] as? String else {
            return nil
        }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        return PublicComment(id: document.documentID, authorName: authorName, text: text, createdAt: createdAt)
    }

    private func samplePosts() -> [PublicPost] {
        [
            PublicPost(
                id: UUID().uuidString,
                authorName: "Maya R.",
                title: "My birthday vibe board",
                body: "Cozy nights, vinyl, and coffee. Drop your favorite mug recs.",
                tags: ["cozy", "music", "coffee"],
                postType: "Recommendation",
                productTitle: "Vintage record player",
                imageData: nil,
                createdAt: Date(),
                likeCount: 12,
                commentCount: 4
            ),
            PublicPost(
                id: UUID().uuidString,
                authorName: "Andre K.",
                title: "Wishlist: spring hiking",
                body: "Planning a trail weekend. Lightweight gear only.",
                tags: ["outdoors", "fitness"],
                postType: "Wishlist",
                productTitle: "Ultralight daypack",
                imageData: nil,
                createdAt: Date(),
                likeCount: 7,
                commentCount: 1
            )
        ]
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
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var giftService: GiftService
    @State private var showingAddContact = false
    @State private var lastRefreshedAt = Date()
    @State private var showCreateEventSheet = false
    @State private var showInviteInboxSheet = false
    @State private var selectedEvent: NetworkEvent? = nil
    @State private var showEventDetailPage = false
    @State private var calendarMonthDate: Date = {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }()
    @State private var organizerPhotoURLs: [String: String] = [:]
    @State private var loadingOrganizerPhotoIds: Set<String> = []
    @StateObject private var eventsService = EventsNetworkService.shared

    private struct HomeCalendarEntry: Identifiable {
        let id: String
        let date: Date
        let title: String
        let subtitle: String
        let icon: String
    }

    private var upcomingBirthdays: [Contact] {
        contactStore.contactsWithUpcomingBirthdays(within: 30)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private var contactsCount: Int { contactStore.contacts.count }
    private var upcomingCount: Int { upcomingBirthdays.count }
    private var todayReminderContacts: [Contact] {
        upcomingBirthdays.filter { $0.daysUntilBirthday == 0 }
    }

    private var lastRefreshedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastRefreshedAt, relativeTo: Date())
    }
    
    private var myInvitesEvents: [NetworkEvent] {
        eventsService.events.filter { event in
            if event.isCanceled {
                return false
            }
            if eventsService.isRemovedForCurrentUser(event) {
                return false
            }
            if eventsService.isOrganizer(event) { return true }
            if eventsService.isInvited(event) {
                let status = eventsService.inviteStatus(for: event)
                return status != .declined
            }
            return false
        }
            .sorted { $0.startAt < $1.startAt }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: calendarMonthDate)
    }

    private var monthCalendarEntries: [HomeCalendarEntry] {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: calendarMonthDate)

        var entries: [HomeCalendarEntry] = []

        for contact in contactStore.contacts {
            if contact.hasBirthday,
               let date = dateMatchingMonth(sourceDate: contact.dateOfBirth, monthComponents: monthComponents) {
                entries.append(
                    HomeCalendarEntry(
                        id: "birthday-\(contact.id)-\(date.timeIntervalSince1970)",
                        date: date,
                        title: "\(contact.name)'s Birthday",
                        subtitle: "Contact",
                        icon: "gift.fill"
                    )
                )
            }

            if let anniversary = contact.anniversaryDate,
               let date = dateMatchingMonth(sourceDate: anniversary, monthComponents: monthComponents) {
                entries.append(
                    HomeCalendarEntry(
                        id: "anniversary-\(contact.id)-\(date.timeIntervalSince1970)",
                        date: date,
                        title: "\(contact.name) Anniversary",
                        subtitle: "Contact",
                        icon: "heart.fill"
                    )
                )
            }

            for customEvent in contact.customEvents {
                if let date = dateMatchingMonth(sourceDate: customEvent.date, monthComponents: monthComponents) {
                    entries.append(
                        HomeCalendarEntry(
                            id: "custom-\(contact.id)-\(customEvent.id)-\(date.timeIntervalSince1970)",
                            date: date,
                            title: customEvent.title,
                            subtitle: contact.name,
                            icon: "calendar"
                        )
                    )
                }
            }
        }

        for event in myInvitesEvents {
            if calendar.isDate(event.startAt, equalTo: calendarMonthDate, toGranularity: .month),
               calendar.isDate(event.startAt, equalTo: calendarMonthDate, toGranularity: .year) {
                entries.append(
                    HomeCalendarEntry(
                        id: "network-\(event.id)",
                        date: event.startAt,
                        title: event.title,
                        subtitle: event.isCanceled ? "Canceled" : "Network Event",
                        icon: event.isCanceled ? "xmark.circle.fill" : "person.3.fill"
                    )
                )
            }
        }

        return entries.sorted { $0.date < $1.date }
    }

    private var monthDayGrid: [Date?] {
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: calendarMonthDate)),
              let daysRange = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let leadPadding = (firstWeekday - calendar.firstWeekday + 7) % 7

        var result: [Date?] = Array(repeating: nil, count: leadPadding)
        for day in daysRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                result.append(date)
            }
        }
        return result
    }

    private var pendingInvitesCount: Int {
        eventsService.pendingInviteEvents().count
    }

    private var hostedEventsCount: Int {
        eventsService.events.filter { eventsService.isOrganizer($0) }.count
    }

    private var reminderPreviewContacts: [Contact] {
        Array(upcomingBirthdays.prefix(3))
    }

    private var myGiftIdeas: [Gift] {
        Array(giftService.availableGifts.prefix(6))
    }

    private var contactGiftIdeas: [(contact: Contact, gift: Gift)] {
        reminderPreviewContacts.compactMap { contact in
            guard let first = giftService.getRecommendations(for: contact).first else { return nil }
            return (contact: contact, gift: first)
        }
    }

    var body: some View {
        AppNavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        heroWelcomeCard
                            .padding(.horizontal)

                        quickActionsRow
                            .padding(.horizontal)

                        upcomingRemindersSection
                            .padding(.horizontal)

                        monthCalendarSection
                            .padding(.horizontal)

                        eventsNetworkSection
                            .padding(.horizontal)

                        Spacer(minLength: 28)
                    }
                    .padding(.top, 16)
                }
                .refreshable {
                    await refreshHomepageData()
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactView()
            }
            .sheet(isPresented: $showCreateEventSheet) {
                CreateEventSheetView { eventId in
                    openCreatedEvent(eventId: eventId)
                }
            }
            .sheet(isPresented: $showInviteInboxSheet) {
                InviteInboxSheetView { event in
                    selectedEvent = event
                    showEventDetailPage = true
                }
            }
            .background(
                NavigationLink(
                    destination: Group {
                        if let selectedEvent {
                            EventDetailSheetView(event: selectedEvent)
                        }
                    },
                    isActive: $showEventDetailPage,
                    label: { EmptyView() }
                )
                .hidden()
            )
            .onChange(of: selectedEvent?.id) { id in
                if id != nil {
                    showEventDetailPage = true
                }
            }
            .onChange(of: showEventDetailPage) { isShowing in
                if !isShowing {
                    selectedEvent = nil
                }
            }
            .onAppear {
                lastRefreshedAt = Date()
                eventsService.loadEvents()
                openEventIfNeededFromNotification()
            }
            .onChange(of: notificationManager.shouldNavigateToNetworkEvent) { shouldNavigate in
                if shouldNavigate {
                    openEventIfNeededFromNotification()
                }
            }
        }
    }

    private var planningSnapshotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Planning Snapshot")
                .font(.headline)

            HStack(spacing: 10) {
                homeMetricCard(
                    title: "Today",
                    value: "\(todayReminderContacts.count)",
                    subtitle: "Reminders",
                    icon: "bell.badge.fill"
                )

                homeMetricCard(
                    title: "Invites",
                    value: "\(pendingInvitesCount)",
                    subtitle: "Pending",
                    icon: "envelope.badge.fill"
                )

                homeMetricCard(
                    title: "Hosted",
                    value: "\(hostedEventsCount)",
                    subtitle: "Events",
                    icon: "calendar"
                )
            }
        }
    }

    private func homeMetricCard(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.brand)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(.primary)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.brand.opacity(0.1), lineWidth: 1)
        )
    }

    private var upcomingRemindersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Upcoming Reminders")
                    .font(.headline)
                Spacer()
                Text("Next 30 days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 10) {
                if reminderPreviewContacts.isEmpty {
                    Text("Add a contact birthday or anniversary to populate this section.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(reminderPreviewContacts) { contact in
                        NavigationLink(destination: ContactDetailView(contact: contact)) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.brand.opacity(0.18))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Text(initials(for: contact.name))
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(Color.brand)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                    Text(reminderTimingLabel(for: contact))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.brand.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private var monthCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calendar")
                    .font(.headline)
                Spacer()

                HStack(spacing: 10) {
                    Button {
                        shiftCalendarMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)

                    Text(monthTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Button {
                        shiftCalendarMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            }

            let weekdaySymbols = rotatedWeekdaySymbols()
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                    ForEach(Array(monthDayGrid.enumerated()), id: \.offset) { _, maybeDate in
                        if let date = maybeDate {
                            let day = Calendar.current.component(.day, from: date)
                            let hasItems = monthCalendarEntries.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }

                            VStack(spacing: 3) {
                                Text("\(day)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.primary)

                                Circle()
                                    .fill(hasItems ? Color.brand : Color.clear)
                                    .frame(width: 5, height: 5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 30)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.brand.opacity(0.1), lineWidth: 1)
            )

            if monthCalendarEntries.isEmpty {
                Text("No reminders or events this month.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(monthCalendarEntries.prefix(6)) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color.brand)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(dayLabel(for: item.date))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    private func shiftCalendarMonth(by value: Int) {
        let calendar = Calendar.current
        calendarMonthDate = calendar.date(byAdding: .month, value: value, to: calendarMonthDate) ?? calendarMonthDate
    }

    private func dateMatchingMonth(sourceDate: Date, monthComponents: DateComponents) -> Date? {
        let calendar = Calendar.current
        let sourceParts = calendar.dateComponents([.month, .day], from: sourceDate)
        guard let sourceMonth = sourceParts.month,
              let sourceDay = sourceParts.day,
              let year = monthComponents.year,
              let month = monthComponents.month,
              sourceMonth == month else {
            return nil
        }

        return calendar.date(from: DateComponents(year: year, month: month, day: sourceDay))
    }

    private func rotatedWeekdaySymbols() -> [String] {
        let calendar = Calendar.current
        var symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = max(0, calendar.firstWeekday - 1)
        if shift > 0, shift < symbols.count {
            let prefix = symbols[..<shift]
            symbols.removeFirst(shift)
            symbols.append(contentsOf: prefix)
        }
        return symbols
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func openShopForMe() {
        NotificationCenter.default.post(
            name: .openShopFromHome,
            object: nil,
            userInfo: [
                "contactId": nil as String?,
                "store": nil as String?
            ]
        )
    }

    private func openShopForUpcomingContact() {
        let targetContactId = contactGiftIdeas.first?.contact.id.uuidString
        let targetStore = contactGiftIdeas.first?.gift.retailer

        NotificationCenter.default.post(
            name: .openShopFromHome,
            object: nil,
            userInfo: [
                "contactId": targetContactId as Any,
                "store": targetStore as Any
            ]
        )
    }

    private func openEventIfNeededFromNotification() {
        guard let eventId = notificationManager.selectedNetworkEventId else { return }

        if let matching = eventsService.events.first(where: { $0.id == eventId }) {
            selectedEvent = matching
            notificationManager.resetEventNavigation()
            return
        }

        eventsService.refreshEvents()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let matching = eventsService.events.first(where: { $0.id == eventId }) {
                selectedEvent = matching
            }
            notificationManager.resetEventNavigation()
        }
    }

    private func openCreatedEvent(eventId: String) {
        if let matching = eventsService.events.first(where: { $0.id == eventId }) {
            selectedEvent = matching
            return
        }

        eventsService.refreshEvents()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let matching = eventsService.events.first(where: { $0.id == eventId }) {
                selectedEvent = matching
            }
        }
    }

    private var heroWelcomeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(greetingText),")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.92))

            Text("Welcome to GiftMinder")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)

            Text("Stay ahead of birthdays and special moments with smart reminders.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))

            if !todayReminderContacts.isEmpty {
                Text("\(todayReminderContacts.count) reminder\(todayReminderContacts.count == 1 ? "" : "s") today")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                Label("\(upcomingCount) upcoming", systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())

                Label("\(contactsCount) contacts", systemImage: "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
            }
            .foregroundColor(.white)

            Text("Updated \(lastRefreshedText)")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            ZStack {
                LinearGradient(colors: [Color.brandStart, Color.brandEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .cornerRadius(20)
        .shadow(color: Color.brand.opacity(0.25), radius: 12, x: 0, y: 8)
    }

    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            quickActionTile(title: "Add Contact", subtitle: "Build your circle", icon: "person.badge.plus") {
                showingAddContact = true
            }

            quickActionTile(title: "Create Event", subtitle: "Invite your circle", icon: "calendar.badge.plus") {
                showCreateEventSheet = true
            }

            quickActionTile(
                title: "Invites",
                subtitle: pendingInvitesCount > 0 ? "\(pendingInvitesCount) pending" : "Open inbox",
                icon: "envelope.badge.fill",
                badgeCount: pendingInvitesCount
            ) {
                showInviteInboxSheet = true
            }
        }
    }

    private func quickActionTile(title: String, subtitle: String, icon: String, badgeCount: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color.brand)
                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.brand.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var eventsNetworkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Invites")
                    .font(.headline)
                Spacer()
            }

            if myInvitesEvents.isEmpty {
                Text("No invites yet. Create an event to start planning with your circle.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
            } else {
                Text("My Invites")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)

                ForEach(myInvitesEvents) { event in
                    networkEventCard(for: event)
                }
            }

        }
    }

    private func networkEventCard(for event: NetworkEvent) -> some View {
        let inviteStatus = eventsService.inviteStatus(for: event)
        let isTentative = eventsService.isInvited(event) && !eventsService.isOrganizer(event) && inviteStatus == .maybe
        let isCanceled = event.isCanceled

        return Button(action: { selectedEvent = event }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    organizerAvatar(for: event)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Organized by")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(event.organizerName)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        if isCanceled {
                            Text("Canceled")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.16))
                                .foregroundColor(.red)
                                .clipShape(Capsule())
                        }

                        if isTentative {
                            Text("Tentative")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.16))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                        }

                        Text(event.visibility.rawValue)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.brand.opacity(0.12))
                            .foregroundColor(Color.brand)
                            .clipShape(Capsule())
                    }
                }

                Divider()
                    .opacity(0.3)

                HStack {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                }

                HStack(spacing: 10) {
                    Label(relativePostDate(event.startAt), systemImage: "clock")
                    Label(event.locationName, systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Text(event.theme.isEmpty ? "No theme" : event.theme)
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color.brand)

                    Spacer()
                    Label("\(event.attendeeCount)", systemImage: "person.3.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                if !event.details.isEmpty {
                    Text(event.details)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.brand.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadOrganizerPhotoIfNeeded(for: event)
        }
    }

    private func organizerAvatar(for event: NetworkEvent) -> some View {
        let organizerId = event.organizerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let photoURL = organizerPhotoURLs[organizerId]

        return Group {
            if let photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        ZStack {
                            Circle().fill(Color.brand.opacity(0.2))
                            Text(initials(for: event.organizerName))
                                .font(.caption2.weight(.bold))
                                .foregroundColor(Color.brand)
                        }
                    }
                }
            } else {
                ZStack {
                    Circle().fill(Color.brand.opacity(0.2))
                    Text(initials(for: event.organizerName))
                        .font(.caption2.weight(.bold))
                        .foregroundColor(Color.brand)
                }
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }

    private func loadOrganizerPhotoIfNeeded(for event: NetworkEvent) {
        let organizerId = event.organizerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !organizerId.isEmpty else { return }
        guard organizerPhotoURLs[organizerId] == nil else { return }
        guard !loadingOrganizerPhotoIds.contains(organizerId) else { return }

        loadingOrganizerPhotoIds.insert(organizerId)

        Firestore.firestore().collection("users").document(organizerId).getDocument { snapshot, _ in
            DispatchQueue.main.async {
                loadingOrganizerPhotoIds.remove(organizerId)

                guard let data = snapshot?.data() else { return }
                let photo = String(
                    (data["profileImageURL"] as? String) ??
                    (data["photoURL"] as? String) ??
                    (data["imageUrl"] as? String) ??
                    ""
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                if !photo.isEmpty {
                    organizerPhotoURLs[organizerId] = photo
                }
            }
        }
    }

    private func refreshHomepageData() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        await MainActor.run {
            lastRefreshedAt = Date()
            eventsService.refreshEvents()
        }
    }

    private func relativePostDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func initials(for name: String) -> String {
        let components = name.split(separator: " ").map { String($0) }
        if components.count >= 2 {
            return (components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else if !components.isEmpty {
            return components[0].prefix(2).uppercased()
        }
        return "?"
    }

    private func reminderTimingLabel(for contact: Contact) -> String {
        let days = contact.daysUntilBirthday
        if days == 0 {
            return "Today"
        }
        if days == 1 {
            return "Tomorrow"
        }
        return "In \(days) days"
    }

}

struct CreatePostSheetView: View {
    enum PostType: String, CaseIterable, Identifiable {
        case normal = "Normal"
        case feedback = "Feedback"
        case recommendation = "Recommendation"
        case wishlist = "Wishlist"
        case question = "Question"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedService: FeedService
    @State private var postType: PostType = .normal
    @State private var postTitle: String = ""
    @State private var productName: String = ""
    @State private var postBody: String = ""
    @State private var tagsInput: String = ""
    @State private var attachedImage: UIImage? = nil
    @State private var showImagePicker = false
    @State private var showPostedAlert = false
    @State private var postFailedAlert = false

    var body: some View {
        AppNavigationView {
            Form {
                Section("Post Type") {
                    Picker("Type", selection: $postType) {
                        ForEach(PostType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Post Details") {
                    TextField("Title", text: $postTitle)
                    TextField("Product name or link", text: $productName)
                    TextField("Tags (comma-separated)", text: $tagsInput)

                    ZStack(alignment: .topLeading) {
                        if postBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Share your thoughts, feedback, or recommendations...")
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $postBody)
                            .frame(minHeight: 140)
                    }
                }

                Section("Photo") {
                    if let image = attachedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .clipped()
                            .cornerRadius(12)
                    } else {
                        Text("Add a product photo or inspiration image.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Button(attachedImage == nil ? "Add Photo" : "Replace Photo") {
                        showImagePicker = true
                    }

                    if attachedImage != nil {
                        Button("Remove Photo", role: .destructive) {
                            attachedImage = nil
                        }
                    }
                }
            }
            .navigationTitle("New Public Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        submitPost()
                    }
                    .disabled(postBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Post Created", isPresented: $showPostedAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your post is now live in the community feed.")
            }
            .alert("Post Failed", isPresented: $postFailedAlert) {
                Button("OK") { }
            } message: {
                Text("We couldn't publish your post. Please try again.")
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $attachedImage)
            }
        }
    }

    private func submitPost() {
        let uid = Auth.auth().currentUser?.uid
        let scoped = uid.flatMap { UserDefaults.standard.string(forKey: "identity_\($0)_displayName") } ?? ""
        let stored = UserDefaults.standard.string(forKey: "userName") ?? ""
        let auth = Auth.auth().currentUser?.displayName ?? ""
        let authorName = [scoped, stored, auth]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "You"
        let tags = tagsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        feedService.createPost(
            authorName: authorName,
            title: postTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            body: postBody,
            tags: tags,
            postType: postType.rawValue,
            productTitle: productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : productName,
            image: attachedImage
        ) { success in
            if success {
                showPostedAlert = true
            } else {
                postFailedAlert = true
            }
        }
    }
}

// MARK: - FilterChip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(isSelected ? .white : Color.brand)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.brand : Color.brand.opacity(0.1))
                .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Contacts View

struct ContactsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var giftService: GiftService
    @StateObject private var eventsService = EventsNetworkService.shared
    @State private var userOtherDatesRaw: String = loadScopedUserOtherDatesRaw()
    @State private var showingAddContact = false
    @State private var searchText = ""
    @State private var showCalendar = false
    @State private var networkSection: NetworkSection = .contacts
    @State private var discoverUserCount: Int = 0
    @State private var showQuickActions = false
    @State private var pressedQuickAction: QuickAction? = nil
    @State private var showImportAlert = false
    @State private var importResultMessage = ""
    @State private var isImporting = false
    @State private var showContactPicker = false
    @State private var showImportOptions = false
    @State private var inviteTargetContact: Contact?
    @State private var showHostedEventPicker = false
    @State private var showInviteFeedback = false
    @State private var inviteFeedbackMessage = ""

    private enum NetworkSection: String, CaseIterable {
        case contacts = "Contacts"
        case discover = "Discover"
    }

    private var upcomingBirthdays: [Contact] {
        contactStore.contactsWithUpcomingBirthdays(within: 30)
    }

    private var filteredUpcoming: [Contact] {
        upcomingBirthdays.filter { contact in
            searchText.isEmpty || contact.name.localizedCaseInsensitiveContains(searchText)
                || contact.interests.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var filteredOtherContacts: [Contact] {
        let otherContacts = contactStore.contacts.filter { c in
            !upcomingBirthdays.contains(where: { $0.id == c.id })
        }

        return otherContacts.filter { contact in
            searchText.isEmpty || contact.name.localizedCaseInsensitiveContains(searchText)
                || contact.interests.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var filteredGiftMinderContacts: [Contact] {
        filteredOtherContacts.filter { isGiftMinderUserContact($0) }
    }

    private var filteredNonGiftMinderContacts: [Contact] {
        filteredOtherContacts.filter { !isGiftMinderUserContact($0) }
    }

    private var hostedEvents: [NetworkEvent] {
        availableHostedEvents()
    }

    private var profileInviteEvents: [ImportedPersonalDate] {
        loadImportedPersonalDates()
            .filter { !hasMatchingHostedEvent(for: $0) }
            .sorted { $0.time < $1.time }
    }

    private var hasAnyInviteEventOption: Bool {
        !hostedEvents.isEmpty || !profileInviteEvents.isEmpty
    }

    private func availableHostedEvents() -> [NetworkEvent] {
        let currentUid = Auth.auth().currentUser?.uid
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return eventsService.events
            .filter { event in
                if event.isCanceled {
                    return false
                }
                if eventsService.isOrganizer(event) { return true }

                guard let currentUid, !currentUid.isEmpty else { return false }
                return event.organizerId.trimmingCharacters(in: .whitespacesAndNewlines) == currentUid
            }
            .sorted { $0.startAt < $1.startAt }
    }

    private func hasMatchingHostedEvent(for entry: ImportedPersonalDate) -> Bool {
        let normalizedTitle = entry.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let date = Date(timeIntervalSince1970: entry.time)

        return hostedEvents.contains { event in
            let eventTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard eventTitle == normalizedTitle else { return false }
            return Calendar.current.isDate(event.startAt, equalTo: date, toGranularity: .minute)
        }
    }

    private enum QuickAction {
        case calendar
        case importContacts
        case addContact
    }

    var body: some View {
        AppNavigationView {
            ZStack(alignment: .topTrailing) {
                AppBackground()

                VStack(spacing: 12) {
                    Picker("Network", selection: $networkSection) {
                        Text(NetworkSection.contacts.rawValue).tag(NetworkSection.contacts)
                        Text(discoverSegmentTitle).tag(NetworkSection.discover)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if networkSection == .contacts {
                        HStack(spacing: 12) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Search contacts...", text: $searchText)
                                    .textFieldStyle(PlainTextFieldStyle())
                            }
                            .padding(12)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.brand.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)

                            Button(action: { toggleQuickActions() }) {
                                Image(systemName: "line.horizontal.3.decrease")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(12)
                                    .background(Circle().fill(Color(UIColor.tertiarySystemBackground)))
                                    .overlay(Circle().stroke(Color.brand.opacity(0.12), lineWidth: 1))
                                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 4)
                            }
                        }
                        .padding(.horizontal)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                if !filteredUpcoming.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        StylishSectionHeader(title: "Upcoming Events", icon: "calendar", style: .primary, showsShine: true)

                                        ForEach(filteredUpcoming) { contact in
                                            contactListRow(contact: contact, showUpcomingEvent: true)
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    allContactsBanner

                                    if filteredOtherContacts.isEmpty && searchText.isEmpty {
                                        EmptyContactsView()
                                    } else if filteredOtherContacts.isEmpty {
                                        Text("No contacts match your search.")
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 4)
                                    } else {
                                        ForEach(filteredGiftMinderContacts) { contact in
                                            contactListRow(contact: contact)
                                        }

                                        ForEach(filteredNonGiftMinderContacts) { contact in
                                            contactListRow(contact: contact)
                                        }
                                    }
                                }

                                Spacer(minLength: 24)
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                        }
                        .disabled(isImporting)
                        .blur(radius: isImporting ? 2 : 0)
                        .coordinateSpace(name: "contactList")
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("contactList")).minY)
                        })
                    } else {
                        SearchView(
                            embedded: true,
                            onResultCountChanged: { count in
                                discoverUserCount = count
                            }
                        )
                            .environmentObject(contactStore)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                if networkSection == .contacts && showQuickActions {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { closeQuickActions() }

                    quickActionsMenu
                        .padding(.trailing, 18)
                        .padding(.top, 62)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactView()
            }
            .sheet(isPresented: $showCalendar) {
                CalendarView()
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerView(onSelect: handleContactSelection, onCancel: { showContactPicker = false })
            }
            .confirmationDialog("Import Data", isPresented: $showImportOptions, titleVisibility: .visible) {
                Button("Import Contacts (Select)") { showContactPicker = true }
                Button("Import Contacts (All)") { importAllContacts() }
                Button("Import Reminders") { importRemindersFromNativeApp() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose what to import from your iPhone.")
            }
            .alert(isPresented: $showImportAlert) {
                Alert(title: Text("Import"), message: Text(importResultMessage), dismissButton: .default(Text("OK")))
            }
            .confirmationDialog(
                inviteTargetContact == nil ? "Invite to Event" : "Invite \(inviteTargetContact?.name ?? "")",
                isPresented: $showHostedEventPicker,
                titleVisibility: .visible
            ) {
                ForEach(hostedEvents) { event in
                    Button("🌐 \(event.title) • \(event.startAt, formatter: inviteEventDateFormatter)") {
                        guard let inviteTargetContact else { return }
                        quickInvite(inviteTargetContact, to: event)
                    }
                }
                ForEach(profileInviteEvents) { entry in
                    Button("🗓️ \(entry.label) • \(Date(timeIntervalSince1970: entry.time), formatter: inviteEventDateFormatter)") {
                        guard let inviteTargetContact else { return }
                        quickInvite(inviteTargetContact, toProfileEvent: entry)
                    }
                }
                Button("Cancel", role: .cancel) {
                    inviteTargetContact = nil
                }
            } message: {
                Text("Choose one of your profile events.")
            }
            .alert("Invite", isPresented: $showInviteFeedback) {
                Button("OK") {}
            } message: {
                Text(inviteFeedbackMessage)
            }
            .onAppear {
                eventsService.loadEvents()
                userOtherDatesRaw = loadScopedUserOtherDatesRaw()
            }
        }
    }

    private var discoverSegmentTitle: String {
        discoverUserCount > 0 ? "Discover (\(discoverUserCount))" : NetworkSection.discover.rawValue
    }

    private var allContactsBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .foregroundColor(.white)
                .padding(6)
                .background(Circle().fill(Color.white.opacity(0.12)))

            Text("All Contacts")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LinearGradient(colors: [Color.brandStart, Color.brandEnd], startPoint: .leading, endPoint: .trailing))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func isGiftMinderUserContact(_ contact: Contact) -> Bool {
        if let source = contact.sourceIdentifier,
           source.lowercased().hasPrefix("firebase:") {
            return true
        }
        return firstHandleInText(contact.notes) != nil
    }

    private func contactListRow(contact: Contact, showUpcomingEvent: Bool = false) -> some View {
        HStack(spacing: 10) {
            NavigationLink(destination: ContactDetailView(contact: contact)) {
                ContactRowView(contact: contact, showUpcomingEvent: showUpcomingEvent, isGiftMinderUser: isGiftMinderUserContact(contact))
                    .padding(8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.brand.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: {
                startQuickInvite(for: contact)
            }) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.brand)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.brand.opacity(0.12)))
                    .overlay(Circle().stroke(Color.brand.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Invite \(contact.name) to hosted event")
        }
    }

    private func startQuickInvite(for contact: Contact) {
        userOtherDatesRaw = loadScopedUserOtherDatesRaw()

        if hasAnyInviteEventOption {
            inviteTargetContact = contact
            showHostedEventPicker = true
            return
        }

        eventsService.refreshEvents()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            userOtherDatesRaw = loadScopedUserOtherDatesRaw()

            if hasAnyInviteEventOption {
                inviteTargetContact = contact
                showHostedEventPicker = true
            } else {
                inviteFeedbackMessage = "Create a hosted event or add a profile event first, then you can invite contacts from this list."
                showInviteFeedback = true
            }
        }
    }

    private func quickInvite(_ contact: Contact, to event: NetworkEvent) {
        resolveInviteHandle(for: contact) { resolvedHandle in
            if let handle = resolvedHandle {
                eventsService.addInviteHandle(event: event, handle: handle) { result in
                    switch result {
                    case .added:
                        inviteFeedbackMessage = "Added \(contact.name) to \(event.title)."
                    case .alreadyInvited:
                        inviteFeedbackMessage = "\(contact.name) is already invited to \(event.title)."
                    case .invalidHandle:
                        inviteFeedbackMessage = "That @username is invalid. Update the contact notes and try again."
                    case .failed:
                        inviteFeedbackMessage = "Couldn’t send invite right now. Please try again."
                    }

                    inviteTargetContact = nil
                    showInviteFeedback = true
                }
                return
            }

            if isGiftMinderUserContact(contact) {
                inviteFeedbackMessage = "Couldn’t resolve this GiftMinder username yet. Try again in a moment."
                inviteTargetContact = nil
                showInviteFeedback = true
                return
            }

            eventsService.addExternalInvitee(event: event, contactName: contact.name, phoneNumber: contact.phoneNumber) { result in
                switch result {
                case .added:
                    sendTextInviteForNonUser(contact: contact, event: event)
                    inviteFeedbackMessage = "Added \(contact.name) to \(event.title). You can update RSVP manually from People."
                case .alreadyInvited:
                    sendTextInviteForNonUser(contact: contact, event: event)
                    inviteFeedbackMessage = "\(contact.name) is already on this event."
                case .invalidHandle, .failed:
                    inviteFeedbackMessage = "Couldn’t add \(contact.name) to this event right now."
                }

                inviteTargetContact = nil
                showInviteFeedback = true
            }
        }
    }

    private func quickInvite(_ contact: Contact, toProfileEvent entry: ImportedPersonalDate) {
        let eventDate = Date(timeIntervalSince1970: entry.time)
        let trimmedTitle = entry.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventTitle = trimmedTitle.isEmpty ? "Event" : trimmedTitle

        if let existing = matchingHostedEvent(forTitle: eventTitle, date: eventDate) {
            quickInvite(contact, to: existing)
            return
        }

        resolveInviteHandle(for: contact) { resolvedHandle in
            if let handle = resolvedHandle {
                eventsService.createEvent(
                    title: eventTitle,
                    details: "Shared from your profile",
                    theme: "Personal",
                    startAt: eventDate,
                    locationName: "Location TBD",
                    visibility: .inviteOnly,
                    publicJoinMode: .requestApproval,
                    invitedHandlesText: handle
                    ) { success, _ in
                    if success {
                        inviteFeedbackMessage = "Invited \(contact.name) to \(eventTitle)."
                    } else {
                        inviteFeedbackMessage = "Couldn’t create that event invite right now. Please try again."
                    }
                    inviteTargetContact = nil
                    showInviteFeedback = true
                }
                return
            }

            if isGiftMinderUserContact(contact) {
                inviteFeedbackMessage = "Couldn’t resolve this GiftMinder username yet. Try again in a moment."
                inviteTargetContact = nil
                showInviteFeedback = true
                return
            }

            eventsService.createEvent(
                title: eventTitle,
                details: "Shared from your profile",
                theme: "Personal",
                startAt: eventDate,
                locationName: "Location TBD",
                visibility: .inviteOnly,
                publicJoinMode: .requestApproval,
                invitedHandlesText: ""
            ) { success, eventId in
                guard success, let eventId else {
                    inviteFeedbackMessage = "Couldn’t create that event invite right now. Please try again."
                    inviteTargetContact = nil
                    showInviteFeedback = true
                    return
                }

                eventsService.addExternalInvitee(
                    eventId: eventId,
                    existingInvitedHandles: [],
                    contactName: contact.name,
                    phoneNumber: contact.phoneNumber
                ) { result in
                    if case .failed = result {
                        inviteFeedbackMessage = "Event created, but adding \(contact.name) failed. Try again."
                    } else {
                        sendTextInviteForNonUser(contact: contact, title: eventTitle, startAt: eventDate, locationName: nil)
                        inviteFeedbackMessage = "Invited \(contact.name) to \(eventTitle)."
                    }
                    inviteTargetContact = nil
                    showInviteFeedback = true
                }
            }
        }
    }

    private func matchingHostedEvent(forTitle title: String, date: Date) -> NetworkEvent? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return hostedEvents.first { event in
            let eventTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return eventTitle == normalizedTitle && Calendar.current.isDate(event.startAt, inSameDayAs: date)
        }
    }

    private func resolveInviteHandle(for contact: Contact, completion: @escaping (String?) -> Void) {
        if let local = preferredInviteHandle(for: contact) {
            completion(local)
            return
        }

        guard let uid = firebaseUid(from: contact) else {
            completion(nil)
            return
        }

        Firestore.firestore().collection("users").document(uid).getDocument { snapshot, _ in
            let data = snapshot?.data()

            let candidates: [String] = [
                data?["userId"] as? String,
                data?["username"] as? String,
                data?["handle"] as? String
            ].compactMap { $0 }

            let resolved = candidates
                .map { normalizeInviteHandle($0) }
                .first { !$0.isEmpty }

            DispatchQueue.main.async {
                if let resolved {
                    cacheResolvedInviteHandle(resolved, for: contact)
                }
                completion(resolved)
            }
        }
    }

    private func firebaseUid(from contact: Contact) -> String? {
        guard let source = contact.sourceIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              source.lowercased().hasPrefix("firebase:") else {
            return nil
        }

        let uid = String(source.dropFirst("firebase:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return uid.isEmpty ? nil : uid
    }

    private func cacheResolvedInviteHandle(_ handle: String, for contact: Contact) {
        guard let index = contactStore.contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        let marker = "@\(handle)"
        let existingNotes = contactStore.contacts[index].notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingNotes.localizedCaseInsensitiveContains(marker) {
            return
        }

        contactStore.contacts[index].notes = existingNotes.isEmpty ? marker : "\(existingNotes) \(marker)"
        contactStore.contacts[index].updatedAt = Date()
    }

    private func preferredInviteHandle(for contact: Contact) -> String? {
        if let noteHandle = firstHandleInText(contact.notes) {
            return noteHandle
        }
        if contact.name.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@") {
            let fromName = normalizeInviteHandle(contact.name)
            return fromName.isEmpty ? nil : fromName
        }
        return nil
    }

    private func firstHandleInText(_ text: String) -> String? {
        let tokens = text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        for token in tokens {
            let trimmed = token.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "@")))
            if trimmed.hasPrefix("@") {
                let normalized = normalizeInviteHandle(trimmed)
                if !normalized.isEmpty {
                    return normalized
                }
            }
        }
        return nil
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

    private func sendTextInviteForNonUser(contact: Contact, event: NetworkEvent) {
        sendTextInviteForNonUser(contact: contact, title: event.title, startAt: event.startAt, locationName: event.locationName)
    }

    private func sendTextInviteForNonUser(contact: Contact, title: String, startAt: Date, locationName: String?) {
        guard let rawPhone = contact.phoneNumber,
              let recipient = normalizedSMSRecipient(rawPhone) else {
            inviteFeedbackMessage = "\(contact.name) doesn't have a phone number. Add one (or add @username in notes) to invite."
            showInviteFeedback = true
            return
        }

        let body = smsInviteBody(title: title, startAt: startAt, locationName: locationName)
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        guard let url = URL(string: "sms:\(recipient)&body=\(encodedBody)") else {
            inviteFeedbackMessage = "Couldn’t open Messages right now."
            showInviteFeedback = true
            return
        }

        openURL(url)
    }

    private func normalizedSMSRecipient(_ value: String) -> String? {
        let filtered = value.filter { $0.isNumber || $0 == "+" }
        return filtered.isEmpty ? nil : filtered
    }

    private func smsInviteBody(for event: NetworkEvent) -> String {
        smsInviteBody(title: event.title, startAt: event.startAt, locationName: event.locationName)
    }

    private func smsInviteBody(title: String, startAt: Date, locationName: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let when = formatter.string(from: startAt)

        let normalizedLocation = (locationName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let locationLine = normalizedLocation.isEmpty ? "" : " at \(normalizedLocation)"

        return "Hey! You're invited to \(title) on \(when)\(locationLine). Join me on GiftMinder to RSVP and stay updated."
    }

    private var inviteEventDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private var quickActionsMenu: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(Color.brand.opacity(0.22), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)

            VStack(spacing: 12) {
                quickActionButton(action: .calendar, title: "Calendar", icon: "calendar")
                quickActionButton(action: .importContacts, title: "Import", icon: "person.crop.circle.badge.plus")
                quickActionButton(action: .addContact, title: "Add", icon: "plus")
            }
        }
        .frame(width: 170, height: 170)
    }

    private func quickActionButton(action: QuickAction, title: String, icon: String) -> some View {
        Button(action: { handleQuickAction(action) }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(UIColor.secondarySystemBackground).opacity(0.9)))
            .scaleEffect(pressedQuickAction == action ? 0.94 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pressedQuickAction)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func toggleQuickActions() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            showQuickActions.toggle()
        }
    }

    private func closeQuickActions() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showQuickActions = false
        }
    }

    private func handleQuickAction(_ action: QuickAction) {
        pressedQuickAction = action
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            pressedQuickAction = nil
            closeQuickActions()
            switch action {
            case .calendar:
                showCalendar = true
            case .importContacts:
                showImportOptions = true
            case .addContact:
                showingAddContact = true
            }
        }
    }

    // MARK: - Import Contacts
    private func handleContactSelection(_ contacts: [CNContact]) {
        showContactPicker = false
        isImporting = true
        let importedCount = importSelectedContacts(contacts)
        isImporting = false
        importResultMessage = "Imported \(importedCount) contacts."
        showImportAlert = true
    }

    private func importSelectedContacts(_ contacts: [CNContact]) -> Int {
        var importedCount = 0
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        var existingIdentifiers = Set(contactStore.contacts.compactMap { $0.sourceIdentifier })
        var existingNames = Set(contactStore.contacts.map { normalizedName($0.name) })
        for cnContact in contacts {
            let resolvedContact: CNContact
            if cnContact.thumbnailImageData == nil {
                let predicate = CNContact.predicateForContacts(withIdentifiers: [cnContact.identifier])
                if let refreshed = try? store.unifiedContacts(matching: predicate, keysToFetch: keys).first {
                    resolvedContact = refreshed
                } else {
                    resolvedContact = cnContact
                }
            } else {
                resolvedContact = cnContact
            }

            let fullName = contactDisplayName(for: resolvedContact)
            guard !fullName.isEmpty else { continue }
            let normalized = normalizedName(fullName)
            let identifier = resolvedContact.identifier

            if (!identifier.isEmpty && existingIdentifiers.contains(identifier))
                || existingNames.contains(normalized) {
                continue
            }
            if !identifier.isEmpty {
                existingIdentifiers.insert(identifier)
            }
            existingNames.insert(normalized)
            if true {
                var newContact = Contact(
                    name: fullName,
                    dateOfBirth: Date(),
                    relationship: .other,
                    isBirthYearKnown: false,
                    hasBirthday: false,
                    sourceIdentifier: identifier.isEmpty ? nil : identifier,
                    phoneNumber: resolvedContact.phoneNumbers.first?.value.stringValue
                )
                newContact.photoData = resolvedContact.thumbnailImageData
                contactStore.addContact(newContact)
                importedCount += 1
            }
        }
        return importedCount
    }

    private func importAllContacts() {
        isImporting = true
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, error in
            if let err = error {
                DispatchQueue.main.async {
                    isImporting = false
                    importResultMessage = "Error requesting access: \(err.localizedDescription)"
                    showImportAlert = true
                }
                return
            }

            guard granted else {
                DispatchQueue.main.async {
                    isImporting = false
                    importResultMessage = "Contacts access was denied. Enable access in Settings to import."
                    showImportAlert = true
                }
                return
            }

            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)

            DispatchQueue.main.async {
                let existingIdentifiers = Set(contactStore.contacts.compactMap { $0.sourceIdentifier })
                let existingNames = Set(contactStore.contacts.map { normalizedName($0.name) })

                DispatchQueue.global(qos: .userInitiated).async {
                    var imported: [Contact] = []
                    var seenIdentifiers = existingIdentifiers
                    var seenNames = existingNames

                    do {
                        try store.enumerateContacts(with: request) { cnContact, _ in
                            let fullName = contactDisplayName(for: cnContact)
                            guard !fullName.isEmpty else { return }
                            let normalized = normalizedName(fullName)
                            let identifier = cnContact.identifier

                            if (!identifier.isEmpty && seenIdentifiers.contains(identifier))
                                || seenNames.contains(normalized) {
                                return
                            }
                            if !identifier.isEmpty {
                                seenIdentifiers.insert(identifier)
                            }
                            seenNames.insert(normalized)
                            if true {
                                var newContact = Contact(
                                    name: fullName,
                                    dateOfBirth: Date(),
                                    relationship: .other,
                                    isBirthYearKnown: false,
                                    hasBirthday: false,
                                    sourceIdentifier: identifier.isEmpty ? nil : identifier,
                                    phoneNumber: cnContact.phoneNumbers.first?.value.stringValue
                                )
                                newContact.photoData = cnContact.thumbnailImageData
                                imported.append(newContact)
                            }
                        }

                        DispatchQueue.main.async {
                            imported.forEach { contactStore.addContact($0) }
                            isImporting = false
                            importResultMessage = "Imported \(imported.count) contacts."
                            showImportAlert = true
                        }
                    } catch {
                        DispatchQueue.main.async {
                            isImporting = false
                            importResultMessage = "Failed to import contacts: \(error.localizedDescription)"
                            showImportAlert = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Import Reminders
    private typealias ImportedPersonalDate = PersonalDateRecord

    private func importRemindersFromNativeApp() {
        isImporting = true
        fetchIncompleteRemindersFromNativeApp { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(.accessDenied):
                    isImporting = false
                    importResultMessage = "Reminders access was denied. Enable access in Settings to import."
                    showImportAlert = true
                case .failure(.accessFailure(let message)):
                    isImporting = false
                    importResultMessage = "Could not access reminders: \(message)"
                    showImportAlert = true
                case .success(let reminders):
                    let importedCount = mergeImportedReminders(reminders)
                    isImporting = false
                    importResultMessage = importedCount == 0
                        ? "No due reminders were available to import."
                        : "Imported \(importedCount) reminders."
                    showImportAlert = true
                }
            }
        }
    }

    private func mergeImportedReminders(_ reminders: [EKReminder]) -> Int {
        let result = PersonalDateStore.merge(reminders: reminders, into: loadImportedPersonalDates())
        saveImportedPersonalDates(result.entries)
        return result.importedCount
    }

    private func loadImportedPersonalDates() -> [ImportedPersonalDate] {
        PersonalDateStore.load(from: userOtherDatesRaw)
    }

    private func saveImportedPersonalDates(_ entries: [ImportedPersonalDate]) {
        if let raw = PersonalDateStore.encode(entries) {
            userOtherDatesRaw = raw
            saveScopedUserOtherDatesRaw(raw)
        }
    }

    private func contactDisplayName(for contact: CNContact) -> String {
        let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        if !fullName.isEmpty {
            return fullName
        }
        return contact.organizationName.trimmingCharacters(in: .whitespaces)
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct WishlistBoardView: View {
    @EnvironmentObject var contactStore: ContactStore
    @State private var userOtherDatesRaw: String = loadScopedUserOtherDatesRaw()
    @State private var isSyncingReminders = false
    @State private var showSyncAlert = false
    @State private var syncMessage = ""

    private var contactsWithUpcomingEvents: [Contact] {
        contactStore.contacts
            .filter { $0.hasBirthday || $0.anniversaryDate != nil || !$0.customEvents.isEmpty }
            .sorted { $0.daysUntilBirthday < $1.daysUntilBirthday }
    }

    var body: some View {
        AppNavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Wishlist Board")
                                .font(.headline)
                            Text("Manage gift planning by contact and keep reminders in sync.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button(action: syncRemindersFromNativeApp) {
                                HStack(spacing: 8) {
                                    if isSyncingReminders {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text(isSyncingReminders ? "Syncing iPhone Reminders..." : "Sync iPhone Reminders")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.brand.opacity(0.1))
                                .foregroundColor(Color.brand)
                                .cornerRadius(10)
                            }
                            .disabled(isSyncingReminders)
                        }
                        .padding(14)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.brand.opacity(0.1), lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Contacts")
                                .font(.headline)

                            if contactsWithUpcomingEvents.isEmpty {
                                Text("Add contacts and events to start building your wishlist board.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(contactsWithUpcomingEvents) { contact in
                                    NavigationLink(destination: ContactDetailView(contact: contact)) {
                                        HStack(spacing: 10) {
                                            if let data = contact.photoData, let ui = UIImage(data: data) {
                                                Image(uiImage: ui)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 38, height: 38)
                                                    .clipShape(Circle())
                                            } else {
                                                Circle()
                                                    .fill(Color.brand.opacity(0.2))
                                                    .frame(width: 38, height: 38)
                                                    .overlay(
                                                        Text(initials(for: contact.name))
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundColor(Color.brand)
                                                    )
                                            }

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(contact.name)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(.primary)
                                                Text(summaryLine(for: contact))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(10)
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.brand.opacity(0.1), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Gift Lists")
            .alert("Reminders Sync", isPresented: $showSyncAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(syncMessage)
            }
            .onAppear {
                userOtherDatesRaw = loadScopedUserOtherDatesRaw()
            }
        }
    }

    private typealias ImportedPersonalDate = PersonalDateRecord

    private func syncRemindersFromNativeApp() {
        guard !isSyncingReminders else { return }
        isSyncingReminders = true

        fetchIncompleteRemindersFromNativeApp { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(.accessDenied):
                    isSyncingReminders = false
                    syncMessage = "Reminders access was denied. Enable access in Settings to sync."
                    showSyncAlert = true
                case .failure(.accessFailure(let message)):
                    isSyncingReminders = false
                    syncMessage = "Could not access reminders: \(message)"
                    showSyncAlert = true
                case .success(let reminders):
                    let importedCount = mergeImportedReminders(reminders)
                    isSyncingReminders = false
                    syncMessage = importedCount == 0
                        ? "No new due reminders were available to sync."
                        : "Synced \(importedCount) reminders from iPhone Reminders."
                    showSyncAlert = true
                }
            }
        }
    }

    private func mergeImportedReminders(_ reminders: [EKReminder]) -> Int {
        let result = PersonalDateStore.merge(reminders: reminders, into: loadImportedPersonalDates())
        saveImportedPersonalDates(result.entries)
        return result.importedCount
    }

    private func loadImportedPersonalDates() -> [ImportedPersonalDate] {
        PersonalDateStore.load(from: userOtherDatesRaw)
    }

    private func saveImportedPersonalDates(_ entries: [ImportedPersonalDate]) {
        if let raw = PersonalDateStore.encode(entries) {
            userOtherDatesRaw = raw
            saveScopedUserOtherDatesRaw(raw)
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first.map { String($0.prefix(1)) } ?? ""
        let last = parts.count > 1 ? String(parts.last!.prefix(1)) : ""
        return (first + last).uppercased()
    }

    private func summaryLine(for contact: Contact) -> String {
        var chunks: [String] = []
        if contact.hasBirthday {
            let d = contact.daysUntilBirthday
            if d == 0 {
                chunks.append("Birthday today")
            } else if d > 0 && d <= 365 {
                chunks.append("Birthday in \(d)d")
            }
        }
        if contact.anniversaryDate != nil {
            chunks.append("Anniversary")
        }
        if !contact.customEvents.isEmpty {
            chunks.append("\(contact.customEvents.count) custom")
        }
        if chunks.isEmpty {
            return "Open contact wishlist"
        }
        return chunks.joined(separator: " • ")
    }
}

private struct PlanReminderItem: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var dueDate: Date?
    var isDone: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        dueDate: Date?,
        isDone: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isDone = isDone
        self.createdAt = createdAt
    }
}

struct PlansHubView: View {
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var giftService: GiftService
    @StateObject private var eventsService = EventsNetworkService.shared

    @State private var showGiftLists = false
    @State private var showReminders = false

    private var hostedInvitations: [NetworkEvent] {
        eventsService.events
            .filter { eventsService.isOrganizer($0) && !$0.isCanceled }
            .sorted { $0.startAt > $1.startAt }
    }

    var body: some View {
        AppNavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Plans")
                                .font(.title3.weight(.bold))
                            Text("Keep gift lists, reminders, and invitation design together in one place.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        planCard(
                            title: "Gift Lists",
                            subtitle: "Manage wishlist planning by contact",
                            icon: "gift.fill",
                            accent: Color.brand,
                            action: { showGiftLists = true }
                        )

                        planCard(
                            title: "Reminder List",
                            subtitle: "Track what to do next for upcoming events",
                            icon: "checklist",
                            accent: .orange,
                            action: { showReminders = true }
                        )

                        NavigationLink(destination: InvitationDesignerView(initialEventId: nil)) {
                            planCardContent(
                                title: "Invitation Designer",
                                subtitle: "Create polished invitations with simple templates",
                                icon: "wand.and.stars",
                                accent: .purple
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        if !hostedInvitations.isEmpty {
                            myInvitationsCard
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Plans")
            .onAppear {
                eventsService.loadEvents()
            }
            .sheet(isPresented: $showGiftLists) {
                WishlistBoardView()
                    .environmentObject(contactStore)
            }
            .sheet(isPresented: $showReminders) {
                SimpleReminderListView()
            }
        }
    }

    private var myInvitationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("My Invitations")
                    .font(.headline)
                Spacer()
                NavigationLink(destination: InvitationDesignerView(initialEventId: nil)) {
                    Text("New")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.brand)
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(hostedInvitations.prefix(3))) { event in
                NavigationLink(destination: InvitationDesignerView(initialEventId: event.id)) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.brand.opacity(0.12))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: "envelope.open.fill")
                                    .foregroundColor(Color.brand)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(event.startAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                invitationStatusBadge(for: event)
                            }
                        }

                        Spacer()

                        Text("Edit")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color.brand)
                    }
                    .padding(10)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            if hostedInvitations.count > 3 {
                Text("Open Invitation Designer to edit all invitations.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.brand.opacity(0.18), lineWidth: 1)
        )
    }

    private func invitationStatusBadge(for event: NetworkEvent) -> some View {
        let calendar = Calendar.current
        let now = Date()

        let statusText: String
        let textColor: Color
        let fillColor: Color

        if calendar.isDateInToday(event.startAt) {
            statusText = "Today"
            textColor = .orange
            fillColor = Color.orange.opacity(0.16)
        } else if event.startAt > now {
            statusText = "Upcoming"
            textColor = Color.brand
            fillColor = Color.brand.opacity(0.14)
        } else {
            statusText = "Past"
            textColor = .secondary
            fillColor = Color.secondary.opacity(0.14)
        }

        return Text(statusText)
            .font(.caption2.weight(.semibold))
            .foregroundColor(textColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(fillColor)
            .clipShape(Capsule())
    }

    private func planCard(title: String, subtitle: String, icon: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            planCardContent(title: title, subtitle: subtitle, icon: icon, accent: accent)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func planCardContent(title: String, subtitle: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accent.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(accent)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }
}

struct SimpleReminderListView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var reminders: [PlanReminderItem] = []
    @State private var reminderInput = ""
    @State private var includeDate = false
    @State private var selectedDate = Date()

    private var storageKey: String {
        let uid = Auth.auth().currentUser?.uid ?? "guest"
        return "planReminders_\(uid)"
    }

    private var upcoming: [PlanReminderItem] {
        reminders
            .filter { !$0.isDone }
            .sorted {
                let lhsDate = $0.dueDate ?? Date.distantFuture
                let rhsDate = $1.dueDate ?? Date.distantFuture
                if lhsDate == rhsDate {
                    return $0.createdAt < $1.createdAt
                }
                return lhsDate < rhsDate
            }
    }

    private var done: [PlanReminderItem] {
        reminders
            .filter { $0.isDone }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        AppNavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reminder List")
                                .font(.headline)
                            Text("Add quick reminders for tasks and deadlines tied to your plans.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            VStack(spacing: 8) {
                                TextField("Add a reminder", text: $reminderInput)
                                    .textFieldStyle(.roundedBorder)

                                Toggle("Add due date", isOn: $includeDate)
                                    .font(.subheadline)

                                if includeDate {
                                    DatePicker("Due", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.compact)
                                }

                                Button(action: addReminder) {
                                    Text("Add Reminder")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.brand)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                                .disabled(reminderInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(14)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(14)

                        reminderSection(title: "Upcoming", items: upcoming)

                        if !done.isEmpty {
                            reminderSection(title: "Done", items: done)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Reminder List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: loadReminders)
        }
    }

    private func reminderSection(title: String, items: [PlanReminderItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if items.isEmpty {
                Text(title == "Upcoming" ? "No reminders yet." : "No completed reminders.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Button {
                            toggleDone(item)
                        } label: {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(item.isDone ? .green : .secondary)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .strikethrough(item.isDone)
                                .foregroundColor(.primary)

                            if let dueDate = item.dueDate {
                                Text(reminderDateFormatter.string(from: dueDate))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button(role: .destructive) {
                            deleteReminder(item)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
        }
    }

    private var reminderDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private func addReminder() {
        let trimmed = reminderInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        reminders.append(
            PlanReminderItem(
                title: trimmed,
                dueDate: includeDate ? selectedDate : nil
            )
        )

        reminderInput = ""
        includeDate = false
        selectedDate = Date()
        saveReminders()
    }

    private func toggleDone(_ item: PlanReminderItem) {
        guard let index = reminders.firstIndex(where: { $0.id == item.id }) else { return }
        reminders[index].isDone.toggle()
        saveReminders()
    }

    private func deleteReminder(_ item: PlanReminderItem) {
        reminders.removeAll { $0.id == item.id }
        saveReminders()
    }

    private func loadReminders() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            reminders = []
            return
        }

        do {
            reminders = try JSONDecoder().decode([PlanReminderItem].self, from: data)
        } catch {
            reminders = []
        }
    }

    private func saveReminders() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

struct InvitationDesignerView: View {
    @StateObject private var eventsService = EventsNetworkService.shared
    let initialEventId: String?

    @State private var template: InvitationTemplate = .partyPop
    @State private var tone: InvitationTone = .warm
    @State private var occasion: InvitationOccasion = .custom
    @State private var backgroundStyle: InvitationBackgroundStyle = .softGlow
    @State private var decoration: InvitationDecoration = .none
    @State private var layoutMode: InvitationLayoutMode = .classic
    @State private var title = ""
    @State private var subtitle = ""
    @State private var message = ""
    @State private var eventDate = Date().addingTimeInterval(86_400)
    @State private var location = ""
    @State private var inviteHandles = ""
    @State private var selectedHostedEventId = ""
    @State private var selectedHostedHeaderURL: String?
    @State private var shouldClearHeaderImage = false
    @State private var isPublishing = false
    @State private var showPublishResult = false
    @State private var publishMessage = ""
    @State private var heroImage: UIImage?
    @State private var showImagePicker = false

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPublishing
    }

    private var hostedEvents: [NetworkEvent] {
        eventsService.events
            .filter { eventsService.isOrganizer($0) && !$0.isCanceled }
            .sorted { $0.startAt < $1.startAt }
    }

    private var isEditingExistingInvitation: Bool {
        !selectedHostedEventId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inviteeCount: Int {
        inviteHandles
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private var previewBackground: some ShapeStyle {
        backgroundStyle.gradient(accent: template.accent)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    invitationHeroCard
                    invitationPreview
                    designerControls

                    Button(action: publishInvitation) {
                        HStack {
                            if isPublishing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text(isPublishing ? "Publishing..." : (isEditingExistingInvitation ? "Save Invitation" : "Publish Invitation"))
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canPublish ? Color.brand : Color.secondary.opacity(0.35))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canPublish)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Invitation Designer")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Invitation Designer", isPresented: $showPublishResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(publishMessage)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $heroImage)
        }
        .onAppear {
            eventsService.loadEvents()
            applyInitialEventSelectionIfNeeded()
        }
        .onChange(of: hostedEvents.map { $0.id }) { _ in
            applyInitialEventSelectionIfNeeded()
        }
    }

    private var invitationHeroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isEditingExistingInvitation ? "Editing Invitation" : "Create Invitation")
                    .font(.headline)
                Spacer()
                Text("\(inviteeCount) invitees")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.brand.opacity(0.12))
                    .foregroundColor(Color.brand)
                    .clipShape(Capsule())
            }

            Text("Design and publish a polished invite with realtime updates for your event guests.")
                .font(.caption)
                .foregroundColor(.secondary)

            if !hostedEvents.isEmpty {
                Picker("Invitation", selection: $selectedHostedEventId) {
                    Text("Create new invitation").tag("")
                    ForEach(hostedEvents) { event in
                        Text("Edit: \(event.title)")
                            .tag(event.id)
                    }
                }
                .onChange(of: selectedHostedEventId) { _ in
                    applySelectedHostedEvent()
                }
            }
        }
        .padding(14)
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
                .stroke(Color.brand.opacity(0.18), lineWidth: 1)
        )
    }

    private var designerControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Occasion")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InvitationOccasion.allCases) { option in
                        Button {
                            applyOccasionPreset(option)
                        } label: {
                            Text(option.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(occasion == option ? Color.brand : Color(UIColor.tertiarySystemBackground))
                                .foregroundColor(occasion == option ? .white : .primary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Template")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InvitationTemplate.allCases) { option in
                        Button {
                            template = option
                        } label: {
                            Text(option.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(template == option ? option.accent : Color(UIColor.tertiarySystemBackground))
                                .foregroundColor(template == option ? .white : .primary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Tone")
                .font(.headline)
                .padding(.top, 2)

            HStack(spacing: 8) {
                ForEach(InvitationTone.allCases) { option in
                    Button {
                        tone = option
                    } label: {
                        Text(option.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(tone == option ? Color.brand : Color(UIColor.tertiarySystemBackground))
                            .foregroundColor(tone == option ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Background Style")
                .font(.headline)
                .padding(.top, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InvitationBackgroundStyle.allCases) { option in
                        Button {
                            backgroundStyle = option
                        } label: {
                            Text(option.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(backgroundStyle == option ? template.accent : Color(UIColor.tertiarySystemBackground))
                                .foregroundColor(backgroundStyle == option ? .white : .primary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Decoration")
                .font(.headline)
                .padding(.top, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InvitationDecoration.allCases) { option in
                        Button {
                            decoration = option
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: option.symbolName)
                                Text(option.rawValue)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(decoration == option ? Color.brand : Color(UIColor.tertiarySystemBackground))
                            .foregroundColor(decoration == option ? .white : .primary)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Layout")
                .font(.headline)
                .padding(.top, 2)

            HStack(spacing: 8) {
                ForEach(InvitationLayoutMode.allCases) { option in
                    Button {
                        layoutMode = option
                    } label: {
                        Text(option.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(layoutMode == option ? Color.brand : Color(UIColor.tertiarySystemBackground))
                            .foregroundColor(layoutMode == option ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("Subtitle (optional)", text: $subtitle)
                .textFieldStyle(.roundedBorder)
            TextField("Message", text: $message, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)

            DatePicker("Date & Time", selection: $eventDate)
            TextField("Location", text: $location)
                .textFieldStyle(.roundedBorder)
            TextField("Invite handles (comma-separated)", text: $inviteHandles)
                .textFieldStyle(.roundedBorder)

            Button {
                showImagePicker = true
            } label: {
                Label(heroImage == nil ? "Add Header Image" : "Change Header Image", systemImage: "photo")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)

            if heroImage != nil || !(selectedHostedHeaderURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                Button(role: .destructive) {
                    heroImage = nil
                    selectedHostedHeaderURL = nil
                    shouldClearHeaderImage = true
                } label: {
                    Label("Remove Header Image", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.brand.opacity(0.12), lineWidth: 1)
        )
    }

    private var invitationPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live Preview")
                    .font(.headline)
                Spacer()
                Text(template.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(template.accent.opacity(0.16))
                    .foregroundColor(template.accent)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                if let heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .clipped()
                        .cornerRadius(10)
                } else if let remote = selectedHostedHeaderURL,
                          let url = URL(string: remote),
                          remote.hasPrefix("http") {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Color.brand.opacity(0.12)
                        }
                    }
                    .frame(height: 160)
                    .clipped()
                    .cornerRadius(10)
                }

                if decoration != .none {
                    HStack {
                        Spacer()
                        Image(systemName: decoration.symbolName)
                            .font(.title2)
                            .foregroundColor(template.accent)
                        Spacer()
                    }
                }

                previewLayoutContent
            }
            .padding(14)
            .background(previewBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(template.accent.opacity(0.25), lineWidth: 1)
            )
            .cornerRadius(14)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.brand.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var previewLayoutContent: some View {
        ZStack {
            switch layoutMode {
            case .classic:
                previewClassicLayout
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity))
            case .centered:
                previewCenteredLayout
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)), removal: .opacity))
            case .poster:
                previewPosterLayout
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
            }
        }
        .id(layoutMode)
        .animation(.easeInOut(duration: 0.28), value: layoutMode)
    }

    private var previewClassicLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your Invitation Title" : title)
                .font(.title3.weight(.bold))

            if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            Text(composePreviewMessage())
                .font(.subheadline)
                .foregroundColor(.primary)

            Divider()

            Label(datePreviewFormatter.string(from: eventDate), systemImage: "calendar")
                .font(.caption)

            Label(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add location" : location, systemImage: "mappin.and.ellipse")
                .font(.caption)

            Label("RSVP via GiftMinder", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundColor(Color.brand)
        }
    }

    private var previewCenteredLayout: some View {
        VStack(spacing: 10) {
            Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your Invitation Title" : title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(composePreviewMessage())
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Divider()

            Text(datePreviewFormatter.string(from: eventDate))
                .font(.caption)
                .multilineTextAlignment(.center)

            Text(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add location" : location)
                .font(.caption)
                .multilineTextAlignment(.center)

            Text("RSVP via GiftMinder")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.brand)
        }
        .frame(maxWidth: .infinity)
    }

    private var previewPosterLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOU'RE INVITED")
                .font(.caption2.weight(.bold))
                .kerning(1.2)
                .foregroundColor(template.accent)

            Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your Invitation Title" : title)
                .font(.title2.weight(.heavy))

            if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.secondary)
            }

            Text(composePreviewMessage())
                .font(.subheadline)
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                Label(datePreviewFormatter.string(from: eventDate), systemImage: "calendar")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Capsule())

                Label(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add location" : location, systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Capsule())
            }

            Text("RSVP via GiftMinder")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.brand)
        }
    }

    private var datePreviewFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }

    private func composePreviewMessage() -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        switch tone {
        case .formal:
            return "You are cordially invited. Please RSVP at your earliest convenience."
        case .warm:
            return "I’d love for you to join me—come celebrate and make memories together."
        case .playful:
            return "Save the date! Good vibes, fun moments, and great company await 🎉"
        }
    }

    private func publishInvitation() {
        guard canPublish else { return }
        isPublishing = true

        let finalMessage = composePreviewMessage()
        let detailsBody = [
            subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            finalMessage,
            "Tone: \(tone.rawValue)",
            "Template: \(template.rawValue)",
            "Occasion: \(occasion.rawValue)",
            "Background: \(backgroundStyle.rawValue)",
            "Decoration: \(decoration.rawValue)",
            "Layout: \(layoutMode.rawValue)"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)

        if isEditingExistingInvitation {
            eventsService.updateEvent(
                eventId: selectedHostedEventId,
                title: finalTitle,
                details: detailsBody,
                theme: template.rawValue,
                startAt: eventDate,
                locationName: finalLocation,
                visibility: .inviteOnly,
                publicJoinMode: .requestApproval,
                invitedHandlesText: inviteHandles
            ) { success in
                handlePublishCompletion(success: success, eventId: selectedHostedEventId)
            }
        } else {
            eventsService.createEvent(
                title: finalTitle,
                details: detailsBody,
                theme: template.rawValue,
                startAt: eventDate,
                locationName: finalLocation,
                visibility: .inviteOnly,
                publicJoinMode: .requestApproval,
                invitedHandlesText: inviteHandles
            ) { success, eventId in
                handlePublishCompletion(success: success, eventId: eventId)
            }
        }
    }

    private func handlePublishCompletion(success: Bool, eventId: String?) {
        guard success, let eventId, !eventId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isPublishing = false
            publishMessage = "Couldn’t publish right now. Please try again."
            showPublishResult = true
            return
        }

        if let heroImage {
            eventsService.updateEventHeaderImage(eventId: eventId, image: heroImage) { uploadSuccess, url in
                DispatchQueue.main.async {
                    isPublishing = false
                    if uploadSuccess {
                        selectedHostedHeaderURL = url
                    }
                    completePublishSuccess()
                }
            }
            return
        }

        if shouldClearHeaderImage {
            eventsService.clearEventHeaderImage(eventId: eventId) { _ in
                DispatchQueue.main.async {
                    isPublishing = false
                    completePublishSuccess()
                }
            }
            return
        }

        isPublishing = false
        completePublishSuccess()
    }

    private func completePublishSuccess() {
        publishMessage = isEditingExistingInvitation
            ? "Invitation updated and synced. Invitees will see the latest version in real time."
            : "Invitation published. Invitees can now RSVP in-app, with SMS fallback available from your contacts flow."
        showPublishResult = true
        if !isEditingExistingInvitation {
            clearDraftFields()
        }
    }

    private func clearDraftFields() {
        title = ""
        subtitle = ""
        message = ""
        location = ""
        inviteHandles = ""
        occasion = .custom
        backgroundStyle = .softGlow
        decoration = .none
        layoutMode = .classic
        template = .partyPop
        tone = .warm
        heroImage = nil
        selectedHostedHeaderURL = nil
        shouldClearHeaderImage = false
    }

    private func applySelectedHostedEvent() {
        guard !selectedHostedEventId.isEmpty,
              let selectedEvent = hostedEvents.first(where: { $0.id == selectedHostedEventId }) else {
            clearDraftFields()
            eventDate = Date().addingTimeInterval(86_400)
            template = .partyPop
            tone = .warm
            return
        }

        title = selectedEvent.title
        eventDate = selectedEvent.startAt
        location = selectedEvent.locationName
        inviteHandles = selectedEvent.invitedUserHandles.joined(separator: ",")
        selectedHostedHeaderURL = selectedEvent.headerImageURL
        heroImage = nil
        shouldClearHeaderImage = false

        if let mappedTemplate = InvitationTemplate(rawValue: selectedEvent.theme) {
            template = mappedTemplate
        }

        let parsed = parseDetails(selectedEvent.details)
        subtitle = parsed.subtitle
        message = parsed.message
        if let parsedTone = parsed.tone {
            tone = parsedTone
        }
        if let parsedOccasion = parsed.occasion {
            occasion = parsedOccasion
        }
        if let parsedBackground = parsed.backgroundStyle {
            backgroundStyle = parsedBackground
        }
        if let parsedDecoration = parsed.decoration {
            decoration = parsedDecoration
        }
        if let parsedLayout = parsed.layoutMode {
            layoutMode = parsedLayout
        }
    }

    private func parseDetails(_ details: String) -> (subtitle: String, message: String, tone: InvitationTone?, occasion: InvitationOccasion?, backgroundStyle: InvitationBackgroundStyle?, decoration: InvitationDecoration?, layoutMode: InvitationLayoutMode?) {
        let lines = details.components(separatedBy: "\n")
        var parsedTone: InvitationTone?
        var parsedOccasion: InvitationOccasion?
        var parsedBackgroundStyle: InvitationBackgroundStyle?
        var parsedDecoration: InvitationDecoration?
        var parsedLayoutMode: InvitationLayoutMode?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Tone:") {
                let value = trimmed.replacingOccurrences(of: "Tone:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                parsedTone = InvitationTone(rawValue: value)
            } else if trimmed.hasPrefix("Occasion:") {
                let value = trimmed.replacingOccurrences(of: "Occasion:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                parsedOccasion = InvitationOccasion(rawValue: value)
            } else if trimmed.hasPrefix("Background:") {
                let value = trimmed.replacingOccurrences(of: "Background:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                parsedBackgroundStyle = InvitationBackgroundStyle(rawValue: value)
            } else if trimmed.hasPrefix("Decoration:") {
                let value = trimmed.replacingOccurrences(of: "Decoration:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                parsedDecoration = InvitationDecoration(rawValue: value)
            } else if trimmed.hasPrefix("Layout:") {
                let value = trimmed.replacingOccurrences(of: "Layout:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                parsedLayoutMode = InvitationLayoutMode(rawValue: value)
            }
        }

        let cleanedLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.hasPrefix("Tone:")
                && !trimmed.hasPrefix("Template:")
                && !trimmed.hasPrefix("Occasion:")
                && !trimmed.hasPrefix("Background:")
                && !trimmed.hasPrefix("Decoration:")
                && !trimmed.hasPrefix("Layout:")
        }

        let cleanedBody = cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleanedBody
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if parts.count >= 2 {
            return (
                subtitle: parts[0],
                message: parts.dropFirst().joined(separator: "\n\n"),
                tone: parsedTone,
                occasion: parsedOccasion,
                backgroundStyle: parsedBackgroundStyle,
                decoration: parsedDecoration,
                layoutMode: parsedLayoutMode
            )
        }

        return (
            subtitle: "",
            message: cleanedBody,
            tone: parsedTone,
            occasion: parsedOccasion,
            backgroundStyle: parsedBackgroundStyle,
            decoration: parsedDecoration,
            layoutMode: parsedLayoutMode
        )
    }

    private func applyOccasionPreset(_ option: InvitationOccasion) {
        occasion = option

        switch option {
        case .custom:
            return
        case .birthday:
            template = .partyPop
            tone = .playful
            backgroundStyle = .confetti
            decoration = .stars
            layoutMode = .poster
            title = "Birthday Celebration"
            subtitle = "You’re invited to celebrate!"
            message = "Join us for cake, laughs, and a memorable celebration."
        case .babyShower:
            template = .elegant
            tone = .warm
            backgroundStyle = .pastel
            decoration = .sparkles
            layoutMode = .centered
            title = "Baby Shower"
            subtitle = "Celebrate with us"
            message = "We’re excited to celebrate this special moment with friends and family."
        case .wedding:
            template = .elegant
            tone = .formal
            backgroundStyle = .sunset
            decoration = .floral
            layoutMode = .classic
            title = "Wedding Celebration"
            subtitle = "Save the Date"
            message = "You are warmly invited to celebrate our wedding day together."
        case .holiday:
            template = .minimal
            tone = .warm
            backgroundStyle = .glowNight
            decoration = .confetti
            layoutMode = .poster
            title = "Holiday Gathering"
            subtitle = "Seasonal Celebration"
            message = "Let’s gather for festive food, joy, and quality time."
        case .housewarming:
            template = .minimal
            tone = .warm
            backgroundStyle = .softGlow
            decoration = .sparkles
            layoutMode = .centered
            title = "Housewarming Party"
            subtitle = "Come see our new place"
            message = "Stop by for a cozy evening and help us celebrate our new home."
        }
    }

    private func applyInitialEventSelectionIfNeeded() {
        guard selectedHostedEventId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let initialEventId,
              !initialEventId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hostedEvents.contains(where: { $0.id == initialEventId }) else {
            return
        }

        selectedHostedEventId = initialEventId
        applySelectedHostedEvent()
    }
}

private enum InvitationTemplate: String, CaseIterable, Identifiable {
    case minimal = "Minimal"
    case partyPop = "Party Pop"
    case elegant = "Elegant"
    case playful = "Playful"

    var id: String { rawValue }

    var accent: Color {
        switch self {
        case .minimal: return .blue
        case .partyPop: return .pink
        case .elegant: return .purple
        case .playful: return .orange
        }
    }
}

private enum InvitationTone: String, CaseIterable, Identifiable {
    case formal = "Formal"
    case warm = "Warm"
    case playful = "Playful"

    var id: String { rawValue }
}

private enum InvitationOccasion: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case birthday = "Birthday"
    case babyShower = "Baby Shower"
    case wedding = "Wedding"
    case holiday = "Holiday"
    case housewarming = "Housewarming"

    var id: String { rawValue }
}

private enum InvitationBackgroundStyle: String, CaseIterable, Identifiable {
    case softGlow = "Soft Glow"
    case confetti = "Confetti"
    case sunset = "Sunset"
    case glowNight = "Glow Night"
    case pastel = "Pastel"

    var id: String { rawValue }

    func gradient(accent: Color) -> LinearGradient {
        switch self {
        case .softGlow:
            return LinearGradient(
                colors: [accent.opacity(0.18), Color(UIColor.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .confetti:
            return LinearGradient(
                colors: [Color.pink.opacity(0.22), Color.orange.opacity(0.18), Color.yellow.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sunset:
            return LinearGradient(
                colors: [Color.orange.opacity(0.22), Color.purple.opacity(0.18), Color.pink.opacity(0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .glowNight:
            return LinearGradient(
                colors: [Color.indigo.opacity(0.26), Color.blue.opacity(0.2), Color.black.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .pastel:
            return LinearGradient(
                colors: [Color.mint.opacity(0.18), Color.pink.opacity(0.14), Color.teal.opacity(0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private enum InvitationDecoration: String, CaseIterable, Identifiable {
    case none = "None"
    case stars = "Stars"
    case sparkles = "Sparkles"
    case confetti = "Confetti"
    case floral = "Floral"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .none:
            return "circle"
        case .stars:
            return "sparkles"
        case .sparkles:
            return "wand.and.stars"
        case .confetti:
            return "party.popper.fill"
        case .floral:
            return "leaf.fill"
        }
    }
}

private enum InvitationLayoutMode: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case centered = "Centered"
    case poster = "Poster"

    var id: String { rawValue }
}

struct ContactPickerView: UIViewControllerRepresentable {
    var onSelect: ([CNContact]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onSelect: ([CNContact]) -> Void
        private let onCancel: () -> Void

        init(onSelect: @escaping ([CNContact]) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onSelect(contacts)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}

// Preference key to report each month's mid Y position inside the scroll
private struct MonthMidYPreferenceKey: PreferenceKey {
    typealias Value = [Int: CGFloat]
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// Preference key reporting each month's top Y (minY) within the scroll coordinate space
private struct MonthTopPreferenceKey: PreferenceKey {
    typealias Value = [Int: CGFloat]
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// Calendar view: vertically scrollable months with a minimalist look
struct CalendarView: View {
    @EnvironmentObject var contactStore: ContactStore

    @State private var selectedDateContacts: [Contact] = []
    @State private var showDaySheet: Bool = false
    @State private var centeredOffset: Int = 0
    @State private var showAddContactSheet: Bool = false
    @State private var showExistingContactSheet: Bool = false
    @State private var showExistingEventSheet: Bool = false
    @State private var showPersonalEventSheet: Bool = false
    @State private var selectedExistingContact: Contact? = nil
    @Environment(\.presentationMode) private var presentationMode
    @State private var userDOBTime: Double = loadScopedUserDOBTime()
    @State private var userAnniversaryTime: Double = loadScopedUserAnniversaryTime()
    @State private var userOtherDatesRaw: String = loadScopedUserOtherDatesRaw()

    private typealias PersonalDateEntry = PersonalDateRecord

    private let calendar = Calendar.current
    private let monthRange = Array(-12...12)

    @State private var selectedDate: Date? = nil

    var body: some View {
        AppNavigationView {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Sticky header showing the month corresponding to the top-most fully visible month
                    HStack {
                        Text(currentMonthHeader)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Done") { dismiss() }
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)
                    .background(Color(UIColor.systemBackground))

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 12) {
                            ForEach(monthRange, id: \.self) { offset in
                                MonthCard(offset: offset, contacts: contactStore.contacts, onDayTap: { date, matches in
                                    // set selected date and contacts, animate popup
                                    selectedDate = date
                                    selectedDateContacts = matches
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showDaySheet = true
                                    }
                                })
                                .id(offset)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal)
                                // report the top of each month so we can determine which month is visible
                                .background(GeometryReader { proxy in
                                    Color.clear.preference(key: MonthTopPreferenceKey.self, value: [offset: proxy.frame(in: .named("calendarScroll")).minY])
                                })
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .coordinateSpace(name: "calendarScroll")
                    .onPreferenceChange(MonthTopPreferenceKey.self) { tops in
                        // Determine the month whose top is closest to the top inset (below header)
                        let headerHeight: CGFloat = 60
                        let targetY = headerHeight
                        if let closest = tops.min(by: { abs($0.value - targetY) < abs($1.value - targetY) })?.key {
                            if closest != centeredOffset {
                                withAnimation(.easeInOut) { centeredOffset = closest }
                            }
                        }
                    }
                }
            }
            .overlay(
                Group {
                    if showDaySheet {
                        DayContactsPopup(
                            date: selectedDate ?? Date(),
                            contacts: selectedDateContacts,
                            onAddNew: {
                                showAddContactSheet = true
                            },
                            onSelectExisting: {
                                showExistingContactSheet = true
                            },
                            onAddForMe: {
                                showPersonalEventSheet = true
                            },
                            onClose: {
                                withAnimation(.easeInOut) {
                                    showDaySheet = false
                                    selectedDate = nil
                                    selectedDateContacts = []
                                }
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            )
            .sheet(isPresented: $showAddContactSheet) {
                AddContactView(prefillBirthday: selectedDate)
            }
            .sheet(isPresented: $showExistingContactSheet) {
                ExistingContactPickerView(date: selectedDate ?? Date()) { contact in
                    selectedExistingContact = contact
                    showExistingEventSheet = true
                }
            }
            .sheet(isPresented: $showExistingEventSheet) {
                if let contact = selectedExistingContact, let date = selectedDate {
                    ExistingContactEventTypeSheet(
                        contact: contact,
                        date: date,
                        onSave: { eventType, title in
                            switch eventType {
                            case .birthday:
                                applyBirthday(date: date, to: contact)
                            case .anniversary:
                                applyAnniversary(date: date, to: contact)
                            case .customEvent:
                                applyCustomEvent(title: title, date: date, to: contact)
                            }
                        },
                        onCancel: { showExistingEventSheet = false }
                    )
                }
            }
            .sheet(isPresented: $showPersonalEventSheet) {
                if let date = selectedDate {
                    PersonalEventTypeSheet(
                        date: date,
                        onSave: { eventType, title in
                            switch eventType {
                            case .birthday:
                                userDOBTime = normalized(date).timeIntervalSince1970
                                saveScopedUserDOBTime(userDOBTime)
                                persistPersonalDatesToFirestore()
                            case .anniversary:
                                userAnniversaryTime = normalized(date).timeIntervalSince1970
                                saveScopedUserAnniversaryTime(userAnniversaryTime)
                                persistPersonalDatesToFirestore()
                            case .customEvent:
                                addPersonalCustomEvent(title: title, date: date)
                            }
                            closeDaySheets()
                        },
                        onCancel: { showPersonalEventSheet = false }
                    )
                }
            }
            .onAppear {
                userDOBTime = loadScopedUserDOBTime()
                userAnniversaryTime = loadScopedUserAnniversaryTime()
                userOtherDatesRaw = loadScopedUserOtherDatesRaw()
            }
        }
    }

    private var currentMonthHeader: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        let date = calendar.date(byAdding: .month, value: centeredOffset, to: Date()) ?? Date()
        return formatter.string(from: date)
    }

    private func dismiss() { presentationMode.wrappedValue.dismiss() }

    private func applyBirthday(date: Date, to contact: Contact) {
        guard let index = contactStore.contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        let normalizedDate = normalized(date)
        contactStore.contacts[index].dateOfBirth = normalizedDate
        contactStore.contacts[index].hasBirthday = true
        contactStore.contacts[index].isBirthYearKnown = false
        contactStore.contacts[index].updatedAt = Date()
        closeDaySheets()
    }

    private func applyAnniversary(date: Date, to contact: Contact) {
        guard let index = contactStore.contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        let normalizedDate = normalized(date)
        contactStore.contacts[index].anniversaryDate = normalizedDate
        contactStore.contacts[index].isAnniversaryYearKnown = false
        contactStore.contacts[index].updatedAt = Date()
        closeDaySheets()
    }

    private func applyCustomEvent(title: String, date: Date, to contact: Contact) {
        guard let index = contactStore.contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        let normalizedDate = normalized(date)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventTitle = trimmedTitle.isEmpty ? "Event" : trimmedTitle
        let newEvent = ContactEvent(title: eventTitle, date: normalizedDate, isYearKnown: false)
        contactStore.contacts[index].customEvents.append(newEvent)
        contactStore.contacts[index].updatedAt = Date()
        closeDaySheets()
    }

    private func normalized(_ date: Date) -> Date {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        if comps.year == nil { comps.year = calendar.component(.year, from: Date()) }
        if comps.month == nil { comps.month = calendar.component(.month, from: Date()) }
        if comps.day == nil { comps.day = calendar.component(.day, from: Date()) }
        return calendar.date(from: comps) ?? date
    }

    private func closeDaySheets() {
        withAnimation(.easeInOut) {
            showDaySheet = false
            showExistingContactSheet = false
            showExistingEventSheet = false
            showPersonalEventSheet = false
            selectedExistingContact = nil
            selectedDate = nil
            selectedDateContacts = []
        }
    }

    private func addPersonalCustomEvent(title: String, date: Date) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventTitle = trimmedTitle.isEmpty ? "Event" : trimmedTitle
        var existing = loadPersonalDates()
        existing.append(
            PersonalDateEntry(
                label: eventTitle,
                time: normalized(date).timeIntervalSince1970
            )
        )
        savePersonalDates(existing)
    }

    private func loadPersonalDates() -> [PersonalDateEntry] {
        PersonalDateStore.load(from: userOtherDatesRaw)
    }

    private func savePersonalDates(_ entries: [PersonalDateEntry]) {
        if let raw = PersonalDateStore.encode(entries) {
            userOtherDatesRaw = raw
            saveScopedUserOtherDatesRaw(raw)
            persistPersonalDatesToFirestore()
        }
    }

    private func persistPersonalDatesToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload: [[String: Any]] = loadPersonalDates().map { entry in
            [
                "label": entry.label,
                "time": entry.time,
            ]
        }

        Firestore.firestore().collection("users").document(uid).setData([
            "userDOBTime": userDOBTime,
            "userAnniversaryTime": userAnniversaryTime,
            "userOtherDates": payload,
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true)
    }
}

// A minimal, card-like month view used inside the vertical stack
struct MonthCard: View {
    let offset: Int
    let contacts: [Contact]
    var onDayTap: (Date, [Contact]) -> Void

    private let calendar = Calendar.current

    private var monthDate: Date {
        calendar.date(byAdding: .month, value: offset, to: Date()) ?? Date()
    }

    private var startOfMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate)) ?? Date()
    }

    private var firstWeekdayIndex: Int {
        calendar.component(.weekday, from: startOfMonth) - 1
    }

    private var totalCells: Int { 42 }

    private func dateForCell(at index: Int) -> Date {
        let lead = firstWeekdayIndex
        let dayNumber = index - lead + 1
        return calendar.date(byAdding: .day, value: dayNumber - 1, to: startOfMonth) ?? startOfMonth
    }

    private func contacts(on date: Date) -> [Contact] {
        contacts.filter { contact in
            guard contact.hasBirthday else { return false }
            let cMonth = calendar.component(.month, from: contact.dateOfBirth)
            let cDay = calendar.component(.day, from: contact.dateOfBirth)
            let dMonth = calendar.component(.month, from: date)
            let dDay = calendar.component(.day, from: date)
            return cMonth == dMonth && cDay == dDay
        }
    }

    private func dotColor(for contact: Contact) -> Color { Color.brand }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 10) {
                // month header with subtle card look
                Text(monthTitle)
                    .font(.headline)
                    .padding(.vertical, 8)

                HStack(spacing: 0) {
                    ForEach(calendar.shortStandaloneWeekdaySymbols, id: \.self) { wd in
                        Text(wd)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                    ForEach(0..<totalCells, id: \.self) { idx in
                        let cellDate = dateForCell(at: idx)
                        let inMonth = calendar.isDate(cellDate, equalTo: startOfMonth, toGranularity: .month)
                        let dayNumber = calendar.component(.day, from: cellDate)
                        let matches = contacts(on: cellDate)

                        Button(action: {
                            onDayTap(cellDate, matches)
                        }) {
                            VStack(spacing: 6) {
                                Text("\(dayNumber)")
                                    .font(.subheadline)
                                    .foregroundColor(inMonth ? .primary : .secondary)

                                // Minimal dots for events with fade-in animation
                                HStack(spacing: 6) {
                                    ForEach(matches.prefix(3), id: \.id) { _ in
                                        Circle()
                                            .fill(dotColor(for: contacts.first!))
                                            .frame(width: 7, height: 7)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                    if matches.count > 3 {
                                        Text("+\(matches.count - 3)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(height: 12)
                            }
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(BounceButtonStyle())
                    }
                }
                .padding(.horizontal)

            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(UIColor.secondarySystemBackground).opacity(0.9))
                    .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
            )
        }
    }
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: monthDate)
    }
}

struct DayContactsListView: View {
    let date: Date
    let contacts: [Contact]

    var body: some View {
        AppNavigationView {
            List {
                ForEach(contacts) { c in
                    VStack(alignment: .leading) {
                        Text(c.name).font(.headline)
                        Text(reasonString(for: c)).font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(dayTitle)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(action: { dismiss() }) { Text("Done") } } }
        }
    }

    private var dayTitle: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        return fmt.string(from: date)
    }

    @Environment(\.presentationMode) private var presentationMode
    private func dismiss() { presentationMode.wrappedValue.dismiss() }

    private func reasonString(for contact: Contact) -> String {
        let days = contact.daysUntilBirthday
        if days == 0 { return "Birthday — Today" }
        return "Birthday in \(days) day\(days == 1 ? "" : "s")"
    }
}

// Popup view shown when tapping a day — sleek card with close button
struct DayContactsPopup: View {
    let date: Date
    let contacts: [Contact]
    var onAddNew: () -> Void
    var onSelectExisting: () -> Void
    var onAddForMe: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                HStack {
                    Text(dayTitle)
                        .font(.headline)
                    Spacer()
                    Button(action: onClose) {
                        Text("Done").foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)

                if contacts.isEmpty {
                    Text("No events")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(contacts) { c in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(c.name).font(.headline)
                                Text(reasonString(for: c)).font(.subheadline).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.systemBackground)))
                        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                    }
                }

                HStack(spacing: 12) {
                    Button(action: onAddNew) {
                        Text("Add New Contact")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.brand)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button(action: onSelectExisting) {
                        Text("Use Existing")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)

                Button(action: onAddForMe) {
                    Text("Add Event For Me")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.brand.opacity(0.12))
                        .foregroundColor(Color.brand)
                        .cornerRadius(10)
                }
                .padding(.horizontal)

            }
            .padding(.vertical)
            .background(VisualEffectBlur(blurStyle: .systemThinMaterial))
            .cornerRadius(16)
            .padding()
        }
        .edgesIgnoringSafeArea(.bottom)
    }

    private var dayTitle: String {
        let fmt = DateFormatter(); fmt.dateStyle = .full; return fmt.string(from: date)
    }

    private func reasonString(for contact: Contact) -> String {
        let days = contact.daysUntilBirthday
        if days == 0 { return "Birthday — Today" }
        return "Birthday in \(days) day\(days == 1 ? "" : "s")"
    }
}

struct ExistingContactPickerView: View {
    @EnvironmentObject var contactStore: ContactStore
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let onSelect: (Contact) -> Void

    @State private var searchText = ""

    private var filteredContacts: [Contact] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return contactStore.contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return contactStore.contacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        AppNavigationView {
            List {
                if filteredContacts.isEmpty {
                    Text("No contacts found")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(filteredContacts) { contact in
                        Button(action: {
                            onSelect(contact)
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                if let data = contact.photoData, let ui = UIImage(data: data) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                        .overlay(Text(initials(for: contact.name)).font(.caption))
                                }

                                VStack(alignment: .leading) {
                                    Text(contact.name)
                                        .font(.headline)
                                    Text("Assign \(formattedDate)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Choose Contact")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .filter { !$0.isEmpty }
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? parts.last?.prefix(1) ?? "" : ""
        let initials = "\(first)\(last)"
        return initials.isEmpty ? "?" : initials.uppercased()
    }
}

struct ExistingContactEventTypeSheet: View {
    enum EventType: String, CaseIterable, Identifiable {
        case birthday = "Birthday"
        case anniversary = "Anniversary"
        case customEvent = "Event"

        var id: String { rawValue }
    }

    let contact: Contact
    let date: Date
    let onSave: (EventType, String) -> Void
    let onCancel: () -> Void

    @State private var selectedType: EventType = .birthday
    @State private var eventTitle: String = "Event"

    var body: some View {
        AppNavigationView {
            Form {
                Section("Assign Date") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(EventType.allCases) { eventType in
                            Text(eventType.rawValue).tag(eventType)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    if selectedType == .customEvent {
                        TextField("Event title", text: $eventTitle)
                    }
                }

                Section {
                    Text("\(contact.name) -> \(formattedDate)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add to Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let title = trimmed.isEmpty ? "Event" : trimmed
                        onSave(selectedType, title)
                    }
                    .disabled(selectedType == .customEvent && eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }
}

struct PersonalEventTypeSheet: View {
    enum EventType: String, CaseIterable, Identifiable {
        case birthday = "Birthday"
        case anniversary = "Anniversary"
        case customEvent = "Event"

        var id: String { rawValue }
    }

    let date: Date
    let onSave: (EventType, String) -> Void
    let onCancel: () -> Void

    @State private var selectedType: EventType = .birthday
    @State private var eventTitle: String = "Event"

    var body: some View {
        AppNavigationView {
            Form {
                Section("Set For Me") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(EventType.allCases) { eventType in
                            Text(eventType.rawValue).tag(eventType)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    if selectedType == .customEvent {
                        TextField("Event title", text: $eventTitle)
                    }
                }

                Section {
                    Text("Me → \(formattedDate)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Personal Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let title = trimmed.isEmpty ? "Event" : trimmed
                        onSave(selectedType, title)
                    }
                    .disabled(selectedType == .customEvent && eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }
}

// Small bounce button style for tap animation
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct StylishSectionHeader: View {
    let title: String
    let icon: String
    let style: Style
    let showsShine: Bool
    @State private var isShining = false

    enum Style {
        case primary
        case secondary
    }

    var body: some View {
        switch style {
        case .primary:
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.18)))
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(LinearGradient(colors: [Color.brandStart, Color.brandEnd], startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .overlay(
                GeometryReader { proxy in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.0), Color.white.opacity(0.45), Color.white.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .rotationEffect(.degrees(20))
                        .offset(x: isShining ? proxy.size.width * 1.6 : -proxy.size.width * 1.6)
                }
                .clipped()
                .opacity(showsShine ? 1 : 0)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
            .padding(.horizontal, 2)
            .onAppear {
                guard showsShine else { return }
                isShining = false
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                    isShining = true
                }
            }
        case .secondary:
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(Color.brand)
                    .padding(6)
                    .background(Circle().fill(Color.brand.opacity(0.12)))
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .padding(.horizontal, 2)
        }
    }
}

// (VisualEffectBlur is defined earlier in this file)

struct ContactRowView: View {
    let contact: Contact
    var showUpcomingEvent: Bool = false
    var isGiftMinderUser: Bool = false
    @State private var animateIn = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.14))
                    .frame(width: 52, height: 52)
                if let data = contact.photoData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                } else {
                    Image(systemName: contact.relationship.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.brand)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(contact.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    if showUpcomingEvent, let upcomingEventText = upcomingEventText {
                        Text(upcomingEventText)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                            .foregroundColor(.orange)
                    }
                }

                Text(contact.relationship.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: isGiftMinderUser ? "checkmark.seal.fill" : "person.crop.circle")
                        .font(.caption2)
                        .foregroundColor(isGiftMinderUser ? .green : .secondary)
                    Text(isGiftMinderUser ? "GiftMinder user" : "Non-user")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if !contact.interests.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(contact.interests.prefix(3), id: \.self) { interest in
                                Text(interest.capitalized)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.brand.opacity(0.08)))
                                    .foregroundColor(Color.brand)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.brand.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
        )
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                animateIn = true
            }
        }
    }

    private var upcomingEventText: String? {
        guard contact.hasBirthday else { return nil }
        let days = contact.daysUntilBirthday
        guard days >= 0 && days <= 30 else { return nil }
        if days == 0 {
            return "Birthday today"
        }
        return "Birthday in \(days) day\(days == 1 ? "" : "s")"
    }
}

struct EmptyContactsView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Contacts Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Start by adding one contact so reminders, invites, and shopping suggestions can be personalized.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Tap Add Contact")
                Text("2. Add a birthday or anniversary")
                Text("3. Save and view upcoming reminders")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct UpcomingBirthdaysCard: View {
    let contacts: [Contact]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "birthday.cake.fill")
                    .foregroundColor(.orange)
                Text("Upcoming Birthdays")
                    .font(.headline)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(contacts.prefix(5)) { contact in
                        BirthdayContactView(contact: contact)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct BirthdayContactView: View {
    let contact: Contact

    var body: some View {
        VStack(spacing: 4) {
            Text(contact.name.split(separator: " ").first?.description ?? contact.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            Text("\(contact.daysUntilBirthday)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.orange)

            Text(contact.daysUntilBirthday == 1 ? "day" : "days")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 60)
    }
}

// MARK: - Event Stat Model

struct EventStat: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let color: Color
}

// MARK: - Contact Detail View

struct ContactDetailView: View {
    let contact: Contact
    @EnvironmentObject var giftService: GiftService
    @EnvironmentObject var contactStore: ContactStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditSheet = false
    @State private var editingContact: Contact
    @State private var startEditInNotes = false
    @State private var contactGifts: [ContactGift] = []
    @State private var showAddGiftSheet = false
    @State private var editingGift: ContactGift?
    @State private var isLoadingGifts = false
    @State private var remoteProfile: RemoteContactProfile?
    @State private var remoteProfileListener: ListenerRegistration?
    private let contactId: UUID

    private struct RemoteContactEvent {
        let label: String
        let time: TimeInterval
    }

    private struct RemoteContactProfile {
        let displayName: String
        let userId: String?
        let bio: String
        let interests: [String]
        let dobTime: TimeInterval
        let anniversaryTime: TimeInterval
        let otherDates: [RemoteContactEvent]
    }

    init(contact: Contact) {
        self.contact = contact
        self.contactId = contact.id
        _editingContact = State(initialValue: contact)
    }

    private var recommendations: [Gift] {
        giftService.getRecommendations(for: contactForDisplay)
    }

    private var giftMinderUid: String? {
        let source = (contact.sourceIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.lowercased().hasPrefix("firebase:") else { return nil }
        let uid = String(source.dropFirst("firebase:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return uid.isEmpty ? nil : uid
    }

    private var isGiftMinderManagedContact: Bool {
        giftMinderUid != nil
    }

    private var canEditWishlist: Bool {
        guard let currentUid = Auth.auth().currentUser?.uid.trimmingCharacters(in: .whitespacesAndNewlines), !currentUid.isEmpty else {
            return false
        }

        if let managedUid = giftMinderUid?.trimmingCharacters(in: .whitespacesAndNewlines), !managedUid.isEmpty {
            return managedUid == currentUid
        }

        return true
    }

    private var contactForDisplay: Contact {
        // Always get fresh data from store for real-time updates
        var resolved = contactStore.contacts.first(where: { $0.id == contactId }) ?? contact

        guard let remoteProfile else {
            return resolved
        }

        resolved.name = remoteProfile.displayName
        resolved.notes = remoteProfile.bio
        resolved.interests = remoteProfile.interests

        if remoteProfile.dobTime > 0 {
            resolved.hasBirthday = true
            resolved.isBirthYearKnown = false
            resolved.dateOfBirth = Date(timeIntervalSince1970: remoteProfile.dobTime)
        } else {
            resolved.hasBirthday = false
        }

        if remoteProfile.anniversaryTime > 0 {
            resolved.anniversaryDate = Date(timeIntervalSince1970: remoteProfile.anniversaryTime)
            resolved.isAnniversaryYearKnown = false
        } else {
            resolved.anniversaryDate = nil
        }

        resolved.customEvents = remoteProfile.otherDates.map { event in
            ContactEvent(title: event.label, date: Date(timeIntervalSince1970: event.time), isYearKnown: false)
        }

        return resolved
    }

    var body: some View {
        ZStack {
            AppBackground()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    profileHeaderSection
                    
                    VStack(spacing: 16) {
                        aboutSection
                        upcomingEventsSection
                        interestsSection
                        wishlistSection
                        giftsSection
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
            .coordinateSpace(name: "contactDetailScroll")
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingEditSheet) {
            EditContactView(
                contact: $editingContact,
                isPresented: $showingEditSheet,
                startInNotes: startEditInNotes,
                onSave: saveContact
            )
        }
        .onAppear(perform: startRemoteProfileListenerIfNeeded)
        .onAppear {
            if isGiftMinderManagedContact {
                showingEditSheet = false
                showAddGiftSheet = false
            }
        }
        .onDisappear {
            remoteProfileListener?.remove()
            remoteProfileListener = nil
        }
    }

    private var profileHeaderSection: some View {
        let contact = contactForDisplay
        let avatarSize: CGFloat = 96
        let bannerHeight: CGFloat = 140
        
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Banner
                LinearGradient(
                    colors: [Color.brandStart, Color.brandEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: bannerHeight)
                .ignoresSafeArea(edges: .top)
                
                // Back button
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }
                .padding(.leading, 16)
                .padding(.top, 8)
            }
            
            VStack(spacing: 12) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let data = contact.photoData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ZStack {
                                Circle().fill(Color.brand)
                                Text(initials(for: contact.name))
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 4))
                    .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 4)
                    
                    // Edit button
                    if !isGiftMinderManagedContact {
                        Button(action: {
                            editingContact = contactForDisplay
                            startEditInNotes = false
                            showingEditSheet = true
                        }) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.brand).frame(width: 28, height: 28))
                        }
                    }
                }
                .offset(y: -avatarSize * 0.4)
                
                VStack(spacing: 6) {
                    Text(contact.name)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("@\(remoteProfile?.userId ?? contact.name.lowercased().replacingOccurrences(of: " ", with: ""))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .offset(y: -avatarSize * 0.3)
            }
            .padding(.horizontal)
        }
    }

    private var aboutSection: some View {
        let contact = contactForDisplay
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("About")
                    .font(.headline)
                Spacer()
                if !isGiftMinderManagedContact {
                    Button(action: {
                        editingContact = contactForDisplay
                        startEditInNotes = true
                        showingEditSheet = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(Color.brand)
                    }
                } else {
                    Text("Synced")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }

            if contact.notes.isEmpty {
                Text("Write a short bio to let others know their gift preferences, favorite interests, and style.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text(contact.notes)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
        .padding(.horizontal)
    }

    private var eventStats: [EventStat] {
        let contact = contactForDisplay
        var stats: [EventStat] = []

        if contact.hasBirthday {
            stats.append(
                EventStat(
                    title: "Next Birthday",
                    value: daysText(contact.daysUntilBirthday),
                    icon: "birthday.cake.fill",
                    color: .orange
                )
            )
            stats.append(
                EventStat(
                    title: "Birthday",
                    value: monthDayOnly(contact.dateOfBirth),
                    icon: "calendar",
                    color: .blue
                )
            )
        }

        if let ann = contact.anniversaryDate {
            let annValue = contact.isAnniversaryYearKnown
                ? marriageYearsText(for: ann)
                : daysText(daysUntilAnniversary(ann))
            stats.append(
                EventStat(
                    title: "Anniversary",
                    value: annValue,
                    icon: "heart.circle.fill",
                    color: Color(red: 0.9, green: 0.4, blue: 0.6)
                )
            )
        }

        let customUpcoming = contact.customEvents
            .sorted { daysUntilEvent($0) < daysUntilEvent($1) }

        for event in customUpcoming {
            stats.append(
                EventStat(
                    title: event.title,
                    value: daysText(daysUntilEvent(event)),
                    icon: "star.fill",
                    color: .yellow
                )
            )
        }

        return stats
    }

    private var upcomingEventsSection: some View {
        let stats = eventStats
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Upcoming Events", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                if !stats.isEmpty {
                    Text("\(stats.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.brand))
                }
            }
            .padding(.horizontal)

            if stats.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    VStack(spacing: 4) {
                        Text("No upcoming events")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Text("Add a birthday, anniversary, or custom event")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(stats) { stat in
                        EventCard(
                            title: stat.title,
                            value: stat.value,
                            icon: stat.icon,
                            color: stat.color
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func daysText(_ days: Int) -> String {
        if days == 0 {
            return "Today"
        } else if days == 1 {
            return "Tomorrow"
        }
        return "\(days) days"
    }
    
    private func daysUntilAnniversary(_ anniversaryDate: Date) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        
        var nextAnniversary = calendar.date(
            byAdding: .year,
            value: currentYear - calendar.component(.year, from: anniversaryDate),
            to: anniversaryDate
        ) ?? anniversaryDate
        
        if nextAnniversary < now {
            nextAnniversary = calendar.date(byAdding: .year, value: 1, to: nextAnniversary) ?? anniversaryDate
        }
        
        return calendar.dateComponents([.day], from: now, to: nextAnniversary).day ?? 0
    }

    private func marriageYearsText(for anniversaryDate: Date) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let annYear = calendar.component(.year, from: anniversaryDate)
        let years = max(0, currentYear - annYear)
        return years == 1 ? "1 yr" : "\(years) yrs"
    }
    
    private func daysUntilEvent(_ event: ContactEvent) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let eventYear = calendar.component(.year, from: event.date)
        
        // Start with the event in the current year if it hasn't passed, otherwise next year
        var nextEventDate = calendar.date(
            byAdding: .year,
            value: currentYear - eventYear,
            to: event.date
        ) ?? event.date
        
        if nextEventDate < now {
            nextEventDate = calendar.date(byAdding: .year, value: 1, to: nextEventDate) ?? event.date
        }
        
        return calendar.dateComponents([.day], from: now, to: nextEventDate).day ?? 0
    }

    private var interestsSection: some View {
        let contact = contactForDisplay
        return VStack(alignment: .leading, spacing: 10) {
            Text("Interests")
                .font(.headline)

            if contact.interests.isEmpty {
                Text("No interests added yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(contact.interests, id: \.self) { interest in
                            HStack(spacing: 6) {
                                Text(interest.capitalized)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.brand.opacity(0.12)))
                            .foregroundColor(Color.brand)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(.horizontal)
    }

    private var wishlistSection: some View {
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Shop Suggestions", systemImage: "gift")
                    .font(.headline)
                Spacer()
                if !recommendations.isEmpty {
                    Text("\(recommendations.count)+")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.brand))
                }
            }
            .padding(.horizontal)

            if recommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "gift")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    VStack(spacing: 4) {
                        Text("No shop suggestions yet")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Text("Add interests to see personalized shop suggestions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recommendations.prefix(10)) { gift in
                            ProductCard(gift: gift)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var giftsSection: some View {
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Your Gifts", systemImage: "🎁")
                    .font(.headline)
                Spacer()
                if !contactGifts.isEmpty {
                    Text("\(contactGifts.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.brand))
                }
                if canEditWishlist {
                    Button(action: {
                        editingGift = nil
                        showAddGiftSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.brand)
                    }
                }
            }
            .padding(.horizontal)

            if !canEditWishlist {
                Text("This wishlist is view-only for your account.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            if contactGifts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    VStack(spacing: 4) {
                        Text("No gifts yet")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Text("Add items to shop for this contact")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    let wishlist = contactGifts.filter { $0.status == "wishlist" }
                    let purchased = contactGifts.filter { $0.status == "purchased" }

                    if !wishlist.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Wishlist")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            ForEach(wishlist) { gift in
                                ContactGiftRowView(
                                    gift: gift,
                                    isReadOnly: !canEditWishlist,
                                    onTap: {
                                        guard canEditWishlist else { return }
                                        editingGift = gift
                                        showAddGiftSheet = true
                                    },
                                    onTogglePurchased: {
                                        guard canEditWishlist else { return }
                                        markGiftPurchased(gift, purchased: true)
                                    },
                                    onDelete: {
                                        guard canEditWishlist else { return }
                                        deleteGift(gift)
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                    }

                    if !purchased.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            if !wishlist.isEmpty {
                                Divider()
                                    .padding(.vertical, 4)
                            }

                            Text("Purchased")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            ForEach(purchased) { gift in
                                ContactGiftRowView(
                                    gift: gift,
                                    isReadOnly: !canEditWishlist,
                                    onTap: {
                                        guard canEditWishlist else { return }
                                        editingGift = gift
                                        showAddGiftSheet = true
                                    },
                                    onTogglePurchased: {
                                        guard canEditWishlist else { return }
                                        markGiftPurchased(gift, purchased: false)
                                    },
                                    onDelete: {
                                        guard canEditWishlist else { return }
                                        deleteGift(gift)
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(14)
                .padding(.horizontal)
            }
        }
        .onAppear {
            loadContactGifts()
        }
        .sheet(isPresented: $showAddGiftSheet) {
            AddEditGiftView(
                contact: contactForDisplay,
                gift: editingGift,
                isPresented: $showAddGiftSheet,
                onSave: { _ in
                    loadContactGifts()
                }
            )
        }
    }

    private var nextBirthdayText: String {
        let contact = contactForDisplay
        guard contact.hasBirthday else { return "—" }
        if contact.daysUntilBirthday == 0 {
            return "Today! 🎉"
        } else if contact.daysUntilBirthday == 1 {
            return "Tomorrow"
        }
        return "\(contact.daysUntilBirthday) days"
    }

    private func monthDayOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first.map { String($0.prefix(1)) } ?? ""
        let last = parts.count > 1 ? String(parts.last!.prefix(1)) : ""
        return (first + last).uppercased()
    }

    private func saveContact() {
        guard !isGiftMinderManagedContact else {
            showingEditSheet = false
            return
        }
        // Find the contact in the store and update it
        if let index = contactStore.contacts.firstIndex(where: { $0.id == contactId }) {
            contactStore.contacts[index] = editingContact
        }
        showingEditSheet = false
    }

    private func loadContactGifts() {
        guard Auth.auth().currentUser?.uid != nil else { return }
        isLoadingGifts = true

        let db = Firestore.firestore()
        db.collection("contacts")
            .document(contact.id.uuidString)
            .collection("gifts")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                isLoadingGifts = false
                guard let snapshot = snapshot, error == nil else {
                    print("Error loading gifts: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }

                var gifts: [ContactGift] = []
                for doc in snapshot.documents {
                    do {
                        var gift = try doc.data(as: ContactGift.self)
                        gift.id = doc.documentID
                        gifts.append(gift)
                    } catch {
                        print("Error decoding gift: \(error)")
                    }
                }

                DispatchQueue.main.async {
                    self.contactGifts = gifts
                }
            }
    }

    private func startRemoteProfileListenerIfNeeded() {
        guard let uid = giftMinderUid else {
            remoteProfile = nil
            remoteProfileListener?.remove()
            remoteProfileListener = nil
            return
        }

        remoteProfileListener?.remove()
        remoteProfileListener = Firestore.firestore()
            .collection("users")
            .document(uid)
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data() else { return }

                let displayName = ((data["displayName"] as? String)
                    ?? (data["name"] as? String)
                    ?? contactForDisplay.name)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let userId = (data["userId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let bio = ((data["bio"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let interests = (data["interests"] as? [String] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let dobTime = (data["userDOBTime"] as? Double) ?? (data["userDOBTime"] as? NSNumber)?.doubleValue ?? 0
                let anniversaryTime = (data["userAnniversaryTime"] as? Double) ?? (data["userAnniversaryTime"] as? NSNumber)?.doubleValue ?? 0
                let otherDatesRaw = data["userOtherDates"] as? [[String: Any]] ?? []
                let otherDates: [RemoteContactEvent] = otherDatesRaw.compactMap { item in
                    let label = (item["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let time = (item["time"] as? Double) ?? (item["time"] as? NSNumber)?.doubleValue ?? 0
                    guard !label.isEmpty, time > 0 else { return nil }
                    return RemoteContactEvent(label: label, time: time)
                }

                remoteProfile = RemoteContactProfile(
                    displayName: displayName.isEmpty ? contactForDisplay.name : displayName,
                    userId: userId,
                    bio: bio,
                    interests: interests,
                    dobTime: dobTime,
                    anniversaryTime: anniversaryTime,
                    otherDates: otherDates
                )

                guard let index = contactStore.contacts.firstIndex(where: { $0.id == contactId }) else { return }
                var updated = contactStore.contacts[index]
                updated.name = remoteProfile?.displayName ?? updated.name
                updated.notes = remoteProfile?.bio ?? updated.notes
                updated.interests = remoteProfile?.interests ?? updated.interests
                if let remoteProfile, remoteProfile.dobTime > 0 {
                    updated.hasBirthday = true
                    updated.dateOfBirth = Date(timeIntervalSince1970: remoteProfile.dobTime)
                    updated.isBirthYearKnown = false
                } else {
                    updated.hasBirthday = false
                }
                if let remoteProfile, remoteProfile.anniversaryTime > 0 {
                    updated.anniversaryDate = Date(timeIntervalSince1970: remoteProfile.anniversaryTime)
                    updated.isAnniversaryYearKnown = false
                } else {
                    updated.anniversaryDate = nil
                }
                if let remoteProfile {
                    updated.customEvents = remoteProfile.otherDates.map { event in
                        ContactEvent(title: event.label, date: Date(timeIntervalSince1970: event.time), isYearKnown: false)
                    }
                }
                updated.updatedAt = Date()
                contactStore.contacts[index] = updated
            }
    }

    private func markGiftPurchased(_ gift: ContactGift, purchased: Bool) {
        guard canEditWishlist else { return }
        let functions = Functions.functions()
        functions.httpsCallable("markGiftPurchased").call([
            "contactId": contact.id.uuidString,
            "giftId": gift.id,
            "purchased": purchased,
        ]) { result, error in
            if let error = error {
                print("Error marking gift as purchased: \(error.localizedDescription)")
            } else {
                loadContactGifts()
            }
        }
    }

    private func deleteGift(_ gift: ContactGift) {
        guard canEditWishlist else { return }
        let db = Firestore.firestore()
        db.collection("contacts")
            .document(contact.id.uuidString)
            .collection("gifts")
            .document(gift.id)
            .delete { error in
                if let error = error {
                    print("Error deleting gift: \(error.localizedDescription)")
                } else {
                    DispatchQueue.main.async {
                        self.contactGifts.removeAll { $0.id == gift.id }
                    }
                }
            }
    }
}

// Edit Contact Modal
struct EditContactView: View {
    @Binding var contact: Contact
    @Binding var isPresented: Bool
    var startInNotes: Bool = false
    var onSave: () -> Void
    
    @State private var editName: String = ""
    @State private var editRelationship: Relationship = .other
    @State private var editNotes: String = ""
    @State private var editInterests: String = ""
    @State private var editMonth = Calendar.current.component(.month, from: Date())
    @State private var editDay = Calendar.current.component(.day, from: Date())
    @State private var hasBirthday = true
    @State private var annMonth = Calendar.current.component(.month, from: Date())
    @State private var annDay = Calendar.current.component(.day, from: Date())
    @State private var annYear = Calendar.current.component(.year, from: Date())
    @State private var includeAnnYear = false
    @State private var hasAnniversary = false
    @State private var customEventDrafts: [DraftEvent] = []
    @State private var showAddBirthday = false
    @State private var showAddAnniversary = false
    @State private var showAddEvent = false
    @State private var newEventTitle: String = ""
    @State private var newEventMonth = 1
    @State private var newEventDay = 1
    @State private var newEventYear = Calendar.current.component(.year, from: Date())
    @State private var newEventIncludeYear = false
    @FocusState private var isNotesFocused: Bool
    
    private struct DraftEvent: Identifiable {
        let id = UUID()
        var title: String
        var month: Int
        var day: Int
        var year: Int
        var isYearKnown: Bool
    }
    
    private var interestsList: [String] {
        editInterests.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Info")) {
                    TextField("Name", text: $editName)
                    
                    Picker("Relationship", selection: $editRelationship) {
                        ForEach(Relationship.allCases, id: \.self) { rel in
                            Text(rel.rawValue).tag(rel)
                        }
                    }
                }
                
                Section(header: Text("Birthday")) {
                    if hasBirthday {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Birthday")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(monthDayOnly(contact.dateOfBirth))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: { showAddBirthday.toggle() }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.secondary)
                            }
                            Button(action: {
                                hasBirthday = false
                                showAddBirthday = false
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Button(action: {
                            showAddBirthday.toggle()
                            if showAddBirthday { hasBirthday = true }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("Add birthday")
                            }
                        }
                    }

                    if showAddBirthday {
                        HStack {
                            Picker("Month", selection: $editMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(monthName(month)).tag(month)
                                }
                            }
                            Picker("Day", selection: $editDay) {
                                ForEach(1...31, id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                        }
                        
                    }
                }
                
                Section(header: Text("Anniversary")) {
                    if hasAnniversary {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Anniversary")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if let ann = contact.anniversaryDate {
                                    Text(contact.isAnniversaryYearKnown ? fullDate(ann) : monthDayOnly(ann))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button(action: { showAddAnniversary.toggle() }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.secondary)
                            }
                            Button(action: {
                                hasAnniversary = false
                                showAddAnniversary = false
                                includeAnnYear = false
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Button(action: {
                            showAddAnniversary.toggle()
                            if showAddAnniversary { hasAnniversary = true }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("Add anniversary")
                            }
                        }
                    }

                    if showAddAnniversary {
                        HStack {
                            Picker("Month", selection: $annMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(monthName(month)).tag(month)
                                }
                            }
                            Picker("Day", selection: $annDay) {
                                ForEach(1...31, id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                        }
                        
                        Toggle("Include year", isOn: $includeAnnYear)
                        
                        if includeAnnYear {
                            Picker("Year", selection: $annYear) {
                                ForEach((1950...2024).reversed(), id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Custom Events")) {
                    if !customEventDrafts.isEmpty {
                        ForEach(customEventDrafts) { event in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.title).font(.subheadline).fontWeight(.semibold)
                                    Text("\(monthName(for: event.month)) \(event.day)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(action: { removeDraftEvent(event.id) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Button(action: { showAddEvent.toggle() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Add event")
                        }
                    }

                    if showAddEvent {
                        TextField("Event name", text: $newEventTitle)

                        HStack(spacing: 10) {
                            Picker("Month", selection: $newEventMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(monthName(month)).tag(month)
                                }
                            }

                            Picker("Day", selection: $newEventDay) {
                                ForEach(1...31, id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                        }

                        Toggle("Include year", isOn: $newEventIncludeYear)

                        if newEventIncludeYear {
                            Picker("Year", selection: $newEventYear) {
                                ForEach(currentYear...(currentYear + 10), id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                        }

                        Button(action: addDraftEvent) {
                            Text("Add Event")
                                .fontWeight(.semibold)
                        }
                        .disabled(newEventTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                
                Section(header: Text("Interests")) {
                    TextField("Interests (comma-separated)", text: $editInterests)
                    
                    if !interestsList.isEmpty {
                        ForEach(interestsList, id: \.self) { interest in
                            HStack {
                                Text(interest)
                                    .font(.subheadline)
                                Spacer()
                                Button(action: {
                                    editInterests = interestsList.filter { $0 != interest }.joined(separator: ", ")
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $editNotes)
                        .frame(height: 100)
                        .focused($isNotesFocused)
                }
            }
            .navigationTitle("Edit Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                editName = contact.name
                editRelationship = contact.relationship
                editNotes = contact.notes
                editInterests = contact.interests.joined(separator: ", ")
                hasBirthday = contact.hasBirthday
                
                let cal = Calendar.current
                editMonth = cal.component(.month, from: contact.dateOfBirth)
                editDay = cal.component(.day, from: contact.dateOfBirth)
                
                if let ann = contact.anniversaryDate {
                    hasAnniversary = true
                    annMonth = cal.component(.month, from: ann)
                    annDay = cal.component(.day, from: ann)
                    annYear = cal.component(.year, from: ann)
                    includeAnnYear = contact.isAnniversaryYearKnown
                } else {
                    hasAnniversary = false
                }
                
                // Load custom events
                customEventDrafts = contact.customEvents.map { event in
                    let eventCal = Calendar.current
                    return DraftEvent(
                        title: event.title,
                        month: eventCal.component(.month, from: event.date),
                        day: eventCal.component(.day, from: event.date),
                        year: eventCal.component(.year, from: event.date),
                        isYearKnown: event.isYearKnown
                    )
                }

                if startInNotes {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isNotesFocused = true
                    }
                }
            }
        }
    }
    
    private func saveChanges() {
        contact.name = editName
        contact.relationship = editRelationship
        contact.notes = editNotes
        contact.interests = interestsList
        contact.isBirthYearKnown = false
        contact.hasBirthday = hasBirthday
        
        // Update birthday
        let cal = Calendar.current
        if hasBirthday {
            var comps = DateComponents()
            comps.month = editMonth
            comps.day = editDay
            comps.year = cal.component(.year, from: Date())
            if let newDOB = cal.date(from: comps) {
                contact.dateOfBirth = newDOB
            }
        }
        
        // Update anniversary only if the form was opened
        if hasAnniversary {
            var annComps = DateComponents()
            annComps.month = annMonth
            annComps.day = annDay
            annComps.year = includeAnnYear ? annYear : cal.component(.year, from: Date())
            contact.anniversaryDate = cal.date(from: annComps)
            contact.isAnniversaryYearKnown = includeAnnYear
        } else {
            contact.anniversaryDate = nil
        }
        
        // Update custom events
        let customEvents = customEventDrafts.map { draft -> ContactEvent in
            var eventComps = DateComponents()
            eventComps.month = draft.month
            eventComps.day = draft.day
            eventComps.year = draft.isYearKnown ? draft.year : cal.component(.year, from: Date())
            let eventDate = cal.date(from: eventComps) ?? Date()
            return ContactEvent(title: draft.title, date: eventDate, isYearKnown: draft.isYearKnown)
        }
        contact.customEvents = customEvents
        
        onSave()
    }
    
    private func addDraftEvent() {
        guard !newEventTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let draft = DraftEvent(
            title: newEventTitle,
            month: newEventMonth,
            day: newEventDay,
            year: newEventYear,
            isYearKnown: newEventIncludeYear
        )
        customEventDrafts.append(draft)
        
        // Reset form
        newEventTitle = ""
        newEventMonth = 1
        newEventDay = 1
        newEventYear = Calendar.current.component(.year, from: Date())
        newEventIncludeYear = false
        showAddEvent = false
    }
    
    private func removeDraftEvent(_ id: UUID) {
        customEventDrafts.removeAll { $0.id == id }
    }
    
    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        return formatter.monthSymbols[month - 1]
    }
    
    private func monthName(for month: Int) -> String {
        let formatter = DateFormatter()
        return formatter.monthSymbols[month - 1]
    }
    
    private func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func monthDayOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

struct ContactHeaderView: View {
    let contact: Contact

    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.brand.opacity(0.1))
                .frame(width: 120, height: 120)
                .overlay(
                    Text(contact.name.prefix(2).uppercased())
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(Color.brand)
                )

            VStack(spacing: 8) {
                Text(contact.name)
                    .font(.title)
                    .fontWeight(.bold)

                HStack {
                    Image(systemName: contact.relationship.icon)
                        .foregroundColor(Color.brand)
                    Text(contact.relationship.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if !contact.notes.isEmpty {
                    Text(contact.notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(16)
    }
}

struct ContactStatsView: View {
    let contact: Contact

    private var nextBirthdayText: String {
        guard contact.hasBirthday else { return "—" }
        if contact.daysUntilBirthday == 0 {
            return "Today! 🎉"
        } else if contact.daysUntilBirthday == 1 {
            return "Tomorrow"
        } else {
            return "\(contact.daysUntilBirthday) days"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Next Birthday",
                value: nextBirthdayText,
                icon: "birthday.cake",
                color: .orange
            )

            StatCard(
                title: "Interests",
                value: "\(contact.interests.count)",
                icon: "heart",
                color: .pink
            )
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String?
    let color: Color

    init(title: String, value: String, icon: String? = nil, color: Color = .accentColor) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
    }

    var body: some View {
        VStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }

            Text(value)
                .font(.headline)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct EventCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var compact: Bool = false
    var onEdit: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack {
                Image(systemName: icon)
                    .font(compact ? .caption.weight(.semibold) : .title3)
                    .foregroundColor(color)
                    .frame(width: compact ? 20 : 32, height: compact ? 20 : 32)
                    .background(Circle().fill(color.opacity(0.15)))

                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color(UIColor.tertiarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(compact ? .headline.weight(.bold) : .title3.weight(.bold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                
                Text(title)
                    .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(compact ? 10 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 12 : 16)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 12 : 16)
                        .stroke(color.opacity(0.2), lineWidth: 1.5)
                )
        )
        .shadow(color: color.opacity(compact ? 0.05 : 0.1), radius: compact ? 2 : 4, x: 0, y: compact ? 1 : 2)
    }
}

struct ProductCard: View {
    let gift: Gift
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemFill))
                .frame(width: 160, height: 140)
                .overlay(
                    Image(systemName: gift.category.icon)
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.3))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(gift.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(gift.retailer)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack {
                    Text(gift.formattedPrice)
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color.brand)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 160)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct InterestsSection: View {
    let contact: Contact

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Interests")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
            }

            if contact.interests.isEmpty {
                Text("No interests added yet")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ForEach(contact.interests, id: \.self) { interest in
                        HStack {
                            Text(interest.capitalized)
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.brand.opacity(0.1))
                        .foregroundColor(Color.brand)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(16)
    }
}

struct RecommendationsSection: View {
    let recommendations: [Gift]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Shop Recommendations")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
            }

            if recommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "gift")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("No shop recommendations found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(recommendations) { gift in
                            RecommendationCard(gift: gift)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(16)
    }
}

struct RecommendationCard: View {
    let gift: Gift

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if gift.isSponsored {
                HStack {
                    Text("SPONSORED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .cornerRadius(4)
                    Spacer()
                }
            }

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 120)
                .overlay(
                    Image(systemName: gift.category.icon)
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                )

            Text(gift.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)

            Text(gift.formattedPrice)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(Color.brand)

            HStack {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", gift.rating))
                        .font(.caption2)
                }

                Spacer()

                Text(gift.retailer)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 160)
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .gray.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Add Contact View

struct AddContactView: View {
    @EnvironmentObject var contactStore: ContactStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var showAddBirthday = false
    @State private var birthMonth = Calendar.current.component(.month, from: Date())
    @State private var birthDay = Calendar.current.component(.day, from: Date())
    @State private var showAddAnniversary = false
    @State private var anniversaryMonth = Calendar.current.component(.month, from: Date())
    @State private var anniversaryDay = Calendar.current.component(.day, from: Date())
    @State private var anniversaryYear = Calendar.current.component(.year, from: Date())
    @State private var includeAnniversaryYear = false
    @State private var customEventDrafts: [DraftEvent] = []
    @State private var newEventTitle = ""
    @State private var newEventMonth = Calendar.current.component(.month, from: Date())
    @State private var newEventDay = Calendar.current.component(.day, from: Date())
    @State private var newEventYear = Calendar.current.component(.year, from: Date())
    @State private var newEventIncludeYear = false
    @State private var showAddEvent = false
    @State private var selectedRelationship = Relationship.friend
    @State private var interests: [String] = []
    @State private var newInterest = ""
    @State private var notes = ""

    init(prefillBirthday: Date? = nil) {
        if let date = prefillBirthday {
            let calendar = Calendar.current
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            _showAddBirthday = State(initialValue: true)
            _birthMonth = State(initialValue: comps.month ?? calendar.component(.month, from: Date()))
            _birthDay = State(initialValue: comps.day ?? calendar.component(.day, from: Date()))
        }
    }

    private struct DraftEvent: Identifiable {
        let id = UUID()
        var title: String
        var month: Int
        var day: Int
        var year: Int
        var isYearKnown: Bool
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        AppNavigationView {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name)
                    Picker("Relationship", selection: $selectedRelationship) {
                        ForEach(Relationship.allCases, id: \.self) { relationship in
                            HStack {
                                Image(systemName: relationship.icon)
                                Text(relationship.rawValue)
                            }
                            .tag(relationship)
                        }
                    }
                }
                Section("Dates & Events") {
                    Button(action: { showAddBirthday.toggle() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Add birthday")
                        }
                    }

                    if showAddBirthday {
                        HStack(spacing: 10) {
                            Picker("Month", selection: $birthMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(DateFormatter().monthSymbols[month - 1]).tag(month)
                                }
                            }

                            Picker("Day", selection: $birthDay) {
                                ForEach(1...daysInSelectedMonth, id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    Button(action: { showAddAnniversary.toggle() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Add anniversary")
                        }
                    }

                    if showAddAnniversary {
                        HStack(spacing: 10) {
                            Picker("Month", selection: $anniversaryMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(DateFormatter().monthSymbols[month - 1]).tag(month)
                                }
                            }

                            Picker("Day", selection: $anniversaryDay) {
                                ForEach(1...daysInMonth(month: anniversaryMonth, year: anniversaryYear), id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                        }
                        .pickerStyle(MenuPickerStyle())

                        Toggle("Include year", isOn: $includeAnniversaryYear)

                        if includeAnniversaryYear {
                            Picker("Year", selection: $anniversaryYear) {
                                ForEach((currentYear - 120)...currentYear, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }

                    if !customEventDrafts.isEmpty {
                        ForEach(customEventDrafts) { event in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.title).font(.subheadline).fontWeight(.semibold)
                                    Text("\(monthName(for: event.month)) \(event.day)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(action: { removeDraftEvent(event.id) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Button(action: { showAddEvent.toggle() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Add event")
                        }
                    }

                    if showAddEvent {
                        TextField("Event name", text: $newEventTitle)

                        HStack(spacing: 10) {
                            Picker("Month", selection: $newEventMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(DateFormatter().monthSymbols[month - 1]).tag(month)
                                }
                            }

                            Picker("Day", selection: $newEventDay) {
                                ForEach(1...daysInMonth(month: newEventMonth, year: newEventYear), id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                        }
                        .pickerStyle(MenuPickerStyle())

                        Toggle("Include year", isOn: $newEventIncludeYear)

                        if newEventIncludeYear {
                            Picker("Year", selection: $newEventYear) {
                                ForEach(currentYear...(currentYear + 10), id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }

                        Button("Save Event") { saveDraftEvent() }
                    }
                }

                Section("Interests") {
                    HStack {
                        TextField("Add interest...", text: $newInterest)
                            .onSubmit {
                                addInterest()
                            }

                        Button("Add") {
                            addInterest()
                        }
                        .disabled(
                            newInterest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !interests.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(interests, id: \.self) { interest in
                                    HStack(spacing: 4) {
                                        Text(interest.capitalized)
                                            .font(.caption)

                                        Button {
                                            interests.removeAll { $0 == interest }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.brand.opacity(0.1))
                                    .foregroundColor(Color.brand)
                                    .cornerRadius(12)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Additional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveContact()
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func addInterest() {
        let trimmedInterest = newInterest.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !trimmedInterest.isEmpty else { return }
        guard !interests.contains(trimmedInterest) else {
            newInterest = ""
            return
        }

        interests.append(trimmedInterest)
        newInterest = ""
    }

    private func saveContact() {
        let calendar = Calendar.current
        let dob: Date
        let isBirthYearKnown: Bool

        if showAddBirthday {
            let year = calendar.component(.year, from: Date())
            var comps = DateComponents()
            comps.year = year
            comps.month = birthMonth
            comps.day = min(birthDay, daysInSelectedMonth)
            dob = calendar.date(from: comps) ?? Date()
            isBirthYearKnown = false
        } else {
            dob = Date()
            isBirthYearKnown = false
        }

        var anniversaryDate: Date? = nil
        if showAddAnniversary {
            let annYear = includeAnniversaryYear ? anniversaryYear : calendar.component(.year, from: Date())
            var annComps = DateComponents()
            annComps.year = annYear
            annComps.month = anniversaryMonth
            annComps.day = min(anniversaryDay, daysInMonth(month: anniversaryMonth, year: annYear))
            anniversaryDate = calendar.date(from: annComps)
        }

        let customEvents = customEventDrafts.map { draft -> ContactEvent in
            let evYear = draft.isYearKnown ? draft.year : calendar.component(.year, from: Date())
            var evComps = DateComponents()
            evComps.year = evYear
            evComps.month = draft.month
            evComps.day = min(draft.day, daysInMonth(month: draft.month, year: evYear))
            let evDate = calendar.date(from: evComps) ?? Date()
            return ContactEvent(title: draft.title, date: evDate, isYearKnown: draft.isYearKnown)
        }

        let contact = Contact(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            dateOfBirth: dob,
            relationship: selectedRelationship,
            interests: interests,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isBirthYearKnown: isBirthYearKnown,
            anniversaryDate: anniversaryDate,
            isAnniversaryYearKnown: includeAnniversaryYear,
            customEvents: customEvents,
            hasBirthday: showAddBirthday
        )

        contactStore.addContact(contact)
        dismiss()
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }


    private var daysInSelectedMonth: Int {
        daysInMonth(month: birthMonth, year: currentYear)
    }

    private func daysInMonth(month: Int, year: Int) -> Int {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        let date = calendar.date(from: comps) ?? Date()
        return calendar.range(of: .day, in: .month, for: date)?.count ?? 31
    }

    private func monthName(for month: Int) -> String {
        DateFormatter().monthSymbols[max(0, month - 1)]
    }

    private func saveDraftEvent() {
        let trimmed = newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let draft = DraftEvent(
            title: trimmed,
            month: newEventMonth,
            day: min(newEventDay, daysInMonth(month: newEventMonth, year: newEventYear)),
            year: newEventYear,
            isYearKnown: newEventIncludeYear
        )
        customEventDrafts.append(draft)
        newEventTitle = ""
        showAddEvent = false
    }

    private func removeDraftEvent(_ id: UUID) {
        customEventDrafts.removeAll { $0.id == id }
    }
}

// MARK: - Recommendations View

struct RecommendationsView: View {
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var giftService: GiftService
    @State private var selectedContact: Contact? = nil

    var body: some View {
        AppNavigationView {
            VStack {
                if contactStore.contacts.isEmpty {
                    EmptyRecommendationsView()
                } else {
                    ContactSelectorView(
                        contacts: contactStore.contacts,
                        selectedContact: $selectedContact
                    )

                    if let contact = selectedContact {
                        RecommendationsListView(
                            contact: contact,
                            recommendations: giftService.getRecommendations(for: contact)
                        )
                    } else {
                        AllContactsView(contacts: contactStore.contacts)
                    }
                }
            }
            .navigationTitle("Shop")
            .onAppear {
                if selectedContact == nil {
                    selectedContact = contactStore.contacts.first
                }
            }
        }
    }
}

struct EmptyRecommendationsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gift.circle")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            Text("No Shop Suggestions Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add at least one contact with interests to unlock personalized shopping suggestions.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ContactSelectorView: View {
    let contacts: [Contact]
    @Binding var selectedContact: Contact?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button("All") {
                    selectedContact = nil
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    selectedContact == nil ? Color.brand.opacity(0.2) : Color.gray.opacity(0.1)
                )
                .foregroundColor(selectedContact == nil ? Color.brand : .primary)
                .cornerRadius(20)

                ForEach(contacts) { contact in
                    Button(contact.name) {
                        selectedContact = contact
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        selectedContact?.id == contact.id
                            ? Color.brand.opacity(0.2) : Color.gray.opacity(0.1)
                    )
                    .foregroundColor(selectedContact?.id == contact.id ? Color.brand : .primary)
                    .cornerRadius(20)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

struct RecommendationsListView: View {
    let contact: Contact
    let recommendations: [Gift]

    var body: some View {
        List(recommendations) { gift in
            GiftRowView(gift: gift)
        }
        .listStyle(PlainListStyle())
    }
}

struct AllContactsView: View {
    let contacts: [Contact]
    @EnvironmentObject var giftService: GiftService

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(contacts.prefix(3)) { contact in
                    ContactGiftSection(
                        contact: contact,
                        recommendations: Array(
                            giftService.getRecommendations(for: contact).prefix(3))
                    )
                }
            }
            .padding()
        }
    }
}

struct ContactGiftSection: View {
    let contact: Contact
    let recommendations: [Gift]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("For \(contact.name)")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                if contact.hasBirthday && contact.daysUntilBirthday <= 30 {
                    Text("\(contact.daysUntilBirthday) days")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recommendations) { gift in
                        MiniGiftCard(gift: gift)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct MiniGiftCard: View {
    let gift: Gift

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 100, height: 80)
                .overlay(
                    Image(systemName: gift.category.icon)
                        .font(.title2)
                        .foregroundColor(.secondary)
                )

            Text(gift.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 100, alignment: .leading)

            Text(gift.formattedPrice)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(Color.brand)
        }
        .frame(width: 100)
    }
}

struct GiftRowView: View {
    let gift: Gift

    var body: some View {
        HStack(spacing: 12) {
            if let img = gift.imageURL, let url = URL(string: img) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 60, height: 60)
                    case .success(let image):
                        image.resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipped()
                            .cornerRadius(8)
                    case .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay(Image(systemName: gift.category.icon).foregroundColor(.secondary))
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: gift.category.icon)
                            .foregroundColor(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(gift.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    if gift.isSponsored {
                        Text("AD")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .cornerRadius(3)
                    }
                }

                Text(gift.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack {
                    // price pill
                    Text(gift.formattedPrice)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.brand.opacity(0.08)))
                        .foregroundColor(Color.brand)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", gift.rating))
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProductRowView: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            if let url = URL(string: product.image) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 60, height: 60)
                    case .success(let image):
                        image.resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipped()
                            .cornerRadius(8)
                    case .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay(Image(systemName: "photo"))
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "photo"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(product.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text(product.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack {
                    Text(String(format: "$%.2f", product.price))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.brand.opacity(0.08)))
                        .foregroundColor(Color.brand)

                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProductDetailView: View {
    let product: Product
    let recipientName: String
    let preferredStore: String?
    @Environment(\.openURL) private var openURL
    @State private var showOpenStoreFailedAlert = false

    private var sanitizedQuery: String {
        product.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var commonReferralItems: [URLQueryItem] {
        [
            URLQueryItem(name: "utm_source", value: "giftminder"),
            URLQueryItem(name: "utm_medium", value: "app"),
            URLQueryItem(name: "utm_campaign", value: "shop_redirect"),
            URLQueryItem(name: "ref", value: "giftminder_app")
        ]
    }

    private func makeURL(base: String, searchParamName: String, query: String, extraItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: searchParamName, value: query))
        items.append(contentsOf: commonReferralItems)
        items.append(contentsOf: extraItems)
        components.queryItems = items
        return components.url
    }

    private var destinationURL: URL? {
        let query = sanitizedQuery.isEmpty ? "gift" : sanitizedQuery
        guard let preferredStore,
              !preferredStore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return makeURL(base: "https://www.google.com/search", searchParamName: "q", query: query, extraItems: [
                URLQueryItem(name: "tbm", value: "shop")
            ])
        }

        switch preferredStore.lowercased() {
        case "amazon":
            return makeURL(base: "https://www.amazon.com/s", searchParamName: "k", query: query, extraItems: [
                URLQueryItem(name: "tag", value: "giftminderapp-20")
            ])
        case "target":
            return makeURL(base: "https://www.target.com/s", searchParamName: "searchTerm", query: query, extraItems: [
                URLQueryItem(name: "afid", value: "giftminder_app")
            ])
        case "best buy":
            return makeURL(base: "https://www.bestbuy.com/site/searchpage.jsp", searchParamName: "st", query: query)
        case "etsy":
            return makeURL(base: "https://www.etsy.com/search", searchParamName: "q", query: query)
        case "nike":
            return makeURL(base: "https://www.nike.com/w", searchParamName: "q", query: query)
        case "adidas":
            return makeURL(base: "https://www.adidas.com/us/search", searchParamName: "q", query: query)
        case "apple":
            return makeURL(base: "https://www.apple.com/us/search", searchParamName: "q", query: query, extraItems: [
                URLQueryItem(name: "src", value: "globalnav")
            ])
        default:
            return makeURL(base: "https://www.google.com/search", searchParamName: "q", query: "\(query) \(preferredStore)")
        }
    }

    private var destinationLabel: String {
        if let preferredStore,
           !preferredStore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Open at \(preferredStore)"
        }
        return "Compare Deals"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let url = URL(string: product.image) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 240)
                        case .success(let image):
                            image.resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 240)
                                .clipped()
                                .cornerRadius(12)
                        case .failure:
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 240)
                                .overlay(Image(systemName: "photo"))
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(product.title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(String(format: "$%.2f", product.price))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Color.brand)

                    Text(product.description)
                        .foregroundColor(.secondary)
                        .font(.body)

                    HStack(spacing: 8) {
                        Label("Shopping for \(recipientName)", systemImage: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.brand.opacity(0.1)))
                            .foregroundColor(Color.brand)

                        if let preferredStore,
                           !preferredStore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label(preferredStore, systemImage: "bag")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color(UIColor.tertiarySystemBackground)))
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("GiftMinder shows product details and sends you to the retailer to complete checkout.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Some outbound links may include referral or campaign parameters.")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Button(action: {
                            guard let url = destinationURL else {
                                showOpenStoreFailedAlert = true
                                return
                            }
                            openURL(url)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.square.fill")
                                Text(destinationLabel)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.brand))
                            .foregroundColor(.white)
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn’t open store", isPresented: $showOpenStoreFailedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please try again in a moment.")
        }
    }
}

struct GiftDetailView: View {
    let gift: Gift
    var recipientName: String = "Me"
    var preferredStore: String? = nil
    @Environment(\.openURL) private var openURL
    @State private var showOpenStoreFailedAlert = false

    private var effectiveStore: String {
        let first = preferredStore?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !first.isEmpty { return first }
        return gift.retailer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sanitizedQuery: String {
        gift.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var commonReferralItems: [URLQueryItem] {
        [
            URLQueryItem(name: "utm_source", value: "giftminder"),
            URLQueryItem(name: "utm_medium", value: "app"),
            URLQueryItem(name: "utm_campaign", value: "shop_redirect"),
            URLQueryItem(name: "ref", value: "giftminder_app")
        ]
    }

    private func makeURL(base: String, searchParamName: String, query: String, extraItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: searchParamName, value: query))
        items.append(contentsOf: commonReferralItems)
        items.append(contentsOf: extraItems)
        components.queryItems = items
        return components.url
    }

    private var destinationURL: URL? {
        let query = sanitizedQuery.isEmpty ? "gift" : sanitizedQuery
        guard !effectiveStore.isEmpty else {
            return makeURL(base: "https://www.google.com/search", searchParamName: "q", query: query, extraItems: [
                URLQueryItem(name: "tbm", value: "shop")
            ])
        }

        switch effectiveStore.lowercased() {
        case "amazon":
            return makeURL(base: "https://www.amazon.com/s", searchParamName: "k", query: query, extraItems: [
                URLQueryItem(name: "tag", value: "giftminderapp-20")
            ])
        case "target":
            return makeURL(base: "https://www.target.com/s", searchParamName: "searchTerm", query: query, extraItems: [
                URLQueryItem(name: "afid", value: "giftminder_app")
            ])
        case "best buy":
            return makeURL(base: "https://www.bestbuy.com/site/searchpage.jsp", searchParamName: "st", query: query)
        case "etsy":
            return makeURL(base: "https://www.etsy.com/search", searchParamName: "q", query: query)
        case "nike":
            return makeURL(base: "https://www.nike.com/w", searchParamName: "q", query: query)
        case "adidas":
            return makeURL(base: "https://www.adidas.com/us/search", searchParamName: "q", query: query)
        case "apple":
            return makeURL(base: "https://www.apple.com/us/search", searchParamName: "q", query: query, extraItems: [
                URLQueryItem(name: "src", value: "globalnav")
            ])
        default:
            return makeURL(base: "https://www.google.com/search", searchParamName: "q", query: "\(query) \(effectiveStore)")
        }
    }

    private var destinationLabel: String {
        effectiveStore.isEmpty ? "Compare Deals" : "Open at \(effectiveStore)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let s = gift.imageURL, let url = URL(string: s) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 240)
                        case .success(let image):
                            image.resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 240)
                                .clipped()
                                .cornerRadius(12)
                        case .failure:
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 240)
                                .overlay(Image(systemName: "photo"))
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(gift.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(gift.formattedPrice)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)

                    Text(gift.description)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Label("Shopping for \(recipientName)", systemImage: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.brand.opacity(0.1)))
                            .foregroundColor(Color.brand)

                        if !effectiveStore.isEmpty {
                            Label(effectiveStore, systemImage: "bag")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color(UIColor.tertiarySystemBackground)))
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("GiftMinder shows product details and sends you to the retailer to complete checkout.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Some outbound links may include referral or campaign parameters.")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Button(action: {
                            guard let url = destinationURL else {
                                showOpenStoreFailedAlert = true
                                return
                            }
                            openURL(url)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.square.fill")
                                Text(destinationLabel)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.brand))
                            .foregroundColor(.white)
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn’t open store", isPresented: $showOpenStoreFailedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please try again in a moment.")
        }
    }
}

struct ProductsFilterView: View {
    @Binding var isPresented: Bool
    let categories: [String]
    @Binding var selectedCategory: String?
    @Binding var showStores: Bool
    @Binding var showLocal: Bool

    var body: some View {
        AppNavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(categories, id: \.self) { cat in
                        Button(action: {
                            if cat == "Stores" {
                                // open stores
                                selectedCategory = nil
                                showStores = true
                                isPresented = false
                            } else if cat == "Support Local Shops" {
                                selectedCategory = nil
                                showLocal = true
                                isPresented = false
                            } else if cat == "All" {
                                selectedCategory = nil
                                isPresented = false
                            } else {
                                selectedCategory = cat
                                isPresented = false
                            }
                        }) {
                            HStack {
                                Text(cat)
                                    .fontWeight(.semibold)
                                    .foregroundColor(selectedCategory == cat ? .white : .primary)
                                Spacer()
                                if selectedCategory == cat {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(12)
                            .background(selectedCategory == cat ? Color.brand : Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Filter")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Search View

struct SearchView: View {
    var embedded: Bool = false
    var onResultCountChanged: ((Int) -> Void)? = nil
    @EnvironmentObject var contactStore: ContactStore
    @State private var searchText = ""
    @State private var users: [DiscoverableUser] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasMoreUsers = false
    @State private var errorMessage: String?
    @State private var addedUserSourceIds: Set<String> = []
    @State private var pendingUserSourceIds: Set<String> = []
    @State private var lastUserDocument: DocumentSnapshot?
    @State private var searchDebounceWorkItem: DispatchWorkItem?
    @State private var activeSearchQuery = ""

    private let db = Firestore.firestore()
    private let pageSize = 40

    private struct DiscoverableUser: Identifiable {
        let uid: String
        let userId: String
        let displayName: String
        let photoURL: String?
        let bio: String?

        var id: String { uid }
    }

    var body: some View {
        Group {
            if embedded {
                discoverContent
            } else {
                AppNavigationView {
                    discoverContent
                }
            }
        }
    }

    private var discoverContent: some View {
            ZStack {
                if !embedded {
                    AppBackground()
                }

                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color.brand.opacity(0.8))

                        TextField("Search users by name or @username", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if !searchText.isEmpty {
                            Button(action: {
                                searchDebounceWorkItem?.cancel()
                                searchText = ""
                                users = []
                                hasMoreUsers = false
                                lastUserDocument = nil
                                activeSearchQuery = ""
                                errorMessage = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.brand.opacity(0.14), lineWidth: 1)
                    )
                    .padding(.horizontal)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    if isLoading {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Searching users...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 40)
                    } else if users.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 56))
                                .foregroundColor(.secondary)

                            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Find GiftMinder Users" : "No Users Found")
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Search by name or username to find registered accounts." : "Try a different name or username.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(users) { user in
                                userRow(user)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                            }

                            if hasMoreUsers {
                                HStack {
                                    Spacer()
                                    Button(action: loadMoreUsers) {
                                        if isLoadingMore {
                                            ProgressView()
                                        } else {
                                            Text("Load More")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(Color.brand)
                                        }
                                    }
                                    .disabled(isLoadingMore)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(PlainListStyle())
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .onAppear {
                refreshAddedUserIds()
                reportResultCount()
            }
            .onChange(of: searchText) { newValue in
                scheduleSearch(query: newValue)
            }
            .onChange(of: users.count) { _ in
                reportResultCount()
            }
        }


    private func reportResultCount() {
        onResultCountChanged?(users.count)
    }
    private func userRow(_ user: DiscoverableUser) -> some View {
        HStack(spacing: 12) {
            userAvatar(user)

            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text("@\(user.userId)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: { addUserAsContact(user) }) {
                Text(buttonTitle(for: user))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(buttonBackground(for: user))
                    .foregroundColor(buttonForeground(for: user))
                    .clipShape(Capsule())
            }
            .disabled(isAdded(user) || pendingUserSourceIds.contains(sourceIdentifier(for: user.uid)))
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.brand.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func userAvatar(_ user: DiscoverableUser) -> some View {
        Group {
            if let raw = user.photoURL, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsAvatar(user.displayName)
                    }
                }
            } else {
                initialsAvatar(user.displayName)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
    }

    private func initialsAvatar(_ name: String) -> some View {
        ZStack {
            Circle().fill(Color.brand.opacity(0.16))
            Text(initials(for: name))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(Color.brand)
        }
    }

    private func buttonTitle(for user: DiscoverableUser) -> String {
        let sourceId = sourceIdentifier(for: user.uid)
        if pendingUserSourceIds.contains(sourceId) {
            return "Adding..."
        }
        return isAdded(user) ? "Added" : "Add"
    }

    private func buttonBackground(for user: DiscoverableUser) -> Color {
        if isAdded(user) {
            return Color.brand.opacity(0.12)
        }
        return Color.brand
    }

    private func buttonForeground(for user: DiscoverableUser) -> Color {
        if isAdded(user) {
            return Color.brand
        }
        return .white
    }

    private func isAdded(_ user: DiscoverableUser) -> Bool {
        addedUserSourceIds.contains(sourceIdentifier(for: user.uid))
    }

    private func sourceIdentifier(for uid: String) -> String {
        "firebase:\(uid)"
    }

    private func scheduleSearch(query: String) {
        searchDebounceWorkItem?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            activeSearchQuery = ""
            users = []
            hasMoreUsers = false
            lastUserDocument = nil
            errorMessage = nil
            isLoading = false
            isLoadingMore = false
            return
        }

        let workItem = DispatchWorkItem {
            startSearch(query: trimmed)
        }
        searchDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func startSearch(query: String) {
        activeSearchQuery = query.lowercased()
        users = []
        hasMoreUsers = true
        lastUserDocument = nil
        errorMessage = nil
        fetchUsersPage(reset: true)
    }

    private func loadMoreUsers() {
        fetchUsersPage(reset: false)
    }

    private func fetchUsersPage(reset: Bool) {
        errorMessage = nil
        guard !activeSearchQuery.isEmpty else {
            return
        }
        guard !isLoading && !isLoadingMore else { return }
        if !reset && !hasMoreUsers { return }

        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }

        let normalized = activeSearchQuery

        var query: Query = db.collection("users")
            .order(by: "userId")
            .limit(to: pageSize)

        if let lastUserDocument {
            query = query.start(afterDocument: lastUserDocument)
        }

        query
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    isLoadingMore = false

                    guard normalized == activeSearchQuery else { return }

                    if let error = error {
                        errorMessage = error.localizedDescription
                        if reset {
                            users = []
                        }
                        return
                    }

                    let currentUid = Auth.auth().currentUser?.uid
                    let docs = snapshot?.documents ?? []
                    lastUserDocument = docs.last
                    hasMoreUsers = docs.count == pageSize

                    let mapped: [DiscoverableUser] = docs.compactMap { doc in
                        let data = doc.data()
                        let uid = (data["uid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                            ? (data["uid"] as? String ?? doc.documentID)
                            : doc.documentID
                        if uid == currentUid {
                            return nil
                        }

                        let userId = (data["userId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let displayName = ((data["displayName"] as? String)
                            ?? (data["name"] as? String)
                            ?? (data["fullName"] as? String)
                            ?? userId)
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        guard !userId.isEmpty || !displayName.isEmpty else { return nil }

                        let nameToSearch = displayName.lowercased()
                        let idToSearch = userId.lowercased()
                        guard nameToSearch.contains(normalized) || idToSearch.contains(normalized) else {
                            return nil
                        }

                        return DiscoverableUser(
                            uid: uid,
                            userId: userId.isEmpty ? uid : userId,
                            displayName: displayName.isEmpty ? userId : displayName,
                            photoURL: ((data["profileImageURL"] as? String)
                                ?? (data["photoURL"] as? String)
                                ?? (data["avatarURL"] as? String)),
                            bio: data["bio"] as? String
                        )
                    }

                    var mergedById: [String: DiscoverableUser] = Dictionary(uniqueKeysWithValues: users.map { ($0.uid, $0) })
                    for user in mapped {
                        mergedById[user.uid] = user
                    }

                    users = mergedById.values.sorted { lhs, rhs in
                        let lhsStarts = lhs.userId.lowercased().hasPrefix(normalized) || lhs.displayName.lowercased().hasPrefix(normalized)
                        let rhsStarts = rhs.userId.lowercased().hasPrefix(normalized) || rhs.displayName.lowercased().hasPrefix(normalized)
                        if lhsStarts != rhsStarts { return lhsStarts }
                        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                    }
                }
            }
    }

    private func addUserAsContact(_ user: DiscoverableUser) {
        let sourceId = sourceIdentifier(for: user.uid)
        guard !addedUserSourceIds.contains(sourceId) else { return }
        pendingUserSourceIds.insert(sourceId)

        let addContactWithData: (Data?) -> Void = { imageData in
            DispatchQueue.main.async {
                var newContact = Contact(
                    name: user.displayName,
                    dateOfBirth: Date(),
                    relationship: .friend,
                    interests: [],
                    notes: "@\(user.userId)",
                    isBirthYearKnown: false,
                    anniversaryDate: nil,
                    isAnniversaryYearKnown: false,
                    customEvents: [],
                    hasBirthday: false,
                    sourceIdentifier: sourceId
                )
                newContact.photoData = imageData
                contactStore.addContact(newContact)
                addedUserSourceIds.insert(sourceId)
                pendingUserSourceIds.remove(sourceId)
            }
        }

        if let raw = user.photoURL, let url = URL(string: raw) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                addContactWithData(data)
            }.resume()
        } else {
            addContactWithData(nil)
        }
    }

    private func refreshAddedUserIds() {
        let ids = contactStore.contacts
            .compactMap { $0.sourceIdentifier }
            .filter { $0.hasPrefix("firebase:") }
        addedUserSourceIds = Set(ids)
    }

    private func initials(for name: String) -> String {
        let pieces = name.split(separator: " ")
        let first = pieces.first.map { String($0.prefix(1)) } ?? ""
        let second = pieces.count > 1 ? String(pieces[1].prefix(1)) : ""
        let result = (first + second).uppercased()
        return result.isEmpty ? "U" : result
    }
}

// Store picker with search and popular brands
struct StorePickerSheetView: View {
    @Binding var selectedStore: String?
    let storeNames: [String]
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var popularStores: [String] {
        Array(storeNames.prefix(6))
    }

    private var filteredStores: [String] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storeNames
        }
        return storeNames.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        AppNavigationView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search stores...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !popularStores.isEmpty {
                            Text("Popular Stores")
                                .font(.headline)
                                .padding(.horizontal)

                            WrapHStack(items: popularStores) { store in
                                Button(action: { selectStore(store) }) {
                                    Text(store)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal)
                        }

                        Text("All Stores")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 10) {
                            ForEach(filteredStores, id: \.self) { store in
                                Button(action: { selectStore(store) }) {
                                    HStack {
                                        Text(store)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        if selectedStore == store {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(Color.brand)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Stores")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func selectStore(_ store: String) {
        selectedStore = store
        dismiss()
    }
}

struct LocalBusiness: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let address: String
    let phone: String
    let coordinate: CLLocationCoordinate2D
    let tags: String
}

final class LocalBusinessLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        )
    }
}

// Local Shops view with map + business details
struct LocalBusinessSheetView: View {
    @StateObject private var locationManager = LocalBusinessLocationManager()
    @Environment(\.dismiss) private var dismiss

    private let businesses: [LocalBusiness] = [
        LocalBusiness(name: "Cedar & Pine Gifts", category: "Handmade", address: "123 Market St", phone: "(555) 013-2456", coordinate: CLLocationCoordinate2D(latitude: 37.7766, longitude: -122.4172), tags: "Candles • Art"),
        LocalBusiness(name: "Neighborhood Books", category: "Books", address: "456 Mission St", phone: "(555) 019-8891", coordinate: CLLocationCoordinate2D(latitude: 37.7722, longitude: -122.4235), tags: "Books • Stationery"),
        LocalBusiness(name: "Oak & Thread", category: "Apparel", address: "88 Valencia St", phone: "(555) 010-7788", coordinate: CLLocationCoordinate2D(latitude: 37.7703, longitude: -122.4211), tags: "Clothing • Accessories")
    ]

    var body: some View {
        AppNavigationView {
            VStack(spacing: 16) {
                Map(coordinateRegion: $locationManager.region, showsUserLocation: true, annotationItems: businesses) { biz in
                    MapAnnotation(coordinate: biz.coordinate) {
                        VStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color.brand)
                            Text(biz.name)
                                .font(.caption2)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .frame(height: 220)
                .cornerRadius(14)
                .padding(.horizontal)

                if locationManager.authorizationStatus == .notDetermined || locationManager.authorizationStatus == .denied {
                    Button(action: { locationManager.requestAccess() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "location.fill")
                            Text("Enable Location")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.brandGradient))
                        .foregroundColor(.white)
                    }
                }

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(businesses) { biz in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(biz.name)
                                            .font(.headline)
                                        Text(biz.category)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Link(destination: URL(string: "https://maps.apple.com/?q=\(biz.name.replacingOccurrences(of: " ", with: "+"))")!) {
                                        Text("Open in Maps")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(Color.brand)
                                }

                                Text(biz.tags)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 12) {
                                    Label(biz.address, systemImage: "mappin.and.ellipse")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Label(biz.phone, systemImage: "phone")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Local Shops")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// Category picker removed — categories are available inline under the search bar.

// MARK: - Profile View

struct ProfileView: View {
    @EnvironmentObject var contactStore: ContactStore
    @EnvironmentObject var giftService: GiftService
    @StateObject private var eventsService = EventsNetworkService.shared

    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userId") private var userId: String = ""
    @AppStorage("lastSyncedAuthUid") private var lastSyncedAuthUid: String = ""
    @AppStorage("userBio") private var userBio: String = ""
    @AppStorage("userInterests") private var userInterestsRaw: String = ""
    @AppStorage("userSubtitle") private var userSubtitle: String = "Gift Seeker • Curator"
    @AppStorage("profileFontStyle") private var profileFontStyleRaw: String = "default"
    @AppStorage("profileAnimationsEnabled") private var profileAnimationsEnabled: Bool = false

    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
    @State private var profileUIImage: UIImage?
    @State private var showingBannerImagePicker = false
    @State private var bannerInputImage: UIImage?
    @State private var bannerUIImage: UIImage?
    @State private var profileBannerMode: String = "gradient" // "gradient" or "image" or "none"
    @State private var profileBannerGradientIndex: Int = 0
    @State private var newInterest: String = ""
    @State private var showingInterestEditor: Bool = false
    @State private var editInterestsBuffer: [String] = []
    @State private var showingBannerOptions = false
    @State private var showingEditProfile = false
    @State private var showingEditDates = false
    @State private var showingEditName = false
    @State private var editSubtitle: String = ""
    @State private var editBio: String = ""
    @State private var editInterestsRaw: String = ""
    @State private var editProfileFontStyleRaw: String = "default"
    @State private var editProfileAnimationsEnabled: Bool = false
    @State private var editName: String = ""
    @State private var editUserId: String = ""
    @State private var showingGradientPicker = false
    @State private var userIdAvailability: UserIdAvailability = .idle
    @State private var identityErrorMessage: String?
    @State private var isSavingIdentity = false
    @State private var showIdentitySavedToast = false
    @State private var moderationAlertMessage: String?
    @State private var showCreateEventSheet = false
    @State private var selectedEvent: NetworkEvent?
    @State private var showEventDetailPage = false
    @State private var profileRealtimeListener: ListenerRegistration?
    @State private var profileAvatarPulse = false
    @AppStorage("userDOBTime") private var userDOBTime: Double = 0
    @AppStorage("userAnniversaryTime") private var userAnniversaryTime: Double = 0
    @AppStorage("userOtherDates") private var userOtherDatesRaw: String = "[]"

    struct OtherDate: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var label: String
        var time: TimeInterval
    }

    private enum UserIdAvailability {
        case idle
        case checking
        case available
        case taken
        case invalid
    }

    private var userDOB: Date? { userDOBTime > 0 ? Date(timeIntervalSince1970: userDOBTime) : nil }
    private var userAnniversary: Date? { userAnniversaryTime > 0 ? Date(timeIntervalSince1970: userAnniversaryTime) : nil }
    private func loadOtherDates() -> [OtherDate] {
        guard let data = userOtherDatesRaw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([OtherDate].self, from: data)) ?? []
    }
    private func saveOtherDates(_ arr: [OtherDate]) {
        if let d = try? JSONEncoder().encode(arr), let s = String(data: d, encoding: .utf8) {
            userOtherDatesRaw = s
        }
    }

    // editing states for dates
    @State private var editHasDOB: Bool = false
    @State private var editHasAnniversary: Bool = false
    @State private var editDOB: Date = Date()
    @State private var editAnniversary: Date = Date()
    @State private var editOtherDates: [OtherDate] = []
    @State private var newOtherLabel: String = ""
    @State private var newOtherDate: Date = Date()
    @State private var showDeleteBirthdayConfirmation: Bool = false
    @State private var showDeleteAnniversaryConfirmation: Bool = false
    @State private var pendingDeleteOtherDateId: UUID?

    private var interests: [String] {
        userInterestsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var resolvedUserId: String {
        let stored = normalizeUserId(userId)
        if !stored.isEmpty { return stored }
        if let uid = Auth.auth().currentUser?.uid {
            let alphanumeric = uid.lowercased().filter { $0.isLetter || $0.isNumber }
            if !alphanumeric.isEmpty {
                return "user_\(String(alphanumeric.prefix(14)))"
            }
        }
        return "me"
    }

    private var profileFontDesign: Font.Design {
        switch profileFontStyleRaw {
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
    
    private var avatarSize: CGFloat { 96 }
    private var bannerHeight: CGFloat { 140 }
    
    // Compute event stats for the user profile
    private var userEventStats: [EventStat] {
        var stats: [EventStat] = []
        let calendar = Calendar.current
        let now = Date()
        
        // Birthday
        if let dob = userDOB {
            var next = calendar.date(byAdding: .year, value: calendar.component(.year, from: now) - calendar.component(.year, from: dob), to: dob) ?? dob
            if next < now {
                next = calendar.date(byAdding: .year, value: 1, to: next) ?? next
            }
            let days = calendar.dateComponents([.day], from: now, to: next).day ?? 0
            stats.append(EventStat(
                title: "Birthday",
                value: days == 0 ? "Today!" : "in \(days) day\(days == 1 ? "" : "s")",
                icon: "birthday.cake.fill",
                color: Color.orange
            ))
        }
        
        // Anniversary
        if let ann = userAnniversary {
            let annThisYear = calendar.date(bySetting: .year, value: calendar.component(.year, from: now), of: ann) ?? ann
            var next = annThisYear
            if next < now {
                next = calendar.date(byAdding: .year, value: 1, to: next) ?? next
            }
            let days = calendar.dateComponents([.day], from: now, to: next).day ?? 0
            stats.append(EventStat(
                title: "Anniversary",
                value: days == 0 ? "Today!" : "in \(days) day\(days == 1 ? "" : "s")",
                icon: "heart.circle.fill",
                color: Color.pink
            ))
        }

        for od in loadOtherDates() {
            let eventDate = Date(timeIntervalSince1970: od.time)
            let eventThisYear = calendar.date(bySetting: .year, value: calendar.component(.year, from: now), of: eventDate) ?? eventDate
            var next = eventThisYear
            if next < now {
                next = calendar.date(byAdding: .year, value: 1, to: next) ?? next
            }
            let days = calendar.dateComponents([.day], from: now, to: next).day ?? 0
            stats.append(EventStat(
                title: od.label,
                value: days == 0 ? "Today!" : "in \(days) day\(days == 1 ? "" : "s")",
                icon: "calendar",
                color: Color.blue
            ))
        }
        
        return stats
    }

    private var hostedUpcomingEvents: [NetworkEvent] {
        let visibleWindowStart = Date().addingTimeInterval(-86_400)
        return eventsService.events
            .filter {
                guard $0.startAt >= visibleWindowStart else { return false }
                if eventsService.isOrganizer($0) {
                    return true
                }
                let uid = Auth.auth().currentUser?.uid ?? ""
                if !uid.isEmpty && $0.attendingUserIds.contains(uid) {
                    return true
                }

                guard eventsService.isInvited($0) else { return false }
                let status = eventsService.inviteStatus(for: $0)
                return status == .accepted || status == .maybe
            }
            .sorted { $0.startAt < $1.startAt }
    }
    
    private var userRecommendations: [Gift] {
        giftService.availableGifts.filter { gift in
            interests.contains(where: { interest in
                gift.interests.contains(where: { $0.caseInsensitiveCompare(interest) == .orderedSame })
            })
        }
    }

    var body: some View {
        AppNavigationView {
            ZStack(alignment: .top) {
                AppBackground()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        profileHeaderSection
                        
                        VStack(spacing: 16) {
                            bioSection
                            upcomingEventsSection
                            interestsSection
                            hostedEventsSection
                            giftIdeasSection
                            Spacer(minLength: 40)
                        }
                        .padding(.top, 8)
                    }
                }

                if showIdentitySavedToast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Profile updated")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.brand.opacity(0.18), lineWidth: 1)
                    )
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

            }
            .fontDesign(profileFontDesign)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $inputImage)
                    .onDisappear {
                        if inputImage != nil {
                            loadImage()
                        }
                    }
            }
            .sheet(isPresented: $showingBannerImagePicker) {
                ImagePicker(image: $bannerInputImage)
                    .onDisappear(perform: loadBannerImage)
            }
            .sheet(isPresented: $showingGradientPicker) {
                gradientPickerSheet
            }
            .sheet(isPresented: $showingEditProfile) {
                editProfileSheet
            }
            .sheet(isPresented: $showingEditDates) {
                editDatesSheet
            }
            .sheet(isPresented: $showingEditName) {
                editNameSheet
            }
            .sheet(isPresented: $showCreateEventSheet) {
                CreateEventSheetView { eventId in
                    openCreatedEvent(eventId: eventId)
                }
            }
            .background(
                NavigationLink(
                    destination: Group {
                        if let selectedEvent {
                            EventDetailSheetView(event: selectedEvent)
                        }
                    },
                    isActive: $showEventDetailPage,
                    label: { EmptyView() }
                )
                .hidden()
            )
            .onChange(of: selectedEvent?.id) { id in
                if id != nil {
                    showEventDetailPage = true
                }
            }
            .onChange(of: showEventDetailPage) { isShowing in
                if !isShowing {
                    selectedEvent = nil
                }
            }
            .onAppear(perform: loadBannerPreferences)
            .onAppear(perform: loadBannerSavedImage)
            .onAppear(perform: loadSavedImage)
            .onAppear(perform: restoreProfilePresentationFromScopedCache)
            .onChange(of: inputImage) { _ in
                if inputImage != nil {
                    loadImage()
                }
            }
            .onAppear(perform: syncIdentityFromBackendIfNeeded)
            .onAppear { eventsService.loadEvents() }
            .onAppear(perform: startRealtimeProfileListener)
            .onAppear { profileAvatarPulse = false }
            .onChange(of: lastSyncedAuthUid) { _ in
                restoreProfilePresentationFromScopedCache()
                loadBannerPreferences()
                loadBannerSavedImage()
                loadSavedImage()
            }
            .alert("Profile update blocked", isPresented: Binding(
                get: { moderationAlertMessage != nil },
                set: { newValue in if !newValue { moderationAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(moderationAlertMessage ?? "")
            }
            .onDisappear {
                profileRealtimeListener?.remove()
                profileRealtimeListener = nil
            }
        }
    }

    private func openCreatedEvent(eventId: String) {
        if let matching = eventsService.events.first(where: { $0.id == eventId }) {
            selectedEvent = matching
            return
        }

        eventsService.refreshEvents()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let matching = eventsService.events.first(where: { $0.id == eventId }) {
                selectedEvent = matching
            }
        }
    }
    
    private var profileHeaderSection: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Banner
                Group {
                    if profileBannerMode == "image", let bi = bannerUIImage {
                        Image(uiImage: bi)
                            .resizable()
                            .scaledToFill()
                            .frame(height: bannerHeight)
                            .clipped()
                    } else if profileBannerMode == "gradient" {
                        let presets: [[Color]] = [
                            [Color(red:0.11,green:0.44,blue:0.98), Color.brandEnd],
                            [Color(red:0.0,green:0.6,blue:0.4), Color.green],
                            [Color.orange, Color.pink],
                            [Color.gray, Color.black]
                        ]
                        let g = presets[min(profileBannerGradientIndex, presets.count - 1)]
                        LinearGradient(colors: g, startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(height: bannerHeight)
                    } else {
                        LinearGradient(
                            colors: [Color.brandStart, Color.brandEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: bannerHeight)
                    }
                }
                .ignoresSafeArea(edges: .top)
                
                // Banner options button
                Button(action: { showingBannerOptions = true }) {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }
                .padding(.leading, 16)
               .padding(.top, 8)
                .confirmationDialog("Banner", isPresented: $showingBannerOptions, titleVisibility: .visible) {
                    Button("Choose Photo") { showingBannerImagePicker = true }
                    Button("Choose Gradient") { showingGradientPicker = true }
                    Button("Remove Background", role: .destructive) { 
                        profileBannerMode = "none"
                        saveBannerPreferences()
                        bannerUIImage = nil
                        UserDefaults.standard.removeObject(forKey: currentProfileBannerImageKey())
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            
            VStack(spacing: 12) {
                // Avatar
                Button(action: { showingImagePicker = true }) {
                    Group {
                        if let img = profileUIImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ZStack {
                                Circle().fill(Color.brand)
                                Image(systemName: "person.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 4))
                    .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 4)
                    .scaleEffect(1.0)
                }
                .offset(y: -avatarSize * 0.4)
                
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text(userName.isEmpty ? "Me" : userName)
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Button(action: {
                            startIdentityEditing()
                            showingEditName = true
                        }) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundColor(Color.brand)
                        }
                    }
                    
                    Text("@\(resolvedUserId)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if !userSubtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(userSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 22)
                    }
                }
                .offset(y: -avatarSize * 0.3)
            }
            .padding(.horizontal)
        }
    }

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Bio", systemImage: "text.quote")
                    .font(.headline)
                Spacer()
                Button(action: {
                    editName = userName
                    editSubtitle = userSubtitle
                    editBio = userBio
                    editInterestsRaw = userInterestsRaw
                    editProfileFontStyleRaw = profileFontStyleRaw
                    editProfileAnimationsEnabled = profileAnimationsEnabled
                    editHasDOB = userDOB != nil
                    editHasAnniversary = userAnniversary != nil
                    editDOB = userDOB ?? Date()
                    editAnniversary = userAnniversary ?? Date()
                    editOtherDates = loadOtherDates()
                    showingEditProfile = true
                }) {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(Color.brand)
                }
            }
            .padding(.horizontal)

            if userBio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Add a bio so others understand your style, preferences, and what to shop for.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                Text(userBio)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineSpacing(2)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
        .padding(.horizontal)
    }
    
    private var upcomingEventsSection: some View {
        let stats = userEventStats

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Info", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Button(action: { openDatesEditor() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color.brand)
                }
            }
            .padding(.horizontal)

            if stats.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    VStack(spacing: 4) {
                        Text("No upcoming events")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Text("Add your birthday, anniversary, or custom events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button(action: { openDatesEditor() }) {
                        Text("Add Events")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.brand))
                    }
               }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
            } else {
                let columns = max(1, min(3, stats.count))
                let grid = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columns)

                LazyVGrid(columns: grid, alignment: .center, spacing: 8) {
                    ForEach(stats) { stat in
                        EventCard(
                            title: stat.title,
                            value: stat.value,
                            icon: stat.icon,
                            color: stat.color,
                            compact: true,
                            onEdit: { openDatesEditor() }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var hostedEventsSection: some View {
        let events = hostedUpcomingEvents

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Events", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Spacer()
                Button(action: {
                    showCreateEventSheet = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color.brand)
                }
            }
            .padding(.horizontal)

            if events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("No upcoming events")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    Text("Create an event or respond to invites to see details here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(events) { event in
                            let inviteStatus = eventsService.inviteStatus(for: event)
                            let isTentative = eventsService.isInvited(event) && !eventsService.isOrganizer(event) && inviteStatus == .maybe

                            Button(action: {
                                selectedEvent = event
                            }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Event: \(event.title)")
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                        Spacer()

                                        HStack(spacing: 6) {
                                            if isTentative {
                                                Text("Tentative")
                                                    .font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.orange.opacity(0.16))
                                                    .foregroundColor(.orange)
                                                    .clipShape(Capsule())
                                            }

                                            Text(event.visibility.rawValue)
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.brand.opacity(0.12))
                                                .foregroundColor(Color.brand)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Label(profileEventDateLine(event.startAt), systemImage: "clock")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    if !event.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Label(event.locationName, systemImage: "mappin.and.ellipse")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Divider().opacity(0.25)

                                    if event.attendingNames.isEmpty {
                                        Text("No attendees yet")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Going: \(event.attendingNames.joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(12)
                                .frame(width: 260, alignment: .leading)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.brand.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func profileEventDateLine(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Interests", systemImage: "heart")
                    .font(.headline)
                Spacer()
                Button(action: {
                    if showingInterestEditor {
                        saveInterestEdits()
                    } else {
                        editInterestsBuffer = interests
                        showingInterestEditor = true
                    }
                }) {
                    Image(systemName: showingInterestEditor ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color.brand)
                }
            }
            .padding(.horizontal)
            
            if showingInterestEditor {
                let presetInterests: [String] = ["technology", "hiking", "books", "coffee", "travel", "photography", "fitness", "cooking", "music", "art"]
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presetInterests, id: \.self) { preset in
                            let selected = editInterestsBuffer.contains { $0.caseInsensitiveCompare(preset) == .orderedSame }
                            Button(action: {
                                if selected { 
                                    editInterestsBuffer.removeAll { $0.caseInsensitiveCompare(preset) == .orderedSame }
                                } else {
                                    editInterestsBuffer.append(preset)
                                }
                            }) {
                                Text(preset.capitalized)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.brand : Color(UIColor.secondarySystemFill)))
                                    .foregroundColor(selected ? .white : .primary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if interests.isEmpty && !showingInterestEditor {
                VStack(spacing: 12) {
                    Image(systemName: "heart")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    VStack(spacing: 4) {
                        Text("No interests yet")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Text("Add interests to get personalized recommendations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth:. infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
            } else if !interests.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(interests, id: \.self) { interest in
                            HStack(spacing: 6) {
                                Text(interest.capitalized)
                                    .font(.caption)
                                
                                if showingInterestEditor {
                                    Button(action: { removeInterest(interest) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.brand.opacity(0.12)))
                            .foregroundColor(Color.brand)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            if showingInterestEditor {
                HStack(spacing: 8) {
                    TextField("Add interest...", text: $newInterest, onCommit: addInterest)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: addInterest) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(Color.brand)
                    }
                    .disabled(newInterest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var giftIdeasSection: some View {
        let recommendations = userRecommendations
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Shop Suggestions", systemImage: "gift")
                    .font(.headline)
                Spacer()
                if !recommendations.isEmpty {
                    Text("\(recommendations.count)+")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.brand))
                }
            }
            .padding(.horizontal)

            if recommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "gift")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    VStack(spacing: 4) {
                        Text("No recommendations yet")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Text("Add interests to see personalized shop suggestions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recommendations.prefix(10)) { gift in
                            ProductCard(gift: gift)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private var gradientPickerSheet: some View {
        VStack(spacing: 16) {
            Text("Choose a Gradient").font(.headline).padding(.top)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<4) { idx in
                        let presets: [[Color]] = [
                            [Color(red:0.11,green:0.44,blue:0.98), Color.brandEnd],
                            [Color(red:0.0,green:0.6,blue:0.4), Color.green],
                            [Color.orange, Color.pink],
                            [Color.gray, Color.black]
                        ]
                        let g = presets[idx]
                        Button(action: {
                            profileBannerGradientIndex = idx
                            profileBannerMode = "gradient"
                            saveBannerPreferences()
                            showingGradientPicker = false
                        }) {
                            LinearGradient(colors: g, startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(width: 160, height: 100)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
            Spacer()
            Button("Done") { showingGradientPicker = false }.padding(.bottom)
        }
    }
    
    private var editNameSheet: some View {
        NavigationView {
            ZStack {
                AppBackground()
                
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Profile Identity")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 12) {
                            // Display name
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(Color.brand)
                                    .frame(width: 28)
                                TextField("Full name", text: $editName)
                                    .font(.subheadline)
                                    .textContentType(.name)
                            }
                            .padding(12)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(10)
                            
                            // Username
                            HStack {
                                Image(systemName: "at")
                                    .foregroundColor(.purple)
                                    .frame(width: 28)
                                Text("@")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("username", text: $editUserId)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.subheadline)
                                    .onChange(of: editUserId) { value in
                                        scheduleUserIdCheck(value)
                                    }
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(10)

                            HStack(spacing: 6) {
                                if let icon = userIdStatusIcon {
                                    Image(systemName: icon)
                                        .font(.caption)
                                }
                                Text(userIdStatusText)
                                    .font(.caption)
                            }
                            .foregroundColor(userIdStatusColor)

                            if let identityErrorMessage {
                                Text(identityErrorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        
                        Text("Choose any username with 3-20 lowercase letters, numbers, or underscores.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .padding(.top)
            }
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingEditName = false
                    }
                    .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        saveIdentityChanges()
                    }) {
                        if isSavingIdentity {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.9)
                                Text("Saving")
                                    .font(.headline)
                            }
                        } else {
                            Text("Save")
                                .font(.headline)
                        }
                    }
                    .foregroundColor(Color.brand)
                    .disabled(isIdentitySaveDisabled)
                }
            }
        }
    }

    private var isIdentitySaveDisabled: Bool {
        let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizeUserId(editUserId)
        if isSavingIdentity { return true }
        if trimmedName.isEmpty { return true }
        if normalized.isEmpty || !isValidUserId(normalized) { return true }
        if userIdAvailability == .checking || userIdAvailability == .taken || userIdAvailability == .invalid { return true }
        return false
    }

    private var userIdStatusText: String {
        switch userIdAvailability {
        case .idle:
            return "Usernames are public. Use 3-20 letters, numbers, or underscore."
        case .checking:
            return "Checking username availability..."
        case .available:
            return "Username is available"
        case .taken:
            return "Username is already taken"
        case .invalid:
            return "Username must be 3-20 letters, numbers, or underscore."
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

    private func startIdentityEditing() {
        identityErrorMessage = nil
        editName = userName
        editUserId = resolvedUserId
        scheduleUserIdCheck(editUserId)
    }

    private func normalizeUserId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidUserId(_ value: String) -> Bool {
        let pattern = "^[a-z0-9_]{3,20}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private func scheduleUserIdCheck(_ value: String) {
        identityErrorMessage = nil

        let normalized = normalizeUserId(value)
        if normalized.isEmpty {
            userIdAvailability = .idle
            return
        }

        if !isValidUserId(normalized) {
            userIdAvailability = .invalid
            return
        }

        if normalized == normalizeUserId(userId) {
            userIdAvailability = .available
            return
        }

        userIdAvailability = .checking
        checkUserIdAvailability(normalized)
    }

    private func checkUserIdAvailability(_ candidate: String) {
        let db = Firestore.firestore()
        db.collection("usernames").document(candidate).getDocument { snapshot, error in
            DispatchQueue.main.async {
                if candidate != normalizeUserId(editUserId) {
                    return
                }

                if error != nil {
                    userIdAvailability = .idle
                    return
                }

                if snapshot?.exists == true {
                    let mappedUid = snapshot?.data()?["uid"] as? String
                    let currentUid = Auth.auth().currentUser?.uid
                    userIdAvailability = (mappedUid == currentUid) ? .available : .taken
                } else {
                    userIdAvailability = .available
                }
            }
        }
    }

    private func saveIdentityChanges() {
        identityErrorMessage = nil
        let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizeUserId(editUserId)

        guard !trimmedName.isEmpty else {
            identityErrorMessage = "Name cannot be empty."
            return
        }

        guard isValidUserId(normalized) else {
            userIdAvailability = .invalid
            identityErrorMessage = "Choose a valid username."
            return
        }

        if let uid = Auth.auth().currentUser?.uid {
            isSavingIdentity = true
            updateIdentityInFirestore(uid: uid, displayName: trimmedName, newUserId: normalized)
        } else {
            userName = trimmedName
            userId = normalized
            showingEditName = false
        }
    }

    private func updateIdentityInFirestore(uid: String, displayName: String, newUserId: String) {
        let db = Firestore.firestore()
        let normalizedOldUserId = normalizeUserId(userId)
        let usersRef = db.collection("users").document(uid)
        let newHandleRef = db.collection("usernames").document(newUserId)

        db.runTransaction({ transaction, errorPointer -> Any? in
            if newUserId != normalizedOldUserId {
                let newSnapshot: DocumentSnapshot
                do {
                    newSnapshot = try transaction.getDocument(newHandleRef)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }

                if newSnapshot.exists,
                   let mappedUid = newSnapshot.data()?["uid"] as? String,
                   mappedUid != uid {
                    errorPointer?.pointee = NSError(
                        domain: "GiftMinder",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "That username is already taken."]
                    )
                    return nil
                }

                transaction.setData(
                    [
                        "uid": uid,
                        "userId": newUserId,
                        "createdAt": FieldValue.serverTimestamp()
                    ],
                    forDocument: newHandleRef,
                    merge: true
                )

                if !normalizedOldUserId.isEmpty {
                    let oldHandleRef = db.collection("usernames").document(normalizedOldUserId)
                    do {
                        let oldSnapshot = try transaction.getDocument(oldHandleRef)
                        if oldSnapshot.exists,
                           let oldUid = oldSnapshot.data()?["uid"] as? String,
                           oldUid == uid {
                            transaction.deleteDocument(oldHandleRef)
                        }
                    } catch {
                        // Ignore old handle cleanup failures to avoid blocking updates.
                    }
                }
            }

            transaction.setData(
                [
                    "uid": uid,
                    "displayName": displayName,
                    "name": displayName,
                    "userId": newUserId,
                    "updatedAt": FieldValue.serverTimestamp()
                ],
                forDocument: usersRef,
                merge: true
            )

            return nil
        }) { _, error in
            DispatchQueue.main.async {
                isSavingIdentity = false
                if let error = error {
                    identityErrorMessage = error.localizedDescription
                    if identityErrorMessage?.localizedCaseInsensitiveContains("taken") == true {
                        userIdAvailability = .taken
                    }
                    return
                }

                userName = displayName
                userId = newUserId
                userIdAvailability = .available
                showingEditName = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showIdentitySavedToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showIdentitySavedToast = false
                    }
                }
            }
        }
    }

    private func syncIdentityFromBackendIfNeeded() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let isAccountSwitch = lastSyncedAuthUid != uid

        if isAccountSwitch {
            resetLocalProfileStateForAccountSwitch()
            lastSyncedAuthUid = uid
            restoreProfilePresentationFromScopedCache()
        }

        let hasLocalUserId = !normalizeUserId(userId).isEmpty
        let hasLocalName = !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasLocalUserId && hasLocalName && !isAccountSwitch { return }

        Firestore.firestore().collection("users").document(uid).getDocument { snapshot, _ in
            DispatchQueue.main.async {
                guard let data = snapshot?.data() else {
                    recoverIdentityFallback(for: uid)
                    return
                }
                lastSyncedAuthUid = uid
                if !hasLocalUserId, let remoteUserId = data["userId"] as? String {
                    userId = normalizeUserId(remoteUserId)
                }
                if !hasLocalName {
                    if let displayName = normalizedProfileDisplayName(from: data["displayName"] as? String) {
                        userName = displayName
                    } else if let name = normalizedProfileDisplayName(from: data["name"] as? String) {
                        userName = name
                    }
                }

                if normalizeUserId(userId).isEmpty {
                    recoverIdentityFallback(for: uid)
                }

                userSubtitle = ((data["subtitle"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                userBio = ((data["bio"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                if let remoteFontStyle = data["profileFontStyle"] as? String,
                   ["default", "rounded", "serif", "monospaced"].contains(remoteFontStyle) {
                    profileFontStyleRaw = remoteFontStyle
                } else {
                    profileFontStyleRaw = "default"
                }

                profileAnimationsEnabled = (data["profileAnimationsEnabled"] as? Bool) ?? false

                let remoteInterests = data["interests"] as? [String] ?? []
                userInterestsRaw = remoteInterests
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")

                applyRemoteProfileDates(from: data)
                syncProfileImageFromBackend(data)
                syncScopedIdentityMirror()

                saveProfilePresentationToScopedCache()
            }
        }
    }

    private func recoverIdentityFallback(for uid: String) {
        let db = Firestore.firestore()

        if userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let authDisplay = Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authDisplay.isEmpty {
            userName = authDisplay
        }

        db.collection("usernames")
            .whereField("uid", isEqualTo: uid)
            .limit(to: 1)
            .getDocuments { snapshot, _ in
                DispatchQueue.main.async {
                    guard normalizeUserId(userId).isEmpty,
                          let doc = snapshot?.documents.first else { return }

                    let mappedUserId = (doc.data()["userId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? doc.documentID
                    userId = normalizeUserId(mappedUserId)
                }
            }
    }

    private func startRealtimeProfileListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        profileRealtimeListener?.remove()
        profileRealtimeListener = Firestore.firestore().collection("users").document(uid)
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data() else { return }

                if let remoteName = normalizedProfileDisplayName(from: data["displayName"] as? String) {
                    userName = remoteName
                } else if let remoteName = normalizedProfileDisplayName(from: data["name"] as? String) {
                    userName = remoteName
                }

                if let remoteUserId = (data["userId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !remoteUserId.isEmpty {
                    userId = normalizeUserId(remoteUserId)
                }

                userSubtitle = ((data["subtitle"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                userBio = ((data["bio"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                if let remoteFontStyle = data["profileFontStyle"] as? String,
                   ["default", "rounded", "serif", "monospaced"].contains(remoteFontStyle) {
                    profileFontStyleRaw = remoteFontStyle
                } else {
                    profileFontStyleRaw = "default"
                }
                profileAnimationsEnabled = false
                profileAvatarPulse = false
                let remoteInterests = data["interests"] as? [String] ?? []
                userInterestsRaw = remoteInterests
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")

                applyRemoteProfileDates(from: data)
                syncProfileImageFromBackend(data)
                syncScopedIdentityMirror()

                saveProfilePresentationToScopedCache()
            }
    }

    private func resetLocalProfileStateForAccountSwitch() {
        userName = ""
        userId = ""
        userBio = ""
        userInterestsRaw = ""
        userSubtitle = ""
        profileFontStyleRaw = "default"
        profileAnimationsEnabled = false
        userDOBTime = 0
        userAnniversaryTime = 0
        userOtherDatesRaw = "[]"
        profileUIImage = nil
        bannerUIImage = nil
    }

    private func persistProfilePresentationToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        saveProfilePresentationToScopedCache()

        let displayName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = userSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let bio = userBio.trimmingCharacters(in: .whitespacesAndNewlines)
        let interests = userInterestsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let otherDatesPayload: [[String: Any]] = loadOtherDates().map { other in
            [
                "label": other.label,
                "time": other.time,
            ]
        }

        Firestore.firestore().collection("users").document(uid).setData([
            "displayName": displayName,
            "name": displayName,
            "userId": resolvedUserId,
            "subtitle": subtitle,
            "bio": bio,
            "interests": interests,
            "userDOBTime": userDOBTime,
            "userAnniversaryTime": userAnniversaryTime,
            "userOtherDates": otherDatesPayload,
            "profileFontStyle": profileFontStyleRaw,
            "profileAnimationsEnabled": false,
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true)

        syncScopedIdentityMirror()
    }

    private func syncScopedIdentityMirror() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let defaults = UserDefaults.standard
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedId = normalizeUserId(userId)

        if !trimmedName.isEmpty {
            defaults.set(trimmedName, forKey: "identity_\(uid)_displayName")
        }
        if !normalizedId.isEmpty {
            defaults.set(normalizedId, forKey: "identity_\(uid)_userId")
        }
    }

    private func applyRemoteProfileDates(from data: [String: Any]) {
        if let dob = data["userDOBTime"] as? Double {
            userDOBTime = dob
        } else if let dobNumber = data["userDOBTime"] as? NSNumber {
            userDOBTime = dobNumber.doubleValue
        }

        if let anniversary = data["userAnniversaryTime"] as? Double {
            userAnniversaryTime = anniversary
        } else if let anniversaryNumber = data["userAnniversaryTime"] as? NSNumber {
            userAnniversaryTime = anniversaryNumber.doubleValue
        }

        if let rawOther = data["userOtherDates"] as? [[String: Any]] {
            let parsed: [OtherDate] = rawOther.compactMap { item in
                let label = (item["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let time = (item["time"] as? Double) ?? (item["time"] as? NSNumber)?.doubleValue ?? 0
                guard !label.isEmpty, time > 0 else { return nil }
                return OtherDate(label: label, time: time)
            }

            if let encoded = try? JSONEncoder().encode(parsed),
               let raw = String(data: encoded, encoding: .utf8) {
                userOtherDatesRaw = raw
            } else {
                userOtherDatesRaw = "[]"
            }
        }
    }

    private func restoreProfilePresentationFromScopedCache() {
        let defaults = UserDefaults.standard

        if let subtitle = defaults.string(forKey: scopedProfileKey("subtitle")) {
            userSubtitle = subtitle
        } else {
            userSubtitle = ""
        }

        if let bio = defaults.string(forKey: scopedProfileKey("bio")) {
            userBio = bio
        } else {
            userBio = ""
        }

        if let interests = defaults.string(forKey: scopedProfileKey("interestsRaw")) {
            userInterestsRaw = interests
        } else {
            userInterestsRaw = ""
        }

        let fontStyle = defaults.string(forKey: scopedProfileKey("fontStyle")) ?? "default"
        profileFontStyleRaw = ["default", "rounded", "serif", "monospaced"].contains(fontStyle) ? fontStyle : "default"

        let animationsKey = scopedProfileKey("animationsEnabled")
        profileAnimationsEnabled = defaults.object(forKey: animationsKey) == nil ? false : defaults.bool(forKey: animationsKey)

        let dobKey = scopedProfileKey("dobTime")
        userDOBTime = defaults.object(forKey: dobKey) == nil ? 0 : defaults.double(forKey: dobKey)

        let anniversaryKey = scopedProfileKey("anniversaryTime")
        userAnniversaryTime = defaults.object(forKey: anniversaryKey) == nil ? 0 : defaults.double(forKey: anniversaryKey)

        if let otherDatesRaw = defaults.string(forKey: scopedProfileKey("otherDatesRaw")) {
            userOtherDatesRaw = otherDatesRaw
        } else {
            userOtherDatesRaw = "[]"
        }
    }

    private func saveProfilePresentationToScopedCache() {
        let defaults = UserDefaults.standard
        defaults.set(userSubtitle, forKey: scopedProfileKey("subtitle"))
        defaults.set(userBio, forKey: scopedProfileKey("bio"))
        defaults.set(userInterestsRaw, forKey: scopedProfileKey("interestsRaw"))
        defaults.set(profileFontStyleRaw, forKey: scopedProfileKey("fontStyle"))
        defaults.set(profileAnimationsEnabled, forKey: scopedProfileKey("animationsEnabled"))
        defaults.set(userDOBTime, forKey: scopedProfileKey("dobTime"))
        defaults.set(userAnniversaryTime, forKey: scopedProfileKey("anniversaryTime"))
        defaults.set(userOtherDatesRaw, forKey: scopedProfileKey("otherDatesRaw"))
    }

    private func scopedProfileKey(_ suffix: String) -> String {
        let uid = Auth.auth().currentUser?.uid ?? "guest"
        return "profile_\(uid)_\(suffix)"
    }

    private func normalizedProfileDisplayName(from value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        return trimmed
    }

    private func startProfileAnimationsIfNeeded() {
        profileAvatarPulse = false
    }

    private func openDatesEditor() {
        editHasDOB = userDOB != nil
        editHasAnniversary = userAnniversary != nil
        editDOB = userDOB ?? Date()
        editAnniversary = userAnniversary ?? Date()
        editOtherDates = loadOtherDates()
        showingEditDates = true
    }

    private func clearProfileTextDraft() {
        editSubtitle = ""
        editBio = ""
        editInterestsRaw = ""
    }

    private func removeProfilePhoto() {
        profileUIImage = nil
        inputImage = nil
        UserDefaults.standard.removeObject(forKey: currentUserProfileImageKey())
        UserDefaults.standard.removeObject(forKey: currentUserProfileImageURLKey())
        clearProfileImageFromBackend()
    }

    private func removeProfileBanner() {
        profileBannerMode = "none"
        saveBannerPreferences()
        bannerUIImage = nil
        bannerInputImage = nil
        UserDefaults.standard.removeObject(forKey: currentProfileBannerImageKey())
    }

    private var editDatesSheet: some View {
        NavigationView {
            ZStack {
                AppBackground()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Important Dates Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Important Dates")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 12) {
                                // Date of Birth
                                if editHasDOB {
                                    HStack {
                                        Image(systemName: "birthday.cake.fill")
                                            .foregroundColor(Color.brand)
                                            .frame(width: 28)
                                        Text("Birthday")
                                            .font(.subheadline)
                                        Spacer()
                                        DatePicker("", selection: $editDOB, displayedComponents: .date)
                                            .labelsHidden()
                                        Button(role: .destructive) {
                                            showDeleteBirthdayConfirmation = true
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(10)
                                } else {
                                    Button {
                                        editHasDOB = true
                                        editDOB = Date()
                                    } label: {
                                        Label("Add Birthday", systemImage: "plus.circle")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(10)
                                }
                                
                                // Anniversary
                                if editHasAnniversary {
                                    HStack {
                                        Image(systemName: "heart.circle.fill")
                                            .foregroundColor(.pink)
                                            .frame(width: 28)
                                        Text("Anniversary")
                                            .font(.subheadline)
                                        Spacer()
                                        DatePicker("", selection: $editAnniversary, displayedComponents: .date)
                                            .labelsHidden()
                                        Button(role: .destructive) {
                                            showDeleteAnniversaryConfirmation = true
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(10)
                                } else {
                                    Button {
                                        editHasAnniversary = true
                                        editAnniversary = Date()
                                    } label: {
                                        Label("Add Anniversary", systemImage: "plus.circle")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                        
                        // Custom Events Card
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Custom Events")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                if !editOtherDates.isEmpty {
                                    Text("\(editOtherDates.count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.brand))
                                }
                            }
                            
                            if editOtherDates.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "calendar.badge.plus")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    Text("No custom events yet")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(12)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach($editOtherDates) { $od in
                                        HStack(spacing: 12) {
                                            Image(systemName: "calendar")
                                                .foregroundColor(.blue)
                                                .frame(width: 28)
                                            
                                            TextField("Event name", text: $od.label)
                                                .font(.subheadline)
                                            
                                            DatePicker("", selection: Binding(
                                                get: { Date(timeIntervalSince1970: od.time) },
                                                set: { od.time = $0.timeIntervalSince1970 }
                                            ), displayedComponents: .date)
                                            .labelsHidden()
                                            .fixedSize()

                                            Button(role: .destructive) {
                                                pendingDeleteOtherDateId = od.id
                                            } label: {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red)
                                            }
                                        }
                                        .padding(12)
                                        .background(Color(UIColor.tertiarySystemBackground))
                                        .cornerRadius(10)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                pendingDeleteOtherDateId = od.id
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Add new event
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(Color.brand)
                                        .frame(width: 28)
                                    
                                    TextField("Event name", text: $newOtherLabel)
                                        .font(.subheadline)
                                    
                                    DatePicker("", selection: $newOtherDate, displayedComponents: .date)
                                        .labelsHidden()
                                        .fixedSize()
                                }
                                .padding(12)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(10)
                                
                                Button(action: {
                                    let od = OtherDate(
                                        label: newOtherLabel.isEmpty ? "Event" : newOtherLabel,
                                        time: newOtherDate.timeIntervalSince1970
                                    )
                                    editOtherDates.append(od)
                                    newOtherLabel = ""
                                    newOtherDate = Date()
                                }) {
                                    HStack {
                                        Image(systemName: "plus")
                                        Text("Add Event")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(newOtherLabel.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.brand)
                                    )
                                }
                                .disabled(newOtherLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)

                        Text("Delete one item at a time using the trash icon next to each birthday, anniversary, or custom event.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Edit Dates")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete Birthday?", isPresented: $showDeleteBirthdayConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    editHasDOB = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your birthday from the Info section.")
            }
            .confirmationDialog("Delete Anniversary?", isPresented: $showDeleteAnniversaryConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    editHasAnniversary = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your anniversary from the Info section.")
            }
            .confirmationDialog("Delete Event?", isPresented: Binding(
                get: { pendingDeleteOtherDateId != nil },
                set: { newValue in
                    if !newValue {
                        pendingDeleteOtherDateId = nil
                    }
                }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDeleteOtherDateId,
                       let index = editOtherDates.firstIndex(where: { $0.id == id }) {
                        editOtherDates.remove(at: index)
                    }
                    pendingDeleteOtherDateId = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteOtherDateId = nil
                }
            } message: {
                Text("This removes this custom event from the Info section.")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingEditDates = false
                    }
                    .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        userDOBTime = editHasDOB ? editDOB.timeIntervalSince1970 : 0
                        userAnniversaryTime = editHasAnniversary ? editAnniversary.timeIntervalSince1970 : 0
                        saveOtherDates(editOtherDates)
                        persistProfilePresentationToFirestore()
                        showingEditDates = false
                    }
                    .font(.headline)
                    .foregroundColor(Color.brand)
                }
            }
        }
    }
    
    private var editProfileSheet: some View {
        NavigationView {
            ZStack {
                AppBackground()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Basic Info Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Basic Info")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 12) {
                                // Name
                                HStack {
                                    Image(systemName: "person.fill")
                                        .foregroundColor(Color.brand)
                                        .frame(width: 28)
                                    TextField("Full name", text: $editName)
                                        .font(.subheadline)
                                }
                                .padding(12)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(10)
                                
                                // Title/Subtitle
                                HStack {
                                    Image(systemName: "text.quote")
                                        .foregroundColor(.purple)
                                        .frame(width: 28)
                                    TextField("Title or tagline", text: $editSubtitle)
                                        .font(.subheadline)
                                }
                                .padding(12)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(10)

                                HStack(alignment: .top) {
                                    Image(systemName: "person.text.rectangle")
                                        .foregroundColor(Color.brand)
                                        .frame(width: 28)
                                        .padding(.top, 6)
                                    TextField("Bio", text: $editBio, axis: .vertical)
                                        .lineLimit(3...7)
                                        .font(.subheadline)
                                }
                                .padding(12)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Profile Theme")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Picker("Font Style", selection: $editProfileFontStyleRaw) {
                                Text("Default").tag("default")
                                Text("Rounded").tag("rounded")
                                Text("Serif").tag("serif")
                                Text("Mono").tag("monospaced")
                            }
                            .pickerStyle(.segmented)

                            Text("Profile animations are disabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                        
                        // Important Dates Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Important Dates")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 12) {
                                // Date of Birth
                                if editHasDOB {
                                    HStack {
                                        Image(systemName: "birthday.cake.fill")
                                            .foregroundColor(Color.brand)
                                            .frame(width: 28)
                                        Text("Birthday")
                                            .font(.subheadline)
                                        Spacer()
                                        DatePicker("", selection: $editDOB, displayedComponents: .date)
                                            .labelsHidden()
                                        Button(role: .destructive) {
                                            showDeleteBirthdayConfirmation = true
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(10)
                                } else {
                                    Button {
                                        editHasDOB = true
                                        editDOB = Date()
                                    } label: {
                                        Label("Add Birthday", systemImage: "plus.circle")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(10)
                                }
                                
                                // Anniversary
                                if editHasAnniversary {
                                    HStack {
                                        Image(systemName: "heart.circle.fill")
                                            .foregroundColor(.pink)
                                            .frame(width: 28)
                                        Text("Anniversary")
                                            .font(.subheadline)
                                        Spacer()
                                        DatePicker("", selection: $editAnniversary, displayedComponents: .date)
                                            .labelsHidden()
                                        Button(role: .destructive) {
                                            showDeleteAnniversaryConfirmation = true
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(10)
                                } else {
                                    Button {
                                        editHasAnniversary = true
                                        editAnniversary = Date()
                                    } label: {
                                        Label("Add Anniversary", systemImage: "plus.circle")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                        
                        // Custom Events Card
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Custom Events")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                if !editOtherDates.isEmpty {
                                    Text("\(editOtherDates.count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.brand))
                                }
                            }
                            
                            if !editOtherDates.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach($editOtherDates) { $od in
                                        HStack(spacing: 12) {
                                            Image(systemName: "calendar")
                                                .foregroundColor(.blue)
                                                .frame(width: 28)
                                            
                                            TextField("Event name", text: $od.label)
                                                .font(.subheadline)
                                            
                                            DatePicker("", selection: Binding(
                                                get: { Date(timeIntervalSince1970: od.time) },
                                                set: { od.time = $0.timeIntervalSince1970 }
                                            ), displayedComponents: .date)
                                            .labelsHidden()
                                            .fixedSize()

                                            Button(role: .destructive) {
                                                pendingDeleteOtherDateId = od.id
                                            } label: {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red)
                                            }
                                        }
                                        .padding(12)
                                        .background(Color(UIColor.tertiarySystemBackground))
                                        .cornerRadius(10)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                pendingDeleteOtherDateId = od.id
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Add new event
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(Color.brand)
                                        .frame(width: 28)
                                    
                                    TextField("Event name", text: $newOtherLabel)
                                        .font(.subheadline)
                                    
                                    DatePicker("", selection: $newOtherDate, displayedComponents: .date)
                                        .labelsHidden()
                                        .fixedSize()
                                }
                                .padding(12)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(10)
                                
                                Button(action: {
                                    let od = OtherDate(
                                        label: newOtherLabel.isEmpty ? "Event" : newOtherLabel,
                                        time: newOtherDate.timeIntervalSince1970
                                    )
                                    editOtherDates.append(od)
                                    newOtherLabel = ""
                                    newOtherDate = Date()
                                }) {
                                    HStack {
                                        Image(systemName: "plus")
                                        Text("Add Event")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(newOtherLabel.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.brand)
                                    )
                                }
                                .disabled(newOtherLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                        
                        // Interests Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Interests")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.pink)
                                    .frame(width: 28)
                                TextField("Technology, Books, Travel...", text: $editInterestsRaw)
                                    .font(.subheadline)
                            }
                            .padding(12)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(10)
                            
                            Text("Separate multiple interests with commas")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Delete Profile Data")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Button(role: .destructive) {
                                clearProfileTextDraft()
                            } label: {
                                Label("Clear Bio, Subtitle & Interests", systemImage: "text.badge.minus")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)

                            Button(role: .destructive) {
                                removeProfilePhoto()
                            } label: {
                                Label("Remove Profile Photo", systemImage: "person.crop.circle.badge.xmark")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)

                            Button(role: .destructive) {
                                removeProfileBanner()
                            } label: {
                                Label("Remove Profile Banner", systemImage: "photo.badge.minus")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)

                            Text("Tip: tap Save to keep text/date changes.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete Birthday?", isPresented: $showDeleteBirthdayConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    editHasDOB = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your birthday from the Info section.")
            }
            .confirmationDialog("Delete Anniversary?", isPresented: $showDeleteAnniversaryConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    editHasAnniversary = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your anniversary from the Info section.")
            }
            .confirmationDialog("Delete Event?", isPresented: Binding(
                get: { pendingDeleteOtherDateId != nil },
                set: { newValue in
                    if !newValue {
                        pendingDeleteOtherDateId = nil
                    }
                }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDeleteOtherDateId,
                       let index = editOtherDates.firstIndex(where: { $0.id == id }) {
                        editOtherDates.remove(at: index)
                    }
                    pendingDeleteOtherDateId = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteOtherDateId = nil
                }
            } message: {
                Text("This removes this custom event from the Info section.")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingEditProfile = false
                    }
                    .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let sanitizedBio = editBio.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let violation = validateBioForModeration(sanitizedBio) {
                            moderationAlertMessage = violation
                            return
                        }

                        userName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
                        userSubtitle = editSubtitle
                        userInterestsRaw = editInterestsRaw
                        userDOBTime = editHasDOB ? editDOB.timeIntervalSince1970 : 0
                        userAnniversaryTime = editHasAnniversary ? editAnniversary.timeIntervalSince1970 : 0
                        saveOtherDates(editOtherDates)
                        userBio = sanitizedBio
                        profileFontStyleRaw = editProfileFontStyleRaw
                        profileAnimationsEnabled = false
                        persistProfilePresentationToFirestore()
                        syncScopedIdentityMirror()
                        profileAvatarPulse = false
                        showingEditProfile = false
                    }
                    .font(.headline)
                    .foregroundColor(Color.brand)
                }
            }
        }
    }

    private func addInterest() {
        let cleaned = newInterest.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }

        if showingInterestEditor {
            // operate on buffer
            if !editInterestsBuffer.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) {
                editInterestsBuffer.append(cleaned)
            }
        } else {
            var all = interests
            all.append(cleaned)
            userInterestsRaw = all.joined(separator: ", ")
        }

        newInterest = ""
    }

    private func removeInterest(_ interest: String) {
        if showingInterestEditor {
            editInterestsBuffer.removeAll { $0.caseInsensitiveCompare(interest) == .orderedSame }
        } else {
            let filtered = interests.filter { $0.caseInsensitiveCompare(interest) != .orderedSame }
            userInterestsRaw = filtered.joined(separator: ", ")
        }
    }

    private func addPresetInterest(_ interest: String) {
        let cleaned = interest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        // avoid duplicates (case-insensitive)
        if showingInterestEditor {
            if editInterestsBuffer.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) { return }
            editInterestsBuffer.append(cleaned)
            return
        }

        if interests.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) { return }
        var all = interests
        all.append(cleaned)
        userInterestsRaw = all.joined(separator: ", ")
    }

    private func saveInterestEdits() {
        // commit buffer to storage
        userInterestsRaw = editInterestsBuffer.joined(separator: ", ")
        showingInterestEditor = false
        // clear buffer
        editInterestsBuffer = []
    }

    private func loadSavedImage() {
        profileUIImage = nil
        if let data = UserDefaults.standard.data(forKey: currentUserProfileImageKey()), let ui = UIImage(data: data) {
            profileUIImage = ui
        }
    }

    private func loadImage() {
        guard let input = inputImage else { return }
        moderateSelectedProfileImage(input) { approved in
            guard approved else {
                inputImage = nil
                return
            }

            profileUIImage = input
            if let data = input.jpegData(compressionQuality: 0.85) {
                UserDefaults.standard.set(data, forKey: currentUserProfileImageKey())
                uploadProfileImageToBackend(imageData: data)
            }
            inputImage = nil
        }
    }

    private func syncProfileImageFromBackend(_ data: [String: Any]) {
        let remoteURL = ((data["profileImageURL"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remoteURL.isEmpty else { return }

        let urlKey = currentUserProfileImageURLKey()
        let cachedRemoteURL = UserDefaults.standard.string(forKey: urlKey) ?? ""
        if cachedRemoteURL == remoteURL,
           let data = UserDefaults.standard.data(forKey: currentUserProfileImageKey()),
           let image = UIImage(data: data) {
            profileUIImage = image
            return
        }

        guard let url = URL(string: remoteURL) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                UserDefaults.standard.set(data, forKey: currentUserProfileImageKey())
                UserDefaults.standard.set(remoteURL, forKey: urlKey)
                profileUIImage = image
            }
        }.resume()
    }

    private func uploadProfileImageToBackend(imageData: Data) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Storage.storage().reference().child("profileImages/\(uid).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        ref.putData(imageData, metadata: meta) { _, error in
            if let error {
                print("Failed uploading profile image: \(error.localizedDescription)")
                return
            }

            ref.downloadURL { url, error in
                if let error {
                    print("Failed to get profile image URL: \(error.localizedDescription)")
                    return
                }

                guard let url else { return }
                Firestore.firestore().collection("users").document(uid).setData([
                    "profileImageURL": url.absoluteString,
                    "photoURL": url.absoluteString,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)

                UserDefaults.standard.set(url.absoluteString, forKey: currentUserProfileImageURLKey())
            }
        }
    }

    private func clearProfileImageFromBackend() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid).setData([
            "profileImageURL": FieldValue.delete(),
            "photoURL": FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    private func validateBioForModeration(_ bio: String) -> String? {
        if bio.count > 240 {
            return "Bio must be 240 characters or fewer."
        }

        if containsUrlLikeText(bio) {
            return "Bio cannot include links or URL-style text."
        }

        let blockedTerms = ["porn", "nude", "xxx", "escort", "hate", "slur"]
        let lowered = bio.lowercased()
        if blockedTerms.contains(where: { lowered.contains($0) }) {
            return "Bio includes language that isn't allowed."
        }

        return nil
    }

    private func containsUrlLikeText(_ value: String) -> Bool {
        let pattern = "(https?://|www\\.|\\b[a-z0-9.-]+\\.[a-z]{2,}(/|\\b))"
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func moderateSelectedProfileImage(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            moderationAlertMessage = "Unable to process this image."
            completion(false)
            return
        }

        let byteSize = jpeg.count
        if byteSize > 5_000_000 {
            moderationAlertMessage = "Image is too large. Please choose an image under 5 MB."
            completion(false)
            return
        }

        let callable = Functions.functions().httpsCallable("moderateProfileContent")
        callable.call([
            "bio": userBio,
            "imageMeta": [
                "byteSize": byteSize,
                "width": Int(image.size.width),
                "height": Int(image.size.height),
            ],
        ]) { result, error in
            if let error {
                print("Profile image moderation call failed: \(error.localizedDescription)")
                completion(true)
                return
            }

            let payload = result?.data as? [String: Any]
            let allowed = payload?["allowed"] as? Bool ?? false
            if !allowed {
                let reasons = payload?["reasons"] as? [String] ?? []
                moderationAlertMessage = reasons.first ?? "This photo couldn't be approved."
                completion(false)
                return
            }

            completion(true)
        }
    }

    private func loadBannerSavedImage() {
        bannerUIImage = nil
        if let data = UserDefaults.standard.data(forKey: currentProfileBannerImageKey()), let ui = UIImage(data: data) {
            bannerUIImage = ui
        }
    }

    private func loadBannerImage() {
        guard let input = bannerInputImage else { return }
        bannerUIImage = input
        if let data = input.jpegData(compressionQuality: 0.85) {
            UserDefaults.standard.set(data, forKey: currentProfileBannerImageKey())
            profileBannerMode = "image"
            saveBannerPreferences()
        }
    }

    private func loadBannerPreferences() {
        let defaults = UserDefaults.standard
        profileBannerMode = defaults.string(forKey: currentProfileBannerModeKey()) ?? "gradient"
        profileBannerGradientIndex = defaults.integer(forKey: currentProfileBannerGradientIndexKey())
    }

    private func saveBannerPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(profileBannerMode, forKey: currentProfileBannerModeKey())
        defaults.set(profileBannerGradientIndex, forKey: currentProfileBannerGradientIndexKey())
    }

    private func currentUserProfileImageKey() -> String {
        let uid = Auth.auth().currentUser?.uid ?? "guest"
        return "userProfileImage_\(uid)"
    }

    private func currentUserProfileImageURLKey() -> String {
        let uid = Auth.auth().currentUser?.uid ?? "guest"
        return "userProfileImageURL_\(uid)"
    }

    private func currentProfileBannerImageKey() -> String {
        let uid = Auth.auth().currentUser?.uid ?? "guest"
        return "profileBannerImage_\(uid)"
    }

    private func currentProfileBannerModeKey() -> String {
        let uid = Auth.auth().currentUser?.uid ?? "guest"
        return "profileBannerMode_\(uid)"
    }

    private func currentProfileBannerGradientIndexKey() -> String {
        let uid = Auth.auth().currentUser?.uid ?? "guest"
        return "profileBannerGradientIndex_\(uid)"
    }

    private func monthDayOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// Simple stat tile
struct StatView: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.primary)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.headline).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }
}

// A tiny wrapping HStack for chips
struct WrapHStack<Element: Hashable, Content: View>: View {
    let items: [Element]
    let content: (Element) -> Content

    init(items: [Element], @ViewBuilder content: @escaping (Element) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    content(item)
                }
            }
        }
    }
}

// UIImagePicker representable
struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    @Binding var image: UIImage?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let ui = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.image = ui
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Settings View

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    @Published private(set) var products: [StoreKit.Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchaseInFlightProductID: String?
    @Published private(set) var activeSubscriptionProductID: String?
    @Published private(set) var statusMessage: String?

    private let proProductIDs: Set<String> = [
        "dave.b.GiftMinder.pro.monthly",
        "dave.b.GiftMinder.pro.yearly"
    ]
    private let defaults = UserDefaults.standard
    private var updatesTask: Task<Void, Never>?

    var isProSubscriber: Bool {
        activeSubscriptionProductID != nil
    }

    private init() {
        updatesTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            for await verificationResult in StoreKit.Transaction.updates {
                await self.handle(transactionVerificationResult: verificationResult, finish: true)
            }
        }

        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        if isLoadingProducts { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetched = try await StoreKit.Product.products(for: Array(proProductIDs))
            products = fetched.sorted(by: { $0.price < $1.price })
            if products.isEmpty {
                statusMessage = "No Pro products are currently available."
            }
        } catch {
            statusMessage = "Couldn’t load subscriptions right now."
            print("StoreKit loadProducts failed: \(error.localizedDescription)")
        }
    }

    func refreshEntitlements() async {
        var foundActiveProductID: String?

        for await verificationResult in StoreKit.Transaction.currentEntitlements {
            guard let transaction = verifiedTransaction(from: verificationResult) else { continue }
            guard proProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate < Date() { continue }
            foundActiveProductID = transaction.productID
            break
        }

        applyEntitlement(productID: foundActiveProductID)
    }

    func purchase(_ product: StoreKit.Product) async {
        purchaseInFlightProductID = product.id
        defer { purchaseInFlightProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                guard let transaction = verifiedTransaction(from: verificationResult) else {
                    statusMessage = "Purchase verification failed."
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                statusMessage = isProSubscriber ? "Pro is now active." : "Purchase completed, but entitlement is still updating."
            case .pending:
                statusMessage = "Purchase is pending approval."
            case .userCancelled:
                statusMessage = "Purchase cancelled."
            @unknown default:
                statusMessage = "Purchase didn’t complete."
            }
        } catch {
            statusMessage = "Couldn’t complete purchase right now."
            print("StoreKit purchase failed: \(error.localizedDescription)")
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isProSubscriber ? "Purchases restored." : "No active Pro subscription found to restore."
        } catch {
            statusMessage = "Couldn’t restore purchases right now."
            print("StoreKit restore failed: \(error.localizedDescription)")
        }
    }

    private func handle(transactionVerificationResult: StoreKit.VerificationResult<StoreKit.Transaction>, finish: Bool) async {
        guard let transaction = verifiedTransaction(from: transactionVerificationResult) else { return }
        if finish {
            await transaction.finish()
        }
        await refreshEntitlements()
    }

    private func verifiedTransaction(from verificationResult: StoreKit.VerificationResult<StoreKit.Transaction>) -> StoreKit.Transaction? {
        switch verificationResult {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            print("StoreKit verification failed: \(error.localizedDescription)")
            statusMessage = "Purchase verification failed."
            return nil
        }
    }

    private func applyEntitlement(productID: String?) {
        activeSubscriptionProductID = productID
        defaults.set(productID != nil, forKey: "isProSubscriber")
        if let productID {
            defaults.set(productID, forKey: "activeSubscriptionProductID")
        } else {
            defaults.removeObject(forKey: "activeSubscriptionProductID")
        }
    }
}

struct SettingsView: View {
    private let presetNotificationDays: [Int] = [0, 1, 7, 15, 30]
    @AppStorage("themeMode") private var themeModeRaw: String = ThemeMode.system.rawValue
    @AppStorage("authState") private var authStateRaw: String = AuthState.unauthenticated.rawValue
    @AppStorage("isProSubscriber") private var isProSubscriber: Bool = false
    @AppStorage("enableNotifications") private var enableNotifications: Bool = true
    @AppStorage("forumNotificationsEnabled") private var forumNotificationsEnabled: Bool = true
    @AppStorage("daysInAdvance") private var daysInAdvance: Int = 1
    @State private var selectedDaysInAdvanceOption: Int = 1
    @State private var customDaysInput: String = ""
    @StateObject private var subscriptionStore = SubscriptionStore.shared
    @FocusState private var isCustomDaysFieldFocused: Bool
    @State private var showLogoutAlert = false
    @State private var showHelpSheet = false
    @State private var showProUpgradeSheet = false
    @State private var showNotificationMessage = false
    @State private var notificationMessage = ""
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    private let developerName = "David Johnson"
    private let supportEmail = "david.b.johnson.dev@gmail.com"
    private let privacyPolicyURLString = ""
    
    private var themeModeBinding: Binding<ThemeMode> {
        Binding<ThemeMode>(
            get: { ThemeMode(rawValue: themeModeRaw) ?? .system },
            set: { themeModeRaw = $0.rawValue }
        )
    }
    
    private var authState: AuthState {
        get { AuthState(rawValue: authStateRaw) ?? .unauthenticated }
        nonmutating set { authStateRaw = newValue.rawValue }
    }

    private var accountButtonTitle: String {
        authState == .authenticated ? "Sign Out" : "Exit Guest Mode"
    }

    private var accountButtonMessage: String {
        authState == .authenticated ? "You will be signed out of your account." : "You will exit guest mode and return to the login screen."
    }

    private var privacyPolicyURL: URL? {
        guard !privacyPolicyURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(string: privacyPolicyURLString)
    }

    private var notificationPermissionMessage: String {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Event reminders are enabled on this device."
        case .notDetermined:
            return "Allow notifications to receive event reminders."
        case .denied:
            return "Notifications are turned off in iPhone Settings."
        @unknown default:
            return "Notification permission status is unavailable."
        }
    }

    private var planName: String {
        isProSubscriber ? "Pro" : "Free"
    }

    private var maxFreeReminderLeadTime: Int {
        presetNotificationDays.max() ?? 30
    }

    private var freePlanFeatures: [String] {
        [
            "Unlimited contacts, events, and invites",
            "Core reminders (same day, 1, 7, 15, or 30 days)",
            "Gift tracking and shopping recommendations"
        ]
    }

    private var proPlanFeatures: [String] {
        [
            "Custom reminder lead times (any number of days)",
            "Priority support",
            "Early access to upcoming premium features"
        ]
    }

    private var customDaysValue: Int? {
        guard let value = Int(customDaysInput.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 0 else {
            return nil
        }
        return value
    }

    var body: some View {
        AppNavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .center) {
                                Label("GiftMinder Pro", systemImage: "star.fill")
                                    .font(.headline)
                                    .foregroundColor(Color.brand)
                                Spacer()
                                Text(planName)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.brand.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            Text("Core reminders and planning stay free forever. Upgrade only for advanced controls.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Free")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(freePlanFeatures, id: \.self) { feature in
                                    Label(feature, systemImage: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Button(isProSubscriber ? "Manage Plan" : "Upgrade to Pro") {
                                showProUpgradeSheet = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.brand.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .padding(16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.brand.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 14) {
                            Label("Appearance", systemImage: "paintpalette.fill")
                                .font(.headline)
                                .foregroundColor(Color.brand)

                            Picker("Theme", selection: themeModeBinding) {
                                ForEach(ThemeMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        .padding(16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.brand.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 14) {
                            Label("Notifications", systemImage: "bell.badge.fill")
                                .font(.headline)
                                .foregroundColor(Color.brand)

                            Text("Get reminders for birthdays, anniversaries, and event-related updates.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("Enable notifications to receive timely alerts before important dates.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Toggle("Enable Event Notifications", isOn: $enableNotifications)
                                .onChange(of: enableNotifications) { enabled in
                                    if enabled {
                                        NotificationService.shared.requestNotificationPermissions { _ in
                                            refreshNotificationAuthorizationStatus()
                                        }
                                    } else {
                                        refreshNotificationAuthorizationStatus()
                                    }
                                    updateNotificationPreferences()
                                }

                            Toggle("Forum message notifications", isOn: $forumNotificationsEnabled)
                                .onChange(of: forumNotificationsEnabled) { _ in
                                    updateNotificationPreferences()
                                }

                            if enableNotifications {
                                Picker("Notify me", selection: $selectedDaysInAdvanceOption) {
                                    Text("Same day").tag(0)
                                    Text("1 day before").tag(1)
                                    Text("7 days before").tag(7)
                                    Text("15 days before").tag(15)
                                    Text("30 days before").tag(30)
                                    if isProSubscriber {
                                        Text("Custom...").tag(-1)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: selectedDaysInAdvanceOption) { selected in
                                    if selected >= 0 {
                                        daysInAdvance = selected
                                        customDaysInput = ""
                                        updateNotificationPreferences()
                                    } else if customDaysInput.isEmpty {
                                        customDaysInput = "\(daysInAdvance)"
                                    }
                                }

                                if !isProSubscriber {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Need reminders further out?")
                                            .font(.subheadline.weight(.semibold))
                                        Text("Custom lead times are available on Pro.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Button("See Pro options") {
                                            showProUpgradeSheet = true
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.brand.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                }

                                if selectedDaysInAdvanceOption == -1 {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Custom days before")
                                            .font(.subheadline.weight(.semibold))

                                        TextField("Enter number of days", text: $customDaysInput)
                                            .keyboardType(.numberPad)
                                            .textFieldStyle(.roundedBorder)
                                            .focused($isCustomDaysFieldFocused)

                                        Button("Save custom days") {
                                            applyCustomDaysIfValid()
                                            isCustomDaysFieldFocused = false
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.brand.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                        Text("Type any number from 0 and up, then tap Save custom days.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Text(notificationPermissionMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if notificationAuthorizationStatus == .notDetermined {
                                    Button("Allow Notifications") {
                                        NotificationService.shared.requestNotificationPermissions { _ in
                                            refreshNotificationAuthorizationStatus()
                                        }
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.brand.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                } else if notificationAuthorizationStatus == .denied {
                                    Button("Open iPhone Settings") {
                                        openSystemNotificationSettings()
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.brand.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.brand.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 14) {
                            Label("Help & FAQ", systemImage: "questionmark.circle.fill")
                                .font(.headline)
                                .foregroundColor(Color.brand)

                            Text("Learn how reminders, events, and gift tracking work.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button("How GiftMinder Works") {
                                showHelpSheet = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.brand.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .padding(16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.brand.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 14) {
                            Label("Account", systemImage: "person.crop.circle.fill")
                                .font(.headline)
                                .foregroundColor(Color.brand)

                            if authState == .authenticated {
                                if let email = Auth.auth().currentUser?.email {
                                    HStack(spacing: 10) {
                                        Image(systemName: "envelope.fill")
                                            .foregroundColor(.secondary)
                                        Text("Email")
                                        Spacer()
                                        Text(email)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .font(.subheadline)
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(12)
                                }
                            } else if authState == .guest {
                                HStack {
                                    Text("Status")
                                    Spacer()
                                    Text("Guest Mode")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                                .padding(12)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(12)
                            }

                            Button(action: { showLogoutAlert = true }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .foregroundColor(.red)
                                    Text(accountButtonTitle)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.brand.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 14) {
                            Label("About", systemImage: "info.circle.fill")
                                .font(.headline)
                                .foregroundColor(Color.brand)

                            HStack {
                                Text("Version")
                                Spacer()
                                Text("1.0.0")
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                            .padding(12)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(12)
                        }
                        .padding(16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.brand.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 14) {
                            Label("Developer & Privacy", systemImage: "lock.shield.fill")
                                .font(.headline)
                                .foregroundColor(Color.brand)

                            HStack {
                                Text("Developer")
                                Spacer()
                                Text(developerName)
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                            .padding(12)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(12)

                            HStack {
                                Text("Contact")
                                Spacer()
                                Text(supportEmail)
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                            .padding(12)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(12)

                            Group {
                                if let privacyPolicyURL {
                                    Link(destination: privacyPolicyURL) {
                                        HStack {
                                            Text("Privacy Policy")
                                                .foregroundColor(Color.brand)
                                            Spacer()
                                            Image(systemName: "arrow.up.right.square")
                                                .foregroundColor(Color.brand)
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.vertical, 12)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.brand.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                } else {
                                    HStack {
                                        Text("Privacy Policy")
                                        Spacer()
                                        Text("Link coming soon")
                                            .foregroundColor(.secondary)
                                    }
                                    .font(.subheadline)
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.brand.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal)

                        Spacer(minLength: 24)
                    }
                    .padding(.top, 12)
                }
                .coordinateSpace(name: "settingsScroll")
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("settingsScroll")).minY)
                })
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        applyCustomDaysIfValid()
                        isCustomDaysFieldFocused = false
                    }
                }
            }
            .onAppear {
                refreshNotificationAuthorizationStatus()
                syncNotificationLeadTimeSelection()
                Task {
                    await subscriptionStore.refreshEntitlements()
                    await subscriptionStore.loadProducts()
                    isProSubscriber = subscriptionStore.isProSubscriber
                }
            }
            .onChange(of: isProSubscriber) { hasPro in
                if !hasPro {
                    if daysInAdvance > maxFreeReminderLeadTime {
                        daysInAdvance = maxFreeReminderLeadTime
                    }
                    syncNotificationLeadTimeSelection()
                    updateNotificationPreferences()
                }
            }
            .onChange(of: subscriptionStore.isProSubscriber) { subscribed in
                isProSubscriber = subscribed
            }
            .alert("Are you sure?", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button(authState == .authenticated ? "Sign Out" : "Exit", role: .destructive) {
                    logout()
                }
            } message: {
                Text(accountButtonMessage)
            }
            .sheet(isPresented: $showHelpSheet) {
                HelpFAQView()
            }
            .sheet(isPresented: $showProUpgradeSheet) {
                ProUpgradeSheetView(
                    subscriptionStore: subscriptionStore,
                    isProSubscriber: $isProSubscriber,
                    freePlanFeatures: freePlanFeatures,
                    proPlanFeatures: proPlanFeatures
                )
            }
        }
    }
    
    private func updateNotificationPreferences() {
        NotificationService.shared.updateNotificationPreferences(
            enableNotifications: enableNotifications,
            daysInAdvance: daysInAdvance,
            forumNotificationsEnabled: forumNotificationsEnabled
        ) { success, error in
            if success {
                showNotificationMessage = true
                notificationMessage = "Notification settings updated"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showNotificationMessage = false
                }
            } else if let error = error {
                showNotificationMessage = true
                notificationMessage = "Update failed: \(error.localizedDescription)"
            }
        }
    }

    private func refreshNotificationAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationAuthorizationStatus = settings.authorizationStatus
            }
        }
    }

    private func openSystemNotificationSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    private func syncNotificationLeadTimeSelection() {
        if !isProSubscriber, daysInAdvance > maxFreeReminderLeadTime {
            daysInAdvance = maxFreeReminderLeadTime
        }

        if presetNotificationDays.contains(daysInAdvance) {
            selectedDaysInAdvanceOption = daysInAdvance
            customDaysInput = ""
        } else {
            if isProSubscriber {
                selectedDaysInAdvanceOption = -1
                customDaysInput = "\(daysInAdvance)"
            } else {
                selectedDaysInAdvanceOption = maxFreeReminderLeadTime
                customDaysInput = ""
            }
        }
    }

    private func applyCustomDaysIfValid() {
        guard isProSubscriber else {
            selectedDaysInAdvanceOption = maxFreeReminderLeadTime
            daysInAdvance = maxFreeReminderLeadTime
            customDaysInput = ""
            showProUpgradeSheet = true
            return
        }
        guard selectedDaysInAdvanceOption == -1, let customValue = customDaysValue else { return }
        daysInAdvance = customValue
        updateNotificationPreferences()
    }
    
    private func logout() {
        if authState == .authenticated {
            try? Auth.auth().signOut()
        }
        authState = .unauthenticated
    }
}

struct ProUpgradeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var subscriptionStore: SubscriptionStore
    @Binding var isProSubscriber: Bool
    let freePlanFeatures: [String]
    let proPlanFeatures: [String]

    var body: some View {
        AppNavigationView {
            List {
                Section("GiftMinder Plans") {
                    Text("Keep all core reminder and invite workflows free. Upgrade only for advanced controls.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section("Free") {
                    ForEach(freePlanFeatures, id: \.self) { feature in
                        Label(feature, systemImage: "checkmark")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Pro") {
                    ForEach(proPlanFeatures, id: \.self) { feature in
                        Label(feature, systemImage: "star.fill")
                    }
                }

                Section {
                    if subscriptionStore.products.isEmpty {
                        if subscriptionStore.isLoadingProducts {
                            HStack {
                                ProgressView()
                                Text("Loading subscriptions…")
                            }
                        } else {
                            Text("Subscriptions are currently unavailable.")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(subscriptionStore.products, id: \.id) { product in
                            Button {
                                Task {
                                    await subscriptionStore.purchase(product)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(product.displayName)
                                            .font(.subheadline.weight(.semibold))
                                        Text(product.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if subscriptionStore.purchaseInFlightProductID == product.id {
                                        ProgressView()
                                    } else {
                                        Text(product.displayPrice)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }
                            }
                            .disabled(subscriptionStore.purchaseInFlightProductID != nil)
                        }
                    }

                    Button("Restore Purchases") {
                        Task {
                            await subscriptionStore.restorePurchases()
                        }
                    }

                    if isProSubscriber {
                        Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    }
                } footer: {
                    Text(subscriptionStore.statusMessage ?? "Subscriptions are billed through your Apple ID and can be managed in App Store settings.")
                }
            }
            .navigationTitle("GiftMinder Pro")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    await subscriptionStore.refreshEntitlements()
                    await subscriptionStore.loadProducts()
                    isProSubscriber = subscriptionStore.isProSubscriber
                }
            }
            .onChange(of: subscriptionStore.isProSubscriber) { subscribed in
                isProSubscriber = subscribed
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct HelpFAQView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppNavigationView {
            List {
                Section("Start Here") {
                    Text("1) Add a contact with a birthday or anniversary.")
                    Text("2) Open Settings and choose your reminder lead time.")
                    Text("3) Add shop items under each contact and mark purchased when done.")
                }

                Section("Contacts & Profiles") {
                    Text("You can add and manage contacts even if they do not use GiftMinder.")
                    Text("If a contact is a GiftMinder user, they manage their own profile details, and their public profile reflects what they choose to share.")
                    Text("If someone exists in your device contacts/calendar imports, GiftMinder can use their contact photo as an avatar fallback when available.")
                }

                Section("How Reminders Work") {
                    Text("GiftMinder sends notifications for upcoming dates, event updates, and invite activity based on your preferences.")
                    Text("If notifications are disabled in iPhone Settings, reminders will not appear.")
                }

                Section("Events & Invites") {
                    Text("Create birthdays, celebrations, meetups, and other events from Home, then invite your contacts.")
                    Text("Event updates and invite responses can send push notifications when enabled.")
                }

                Section("Gift Tracking") {
                    Text("Use each contact's gift list to keep wishlist and purchased items separate.")
                    Text("Marking a gift as purchased updates its status so you avoid duplicate buys.")
                }

                Section("Shopping") {
                    Text("You can shop for yourself or switch the recipient to shop for someone else.")
                    Text("Recipient-specific suggestions use that person's saved interests and profile details.")
                }
            }
            .navigationTitle("Help & FAQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Contact Gift Row View
struct ContactGiftRowView: View {
    let gift: ContactGift
    var isReadOnly: Bool = false
    var onTap: () -> Void
    var onTogglePurchased: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Status checkbox
                Group {
                    if isReadOnly {
                        Image(systemName: gift.status == "purchased" ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundColor(gift.status == "purchased" ? .green : .gray)
                    } else {
                        Button(action: onTogglePurchased) {
                            Image(systemName: gift.status == "purchased" ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(gift.status == "purchased" ? .green : .gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Gift details
                VStack(alignment: .leading, spacing: 4) {
                    Text(gift.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .strikethrough(gift.status == "purchased", color: .secondary)
                        .foregroundColor(gift.status == "purchased" ? .secondary : .primary)

                    if let price = gift.price {
                        Text("$\(String(format: "%.2f", price))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let notes = gift.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isReadOnly {
                    Menu {
                        Button(action: onTap) {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(10)
        }
    }
}

// MARK: - Add/Edit Gift View
struct AddEditGiftView: View {
    let contact: Contact
    let gift: ContactGift?
    @Binding var isPresented: Bool
    var onSave: (ContactGift) -> Void

    @State private var title: String = ""
    @State private var price: String = ""
    @State private var url: String = ""
    @State private var status: String = "wishlist"
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var errorMessage = ""

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    var body: some View {
        NavigationView {
            Form {
                Section("Gift Details") {
                    TextField("Gift name *", text: $title)
                        .textContentType(.none)

                    TextField("Price (optional)", text: $price)
                        .keyboardType(.decimalPad)

                    TextField("URL (optional)", text: $url)
                        .textContentType(.URL)
                        .keyboardType(.URL)

                    Picker("Status", selection: $status) {
                        Text("Wishlist").tag("wishlist")
                        Text("Purchased").tag("purchased")
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(gift != nil ? "Edit Gift" : "Add Gift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveGift) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let gift = gift {
                    title = gift.title
                    price = gift.price.map { String(format: "%.2f", $0) } ?? ""
                    url = gift.url ?? ""
                    status = gift.status
                    notes = gift.notes ?? ""
                }
            }
        }
    }

    private func saveGift() {
        guard let currentUid = Auth.auth().currentUser?.uid.trimmingCharacters(in: .whitespacesAndNewlines), !currentUid.isEmpty else {
            errorMessage = "Please sign in to edit wishlist items"
            return
        }

        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Gift name is required"
            return
        }

        var priceValue: Double? = nil
        if !price.isEmpty {
            guard let p = Double(price), p >= 0 else {
                errorMessage = "Price must be a valid positive number"
                return
            }
            priceValue = p
        }

        if !url.isEmpty {
            guard isValidUrl(url) else {
                errorMessage = "URL must be a valid web address"
                return
            }
        }

        isSaving = true
        errorMessage = ""

        if let existingGift = gift {
            // Update existing gift
            db.collection("contacts")
                .document(contact.id.uuidString)
                .collection("gifts")
                .document(existingGift.id)
                .updateData([
                    "ownerUserId": currentUid,
                    "title": title,
                    "price": priceValue as Any,
                    "url": url.isEmpty ? NSNull() : url,
                    "status": status,
                    "notes": notes.isEmpty ? NSNull() : notes,
                    "updatedAt": FieldValue.serverTimestamp(),
                ]) { error in
                    isSaving = false
                    if let error = error {
                        errorMessage = "Error updating gift: \(error.localizedDescription)"
                    } else {
                        let updatedGift = ContactGift(
                            id: existingGift.id,
                            title: title,
                            price: priceValue,
                            url: url.isEmpty ? nil : url,
                            status: status,
                            notes: notes.isEmpty ? nil : notes,
                            createdAt: existingGift.createdAt,
                            updatedAt: Date()
                        )
                        onSave(updatedGift)
                        isPresented = false
                    }
                }
        } else {
            // Create new gift
            let giftsRef = db.collection("contacts").document(contact.id.uuidString).collection("gifts")
            let docRef = giftsRef.document()

            docRef.setData([
                "ownerUserId": currentUid,
                "title": title,
                "price": priceValue as Any,
                "url": url.isEmpty ? NSNull() : url,
                "status": status,
                "notes": notes.isEmpty ? NSNull() : notes,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]) { error in
                isSaving = false
                if let error = error {
                    errorMessage = "Error creating gift: \(error.localizedDescription)"
                } else {
                    let newGift = ContactGift(
                        id: docRef.documentID,
                        title: title,
                        price: priceValue,
                        url: url.isEmpty ? nil : url,
                        status: status,
                        notes: notes.isEmpty ? nil : notes
                    )
                    onSave(newGift)
                    isPresented = false
                }
            }
        }
    }

    private func isValidUrl(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}

#Preview {
    ContentView(animateEntrance: .constant(true))
        .environmentObject(NotificationManager.shared)
}

