import Foundation

struct SceneSymbolGroup {
    struct Symbol: Identifiable {
        let id: String
        let label: LocalizedStringResource
        let searchTerms: String
    }
    let key: String
    let symbols: [String]

    static let groups: [Self] = [
        .init(key: "Scene symbols: Headphones speakers microphone music audio", symbols: ["headphones", "headphones.circle.fill", "speaker.wave.2.fill", "speaker.fill", "speaker.slash.fill", "mic.fill", "mic.circle.fill", "music.note", "music.note.list", "music.mic", "waveform", "waveform.circle.fill", "hifispeaker.fill", "airpodspro", "ear"]),
        .init(key: "Scene symbols: Computer display keyboard phone technology", symbols: ["desktopcomputer", "laptopcomputer", "display", "keyboard.fill", "computermouse.fill", "iphone", "ipad", "applewatch", "printer.fill", "externaldrive.fill", "cpu", "network", "wifi"]),
        .init(key: "Scene symbols: Games video camera film entertainment", symbols: ["gamecontroller.fill", "dpad.fill", "dice.fill", "puzzlepiece.fill", "videoprojector.fill", "video.fill", "camera.fill", "film.fill", "tv.fill", "play.rectangle.fill"]),
        .init(key: "Scene symbols: Home office work building tools", symbols: ["house.fill", "building.2.fill", "briefcase.fill", "sofa.fill", "lamp.desk.fill", "lightbulb.fill", "wrench.and.screwdriver.fill", "hammer.fill"]),
        .init(key: "Scene symbols: Reading study writing school book", symbols: ["book.fill", "books.vertical.fill", "graduationcap.fill", "pencil", "pencil.and.outline", "doc.text.fill", "newspaper.fill"]),
        .init(key: "Scene symbols: Sleep night sun weather relaxation", symbols: ["moon.fill", "moon.stars.fill", "sun.max.fill", "cloud.fill", "cloud.rain.fill", "snowflake", "bed.double.fill", "sparkles"]),
        .init(key: "Scene symbols: Coffee food cooking dining drink", symbols: ["cup.and.saucer.fill", "mug.fill", "fork.knife", "wineglass.fill", "birthday.cake.fill", "carrot.fill"]),
        .init(key: "Scene symbols: Heart star lightning favorites shapes", symbols: ["heart.fill", "star.fill", "bolt.fill", "circle.fill", "triangle.fill", "square.fill", "hexagon.fill", "diamond.fill", "flag.fill", "gift.fill"]),
        .init(key: "Scene symbols: Nature plants leaf animals outdoors", symbols: ["leaf.fill", "tree.fill", "pawprint.fill", "bird.fill", "fish.fill", "mountain.2.fill", "tent.fill", "flame.fill", "drop.fill"]),
        .init(key: "Scene symbols: Travel car bicycle train airplane transport", symbols: ["car.fill", "bicycle", "tram.fill", "airplane", "bus.fill", "ferry.fill", "sailboat.fill", "suitcase.fill"]),
        .init(key: "Scene symbols: Sports walking running fitness exercise", symbols: ["figure.walk", "figure.run", "figure.yoga", "figure.mind.and.body", "dumbbell.fill", "sportscourt.fill", "basketball.fill", "football.fill", "tennisball.fill"]),
        .init(key: "Scene symbols: Map location world time calendar timer", symbols: ["map.fill", "location.fill", "globe", "clock.fill", "timer", "calendar", "bell.fill", "pin.fill", "compass.drawing"]),
    ]

    // Resolve once across all shipped translations, allowing searches in any supported language.
    static let index: [Symbol] = groups.flatMap { group in
        let bundles = Bundle.main.localizations.compactMap { locale in
            Bundle.main.path(forResource: locale, ofType: "lproj").flatMap(Bundle.init(path:))
        }
        let terms = ([group.key] + bundles.map {
            $0.localizedString(forKey: group.key, value: nil, table: nil)
        }).joined(separator: " ")
        return group.symbols.map {
            Symbol(id: $0, label: LocalizedStringResource(String.LocalizationValue(group.key)),
                   searchTerms: terms + " " + $0.replacingOccurrences(of: ".", with: " "))
        }
    }

    static func matching(_ query: String) -> [Symbol] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return words.isEmpty ? index : index.filter { symbol in
            words.allSatisfy { symbol.searchTerms.localizedStandardContains($0) || symbol.id.localizedStandardContains($0) }
        }
    }
}
