import SwiftUI

/// Sign In / Create Account form rows for an Archie account — the same
/// accounts as app.archie.now. Embeds in a Form section (Settings) or in
/// `ArchieAccountSheet` (Archie AI tab).
struct ArchieAccountForm: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case create = "Create Account"
        var id: String { rawValue }
    }

    @AppStorage(AppSettings.archieBaseURLKey) private var archieBaseURL = ""

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorText: String?

    /// Called with the signed-in email after a successful sign-in or signup.
    var onAuthenticated: (String) -> Void

    var body: some View {
        Picker("Mode", selection: $mode) {
            ForEach(Mode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(isWorking)

        if mode == .create {
            TextField("Your name", text: $name)
                .textContentType(.name)
        }

        TextField("Email", text: $email)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .textContentType(.username)

        SecureField("Password", text: $password)
            .textContentType(mode == .create ? .newPassword : .password)

        if mode == .create {
            Text("At least 8 characters, with an uppercase letter, a lowercase letter, and a number.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        Button {
            submit()
        } label: {
            if isWorking {
                HStack {
                    ProgressView()
                    Text(mode == .signIn ? "Signing in…" : "Creating account…")
                }
            } else {
                Text(mode.rawValue)
            }
        }
        .disabled(isWorking || !inputLooksComplete)

        if let errorText {
            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }

        Link(destination: URL(string: "https://app.archie.now/")!) {
            Label("Archie on the web (app.archie.now)", systemImage: "arrow.up.right.square")
        }
    }

    private var inputLooksComplete: Bool {
        let hasCredentials = !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        guard mode == .create else { return hasCredentials }
        return hasCredentials && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Mirrors the server's validation so most mistakes get instant feedback;
    /// the server remains authoritative.
    private func validateForSignup() -> String? {
        if name.trimmingCharacters(in: .whitespaces).count < 2 {
            return "Name must be at least 2 characters."
        }
        if password.count < 8 {
            return "Password must be at least 8 characters."
        }
        if password.rangeOfCharacter(from: .uppercaseLetters) == nil {
            return "Password must contain at least one uppercase letter."
        }
        if password.rangeOfCharacter(from: .lowercaseLetters) == nil {
            return "Password must contain at least one lowercase letter."
        }
        if password.rangeOfCharacter(from: .decimalDigits) == nil {
            return "Password must contain at least one number."
        }
        return nil
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            errorText = "Enter a valid email address."
            return
        }
        if mode == .create, let problem = validateForSignup() {
            errorText = problem
            return
        }

        errorText = nil
        isWorking = true
        let password = password
        let mode = mode
        Task {
            do {
                let service = ArchieBackendService(baseURL: AppSettings.archieBaseURL(from: archieBaseURL))
                switch mode {
                case .signIn:
                    try await service.signIn(email: trimmedEmail, password: password)
                case .create:
                    try await service.signUp(name: trimmedName, email: trimmedEmail, password: password)
                }
                isWorking = false
                onAuthenticated(trimmedEmail)
            } catch {
                errorText = error.localizedDescription
                isWorking = false
            }
        }
    }
}

/// Modal wrapper so the Archie AI tab can offer sign-in/signup in place.
struct ArchieAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAuthenticated: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ArchieAccountForm { email in
                        onAuthenticated(email)
                        dismiss()
                    }
                } header: {
                    Text("Archie Account")
                } footer: {
                    Text("One account for everything Archie — this app and app.archie.now. New accounts are free.")
                }
            }
            .navigationTitle("Sign in to Archie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
