# Privacy and copyright self-check before going public

A travel app naturally holds a lot of private information: who is traveling with whom, where you stay, where you are on which day, orders, IDs, server addresses. This template itself contains no real trip data; but as you build your own app with it, the repository will gradually fill up with this kind of information. Recommendations:

- **Keep your trip repository private.** When you want to share with friends, share TestFlight, not the repository.
- If you want to contribute improvements back to the template, or make your own version public, go through this document first.

## 1. Things you should never commit

| Content | Where it goes |
| --- | --- |
| Apple Team ID, your own Bundle ID | `ios/Signing.xcconfig` (ignored) |
| Backend URL, shared key | `ios/SharedAccess.xcconfig` (ignored) |
| Generated Xcode project (records the Team ID) | `ios/*.xcodeproj` (ignored; generate it with `xcodegen`) |
| APNs `.p8` key, server environment variables | Only on the server, e.g. `/etc/trip-journal*.env` |
| Databases, backups, original ticket files | Server or a private directory on your machine |
| ID numbers, order numbers, confirmation numbers, phone numbers, home address | Don't write them into any file; original ticket files are kept only inside the app |

## 2. Private information that's easy to miss

- Real names, nicknames, pet names between partners; GitHub usernames, email addresses.
- Departure city, the airport near your home; flight number + date (together they can identify a person); amounts actually paid.
- Local paths (home directory paths containing your username), external drive paths, device names.
- Server IPs, domains, secret paths, ports; App Store Connect app IDs, build UUIDs.
- Screenshots, logs and receipts in process notes (they often carry all of the above).
- Test passphrases and sample accounts (don't use real numbers such as birthdays or departure dates).
- **Git history**: deleting a file doesn't delete its history. Before turning a private repository public, the safest approach is to commit the files you want to publish into a clean new repository (this template was produced that way), rather than deleting and editing in the old one.

## 3. Copyright and licensing

| Material | What to do in a public repository |
| --- | --- |
| Images and text of social media posts (Xiaohongshu, etc.) | Don't include them without the author's permission; keep only the title, author, link and your own summary |
| Hotel / booking platform images, quote screenshots | Don't include them |
| Images from official websites (marked All Rights Reserved) | Don't include them |
| Openly licensed photos (Wikimedia Commons, etc.) | OK; you must keep the author, license and source; crops/thumbnails of CC BY-SA images are derivative works and likewise require attribution and share-alike |
| OpenStreetMap data | OK; credit © OpenStreetMap contributors (ODbL) |
| Photos you took, text you wrote | OK; stating an explicit license is recommended |

## 4. Automated check: `scripts/privacy_check.py`

The script scans every file that would be published (tracked + new files that aren't ignored), and can optionally scan the entire Git history:

- Built-in rules: private keys, common API tokens, local paths, public IPv4 addresses, email addresses, files over 1 MB (3 MB for README images under `docs/assets/`).
- Your private word list: create `.privacy-denylist` at the repository root (already ignored by git), one regex per line, listing strings you don't want to appear:

```text
# Names, nicknames, usernames
John Doe
johndoe
# Cities, flights, dates
Shanghai
MU ?1234
2031-04-
# Servers and accounts
my-domain\.com
203\.0\.113\.7
ABCDE12345
```

Run:

```bash
python3 scripts/privacy_check.py            # working tree
python3 scripts/privacy_check.py --history  # plus all commit history and commit authors
```

Only go public once it prints `PASS`. The script can only find what you tell it about and common patterns; finally, read through the `git diff`, the docs and the images yourself.

## 5. Commit identity

A public repository exposes the author name and email of every commit. Use the noreply email GitHub provides (`<id>+<username>@users.noreply.github.com`), set within the repository:

```bash
git config user.email "<id>+<username>@users.noreply.github.com"
```
