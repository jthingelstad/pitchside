# Distribution

Pitchside is in TestFlight for the Dev (internal) group only. It is not yet ready to
submit to the App Store. This file lists what a submission needs, what is done, and
what is left. Every upload, every tester group and the App Store are Jamie's call.
Nothing here has been sent to Apple: `scripts/testflight.sh` and `scripts/asc.swift`
are here for that day.

Read on 2026-11-26. "Ours" means work in this repository. "Jamie" means a step in App
Store Connect or the developer portal.

## Where the record stands (read 2026-11-26)

These came from GET calls to the App Store Connect API (`scripts/asc.swift`), with no
writes:

- **The app** exists: "Kubb: Pitchside", bundle id `com.throwingwood.pitchside`, primary
  language English (U.S.), not made for kids. The content rights declaration is not
  answered.
- **One App Store version, "1.0"**, in Prepare for Submission. It is set to release after
  approval. It has no build, no copyright, no screenshots, no review details and no
  review submission.
- **App information**: no subtitle, no privacy policy URL, no primary or secondary
  category, and no age rating answers.
- **Price and availability**: neither is set. The price schedule has the United States
  as its base, but no price, and no territories are chosen.
- **TestFlight**: Dev (internal, every build) has one tester. Beta (external) has none
  and its public link is off. Beta App Review details and the beta description are
  empty.
- **Builds**: nine (17 to 59, all `0.1`), all valid, all minimum iOS 26.0, all
  **internal only**. They were made by hand from the main checkout before this script
  existed. An internal-only build can never be added to the Beta group or to an App
  Store version. **Submission needs a new build uploaded with `--external`.**
- Build 59 says Apple will also offer it on Apple silicon Macs and Apple Vision Pro
  (iPhone apps run there unless the developer turns that off).

## Readiness

| Item | State | What is left, and whose |
| --- | --- | --- |
| App record and bundle id | Done | Nothing. |
| Signing | Done (automatic, team in a git-ignored file) | Ours: copy Throwing Wood's `Config/Signing.local.xcconfig` and `Config/AppStoreConnect.local` into this checkout. Jamie: the iCloud container below. |
| iCloud Drive folder (pull request 15) | Arriving | Jamie: register `iCloud.com.throwingwood.pitchside` and turn on iCloud (Documents) for the App ID before the first signed build that has the entitlements. Xcode's automatic signing can do it with Jamie's sign-in in Xcode. The API key cannot. |
| App icon | Done for submission | A single 1024 master with no alpha is enough. iOS makes the dark and tinted looks from it. Dedicated dark and tinted art is optional. The final icon is Jamie's call. |
| Launch screen | Done | `UILaunchScreen` (an empty one: the system background, then the app). |
| Display name | Done | "Kubb: Pitchside", 15 characters, shows in full under the icon. |
| Category | Done in the build (Sports) | Jamie: set Sports and a secondary in App Store Connect ("The listing"). |
| Privacy manifest | Done (this pull request) | `Pitchside/PrivacyInfo.xcprivacy` ("Required reasons"). |
| Export compliance | Done | `ITSAppUsesNonExemptEncryption` is false, so App Store Connect asks nothing. |
| Usage strings | Done (none needed) | The app asks for no camera, photos, contacts, location or microphone. The file picker, share sheet and print need none. |
| Orientations, full screen | Done | iPhone only, portrait plus landscape for the scorer. `UIRequiresFullScreen` matters only on iPad, and the app is iPhone only. |
| Accessibility | Done for submission | VoiceOver labels every piece on the pitch, the turn history and the counts. Text uses Dynamic Type, with stacked layouts at the accessibility sizes. Jamie may fill in Accessibility Nutrition Labels: optional, and only claim what was checked on a phone. |
| App Privacy | Ready to enter | Jamie: "Data Not Collected" ("App Privacy worksheet"). Web only. |
| Age rating | Ready to enter | Jamie: the worksheet below. Expect 4+. |
| Price and territories | Not set | Jamie: free, in every territory (as Throwing Wood). |
| Mac and Vision Pro | On by default | Jamie: recommended off for 1.0 (Pricing and Availability), as nobody has tried it there. |
| Content rights | Not answered | Jamie: "Yes, it contains third-party content", and confirm the rights ("Third-party content"). |
| App Compliance (China mainland) | Not answered | Jamie: no feature that needs a security assessment, and no AI-generated or synthetic content service. A new app cannot be submitted until both are answered. Web only. |
| Listing words and URLs | Drafted below | Jamie: approve them, then they go in with `scripts/asc.swift`. The pages at throwingwood.com/pitchside are another pull request's. |
| Screenshots | Done (`docs/store/`, six) | Retake after the scorer work lands ("Screenshots"). |
| Review notes | Drafted below | Jamie: a contact name, phone and email in App Review Information. |
| The version | `0.1` | Ours: set `VERSION` and the record's version to the same number before the external upload ("The version"). |
| A build for the App Store | None yet | Jamie's go, then `scripts/testflight.sh --external` from a new commit on main. |
| iOS 26.2 | Unverified on a phone | See "The iOS 26.2 simulator crash". One run on a phone with iOS 26 settles it. |

### Jamie's steps, in order

1. Approve the version number, then the listing words below.
2. Developer portal (or Xcode with Jamie signed in): the iCloud container on the App ID,
   once pull request 15 is merged.
3. App Store Connect, App Information: category, content rights, age rating, App
   Compliance (China).
4. App Privacy: "Data Not Collected", then Publish.
5. Pricing and Availability: free, all territories. Turn off Mac and Vision Pro.
6. The go for an external upload. Then `scripts/testflight.sh --external`.
7. The version page: the words, the URLs, the screenshots, the review notes and contact,
   and the build. Then Add for Review and Submit.

Steps 1 and 6 are Jamie's go. Steps 3 to 5 are web only. The rest of step 7 can be done
by us with `scripts/asc.swift`, once Jamie says so (`ASC_WRITE=1`).

## Internal testers

`scripts/testflight.sh` archives a clean commit on main and uploads it for the Dev
group only (`testFlightInternalTestingOnly` in `Config/ExportOptions-TestFlight.plist`).
The version is `VERSION`. The build number is the commit count, so a commit uploads
once.

Before the first run in a checkout, copy Throwing Wood's two local files into
`Config/`. They hold the same team and key. Git ignores both.

- `--dry-run` runs the checks and prints the plan, then stops.
- `--unsigned` builds a Release archive for a phone with no signing, and stops. It
  checks that the archive builds and prints its version.

## Outside testers and the App Store

`scripts/testflight.sh --external` makes a build the Beta group and the App Store can
take. It leaves out `testFlightInternalTestingOnly`. The Dev group sees it too. A commit
uploads once, so an external build needs a commit on main that has not been uploaded.

The Beta group also needs Beta App Review details (a contact, a beta description and a
feedback email) before its first build. The App Store does not need them.

`scripts/asc.swift` reads the record with GET. Any other method refuses unless
`ASC_WRITE=1` is set, and that is set only after Jamie says go.

## The iOS 26.2 simulator crash

**What happens.** On this Mac (macOS 27.2.1, Xcode 27.2), the iOS 26.2 simulator stops
Pitchside at launch. The crash is in JavaScriptCore, while the Notation reader loads
(`JSRopeString::resolveToBuffer` from `regExpProtoFuncSplitFast`, a bad memory access).
It happens on a plain launch, on a new simulator, and with the JIT off. The iOS 27.2
simulator and CI's iOS 26.2 simulator (on a macOS 26 runner) both pass.

**Why (inferred, high confidence).** The crash reports show a pointer that lost exactly
its top bits: the string's address was `0x70_3442_23e0`, and JavaScriptCore read
`0x0_3442_2390`. JavaScriptCore on iOS 26 keeps some string pointers in 36 bits, which
is all the address space an iPhone gives an app. The macOS 27 host puts the simulated
app's memory at about `0x70_0000_0000`, above 36 bits. So the iOS 26.2 simulator's own
JavaScriptCore cannot run on this host. It is not a fault in Pitchside or the vendored
reader: the same reader read all 150 archive games, without a crash, in a small test app
on the same simulator, whose memory sat lower.

**What would settle it.** A launch on a phone with iOS 26. Opening any TestFlight build
(59 is the newest) on such a phone and scoring one turn would do. CI's run on a macOS 26
host already shows the iOS 26.2 runtime is fine where its memory fits.

**A guard?** None worth adding. The crash is a bad memory access, which Swift cannot
catch. The reader is needed at launch, to read the saved games, so starting it later
would only move the crash. No code changed for it.

If a phone with iOS 26 ever does crash this way, the fallback is to set the minimum to
iOS 27. Pitchside asks for 26.0 today.

## Data that leaves the device

None, by Pitchside. It has no network code: no URLSession, no sockets, no CloudKit, no
analytics or ad SDK. The JavaScript the reader runs has no network access either. The
Home screen says so: "Pitchside sends nothing anywhere."

- **Games, notes and the roster** are files under Application Support on the phone.
- **Share** (the `.txt` file, the PDF) uses the system share sheet. The person picks
  where it goes. Pitchside never sees where.
- **Open file** reads a text file the person picks.
- **Print** uses the system print panel.
- **The iCloud Drive folder** (pull request 15): each finished game's text file is also
  copied to the person's own iCloud Drive (or to On My iPhone with iCloud Drive off). It
  holds team and player names. It is the person's own storage: Apple holds it, and the
  developer cannot read it. The roster stays on the phone.

## App Privacy worksheet

Answer **"No, we do not collect data from this app"**. App Store Connect then shows
"Data Not Collected".

Apple's definition: data is collected when it is sent off the device "in a way that
allows you and/or your third-party partners to access it for a period longer than
necessary to service the transmitted request in real time." Pitchside sends nothing to
us or to anyone working with us. What the share sheet sends goes where the person
chooses. The iCloud Drive copy goes to the person's own iCloud, which the developer
cannot read, the same as a document app saving to iCloud Drive. Neither one is data we
collect. No tracking. [Apple's privacy definitions](https://developer.apple.com/app-store/app-privacy-details/)

Check this again if Pitchside ever adds sign-in, feedback, a server, crash reporting
outside Apple's own, or CloudKit with a public database.

### Required reasons

`Pitchside/PrivacyInfo.xcprivacy` says no tracking, no collected data, and one
required-reason API:

- **File timestamp, `C617.1`.** `GameStore.needsReplay` reads `contentModificationDate`
  of the app's own game files, to see whether an export is older than its journal.
  Apple's `C617.1`: "access the timestamps, size, or other metadata of files inside the
  app container".

Nothing else in the app's code uses one. There is no UserDefaults or `@AppStorage`, no
system boot time, no disk space and no keyboard list. Lua's `os.clock` and `os.time`
are not on Apple's list, and the vendored musl maths does no file calls. JavaScriptCore
is Apple's own. Pull request 15 adds no API from the list. [Apple's required reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

## Age-rating worksheet

| Question group | Answer and why |
| --- | --- |
| User-generated content | No. Names and notes a person types stay on the phone. Nobody else sees them through the app: they leave only when the person shares a file. |
| Messaging and chat | No. |
| Contests | None. Pitchside keeps score of a game people play in real life. It runs no rankings, prizes or events. |
| Advertising, web access, social feed | None. |
| In-app controls | No parental controls or age checks. |
| Mature themes, violence, profanity, drugs, sexual content, horror | None. A baton knocks over wooden kubbs. |
| Medical, health and wellness | None. |
| Gambling, loot boxes | None. |

Expect 4+. The build makes no Kids Category claim. [Apple's rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)

## Third-party content

Pull request 16 bundles fourteen games from the Planet Kubb archive (pk-kubb-score,
unchanged), with the real names of the players, scorers, events and places from
2011 to 2015. Planet Kubb published its content under CC BY-SA. The 2012 post that says
so names no version. Each game shows a credit card (event, date, place, scorer, archive
file).

Answer the content rights question **"Yes, it contains, shows or accesses third-party
content"**, and **"Yes, I have the necessary rights"**. That is Jamie's call to make:
Jamie is an admin of the Planet-Kubb organisation, and the archive is public. Say so in
the review notes too.

## Export compliance

Nothing to answer: `ITSAppUsesNonExemptEncryption` is false. Pitchside has no network
code and no cryptography of its own.

## The listing

Words for Jamie to approve. Short, plain, kubb talk.

**Name** (15 of 30): Kubb: Pitchside

**Subtitle** (30 of 30): Tap the kubbs. Keep the score.

**Promotional text** (141 of 170): Take your phone to the pitch. Tap each kubb that
falls, and Pitchside keeps the score sheet for you, baton by baton, all the way to the
king.

**Description**:

> Kubb is the lawn game where you knock down the other side's wooden kubbs with
> batons, then topple the king. Pitchside keeps score while you play.
>
> Turn your phone on its side and the whole pitch is in front of you. After each
> baton, tap the kubbs that fell. Pitchside counts the batons, keeps the inkast and
> the field kubbs straight, and knows whose turn it is.
>
> When the king goes down, the game is a score sheet in Planet Kubb notation. Fix a
> throw you got wrong, print the sheet, or share it as a file. Open games someone
> else scored, read a game back throw by throw, and see how each player throws.
>
> Start with real games from the Planet Kubb archive, from US Nationals to a
> championship on Gotland.
>
> Your games and names stay on your phone. No sign-in, no ads, no tracking.

(The archive paragraph only if pull request 16 ships. With pull request 15, the last
line becomes: "Your games stay on your phone, with a copy of each finished game in
your own iCloud Drive. No sign-in, no ads, no tracking.")

**Keywords** (93 of 100): lawn game,score sheet,scorekeeper,baton,king,viking
chess,backyard,tournament,stats,yard game

The words of the name are already searched, so "kubb" and "pitchside" are left out.

**Categories**: Sports, then Utilities.

**What's New**: none. App Store Connect does not take it for the first version.

**Copyright**: 2026 Jamie Thingelstad

**URLs**:

- Marketing: `https://throwingwood.com/pitchside/`
- Support: `https://throwingwood.com/pitchside/support/`
- Privacy policy: `https://throwingwood.com/pitchside/privacy/`

**Review notes**:

> Pitchside is a scorekeeper for kubb, a lawn game played with wooden blocks and
> batons. There is no sign-in and no account, and the app makes no network
> connections.
>
> To try it: tap New game, add a player to each side (any names), tap Next: this game,
> then Start scoring. The scorer turns to landscape. Tap the kubbs a baton knocked
> down, then the button to finish the baton. The Games list also has real games from
> the Planet Kubb archive to open and read. Planet Kubb published them under CC BY-SA;
> the developer is an admin of the Planet Kubb project.
>
> Finished games are also copied as text files to the person's own iCloud Drive
> (Files, iCloud Drive, Pitchside). Nothing is sent to the developer.

Edit the steps if the scorer's buttons change before submission.

## Screenshots

Apple's specification (read 2026-11-26): the store needs at least one iPhone set. The
6.9-inch sizes are 1320 x 2868 (or 1290 x 2796, 1260 x 2736) and their landscape
sizes. Smaller iPhones use scaled 6.9-inch pictures when they have none of their own.
One to ten a set, PNG or JPEG, no transparency. The app is iPhone only, so no iPad set.
Apple's page says nothing against portrait and landscape in one set, and the store shows
them as they are. Throwing Wood was approved with one 6.9-inch set. If App Store Connect
asks for a 6.3-inch set too, run the script on a 6.3-inch simulator.

`scripts/store-shots.sh` takes the set from the DEBUG demo games (invented names only)
on the newest iPhone Pro Max simulator. It writes `docs/store/iphone-69-<n>-<name>.png`:
the status bar at 9:41 with a full battery, light appearance, no added words, no alpha.

```sh
scripts/store-shots.sh                  # all six, newest Pro Max
scripts/store-shots.sh 1                # only the scorer
scripts/store-shots.sh "iPhone 18 Pro Max" 1 4
```

The order, first three being the ones a search result shows:

1. `scorer`: the live pitch on its side (2868 x 1320).
2. `sheet`: the finished score sheet.
3. `stats`: one game's numbers.
4. `games`: the Games list.
5. `teams`: setting up a new game.
6. `players`: the Stats tab, per player.

**Which go stale**: the scorer (the scorer work in flight changes it), and the games
list (it prints the version, build and today's date in its footer, and pull request 16
adds a reference games row). Retake both after those land and after the version is set.
The other four change only when their screens do. Look at every picture before you
commit it.

## The version

`VERSION` is `0.1`. The record's version is "1.0". Set both to the same number before
the external upload. Throwing Wood and its engine shipped as `1.0.0`, so `1.0.0` keeps
the family alike. The record's version string can change before submission.
