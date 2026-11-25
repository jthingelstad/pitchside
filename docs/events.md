# Events in Pitchside

Design notes from 2026-11-25. This is a proposal for future work.

Pitchside would own the event: who has entered, who plays whom, where to go, and which result counts. Throwing Wood would own the online game. On grass, teams could play an entire tournament with their phones in their pockets between matches. Reporting the winner would be enough to advance. Someone who wants a score sheet could also use Pitchside to record the throws.

Two examples motivated the design. An organizer runs an annual eight-team kubb tournament at work, with round-robin play feeding championship brackets. A monthly Throwing Wood cup could use the same event structure, with opponents meeting online during agreed play windows. The first question for both is how people join, find each other, and finish a scheduled match. An organizer can enter the pairings by hand while we work that out.

## Joining without accounts

The event has a random ID and lasts across days, including nights when every device is offline. Pitchside remembers the events joined on this phone. Scanning an invitation gives the installation permission to act within one event. Several teammates can scan the same invitation and each get their own access. Nothing requires a server-side player profile or a player identity shared across events.

| What someone opens | What it means |
| --- | --- |
| Event QR or link | Opens the schedule, standings, and brackets. **Follow event** keeps it in Pitchside. A read-only web view would let someone follow along from the picnic table or from home. |
| Team QR or private link | **Join as Mossy Stakes** adds the event and the team in one step. Any teammate who joins can report a result for either side of a Mossy Stakes match. |
| Scorer QR or private link | Adds permission to pick a scheduled match and score it, including one involving two other teams. A volunteer can cover several matches over the day. |
| Sign on Pitch 3 | Opens this event’s schedule for Pitch 3. Everyone sees who is playing and who is next. Team members and scorers see the actions their existing permissions allow. Changing the schedule updates what the same sign shows. |

An invitation can arrive before the schedule. The team sees “You’re in. The schedule hasn’t been posted yet.” Opening the same invitation again returns to the event. One person can organize the event, play for a team, and volunteer to score during a bye.

For a known field, the organizer creates the teams and hands out their invitations. A possible online registration flow lets someone enter a new team and privately invite teammates. Listing an entrant in the standings gives spectators a way to follow that team. Joining it requires its invitation. A shared team invitation can be forwarded, so the organizer needs a way to replace it and withdraw access already granted through it.

## One scheduled match on grass

1. **Find it.** Mossy Stakes opens **Your next match** and sees “Crooked Crowns · Pitch 3 · after the current game.” A stable match ID ties together the two entrants, the schedule, and the eventual result. Moving the game to Pitch 2 updates both signs.
2. **Play it.** The teams meet and start. Seeing each other on the grass is enough to check in. They can finish the game before anyone opens the app.
3. **Optionally score it.** A teammate or an invited volunteer taps **Score this match**. Pitchside fills in the two team names. The scorer chooses who throws first and can add a throwing order if they want individual statistics. Other volunteers see that this game is covered. Today setup requires one to six players per side. Starting with team names alone would need a change to the scoring flow. [Current game setup](../Pitchside/NewGameFlow.swift)
4. **Report it.** Either team taps **Report winner** and chooses one of the two team names. A scorer who recorded the game can submit the winner from the score sheet. Both paths supply one result to the event. The throw log and player details stay on the scorer’s phone unless they choose to share the file. Abandoning a partial score sheet leaves the teams free to report who won. [Pitchside’s local scoring and sharing model](../README.md)
5. **Move on.** Both teams see the accepted result, the standings, and their next opponent when known. A scorer reconnecting after the next game starts on Pitch 3 still submits to the match they selected.

## One scheduled match in Throwing Wood

1. **Arrange a time.** The match card names the opponent and the deadline. One option for pool play is to offer a few windows, let one team propose a time and the other accept, and show the appointment in each device’s local time. A final could have a fixed start so spectators know when to watch.
2. **Check in.** Each side signals that it is ready through Pitchside. The other side can see who has arrived. Any enrolled teammate can check in for the team. Each person actually throwing takes their own seat in the game.
3. **Take a seat.** On iPhone, **Play in Throwing Wood** would open the game with a short-lived, single-use pass for this scheduled match and side. On desktop, the browser would display a pairing QR. The player scans it with Pitchside and confirms which game and side the browser is joining. This QR authorizes one browser seat. The team invitation on the phone lasts for the event. Throwing Wood would enforce seat admission. Spectators could choose **Watch** on the web.
4. **Finish.** AWS would associate the scheduled match with the specific Throwing Wood game and its A/B team assignments at start. Its finish would supply the official winner, even if the finish arrives late. A casual rematch on the same pitch would be a different game. The pitch server already sends signed start and finish data to AWS. The tournament association and seat passes are proposed additions. [Throwing Wood’s AWS push contract](https://github.com/jthingelstad/kubb.thingelstad.xyz/blob/c4bcc3c2273b9271b3c35753ce9b116cbe9fdab3/backend/api/API.md#pushes)

## The organizer’s desk

The organizer creates the event, chooses its dates, distributes invitations, posts or moves matchups, resolves exceptions, and closes play. Routine results should advance the event without organizer approval. These are proposed defaults to try against a real tournament.

| Situation | Proposed handling |
| --- | --- |
| Two people report the same game | Matching reports count once. Conflicting winners go to the organizer. Show what each side or scorer reported. If a correction changes a matchup already underway, let the organizer settle it before changing that bracket. |
| Poor reception on grass | Show the last saved schedule, keep scoring locally, and mark a queued result **Waiting to send** until the server accepts it. A first join and an online seat handoff need a connection. |
| A team misses its window or drops mid-game | Show check-ins and let the organizer extend the window, reschedule, or award a forfeit. In tournament play a connected teammate could cover a throw. If a whole side disconnects, pause for reconnection. Casual Throwing Wood currently allows the host to cover an absent side. [Current multiplayer rules](https://github.com/jthingelstad/kubb.thingelstad.xyz/blob/c4bcc3c2273b9271b3c35753ce9b116cbe9fdab3/docs/MULTIPLAYER.md#who-acts) |
| A phone leaves or is lost | Leaving drops this phone’s event access. Withdrawing a team changes future games and needs a separate decision. A teammate can join on a replacement phone through a valid invitation. Consider a second organizer device or a recovery invitation before play starts. |
| Pool play ends | An example for eight teams is two pools of four feeding championship and consolation brackets. Preview the seeds, resolve ties, then publish the brackets. A winner-only event needs a tiebreak it can determine from the results it actually collects, or an organizer ruling. |
| The event closes | Show final standings for an announced read-only period, then expire event access and remove the shared event data. Locally scored games remain with their scorers. |

## Where the event lives

The proposed home is the existing AWS HTTPS API, with Lambda handling occasional event requests and DynamoDB keeping the shared records. The multi-day schedule advances through small writes such as posting a matchup or accepting a winner. Refreshing an open event screen could be enough for spectators. Cloudflare continues to handle the low-latency throws inside a live Throwing Wood game. Its existing reporting path to AWS gives the tournament a place to pick up the finish. [Throwing Wood API](https://github.com/jthingelstad/kubb.thingelstad.xyz/blob/c4bcc3c2273b9271b3c35753ce9b116cbe9fdab3/backend/api/API.md)

## Where to pick this up

Walk through one manually posted match twice. On grass, try both a winner-only report and a volunteer scoring on a phone that loses reception. Online, take two team invitations through scheduling, check-in, iPhone or browser admission, and one recorded finish. Repeat with a moved pitch, a late team, and conflicting reports.

Those journeys should help settle who may register or withdraw a team, who can see a private event, how organizer recovery and invitation revocation work, and how long a closed event stays readable. Pairing algorithms, seeding rules, and a persistent identity for teams entering next month’s cup can wait. A final could get a complete score sheet while every pool game reports only a winner, and both should lead to the same usable bracket.
