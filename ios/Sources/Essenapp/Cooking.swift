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

/// Vollbild, dunkel, Bildschirm bleibt an. Seite 0 Vorbereitung, dann ein Schritt pro Seite, zuletzt „Fertig! 🎉“.
struct CookingView: View {
    let meal: MealDTO
    var imagesLoading = false  // Schritt-Bilder entstehen noch → leere Plätze schimmern (9)
    var factor = 1.0  // Portionen-Stepper aus S3
    var person: (emoji: String, factor: Double)?  // „Deine Portion“ aus S3
    let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var appScheme  // außerhalb des Kochmodus (der selbst immer dunkel ist)
    @State private var page = Demo.screen == "cooking" ? 2 : 0
    @State private var checked: Set<Int> = []
    @State private var timers = CookTimers()
    @State private var voice = VoiceControl()
    @State private var askPush = false

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
        VStack(spacing: 0) {
            header
            TabView(selection: $page) {
                prepPage.tag(0)
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in stepPage(i, step).tag(i + 1) }
                finishPage.tag(last)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            TimerBar(timers: timers).padding(.horizontal, Theme.pagePadding)
            nav
        }
        .background(Theme.C.cookBg.ignoresSafeArea())
        .overlay {
            if page == last && !reduceMotion { Confetti().allowsHitTesting(false).ignoresSafeArea() }
        }
        .overlay(alignment: .top) { banners.padding(.top, 70) }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
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
        .sheet(isPresented: $askPush, onDismiss: { timers.rescheduleAll() }) {
            PushPermissionSheet(text: "Damit dein Timer klingelt, auch wenn das iPhone gesperrt ist oder du eine andere App offen hast.")
                .presentationDetents([.medium]).presentationCornerRadius(Theme.R.sheet)
                .foregroundStyle(Theme.C.text1).environment(\.colorScheme, appScheme)  // Sheet folgt dem App-Erscheinungsbild
        }
    }

    // MARK: Teile

    private var header: some View {
        HStack(spacing: 12) {
            circleButton("xmark", "Kochmodus schließen") { dismiss() }
            VStack(alignment: .leading, spacing: 8) {
                Text(page == 0 ? "Vorbereitung" : page == last ? "Fertig" : "Schritt \(page) von \(steps.count)")
                    .font(Theme.F.caption).foregroundStyle(Theme.C.cookText2)
                    .contentTransition(.numericText())
                GeometryReader { g in
                    Capsule().fill(Theme.C.cookSurface)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.C.accent).frame(width: g.size.width * Double(page) / Double(last))
                        }
                }
                .frame(height: 6)
                .animation(Theme.spring, value: page)
                .accessibilityHidden(true)
            }
            circleButton(voice.listening ? "mic.fill" : "mic", voice.listening ? "Sprachsteuerung aus" : "Sprachsteuerung an",
                         on: voice.listening) { Task { await voice.toggle() } }
        }
        .padding(.horizontal, Theme.pagePadding).padding(.top, 8).padding(.bottom, 12)
    }

    @ViewBuilder private var banners: some View {
        VStack(spacing: 8) {
            if voice.listening || voice.note != nil { VoicePill(voice: voice).transition(.scale.combined(with: .opacity)) }
            if let name = timers.ringing {
                Label("\(name) ist fertig!", systemImage: "timer")
                    .font(Theme.F.headline)
                    .padding(.horizontal, 18).frame(minHeight: 48)
                    .background(Theme.C.accent, in: Capsule())
                    .floatShadow()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var prepPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Vorbereitung").font(Theme.F.cookTitle)
                Text("Alles bereitstellen und abhaken · \(checked.count) von \(ingredients.count)")
                    .font(Theme.F.callout).foregroundStyle(Theme.C.cookText2)
                    .contentTransition(.numericText())
                    .padding(.bottom, 6)
                ForEach(Array(ingredients.enumerated()), id: \.offset) { i, ing in
                    let on = checked.contains(i)
                    Button {
                        withAnimation(Theme.spring) { if checked.remove(i) == nil { checked.insert(i) } }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(Theme.F.cookBody)
                                .foregroundStyle(on ? Theme.C.accent : Theme.C.cookText2)
                                .contentTransition(.symbolEffect(.replace))
                            Text(ing.name).font(Theme.F.cookBody).strikethrough(on)
                                .foregroundStyle(on ? Theme.C.cookText2 : .white)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(qty(ing.amount, ing.unit)).font(Theme.F.callout).monospacedDigit()
                                if let person {
                                    Text("\(person.emoji) \(qty(meal.recipe.ingredients[i].amount * person.factor, ing.unit))")
                                        .font(Theme.F.micro).monospacedDigit().foregroundStyle(Theme.C.highlight)
                                }
                            }
                            .foregroundStyle(on ? Theme.C.cookText2 : .white)
                        }
                        .padding(14)
                        .background(Theme.C.cookSurface, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.bottom, 16)
        }
        .sensoryFeedback(.success, trigger: checked)
    }

    private func stepPage(_ i: Int, _ step: String) -> some View {
        let used = ingredients.filter { ing in CookParse.mentions(ing.name, in: step) }
        let name = CookParse.timerName(step, ingredients)
        return VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let images = meal.recipe.stepImages, i < images.count, !images[i].isEmpty || imagesLoading {
                        StepImage(path: images[i], dark: true)
                    }
                    Text("Schritt \(i + 1)").font(Theme.F.callout).foregroundStyle(Theme.C.accent)
                    Text(step).font(Theme.F.cookStep).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(CookParse.durations(in: step).enumerated()), id: \.offset) { _, seconds in
                        let running = timers.timers.contains { t in t.name == name && t.total == seconds && !t.rang }
                        Button { startTimer(name, seconds) } label: {
                            Label(running ? "\(name) läuft" : "\(name) · \(CookTimer.clock(seconds))", systemImage: "timer")
                                .font(Theme.F.headline)
                                .padding(.horizontal, 20).frame(minHeight: 52)
                                .background(running ? Theme.C.cookSurface : Theme.C.accent, in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(running)
                        .accessibilityLabel(running ? "Timer \(name) läuft" : "Timer \(name) \(CookTimer.clock(seconds)) starten")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.pagePadding)
            }
            if !used.isEmpty {
                Text("ZUTATEN IN DIESEM SCHRITT").font(Theme.F.micro).foregroundStyle(Theme.C.cookText2)
                    .padding(.horizontal, Theme.pagePadding)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(used, id: \.self) { ing in
                            HStack(spacing: 6) {
                                Text(ing.name)
                                Text(qty(ing.amount, ing.unit)).foregroundStyle(Theme.C.cookText2).monospacedDigit()
                            }
                            .font(Theme.F.callout)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Theme.C.cookSurface, in: Capsule())
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
            }
        }
        .padding(.bottom, 12)
    }

    private var finishPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Plate(url: mediaURL(meal.recipe.imageUrl), size: 200, seed: meal.recipe.title)
            Text("Fertig! 🎉").font(Theme.F.cookTitle)
            Text("Guten Appetit! Bewerte das Gericht – danach ziehen wir die Zutaten vom Vorrat ab.")
                .font(Theme.F.body).foregroundStyle(Theme.C.cookText2).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    private var nav: some View {
        HStack(spacing: 12) {
            circleButton("chevron.left", "Zurück") { go(page - 1) }
                .disabled(page == 0).opacity(page == 0 ? 0.3 : 1)
            Button { page == last ? onFinish() : go(page + 1) } label: {
                HStack(spacing: 8) {
                    Text(page == last ? "Bewerten ★" : page == 0 ? "Los geht's" : page == steps.count ? "Fertig" : "Weiter")
                    if page < last { Image(systemName: "chevron.right") }
                }
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.C.accent))
        }
        .padding(.horizontal, Theme.pagePadding).padding(.top, 10).padding(.bottom, 8)
    }

    private func circleButton(_ symbol: String, _ label: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(Theme.F.headline)
                .frame(width: 44, height: 44)
                .background(on ? Theme.C.accent : Theme.C.cookSurface, in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    // MARK: Aktionen

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

/// Schwebende Timer-Leiste: Glas-Kapseln mit Ring, Restzeit, Pause/+1 min/Stop.
struct TimerBar: View {
    let timers: CookTimers

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(spacing: 8) {
                ForEach(timers.timers) { t in capsule(t, now: ctx.date).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
        }
        .task {
            while !Task.isCancelled {
                timers.check()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func capsule(_ t: CookTimer, now: Date) -> some View {
        let left = t.remaining(now)
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.C.cookSurface, lineWidth: 4)
                Circle().trim(from: 0, to: t.total > 0 ? 1 - Double(left) / Double(t.total) : 1)
                    .stroke(t.rang ? Color.white : Theme.C.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(t.name).font(Theme.F.micro).foregroundStyle(Theme.C.cookText2).lineLimit(1)
                Text(t.rang ? "fertig!" : CookTimer.clock(left)).font(Theme.F.cookTimer).monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .phaseAnimator([1.0, 0.35]) { view, phase in view.opacity(t.rang ? phase : 1) }
            }
            Spacer(minLength: 0)
            if !t.rang {
                small(t.end == nil ? "play.fill" : "pause.fill", t.end == nil ? "Fortsetzen" : "Pause") { timers.toggle(t.id) }
            }
            Button { timers.addMinute(t.id) } label: {
                Text("+1 min").font(Theme.F.micro).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Eine Minute mehr")
            small("xmark", "Timer \(t.name) stoppen") { timers.stop(t.id) }
        }
        .padding(.leading, 12).padding(.trailing, 4)
        .frame(minHeight: 56)
        .glass(Capsule(), tint: t.rang ? Theme.C.accent.opacity(0.7) : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timer \(t.name), \(t.rang ? "fertig" : CookTimer.clock(left))")
    }

    private func small(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(Theme.F.callout).frame(width: 44, height: 44)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Glas-Pille „🎙 hört zu …“ mit Pegel; erkannter Befehl blinkt kurz.
struct VoicePill: View {
    let voice: VoiceControl
    private let bars: [Float] = [0.5, 0.8, 1, 0.8, 0.5]

    var body: some View {
        HStack(spacing: 8) {
            Text("🎙")
            if let heard = voice.heard {
                Text("„\(heard)“").foregroundStyle(Theme.C.accent)
                    .phaseAnimator([1.0, 0.3, 1.0]) { view, phase in view.opacity(phase) }
            } else if let note = voice.note, !voice.listening {
                Text(note).lineLimit(2)
            } else {
                Text("hört zu …")
                HStack(spacing: 3) {
                    ForEach(bars.indices, id: \.self) { i in
                        Capsule().fill(Theme.C.accent).frame(width: 3, height: CGFloat(4 + 18 * voice.level * bars[i]))
                    }
                }
                .frame(height: 22)
                .animation(.easeOut(duration: 0.1), value: voice.level)
            }
        }
        .font(Theme.F.callout)
        .padding(.horizontal, 16).frame(minHeight: 44)
        .glass(Capsule())
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
              color: [Theme.C.accent, Theme.C.highlight, Theme.C.carbs, Theme.C.fat, Theme.C.protein, .white].randomElement()!)
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
