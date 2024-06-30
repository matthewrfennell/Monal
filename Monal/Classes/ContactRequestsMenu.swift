//
//  ContactRequestsMenu.swift
//  Monal
//
//  Created by Jan on 27.10.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

struct ContactRequestsMenuEntry: View {
    let contact : MLContact
    let doDelete: () -> ()
    @State private var isDeleted = false
    
    private func delete() {
        if(isDeleted == false) {
            isDeleted = true
            doDelete()
        }
    }

    var body: some View {
        HStack {
            Text(contact.contactJid)
            Spacer()
            Group {
                Button {
                    let appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
                    appDelegate.openChat(of:contact)
                } label: {
                    Image(systemName: "text.bubble")
                        .accentColor(.black)
                }
                //see https://www.hackingwithswift.com/forums/swiftui/tap-button-in-hstack-activates-all-button-actions-ios-14-swiftui-2/2952
                .buttonStyle(BorderlessButtonStyle())
                
                Button {
                    // deny request
                    self.delete()       //update ui first because the array index can change afterwards
                    MLXMPPManager.sharedInstance().remove(contact)
                } label: {
                    Image(systemName: "trash.circle")
                        .accentColor(.red)
                }
                //see https://www.hackingwithswift.com/forums/swiftui/tap-button-in-hstack-activates-all-button-actions-ios-14-swiftui-2/2952
                .buttonStyle(BorderlessButtonStyle())
                
                Button {
                    // accept request
                    self.delete()       //update ui first because the array index can change afterwards
                    MLXMPPManager.sharedInstance().add(contact)
                    let appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
                    appDelegate.openChat(of:contact)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .accentColor(.green)
                }
                //see https://www.hackingwithswift.com/forums/swiftui/tap-button-in-hstack-activates-all-button-actions-ios-14-swiftui-2/2952
                .buttonStyle(BorderlessButtonStyle())
            }
            .font(.largeTitle)
        }
    }
}

struct ContactRequestsMenu: View {
    @State private var pendingRequests: [MLContact]

    var body: some View {
        Form {
            List {
                Section(header: Text("Allowing someone to add you as a contact lets them see your profile picture and when you are online.")) {
                    if(pendingRequests.isEmpty) {
                        Text("No pending requests")
                            .foregroundColor(.secondary)
                    }
                    ForEach(pendingRequests.indices, id: \.self) { idx in
                        ContactRequestsMenuEntry(
                            contact: pendingRequests[idx],
                            doDelete: {
                                self.pendingRequests.remove(at: idx)
                            }
                        )
                    }
                }
            }
        }
        .navigationBarTitle(Text("Contact Requests"), displayMode: .inline)
        .navigationViewStyle(.stack)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalContactRefresh")).receive(on: RunLoop.main)) { notification in
            self.pendingRequests = DataLayer.sharedInstance().allContactRequests() as! [MLContact]
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalContactRemoved")).receive(on: RunLoop.main)) { notification in
            self.pendingRequests = DataLayer.sharedInstance().allContactRequests() as! [MLContact]
        }
    }

    init() {
        self.pendingRequests = DataLayer.sharedInstance().allContactRequests() as! [MLContact]
    }
}

struct ContactRequestsMenu_Previews: PreviewProvider {
    static var previews: some View {
        ContactRequestsMenu()
    }
}
