//
//  ChangePassword.swift
//  Monal
//
//  Created by lissine on 2/8/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

struct ChangePassword: View {
    @Environment(\.presentationMode) var presentationMode

    @State private var oldPass = ""
    @State private var newPass = ""

    @State private var showAlert = false
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))

    @StateObject private var overlay = LoadingOverlayState()

    let accountID: NSNumber

    private func errorAlert(title: Text, message: Text = Text("")) {
        alertPrompt.title = title
        alertPrompt.message = message
        showAlert = true
        alertPrompt.dismissCallback = nil
    }
    private func successAlert(title: Text, message: Text) {
        alertPrompt.title = title
        alertPrompt.message = message
        showAlert = true
        alertPrompt.dismissCallback = {
            self.presentationMode.wrappedValue.dismiss()
        }
    }
    private func passwordChangeProcessing() {
        guard let account = MLXMPPManager.sharedInstance().getEnabledAccount(forID: accountID) else {
            errorAlert(
                title: Text("Account Offline"),
                message: Text("Please make sure you are connected before changing your password.")
            )
            return
        }

        guard MLXMPPManager.sharedInstance().isValidPassword(oldPass, forAccount: accountID) else {
            errorAlert(
                title: Text("Wrong Password!"),
                message: Text("The current password is not correct.")
            )
            return
        }

        showPromisingLoadingOverlay(overlay, headlineView: Text("Changing Password"), descriptionView: Text("")) {
            account.changePassword(newPass)
        }
        .done { _ in
            successAlert(title: Text("Success"), message: Text("The password has been changed"))
        }
        .catch { error in
            errorAlert(title: Text("Error"), message: Text(error.localizedDescription))
        }

    }

    var body: some View {
        Form {
            Section(header: Text("Enter your new password. Passwords may not be empty. They may also be governed by server or company policies.")) {
                SecureField("Current Password", text: $oldPass)
#if IS_QUICKSY
                    .onAppear {
                        oldPass = MLXMPPManager.sharedInstance().getPasswordForAccount(accountID)
                    }
#endif
                SecureField("New Password", text: $newPass)
            }

            Section {
                Button(action: passwordChangeProcessing) {
                    Text("Change Password")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(oldPass.isEmpty || newPass.isEmpty)
            }

        }
        .alert(
            alertPrompt.title,
            isPresented: $showAlert,
            actions: { Button("Close", action: alertPrompt.dismissCallback ?? {}) },
            message: { alertPrompt.message }
        )
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
        .addLoadingOverlay(overlay)
    }
}
