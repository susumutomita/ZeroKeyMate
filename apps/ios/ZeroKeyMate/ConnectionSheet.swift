import SwiftUI

struct ConnectionSheet:View {
    @ObservedObject var model:CompanionModel
    @State private var value:AppConfiguration
    init(model:CompanionModel) {
        self.model=model
        _value=State(initialValue:model.configuration)
    }
    var body:some View {
        Form {
            Section("Execution service") {
                TextField("HTTPS API URL",text:$value.apiURL).keyboardType(.URL)
                SecureField("Installation pairing token",text:$value.apiToken)
                Text("Use the token from your private .env file. An iPhone needs an HTTPS endpoint reachable from the phone; Simulator can use localhost.").font(.footnote)
            }
            Section("Settlement") {
                Picker("Test network",selection:$value.chainID) {
                    Text("Arc Testnet").tag(UInt64(5_042_002))
                    Text("Sepolia testnet").tag(UInt64(11_155_111))
                }.onChange(of:value.chainID) {_,chain in
                    value.rpcURL=chain==5_042_002 ? "https://rpc.testnet.arc.network":"https://ethereum-sepolia-rpc.publicnode.com"
                    value.token=value.expectedToken ?? ""
                    value.vault=""
                    if chain != 11_155_111{value.ensParent=""}
                }
                TextField("HTTPS RPC URL",text:$value.rpcURL).keyboardType(.URL)
                TextField("Deployed MateVault address",text:$value.vault)
                LabeledContent("USDC",value:value.expectedToken ?? "Unsupported network").font(.caption)
                Text("The service's network, vault and token must match. Changing networks clears the vault field to avoid reusing another deployment's address.").font(.footnote)
            }
            Section("Privy app") {
                TextField("App ID",text:$value.privyAppID)
                TextField("iOS client ID",text:$value.privyClientID)
                Text("Use public app identifiers, never an app secret or wallet private key.").font(.footnote)
            }
            Section {
                Button("Check connection and save") {
                    value.token=value.expectedToken ?? ""
                    Task{await model.applyConfiguration(value)}
                }.disabled(model.financialBusy)
                if model.financialBusy{ProgressView("Checking service and network…")}
                Text("Settings stay in this device's Keychain. Saving stops camera and voice input and reconnects the wallet; it never signs a payment.").font(.footnote)
            }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .navigationTitle("Connection").navigationBarTitleDisplayMode(.inline)
        .disabled(model.financialBusy)
        .interactiveDismissDisabled(model.financialBusy)
    }
}
