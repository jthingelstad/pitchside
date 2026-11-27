# Distribution

Pitchside 1.0.0 (build 73) was submitted to App Review on 2026-11-26 at 7:34 PM Central,
on Jamie's word ("I've run it. Submit."), and is Waiting for Review. It is set to
release by itself once Apple approves it. This file lists what a submission needs and
what was done. Every upload, every tester group and the App Store are Jamie's call.

Updated on 2026-11-26, after the submission. "Ours" means
work in this repository. "Jamie" means a step in App Store Connect or the developer
portal.

**What is left, in order, is the [submission checklist](#submission-checklist) at the
end.**

## Where the record stands (2026-11-26, evening)

Read back with GET calls (`scripts/asc.swift`) and on the App Store Connect pages, after
the writes below. Times are US Central.

- **The app**: "Kubb: Pitchside", bundle id `com.throwingwood.pitchside`, primary
  language English (U.S.), not made for kids.
- **Developer portal**: the iCloud container `iCloud.com.throwingwood.pitchside`
  ("Kubb Pitchside") is registered, and the App ID has iCloud on (CloudKit support) with
  that one container. The App ID's other capabilities are as they were (In-App Purchase,
  Apple's default).
- **Build 73** (1.0.0, commit `53b4d38`) was uploaded with `--external` at 4:03 PM and
  is valid: minimum iOS 26.0, iPhone only (`UIDeviceFamily` 1), no non-exempt
  encryption. Builds 17 to 59 stay internal only.
- **App information**: subtitle "Tap the kubbs. Keep the score.", Sports then Utilities,
  content rights "Yes, it contains, shows, or accesses third-party content, and I have
  the necessary rights", age rating 4+ (Brazil shows "ALL", Korea and Vietnam "00+"),
  privacy policy URL. The App Compliance page answers No to the China mainland security
  assessment and No to AI-generated content, both Active.
- **App Privacy**: "Data Not Collected", published.
- **Pricing and Availability**: free ($0.00, United States base), available in all 175
  countries or regions, and in future ones. Apple silicon Mac and Apple Vision Pro are
  off. Public distribution, as it was.
- **The version**: "1.0.0" (was "1.0"), still Prepare for Submission and set to release
  automatically after approval, as it was. Promotional text, description, keywords,
  copyright, the support and marketing URLs, and build 73 are on it.
- **App Review Information**: the same contact as Throwing Wood's App Review details, no
  sign-in needed, and the review notes below.
- **Screenshots**: the eight pictures in `docs/store/`, in their numbered order, in the
  6.9-inch iPhone set (`APP_IPHONE_67`). Apple took the mix of picture 1 (landscape) and
  the seven portrait ones: all eight processed. The 6.3-inch set, which App Store Connect
  now lists as required, says "Using Existing Assets", the 6.9-inch pictures scaled.
- **TestFlight**: unchanged. Dev (internal) has one tester. Beta (external) has none, its
  public link is off, and its Beta App Review details are empty.

- **Review submission**: one, with the 1.0.0 version as its only item, made and
  submitted through the API (`reviewSubmissions`, `reviewSubmissionItems`, then
  `submitted: true`). The version went from Prepare for Submission to Waiting for
  Review.

What App Store Connect showed as open and did not ask for:

- **iPad 13-inch screenshots: "Required", 0 of 10**, in the Media Manager's iPad tab.
  Build 73 is iPhone only, and the submission went through with no iPad set. The label
  is on every iOS record; an iPhone-only build does not need one.
- **Header asset: 0 of 1** (Header and Search Results, new on the version page; 5244 x
  2950 or 3840 x 1646). Not marked required on the page. None is planned for 1.0.

## Readiness

| Item | State | What is left, and whose |
| --- | --- | --- |
| App record and bundle id | Done | Nothing. |
| Signing | Done (automatic, team in a git-ignored file) | Nothing. The checkout that uploads needs Throwing Wood's `Config/Signing.local.xcconfig` and `Config/AppStoreConnect.local` copied in. |
| iCloud Drive folder | Done (pull request 15; container and App ID, 2026-11-26) | Nothing. |
| Reference games | Done (pull request 16) | Nothing. Content rights answered "Yes, I have the necessary rights". |
| App icon | Done for submission | A single 1024 master with no alpha is enough. iOS makes the dark and tinted looks from it. The final icon is Jamie's call. |
| Launch screen | Done | `UILaunchScreen` (an empty one: the system background, then the app). |
| Display name | Done | "Kubb: Pitchside", 15 characters, shows in full under the icon. |
| Category | Done | Sports, then Utilities, in the build and in App Store Connect. |
| Privacy manifest | Done, checked again 2026-11-26 | `Pitchside/PrivacyInfo.xcprivacy` ("Required reasons"). |
| Export compliance | Done | `ITSAppUsesNonExemptEncryption` is false; build 73 shows no non-exempt encryption. |
| Usage strings | Done (none needed) | No camera, photos, contacts, location or microphone. The file picker, share sheet, print and iCloud Drive need none. |
| Orientations | Done | iPhone only: portrait, and landscape for the scorer. |
| On an iPad | Checked 2026-11-26 | App Review may run it on an iPad. It works there; see "On an iPad". |
| Accessibility | Done for submission | VoiceOver labels every piece on the pitch, the turn history and the counts. Text uses Dynamic Type. Jamie may fill in Accessibility Nutrition Labels: optional, and only claim what was checked on a phone. |
| App Privacy | Done (published 2026-11-26) | Nothing. "Data Not Collected". |
| Age rating | Done | 4+ ("Age-rating worksheet"). |
| Price and territories | Done | Free, all 175 countries or regions. |
| Mac and Vision Pro | Done (off) | Nothing. |
| App Compliance (China mainland) | Done | No and no, both Active. |
| Listing words and URLs | Done (on the version page) | Nothing. Written as drafted below. |
| Screenshots | Done for iPhone (eight, 6.9-inch) | Nothing. The submission did not ask for an iPad set. |
| Review notes | Done | Nothing. Contact as Throwing Wood's. |
| The version | Done (`1.0.0` on the record and the build) | Nothing. |
| A build for the App Store | Done (build 73, attached) | Nothing. |
| iOS 26.2 | Run on a phone | Jamie ran build 73 on a phone on 2026-11-26 before the submission. Which iOS it had was not written down ("The iOS 26.2 simulator crash"). |

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
would only move the crash.

If a phone with iOS 26 ever does crash this way, the fallback is to set the minimum to
iOS 27. Pitchside asks for 26.0 today.

## On an iPad

Pitchside is an iPhone app, but App Review may open it on an iPad, where iPadOS runs it
in an iPhone-shaped window. Checked on 2026-11-26 on the iPad mini simulator (iPadOS
27.2): a fresh launch, a new game, two scored batons, the side switch, the whole-pitch
button and the half tab, back to Games, a reference game's sheet and play by play, and
the PDF preview. All of it works.

- **Fixed here.** iPadOS draws its three window buttons in the top left corner of the
  window, right over the back button and the scorer's "Games" button. A tap on "Games"
  opened the window menu instead, so a reviewer could be stuck in the scorer. The page
  headers and the scorer header now step clear of those buttons, on an iPad only
  (`clearsWindowControls` in `Pitchside/Common.swift`, from UIKit's corner-adapted safe
  area). An iPhone looks the same as before.
- **How it looks.** The scorer asks for landscape. In a portrait iPad the system shows
  it on its side, as it does with any landscape-only iPhone screen; turn the iPad and
  it reads the right way. The simulator would not turn while the window was in
  windowed mode, so the turned iPad is not seen yet. Scoring on its side still works:
  every tap in the check landed.
- **Not a blocker.** Nothing here should stop review. A real iPad layout is not planned
  for 1.0.

## Data that leaves the device

None goes to us. Pitchside has no network code: no URLSession, no sockets, no CloudKit
database, no analytics or ad SDK. The JavaScript the reader runs has no network access
either. The Games footer says so: "Games are kept on this phone. Each finished game's
file, with its team and player names, is also in Files under iCloud Drive › Pitchside,
in your own iCloud. The roster stays on this phone. Nothing is sent to us." (With iCloud
Drive off it names On My iPhone › Kubb: Pitchside instead.)

- **Games, notes and the roster** are files under Application Support on the phone.
- **The iCloud Drive folder** (pull request 15): each finished game's text file is also
  copied to the person's own iCloud Drive, or to On My iPhone with iCloud Drive off. It
  holds the team and player names typed for that game. It is the person's own storage:
  Apple holds it, and the developer cannot read it. The roster stays on the phone.
- **Share** (the `.txt` file, the PDF) uses the system share sheet. The person picks
  where it goes. Pitchside never sees where.
- **Open file** reads a text file the person picks.
- **Print** uses the system print panel.
- **A reference game's links** ("Archive file", "Video") open the archive file on
  GitHub, or the game's video on YouTube, in the browser or the YouTube app. Pitchside
  hands the link to the system and sends nothing with it.

## App Privacy worksheet

Answer **"No, we do not collect data from this app"**. App Store Connect then shows
"Data Not Collected".

Apple's definition: data is collected when it is sent off the device "in a way that
allows you and/or your third-party partners to access it for a period longer than
necessary to service the transmitted request in real time." Pitchside sends nothing to
us or to anyone working with us.

- The iCloud Drive copy goes to the person's own iCloud, which the developer cannot
  read, the same as any document app saving to iCloud Drive.
- What the share sheet sends goes where the person chooses.
- A reference game's link opens a public page; Pitchside sends no data with it.

None of these is data we collect. No tracking. [Apple's privacy definitions](https://developer.apple.com/app-store/app-privacy-details/)

Check this again if Pitchside ever adds sign-in, feedback, a server, crash reporting
outside Apple's own, or a CloudKit database.

### Required reasons

`Pitchside/PrivacyInfo.xcprivacy` says no tracking, no collected data, and one
required-reason API:

- **File timestamp, `C617.1`.** `GameStore.needsReplay` reads `contentModificationDate`
  of the app's own game files, to see whether an export is older than its journal.
  Apple's `C617.1`: "access the timestamps, size, or other metadata of files inside the
  app container".

Checked again on 2026-11-26 against the merged code. The iCloud copy
(`GameMirror`) asks for the iCloud folder, checks the account token, coordinates the
write and lists the folder with no file attributes: none of that is on Apple's list.
The reference games are files inside the app, and their links go through the system.
There is no UserDefaults or `@AppStorage`, no system boot time, no disk space and no
keyboard list. Lua's `os.clock` and `os.time` are not on the list, and the vendored
musl maths does no file calls. JavaScriptCore is Apple's own. The manifest stays as it
is. [Apple's required reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

## Age-rating worksheet

| Question group | Answer and why |
| --- | --- |
| User-generated content | No. The team and player names a person types go into each finished game's file, which is copied to that person's own iCloud Drive; the roster stays on the phone. Nobody else sees any of it through the app. It reaches others only when the person shares a file. |
| Messaging and chat | No. |
| Contests | None. Pitchside keeps score of a game people play in real life. It runs no rankings, prizes or events. |
| Advertising, web access, social feed | None. The two links on a reference game open a public page in the browser; there is no web view in the app. |
| In-app controls | No parental controls or age checks. |
| Mature themes, violence, profanity, drugs, sexual content, horror | None. A baton knocks over wooden kubbs. |
| Medical, health and wellness | None. |
| Gambling, loot boxes | None. |

Expect 4+. The build makes no Kids Category claim. [Apple's rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)

## Third-party content

**What ships.** Fourteen games from the Planet Kubb wiki archive (2011 to 2015),
files from pk-kubb-score at tag `v2-2026.11`, unchanged (a checksum file guards them).
They carry the real names of players, scorers, events and places. Each one's sheet has
a credit: event, date, place, teams, who scored it, who entered it, the source, an
"Archive file" link and, where there is one, the video. Under it: "From the Planet Kubb
wiki archive (wiki.planetkubb.com, 2011 to 2015), kept in pk-kubb-score. Planet Kubb
published its content under Creative Commons BY-SA. The file is shown unmodified."

**The licence.** Planet Kubb's 2012 scoring post says its content is CC BY-SA. It names
no version, and pk-kubb-score has no licence file of its own. BY-SA lets anyone copy and
share the games, also in a paid or free app, as long as the people are credited, the
licence is named, and changed versions stay under BY-SA. Pitchside credits each game,
names the licence and changes nothing, and its own code (MIT) is not a changed version
of the games. The credit names no version and has no link to the licence text, because
the source names none.

**The App Store answer.** App Information asks whether the app "contains, shows or
accesses third-party content". The answer is **Yes**, and then **"Yes, I have the
necessary rights"**, resting on the BY-SA licence. Say so in the review notes too.

**What stays Jamie's.**

- The answer itself: only the account holder can declare the rights.
- Whether that answer rests on the licence alone. Jamie is an admin of the Planet-Kubb
  organisation, but the scorers and the players did not sign up to an app. The archive is public and credited by name either way.
- Whether to add a link to the licence on each credit (CC asks for one where it is
  practical). A small change in `ReferenceGames.swift` if wanted; not needed for review.

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
> Turn your phone on its side and the pitch is in front of you, zoomed to the half
> where the batons land. After each baton, tap the kubbs that fell. Pitchside counts
> the batons, keeps the inkast and the field kubbs straight, and knows whose turn it is.
>
> When the king goes down, the game is a score sheet in Planet Kubb notation. Fix a
> throw you got wrong, print the sheet, or share it as a file. Open games someone
> else scored, read a game back throw by throw, and see how each player throws.
>
> Start with real games from the Planet Kubb archive, from US Nationals to a
> championship on Gotland.
>
> Your games stay on your phone, with a copy of each finished game in your own iCloud
> Drive. No sign-in, no ads, no tracking.

**Keywords** (93 of 100): lawn game,score sheet,scorekeeper,baton,king,viking
chess,backyard,tournament,stats,yard game

The words of the name are already searched, so "kubb" and "pitchside" are left out.

**Categories**: Sports, then Utilities.

**What's New**: none. App Store Connect does not take it for the first version.

**Copyright**: 2026 Jamie Thingelstad

**URLs** (all three live on 2026-11-26):

- Marketing: `https://throwingwood.com/pitchside/`
- Support: `https://throwingwood.com/pitchside/support/`
- Privacy policy: `https://throwingwood.com/pitchside/privacy/`

**Review notes**:

> Pitchside is a scorekeeper for kubb, a lawn game played with wooden blocks and
> batons. There is no sign-in and no account. The app sends nothing to the developer.
>
> To see a real game: on Games, open any game under Reference games. These are 14 real
> tournament games from the Planet Kubb archive, read only. Tap Play by play and then
> Next to step through it, or Score sheet PDF for the printable sheet. Planet Kubb
> published them under Creative Commons BY-SA, and each one shows its credit. The
> developer is an admin of the Planet Kubb project.
>
> To score a game: tap New game, type a player name on each side, tap Next: this game,
> then Start scoring. The scorer turns to landscape and shows the half of the pitch
> where the batons land. Tap the kubbs a baton knocked down, then the big button (Miss,
> or 1 down, 2 down and so on). When the turn changes, the pitch slides to the other
> half. The tab on the edge of the pitch opens the other half, and the button at the
> top shows the whole pitch. Games goes back to the list.
>
> Finished games are also saved as text files in the person's own iCloud Drive
> (Files, iCloud Drive, Pitchside).

Edit the steps if the buttons change before submission.

## Screenshots

Apple's specification (read 2026-11-26): the store needs at least one iPhone set. The
6.9-inch sizes are 1320 x 2868 (or 1290 x 2796, 1260 x 2736) and their landscape
sizes. Smaller iPhones use scaled 6.9-inch pictures when they have none of their own.
One to ten a set, PNG or JPEG, no transparency. The app is iPhone only, so no iPad set.
Portrait and landscape can share a set; the store shows them as they are (App Store
Connect took this set's mix on 2026-11-26). App Store Connect lists the 6.3-inch set as
required, and fills it with the 6.9-inch pictures scaled ("Using Existing Assets"). If it
ever asks for its own, run the script on a 6.3-inch simulator. (Throwing Wood runs on
iPad, so it also has an iPad set; it is no guide to whether an iPhone-only app needs one.)

`scripts/store-shots.sh` takes the set from the DEBUG demo games (invented names only)
on the newest iPhone Pro Max simulator. It writes `docs/store/iphone-69-<n>-<name>.png`:
the status bar at 9:41 with a full battery, light appearance, no added words, no alpha.
It launches with `-PitchsideStoreShot`, so the pictures show no version or build and a
fixed date (the game in progress started Saturday 21 November), and the Games footer
names the iCloud Drive folder. A new upload or a new day changes nothing in them.

```sh
scripts/store-shots.sh                  # all eight, newest Pro Max
scripts/store-shots.sh 1                # only the scorer
scripts/store-shots.sh "iPhone 18 Pro Max" 1 4
```

The order. The first three are the ones a search result shows:

1. `scorer`: the live pitch on its side, framed on the half with three field kubbs to
   clear, the turn history beside it (2868 x 1320).
2. `sheet`: the finished score sheet, turn by turn.
3. `replay`: the play by play, a baton that knocked two field kubbs.
4. `games`: the Games list, with the reference games row and the footer.
5. `references`: the Planet Kubb reference games.
6. `stats`: one game's numbers.
7. `players`: the Stats tab, per player.
8. `teams`: setting up a new game.

A reference game's own sheet, with its credit, is left out on purpose: it shows real
people's names. The list in picture 5 shows only team and event names.

Retake a picture when its screen changes, and look at every picture before you commit
it.

## The version

`VERSION` is `1.0.0`, named by Jamie on 2026-11-26, as Throwing Wood and its engine
shipped. The record's version string was changed from "1.0" to `1.0.0` on 2026-11-26,
so the build and the page match.

## Submission checklist

What is left, in order. Each line is one thing to do.

**Done on 2026-11-26** (on Jamie's go)

1. The listing words, approved as drafted, and the version named `1.0.0`.
2. The iCloud container registered and iCloud turned on for the App ID, in the developer
   portal.
3. Throwing Wood's two local files copied into the checkout, then
   `scripts/testflight.sh --dry-run --external` and `scripts/testflight.sh --external`:
   1.0.0 build 73, valid.
4. App Information: subtitle, Sports then Utilities, content rights, age rating (4+),
   privacy policy URL, and App Compliance for China mainland (no and no).
5. App Privacy: "Data Not Collected", published.
6. Pricing and Availability: free, every territory, Mac and Vision Pro off.
7. App Review Information: contact (as Throwing Wood's), no sign-in, the review notes.
8. The version page: "1.0.0", promotional text, description, keywords, copyright, the
   marketing and support URLs (`scripts/asc.swift` with `ASC_WRITE=1`), the eight
   pictures in order (the same way), and build 73.

9. Jamie ran the build on a phone ("I've run it").
10. Submitted to App Review at 7:34 PM Central, through the API, on Jamie's word. No
    iPad screenshots were asked for.

**Left**

11. Apple's review. On approval the version releases by itself (release type "after
    approval"). Then set `PITCHSIDE_APP_STORE_URL` in the web repo's `src/site/site.mjs`
    so throwingwood.com/pitchside shows the store badge.
