<p align="center">
  <img src="docs/icon.png" width="128" alt="Kontakt-Import icon">
</p>

# Kontakt-Import

**English** · [Deutsch](README.de.md)

A small macOS menu bar app that turns copied contact details (for example an
email signature) into a contact in the Contacts app. Copy the text, press your
shortcut or click the menu bar icon, check the detected fields and save.

<p align="center">
  <img src="docs/screenshot.png" width="720" alt="The “Kontakt prüfen” window with sample data">
</p>

The app's interface is in German. Its parser is tuned for German signatures,
such as this one:

```
Max Mustermann
Geschäftsführer | Mustermann Immobilien GmbH
Telefon: [+49 171 1234567](tel:+491711234567) / [+49 89 123456](tel:+4989123456)
E-Mail: [max@mustermann-immo.de](mailto:max@mustermann-immo.de)
Website: [www.mustermann-immo.de](https://www.mustermann-immo.de)
Hauptstraße 12, 80331 München
```

Missing lines are fine, and plain text without Markdown links
(`Telefon: 0171 …` instead of `[…](tel:…)`) is detected too.

## Download

The ready-made app is available as `ContactImporter.zip` under
[Releases](https://github.com/abrocker/contact-import/releases/latest).
After unzipping, see [Install](#install).

## Features

- **Automatic detection** of name, company, job title, phone and mobile
  number, email, website and postal address
- **Review before saving** in a window showing the original text on the left
  and the detected fields on the right
- **Fill fields by selecting and right-clicking:** select text on the left,
  right-click and choose the target field. Without a selection, a right-click
  uses the whole line you clicked on.
- **Choose the address book** when there is more than one (iCloud, Exchange,
  “On My Mac” …)
- **Global keyboard shortcut** that opens the import from any app
- macOS 26/27 Liquid Glass design, light and dark mode

## Requirements

- macOS 26 or later (the glass effects only exist from that version on)
- Apple silicon or Intel Mac
- To build: Xcode or the Command Line Tools with the macOS 26 SDK or later
  (`xcode-select --install`)

## Build

```bash
git clone https://github.com/abrocker/contact-import.git
cd contact-import
./build.sh
```

The script

1. compiles `main.swift` for Apple silicon and Intel and combines both into a
   universal binary,
2. builds `ContactImporter.app` including the icon,
3. ad-hoc signs the app (without this signature, macOS reports the app as
   “damaged” on other Macs),
4. packs it as `ContactImporter.zip` for sharing.

## Install

```bash
mv ContactImporter.app /Applications/
```

The app is only ad-hoc signed, not signed with an Apple developer certificate,
and not notarized. On the Mac that built it, it starts right away. On other
Macs, Gatekeeper blocks the first launch:

1. Unzip `ContactImporter.zip` and move the app to `/Applications`.
2. Remove the quarantine flag once in Terminal:
   ```bash
   xattr -cr /Applications/ContactImporter.app
   ```
   Alternatively, try to open the app once, then click **Open Anyway** under
   **System Settings → Privacy & Security**.

The app has no Dock icon. It runs from the person icon in the menu bar, and
you quit it there with **Beenden**.

## Permissions

| Permission | Used for | Where to set it |
|---|---|---|
| Contacts | Listing address books and saving contacts. macOS asks on the first import. | System Settings → Privacy & Security → Contacts |
| Accessibility | Only for the global shortcut. Without it the shortcut does nothing, but the menu bar icon still works. | System Settings → Privacy & Security → Accessibility → turn on ContactImporter (if it's missing, add it with **+**) |

## Usage

1. Copy the contact text.
2. Press your shortcut, or choose **Aus Zwischenablage erstellen** (create
   from clipboard) in the menu bar menu.
3. Check the detected fields in the **Kontakt prüfen** (review contact)
   window. The header with avatar and name shows live what the contact will
   look like.
4. Fix fields that are wrong or missing:
   - type directly into the field,
   - select text on the left, **right-click** and choose the target field,
   - or select text on the left and click **⊕** in the matching row.
5. If you have several address books, pick the target under **Speichern in**
   (save to).
6. **Sichern** (save, Return) saves the contact, **Abbrechen** (cancel, Esc)
   discards it.

### Choosing the address book

If there is more than one address book, you can choose it in two places:

- in the menu bar menu under **Adressbuch** (the current one is checked),
- in the **Kontakt prüfen** window under **Speichern in**.

Both share the same setting, and the app remembers it across restarts. If the
chosen address book no longer exists, the app uses the macOS default. With
only one address book, the choice stays hidden.

### Setting the shortcut

Choose **Tastenkürzel festlegen…** (set shortcut) in the menu bar menu, press
the combination you want (with at least ⌘, ⌥ or ⌃) and click **Übernehmen**
(apply). **Entfernen** (remove) deletes the shortcut. The current shortcut is
shown in the menu next to **Aus Zwischenablage erstellen**.

## What gets detected

- **Name:** the first line that matches no other pattern. The first word
  becomes the first name, the rest the last name.
- **Job title | company:** in a line containing `|`, the left part is the job
  title and the right part the company.
- **Company** without `|` too, if the line contains terms such as “GmbH”,
  “AG”, “KG”, “UG”, “Immobilien” or “Inh.”.
- **Phone:** `tel:` links, lines with “Telefon”, “Tel”, “Mobil”, “Fax” or
  “Phone”, and lines consisting only of digits, `+`, `/` and spaces. Several
  numbers (separated by `/` or `,`) are split up: German mobile numbers
  (015x, 016x, 017x) go into **Mobil**, all others into **Telefon**.
- **Email:** `mailto:` links or the pattern `name@domain.tld`.
- **Website:** `http(s)` links or lines with “Website”, “Web” or “Internet”.
- **Address:** a line with a postal code (4–5 digits) and city. Everything
  before it becomes the street. The country is always set to “Deutschland”.

## Project structure

| File | Contents |
|---|---|
| `main.swift` | The whole app: parser, saving, windows, shortcut, menu |
| `Info.plist` | Bundle info, minimum macOS version, Contacts permission text |
| `build.sh` | Builds, signs and packs the app |
| `AppIcon.icns` | The app icon |
| `tools/make_icon.swift` | Draws the icon in code |
| `tools/make_icon.sh` | Generates `AppIcon.icns` and `docs/icon.png` from it |

## Customizing

The main places in `main.swift`:

- **Detection:** `enum ClipboardParser`. Add company terms to
  `companySuffixPattern`; phone number assignment lives in
  `assignPhone(_:to:)`.
- **Country of the address:** `ContactSaver.save`, line
  `addr.country = "Deutschland"`.
- **More fields:** extend `ParsedContact`, add the field to `sections` in
  `EditorWindowController.buildUI()` and read it in `saveTapped()`. The
  right-click menu picks up new fields automatically.
- **Colors and spacing:** `enum Theme`.
- **Icon:** edit `tools/make_icon.swift` and run `./tools/make_icon.sh`.

Run `./build.sh` again after every change.

## Known limitations

- Exactly two phone fields (mobile and phone) and exactly one address
- The country is fixed to “Deutschland”
- The interface is German only
- The app doesn't react to every copy on its own, only to a click or the
  shortcut. That's intentional.
- Without an Apple developer account there is no notarization, hence the
  one-time Gatekeeper step on other Macs

## License

[MIT](LICENSE)
