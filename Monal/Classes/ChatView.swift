//
//  ChatView.swift
//  Monal
//
//  Created by Thilo Molitor on 05.09.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import FrameUp
import ExyteChat
typealias ExyteChatView = ExyteChat.ChatView


/*
struct MonalViewDefaults: ViewModifier {
    @Binding public var alertPrompt: AlertPrompt?
    
    public func body(content: Content) -> some View {
        content
            //TODO: modernize alert prompt usage in all other swiftui files to be in line with this implementation here
            //TODO: e.g. non-hardcoded dismiss button text and usage of optionalMappedToBool and dismissCallback
            .alert(isPresented: $alertPrompt.optionalMappedToBool()) {
                let callback = alertPrompt!.dismissCallback
                return Alert(title: alertPrompt!.title, message: alertPrompt!.message, dismissButton:.default(alertPrompt!.dismissLabel, action: {
                    if let callback = callback {
                        callback()
                    }
                }))
            }
    }
}

private struct AssociatedMonalViewKeys {
    static var AlertPromptKey = "ml_alertPromptKey"
}

extension View {
    func addMonalViewDefaults() -> some View {
        //see https://medium.com/@marcosantadev/stored-properties-in-swift-extensions-615d4c5a9a58
        modifier(MonalViewDefaults(alertPrompt:Binding(
            get: {
                print("Getter called...")
                return AlertPrompt(
                    title: Text("No OMEMO keys found"),
                    message: Text("This contact may not support OMEMO encrypted messages. Please try to enable encryption again in a few seconds, if you think this is wrong."),
                    dismissLabel: Text("Disable Encryption")
                )
//                 guard let value = objc_getAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey) as? AlertPrompt else {
//                     return nil
//                 }
//                 return value
            },
            set: {
                print("Setting: \(String(describing:$0))")
                if let value = $0 {
                    objc_setAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey, value, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                } else {
                    objc_setAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey, nil, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
            }
        )))
    }
}

protocol MonalView: View {
    associatedtype Content: View
    @ViewBuilder var content: Self.Content { get }
}

extension MonalView {
    var body: some View {
        content
            .addMonalViewDefaults()
    }
    
    func showAlert(_ prompt: AlertPrompt) {
        objc_setAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey, prompt, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        content.id(UUID())
    }
}
*/


struct ChatView: View {
    @Environment(\.presentationMode) private var presentationMode
    
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    @State private var selectedContactForContactDetails: ObservableKVOWrapper<MLContact>?
    @State private var alertPrompt: AlertPrompt?
    @State private var confirmationPrompt: ConfirmationPrompt?
    @StateObject private var overlay = LoadingOverlayState()
    @State var messages: [ChatViewMessage] = []
    private var account: xmpp
    
    init(contact: ObservableKVOWrapper<MLContact>) {
        _contact = StateObject(wrappedValue: contact)
        account = contact.obj.account!
    }
    
    private func showCannotEncryptAlert(_ show: Bool) {
        if show {
            DDLogVerbose("Showing cannot encrypt alert...")
            alertPrompt = AlertPrompt(
                title: Text("Encryption Not Supported"),
                message: Text("This contact does not appear to have any devices that support encryption, please try again later if you think this is wrong."),
                dismissLabel: Text("Close")
            )
        } else {
            alertPrompt = nil
        }
    }
    
    private func showShouldDisableEncryptionConfirmation(_ show: Bool) {
        if show {
            DDLogVerbose("Showing should disable encryption confirmation...")
            confirmationPrompt = ConfirmationPrompt(
                title: Text("Disable encryption?"),
                message: Text("Do you really want to disable encryption for this contact?"),
                buttons: [
                    .cancel(
                        Text("No, keep encryption activated"),
                        action: { }
                    ),
                    .destructive(
                        Text("Yes, deactivate encryption"),
                        action: {
                            showCannotEncryptAlert(!contact.obj.toggleEncryption(!contact.isEncrypted))
                        }
                    )
                ]
            )
        } else {
            confirmationPrompt = nil
        }
    }
    
    private func checkOmemoSupport(withAlert showWarning: Bool) {
#if !DISABLE_OMEMO
    if MLDataLayer.sharedInstance().isAccountEnabled(contact.accountID) {
        var omemoDeviceForContactFound = false
        if !contact.isMuc {
            omemoDeviceForContactFound = account.omemo.knownDevices(forAddressName:contact.contactJid).count > 0
        } else {
            omemoDeviceForContactFound = false
            for participant in MLDataLayer.sharedInstance().getMembersAndParticipants(ofMuc:contact.contactJid, forAccountID:contact.accountID) {
                if let participant_jid = participant["participant_jid"] as? String {
                    omemoDeviceForContactFound = omemoDeviceForContactFound || account.omemo.knownDevices(forAddressName:participant_jid).count > 0
                } else if let participant_jid = participant["member_jid"] as? String {
                    omemoDeviceForContactFound = omemoDeviceForContactFound || account.omemo.knownDevices(forAddressName:participant_jid).count > 0
                }
                if omemoDeviceForContactFound {
                    break
                }
            }
        }
        if !omemoDeviceForContactFound && contact.isEncrypted {
            if HelperTools.isContactBlacklistedForEncryption(contact.obj) {
                // this contact was blacklisted for encryption
                // --> disable it
                contact.isEncrypted = false
                MLDataLayer.sharedInstance().disableEncrypt(forJid:contact.contactJid, andAccountID:contact.accountID)
            } else if contact.isMuc && contact.mucType != kMucTypeGroup {
                // a channel type muc has OMEMO encryption enabled, but channels don't support encryption
                // --> disable it
                contact.isEncrypted = false
                MLDataLayer.sharedInstance().disableEncrypt(forJid:contact.contactJid, andAccountID:contact.accountID)
            } else if !contact.isMuc || (contact.isMuc && contact.mucType == kMucTypeGroup) {
                hideLoadingOverlay(overlay)
                
                if showWarning {
                    DDLogWarn("Showing omemo not supported alert for: \(self.contact)")
                    alertPrompt = AlertPrompt(
                        title: Text("No OMEMO keys found"),
                        message: Text("This contact may not support OMEMO encrypted messages. Please try to enable encryption again in a few seconds, if you think this is wrong."),
                        dismissLabel: Text("Disable Encryption")
                    ) {
                        contact.isEncrypted = false
                        MLDataLayer.sharedInstance().disableEncrypt(forJid:contact.contactJid, andAccountID:contact.accountID)
                    }
                } else {
                    DDLogInfo("Trying to fetch omemo keys for: \(self.contact)")
                    
                    // we won't do this twice, because the user won't be able to change isEncrypted to YES,
                    // unless we have omemo devices for that contact
                    showPromisingLoadingOverlay(overlay, headlineView:Text("Loading OMEMO keys"), descriptionView:Text("")).done {
                        // request omemo devicelist
                        account.omemo.subscribeAndFetchDevicelistIfNoSessionExists(forJid:contact.contactJid)
                    }
                }
            }
        } else {
            hideLoadingOverlay(overlay)
        }
    }
#endif
}
    
    var body: some View {
        ExyteChatView(messages: messages, chatType: .conversation, replyMode: .quote) { draft in
            print("sending draft: \(String(describing:draft))")
        } messageBuilder: { message, positionInUserGroup, positionInCommentsGroup, showContextMenuClosure, messageActionClosure, showAttachmentClosure in
            MessageView(message: ObservableKVOWrapper((message as! ChatViewMessage).message))
        }
//         .enableLoadMore(pageSize: 3) { message in
//             print("load more messages before: \(String(describing:message))")
//         }
//         .messageUseMarkdown(messageUseMarkdown: true)
        .sheet(item: $selectedContactForContactDetails) { selectedContact in
            AnyView(AddTopLevelNavigation(withDelegate:nil, to:ContactDetails(delegate:nil, contact:selectedContact)))
        }
        //TODO: modernize action sheet usage in all other swiftui files to be in line with this implementation here
        //TODO: e.g. same usage like alert prompt below
        .actionSheet(isPresented: $confirmationPrompt.optionalMappedToBool()) {
            ActionSheet(title: confirmationPrompt!.title, message: confirmationPrompt!.message, buttons: confirmationPrompt!.buttons)
        }
        //TODO: modernize alert prompt usage in all other swiftui files to be in line with this implementation here
        //TODO: e.g. non-hardcoded dismiss button text and usage of optionalMappedToBool and dismissCallback
        //somehow the order of alert modifiers is important: they have to come after all sheet modifiers
        .alert(isPresented: $alertPrompt.optionalMappedToBool()) {
            let callback = alertPrompt!.dismissCallback
            return Alert(title: alertPrompt!.title, message: alertPrompt!.message, dismissButton:.default(alertPrompt!.dismissLabel, action: {
                if let callback = callback {
                    callback()
                }
            }))
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                //make sure to take all space available, otherwise we'll get aligned to the center
                //of the navigation bar instead of the leading edge
                ZStack {
                    Color.clear
                    
                    HStack {
                        Button {
                            selectedContactForContactDetails = contact
                        } label: {
                            HStack {
                                Image(uiImage: contact.avatar)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 35, height: 35)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 0) {
                                    Text(contact.contactDisplayName as String)
                                        .fontWeight(.semibold)
                                        .font(.headline)
                                        .foregroundColor(.black)
                                    
                                    if (contact.isTyping as Bool) {
                                        Text("Typing...")
                                            .font(.footnote)
                                            .foregroundColor(Color(hex: "AFB3B8"))
                                    } else if let lastInteractionDate:Date = contact.lastInteractionTime {
                                        Text(HelperTools.formatLastInteraction(lastInteractionDate))
                                            .font(.footnote)
                                            .foregroundColor(Color(hex: "AFB3B8"))
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                }
            }
            
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !(contact.isMuc || contact.isSelfChat) {
                    let activeChats = (UIApplication.shared.delegate as! MonalAppDelegate).activeChats!
                    let voipProcessor = (UIApplication.shared.delegate as! MonalAppDelegate).voipProcessor!
                    Button {
                        if let activeCall = voipProcessor.getActiveCall(with:contact.obj) {
                            if !MLDataLayer.sharedInstance().checkCap("urn:xmpp:jingle-message:0", forUser:contact.contactJid, onAccountID:contact.accountID) {
                                confirmationPrompt = ConfirmationPrompt(
                                    title: Text("Missing Call Support"),
                                    message: Text("Your contact may not support calls. Your call might never reach its destination."),
                                    buttons: [
                                        .default(
                                            Text("Try nevertheless"),
                                            action: {
                                                activeChats.call(contact.obj, withUIKitSender:nil)
                                            }
                                        ),
                                        .cancel(
                                            Text("Cancel"),
                                            action: { }
                                        )
                                    ]
                                )
                            }
                        } else {
                                activeChats.call(contact.obj, withUIKitSender:nil)
                        }
                    } label: {
                        if let activeCall = voipProcessor.getActiveCall(with:contact.obj) {
                            Image(systemName: "phone.connection.fill")
                        } else {
                            Image(systemName: "phone.fill")
                        }
                    }
                }
                
                Button {
                    guard !HelperTools.isContactBlacklistedForEncryption(contact.obj) else {
                        return
                    }
                    if contact.isEncrypted {
                        DDLogVerbose("Showing should disable encryption confirmation...")
                        showShouldDisableEncryptionConfirmation(true)
                    } else {
                        showCannotEncryptAlert(!contact.obj.toggleEncryption(!contact.isEncrypted))
                    }
                } label: {
                    if contact.isEncrypted {
                        Label {
                            Text("Messages are encrypted")
                        } icon: {
                            Image(systemName: "lock.fill")
                        }
                    } else {
                        Label {
                            Text("Messages are NOT encrypted")
                        } icon: {
                            Image(systemName: "lock.open.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
                .disabled(
                    //disable encryption button on unsupported muc types
                    (contact.isMuc && contact.mucType != kMucTypeGroup) ||
                    //disable encryption button for special jids
                    HelperTools.isContactBlacklistedForEncryption(contact.obj)
                )
            }
        }
        .toolbarRole(.editor)       //make sure to never show the title of the previous view in the back bar button
        .addLoadingOverlay(overlay)
        .onAppear {
            checkOmemoSupport(withAlert:false)
            
            //TODO: load messages from db
            let dbMessages = MLDataLayer.sharedInstance().messages(forContact:contact.contactJid, forAccount:contact.accountID) as! [MLMessage]
            for msg in dbMessages {
                messages.append(ChatViewMessage(msg))
            }
//             messages = [
//                 ExyteChat.Message(
//                     id: "123",
//                     user: ChatViewUser(contact),
//                     status: .sent,
//                     createdAt: Date(),
//                     text: "Dummy message no. one",
//                     attachments: [],
//                     recording: nil,
//                     replyMessage: nil
//                 ),
//                 ExyteChat.Message(
//                     id: "456",
//                     user: ChatViewUser(contact),
//                     status: .sent,
//                     createdAt: Date(),
//                     text: "Yes, that's really cool :)",
//                     attachments: [],
//                     recording: nil,
//                     replyMessage: nil
//                 )
//             ]
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalOmemoFetchingStateUpdate")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let notificationJid = notification.userInfo?["jid"] as? String {
                if xmppAccount.accountID == contact.accountID && notificationJid == contact.contactJid {
                    DDLogDebug("Got omemo fetching update: \(contact) --> \(String(describing:notification.userInfo))")
                    if let _ = (notification.userInfo?["isFetching"] as? Bool) {
                        //recheck support and show alert if needed
                        DDLogVerbose("Rechecking omemo support with alert, if needed...")
                        checkOmemoSupport(withAlert:true)
                    }
                }
            }
        }
    }
}

struct MessageView: View {
    @StateObject var message: ObservableKVOWrapper<MLMessage>
    
    var body: some View {
        let radius = 12.0
        VStack(alignment: .leading, spacing: 0) {
            Text(message.messageText as String)
                .foregroundColor(.black)
                .background {
                    RoundedRectangle(cornerRadius: radius)
                        .foregroundColor(.blue)
                        //.opacity(isReply ? 0.5 : 1)
                }
                .cornerRadius(radius)
        }
    }
}

class ChatViewMessage: ExyteChat.Message {
    @Published public var message: MLMessage
    
    init(_ message: MLMessage) {
        self.message = message
        super.init(id: message.id, user: ExyteChat.User(id: message.contact.id, name: "", avatarURL: nil, isCurrentUser: false))
    }
}

// class ChatViewUser: ExyteChat.User {
//     private enum CodingKeys: CodingKey {
//         case contact
//     }
// 
// //     @Published public var id: String
// //     @Published public var name: String
// //     @Published public var isCurrentUser: Bool
//     
//     @Published public var contact: MLContact
//     
//     init(_ contact: MLContact) {
//         super.init(id: contact.id, name: "", avatarURL: nil, isCurrentUser: false)
//         self.contact = contact
//         //contact.$contactDisplayName.sink { print($0 as String) }
//     }
//     
//     required public init(from decoder: Decoder) throws {
//         //let container = try decoder.container(keyedBy: CodingKeys.self)
//         //contact = try container.decode(String.self, forKey: .contact)
//         try super.init(from: decoder)
//     }
//     
// //     public func encode(to encoder: Encoder) throws {
// //         var container = encoder.container(keyedBy: CodingKeys.self)
// //         try container.encode(contact, forKey: .contact)
// //         try super.encode(to: encoder)
// //     }
// }

/*
public extension ExyteChat.MessageView {
    @ViewBuilder
    override public var avatarView: some View {
        Group {
            if showAvatar, let image = (message.user as! ChatViewUser).image {
                image
                    .resizable()
                    .scaledToFill()
                    .contentShape(Circle())
                    .onTapGesture {
                        tapAvatarClosure?(message.user, message.id)
                    }
            } else {
                Color.clear.viewSize(avatarSize)
            }
        }
        .padding(.horizontal, ExyteChat.MessageView.horizontalAvatarPadding)
//         .onSizeChange { size in
//             self.avatarViewSize = size
//         }
    }
}*/
