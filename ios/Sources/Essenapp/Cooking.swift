import AVFoundation
import AudioToolbox
import Speech
import SwiftUI
import UserNotifications

// Phase 10: Kochmodus S18 (Feature 4), Timer + Sprachsteuerung (Feature 8).

// MARK: Erkennung (reine Funktionen)

enum CookParse {
    enum Command: Equatable {
        case next, back, again, startTimer, timer(Int), howMuch(String), ingredients

        var label: String {
            switch self {
            case .next: "weiter"
            case .back: "zurück"
            case .again: "wiederholen"
            case .startTimer: "Timer starten"
            case .timer(let s): "Timer \(CookTimer.clock(s))"
            case .howMuch(let q): "wie viel \(q)"
            case .ingredients: "Zutaten"
            }
        }
    }

    // shortcut: nur ganze Zahlwörter, keine „halbe Stunde“ – bei Bedarf ergänzen (auch für die Sprach-Liste, 45)
    static let numberWords = [
        "ein": "1", "eine": "1", "einer": "1", "zwei": "2", "drei": "3", "vier": "4", "fünf": "5", "sechs": "6",
        "sieben": "7", "acht": "8", "neun": "9", "zehn": "10", "elf": "11", "zwölf": "12", "fünfzehn": "15",
        "zwanzig": "20", "fünfundzwanzig": "25", "dreißig": "30", "vierzig": "40", "fünfundvierzig": "45",
        "fünfzig": "50", "sechzig": "60", "neunzig": "90",
    ]

    /// Alle Zeitangaben in Sekunden, in Textreihenfolge. Bereich („5–7 Minuten“) → obere Grenze.
    static func durations(in text: String) -> [Int] {
        let normalized = text.split(separator: " ", omittingEmptySubsequences: false)
            .map { w in numberWords[w.lowercased()] ?? String(w) }.joined(separator: " ")
        let regex = try! Regex(#"(\d+(?:[.,]\d+)?)(?:\s*(?:-|–|—|bis)\s*(\d+(?:[.,]\d+)?))?\s*(stunden|stunde|std|minuten|minute|min|sekunden|sekunde|sek)\b"#)
            .ignoresCase()
        return normalized.matches(of: regex).compactMap { m in
            guard let number = (m.output[2].substring ?? m.output[1].substring).flatMap({ s in Double(s.replacingOccurrences(of: ",", with: ".")) }),
                  let unit = m.output[3].substring?.lowercased() else { return nil }
            let factor: Double = unit.hasPrefix("st") ? 3600 : unit.hasPrefix("min") ? 60 : 1
            return Int((number * factor).rounded())
        }
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { c in !(c.isLetter || c.isNumber) }.map(String.init)
    }

    /// Kommt die Zutat im Text vor? Deutsche Komposita: „Reis“ ↔ „Basmatireis“, „Hähnchen“ ↔ „Hähnchenbrustfilet“.
    static func mentions(_ name: String, in text: String) -> Bool {
        let said = words(text)
        return words(name).contains { n in
            said.contains { w in
                w == n || (min(w.count, n.count) >= 4 && (n.hasPrefix(w) || n.hasSuffix(w) || w.hasPrefix(n) || w.hasSuffix(n)))
            }
        }
    }

    /// Timer-Name: erstes Wort des Schritts, das eine Zutat nennt, sonst die ersten 3 Wörter.
    static func timerName(_ step: String, _ ingredients: [IngredientDTO]) -> String {
        let tokens = step.split(separator: " ").map { t in t.trimmingCharacters(in: .punctuationCharacters) }.filter { t in !t.isEmpty }
        if let hit = tokens.first(where: { t in ingredients.contains { i in mentions(i.name, in: t) } }) { return hit }
        return tokens.prefix(3).joined(separator: " ")
    }

    private static let fillers: Set = ["brauche", "brauch", "braucht", "ich", "man", "nehme", "kommt", "kommen", "rein", "von", "vom",
                                       "der", "die", "das", "den", "dem", "noch", "denn", "davon"]

    /// Sprachbefehl im (Teil-)Ergebnis. nil = noch nichts Vollständiges, weiter zuhören.
    static func command(in transcript: String) -> Command? {
        let lower = transcript.lowercased().replacingOccurrences(of: "wie viel", with: "wieviel")
        if let r = lower.range(of: "timer", options: .backwards) {
            let rest = String(lower[r.upperBound...])
            if let s = durations(in: rest).last { return .timer(s) }
            if words(rest).contains(where: { w in ["starten", "start", "starte", "los", "an"].contains(w) }) { return .startTimer }
            return nil  // „Timer …“ – auf den Rest warten
        }
        let w = words(lower)
        if let i = w.lastIndex(where: { x in x.hasPrefix("wieviel") }) {
            let rest = w[(i + 1)...].filter { x in !fillers.contains(x) }
            return rest.isEmpty ? nil : .howMuch(rest.joined(separator: " "))
        }
        let simple: [(Command, Set<String>)] = [
            (.next, ["weiter", "nächster", "nächste", "next"]), (.back, ["zurück", "vorheriger"]),
            (.again, ["wiederholen", "wiederhole", "nochmal", "nochmals", "wiederholung"]), (.ingredients, ["zutaten"]),
        ]
        // zuletzt gesagter Befehl gewinnt
        return simple.compactMap { cmd, keys in w.lastIndex { x in keys.contains(x) }.map { i in (i, cmd) } }
            .max { a, b in a.0 < b.0 }?.1
    }

    #if DEBUG
    /// Beispiele aus der Spezifikation; läuft beim Öffnen des Kochmodus in Debug-Builds.
    static func selfTest() {
        assert(durations(in: "Tomaten zugeben, 15 Minuten köcheln.") == [900])
        assert(durations(in: "10 Min. ruhen lassen") == [600])
        assert(durations(in: "1 Stunde garen") == [3600])
        assert(durations(in: "1,5 Std im Ofen") == [5400])
        assert(durations(in: "30 Sekunden mixen") == [30])
        assert(durations(in: "5–7 Minuten braten") == [420])
        assert(durations(in: "Eine Stunde ziehen lassen") == [3600])
        assert(durations(in: "2 Zwiebeln würfeln, mindestens gut") == [])
        assert(command(in: "weiter") == .next)
        assert(command(in: "ok zurück") == .back)
        assert(command(in: "bitte wiederholen") == .again)
        assert(command(in: "Timer starten") == .startTimer)
        assert(command(in: "Timer 10 Minuten") == .timer(600))
        assert(command(in: "Timer") == nil)
        assert(command(in: "Wie viel Reis?") == .howMuch("reis"))
        assert(command(in: "wie viel") == nil)
        assert(command(in: "Zutaten") == .ingredients)
        assert(command(in: "zurück weiter") == .next)
        assert(mentions("Basmatireis", in: "Mit Reis servieren."))
        assert(mentions("Hähnchenbrustfilet", in: "Hähnchen dazugeben"))
        assert(!mentions("Weinessig", in: "eine Prise Salz"))
        assert(timerName("Tomaten und Gewürze zugeben, 15 Minuten köcheln.", [Demo.ing("Passierte Tomaten", 500)]) == "Tomaten")
        assert(timerName("Alles gut ruhen lassen.", []) == "Alles gut ruhen")
    }
    #endif
}

// MARK: Timer (Feature 8)

struct CookTimer: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var total: Int  // Sekunden (für den Ring)
    var end: Date?  // läuft bis; nil = pausiert
    var left: Int  // Restsekunden bei Pause
    var rang = false

    func remaining(_ now: Date) -> Int {
        rang ? 0 : end.map { e in max(0, Int(e.timeIntervalSince(now).rounded(.up))) } ?? left
    }

    static func clock(_ s: Int) -> String {
        s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Laufende Timer. Endzeit wird gespeichert (überlebt App-Wechsel), Ablauf meldet eine lokale Mitteilung.
@MainActor @Observable
final class CookTimers {
    /// Kochmodus offen → Ton/Haptik/Banner kommen von der App, nicht doppelt vom System (AppDelegate).
    nonisolated(unsafe) static var cookingOpen = false

    var timers: [CookTimer] { didSet { Persist.save(timers, "cookTimers") } }
    var ringing: String?  // Name des gerade abgelaufenen Timers (Banner)
    var rings = 0  // Auslöser für Ton + Haptik

    init() {
        timers = Demo.screen == "cooking" ? [CookTimer(name: "Zwiebel", total: 300, end: .now + 192, left: 300)]
                                          : Persist.load("cookTimers") ?? []
    }

    func start(_ name: String, seconds: Int) {
        let t = CookTimer(name: name, total: seconds, end: .now + TimeInterval(seconds), left: seconds)
        timers.append(t)
        schedule(t)
    }

    func toggle(_ id: UUID) {
        guard let i = timers.firstIndex(where: { t in t.id == id }) else { return }
        if timers[i].end != nil {
            timers[i].left = timers[i].remaining(.now)
            timers[i].end = nil
            cancel(id)
        } else {
            timers[i].end = .now + TimeInterval(timers[i].left)
            schedule(timers[i])
        }
    }

    func addMinute(_ id: UUID) {
        guard let i = timers.firstIndex(where: { t in t.id == id }) else { return }
        if timers[i].rang {
            timers[i] = CookTimer(id: id, name: timers[i].name, total: 60, end: .now + 60, left: 60)
        } else {
            timers[i].total += 60
            timers[i].left += 60
            timers[i].end = timers[i].end.map { e in e + 60 }
        }
        if timers[i].end != nil { schedule(timers[i]) }
    }

    func stop(_ id: UUID) {
        timers.removeAll { t in t.id == id }
        cancel(id)
    }

    func check() {
        let now = Date.now
        for i in timers.indices where !timers[i].rang {
            guard let end = timers[i].end, end <= now else { continue }
            timers[i].rang = true
            // länger her = lief im Hintergrund ab, die Mitteilung hat schon geklingelt
            if now.timeIntervalSince(end) < 5 { ring(timers[i].name) }
        }
    }

    /// Nach erteilter Erlaubnis: Mitteilungen für schon laufende Timer nachholen.
    func rescheduleAll() {
        for t in timers where t.end != nil && !t.rang { schedule(t) }
    }

    private func ring(_ name: String) {
        ringing = name
        rings += 1
        Task {
            try? await Task.sleep(for: .seconds(4))
            if ringing == name { ringing = nil }
        }
    }

    private func schedule(_ t: CookTimer) {
        guard Demo.screen == nil, let end = t.end else { return }
        let id = "timer-\(t.id)", name = t.name, total = t.total, seconds = max(1, end.timeIntervalSinceNow)
        Task {
            let content = UNMutableNotificationContent()
            content.title = "⏲ \(name) ist fertig"
            content.body = "Dein Timer (\(CookTimer.clock(total))) ist abgelaufen."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    private func cancel(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timer-\(id)"])
    }
}

// MARK: Sprachsteuerung (Feature 8)

/// Audio-Thread hängt Puffer an den aktuellen Request; der Main-Thread tauscht ihn aus – daher das Lock.
private final class AudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ r: SFSpeechAudioBufferRecognitionRequest?) { lock.withLock { request = r } }
    func append(_ b: AVAudioPCMBuffer) { lock.withLock { request?.append(b) } }
}

/// Lauscht nur, solange der Kochmodus (Befehle) bzw. die Sprach-Eingabe der Liste (Diktat, 45) offen und 🎙 an ist.
/// Erkennung auf dem Gerät, wenn verfügbar.
@MainActor @Observable
final class VoiceControl {
    var listening = false
    var level: Float = 0  // Mikrofon-Pegel 0…1
    var heard: String?  // erkannter Befehl, blinkt kurz
    var note: String?  // Hinweis, z. B. fehlende Erlaubnis
    var transcript = ""  // Diktat: bisher erkannter Text
    @ObservationIgnored var dictation = false  // true = Text sammeln statt Befehle auswerten
    @ObservationIgnored var hints: [String] = []
    @ObservationIgnored var onCommand: (CookParse.Command) -> Bool = { _ in false }
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let synth = AVSpeechSynthesizer()
    private let feed = AudioFeed()
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var speaking = false
    @ObservationIgnored private var tapped = false

    func toggle() async {
        if listening { stop(); return }
        guard let recognizer, recognizer.isAvailable else { tell("Spracherkennung ist gerade nicht verfügbar"); return }
        guard await Self.authorize() else { tell("Bitte Mikrofon und Spracherkennung in den iOS-Einstellungen erlauben"); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tap(feed, self))
            tapped = true
            engine.prepare()
            try engine.start()
            listening = true
            listen()
        } catch {
            stop()
            tell("Mikrofon konnte nicht gestartet werden")
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        feed.set(nil)
        synth.stopSpeaking(at: .immediate)
        if tapped {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(.soloAmbient)  // Standard der App wiederherstellen
        }
        listening = false
        level = 0
    }

    /// Vorlesen (de-DE). Währenddessen keine Befehle auswerten, danach mit leerem Puffer weiter.
    func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        speaking = true
        synth.speak(utterance)
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            while synth.isSpeaking { try? await Task.sleep(for: .milliseconds(200)) }
            speaking = false
            if listening { listen() }
        }
    }

    /// Neuer Request = leerer Puffer; alte Ergebnisse werden über `generation` verworfen.
    private func listen() {
        task?.cancel()
        generation += 1
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = hints
        if recognizer?.supportsOnDeviceRecognition == true { request.requiresOnDeviceRecognition = true }
        feed.set(request)
        task = recognizer?.recognitionTask(with: request, resultHandler: Self.results(self, generation))
    }

    private func received(_ text: String?, ended: Bool, gen: Int) {
        guard gen == generation, listening else { return }
        if dictation {
            if let text { transcript = text }
            if ended { stop() }  // Zeitlimit oder Fehler: Text bleibt, neu starten per 🎙
            return
        }
        if let text, !speaking, let cmd = CookParse.command(in: text), onCommand(cmd) {
            flash(cmd.label)
            listen()
        } else if ended {  // Zeitlimit (~1 min) oder Fehler: kurz warten, neu starten
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if gen == generation, listening { listen() }
            }
        }
    }

    private func flash(_ text: String) {
        heard = text
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if heard == text { heard = nil }
        }
    }

    private func tell(_ text: String) {
        note = text
        Task {
            try? await Task.sleep(for: .seconds(4))
            if note == text { note = nil }
        }
    }

    // Callbacks laufen auf fremden Threads → außerhalb des MainActors bauen, dann zurückspringen.
    nonisolated private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in c.resume(returning: status == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    nonisolated private static func tap(_ feed: AudioFeed, _ voice: VoiceControl) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            feed.append(buffer)
            guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += data[i] * data[i] }
            let level = min(1, (sum / Float(n)).squareRoot() * 12)  // grob auf 0…1 für die Pegelanzeige
            Task { @MainActor in voice.level = level }
        }
    }

    nonisolated private static func results(_ voice: VoiceControl, _ gen: Int) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let ended = error != nil || result?.isFinal == true
            Task { @MainActor in voice.received(text, ended: ended, gen: gen) }
        }
    }
}

// MARK: S18 Kochmodus

/// Kochmodus v8 (b.html S18, hell): Seite 0 Vorbereitung, dann ein Schritt pro Seite, zuletzt „Fertig!“. Bildschirm bleibt an.
struct CookingView: View {
    let meal: MealDTO
    var imagesLoading = false  // Schritt-Bilder entstehen noch → leerer Teller schimmert (9)
    var factor = 1.0  // Portionen-Stepper aus S3
    var person: (emoji: String, factor: Double)?  // „Deine Portion“ aus S3
    let onFinish: () -> Void
    var onSubstitute: (MealDTO?) -> Void = { _ in }  // „Ersatz finden“ (7): gespeichertes Rezept → S3 übernimmt es
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var page = Demo.screen == "cooking" ? 2 : 0
    @State private var checked: Set<Int> = []
    @State private var timers = CookTimers()
    @State private var voice = VoiceControl()
    @State private var askPush = false
    @State private var substituting: Int?
    @State private var started = Date.now

    // Mockup-Maße (b.html S18), Bildschirm-Koordinaten inkl. Statusleiste 52
    private enum M {
        static let prepBlob = (x: 196.0, y: -70.0, size: 300.0)
        static let arch = (x: -10.0, y: 480.0, w: 300.0, h: 420.0)
        static let archTimer = (x: -10.0, y: 600.0, w: 260.0, h: 400.0)  // mit Timer: leerer, kleinerer Bogen
        static let cook = (x: -6.0, y: 500.0, w: 290.0)
        static let doneBlob = (x: -50.0, y: 60.0, size: 490.0)
        static let donePlate = (x: 70.0, y: 140.0, size: 250.0)
        static let doneTitle: CGFloat = 448 - 52  // ab Safe Area
        static let doneStats: CGFloat = 578 - 52
        static let timerBottom: CGFloat = 124 - 34  // über der Home-Leiste
    }

    private var steps: [String] { meal.recipe.steps }
    private var last: Int { steps.count + 1 }
    private var stepIndex: Int? { page >= 1 && page <= steps.count ? page - 1 : nil }
    private var ingredients: [IngredientDTO] {
        meal.recipe.ingredients.map { ing in
            var scaled = ing
            scaled.amount *= factor
            return scaled
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if page == 0 {
                    prepPage
                } else if let i = stepIndex {
                    stepPage(i, steps[i])
                } else {
                    finishPage
                }
            }
            .id(page)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 30)), removal: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) { bottom }
        .overlay(alignment: .top) { banner }
        .backdrop8 { backdrop }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in  // Wischen wie früher die Seiten
            if v.translation.width < -60 { go(page + 1) } else if v.translation.width > 60 { go(page - 1) }
        })
        .foregroundStyle(Theme.C.ink)
        .animation(Theme.spring, value: timers.timers)
        .animation(Theme.spring, value: timers.ringing)
        .animation(Theme.spring, value: voice.listening)
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.warning, trigger: timers.rings)
        .onChange(of: timers.rings) { AudioServicesPlaySystemSound(1005) }  // Wecker-Ton
        .onChange(of: scenePhase) { if scenePhase != .active { voice.stop() } }
        .onAppear {
            #if DEBUG
            CookParse.selfTest()
            #endif
            UIApplication.shared.isIdleTimerDisabled = true
            CookTimers.cookingOpen = true
            voice.hints = ["weiter", "zurück", "wiederholen", "Timer starten", "Zutaten", "wie viel"] + meal.recipe.ingredients.map(\.name)
            voice.onCommand = { cmd in handle(cmd) }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            CookTimers.cookingOpen = false
            voice.stop()
        }
        .task {
            while !Task.isCancelled {
                timers.check()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        .sheet(isPresented: $askPush, onDismiss: { timers.rescheduleAll() }) {
            PushPermissionSheet(text: "Damit dein Timer klingelt, auch wenn das iPhone gesperrt ist oder du eine andere App offen hast.")
                .presentationCornerRadius(Theme.R.sheet)
        }
        .sheet(isPresented: Binding(get: { substituting != nil }, set: { on in if !on { substituting = nil } })) {
            if let i = substituting {
                SubstituteSheet(meal: meal, index: i, done: onSubstitute).presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Hintergrund

    @ViewBuilder private var backdrop: some View {
        if page == 0 {
            Color.clear.edgeForm(.circle, Theme.C.sage, width: M.prepBlob.size, height: M.prepBlob.size, left: M.prepBlob.x, top: M.prepBlob.y)
        } else if let i = stepIndex {
            if timers.timers.isEmpty {
                Color.clear
                    .pinned(left: M.cook.x, top: M.cook.y) { stepPicture(i) }
                    .edgeForm(.arch, Theme.C.sage, width: M.arch.w, height: M.arch.h, left: M.arch.x, top: M.arch.y)
            } else {
                Color.clear.edgeForm(.arch, Theme.C.sage, width: M.archTimer.w, height: M.archTimer.h, left: M.archTimer.x, top: M.archTimer.y)
            }
        } else {
            Color.clear
                .pinned(left: M.donePlate.x, top: M.donePlate.y) { PlatePhoto(url: mediaURL(meal.recipe.imageUrl), size: M.donePlate.size) }
                .edgeForm(.circle, Theme.C.blue, width: M.doneBlob.size, height: M.doneBlob.size, left: M.doneBlob.x, top: M.doneBlob.y)
        }
    }

    /// Im Bogen: Schritt-Bild als Teller (9), solange es entsteht ein schimmernder Teller, sonst die Koch-Szene.
    @ViewBuilder private func stepPicture(_ i: Int) -> some View {
        let images = meal.recipe.stepImages ?? []
        if i < images.count, !images[i].isEmpty {
            PlatePhoto(url: mediaURL(images[i]), size: 220).padding(.leading, 35).padding(.top, 30)
        } else if imagesLoading, i < images.count {
            Skeleton8(width: 220, height: 220).clipShape(Circle()).padding(.leading, 35).padding(.top, 30)
        } else {
            Ill("cook").frame(width: M.cook.w)
        }
    }

    // MARK: Seiten

    private var prepPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CloseButton(label: "Kochmodus schließen") { dismiss() }.background(Theme.C.bg, in: Circle().inset(by: 2))
                    Spacer()
                    if voice.listening || voice.note != nil { VoicePill(voice: voice) }
                    RoundIcon(icon: .mic, fill: voice.listening ? Theme.C.blue : nil,
                              label: voice.listening ? "Sprachsteuerung aus" : "Sprachsteuerung an") { Task { await voice.toggle() } }
                }
                StatPair(label: "Vorbereitung", value: "\(checked.count)", size: 104, rest: " von \(ingredients.count)", restSize: 40)
                    .padding(.top, 20)
                Text("Erst alles bereitlegen.").font(Theme.F.t2).padding(.top, 28)
                Text("für \(num(meal.basePortions * factor)) Portionen").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.C.ink2).padding(.top, 4)
                VStack(spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.offset) { i, ing in prepRow(i, ing) }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.success, trigger: checked)
    }

    private func prepRow(_ i: Int, _ ing: IngredientDTO) -> some View {
        let on = checked.contains(i)
        return Button {
            withAnimation(Theme.spring) { if checked.remove(i) == nil { checked.insert(i) } }
        } label: {
            HStack(spacing: 14) {
                CheckCircle(on: on)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ing.name).font(Theme.F.text(16, .bold)).strikethrough(on).foregroundStyle(on ? Theme.C.ink3 : Theme.C.ink)
                        .multilineTextAlignment(.leading)
                    if let person {
                        Text("du: \(qty(meal.recipe.ingredients[i].amount * person.factor, ing.unit))")
                            .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                    }
                }
                Spacer(minLength: 8)
                Text(qty(ing.amount, ing.unit)).font(Theme.F.text(16, .extrabold)).monospacedDigit().foregroundStyle(Theme.C.ink)
            }
            .frame(minHeight: Theme.S.row)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .contextMenu {  // lange drücken → Ersatz (7)
            Button("Ersatz finden", systemImage: "arrow.left.arrow.right") { substituting = i }
        }
        .accessibilityAction(named: "Ersatz finden") { substituting = i }
    }

    private func stepPage(_ i: Int, _ step: String) -> some View {
        let used = ingredients.filter { ing in CookParse.mentions(ing.name, in: step) }
        let name = CookParse.timerName(step, ingredients)
        let (head, rest) = Self.split(step)
        let number = { (n: Int) in n < 10 ? "0\(n)" : "\(n)" }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { go(page - 1) } label: { Icon(.back, size: 26).frame(width: 44, height: 44, alignment: .leading) }
                        .buttonStyle(PressableStyle()).accessibilityLabel("Zurück")
                    Spacer()
                    stepPill
                }
                StatPair(label: "Schritt", value: number(i + 1), size: 112, rest: "/" + number(steps.count), restSize: 48)
                    .padding(.top, 22)
                Text(head).font(Theme.F.t1).fixedSize(horizontal: false, vertical: true).padding(.top, 22)
                if !rest.isEmpty {
                    Text(rest).font(Theme.F.text(17, .semibold, relativeTo: .body)).lineSpacing(8).foregroundStyle(Theme.C.ink2)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                }
                let durations = CookParse.durations(in: step)
                if !used.isEmpty || !durations.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(durations.enumerated()), id: \.offset) { _, seconds in
                                let running = timers.timers.contains { t in t.name == name && t.total == seconds && !t.rang }
                                Chip8(title: running ? "\(name) läuft" : "Timer \(CookTimer.clock(seconds))", on: !running, icon: .clock) {
                                    startTimer(name, seconds)
                                }
                                .disabled(running)
                                .accessibilityLabel(running ? "Timer \(name) läuft" : "Timer \(name) \(CookTimer.clock(seconds)) starten")
                            }
                            ForEach(used, id: \.self) { ing in
                                Text("\(ing.name) · \(qty(ing.amount, ing.unit))").font(Theme.F.chip).foregroundStyle(Theme.C.ink2)
                                    .padding(.horizontal, 15).frame(height: Theme.S.chip)
                                    .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                            }
                        }
                        .padding(.trailing, Theme.pagePadding)
                    }
                    .padding(.trailing, -Theme.pagePadding)
                    .padding(.top, 24)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 220)
        }
        .scrollIndicators(.hidden)
    }

    /// Oben rechts im Schritt: „hört zu …“ (Sprache an) oder die Restzeit des laufenden Timers.
    @ViewBuilder private var stepPill: some View {
        if voice.listening || voice.note != nil {
            VoicePill(voice: voice).transition(.scale.combined(with: .opacity))
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let t = timers.timers.first(where: { !$0.rang }) {
                    HStack(spacing: 6) {
                        Icon(.clock, size: 16)
                        Text(CookTimer.clock(t.remaining(context.date))).monospacedDigit()
                    }
                    .font(Theme.F.pill).foregroundStyle(Theme.C.ink)
                    .padding(.horizontal, 12).frame(height: Theme.S.pill)
                    .background(Theme.C.blue1, in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Timer \(t.name)")
                }
            }
        }
    }

    private var finishPage: some View {
        let minutes = max(1, Int(Date.now.timeIntervalSince(started) / 60))
        return ZStack(alignment: .topLeading) {
            CloseButton(label: "Kochmodus schließen") { dismiss() }.background(Theme.C.bg, in: Circle().inset(by: 2))
            VStack(alignment: .leading, spacing: 6) {
                Text("Fertig!").font(Theme.F.serif(60, relativeTo: .largeTitle))
                Text("\(meal.recipe.title) · \(num(meal.basePortions * factor)) Portionen").font(Theme.F.small).foregroundStyle(Theme.C.ink)
            }
            .padding(.top, M.doneTitle - 14)
            StatNumber(label: "Gekocht in", value: "\(minutes) min", size: 44).padding(.top, M.doneStats - 14)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 14)
    }

    /// Unten: Timer-Kapseln, dann rechts „Los geht's“ + Pfeil (Vorbereitung), Mikro + Pfeil (Schritt) bzw. „Bewerten“ (Fertig).
    @ViewBuilder private var bottom: some View {
        if page == last {
            PrimaryButton(title: "Bewerten", icon: .star) { onFinish() }
                .padding(.horizontal, Theme.pagePadding).padding(.bottom, 6)
        } else {
            VStack(spacing: 0) {
                if stepIndex != nil, !timers.timers.isEmpty {
                    TimerBar(timers: timers).padding(.horizontal, Theme.pagePadding).padding(.bottom, M.timerBottom - 72)
                }
                HStack(spacing: 0) {
                    Spacer()
                    if page == 0 {
                        Text("Los geht's").font(Theme.F.text(16, .extrabold)).padding(.trailing, 14).accessibilityHidden(true)
                    } else {
                        RoundIcon(icon: .mic, size: 60, iconSize: 24, fill: voice.listening ? Theme.C.blue : nil,
                                  label: voice.listening ? "Sprachsteuerung aus" : "Sprachsteuerung an") { Task { await voice.toggle() } }
                            .padding(.trailing, 8)
                    }
                    RoundIcon(icon: .arrow, filled: true, size: 72, iconSize: 24,
                              label: page == 0 ? "Los geht's" : page == steps.count ? "Fertig" : "Nächster Schritt") { go(page + 1) }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            .accessibilityAction(named: "Zurück") { go(page - 1) }
        }
    }

    /// Timer abgelaufen: Tinten-Pille oben (`.toast`).
    @ViewBuilder private var banner: some View {
        if let name = timers.ringing {
            HStack(spacing: 8) {
                Icon(.clock, size: 18)
                Text("\(name) ist fertig!")
            }
            .font(Theme.F.toast).foregroundStyle(Theme.C.onInk)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Theme.C.ink, in: Capsule())
            .padding(.top, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Aktionen

    /// Erster Satz groß (`t1`), der Rest als Erklärung darunter.
    static func split(_ step: String) -> (String, String) {
        guard let r = step.range(of: ". "), step[r.upperBound...].contains(where: \.isLetter) else { return (step, "") }
        return (String(step[..<r.lowerBound]) + ".", String(step[r.upperBound...]))
    }

    private func go(_ target: Int) {
        withAnimation(Theme.spring) { page = min(max(target, 0), last) }
    }

    private func startTimer(_ name: String, _ seconds: Int) {
        timers.start(name, seconds: seconds)
        guard Demo.screen == nil else { return }
        Task {
            if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined { askPush = true }
        }
    }

    private func spoken(_ ing: IngredientDTO) -> String {
        let units = ["g": "Gramm", "kg": "Kilogramm", "ml": "Milliliter", "l": "Liter", "stk": "Stück", "el": "Esslöffel", "tl": "Teelöffel"]
        return "\(num(ing.amount)) \(units[ing.unit.lowercased()] ?? ing.unit) \(ing.name)"
    }

    /// Sprachbefehl ausführen. false = (noch) nicht passend, weiter zuhören.
    private func handle(_ cmd: CookParse.Command) -> Bool {
        let step = stepIndex.map { i in steps[i] }
        let stepIngredients = step.map { s in ingredients.filter { ing in CookParse.mentions(ing.name, in: s) } } ?? ingredients
        switch cmd {
        case .next: go(page + 1)
        case .back: go(page - 1)
        case .again:
            voice.speak(step.map { s in "Schritt \(page). \(s)" }
                        ?? (page == 0 ? "Vorbereitung. " + ingredients.map(spoken).joined(separator: ", ") : "Fertig! Guten Appetit."))
        case .ingredients:
            voice.speak(stepIngredients.isEmpty ? "In diesem Schritt kommen keine Zutaten vor." : stepIngredients.map(spoken).joined(separator: ", "))
        case .startTimer:
            guard let step, let seconds = CookParse.durations(in: step).first else {
                voice.speak("In diesem Schritt steht keine Zeit. Sag zum Beispiel: Timer 10 Minuten.")
                return true
            }
            startTimer(CookParse.timerName(step, ingredients), seconds)
        case .timer(let seconds):
            startTimer(step.map { s in CookParse.timerName(s, ingredients) } ?? "Timer", seconds)
        case .howMuch(let query):
            guard let ing = ingredients.first(where: { i in CookParse.mentions(i.name, in: query) }) else { return false }
            voice.speak(spoken(ing))
        }
        return true
    }
}

/// Timer-Kapseln (S18): Ring mit Pause/Weiter, Name, Restzeit; „…“ für +1 min und Stopp.
struct TimerBar: View {
    let timers: CookTimers

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(spacing: 8) {
                ForEach(timers.timers) { t in capsule(t, now: ctx.date).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
        }
    }

    private func capsule(_ t: CookTimer, now: Date) -> some View {
        let left = t.remaining(now)
        return HStack(spacing: 10) {
            Button { if !t.rang { timers.toggle(t.id) } } label: {
                ZStack {
                    Circle().stroke(Theme.C.line, lineWidth: 4)
                    Circle().trim(from: 0, to: t.total > 0 ? 1 - Double(left) / Double(t.total) : 1)
                        .stroke(Theme.C.blue3, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if !t.rang { Icon(t.end == nil ? .play : .pause, size: 16) }
                }
                .frame(width: 40, height: 40)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .disabled(t.rang)
            .accessibilityLabel(t.end == nil ? "Fortsetzen" : "Pause")
            VStack(alignment: .leading, spacing: 0) {
                Text(t.name).font(Theme.F.text(13, .extrabold, relativeTo: .footnote)).lineLimit(1)
                Text(t.rang ? "fertig!" : CookTimer.clock(left)).font(Theme.F.num(26)).tracking(Theme.F.numTracking(26)).monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .phaseAnimator([1.0, 0.35]) { view, phase in view.opacity(t.rang ? phase : 1) }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Eine Minute mehr", systemImage: "plus") { timers.addMinute(t.id) }
                Button("Timer stoppen", systemImage: "xmark", role: .destructive) { timers.stop(t.id) }
            } label: {
                Icon(.dots, size: 18).frame(width: Theme.S.close, height: Theme.S.close)
                    .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .accessibilityLabel("Timer \(t.name): mehr Zeit oder stoppen")
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, 10)
        .frame(height: 68)
        .background(Theme.C.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
        .floatShadow()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timer \(t.name), \(t.rang ? "fertig" : CookTimer.clock(left))")
    }
}

/// Pille „hört zu …“ mit Pegel (S18): `blue1`, Mikro, Text, fünf Pegel-Striche; erkannter Befehl blinkt kurz.
struct VoicePill: View {
    let voice: VoiceControl
    private let bars: [CGFloat] = [6, 12, 16, 9, 5]

    var body: some View {
        HStack(spacing: 8) {
            Icon(.mic, size: 16)
            if let heard = voice.heard {
                Text("„\(heard)“").phaseAnimator([1.0, 0.3, 1.0]) { view, phase in view.opacity(phase) }
            } else if let note = voice.note, !voice.listening {
                Text(note).lineLimit(2)
            } else {
                Text("hört zu …")
                HStack(spacing: 2) {
                    ForEach(bars.indices, id: \.self) { i in
                        Capsule().fill(Theme.C.ink).frame(width: 3, height: max(3, bars[i] * CGFloat(0.3 + 0.7 * voice.level)))
                    }
                }
                .frame(height: 16)
                .animation(.easeOut(duration: 0.1), value: voice.level)
            }
        }
        .font(Theme.F.pill)
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(Theme.C.blue1, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Leichte Konfetti-Animation (Canvas, ohne Pakete): fällt einmal durch und ist dann weg.
struct Confetti: View {
    private struct Piece {
        var x, delay, speed, sway, phase, spin, size: Double
        var color: Color
    }

    @State private var start = Date.now
    @State private var pieces: [Piece] = (0..<90).map { _ in
        Piece(x: .random(in: 0...1), delay: .random(in: 0...0.8), speed: .random(in: 0.35...0.6), sway: .random(in: 1...3),
              phase: .random(in: 0...6), spin: .random(in: 2...8), size: .random(in: 6...11),
              color: [Theme.C.lime, Theme.C.highlight, Theme.C.carbs, Theme.C.fat, Theme.C.protein, .white].randomElement()!)
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSince(start)
                for p in pieces where t > p.delay {
                    let y = -20 + (t - p.delay) * p.speed * size.height
                    guard y < size.height + 20 else { continue }
                    var c = g
                    c.translateBy(x: p.x * size.width + sin(t * p.sway + p.phase) * 18, y: y)
                    c.rotate(by: .radians(t * p.spin))
                    c.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)), with: .color(p.color))
                }
            }
        }
    }
}

extension View {
    /// Liquid Glass ab iOS 26, sonst Material.
    @ViewBuilder func glass(_ shape: some Shape, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(tint.map { c in Glass.regular.tint(c) } ?? Glass.regular, in: shape)
        } else {
            background(tint ?? .clear, in: shape).background(.ultraThinMaterial, in: shape)
        }
    }
}
