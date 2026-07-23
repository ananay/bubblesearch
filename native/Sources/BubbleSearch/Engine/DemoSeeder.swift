import Foundation

/// A synthetic, PR-friendly conversation for demos and screen recordings.
/// Written ONLY into BubbleSearch's own index database — chat.db is never
/// touched. Content: ~200 messages over ~3 years with a fictional friend,
/// about a rec-league team (the Turbo Llamas), pickleball, fantasy drafts,
/// marathons, and clean everyday life. Every name/handle is fictional
/// (555-01xx is the reserved fictional number block).
enum DemoSeeder {
    static let handle = "+15550194476"
    static let displayName = "Sam Rivera"

    struct SeedMessage {
        let fromMe: Bool
        let text: String
        let date: Date
        /// Tapback kind (2000 love, 2001 like, 2003 laugh, 2004 emphasize,
        /// 2005 question) placed by the NON-author of the message.
        let react: Int?
        /// Reply-quote: how many messages back (within the whole stream)
        /// the quoted parent sits.
        let replyBack: Int?
    }

    private struct Line {
        let me: Bool
        let text: String
        var react: Int? = nil
        var replyBack: Int? = nil
    }

    private struct Cluster {
        let daysAgo: Int
        let hour: Int
        let lines: [Line]
    }

    static func build(now: Date = Date()) -> [SeedMessage] {
        var messages: [SeedMessage] = []
        let calendar = Calendar.current
        for cluster in clusters {
            let start: Date
            if cluster.daysAgo == 0 {
                start = now.addingTimeInterval(-Double(cluster.lines.count * 90 + 300))
            } else {
                let day = now.addingTimeInterval(-Double(cluster.daysAgo) * 86_400)
                start = calendar.date(
                    bySettingHour: cluster.hour,
                    minute: (cluster.daysAgo * 7) % 50 + 5,
                    second: 0, of: day
                ) ?? day
            }
            var t = start
            for (i, line) in cluster.lines.enumerated() {
                t = t.addingTimeInterval(Double(40 + (i * 37) % 80))
                messages.append(SeedMessage(
                    fromMe: line.me, text: line.text, date: t,
                    react: line.react,
                    replyBack: line.replyBack.map { _ in line.replyBack! }
                ))
            }
        }
        return messages
    }

    // ~195 messages, oldest cluster ≈ 3 years back, newest minutes ago (so
    // the conversation sorts to the top of the sidebar).
    private static let clusters: [Cluster] = [
        Cluster(daysAgo: 1085, hour: 19, lines: [
            Line(me: false, text: "yo did you sign us up for the rec league or was that all talk"),
            Line(me: true, text: "signed us up an hour ago. tuesday nights, starts in two weeks"),
            Line(me: false, text: "LETS GO"),
            Line(me: false, text: "we need a team name"),
            Line(me: true, text: "Turbo Llamas", react: 2003),
            Line(me: false, text: "that's actually incredible"),
            Line(me: false, text: "Turbo Llamas it is. making the jersey order tonight"),
            Line(me: true, text: "get me a large. and llama socks if they exist"),
            Line(me: false, text: "they exist. ordering two pairs", react: 2001),
        ]),
        Cluster(daysAgo: 1050, hour: 21, lines: [
            Line(me: true, text: "1-7. we lost 1-7 😅"),
            Line(me: false, text: "we showed up. that's what counts"),
            Line(me: true, text: "our one goal was an own goal by them"),
            Line(me: false, text: "a goal is a goal. it's going in the season recap"),
            Line(me: true, text: "turbo llamas: undefeated in spirit", react: 2000),
            Line(me: false, text: "putting that on a shirt"),
        ]),
        Cluster(daysAgo: 1010, hour: 20, lines: [
            Line(me: false, text: "fantasy draft sunday 7pm don't forget"),
            Line(me: true, text: "auto-draft carried me last year, it can do it again"),
            Line(me: false, text: "you drafted three kickers"),
            Line(me: true, text: "and I still beat you week 4"),
            Line(me: false, text: "one time. ONE time", react: 2003),
            Line(me: true, text: "screenshot lives forever"),
            Line(me: false, text: "ok draft order posted. you're 8th"),
            Line(me: true, text: "perfect. chaos seat"),
        ]),
        Cluster(daysAgo: 985, hour: 9, lines: [
            Line(me: true, text: "turkey trot 5k thanksgiving morning. you in?"),
            Line(me: false, text: "only if pancakes after"),
            Line(me: true, text: "obviously pancakes after"),
            Line(me: false, text: "then I'm in. costume or no costume"),
            Line(me: true, text: "full turkey hat. no shame", react: 2003),
            Line(me: false, text: "registering us now"),
        ]),
        Cluster(daysAgo: 965, hour: 19, lines: [
            Line(me: false, text: "unrelated to sports: I made bread. it's a brick"),
            Line(me: true, text: "pics or it didn't happen"),
            Line(me: false, text: "it could stop a door"),
            Line(me: true, text: "bring the brick to the game. new team mascot", react: 2003),
            Line(me: false, text: "the llamas deserve better than my bread"),
            Line(me: true, text: "nothing is better than your bread. structurally"),
        ]),
        Cluster(daysAgo: 940, hour: 18, lines: [
            Line(me: false, text: "cabin's booked for the ski weekend. jan 12-14"),
            Line(me: true, text: "how are your knees feeling about this"),
            Line(me: false, text: "my knees have no idea what's coming"),
            Line(me: true, text: "renting or bringing gear?"),
            Line(me: false, text: "renting. last time my bindings were older than us"),
            Line(me: true, text: "green runs day one. I mean it"),
            Line(me: false, text: "no promises", react: 2005),
        ]),
        Cluster(daysAgo: 900, hour: 12, lines: [
            Line(me: true, text: "gym was PACKED today. resolution crowd"),
            Line(me: false, text: "give it three weeks"),
            Line(me: true, text: "also tried pickleball at lunch. I might be hooked"),
            Line(me: false, text: "pickleball?? aren't we a little young for that"),
            Line(me: true, text: "come play ONE game and tell me that again"),
            Line(me: false, text: "fine. saturday. prepare to be humbled"),
            Line(me: true, text: "bring water. you'll need it", react: 2004),
        ]),
        Cluster(daysAgo: 897, hour: 16, lines: [
            Line(me: false, text: "ok pickleball is unreasonably fun"),
            Line(me: true, text: "TOLD YOU"),
            Line(me: false, text: "the little paddle sounds are so satisfying"),
            Line(me: true, text: "we're getting a weekly court slot"),
            Line(me: false, text: "already looking at paddles online", react: 2003),
        ]),
        Cluster(daysAgo: 880, hour: 14, lines: [
            Line(me: true, text: "found a coffee place that does a maple cortado. life changing"),
            Line(me: false, text: "maple?? in a cortado??"),
            Line(me: true, text: "do not knock it before saturday. we're going pre-pickleball"),
            Line(me: false, text: "coffee then pickleball is an elite saturday", react: 2001),
            Line(me: true, text: "the perfect morning exists and we found it"),
        ]),
        Cluster(daysAgo: 860, hour: 11, lines: [
            Line(me: false, text: "bracket time. winner buys wings"),
            Line(me: true, text: "my strategy is mascots again"),
            Line(me: false, text: "the mascot strategy went 12-20 last year"),
            Line(me: true, text: "mascot strategy is about heart, not results", react: 2003),
            Line(me: false, text: "my bracket is pure chalk. respect the seeds"),
            Line(me: true, text: "boring wins nothing"),
            Line(me: false, text: "boring wins WINGS"),
        ]),
        Cluster(daysAgo: 858, hour: 22, lines: [
            Line(me: true, text: "my bracket is toast. day one. DAY ONE"),
            Line(me: false, text: "the mascot method strikes again"),
            Line(me: true, text: "the walrus team betrayed me"),
            Line(me: false, text: "there is no walrus team"),
            Line(me: true, text: "there should be", react: 2003),
        ]),
        Cluster(daysAgo: 830, hour: 7, lines: [
            Line(me: false, text: "signed up for the spring half marathon. hold me to it"),
            Line(me: true, text: "training plan or winging it?"),
            Line(me: false, text: "12 week plan. taped it to the fridge"),
            Line(me: true, text: "proud of you honestly", react: 2000, replyBack: 3),
            Line(me: false, text: "week 1 starts monday. 3 easy miles"),
            Line(me: true, text: "I'll do the long runs with you"),
            Line(me: false, text: "you're the best"),
        ]),
        Cluster(daysAgo: 790, hour: 19, lines: [
            Line(me: true, text: "court booked thursday 6pm. bringing the new paddle"),
            Line(me: false, text: "the carbon one?? we're not even good"),
            Line(me: true, text: "the paddle doesn't know that"),
            Line(me: false, text: "rating our rallies out of 10 from now on", react: 2001),
            Line(me: true, text: "last week's 37-shot rally was a 10"),
            Line(me: false, text: "that rally belongs in a museum", react: 2004),
        ]),
        Cluster(daysAgo: 750, hour: 20, lines: [
            Line(me: false, text: "olympics opening ceremony watch party at mine friday"),
            Line(me: true, text: "I'm making a snack bracket. 16 snacks. knockout format"),
            Line(me: false, text: "seed the nachos first. they earned it"),
            Line(me: true, text: "nachos are the 1 seed. queso gets a play-in game", react: 2003),
            Line(me: false, text: "this is the most organized you've ever been"),
            Line(me: true, text: "sports bring out my best self"),
        ]),
        Cluster(daysAgo: 748, hour: 23, lines: [
            Line(me: true, text: "how is table tennis THIS intense"),
            Line(me: false, text: "I haven't blinked in 20 minutes"),
            Line(me: true, text: "we're buying paddles tomorrow"),
            Line(me: false, text: "we already have pickleball thursdays"),
            Line(me: true, text: "and now we have ping pong wednesdays", react: 2003),
        ]),
        Cluster(daysAgo: 730, hour: 9, lines: [
            Line(me: false, text: "my plant survived a whole month. growth as a person"),
            Line(me: true, text: "the fern respects your progress"),
            Line(me: false, text: "it's a pothos"),
            Line(me: true, text: "the pothos respects your progress", react: 2003),
        ]),
        Cluster(daysAgo: 700, hour: 19, lines: [
            Line(me: false, text: "draft tonight. no kickers before round 10. promise me"),
            Line(me: true, text: "I promise nothing"),
            Line(me: true, text: "ok autodraft took a kicker round 6. I blame the algorithm"),
            Line(me: false, text: "you ARE the algorithm. you set the rankings", react: 2003),
            Line(me: true, text: "the rankings were a group effort between me and fate"),
            Line(me: false, text: "fate has you 0-0 with a kicker in round 6"),
        ]),
        Cluster(daysAgo: 660, hour: 21, lines: [
            Line(me: true, text: "lost my fantasy semi by 0.8 points"),
            Line(me: false, text: "0.8?? on what"),
            Line(me: true, text: "a garbage time field goal. by HIS kicker"),
            Line(me: false, text: "the kicker karma is poetic", react: 2003),
            Line(me: true, text: "I'm retiring from fantasy"),
            Line(me: false, text: "see you at next year's draft"),
            Line(me: true, text: "obviously"),
        ]),
        Cluster(daysAgo: 620, hour: 8, lines: [
            Line(me: false, text: "turkey trot rematch. this year I'm beating you"),
            Line(me: true, text: "you said that last year at pancakes"),
            Line(me: false, text: "this year I trained. twice"),
            Line(me: true, text: "twice is technically training", react: 2003),
            Line(me: false, text: "see you at the start line. the turkey hat's mine this year"),
            Line(me: true, text: "you'll have to earn the hat"),
        ]),
        Cluster(daysAgo: 560, hour: 13, lines: [
            Line(me: true, text: "rec league spring signup is open. llamas running it back?"),
            Line(me: false, text: "llamas never die"),
            Line(me: true, text: "we won 2 games last season. momentum."),
            Line(me: false, text: "200% improvement over season one. dynasty behavior", react: 2004),
            Line(me: true, text: "ordering the new jerseys. same socks?"),
            Line(me: false, text: "the socks are our identity now"),
        ]),
        Cluster(daysAgo: 530, hour: 18, lines: [
            Line(me: true, text: "attempting your chili recipe for game night"),
            Line(me: false, text: "secret is the cinnamon. tiny bit. trust"),
            Line(me: true, text: "cinnamon??? in chili???"),
            Line(me: false, text: "TRUST", react: 2004),
            Line(me: true, text: "ok the cinnamon thing is real. the crowd went silent"),
            Line(me: false, text: "the recipe is undefeated since 2019"),
        ]),
        Cluster(daysAgo: 500, hour: 12, lines: [
            Line(me: false, text: "bracket check?"),
            Line(me: true, text: "perfect through round one. I switched to your chalk method"),
            Line(me: false, text: "welcome to the light"),
            Line(me: true, text: "I kept one mascot pick for the soul"),
            Line(me: false, text: "which one"),
            Line(me: true, text: "the fighting okra. obviously", react: 2003),
            Line(me: false, text: "if the okra wins I'll eat okra for a week"),
        ]),
        Cluster(daysAgo: 440, hour: 10, lines: [
            Line(me: true, text: "RACE DAY. you've got this"),
            Line(me: false, text: "nervous. ate the same oatmeal as every long run. ritual complete"),
            Line(me: true, text: "see you at mile 9 with signs"),
            Line(me: false, text: "if the sign has my face on it I'm speeding up"),
            Line(me: true, text: "the sign has your face on it. huge. laminated", react: 2003),
            Line(me: false, text: "DONE. 1:58:41!!!", react: 2004),
            Line(me: true, text: "UNDER TWO HOURS LETS GOOO"),
            Line(me: false, text: "the fridge plan works. next stop: full marathon??"),
            Line(me: true, text: "framing this text", react: 2000, replyBack: 3),
        ]),
        Cluster(daysAgo: 380, hour: 17, lines: [
            Line(me: false, text: "tournament bracket posted. we're the 7 seed"),
            Line(me: true, text: "underdog story loading"),
            Line(me: false, text: "won round one!! 11-6 11-8"),
            Line(me: true, text: "the llama energy transfers to the court"),
            Line(me: false, text: "SEMIS. we're in the SEMIS"),
            Line(me: true, text: "who do we play"),
            Line(me: false, text: "the retired teachers. they're terrifying"),
            Line(me: true, text: "respect them. fear them. lob them", react: 2003),
            Line(me: false, text: "WE WON THE WHOLE THING", react: 2000),
            Line(me: true, text: "CHAMPIONS. dinner's on me tonight"),
        ]),
        Cluster(daysAgo: 300, hour: 19, lines: [
            Line(me: true, text: "fall season kickoff tuesday. year three of the llamas"),
            Line(me: false, text: "captain rotation says it's your year"),
            Line(me: true, text: "first act as captain: mandatory pregame playlist"),
            Line(me: false, text: "second act: actual defense?", react: 2003),
            Line(me: true, text: "defense is a mindset and we're working on it"),
        ]),
        Cluster(daysAgo: 260, hour: 16, lines: [
            Line(me: false, text: "estate sale find: a vintage ping pong paddle. it's beautiful"),
            Line(me: true, text: "does it come with vintage skills"),
            Line(me: false, text: "the skills were extra. couldn't afford them"),
            Line(me: true, text: "wednesday ping pong just got interesting", react: 2001),
        ]),
        Cluster(daysAgo: 200, hour: 20, lines: [
            Line(me: false, text: "PLAYOFFS. llamas in the playoffs"),
            Line(me: true, text: "three seasons in the making"),
            Line(me: false, text: "if we win I'm getting a llama tattoo"),
            Line(me: true, text: "you are NOT"),
            Line(me: false, text: "small one. ankle. tasteful", react: 2003),
            Line(me: true, text: "semifinal thursday. bring the socks"),
            Line(me: false, text: "the socks have never missed a game"),
            Line(me: true, text: "FINAL SCORE 4-2. CHAMPIONSHIP GAME SUNDAY", react: 2004),
            Line(me: false, text: "I cannot believe the llamas are in a final"),
            Line(me: true, text: "believe it. sunday we ride"),
        ]),
        Cluster(daysAgo: 197, hour: 18, lines: [
            Line(me: false, text: "well. 2-3 in the final"),
            Line(me: true, text: "one goal away. ONE"),
            Line(me: false, text: "proudest loss of my life"),
            Line(me: true, text: "trophy next season. I can feel it"),
            Line(me: false, text: "llamas forever", react: 2000),
        ]),
        Cluster(daysAgo: 90, hour: 10, lines: [
            Line(me: true, text: "trail run saturday? the ridge loop"),
            Line(me: false, text: "only if we stop at the overlook for snacks"),
            Line(me: true, text: "snacks are the entire point of the overlook"),
            Line(me: false, text: "7am start. beat the heat"),
            Line(me: true, text: "7:30 and I bring the good granola", react: 2001),
            Line(me: false, text: "deal"),
        ]),
        Cluster(daysAgo: 30, hour: 21, lines: [
            Line(me: false, text: "summer league schedule dropped. we play friday nights now"),
            Line(me: true, text: "friday night lights for the llamas"),
            Line(me: false, text: "also the pickleball court re-opens next week. rusty already"),
            Line(me: true, text: "rust adds character to the rallies"),
            Line(me: false, text: "our rallies have PLENTY of character", react: 2003),
        ]),
        Cluster(daysAgo: 0, hour: 0, lines: [
            Line(me: false, text: "game tonight. 7pm. don't forget the socks"),
            Line(me: true, text: "socks are already in the bag"),
            Line(me: false, text: "llamas ride at seven", react: 2004),
            Line(me: true, text: "see you there 🔥"),
        ]),
    ]
}
