import SwiftUI
import Foundation

struct WelcomeView: View {
    @EnvironmentObject var m: AppModel
    @State private var url = API.base
    @State private var token = ""

    private var backendLine: String {
        guard let live = m.plaidLive else { return "Backend not reachable yet" }
        return live ? "Backend connected, Plaid live" : "Backend connected, using sample bank data"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("ShockProof").font(rounded(20, .bold)).foregroundStyle(Theme.violet)
            Text("What if next month goes wrong?").font(rounded(44))
            Text("Link your bank. We find your paychecks, bills and habits on our own, then replay your money through thousands of possible futures.")
                .font(.title3)
            Spacer()
            if m.busy {
                HStack(spacing: 12) { ProgressView(); Text(m.status).font(.subheadline.weight(.semibold)) }
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                if m.plaidLive == true {
                    TextField("Plaid sandbox public_token", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .inputBox()
                }
                Button { API.base = url; Task { await m.connect(publicToken: token) } } label: { Text("Link bank account") }
                    .buttonStyle(StickerButton())
            }
            if let e = m.error { Text(e).font(.footnote).foregroundStyle(Theme.coral) }
            DisclosureGroup("Backend") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("http://127.0.0.1:8000", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .inputBox()
                        .onSubmit { API.base = url; Task { await m.checkHealth() } }
                    Text(backendLine).font(.footnote)
                    Text("On a real iPhone, use your Mac's local address (for example http://192.168.1.20:8000) and start uvicorn with --host 0.0.0.0.")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.7))
                }.padding(.top, 6)
            }.font(.subheadline.weight(.semibold))
        }
        .padding(24)
        .background(alignment: .topTrailing) {
            ZStack {
                Circle().fill(Theme.sun).frame(width: 180)
                Circle().fill(Theme.coral).frame(width: 90).offset(x: -90, y: 100)
            }.offset(x: 60, y: -20)
        }
        .screen()
        .task { await m.checkHealth() }
    }
}
