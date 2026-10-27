import SwiftUI

/// Apple's icon beside its name. Never inside a `Button`, `NavigationLink` or menu item: Apple
/// allows the icon only to show that Rekkert works with Apple Health, not as a control.
struct AppleHealthMark: View {
    var size: CGFloat?
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 22

    var body: some View {
        let side = size ?? lineHeight
        HStack(spacing: 6) {
            Image("AppleHealth")
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .padding(side / 10)
            Text("Apple Health")
                .textCase(nil)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple Health")
    }
}
