import SwiftUI

struct BreezeIllustration: View {
    enum Artwork: String {
        case emptyACList = "EmptyACListIllustration"
        case acUnavailable = "ACUnavailableIllustration"
        case xiaomiToken = "XiaomiTokenIllustration"
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let artwork: Artwork

    var body: some View {
        Image(decorative: artwork.rawValue)
            .resizable()
            .scaledToFit()
            .frame(width: width)
    }

    private var width: CGFloat {
        if artwork == .xiaomiToken { return 92 }
        return dynamicTypeSize.isAccessibilitySize ? 100 : 144
    }
}
