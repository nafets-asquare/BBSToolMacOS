import Foundation

/// One setting or topic in the programming guide. Text may use Markdown (bold, links).
struct GuideEntry: Identifiable {
    var title: String
    var text: String
    /// Values from the source article's example tunes, if it gives any.
    var typical: String?
    var caution: String?

    var id: String { title }
}

struct GuideSection: Identifiable {
    var title: String
    var intro: String?
    var entries: [GuideEntry]

    var id: String { title }
}

/// A plain-language guide to the controller settings, written for this app from Karl Gesslein's
/// "A Hacker's Guide To Programming The BBS02 & BBSHD" (ElectricBike-Blog.com, 2015).
enum Guide {
    static let sourceTitle = "A Hacker's Guide To Programming The BBS02 & BBSHD"
    static let sourceURL = URL(string: "https://electricbike-blog.com/2015/06/26/a-hackers-guide-to-programming-the-bbs02/")!

    static let sections: [GuideSection] = [
        GuideSection(
            title: "Before you start",
            intro: """
                Bafang has never documented these settings. Everything here comes from riders and dealers \
                who experimented, so treat the numbers as starting points, not specifications. Changing the \
                settings is at your own risk and may void your warranty.
                """,
            entries: [
                GuideEntry(
                    title: "A safe way to work",
                    text: """
                        1. **Connect**, then **Read All**.
                        2. **Save Profile As…** to keep a backup of the controller as it is now.
                        3. Change one or two values at a time, in small steps.
                        4. **Write** the tab. BBSTool lists what will change, checks the values, and reads them back to make sure they were stored.
                        5. Test ride. If you don't like the result, open your backup and **Write All**.
                        """
                ),
                GuideEntry(
                    title: "Gentler is safer",
                    text: """
                        Lowering current and speed limits is low-risk. Raising them makes the motor and controller \
                        work harder. Running every assist level at 100% is a well-known way to overheat the controller.
                        """
                ),
            ]
        ),
        GuideSection(
            title: "How the settings work together",
            entries: [
                GuideEntry(
                    title: "Pedal assist is on or off",
                    text: """
                        The pedal sensor only tells the controller *that* you are pedaling, not how hard. The assist \
                        level you choose on the display then decides how much current and how much motor speed you get, \
                        using the percentages on the **Basic** tab.
                        """
                ),
                GuideEntry(
                    title: "Displays with fewer levels",
                    text: """
                        A display with 9 levels uses Assist 1–9. A 5-level display uses only the odd levels 1, 3, 5, 7 \
                        and 9, and a 3-level display uses 1, 5 and 9. Edit the levels your display actually uses.
                        """
                ),
                GuideEntry(
                    title: "\"By display\"",
                    text: "Leaves that setting to the display. Choosing a value instead fixes it, whatever the display says."
                ),
            ]
        ),
        GuideSection(
            title: "Basic tab",
            entries: [
                GuideEntry(
                    title: "Low battery protection",
                    text: """
                        The battery voltage at which the motor stops. Too high and the motor cuts out while the \
                        battery still has charge; the battery's own protection circuit usually guards the low end anyway.
                        """,
                    typical: "About 38–41 V for a 48 V battery"
                ),
                GuideEntry(
                    title: "Current limit",
                    text: """
                        The most current the controller draws from the battery, which sets the motor's peak power. \
                        Short peaks can go slightly above it. BBSTool never allows more than the maximum the \
                        controller reports.
                        """,
                    typical: "18 A as a gentle all-round value; 25 A for a 750 W BBS02; 30 A suggested for the BBSHD; about 15 A with an internal gear hub",
                    caution: "Don't raise it on units rated below 750 W unless you know the hardware can take it."
                ),
                GuideEntry(
                    title: "Assist levels: current limit",
                    text: """
                        For each assist level, the share of the current limit it may use. Let it rise steadily from \
                        level 1 to level 9 so each step feels like a little more help.
                        """,
                    typical: "Karl's tune: 52, 58, 64, 70, 76, 82, 88, 94, 100 % for levels 1–9"
                ),
                GuideEntry(
                    title: "Assist levels: speed limit",
                    text: """
                        For each assist level, the share of the motor's top speed at which assist starts to back off. \
                        Again, rise steadily from level 1 to 9.
                        """,
                    typical: "Karl's tune: 44, 51, 58, 65, 72, 79, 86, 93, 100 % for levels 1–9",
                    caution: "Setting 100% on every level strains the controller."
                ),
                GuideEntry(
                    title: "Assist 0",
                    text: """
                        Level 0 means no pedal assist. Set its current and speed limits to **1%** if you want the \
                        throttle to work in level 0; on the **Throttle Handle** tab, also set a designated assist level.
                        """,
                    typical: "Current 1 %, speed 1 %"
                ),
                GuideEntry(
                    title: "Wheel diameter",
                    text: "Set your actual wheel size. The displayed speed and the speed limits are calculated from it."
                ),
                GuideEntry(
                    title: "Speed meter type and signals",
                    text: "With the usual spoke magnet and frame sensor: External, Wheel Meter with 1 signal. Leave as is."
                ),
            ]
        ),
        GuideSection(
            title: "Pedal Assist tab",
            intro: "These shape how assist starts and stops. Change them conservatively and one at a time.",
            entries: [
                GuideEntry(
                    title: "Pedal sensor type",
                    text: "Leave it at the factory setting, DoubleSignal-24 on BBS02 and BBSHD kits."
                ),
                GuideEntry(
                    title: "Designated assist level",
                    text: "Normally By display. A fixed level makes pedal assist ignore the display's level."
                ),
                GuideEntry(
                    title: "Speed limit",
                    text: "The road speed at which pedal assist stops. By display uses the limit set in the display."
                ),
                GuideEntry(
                    title: "Start current",
                    text: """
                        How much power you get the moment you start pedaling. One of the most important settings for \
                        protecting the controller: high values give a jolting start and a big current surge.
                        """,
                    typical: "Karl's tune: 10 %; 30 % or less in general; as low as 1 % with an internal gear hub",
                    caution: "At 100% the start can draw over 1 kW."
                ),
                GuideEntry(
                    title: "Slow-start mode",
                    text: """
                        How quickly power ramps up after you start pedaling, from 1 to 8. Extreme values make starts \
                        jerky or hard on the controller, especially when starting in a high gear.
                        """,
                    typical: "Tunes use 3–6; Karl's tune: 4"
                ),
                GuideEntry(
                    title: "Start degree (signals)",
                    text: """
                        How far you must turn the cranks before the motor starts, in pedal sensor pulses; 24 pulses \
                        are one full turn. Fewer pulses make assist start sooner. 0 and 1 don't work properly.
                        """,
                    typical: "Tunes use 4; Karl's tune: 2"
                ),
                GuideEntry(
                    title: "Work mode",
                    text: "Hardly any noticeable effect. Leave it at Undetermined."
                ),
                GuideEntry(
                    title: "Stop delay",
                    text: """
                        How long the motor keeps pushing after you stop pedaling, in steps of 10 ms. Shorter feels \
                        more responsive and safer when braking.
                        """,
                    typical: "Factory 25 (250 ms); Karl recommends 5 (50 ms) on the BBSHD and first BBS02 version",
                    caution: "0 turns pedal assist off. On the second BBS02 controller version, values below 10 stop pedal assist working."
                ),
                GuideEntry(
                    title: "Current decay",
                    text: """
                        The pedaling speed (cadence) at which power starts to drop as you pedal faster, from 1 to 8. \
                        8 keeps full power up to the highest cadence; lower values reduce it sooner.
                        """,
                    typical: "Karl's tune: 8"
                ),
                GuideEntry(
                    title: "Stop decay",
                    text: "How smoothly power fades after you stop pedaling, in steps of 10 ms. 0 cuts power at once.",
                    typical: "Most tunes 0; 20 for a softer stop"
                ),
                GuideEntry(
                    title: "Keep current",
                    text: """
                        How much of the level's current remains when you pedal fast. At 60%, power eases down to 60% \
                        as your cadence rises; at low cadence you always get the full amount.
                        """,
                    typical: "Most tunes 60 %; Karl's tune: 80 %"
                ),
            ]
        ),
        GuideSection(
            title: "Throttle Handle tab",
            entries: [
                GuideEntry(
                    title: "Start voltage",
                    text: """
                        The throttle signal at which the motor starts. Too low and the motor may run, or the display \
                        shows an error, with the throttle released. Check it again if you fit a different throttle.
                        """,
                    typical: "1.1 V; keep between 1.0 and 1.5 V"
                ),
                GuideEntry(
                    title: "End voltage",
                    text: """
                        The throttle signal for full power. Up to 4.2 V uses the throttle's full travel. For an \
                        aftermarket throttle, measure its full-throttle voltage and set slightly below it.
                        """,
                    typical: "3.5 V factory; 4.2 V suggested by Empowered Cycles"
                ),
                GuideEntry(
                    title: "Mode",
                    text: """
                        **Current** feels smoother and is easier on the controller; pair it with a start current \
                        of 10% or less. **Speed** feels stronger and is Karl's preference. Some newer BBS02 \
                        controllers are jerky in Current mode; use Speed if yours is.
                        """
                ),
                GuideEntry(
                    title: "Designated assist level",
                    text: """
                        Which assist level's limits the throttle uses. 9 gives full throttle power; a lower level, \
                        such as 6, makes the throttle tamer.
                        """,
                    typical: "Karl's tune: 9"
                ),
                GuideEntry(
                    title: "Speed limit",
                    text: "In Karl's tests, setting 40 km/h removed a 2–3 second throttle delay in assist level 0.",
                    typical: "By display, or 40 km/h"
                ),
                GuideEntry(
                    title: "Start current",
                    text: "How much power the throttle gives as it starts. Lower values start more smoothly.",
                    typical: "5–10 %; down to 1 % with an internal gear hub",
                    caution: "Above 20% is unwise."
                ),
            ]
        ),
        GuideSection(
            title: "Protecting your controller while riding",
            entries: [
                GuideEntry(
                    title: "Watch your gear on hills",
                    text: """
                        Full throttle in a high gear on a steep hill, with the cranks turning slowly, is the surest way \
                        to burn out the controller. Shift down before hills and before stopping, and keep your cadence up.
                        """
                ),
                GuideEntry(
                    title: "Consider a smaller chainring",
                    text: "For trails and steep terrain a smaller front chainring (Karl uses 34 teeth) keeps the motor spinning faster."
                ),
                GuideEntry(
                    title: "Add a temperature probe",
                    text: "Karl recommends fitting a temperature probe to the controller: a few dollars and a few minutes of work."
                ),
            ]
        ),
    ]
}
