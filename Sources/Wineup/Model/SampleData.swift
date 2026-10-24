import WineupCore
import Foundation

/// Dados fictícios só para preencher a interface.
enum SampleData {
    private static let rows: [(String, String, Int, MarkColor?)] = [
        ("Steel Pulse", "Tightrope", 244, nil),
        ("Steel Pulse", "Roller Skates (Dub)", 263, nil),
        ("The Fugees", "No Woman No Cry", 326, .purple),
        ("Ритм-У", "Наше Небо", 336, nil),
        ("Snoop Dogg", "Doggy Dogg World", 338, nil),
        ("175 Funky Illness", "This Is For Real", 242, .blue),
        ("2Pac", "All Eyez On Me", 342, .yellow),
        ("DJ Cut Killer", "We Want Cut", 399, .purple),
        ("Battlecat", "Swerve On", 243, nil),
        ("Beanie Sigel", "Remember Them", 303, nil),
        ("Big Unc", "Westside G Style", 304, nil),
        ("Black 9", "I'm An O.G.", 222, .yellow),
        ("Boogie", "Shocked", 292, .yellow),
        ("Cool Nutz", "Punk Ass", 227, nil),
        ("Daz Dillinger", "Only For U", 347, .purple),
        ("Dr. Alban", "No Coke (7'' Mix)", 214, nil),
        ("Dr. Alban", "This Time I'm Free", 233, .purple),
        ("Everything But The Girl", "Missing (Todd Terry Remix)", 233, nil),
        ("Fr David", "Girl", 218, nil),
        ("Foreigner", "Urgent (1977)", 270, nil),
        ("Gala", "Let A Boy Cry (Edit Mix)", 203, nil),
        ("Gary Moore", "Still Got The Blues", 250, .purple),
        ("George Michael", "Careless Whisper", 301, .purple),
        ("Haddaway", "What Is Love", 233, nil),
        ("Kris Kross", "I Missed The Bus", 214, nil),
        ("Novika", "Miss Mood (Satin Jackets Remix)", 261, nil),
        ("The Police", "Every Breath You Take", 253, .purple),
        ("Toto", "I Won't Hold You Back", 293, nil),
        ("UB40", "Kingston Town", 227, .purple),
        ("William Pitt", "City Lights Normalize", 227, .purple),
        ("Scorpions", "You And I", 368, .purple),
        ("Snap", "Don't Be Shy", 277, nil),
    ]

    static let tracks: [Track] = rows.map { row in
        Track(artist: row.0, title: row.1, duration: row.2, mark: row.3)
    }

    static let lyrics: [String] = [
        "Primeira linha da letra",
        "A letra sincronizada aparece aqui",
        "Cada linha acende na hora certa",
        "E a anterior fica mais discreta",
        "Aqui é só um exemplo de interface",
        "Nada disso está tocando de verdade",
        "Troque o tamanho com os botões A",
        "Letras de verdade virão do .lrc",
    ]

    /// Curva "Custom" de exemplo que as primeiras versões usavam como EQ inicial.
    static let legacyCustomCurve: [Double] = [-6, 5, 3, -3, 4, -3, -1, 2, 6, 5]

}
