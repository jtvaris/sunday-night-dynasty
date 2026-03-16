# Dynasty — NFL Football Manager Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an iPad NFL Football Manager simulation game with deep scouting, draft, player development, coaching, media, and 3D match engine.

**Architecture:** Clean Architecture with SwiftUI for UI, SceneKit for 3D match view, Swift Data for persistence, and a pure Swift game engine with no framework dependencies. Domain models are independent of UI and persistence layers.

**Tech Stack:** Swift 5, SwiftUI, SceneKit, Swift Data, XCTest, iPadOS 26.2+

---

## Phase 1: Foundation (Project Setup + Domain Models)

The goal of Phase 1 is to convert the SpriteKit template to a SwiftUI app, establish the project structure, create core domain models, and get a basic "new career → see roster → advance week" loop working.

### Task 1: Convert to SwiftUI App Lifecycle

**Files:**
- Delete: `dynasty/dynasty/GameScene.swift`
- Delete: `dynasty/dynasty/GameScene.sks`
- Delete: `dynasty/dynasty/Actions.sks`
- Delete: `dynasty/dynasty/GameViewController.swift`
- Delete: `dynasty/dynasty/Base.lproj/Main.storyboard` (if exists)
- Modify: `dynasty/dynasty/AppDelegate.swift` → replace with SwiftUI App
- Create: `dynasty/dynasty/DynastyApp.swift`
- Create: `dynasty/dynasty/ContentView.swift`

**Step 1: Delete SpriteKit template files**

Remove `GameScene.swift`, `GameScene.sks`, `Actions.sks`, `GameViewController.swift`, and any storyboard files. These are unused template files.

**Step 2: Create SwiftUI App entry point**

Create `dynasty/dynasty/DynastyApp.swift`:

```swift
import SwiftUI

@main
struct DynastyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

Create `dynasty/dynasty/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            Text("Dynasty")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
}

#Preview {
    ContentView()
}
```

**Step 3: Remove @main from AppDelegate and simplify**

Replace `AppDelegate.swift` contents — remove `@main` attribute, keep only if needed for lifecycle events, or delete entirely since SwiftUI App handles everything.

Delete `AppDelegate.swift` entirely — `DynastyApp.swift` is the new entry point.

**Step 4: Update Info.plist settings**

In the Xcode project build settings, remove references to `Main.storyboard` (UIMainStoryboardFile). The project uses `GENERATE_INFOPLIST_FILE = YES` so we need to remove:
- `INFOPLIST_KEY_UIMainStoryboardFile = Main` from both Debug and Release build configurations in `project.pbxproj`
- `INFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen` can stay (needed for launch)

**Step 5: Build and verify**

Run: `xcodebuild -project dynasty/dynasty.xcodeproj -scheme dynasty -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build`

Expected: BUILD SUCCEEDED, app shows "Dynasty" text.

**Step 6: Commit**

```bash
git add -A
git commit -m "Convert from SpriteKit template to SwiftUI app lifecycle"
```

---

### Task 2: Create Project Folder Structure

**Step 1: Create directory structure**

```
dynasty/dynasty/
├── DynastyApp.swift
├── ContentView.swift
├── Domain/
│   ├── Models/
│   │   ├── Player/
│   │   ├── Team/
│   │   ├── Coach/
│   │   ├── League/
│   │   ├── Contract/
│   │   ├── Draft/
│   │   └── Scouting/
│   └── Enums/
├── Engine/
│   ├── Simulation/
│   ├── Draft/
│   ├── Scouting/
│   ├── Contract/
│   ├── PlayerDevelopment/
│   ├── Media/
│   └── Event/
├── Data/
│   ├── Persistence/
│   └── Import/
├── UI/
│   ├── MainMenu/
│   ├── Career/
│   ├── Roster/
│   ├── Draft/
│   ├── Scouting/
│   ├── Match/
│   ├── Standings/
│   ├── Schedule/
│   ├── Staff/
│   ├── Contracts/
│   ├── News/
│   └── Common/
├── ViewModel/
└── Assets.xcassets/
```

Create all directories. Since the project uses `PBXFileSystemSynchronizedRootGroup`, Xcode auto-discovers files — no need to modify `project.pbxproj`.

**Step 2: Add placeholder files**

Add a `.gitkeep` file in each leaf directory so git tracks the empty folders.

**Step 3: Commit**

```bash
git add -A
git commit -m "Add project folder structure for clean architecture"
```

---

### Task 3: Core Enums and Value Types

**Files:**
- Create: `dynasty/dynasty/Domain/Enums/Position.swift`
- Create: `dynasty/dynasty/Domain/Enums/Conference.swift`
- Create: `dynasty/dynasty/Domain/Enums/Division.swift`
- Create: `dynasty/dynasty/Domain/Enums/PersonalityArchetype.swift`
- Create: `dynasty/dynasty/Domain/Enums/Motivation.swift`
- Create: `dynasty/dynasty/Domain/Enums/Scheme.swift`
- Create: `dynasty/dynasty/Domain/Enums/SeasonPhase.swift`
- Create: `dynasty/dynasty/Domain/Enums/CapMode.swift`

**Step 1: Create Position enum**

```swift
// Position.swift
import Foundation

enum Position: String, Codable, CaseIterable, Identifiable {
    // Offense
    case qb = "QB"
    case rb = "RB"
    case fb = "FB"
    case wr = "WR"
    case te = "TE"
    case lt = "LT"
    case lg = "LG"
    case c = "C"
    case rg = "RG"
    case rt = "RT"

    // Defense
    case de = "DE"
    case dt = "DT"
    case olb = "OLB"
    case mlb = "MLB"
    case cb = "CB"
    case fs = "FS"
    case ss = "SS"

    // Special Teams
    case k = "K"
    case p = "P"

    var id: String { rawValue }

    var side: PositionSide {
        switch self {
        case .qb, .rb, .fb, .wr, .te, .lt, .lg, .c, .rg, .rt:
            return .offense
        case .de, .dt, .olb, .mlb, .cb, .fs, .ss:
            return .defense
        case .k, .p:
            return .specialTeams
        }
    }

    var peakAgeRange: ClosedRange<Int> {
        switch self {
        case .qb: return 28...35
        case .rb, .fb: return 24...28
        case .wr: return 26...31
        case .te: return 26...31
        case .lt, .lg, .c, .rg, .rt: return 26...32
        case .de, .dt: return 26...31
        case .olb, .mlb: return 25...30
        case .cb: return 25...30
        case .fs, .ss: return 26...31
        case .k, .p: return 28...38
        }
    }
}

enum PositionSide: String, Codable {
    case offense
    case defense
    case specialTeams
}
```

**Step 2: Create Conference and Division enums**

```swift
// Conference.swift
import Foundation

enum Conference: String, Codable, CaseIterable {
    case afc = "AFC"
    case nfc = "NFC"
}

// Division.swift
import Foundation

enum Division: String, Codable, CaseIterable {
    case north = "North"
    case south = "South"
    case east = "East"
    case west = "West"
}
```

**Step 3: Create personality and motivation enums**

```swift
// PersonalityArchetype.swift
import Foundation

enum PersonalityArchetype: String, Codable, CaseIterable {
    case teamLeader = "Team Leader"
    case loneWolf = "Lone Wolf"
    case feelPlayer = "Feel Player"
    case steadyPerformer = "Steady Performer"
    case dramaQueen = "Drama Queen"
    case quietProfessional = "Quiet Professional"
    case mentor = "Mentor"
    case fieryCompetitor = "Fiery Competitor"
    case classClown = "Class Clown"
}

// Motivation.swift
import Foundation

enum Motivation: String, Codable, CaseIterable {
    case money = "Money"
    case winning = "Winning"
    case stats = "Stats"
    case loyalty = "Loyalty"
    case fame = "Fame"
}
```

**Step 4: Create scheme enums**

```swift
// Scheme.swift
import Foundation

enum OffensiveScheme: String, Codable, CaseIterable {
    case westCoast = "West Coast"
    case airRaid = "Air Raid"
    case spread = "Spread"
    case powerRun = "Power Run"
    case shanahan = "Shanahan Wide Zone"
    case proPassing = "Pro Passing"
    case rpo = "RPO Heavy"
    case option = "Option"
}

enum DefensiveScheme: String, Codable, CaseIterable {
    case base34 = "3-4"
    case base43 = "4-3"
    case cover3 = "Cover 3"
    case pressMan = "Press Man"
    case tampa2 = "Tampa 2"
    case multiple = "Multiple"
    case hybrid = "Hybrid 3-3-5"
}
```

**Step 5: Create season phase and cap mode enums**

```swift
// SeasonPhase.swift
import Foundation

enum SeasonPhase: String, Codable {
    case superBowl = "Super Bowl"
    case proBowl = "Pro Bowl"
    case coachingChanges = "Coaching Changes"
    case combine = "Combine"
    case freeAgency = "Free Agency"
    case draft = "Draft"
    case otas = "OTAs"
    case trainingCamp = "Training Camp"
    case preseason = "Preseason"
    case rosterCuts = "Roster Cuts"
    case regularSeason = "Regular Season"
    case tradeDeadline = "Trade Deadline"
    case playoffs = "Playoffs"
}

// CapMode.swift
import Foundation

enum CapMode: String, Codable {
    case simple = "Simple"
    case realistic = "Realistic"
}
```

**Step 6: Build and verify**

Run: `xcodebuild -project dynasty/dynasty.xcodeproj -scheme dynasty -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build`

Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add dynasty/dynasty/Domain/Enums/
git commit -m "Add core domain enums: Position, Conference, Division, Personality, Scheme, etc."
```

---

### Task 4: Player Domain Model

**Files:**
- Create: `dynasty/dynasty/Domain/Models/Player/PlayerAttributes.swift`
- Create: `dynasty/dynasty/Domain/Models/Player/PlayerPersonality.swift`
- Create: `dynasty/dynasty/Domain/Models/Player/Player.swift`

**Step 1: Create PlayerAttributes**

```swift
// PlayerAttributes.swift
import Foundation

struct PhysicalAttributes: Codable, Equatable {
    var speed: Int          // 1-99
    var acceleration: Int
    var strength: Int
    var agility: Int
    var stamina: Int
    var durability: Int

    static func random() -> PhysicalAttributes {
        PhysicalAttributes(
            speed: Int.random(in: 40...99),
            acceleration: Int.random(in: 40...99),
            strength: Int.random(in: 40...99),
            agility: Int.random(in: 40...99),
            stamina: Int.random(in: 40...99),
            durability: Int.random(in: 40...99)
        )
    }
}

struct MentalAttributes: Codable, Equatable {
    var awareness: Int      // 1-99
    var decisionMaking: Int
    var clutch: Int
    var workEthic: Int
    var coachability: Int
    var leadership: Int

    static func random() -> MentalAttributes {
        MentalAttributes(
            awareness: Int.random(in: 40...99),
            decisionMaking: Int.random(in: 40...99),
            clutch: Int.random(in: 40...99),
            workEthic: Int.random(in: 40...99),
            coachability: Int.random(in: 40...99),
            leadership: Int.random(in: 40...99)
        )
    }
}

struct QBAttributes: Codable, Equatable {
    var armStrength: Int
    var accuracyShort: Int
    var accuracyMid: Int
    var accuracyDeep: Int
    var pocketPresence: Int
    var scrambling: Int
}

struct WRAttributes: Codable, Equatable {
    var routeRunning: Int
    var catching: Int
    var release: Int
    var spectacularCatch: Int
}

struct RBAttributes: Codable, Equatable {
    var vision: Int
    var elusiveness: Int
    var breakTackle: Int
    var receiving: Int
}

struct OLAttributes: Codable, Equatable {
    var runBlock: Int
    var passBlock: Int
    var pull: Int
    var anchor: Int
}

struct DLAttributes: Codable, Equatable {
    var passRush: Int
    var blockShedding: Int
    var powerMoves: Int
    var finesseMoves: Int
}

struct LBAttributes: Codable, Equatable {
    var tackling: Int
    var zoneCoverage: Int
    var manCoverage: Int
    var blitzing: Int
}

struct DBAttributes: Codable, Equatable {
    var manCoverage: Int
    var zoneCoverage: Int
    var press: Int
    var ballSkills: Int
}

struct KickingAttributes: Codable, Equatable {
    var kickPower: Int
    var kickAccuracy: Int
}

enum PositionAttributes: Codable, Equatable {
    case qb(QBAttributes)
    case wr(WRAttributes)
    case rb(RBAttributes)
    case ol(OLAttributes)
    case dl(DLAttributes)
    case lb(LBAttributes)
    case db(DBAttributes)
    case kicking(KickingAttributes)
}
```

**Step 2: Create PlayerPersonality**

```swift
// PlayerPersonality.swift
import Foundation

struct PlayerPersonality: Codable, Equatable {
    let archetype: PersonalityArchetype
    let motivation: Motivation

    var isDramaticInMedia: Bool {
        archetype == .dramaQueen || archetype == .fieryCompetitor
    }

    var isMentor: Bool {
        archetype == .mentor || archetype == .teamLeader
    }

    var isMoodDependent: Bool {
        archetype == .feelPlayer || archetype == .dramaQueen
    }

    var isConsistent: Bool {
        archetype == .steadyPerformer || archetype == .quietProfessional
    }
}
```

**Step 3: Create Player model**

```swift
// Player.swift
import Foundation
import SwiftData

@Model
final class Player {
    var id: UUID
    var firstName: String
    var lastName: String
    var position: Position
    var age: Int
    var yearsPro: Int

    // Attributes
    var physical: PhysicalAttributes
    var mental: MentalAttributes
    var positionAttributes: PositionAttributes

    // Personality
    var personality: PlayerPersonality

    // Hidden potential (1-99, not directly visible to player)
    var truePotential: Int

    // Current state
    var morale: Int          // 1-100
    var fatigue: Int         // 0-100 (0 = fresh)
    var isInjured: Bool
    var injuryWeeksRemaining: Int

    // Career
    var teamID: UUID?
    var contractYearsRemaining: Int
    var annualSalary: Int    // in thousands

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    var overall: Int {
        let physAvg = (physical.speed + physical.acceleration + physical.strength +
                       physical.agility + physical.stamina + physical.durability) / 6
        let mentAvg = (mental.awareness + mental.decisionMaking + mental.clutch) / 3
        return (physAvg + mentAvg) / 2
    }

    init(
        firstName: String,
        lastName: String,
        position: Position,
        age: Int,
        yearsPro: Int = 0,
        physical: PhysicalAttributes = .random(),
        mental: MentalAttributes = .random(),
        positionAttributes: PositionAttributes,
        personality: PlayerPersonality,
        truePotential: Int = Int.random(in: 50...99)
    ) {
        self.id = UUID()
        self.firstName = firstName
        self.lastName = lastName
        self.position = position
        self.age = age
        self.yearsPro = yearsPro
        self.physical = physical
        self.mental = mental
        self.positionAttributes = positionAttributes
        self.personality = personality
        self.truePotential = truePotential
        self.morale = 70
        self.fatigue = 0
        self.isInjured = false
        self.injuryWeeksRemaining = 0
        self.contractYearsRemaining = 0
        self.annualSalary = 0
    }
}
```

**Step 4: Build and verify**

Run: `xcodebuild -project dynasty/dynasty.xcodeproj -scheme dynasty -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build`

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add dynasty/dynasty/Domain/Models/Player/
git commit -m "Add Player domain model with attributes, personality, and position-specific stats"
```

---

### Task 5: Team and League Domain Models

**Files:**
- Create: `dynasty/dynasty/Domain/Models/Team/Team.swift`
- Create: `dynasty/dynasty/Domain/Models/Team/Owner.swift`
- Create: `dynasty/dynasty/Domain/Models/League/League.swift`
- Create: `dynasty/dynasty/Domain/Models/League/Season.swift`
- Create: `dynasty/dynasty/Domain/Enums/MediaMarket.swift`

**Step 1: Create MediaMarket enum**

```swift
// MediaMarket.swift
import Foundation

enum MediaMarket: String, Codable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var mediaPressureMultiplier: Double {
        switch self {
        case .small: return 0.7
        case .medium: return 1.0
        case .large: return 1.5
        }
    }

    var freeAgentAttraction: Double {
        switch self {
        case .small: return 0.8
        case .medium: return 1.0
        case .large: return 1.3
        }
    }
}
```

**Step 2: Create Owner model**

```swift
// Owner.swift
import Foundation
import SwiftData

@Model
final class Owner {
    var id: UUID
    var name: String
    var patience: Int           // 1-10 (how many bad seasons before firing)
    var spendingWillingness: Int // 1-99
    var meddling: Int           // 1-99 (how much they interfere)
    var prefersWinNow: Bool

    var satisfaction: Int        // 0-100

    init(
        name: String,
        patience: Int = 5,
        spendingWillingness: Int = 50,
        meddling: Int = 30,
        prefersWinNow: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.patience = patience
        self.spendingWillingness = spendingWillingness
        self.meddling = meddling
        self.prefersWinNow = prefersWinNow
        self.satisfaction = 70
    }
}
```

**Step 3: Create Team model**

```swift
// Team.swift
import Foundation
import SwiftData

@Model
final class Team {
    var id: UUID
    var name: String             // e.g. "Bears"
    var city: String             // e.g. "Chicago"
    var abbreviation: String     // e.g. "CHI"
    var conference: Conference
    var division: Division
    var mediaMarket: MediaMarket

    // Relationships
    var owner: Owner?
    @Relationship(deleteRule: .nullify) var players: [Player]

    // Season record
    var wins: Int
    var losses: Int
    var ties: Int

    // Finances
    var salaryCap: Int          // in thousands
    var currentCapUsage: Int    // in thousands

    var fullName: String {
        "\(city) \(name)"
    }

    var record: String {
        if ties > 0 {
            return "\(wins)-\(losses)-\(ties)"
        }
        return "\(wins)-\(losses)"
    }

    var availableCap: Int {
        salaryCap - currentCapUsage
    }

    init(
        name: String,
        city: String,
        abbreviation: String,
        conference: Conference,
        division: Division,
        mediaMarket: MediaMarket
    ) {
        self.id = UUID()
        self.name = name
        self.city = city
        self.abbreviation = abbreviation
        self.conference = conference
        self.division = division
        self.mediaMarket = mediaMarket
        self.players = []
        self.wins = 0
        self.losses = 0
        self.ties = 0
        self.salaryCap = 255_000  // $255M in thousands
        self.currentCapUsage = 0
    }
}
```

**Step 4: Create League and Season models**

```swift
// League.swift
import Foundation
import SwiftData

@Model
final class League {
    var id: UUID
    var name: String
    @Relationship(deleteRule: .cascade) var teams: [Team]
    var currentSeason: Int       // year, e.g. 2026
    var currentWeek: Int
    var currentPhase: SeasonPhase

    init(name: String = "National Football League", startYear: Int = 2026) {
        self.id = UUID()
        self.name = name
        self.teams = []
        self.currentSeason = startYear
        self.currentWeek = 1
        self.currentPhase = .preseason
    }
}

// Season.swift
import Foundation
import SwiftData

@Model
final class Season {
    var id: UUID
    var year: Int
    var leagueID: UUID

    init(year: Int, leagueID: UUID) {
        self.id = UUID()
        self.year = year
        self.leagueID = leagueID
    }
}
```

**Step 5: Build and verify**

Run: `xcodebuild -project dynasty/dynasty.xcodeproj -scheme dynasty -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build`

Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add dynasty/dynasty/Domain/
git commit -m "Add Team, Owner, League, Season domain models"
```

---

### Task 6: Coach Domain Model

**Files:**
- Create: `dynasty/dynasty/Domain/Models/Coach/Coach.swift`
- Create: `dynasty/dynasty/Domain/Enums/CoachRole.swift`

**Step 1: Create CoachRole enum**

```swift
// CoachRole.swift
import Foundation

enum CoachRole: String, Codable, CaseIterable {
    case headCoach = "Head Coach"
    case offensiveCoordinator = "Offensive Coordinator"
    case defensiveCoordinator = "Defensive Coordinator"
    case specialTeamsCoordinator = "Special Teams Coordinator"
    case qbCoach = "QB Coach"
    case rbCoach = "RB Coach"
    case wrCoach = "WR Coach"
    case olCoach = "OL Coach"
    case dlCoach = "DL Coach"
    case lbCoach = "LB Coach"
    case dbCoach = "DB Coach"
    case strengthCoach = "Strength & Conditioning"
}
```

**Step 2: Create Coach model**

```swift
// Coach.swift
import Foundation
import SwiftData

@Model
final class Coach {
    var id: UUID
    var firstName: String
    var lastName: String
    var age: Int
    var role: CoachRole

    // Scheme (only relevant for coordinators and HC)
    var offensiveScheme: OffensiveScheme?
    var defensiveScheme: DefensiveScheme?

    // Attributes (1-99)
    var playCalling: Int
    var playerDevelopment: Int
    var reputation: Int
    var adaptability: Int

    // Personality
    var personality: PersonalityArchetype

    // Career
    var teamID: UUID?
    var yearsExperience: Int

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    init(
        firstName: String,
        lastName: String,
        age: Int,
        role: CoachRole,
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil,
        playCalling: Int = 50,
        playerDevelopment: Int = 50,
        reputation: Int = 50,
        adaptability: Int = 50,
        personality: PersonalityArchetype = .quietProfessional
    ) {
        self.id = UUID()
        self.firstName = firstName
        self.lastName = lastName
        self.age = age
        self.role = role
        self.offensiveScheme = offensiveScheme
        self.defensiveScheme = defensiveScheme
        self.playCalling = playCalling
        self.playerDevelopment = playerDevelopment
        self.reputation = reputation
        self.adaptability = adaptability
        self.personality = personality
        self.yearsExperience = 0
    }
}
```

**Step 3: Build and verify, then commit**

```bash
git add dynasty/dynasty/Domain/
git commit -m "Add Coach domain model with roles and schemes"
```

---

### Task 7: Career / Save Game Model

**Files:**
- Create: `dynasty/dynasty/Domain/Models/Career.swift`
- Create: `dynasty/dynasty/Domain/Enums/CareerRole.swift`

**Step 1: Create CareerRole and Career**

```swift
// CareerRole.swift
import Foundation

enum CareerRole: String, Codable {
    case gm = "General Manager"
    case gmAndHeadCoach = "GM & Head Coach"
}

// Career.swift
import Foundation
import SwiftData

@Model
final class Career {
    var id: UUID
    var playerName: String
    var role: CareerRole
    var capMode: CapMode
    var teamID: UUID?
    var leagueID: UUID?

    // GM/HC reputation
    var reputation: Int          // 1-99
    var totalWins: Int
    var totalLosses: Int
    var playoffAppearances: Int
    var championships: Int
    var yearsFired: Int

    // Current season tracking
    var currentSeason: Int
    var currentWeek: Int
    var currentPhase: SeasonPhase

    var winPercentage: Double {
        let total = totalWins + totalLosses
        guard total > 0 else { return 0 }
        return Double(totalWins) / Double(total)
    }

    init(
        playerName: String,
        role: CareerRole,
        capMode: CapMode,
        startYear: Int = 2026
    ) {
        self.id = UUID()
        self.playerName = playerName
        self.role = role
        self.capMode = capMode
        self.reputation = 50
        self.totalWins = 0
        self.totalLosses = 0
        self.playoffAppearances = 0
        self.championships = 0
        self.yearsFired = 0
        self.currentSeason = startYear
        self.currentWeek = 1
        self.currentPhase = .preseason
    }
}
```

**Step 2: Build, verify, and commit**

```bash
git add dynasty/dynasty/Domain/
git commit -m "Add Career (save game) model with role and cap mode selection"
```

---

### Task 8: NFL Team Data Generator

**Files:**
- Create: `dynasty/dynasty/Data/Import/NFLTeamData.swift`
- Create: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift`
- Create: `dynasty/dynasty/Data/Import/LeagueGenerator.swift`

**Step 1: Create NFL team definitions**

```swift
// NFLTeamData.swift
import Foundation

struct NFLTeamDefinition {
    let name: String
    let city: String
    let abbreviation: String
    let conference: Conference
    let division: Division
    let mediaMarket: MediaMarket
}

enum NFLTeamData {
    static let allTeams: [NFLTeamDefinition] = [
        // AFC East
        NFLTeamDefinition(name: "Bills", city: "Buffalo", abbreviation: "BUF", conference: .afc, division: .east, mediaMarket: .medium),
        NFLTeamDefinition(name: "Dolphins", city: "Miami", abbreviation: "MIA", conference: .afc, division: .east, mediaMarket: .medium),
        NFLTeamDefinition(name: "Patriots", city: "New England", abbreviation: "NE", conference: .afc, division: .east, mediaMarket: .large),
        NFLTeamDefinition(name: "Jets", city: "New York", abbreviation: "NYJ", conference: .afc, division: .east, mediaMarket: .large),

        // AFC North
        NFLTeamDefinition(name: "Ravens", city: "Baltimore", abbreviation: "BAL", conference: .afc, division: .north, mediaMarket: .medium),
        NFLTeamDefinition(name: "Bengals", city: "Cincinnati", abbreviation: "CIN", conference: .afc, division: .north, mediaMarket: .medium),
        NFLTeamDefinition(name: "Browns", city: "Cleveland", abbreviation: "CLE", conference: .afc, division: .north, mediaMarket: .medium),
        NFLTeamDefinition(name: "Steelers", city: "Pittsburgh", abbreviation: "PIT", conference: .afc, division: .north, mediaMarket: .medium),

        // AFC South
        NFLTeamDefinition(name: "Texans", city: "Houston", abbreviation: "HOU", conference: .afc, division: .south, mediaMarket: .large),
        NFLTeamDefinition(name: "Colts", city: "Indianapolis", abbreviation: "IND", conference: .afc, division: .south, mediaMarket: .medium),
        NFLTeamDefinition(name: "Jaguars", city: "Jacksonville", abbreviation: "JAX", conference: .afc, division: .south, mediaMarket: .small),
        NFLTeamDefinition(name: "Titans", city: "Tennessee", abbreviation: "TEN", conference: .afc, division: .south, mediaMarket: .small),

        // AFC West
        NFLTeamDefinition(name: "Broncos", city: "Denver", abbreviation: "DEN", conference: .afc, division: .west, mediaMarket: .medium),
        NFLTeamDefinition(name: "Chiefs", city: "Kansas City", abbreviation: "KC", conference: .afc, division: .west, mediaMarket: .medium),
        NFLTeamDefinition(name: "Raiders", city: "Las Vegas", abbreviation: "LV", conference: .afc, division: .west, mediaMarket: .large),
        NFLTeamDefinition(name: "Chargers", city: "Los Angeles", abbreviation: "LAC", conference: .afc, division: .west, mediaMarket: .large),

        // NFC East
        NFLTeamDefinition(name: "Cowboys", city: "Dallas", abbreviation: "DAL", conference: .nfc, division: .east, mediaMarket: .large),
        NFLTeamDefinition(name: "Giants", city: "New York", abbreviation: "NYG", conference: .nfc, division: .east, mediaMarket: .large),
        NFLTeamDefinition(name: "Eagles", city: "Philadelphia", abbreviation: "PHI", conference: .nfc, division: .east, mediaMarket: .large),
        NFLTeamDefinition(name: "Commanders", city: "Washington", abbreviation: "WAS", conference: .nfc, division: .east, mediaMarket: .large),

        // NFC North
        NFLTeamDefinition(name: "Bears", city: "Chicago", abbreviation: "CHI", conference: .nfc, division: .north, mediaMarket: .large),
        NFLTeamDefinition(name: "Lions", city: "Detroit", abbreviation: "DET", conference: .nfc, division: .north, mediaMarket: .medium),
        NFLTeamDefinition(name: "Packers", city: "Green Bay", abbreviation: "GB", conference: .nfc, division: .north, mediaMarket: .small),
        NFLTeamDefinition(name: "Vikings", city: "Minnesota", abbreviation: "MIN", conference: .nfc, division: .north, mediaMarket: .medium),

        // NFC South
        NFLTeamDefinition(name: "Falcons", city: "Atlanta", abbreviation: "ATL", conference: .nfc, division: .south, mediaMarket: .medium),
        NFLTeamDefinition(name: "Panthers", city: "Carolina", abbreviation: "CAR", conference: .nfc, division: .south, mediaMarket: .medium),
        NFLTeamDefinition(name: "Saints", city: "New Orleans", abbreviation: "NO", conference: .nfc, division: .south, mediaMarket: .medium),
        NFLTeamDefinition(name: "Buccaneers", city: "Tampa Bay", abbreviation: "TB", conference: .nfc, division: .south, mediaMarket: .medium),

        // NFC West
        NFLTeamDefinition(name: "Cardinals", city: "Arizona", abbreviation: "ARI", conference: .nfc, division: .west, mediaMarket: .medium),
        NFLTeamDefinition(name: "Rams", city: "Los Angeles", abbreviation: "LAR", conference: .nfc, division: .west, mediaMarket: .large),
        NFLTeamDefinition(name: "49ers", city: "San Francisco", abbreviation: "SF", conference: .nfc, division: .west, mediaMarket: .large),
        NFLTeamDefinition(name: "Seahawks", city: "Seattle", abbreviation: "SEA", conference: .nfc, division: .west, mediaMarket: .medium),
    ]
}
```

**Step 2: Create random name generator**

```swift
// RandomNameGenerator.swift
import Foundation

enum RandomNameGenerator {
    static let firstNames = [
        "James", "Marcus", "Darius", "Tyrell", "Brandon", "DeShawn",
        "Chris", "Tyler", "Patrick", "Justin", "Caleb", "Jordan",
        "Malik", "Antonio", "Derrick", "Khalil", "Josh", "Trevor",
        "Lamar", "Jalen", "Devon", "Trey", "Micah", "Isaiah",
        "Cameron", "Xavier", "DK", "Chase", "Ja'Marr", "CeeDee",
        "Brock", "Tua", "Baker", "Joe", "Dak", "Kyler",
        "Aaron", "Davante", "Travis", "Nick", "George", "Myles",
        "TJ", "Sauce", "Amon-Ra", "Puka", "Sam", "Jayden"
    ]

    static let lastNames = [
        "Johnson", "Williams", "Brown", "Jones", "Davis", "Smith",
        "Wilson", "Thomas", "Jackson", "Harris", "Robinson", "Lewis",
        "Walker", "Hall", "Allen", "Young", "King", "Wright",
        "Hill", "Green", "Adams", "Baker", "Carter", "Mitchell",
        "Turner", "Phillips", "Campbell", "Parker", "Evans", "Edwards",
        "Collins", "Stewart", "Morris", "Rogers", "Reed", "Cook",
        "Morgan", "Bell", "Murphy", "Bailey", "Cooper", "Richardson",
        "Howard", "Ward", "Brooks", "Sanders", "Price", "Watson"
    ]

    static func randomName() -> (first: String, last: String) {
        let first = firstNames.randomElement()!
        let last = lastNames.randomElement()!
        return (first, last)
    }
}
```

**Step 3: Create LeagueGenerator**

```swift
// LeagueGenerator.swift
import Foundation

enum LeagueGenerator {
    static func generateLeague(startYear: Int = 2026) -> (league: League, teams: [Team], players: [Player], owners: [Owner], coaches: [Coach]) {
        let league = League(startYear: startYear)
        var teams: [Team] = []
        var allPlayers: [Player] = []
        var owners: [Owner] = []
        var coaches: [Coach] = []

        for def in NFLTeamData.allTeams {
            let team = Team(
                name: def.name,
                city: def.city,
                abbreviation: def.abbreviation,
                conference: def.conference,
                division: def.division,
                mediaMarket: def.mediaMarket
            )

            let owner = generateOwner(for: team)
            team.owner = owner
            owners.append(owner)

            let roster = generateRoster(for: team)
            team.players = roster
            allPlayers.append(contentsOf: roster)

            let staff = generateCoachingStaff(for: team)
            coaches.append(contentsOf: staff)

            teams.append(team)
        }

        league.teams = teams
        return (league, teams, allPlayers, owners, coaches)
    }

    private static func generateOwner(for team: Team) -> Owner {
        let name = RandomNameGenerator.randomName()
        return Owner(
            name: "\(name.first) \(name.last)",
            patience: Int.random(in: 2...8),
            spendingWillingness: Int.random(in: 30...90),
            meddling: Int.random(in: 10...80),
            prefersWinNow: Bool.random()
        )
    }

    private static func generateRoster(for team: Team) -> [Player] {
        // Generate a 53-man roster with correct position counts
        let positionCounts: [(Position, Int)] = [
            (.qb, 3), (.rb, 3), (.fb, 1), (.wr, 6), (.te, 3),
            (.lt, 2), (.lg, 2), (.c, 2), (.rg, 2), (.rt, 2),
            (.de, 4), (.dt, 3), (.olb, 4), (.mlb, 3),
            (.cb, 5), (.fs, 2), (.ss, 2),
            (.k, 1), (.p, 1)
        ]

        var players: [Player] = []
        for (position, count) in positionCounts {
            for _ in 0..<count {
                let player = generatePlayer(position: position, teamID: team.id)
                players.append(player)
            }
        }
        return players
    }

    private static func generatePlayer(position: Position, teamID: UUID) -> Player {
        let name = RandomNameGenerator.randomName()
        let age = Int.random(in: 22...34)
        let posAttrs = generatePositionAttributes(for: position)
        let personality = PlayerPersonality(
            archetype: PersonalityArchetype.allCases.randomElement()!,
            motivation: Motivation.allCases.randomElement()!
        )

        let player = Player(
            firstName: name.first,
            lastName: name.last,
            position: position,
            age: age,
            yearsPro: max(0, age - 22),
            positionAttributes: posAttrs,
            personality: personality
        )
        player.teamID = teamID
        player.contractYearsRemaining = Int.random(in: 1...4)
        player.annualSalary = Int.random(in: 800...25_000) // $800K - $25M
        return player
    }

    private static func generatePositionAttributes(for position: Position) -> PositionAttributes {
        let r = { Int.random(in: 45...95) }
        switch position {
        case .qb:
            return .qb(QBAttributes(armStrength: r(), accuracyShort: r(), accuracyMid: r(), accuracyDeep: r(), pocketPresence: r(), scrambling: r()))
        case .wr:
            return .wr(WRAttributes(routeRunning: r(), catching: r(), release: r(), spectacularCatch: r()))
        case .rb, .fb:
            return .rb(RBAttributes(vision: r(), elusiveness: r(), breakTackle: r(), receiving: r()))
        case .lt, .lg, .c, .rg, .rt:
            return .ol(OLAttributes(runBlock: r(), passBlock: r(), pull: r(), anchor: r()))
        case .de, .dt:
            return .dl(DLAttributes(passRush: r(), blockShedding: r(), powerMoves: r(), finesseMoves: r()))
        case .olb, .mlb:
            return .lb(LBAttributes(tackling: r(), zoneCoverage: r(), manCoverage: r(), blitzing: r()))
        case .cb, .fs, .ss:
            return .db(DBAttributes(manCoverage: r(), zoneCoverage: r(), press: r(), ballSkills: r()))
        case .k, .p:
            return .kicking(KickingAttributes(kickPower: r(), kickAccuracy: r()))
        }
    }

    private static func generateCoachingStaff(for team: Team) -> [Coach] {
        let roles: [(CoachRole, OffensiveScheme?, DefensiveScheme?)] = [
            (.headCoach, OffensiveScheme.allCases.randomElement(), DefensiveScheme.allCases.randomElement()),
            (.offensiveCoordinator, OffensiveScheme.allCases.randomElement(), nil),
            (.defensiveCoordinator, nil, DefensiveScheme.allCases.randomElement()),
            (.specialTeamsCoordinator, nil, nil),
            (.qbCoach, nil, nil),
            (.rbCoach, nil, nil),
            (.wrCoach, nil, nil),
            (.olCoach, nil, nil),
            (.dlCoach, nil, nil),
            (.lbCoach, nil, nil),
            (.dbCoach, nil, nil),
            (.strengthCoach, nil, nil),
        ]

        return roles.map { role, offScheme, defScheme in
            let name = RandomNameGenerator.randomName()
            let coach = Coach(
                firstName: name.first,
                lastName: name.last,
                age: Int.random(in: 35...65),
                role: role,
                offensiveScheme: offScheme,
                defensiveScheme: defScheme,
                playCalling: Int.random(in: 40...90),
                playerDevelopment: Int.random(in: 40...90),
                reputation: Int.random(in: 30...85),
                adaptability: Int.random(in: 35...85),
                personality: PersonalityArchetype.allCases.randomElement()!
            )
            coach.teamID = team.id
            coach.yearsExperience = Int.random(in: 1...25)
            return coach
        }
    }
}
```

**Step 4: Build, verify, and commit**

```bash
git add dynasty/dynasty/Data/
git commit -m "Add NFL team data, random name generator, and league generator"
```

---

### Task 9: Swift Data Container Setup

**Files:**
- Create: `dynasty/dynasty/Data/Persistence/DataContainer.swift`
- Modify: `dynasty/dynasty/DynastyApp.swift`

**Step 1: Create data container**

```swift
// DataContainer.swift
import SwiftData
import Foundation

enum DataContainer {
    static func create() -> ModelContainer {
        let schema = Schema([
            Career.self,
            League.self,
            Team.self,
            Player.self,
            Owner.self,
            Coach.self,
            Season.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
```

**Step 2: Update DynastyApp.swift**

```swift
import SwiftUI
import SwiftData

@main
struct DynastyApp: App {
    let container = DataContainer.create()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
```

**Step 3: Build, verify, and commit**

```bash
git add dynasty/dynasty/Data/Persistence/ dynasty/dynasty/DynastyApp.swift
git commit -m "Set up Swift Data container with all domain models"
```

---

### Task 10: Main Menu UI

**Files:**
- Create: `dynasty/dynasty/UI/MainMenu/MainMenuView.swift`
- Create: `dynasty/dynasty/UI/Career/NewCareerView.swift`
- Create: `dynasty/dynasty/UI/Career/TeamSelectionView.swift`
- Modify: `dynasty/dynasty/ContentView.swift`

**Step 1: Create MainMenuView**

```swift
// MainMenuView.swift
import SwiftUI
import SwiftData

struct MainMenuView: View {
    @Query private var careers: [Career]

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            Text("DYNASTY")
                .font(.system(size: 64, weight: .black))
                .tracking(8)

            Text("NFL Football Manager")
                .font(.title2)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 16) {
                NavigationLink("New Career") {
                    NewCareerView()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if !careers.isEmpty {
                    NavigationLink("Continue Career") {
                        CareerListView()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CareerListView: View {
    @Query private var careers: [Career]

    var body: some View {
        List(careers) { career in
            NavigationLink(value: career) {
                VStack(alignment: .leading) {
                    Text(career.playerName)
                        .font(.headline)
                    Text("\(career.role.rawValue) — Season \(career.currentSeason)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Load Career")
    }
}
```

**Step 2: Create NewCareerView**

```swift
// NewCareerView.swift
import SwiftUI

struct NewCareerView: View {
    @State private var playerName = ""
    @State private var selectedRole: CareerRole = .gmAndHeadCoach
    @State private var selectedCapMode: CapMode = .simple
    @State private var showTeamSelection = false

    var body: some View {
        Form {
            Section("Your Profile") {
                TextField("Your Name", text: $playerName)

                Picker("Role", selection: $selectedRole) {
                    Text("General Manager").tag(CareerRole.gm)
                    Text("GM & Head Coach").tag(CareerRole.gmAndHeadCoach)
                }
            }

            Section("Salary Cap Mode") {
                Picker("Cap Complexity", selection: $selectedCapMode) {
                    Text("Simple").tag(CapMode.simple)
                    Text("Realistic").tag(CapMode.realistic)
                }
                .pickerStyle(.segmented)

                switch selectedCapMode {
                case .simple:
                    Text("Straightforward salary cap with basic contracts. Great for learning the game.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .realistic:
                    Text("Full NFL CBA mechanics: guaranteed money, dead cap, restructures, void years, and more.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Choose Team") {
                    showTeamSelection = true
                }
                .disabled(playerName.isEmpty)
            }
        }
        .navigationTitle("New Career")
        .navigationDestination(isPresented: $showTeamSelection) {
            TeamSelectionView(
                playerName: playerName,
                role: selectedRole,
                capMode: selectedCapMode
            )
        }
    }
}
```

**Step 3: Create TeamSelectionView**

```swift
// TeamSelectionView.swift
import SwiftUI
import SwiftData

struct TeamSelectionView: View {
    let playerName: String
    let role: CareerRole
    let capMode: CapMode

    @Environment(\.modelContext) private var modelContext
    @State private var navigateToCareer: Career?

    private var teamsByConference: [(String, [(String, [NFLTeamDefinition])])] {
        let conferences: [(Conference, String)] = [(.afc, "AFC"), (.nfc, "NFC")]
        return conferences.map { conf, name in
            let divisions = Division.allCases.map { div in
                let teams = NFLTeamData.allTeams.filter { $0.conference == conf && $0.division == div }
                return ("\(name) \(div.rawValue)", teams)
            }
            return (name, divisions)
        }
    }

    var body: some View {
        List {
            ForEach(teamsByConference, id: \.0) { _, divisions in
                ForEach(divisions, id: \.0) { divName, teams in
                    Section(divName) {
                        ForEach(teams, id: \.abbreviation) { team in
                            Button {
                                startCareer(with: team)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(team.city + " " + team.name)
                                            .font(.headline)
                                        Text(team.mediaMarket.rawValue + " Market")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(team.abbreviation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose Your Team")
        .navigationDestination(item: $navigateToCareer) { career in
            CareerDashboardView(career: career)
        }
    }

    private func startCareer(with teamDef: NFLTeamDefinition) {
        let career = Career(
            playerName: playerName,
            role: role,
            capMode: capMode
        )

        let (league, teams, players, owners, coaches) = LeagueGenerator.generateLeague()

        // Find the selected team
        if let selectedTeam = teams.first(where: { $0.abbreviation == teamDef.abbreviation }) {
            career.teamID = selectedTeam.id
            career.leagueID = league.id
        }

        modelContext.insert(league)
        modelContext.insert(career)
        for team in teams { modelContext.insert(team) }
        for player in players { modelContext.insert(player) }
        for owner in owners { modelContext.insert(owner) }
        for coach in coaches { modelContext.insert(coach) }

        navigateToCareer = career
    }
}
```

**Step 4: Update ContentView**

```swift
// ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            MainMenuView()
        }
    }
}

#Preview {
    ContentView()
}
```

**Step 5: Create placeholder CareerDashboardView**

Create `dynasty/dynasty/UI/Career/CareerDashboardView.swift`:

```swift
// CareerDashboardView.swift
import SwiftUI
import SwiftData

struct CareerDashboardView: View {
    let career: Career

    @Query private var teams: [Team]

    private var myTeam: Team? {
        teams.first { $0.id == career.teamID }
    }

    var body: some View {
        VStack(spacing: 20) {
            if let team = myTeam {
                Text(team.fullName)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("\(career.role.rawValue) — \(career.playerName)")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("Season \(career.currentSeason) — \(career.currentPhase.rawValue)")
                    .font(.headline)

                Text("Record: \(team.record)")
                    .font(.title2)

                Text("Roster: \(team.players.count) players")

                Spacer()
            } else {
                Text("Loading...")
            }
        }
        .padding()
        .navigationTitle("Dashboard")
        .navigationBarBackButtonHidden(true)
    }
}
```

**Step 6: Build, verify, and commit**

```bash
git add dynasty/dynasty/UI/ dynasty/dynasty/ContentView.swift
git commit -m "Add main menu, new career flow, team selection, and career dashboard UI"
```

---

### Task 11: Roster View

**Files:**
- Create: `dynasty/dynasty/UI/Roster/RosterView.swift`
- Create: `dynasty/dynasty/UI/Roster/PlayerDetailView.swift`
- Create: `dynasty/dynasty/UI/Roster/PlayerRowView.swift`

**Step 1: Create PlayerRowView**

```swift
// PlayerRowView.swift
import SwiftUI

struct PlayerRowView: View {
    let player: Player

    var body: some View {
        HStack {
            Text(player.position.rawValue)
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 36)
                .padding(4)
                .background(player.position.side == .offense ? Color.blue.opacity(0.2) : Color.red.opacity(0.2))
                .cornerRadius(4)

            VStack(alignment: .leading) {
                Text(player.fullName)
                    .font(.body)
                    .fontWeight(.medium)
                Text("Age \(player.age) — Year \(player.yearsPro + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(player.overall)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(overallColor)
        }
    }

    private var overallColor: Color {
        switch player.overall {
        case 85...: return .green
        case 70..<85: return .primary
        case 55..<70: return .orange
        default: return .red
        }
    }
}
```

**Step 2: Create RosterView**

```swift
// RosterView.swift
import SwiftUI

struct RosterView: View {
    let players: [Player]

    @State private var selectedSide: PositionSide? = nil
    @State private var sortByOverall = true

    private var filteredPlayers: [Player] {
        var result = players
        if let side = selectedSide {
            result = result.filter { $0.position.side == side }
        }
        if sortByOverall {
            result.sort { $0.overall > $1.overall }
        } else {
            result.sort { $0.position.rawValue < $1.position.rawValue }
        }
        return result
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $selectedSide) {
                    Text("All").tag(nil as PositionSide?)
                    Text("Offense").tag(PositionSide.offense as PositionSide?)
                    Text("Defense").tag(PositionSide.defense as PositionSide?)
                    Text("Special Teams").tag(PositionSide.specialTeams as PositionSide?)
                }
                .pickerStyle(.segmented)
            }

            ForEach(filteredPlayers) { player in
                NavigationLink(value: player) {
                    PlayerRowView(player: player)
                }
            }
        }
        .navigationTitle("Roster (\(players.count))")
        .navigationDestination(for: Player.self) { player in
            PlayerDetailView(player: player)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(sortByOverall ? "Sort: OVR" : "Sort: POS") {
                    sortByOverall.toggle()
                }
            }
        }
    }
}
```

**Step 3: Create PlayerDetailView**

```swift
// PlayerDetailView.swift
import SwiftUI

struct PlayerDetailView: View {
    let player: Player

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Position", value: player.position.rawValue)
                LabeledContent("Age", value: "\(player.age)")
                LabeledContent("Experience", value: "\(player.yearsPro) years")
                LabeledContent("Overall", value: "\(player.overall)")
                LabeledContent("Morale", value: "\(player.morale)")
            }

            Section("Physical Attributes") {
                AttributeRow(name: "Speed", value: player.physical.speed)
                AttributeRow(name: "Acceleration", value: player.physical.acceleration)
                AttributeRow(name: "Strength", value: player.physical.strength)
                AttributeRow(name: "Agility", value: player.physical.agility)
                AttributeRow(name: "Stamina", value: player.physical.stamina)
                AttributeRow(name: "Durability", value: player.physical.durability)
            }

            Section("Mental Attributes") {
                AttributeRow(name: "Awareness", value: player.mental.awareness)
                AttributeRow(name: "Decision Making", value: player.mental.decisionMaking)
                AttributeRow(name: "Clutch", value: player.mental.clutch)
                AttributeRow(name: "Work Ethic", value: player.mental.workEthic)
                AttributeRow(name: "Coachability", value: player.mental.coachability)
                AttributeRow(name: "Leadership", value: player.mental.leadership)
            }

            Section("Personality") {
                LabeledContent("Archetype", value: player.personality.archetype.rawValue)
                LabeledContent("Motivation", value: player.personality.motivation.rawValue)
            }

            Section("Contract") {
                LabeledContent("Years Remaining", value: "\(player.contractYearsRemaining)")
                LabeledContent("Annual Salary", value: "$\(player.annualSalary)K")
            }
        }
        .navigationTitle(player.fullName)
    }
}

struct AttributeRow: View {
    let name: String
    let value: Int

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text("\(value)")
                .fontWeight(.bold)
                .foregroundStyle(attributeColor)
        }
    }

    private var attributeColor: Color {
        switch value {
        case 85...: return .green
        case 70..<85: return .primary
        case 55..<70: return .orange
        default: return .red
        }
    }
}
```

**Step 4: Add roster navigation to CareerDashboardView**

Update `CareerDashboardView` to add a navigation link to the roster.

**Step 5: Build, verify, and commit**

```bash
git add dynasty/dynasty/UI/
git commit -m "Add roster view with player list, filtering, sorting, and detail view"
```

---

## Phase 2: Season Structure and Scheduling (outline)

- Task 12: Schedule generator (18-week season with bye weeks, proper divisional matchups)
- Task 13: Standings view (division standings, wild card, tiebreakers)
- Task 14: Week advancement system (advance from week to week, offseason phases)
- Task 15: Schedule view UI (weekly schedule, scores, upcoming games)

## Phase 3: Basic Match Simulation Engine (outline)

- Task 16: Play result calculator (pure Swift, no UI dependency)
- Task 17: Drive simulator (series of plays into a drive)
- Task 18: Full game simulator (two teams, four quarters, overtime)
- Task 19: Game result model and box score
- Task 20: Game summary UI (post-game stats, highlights)

## Phase 4: SceneKit 3D Match View (outline)

- Task 21: Football field 3D scene (field, yard lines, end zones)
- Task 22: Player 3D models (simple capsules/cylinders with jersey colors)
- Task 23: Formation positioning (11v11 on field)
- Task 24: Play animation system (routes, blocking, ball movement)
- Task 25: Camera and speed controls
- Task 26: Integration with match simulation engine
- Task 27: Play-calling UI overlay during match

## Phase 5: Coaching Staff System (outline)

- Task 28: Coaching staff management UI
- Task 29: Hiring/firing flow
- Task 30: Scheme fit calculation
- Task 31: Coach development between seasons
- Task 32: HC interview system (losing coordinators)

## Phase 6: Contract and Salary Cap (outline)

- Task 33: Simple mode contracts (sign, cut, trade basics)
- Task 34: Realistic mode contract builder (guaranteed money, bonuses, void years)
- Task 35: Cap management dashboard
- Task 36: Free agency system (bidding, AI behavior)
- Task 37: Franchise tag system

## Phase 7: Scouting System (outline)

- Task 38: Scout model and hiring
- Task 39: College prospect generation
- Task 40: Scouting assignment system (weekly during college season)
- Task 41: Scouting report UI (with accuracy/uncertainty)
- Task 42: Combine simulation
- Task 43: Pro day and interview events

## Phase 8: NFL Draft (outline)

- Task 44: Draft board UI
- Task 45: Draft simulation (AI picks based on team needs and big boards)
- Task 46: Trade offer system during draft (trade up/down, future picks)
- Task 47: Draft grades and media reaction
- Task 48: Draft pick value chart for trade negotiations

## Phase 9: Player Development (outline)

- Task 49: Offseason development calculations (work ethic, coaching quality, age curve)
- Task 50: In-season experience gains (playing time, game performance)
- Task 51: Age regression system (physical first, mental later, position-specific peaks)
- Task 52: Mentor/mentee system (veteran leadership accelerates young player growth)
- Task 53: Potential realization logic (coaching fit, personality, scheme fit)
- Task 54: Injury recovery and durability impact

## Phase 10: Media and Events (outline)

- Task 55: News/headline generator (weekly headlines, draft speculation, performance tracking)
- Task 56: Owner satisfaction system (patience, media market pressure, meddling)
- Task 57: Firing and rehiring flow (potkut → työnhaku → uusi joukkue → reputation vaikuttaa)
- Task 58: Off-field event generator (holdouts, suspensions, drama, retirements, positive events)
- Task 59: Event response UI and consequence system (choices with locker room/media/owner impact)

## Phase 11: Visual Polish and Branding (outline)

- Task 60: Team logos (AI-generated or procedural for all 32 teams)
- Task 61: Player headshot generation (procedural portraits or AI-generated)
- Task 62: UI animations and transitions (screen transitions, card reveals, stat animations)
- Task 63: Sound design (menu music, game day atmosphere, notification sounds)
- Task 64: iPad-specific layout optimization (split view, sidebar navigation for larger screens)
- Task 65: App icon and launch screen design
- Task 66: Settings screen (difficulty, simulation speed, notification preferences)
- Task 67: Tutorial/onboarding flow for new players
- Task 68: Achievement/trophy system (career milestones, Super Bowl wins)

## Phase 12: Roster Import/Export (outline)

- Task 69: JSON roster format definition (players, teams, names, attributes)
- Task 70: Export current roster to JSON
- Task 71: Import roster from JSON file (Files app integration)
- Task 72: Default randomized roster vs. development (real) roster toggle
- Task 73: Community sharing support (share roster packs via AirDrop/Files)

---

## Progress Tracker

| Phase | Status | Description |
|-------|--------|-------------|
| 1. Foundation | DONE | SwiftUI, domain models, UI flow, roster |
| 2. Season Structure | DONE | Schedule, standings, week advancement |
| 3. Match Engine | DONE | Play-by-play simulation, box score, game summary |
| 4. SceneKit 3D | DONE | 3D field, match view with replay |
| 5. Coaching Staff | DONE | Scheme fit, coach development, hiring/firing |
| 6. Contracts/Cap | DONE | Simple + realistic modes, free agency |
| 7. Scouting | DONE | Scouts, prospects, combine, draft class |
| 8. NFL Draft | TODO | Draft UI, AI picks, trade system |
| 9. Player Development | TODO | Development, regression, mentoring |
| 10. Media & Events | TODO | Headlines, owner, drama, consequences |
| 11. Visual Polish | TODO | Logos, portraits, animations, sound, settings |
| 12. Roster Import/Export | TODO | JSON format, import/export, sharing |

## Notes

- Each phase after Phase 1 will get its own detailed implementation plan when we reach it
- Phase 1 establishes the playable foundation: create career → see roster → advance through the season skeleton
- Phases 2-3 make the core game loop functional (season + match sim)
- Phase 4 adds the visual match experience
- Phases 5-7 layer on management depth (coaching, contracts, scouting)
- Phase 8 completes the draft cycle
- Phases 9-10 add dynamic gameplay (development, media, events)
- Phase 11 polishes the visual experience for release quality
- Phase 12 enables community content
- All game logic (Engine layer) should be testable without UI
- The project uses `PBXFileSystemSynchronizedRootGroup` — adding files to the `dynasty/dynasty/` folder automatically includes them in the Xcode project
- Game name: **Sunday Night Dynasty**
- Bundle ID: com.brewcrow.dynasty
