import SwiftUI
import GongCore

@Observable
final class SettingsViewModel {
    var urlText: String
    var statusText: String = ""
    var isTesting = false
    let test: (String) async -> Result<Int, Error>
    let save: (String) -> Void
    var onSaved: () -> Void = {}

    init(initialURL: String?, test: @escaping (String) async -> Result<Int, Error>, save: @escaping (String) -> Void) {
        self.urlText = initialURL ?? ""
        self.test = test
        self.save = save
    }

    var trimmed: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var looksValid: Bool { trimmed.hasPrefix("https://") && trimmed.contains("calendar.google.com") }

    func runTest() {
        guard looksValid else { statusText = L("That does not look like a Google Calendar iCal URL (it must start with https://calendar.google.com)."); return }
        isTesting = true
        statusText = L("Fetching…")
        Task { @MainActor in
            let result = await test(trimmed)
            isTesting = false
            switch result {
            case .success(let n): statusText = n == 1 ? L("1 meeting found for the next 48 hours.") : L("%d meetings found for the next 48 hours.", n)
            case .failure(let e): statusText = L("Failed: %@", e.localizedDescription)
            }
        }
    }

    func runSave() {
        guard looksValid else { statusText = L("URL not saved: invalid."); return }
        save(trimmed)
        statusText = L("Saved in the Keychain.")
        onSaved()
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Secret iCal URL of your Google Calendar")).font(.headline)
            Text(L("Google Calendar → Settings → your calendar → Integrate calendar → \"Secret address in iCal format\"."))
                .font(.caption).foregroundStyle(.secondary)
            TextField("https://calendar.google.com/calendar/ical/…/basic.ics", text: $model.urlText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(L("Test")) { model.runTest() }.disabled(model.isTesting)
                Button(L("Save")) { model.runSave() }.keyboardShortcut(.defaultAction).disabled(!model.looksValid)
                Spacer()
                if model.isTesting { ProgressView().controlSize(.small) }
            }
            Text(model.statusText).font(.callout).frame(minHeight: 20, alignment: .leading)
        }
        .padding(20)
        .frame(width: 520)
    }
}
