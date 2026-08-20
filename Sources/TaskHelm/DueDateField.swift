import SwiftUI

struct DueDateField: View {
    @Binding private var due: String
    @State private var calendarDate: Date
    @State private var isCalendarPresented = false

    private let textFieldWidth: CGFloat?
    private let onSubmit: (() -> Void)?

    init(
        due: Binding<String>,
        textFieldWidth: CGFloat? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        _due = due
        _calendarDate = State(initialValue: Self.parse(due.wrappedValue) ?? Date())
        self.textFieldWidth = textFieldWidth
        self.onSubmit = onSubmit
    }

    var body: some View {
        HStack(spacing: 3) {
            TextField("Due", text: $due)
                .frame(width: textFieldWidth)
                .onSubmit { onSubmit?() }

            Button("Today", action: selectToday)
                .controlSize(.small)

            Button {
                calendarDate = Self.parse(due) ?? Calendar.current.startOfDay(for: Date())
                isCalendarPresented = true
            } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(.borderless)
            .help(due.isEmpty ? "Choose a due date" : "Change the due date")
            .accessibilityLabel(due.isEmpty ? "Choose Due Date" : "Change Due Date")
            .popover(isPresented: $isCalendarPresented, arrowEdge: .bottom) {
                calendarPopover
            }

            if !due.isEmpty {
                Button {
                    due = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear the due date")
                .accessibilityLabel("Clear Due Date")
            }
        }
        .onChange(of: due) { _, newValue in
            guard let date = Self.parse(newValue),
                  !Calendar.current.isDate(date, inSameDayAs: calendarDate) else { return }
            calendarDate = date
        }
    }

    private var calendarPopover: some View {
        VStack(spacing: 10) {
            DatePicker("Due date", selection: $calendarDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .onChange(of: calendarDate) { _, newValue in
                    due = Self.formatted(newValue)
                }

            HStack {
                Button("Clear") {
                    due = ""
                    isCalendarPresented = false
                }
                Spacer()
                Button("Today", action: selectToday)
                Button("Done") {
                    isCalendarPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func selectToday() {
        calendarDate = Calendar.current.startOfDay(for: Date())
        due = Self.formatted(calendarDate)
    }

    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func parse(_ value: String) -> Date? {
        let taskwarriorFormatter = DateFormatter()
        taskwarriorFormatter.locale = Locale(identifier: "en_US_POSIX")
        // Taskwarrior exports date-only due values as midnight UTC. Interpret the
        // components in the user's timezone so the selector keeps the same day.
        taskwarriorFormatter.timeZone = .current
        taskwarriorFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        if let date = taskwarriorFormatter.date(from: value) {
            return date
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: value)
    }
}
