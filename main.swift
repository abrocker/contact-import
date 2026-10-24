import Cocoa
import Contacts

// MARK: - Model

struct ParsedContact {
    var givenName: String = ""
    var familyName: String = ""
    var jobTitle: String = ""
    var organization: String = ""
    var mobileNumber: String = ""
    var workNumber: String = ""
    var email: String = ""
    var website: String = ""
    var street: String = ""
    var postalCode: String = ""
    var city: String = ""
}

// MARK: - Parser

enum ClipboardParser {

    private static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < match.numberOfRanges, let r = Range(match.range(at: index), in: text) else { return nil }
        return String(text[r])
    }

    private static func isGermanMobile(_ number: String) -> Bool {
        var digits = number.filter { $0.isNumber }
        if digits.hasPrefix("49") { digits = String(digits.dropFirst(2)) }
        if digits.hasPrefix("0") { digits = String(digits.dropFirst(1)) }
        return digits.hasPrefix("15") || digits.hasPrefix("16") || digits.hasPrefix("17")
    }

    private static func assignPhone(_ number: String, to contact: inout ParsedContact) {
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if isGermanMobile(trimmed) {
            if contact.mobileNumber.isEmpty {
                contact.mobileNumber = trimmed
            } else if contact.workNumber.isEmpty {
                contact.workNumber = trimmed
            } else {
                contact.workNumber += " / " + trimmed
            }
        } else {
            if contact.workNumber.isEmpty {
                contact.workNumber = trimmed
            } else if contact.mobileNumber.isEmpty {
                contact.mobileNumber = trimmed
            } else {
                contact.workNumber += " / " + trimmed
            }
        }
    }

    static func parse(_ raw: String) -> ParsedContact {
        var contact = ParsedContact()

        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let mdLinkPattern = "\\[([^\\]]+)\\]\\(([^\\)]+)\\)"
        let plzPattern = "\\b(\\d{4,5})\\b\\s+([A-Za-zÀ-ÿ\\.\\-]+(?:\\s[A-Za-zÀ-ÿ\\.\\-]+)*)"
        let emailPattern = "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}"
        let urlPattern = "((https?://)?(www\\.)?[A-Z0-9-]+\\.[A-Z]{2,}(/[^\\s\\)]*)?)"
        let companySuffixPattern = "\\b(GmbH|AG|KG|UG|OHG|GbR|e\\.K\\.|Immobilien|Inh\\.|Immobilienmakler)\\b"
        let phoneKeywordPattern = "\\b(Telefon|Tel|Mobil|Fax|Phone)\\b"
        let emailKeywordPattern = "\\b(E-?Mail)\\b"
        let webKeywordPattern = "\\b(Website|Web|Internet)\\b"
        let phoneCharsPattern = "^[+0-9()\\-\\s/]{6,}$"

        for line in lines {
            var handled = false

            let links = matches(mdLinkPattern, in: line)

            // 1) Markdown links present: classify by href scheme first.
            if !links.isEmpty {
                var telDisplays: [String] = []
                var mailtoDisplay: String? = nil
                var httpDisplay: String? = nil

                for m in links {
                    guard let display = group(m, 1, in: line), let href = group(m, 2, in: line) else { continue }
                    let lowerHref = href.lowercased()
                    if lowerHref.hasPrefix("tel:") {
                        telDisplays.append(display)
                    } else if lowerHref.hasPrefix("mailto:") {
                        if mailtoDisplay == nil { mailtoDisplay = display }
                    } else if lowerHref.hasPrefix("http") {
                        if httpDisplay == nil { httpDisplay = display }
                    }
                }

                if !telDisplays.isEmpty {
                    for d in telDisplays {
                        for part in d.components(separatedBy: "/") {
                            assignPhone(part, to: &contact)
                        }
                    }
                    handled = true
                }
                if let mail = mailtoDisplay, contact.email.isEmpty {
                    contact.email = mail
                    handled = true
                }
                if let web = httpDisplay, contact.website.isEmpty {
                    contact.website = web
                    handled = true
                }
                if handled { continue }
            }

            // 2) Keyword / pattern based fallback for plain-text lines.

            if firstMatch(phoneKeywordPattern, in: line, options: .caseInsensitive) != nil
                || firstMatch(phoneCharsPattern, in: line) != nil {
                var rest = line
                if let colonRange = line.range(of: ":") {
                    rest = String(line[colonRange.upperBound...])
                }
                let candidates = rest.components(separatedBy: CharacterSet(charactersIn: "/,"))
                var any = false
                for c in candidates {
                    let digitCount = c.filter { $0.isNumber }.count
                    if digitCount >= 6 {
                        assignPhone(c, to: &contact)
                        any = true
                    }
                }
                if any { continue }
            }

            if contact.email.isEmpty,
               firstMatch(emailKeywordPattern, in: line, options: .caseInsensitive) != nil
                || firstMatch(emailPattern, in: line, options: .caseInsensitive) != nil {
                if let m = firstMatch(emailPattern, in: line, options: .caseInsensitive), let addr = group(m, 0, in: line) {
                    contact.email = addr
                    continue
                }
            }

            if contact.website.isEmpty,
               firstMatch(webKeywordPattern, in: line, options: .caseInsensitive) != nil
                || (firstMatch(urlPattern, in: line, options: .caseInsensitive) != nil && !line.contains("@")) {
                if let m = firstMatch(urlPattern, in: line, options: .caseInsensitive), let url = group(m, 0, in: line) {
                    contact.website = url
                    continue
                }
            }

            if let m = firstMatch(plzPattern, in: line) {
                if let plz = group(m, 1, in: line) {
                    contact.postalCode = plz
                }
                if let city = group(m, 2, in: line) {
                    contact.city = city.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                }
                if let range = Range(m.range, in: line) {
                    var street = String(line[..<range.lowerBound])
                    street = street.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                    if !street.isEmpty {
                        contact.street = street
                    }
                }
                continue
            }

            if line.contains("|") {
                let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    if contact.jobTitle.isEmpty { contact.jobTitle = parts[0] }
                    if contact.organization.isEmpty { contact.organization = parts[1] }
                    continue
                }
            }

            if contact.organization.isEmpty, firstMatch(companySuffixPattern, in: line, options: .caseInsensitive) != nil {
                contact.organization = line
                continue
            }

            if contact.givenName.isEmpty && contact.familyName.isEmpty {
                let parts = line.components(separatedBy: " ").filter { !$0.isEmpty }
                if parts.count >= 2 {
                    contact.givenName = parts.first ?? ""
                    contact.familyName = parts.dropFirst().joined(separator: " ")
                } else if !parts.isEmpty {
                    contact.givenName = parts[0]
                }
                continue
            }
        }

        return contact
    }
}

// MARK: - Address books

enum AddressBooks {
    struct Book {
        let identifier: String
        let name: String
    }

    private static let defaultsKey = "ContactImporterContainerIdentifier"

    static func isAuthorized() -> Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    /// Fragt bei Bedarf nach Kontakte-Zugriff; Completion läuft auf dem Main Thread.
    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        if isAuthorized() { completion(true); return }
        CNContactStore().requestAccess(for: .contacts) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Alle Adressbücher (Container), z. B. iCloud, Exchange, „Auf meinem Mac“.
    static func all() -> [Book] {
        guard isAuthorized(), let containers = try? CNContactStore().containers(matching: nil) else { return [] }
        return containers.map { Book(identifier: $0.identifier, name: displayName(for: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func displayName(for container: CNContainer) -> String {
        if !container.name.isEmpty { return container.name }
        switch container.type {
        case .local: return "Auf meinem Mac"
        case .exchange: return "Exchange"
        case .cardDAV: return "CardDAV"
        default: return "Adressbuch"
        }
    }

    static func defaultIdentifier() -> String? {
        guard isAuthorized() else { return nil }
        return CNContactStore().defaultContainerIdentifier()
    }

    /// Gewähltes Adressbuch; fällt auf das Standard-Adressbuch zurück, wenn das gespeicherte nicht mehr existiert.
    static var selectedIdentifier: String? {
        get {
            let books = all()
            if let saved = UserDefaults.standard.string(forKey: defaultsKey),
               books.contains(where: { $0.identifier == saved }) {
                return saved
            }
            return defaultIdentifier()
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }
}

// MARK: - Save to Contacts

enum ContactSaver {
    static func save(_ c: ParsedContact, containerIdentifier: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, error in
            DispatchQueue.main.async {
                guard granted else {
                    completion(.failure(error ?? NSError(domain: "ContactImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Zugriff auf Kontakte wurde nicht erlaubt. Bitte in Systemeinstellungen > Datenschutz & Sicherheit > Kontakte erlauben."])))
                    return
                }

                let mutable = CNMutableContact()
                mutable.givenName = c.givenName
                mutable.familyName = c.familyName
                mutable.organizationName = c.organization
                mutable.jobTitle = c.jobTitle

                var phones: [CNLabeledValue<CNPhoneNumber>] = []
                if !c.mobileNumber.isEmpty {
                    phones.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: c.mobileNumber)))
                }
                if !c.workNumber.isEmpty {
                    phones.append(CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: c.workNumber)))
                }
                mutable.phoneNumbers = phones

                if !c.email.isEmpty {
                    mutable.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: c.email as NSString)]
                }
                if !c.website.isEmpty {
                    mutable.urlAddresses = [CNLabeledValue(label: CNLabelWork, value: c.website as NSString)]
                }
                if !c.street.isEmpty || !c.postalCode.isEmpty || !c.city.isEmpty {
                    let addr = CNMutablePostalAddress()
                    addr.street = c.street
                    addr.postalCode = c.postalCode
                    addr.city = c.city
                    addr.country = "Deutschland"
                    mutable.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: addr)]
                }

                let saveRequest = CNSaveRequest()
                saveRequest.add(mutable, toContainerWithIdentifier: containerIdentifier)
                do {
                    try store.execute(saveRequest)
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
}

// MARK: - Design (iOS-27-/Liquid-Glass-Stil)

enum Theme {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    /// Hintergrund wie bei gruppierten iOS-Listen.
    static let groupedBackground = dynamic(light: NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 1),
                                           dark: NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1))
    static let card = dynamic(light: .white,
                              dark: NSColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1))
    static let cardRadius: CGFloat = 20
    static let rowHeight: CGFloat = 36
}

/// Abgerundete Fläche für gruppierte Inhalte.
final class CardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Theme.cardRadius
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Theme.card.cgColor
    }
}

/// Hintergrund der Fenster.
final class GroupedBackgroundView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Theme.groupedBackground.cgColor
    }
}

/// Runder Avatar mit Initialen wie in der Kontakte-App.
final class AvatarView: NSView {
    var initials: String = "" { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 64, height: 64) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: bounds)
        NSGradient(starting: NSColor(srgbRed: 0.66, green: 0.69, blue: 0.75, alpha: 1),
                   ending: NSColor(srgbRed: 0.53, green: 0.56, blue: 0.62, alpha: 1))?
            .draw(in: path, angle: -90)

        if initials.isEmpty {
            let config = NSImage.SymbolConfiguration(pointSize: bounds.height * 0.42, weight: .medium)
                .applying(.init(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let s = symbol.size
                symbol.draw(in: NSRect(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height))
            }
            return
        }

        let font = NSFont.systemFont(ofSize: bounds.height * 0.38, weight: .semibold)
        let roundedFont = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
        let attrs: [NSAttributedString.Key: Any] = [.font: roundedFont, .foregroundColor: NSColor.white]
        let text = initials as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

func glassButton(_ title: String, symbol: String? = nil, target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .glass
    button.controlSize = .large
    if let symbol = symbol {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
    }
    return button
}

func sectionHeader(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .secondaryLabelColor
    return label
}

func hairline() -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    box.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return box
}

/// Fenster mit transparenter Titelleiste und gruppiertem Hintergrund.
func makeModernWindow(title: String, size: NSSize) -> (NSWindow, NSView) {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false)
    window.title = title
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.level = .floating
    let background = GroupedBackgroundView(frame: NSRect(origin: .zero, size: size))
    background.wantsLayer = true
    window.contentView = background
    return (window, background)
}

// MARK: - Editor window

final class EditorWindowController: NSWindowController, NSTextFieldDelegate, NSTextViewDelegate {
    private var fields: [String: NSTextField] = [:]
    private var fieldKeysOrder: [String] = []
    /// Abschnitte mit (Schlüssel, Bezeichnung) – auch für das Kontextmenü.
    private var fieldSections: [(String, [(String, String)])] = []
    private var parsed: ParsedContact
    private var rawText: String
    private var clipboardTextView: NSTextView?
    private var addressBookPopup: NSPopUpButton?
    private let avatar = AvatarView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init(contact: ParsedContact, rawText: String) {
        self.parsed = contact
        self.rawText = rawText
        let (window, _) = makeModernWindow(title: "Kontakt prüfen", size: NSSize(width: 820, height: 700))
        super.init(window: window)
        buildUI()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func buildUI() {
        guard let window = window, let contentView = window.contentView else { return }

        // Titel
        let titleLabel = NSTextField(labelWithString: "Kontakt prüfen")
        titleLabel.font = NSFont.systemFont(ofSize: 26, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Text links markieren und per Rechtsklick oder ⊕ ins passende Feld übernehmen.")
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        // Linke Seite: Rohtext aus der Zwischenablage zum Markieren.
        let clipboardCard = CardView()
        let clipIcon = NSImageView(image: NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)!)
        clipIcon.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        clipIcon.contentTintColor = .controlAccentColor
        let clipTitle = sectionHeader("Zwischenablage")
        clipTitle.textColor = .labelColor
        let clipHeader = NSStackView(views: [clipIcon, clipTitle])
        clipHeader.spacing = 6

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.string = rawText
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        textView.defaultParagraphStyle = paragraph
        textView.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: (rawText as NSString).length))
        scrollView.documentView = textView
        textView.delegate = self
        self.clipboardTextView = textView

        for v in [clipHeader, scrollView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            clipboardCard.addSubview(v)
        }
        NSLayoutConstraint.activate([
            clipHeader.topAnchor.constraint(equalTo: clipboardCard.topAnchor, constant: 16),
            clipHeader.leadingAnchor.constraint(equalTo: clipboardCard.leadingAnchor, constant: 16),
            scrollView.topAnchor.constraint(equalTo: clipHeader.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: clipboardCard.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: clipboardCard.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: clipboardCard.bottomAnchor, constant: -12)
        ])

        // Rechte Seite: Kopf mit Avatar + gruppierte Formularfelder.
        nameLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        let nameStack = NSStackView(views: [nameLabel, subtitleLabel])
        nameStack.orientation = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 2
        for label in [nameLabel, subtitleLabel] {
            label.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let header = NSStackView(views: [avatar, nameStack])
        header.spacing = 14
        header.alignment = .centerY

        let sections: [(String, [(String, String, String)])] = [
            ("Person", [
                ("given", "Vorname", parsed.givenName),
                ("family", "Nachname", parsed.familyName),
                ("org", "Firma", parsed.organization),
                ("title", "Position", parsed.jobTitle)
            ]),
            ("Kontakt", [
                ("mobile", "Mobil", parsed.mobileNumber),
                ("work", "Telefon", parsed.workNumber),
                ("email", "E-Mail", parsed.email),
                ("website", "Website", parsed.website)
            ]),
            ("Adresse", [
                ("street", "Straße", parsed.street),
                ("zip", "PLZ", parsed.postalCode),
                ("city", "Ort", parsed.city)
            ])
        ]
        fieldSections = sections.map { ($0.0, $0.1.map { ($0.0, $0.1) }) }

        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 6
        form.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
        form.setCustomSpacing(18, after: header)

        for (title, rows) in sections {
            let headerLabel = sectionHeader(title)
            form.addArrangedSubview(headerLabel)
            let card = makeSectionCard(rows: rows)
            form.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
            form.setCustomSpacing(16, after: card)
            headerLabel.leadingAnchor.constraint(equalTo: form.leadingAnchor, constant: 16).isActive = true
        }

        // Adressbuch-Auswahl nur, wenn es mehrere gibt.
        let books = AddressBooks.all()
        if books.count > 1 {
            let headerLabel = sectionHeader("Speichern in")
            form.addArrangedSubview(headerLabel)
            headerLabel.leadingAnchor.constraint(equalTo: form.leadingAnchor, constant: 16).isActive = true
            let card = makeAddressBookCard(books: books)
            form.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
        }

        // Buttons
        let cancelButton = glassButton("Abbrechen", target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = glassButton("Sichern", symbol: "checkmark", target: self, action: #selector(saveTapped))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelColor = .controlAccentColor
        let buttonRow = NSStackView(views: [NSView(), cancelButton, saveButton])
        buttonRow.spacing = 10

        for v in [titleLabel, subtitle, clipboardCard, form, buttonRow] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            clipboardCard.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 20),
            clipboardCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            clipboardCard.widthAnchor.constraint(equalToConstant: 300),
            clipboardCard.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -16),

            form.topAnchor.constraint(equalTo: clipboardCard.topAnchor),
            form.leadingAnchor.constraint(equalTo: clipboardCard.trailingAnchor, constant: 20),
            form.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            form.widthAnchor.constraint(equalToConstant: 440),

            buttonRow.topAnchor.constraint(greaterThanOrEqualTo: form.bottomAnchor, constant: 4),
            buttonRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        window.setContentSize(contentView.fittingSize)
        updateHeader()
    }

    private func makeAddressBookCard(books: [AddressBooks.Book]) -> NSView {
        let card = CardView()
        card.heightAnchor.constraint(equalToConstant: Theme.rowHeight + 4).isActive = true

        let labelField = NSTextField(labelWithString: "Adressbuch")
        labelField.font = NSFont.systemFont(ofSize: 13)
        labelField.textColor = .secondaryLabelColor

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.isBordered = false
        popup.font = NSFont.systemFont(ofSize: 14)
        let selected = AddressBooks.selectedIdentifier
        for book in books {
            popup.addItem(withTitle: book.name)
            popup.lastItem?.representedObject = book.identifier
            if book.identifier == selected { popup.select(popup.lastItem) }
        }
        popup.target = self
        popup.action = #selector(addressBookChanged(_:))
        addressBookPopup = popup

        for v in [labelField, popup] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(v)
        }
        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            labelField.widthAnchor.constraint(equalToConstant: 76),
            labelField.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            popup.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 4),
            popup.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -12),
            popup.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        return card
    }

    @objc private func addressBookChanged(_ sender: NSPopUpButton) {
        AddressBooks.selectedIdentifier = sender.selectedItem?.representedObject as? String
    }

    private func makeSectionCard(rows: [(String, String, String)]) -> NSView {
        let card = CardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -2),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        for (i, (key, label, value)) in rows.enumerated() {
            let row = makeRow(key: key, label: label, value: value)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if i < rows.count - 1 {
                let line = hairline()
                stack.addArrangedSubview(line)
                line.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 16).isActive = true
                line.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
            }
        }
        return card
    }

    private func makeRow(key: String, label: String, value: String) -> NSView {
        let row = NSView()
        row.heightAnchor.constraint(equalToConstant: Theme.rowHeight).isActive = true

        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.systemFont(ofSize: 13)
        labelField.textColor = .secondaryLabelColor

        let textField = NSTextField(string: value)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.placeholderString = label
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        textField.delegate = self
        fields[key] = textField

        let assignButton = NSButton(image: NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Übernehmen")!,
                                    target: self, action: #selector(assignTapped(_:)))
        assignButton.isBordered = false
        assignButton.symbolConfiguration = .init(pointSize: 17, weight: .regular)
        assignButton.contentTintColor = .controlAccentColor
        assignButton.tag = fieldKeysOrder.count
        assignButton.toolTip = "Markierten Text aus der Zwischenablage übernehmen"
        fieldKeysOrder.append(key)

        for v in [labelField, textField, assignButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(v)
        }
        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            labelField.widthAnchor.constraint(equalToConstant: 76),
            labelField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textField.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: assignButton.leadingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            assignButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            assignButton.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func value(_ key: String) -> String {
        fields[key]?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private func updateHeader() {
        let given = value("given"), family = value("family"), org = value("org"), title = value("title")
        let name = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        nameLabel.stringValue = name.isEmpty ? (org.isEmpty ? "Neuer Kontakt" : org) : name
        subtitleLabel.stringValue = name.isEmpty ? "" : [title, org].filter { !$0.isEmpty }.joined(separator: " · ")
        subtitleLabel.isHidden = subtitleLabel.stringValue.isEmpty
        let initials = [given, family].compactMap { $0.first.map(String.init) }.joined().uppercased()
        avatar.initials = initials
    }

    func controlTextDidChange(_ obj: Notification) {
        updateHeader()
    }

    @objc private func assignTapped(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < fieldKeysOrder.count else { return }
        assignSelection(to: fieldKeysOrder[sender.tag])
    }

    /// Übernimmt den markierten Text der Zwischenablage in das Feld `key`.
    private func assignSelection(to key: String) {
        guard let textView = clipboardTextView else { return }
        let range = textView.selectedRange()
        let ns = textView.string as NSString
        guard range.length > 0, range.location + range.length <= ns.length else {
            NSSound.beep()
            return
        }
        let selected = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else {
            NSSound.beep()
            return
        }
        fields[key]?.stringValue = selected
        updateHeader()
    }

    // MARK: Kontextmenü der Zwischenablage

    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        // Ohne Markierung (oder Klick außerhalb) die angeklickte Zeile markieren.
        let selection = view.selectedRange()
        let clickedInSelection = selection.length > 0 && NSLocationInRange(charIndex, selection)
        if !clickedInSelection, charIndex < (view.string as NSString).length {
            var line = (view.string as NSString).lineRange(for: NSRange(location: charIndex, length: 0))
            line = trimmedRange(line, in: view.string as NSString)
            guard line.length > 0 else { return menu }
            view.setSelectedRange(line)
        }

        let selectedText = (view.string as NSString).substring(with: view.selectedRange())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else { return menu }

        let preview = selectedText.count > 30 ? String(selectedText.prefix(30)) + "…" : selectedText
        var items: [NSMenuItem] = [NSMenuItem.sectionHeader(title: "„\(preview)“ übernehmen als")]
        for (section, rows) in fieldSections {
            items.append(NSMenuItem.sectionHeader(title: section))
            for (key, label) in rows {
                let item = NSMenuItem(title: label, action: #selector(assignFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = key
                item.indentationLevel = 1
                let current = fields[key]?.stringValue ?? ""
                if !current.isEmpty { item.toolTip = "Aktuell: \(current)" }
                items.append(item)
            }
        }
        items.append(.separator())
        for (i, item) in items.enumerated() { menu.insertItem(item, at: i) }
        return menu
    }

    @objc private func assignFromMenu(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        assignSelection(to: key)
    }

    /// Kürzt einen Bereich um führende/abschließende Leerzeichen und Zeilenumbrüche.
    private func trimmedRange(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location, end = range.location + range.length
        let ws = CharacterSet.whitespacesAndNewlines
        while start < end, let s = UnicodeScalar(text.character(at: start)), ws.contains(s) { start += 1 }
        while end > start, let s = UnicodeScalar(text.character(at: end - 1)), ws.contains(s) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    @objc private func cancelTapped() {
        window?.close()
    }

    @objc private func saveTapped() {
        var c = ParsedContact()
        c.givenName = fields["given"]?.stringValue ?? ""
        c.familyName = fields["family"]?.stringValue ?? ""
        c.organization = fields["org"]?.stringValue ?? ""
        c.jobTitle = fields["title"]?.stringValue ?? ""
        c.mobileNumber = fields["mobile"]?.stringValue ?? ""
        c.workNumber = fields["work"]?.stringValue ?? ""
        c.email = fields["email"]?.stringValue ?? ""
        c.website = fields["website"]?.stringValue ?? ""
        c.street = fields["street"]?.stringValue ?? ""
        c.postalCode = fields["zip"]?.stringValue ?? ""
        c.city = fields["city"]?.stringValue ?? ""

        guard !c.givenName.isEmpty || !c.familyName.isEmpty || !c.organization.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Kein Name erkannt"
            alert.informativeText = "Bitte mindestens Vor- oder Nachname eingeben."
            alert.runModal()
            return
        }

        let containerIdentifier = addressBookPopup?.selectedItem?.representedObject as? String ?? AddressBooks.selectedIdentifier
        ContactSaver.save(c, containerIdentifier: containerIdentifier) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.window?.close()
                    let alert = NSAlert()
                    alert.messageText = "Kontakt gespeichert"
                    alert.informativeText = "\(c.givenName) \(c.familyName) wurde in die Kontakte-App gespeichert."
                    alert.runModal()
                case .failure(let error):
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Fehler beim Speichern"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }
}

// MARK: - Global hot key

final class HotKeyManager {
    static let shared = HotKeyManager()

    var action: (() -> Void)?

    private var monitor: Any?
    private var targetKeyCode: UInt16?
    private var targetModifiers: NSEvent.ModifierFlags = []
    private let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    private init() {}

    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        unregister()
        targetKeyCode = keyCode
        targetModifiers = modifiers.intersection(relevantModifiers)

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    func unregister() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        targetKeyCode = nil
    }

    private func handle(_ event: NSEvent) {
        guard let targetKeyCode = targetKeyCode else { return }
        guard event.keyCode == targetKeyCode else { return }
        guard event.modifierFlags.intersection(relevantModifiers) == targetModifiers else { return }
        action?()
    }
}

// MARK: - Shortcut display helpers

private let keyCodeLabels: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
    11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
    18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
    24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
    30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
    37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
    43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
    49: "Leertaste", 36: "Return", 48: "Tab", 51: "⌫", 53: "⎋",
    123: "←", 124: "→", 125: "↓", 126: "↑"
]

func keyDisplayName(for keyCode: UInt16) -> String {
    return keyCodeLabels[keyCode] ?? "Taste \(keyCode)"
}

func shortcutDisplayString(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
    var s = ""
    if flags.contains(.control) { s += "⌃" }
    if flags.contains(.option) { s += "⌥" }
    if flags.contains(.shift) { s += "⇧" }
    if flags.contains(.command) { s += "⌘" }
    s += keyDisplayName(for: keyCode)
    return s
}

// MARK: - Shortcut recorder

final class ShortcutRecorderView: NSView {
    var onCapture: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let flags = event.modifierFlags.intersection(relevant)
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
            NSSound.beep()
            return
        }
        onCapture?(event.keyCode, flags)
    }
}

/// Zerlegt "⌃⌥⌘K" in einzelne Tasten für die Tastenkappen-Anzeige.
func shortcutParts(_ display: String) -> [String] {
    var parts: [String] = []
    var rest = Substring(display)
    while let first = rest.first, "⌃⌥⇧⌘".contains(first) {
        parts.append(String(first))
        rest = rest.dropFirst()
    }
    if !rest.isEmpty { parts.append(String(rest)) }
    return parts
}

final class ShortcutRecorderWindowController: NSWindowController {
    private var recorderView: ShortcutRecorderView!
    private let keycapStack = NSStackView()
    private var pendingKeyCode: UInt16?
    private var pendingFlags: NSEvent.ModifierFlags?

    var onSave: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onClear: (() -> Void)?

    convenience init(currentDisplay: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Tastenkürzel festlegen"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        self.init(window: window)
        buildUI(currentDisplay: currentDisplay)
        window.center()
    }

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func buildUI(currentDisplay: String) {
        guard let window = window else { return }
        let contentView = ShortcutRecorderView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        contentView.wantsLayer = true
        self.recorderView = contentView

        let background = GroupedBackgroundView()
        background.wantsLayer = true

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        let icon = NSImageView(image: NSImage(systemSymbolName: "command", accessibilityDescription: nil)!
            .withSymbolConfiguration(iconConfig)!)
        let iconBadge = NSView()
        iconBadge.wantsLayer = true
        iconBadge.layer?.cornerRadius = 16
        iconBadge.layer?.cornerCurve = .continuous
        iconBadge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.addSubview(icon)

        let title = NSTextField(labelWithString: "Tastenkürzel")
        title.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        let hint = NSTextField(wrappingLabelWithString: "Drücke die gewünschte Tastenkombination mit ⌘, ⌥ oder ⌃.")
        hint.font = NSFont.systemFont(ofSize: 13)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        keycapStack.spacing = 8
        showKeycaps(shortcutParts(currentDisplay))

        let clearButton = glassButton("Entfernen", symbol: "trash", target: self, action: #selector(clearTapped))
        clearButton.contentTintColor = .systemRed
        let cancelButton = glassButton("Abbrechen", target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = glassButton("Übernehmen", target: self, action: #selector(saveTapped))
        saveButton.bezelColor = .controlAccentColor
        let buttonRow = NSStackView(views: [clearButton, NSView(), cancelButton, saveButton])
        buttonRow.spacing = 10

        for v in [background, iconBadge, title, hint, keycapStack, buttonRow] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: contentView.topAnchor),
            background.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            background.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            iconBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40),
            iconBadge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconBadge.widthAnchor.constraint(equalToConstant: 56),
            iconBadge.heightAnchor.constraint(equalToConstant: 56),
            icon.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),

            title.topAnchor.constraint(equalTo: iconBadge.bottomAnchor, constant: 12),
            title.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            hint.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            hint.widthAnchor.constraint(lessThanOrEqualToConstant: 320),

            keycapStack.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 22),
            keycapStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            keycapStack.heightAnchor.constraint(equalToConstant: 48),

            buttonRow.topAnchor.constraint(equalTo: keycapStack.bottomAnchor, constant: 28),
            buttonRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        recorderView.onCapture = { [weak self] keyCode, flags in
            self?.pendingKeyCode = keyCode
            self?.pendingFlags = flags
            self?.showKeycaps(shortcutParts(shortcutDisplayString(keyCode: keyCode, flags: flags)))
        }

        window.contentView = contentView
        window.setContentSize(contentView.fittingSize)
    }

    /// Zeigt jede Taste als Glas-Tastenkappe.
    private func showKeycaps(_ parts: [String]) {
        keycapStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !parts.isEmpty else {
            let empty = NSTextField(labelWithString: "Kein Tastenkürzel")
            empty.font = NSFont.systemFont(ofSize: 15, weight: .medium)
            empty.textColor = .tertiaryLabelColor
            keycapStack.addArrangedSubview(empty)
            return
        }

        for part in parts {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 12
            let label = NSTextField(labelWithString: part)
            label.font = NSFont.systemFont(ofSize: 20, weight: .medium)
            label.alignment = .center
            let holder = NSView()
            label.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: holder.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -12)
            ])
            glass.contentView = holder
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.heightAnchor.constraint(equalToConstant: 48).isActive = true
            glass.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            keycapStack.addArrangedSubview(glass)
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(recorderView)
    }

    @objc private func clearTapped() {
        onClear?()
        window?.close()
    }

    @objc private func cancelTapped() {
        window?.close()
    }

    @objc private func saveTapped() {
        guard let keyCode = pendingKeyCode, let flags = pendingFlags else {
            NSSound.beep()
            return
        }
        onSave?(keyCode, flags)
        window?.close()
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var editorController: EditorWindowController?
    var shortcutRecorderController: ShortcutRecorderWindowController?
    var hotKeyMenuItem: NSMenuItem!
    var addressBookMenuItem: NSMenuItem!

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu, let submenu = addressBookMenuItem.submenu else { return }
        let books = AddressBooks.all()
        addressBookMenuItem.isHidden = books.count < 2
        submenu.removeAllItems()
        let selected = AddressBooks.selectedIdentifier
        for book in books {
            let item = NSMenuItem(title: book.name, action: #selector(selectAddressBook(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = book.identifier
            item.state = book.identifier == selected ? .on : .off
            submenu.addItem(item)
        }
    }

    @objc func selectAddressBook(_ sender: NSMenuItem) {
        AddressBooks.selectedIdentifier = sender.representedObject as? String
    }

    private let hotKeyCodeDefaultsKey = "ContactImporterHotKeyCode"
    private let hotKeyModifiersDefaultsKey = "ContactImporterHotKeyModifiers"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "person.crop.circle.badge.plus", accessibilityDescription: "Kontakt aus Zwischenablage")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let createItem = NSMenuItem(title: "Aus Zwischenablage erstellen", action: #selector(createFromClipboard), keyEquivalent: "")
        createItem.target = self
        createItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(createItem)
        self.hotKeyMenuItem = createItem

        let shortcutItem = NSMenuItem(title: "Tastenkürzel festlegen…", action: #selector(showShortcutRecorder), keyEquivalent: "")
        shortcutItem.target = self
        shortcutItem.image = NSImage(systemSymbolName: "command", accessibilityDescription: nil)
        menu.addItem(shortcutItem)

        // Untermenü wird beim Öffnen befüllt; ausgeblendet bei nur einem Adressbuch.
        let addressBookItem = NSMenuItem(title: "Adressbuch", action: nil, keyEquivalent: "")
        addressBookItem.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: nil)
        addressBookItem.submenu = NSMenu()
        menu.addItem(addressBookItem)
        self.addressBookMenuItem = addressBookItem
        menu.delegate = self

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu

        HotKeyManager.shared.action = { [weak self] in
            self?.createFromClipboard()
        }

        loadSavedHotKey()
    }

    private func loadSavedHotKey() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: hotKeyCodeDefaultsKey) != nil {
            let keyCode = UInt16(defaults.integer(forKey: hotKeyCodeDefaultsKey))
            let rawFlags = UInt(defaults.integer(forKey: hotKeyModifiersDefaultsKey))
            let flags = NSEvent.ModifierFlags(rawValue: rawFlags)
            applyHotKey(keyCode: keyCode, flags: flags, persist: false)
        } else {
            updateHotKeyMenuTitle(display: nil)
        }
    }

    private func applyHotKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, persist: Bool) {
        HotKeyManager.shared.register(keyCode: keyCode, modifiers: flags)
        updateHotKeyMenuTitle(display: shortcutDisplayString(keyCode: keyCode, flags: flags))
        if persist {
            let defaults = UserDefaults.standard
            defaults.set(Int(keyCode), forKey: hotKeyCodeDefaultsKey)
            defaults.set(Int(flags.rawValue), forKey: hotKeyModifiersDefaultsKey)
        }
    }

    private func clearHotKey() {
        HotKeyManager.shared.unregister()
        UserDefaults.standard.removeObject(forKey: hotKeyCodeDefaultsKey)
        UserDefaults.standard.removeObject(forKey: hotKeyModifiersDefaultsKey)
        updateHotKeyMenuTitle(display: nil)
    }

    private func updateHotKeyMenuTitle(display: String?) {
        if let display = display, !display.isEmpty {
            hotKeyMenuItem.title = "Aus Zwischenablage erstellen (\(display))"
        } else {
            hotKeyMenuItem.title = "Aus Zwischenablage erstellen"
        }
    }

    @objc func showShortcutRecorder() {
        let currentTitle = hotKeyMenuItem.title
        var currentDisplay = ""
        if let openParen = currentTitle.firstIndex(of: "("), let closeParen = currentTitle.lastIndex(of: ")") {
            currentDisplay = String(currentTitle[currentTitle.index(after: openParen)..<closeParen])
        }

        let controller = ShortcutRecorderWindowController(currentDisplay: currentDisplay)
        controller.onSave = { [weak self] keyCode, flags in
            self?.applyHotKey(keyCode: keyCode, flags: flags, persist: true)
        }
        controller.onClear = { [weak self] in
            self?.clearHotKey()
        }
        self.shortcutRecorderController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func createFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Zwischenablage leer"
            alert.informativeText = "Kopiere zuerst einen Kontakt-Text und versuche es erneut."
            alert.runModal()
            return
        }
        // Zugriff vorab anfragen, damit der Editor die Adressbücher kennt.
        AddressBooks.requestAccess { [weak self] _ in
            let parsed = ClipboardParser.parse(text)
            let controller = EditorWindowController(contact: parsed, rawText: text)
            self?.editorController = controller
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
