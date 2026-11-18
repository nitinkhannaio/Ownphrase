import Foundation

/// Persisted keys are a fixed vocabulary. Unrecognized words, names and phrases never become keys.
struct Observation {
    let context: String
    let counts: [String: Int]

    init?(_ passage: String) {
        let words = passage.lowercased().split { !$0.isLetter && $0 != "'" && $0 != "’" }
        guard words.count >= 2 else { return nil }
        let work: Set<Substring> = ["deadline", "stakeholders", "deliverable", "invoice", "meeting", "deployment", "client", "project"]
        let casual: Set<Substring> = ["lol", "haha", "hey", "gonna", "yep", "nah", "bro", "mum", "dad"]
        let uniqueWords = Set(words)
        let workCount = uniqueWords.intersection(work).count
        let casualCount = uniqueWords.intersection(casual).count
        if workCount > casualCount && workCount >= 2 { context = "Work" }
        else if casualCount > workCount && casualCount >= 2 { context = "Casual" }
        else { context = "General" }

        var features = ["passages": 1, "words": words.count]
        let contractions = ["n't", "'ll", "'ve", "'re", "'m"]
        let first = words[0]
        let opening = words.prefix(5).joined(separator: " ")
        if ["hi", "hello", "hey", "dear"].contains(first) { features["greeting"] = 1 }
        if ["why", "how", "when", "which", "what", "where", "who", "can", "did", "do", "should", "would", "could", "is", "are"].contains(first),
           passage.contains("?") { features["questionOpening"] = 1 }
        if ["could you ", "would you ", "can you ", "would it be possible", "do you mind "].contains(where: { (opening + " ").hasPrefix($0) }) {
            features["softRequest"] = 1
        } else if ["send", "share", "review", "check", "confirm", "let", "please"].contains(first) {
            features["directOpening"] = 1
        }
        let segments = passage.split(whereSeparator: { ".!?".contains($0) }).filter { $0.contains(where: \.isLetter) }
        if segments.count > 1 { features["multiSentence"] = 1 }
        else if words.count <= 10 { features["shortPassage"] = 1 }
        for word in words {
            let spelling = word.replacingOccurrences(of: "’", with: "'")
            if contractions.contains(where: { spelling.hasSuffix($0) }) { features["contractions", default: 0] += 1 }
            if Self.guidance[String(word)] != nil { features[String(word), default: 0] += 1 }
        }
        for key in Self.guidance.keys where features[key] != nil { features["passages_" + key] = 1 }
        // Only count narrowly identifiable English forms. Do not infer preposition mistakes
        // from word frequency; "at school" and "in the school" can both be appropriate.
        let foldedWords = words.map { $0.replacingOccurrences(of: "’", with: "'") }
        for (first, second) in zip(foldedWords, foldedWords.dropFirst()) {
            if first == "didn't" && Self.pastForms.contains(second) { features["grammar/didBase"] = 1 }
            if first == "an" && ["advice", "information", "equipment"].contains(second) { features["grammar/massNoun"] = 1 }
        }
        counts = features
    }

    private static let pastForms: Set<String> = ["went", "saw", "took", "wrote", "bought", "brought", "came", "ate", "drank", "spoke"]
    static let grammarGuidance = [
        "grammar/didBase": "After “didn’t,” use the base form of the verb. The past tense is already carried by “did.” For example, write “didn’t go” instead of “didn’t went.”",
        "grammar/massNoun": "Words such as “advice,” “information,” and “equipment” usually name something uncountable. Use “some advice” or “a piece of advice” when referring to one suggestion."
    ]

    static let guidance = [
        "so": "“So” can introduce a result or add emphasis. For a result, try “which means” or split the thought into two sentences. For emphasis, try a more precise adjective.",
        "very": "When “very” adds emphasis, try a more specific word. “Essential” may say more than “very important.” Keep “very” when the emphasis sounds like you.",
        "really": "Read the sentence once without “really.” Keep it when it conveys genuine emphasis. If you mean “in fact,” that phrase can make the contrast clearer.",
        "just": "Check what “just” is doing. It can mean “only,” refer to timing, or soften a request. For a direct request, try reading the sentence without it."
    ]
}
