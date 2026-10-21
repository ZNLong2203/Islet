import EventKit
import SwiftUI

@Observable @MainActor
final class CalendarService {
    struct Item: Identifiable {
        let id: String
        let title: String
        let start: Date
        let isAllDay: Bool
        let color: Color
    }

    private(set) var events: [Item] = []
    private(set) var isAuthorized = false

    /// Created only once calendar access exists: an event store holds a daemon connection and caches.
    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    func start() {
        isAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        if isAuthorized { connect() }
    }

    /// Only call from inside the .app bundle: the TCC prompt needs NSCalendarsFullAccessUsageDescription.
    func requestAccess() {
        let store = self.store ?? EKEventStore()
        self.store = store
        Task {
            isAuthorized = (try? await store.requestFullAccessToEvents()) ?? false
            if isAuthorized { connect() }
        }
    }

    private func connect() {
        let store = self.store ?? EKEventStore()
        self.store = store
        if changeObserver == nil {
            changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store,
                                                                    queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
        reload()
    }

    func reload() {
        guard isAuthorized, let store else { events = []; return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now)) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(3)
            .map { Item(id: $0.eventIdentifier ?? UUID().uuidString,
                        title: $0.title ?? "",
                        start: $0.startDate,
                        isAllDay: $0.isAllDay,
                        color: Color(cgColor: $0.calendar.cgColor)) }
    }
}
