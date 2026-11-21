import SwiftUI
import EventKit

@MainActor @Observable final class ReminderExport {
    private let store = EKEventStore()
    var calendars: [EKCalendar] = []
    var selectedID = ""
    var message = ""
    var busy = false

    func connect() async {
        busy = true
        defer { busy = false }
        do {
            guard try await store.requestFullAccessToReminders() else {
                throw RecipeError.message("Allow Recipe app to access Reminders in Settings, then try again.")
            }
            calendars = store.calendars(for: .reminder).filter(\.allowsContentModifications)
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            selectedID = calendars.first { ["groceries", "grocery"].contains($0.title.lowercased()) }?.calendarIdentifier
                ?? calendars.first?.calendarIdentifier ?? ""
            message = calendars.isEmpty ? "Create a list in Reminders, then try again." : ""
        } catch { message = error.localizedDescription }
    }

    func send(_ items: [String]) {
        guard let calendar = store.calendar(withIdentifier: selectedID), calendar.allowsContentModifications else {
            message = "Choose a writable Reminders list."
            return
        }
        do {
            for item in items {
                let reminder = EKReminder(eventStore: store)
                reminder.title = item
                reminder.calendar = calendar
                try store.save(reminder, commit: false)
            }
            try store.commit()
            message = "Added \(items.count) \(items.count == 1 ? "item" : "items") to \(calendar.title)."
        } catch {
            store.reset()
            message = "Could not send items: \(error.localizedDescription)"
        }
    }
}

struct GroceryView: View {
    let book: Cookbook
    @State private var reminders = ReminderExport()
    @Environment(\.dismiss) private var dismiss
    @State private var item = ""
    @State private var confirmSend = false

    private var pending: [String] { book.library.groceries.filter { !$0.done }.map(\.text) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Shopping list") {
                    HStack {
                        TextField("Add a grocery item", text: $item).onSubmit(add)
                        Button("Add", action: add).disabled(item.trimmed.isEmpty)
                    }
                    ForEach(book.library.groceries) { grocery in
                        HStack {
                            Toggle(grocery.text, isOn: Binding(get: { grocery.done }, set: { done in
                                book.update {
                                    if let index = $0.groceries.firstIndex(where: { $0.id == grocery.id }) {
                                        $0.groceries[index].done = done
                                    }
                                }
                            }))
                            .strikethrough(grocery.done)
                            Button {
                                book.update { $0.groceries.removeAll { $0.id == grocery.id } }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).accessibilityLabel("Remove \(grocery.text)")
                        }
                    }
                }
                Section("Apple Reminders") {
                    if reminders.calendars.isEmpty {
                        Button("Connect to Reminders", systemImage: "checklist") {
                            Task { await reminders.connect() }
                        }.disabled(reminders.busy)
                    } else {
                        Picker("Send to list", selection: $reminders.selectedID) {
                            ForEach(reminders.calendars, id: \.calendarIdentifier) { calendar in
                                Text("\(calendar.title) · \(calendar.source.title)").tag(calendar.calendarIdentifier)
                            }
                        }
                        Button("Send unchecked items", systemImage: "arrow.up.right") { confirmSend = true }
                            .disabled(pending.isEmpty || reminders.selectedID.isEmpty)
                    }
                    if !pending.isEmpty { ShareLink(item: pending.joined(separator: "\n")) { Label("Share grocery list", systemImage: "square.and.arrow.up") } }
                    if reminders.busy { ProgressView() }
                    if !reminders.message.isEmpty { Text(reminders.message).foregroundStyle(.secondary) }
                }
            }
            .formStyle(.grouped)
            .appSurface()
            .navigationTitle("Groceries")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Send \(pending.count) items to Reminders?", isPresented: $confirmSend, titleVisibility: .visible) {
                Button("Send items") { reminders.send(pending) }
            } message: { Text("Each export adds the current unchecked items to the selected list.") }
        }
    }

    private func add() {
        guard !item.trimmed.isEmpty else { return }
        book.add([item.trimmed])
        if book.error == nil { item = "" }
    }
}
