import SwiftUI

/// Sign In form rows for an Archie account — the same accounts as
/// app.archie.now. Embeds in a Form section (Settings) or in
/// `ArchieAccountSheet` (Archie AI tab). Accounts are created on the web;
/// the app itself is sign-in only.
struct ArchieAccountForm: View {
    @AppStorage(AppSettings.archieBaseURLKey) private var archieBaseURL = ""

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorText: String?

    /// Called with the signed-in email after a successful sign-in.
    var onAuthenticated: (String) -> Void

    var body: some View {
        TextField("Email", text: $email)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .textContentType(.username)

        SecureField("Password", text: $password)
            .textContentType(.password)

        Button {
            submit()
        } label: {
            if isWorking {
                HStack {
                    ProgressView()
                    Text("Signing in…")
                }
            } else {
                Text("Sign In")
            }
        }
        .disabled(isWorking || !inputLooksComplete)

        if let errorText {
            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }

        Text("Use your existing Archie account from app.archie.now.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var inputLooksComplete: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            errorText = "Enter a valid email address."
            return
        }

        errorText = nil
        isWorking = true
        let password = password
        Task {
            do {
                let service = ArchieBackendService(baseURL: AppSettings.archieBaseURL(from: archieBaseURL))
                try await service.signIn(email: trimmedEmail, password: password)
                isWorking = false
                onAuthenticated(trimmedEmail)
            } catch {
                errorText = error.localizedDescription
                isWorking = false
            }
        }
    }
}

/// Modal wrapper so the Archie AI tab can offer sign-in in place.
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
                    Text("One account for everything Archie — this app and app.archie.now.")
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
