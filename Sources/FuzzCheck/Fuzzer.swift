
import Basic
import Darwin
import Foundation

/// The reason why the fuzzer terminated, to be passed as argument to `exit(..)`
public enum FuzzerTerminationStatus: Int32 {
    case success = 0
    case crash = 1
    case testFailure = 2
    case unknown = 3
}

/**
 The state of the fuzzer:
 - in-memory pool of units
 - statistics
 - state of the external world
 - etc.
 */
public final class FuzzerState <Unit, Properties, World>
    where
    World: FuzzerWorld,
    World.Unit == Unit,
    Properties: FuzzUnitProperties,
    Properties.Unit == Unit
{
    /// A collection of previously-tested units that are considered interesting
    let pool: UnitPool = UnitPool()
    /// The current unit that is being tested
    var unit: Unit
    /// Various statistics about the current fuzzer run.
    var stats: FuzzerStats
    /// The initial settings passed to the fuzzer
    var settings: FuzzerSettings
    /// The time at which the fuzzer started. Used for computing the average execution speed.
    var processStartTime: UInt = 0
    /**
     A property managing the effects and coeffects produced and needed by the fuzzer.
    
     It provides a source of randomness, performs file operations, gives the current
     time, the memory consumption, etc.
     */
    var world: World

    init(unit: Unit, settings: FuzzerSettings, world: World) {
        self.unit = unit
        self.stats = FuzzerStats()
        self.settings = settings
        self.world = world
    }

    /// Gather statistics about the state of the fuzzer and store them in `self.stats`.
    func updateStats() {
        let now = world.clock()
        let seconds = Double(now - processStartTime) / 1_000_000
        stats.executionsPerSecond = Int((Double(stats.totalNumberOfRuns) / seconds).rounded())
        stats.poolSize = pool.units.count
        stats.totalEdgeCoverage = TracePC.getTotalEdgeCoverage()
        stats.score = pool.coverageScore.rounded()
        stats.rss = Int(world.getPeakMemoryUsage())
    }
    
    /// Handle the signal sent to the process and exit.
    func receive(signal: Signal) -> Never {
        world.reportEvent(.caughtSignal(signal), stats: stats)
        switch signal {
        case .illegalInstruction, .abort, .busError, .floatingPointException:
            TracePC.crashed = true
            var features: [Feature] = []
            TracePC.collectFeatures { features.append($0) }
            try! world.saveArtifact(unit: unit, features: features, coverage: pool.coverageScore, kind: .crash)
            exit(FuzzerTerminationStatus.crash.rawValue)
            
        case .interrupt:
            exit(FuzzerTerminationStatus.success.rawValue)
            
        default:
            exit(FuzzerTerminationStatus.unknown.rawValue)
        }
    }
}

/// A fuzzer meant to be used from the command line
public typealias CommandLineFuzzer <FuzzUnit: FuzzUnit> = Fuzzer<FuzzUnit.Unit, FuzzUnit, FuzzUnit, CommandLineFuzzerWorld<FuzzUnit.Unit, FuzzUnit>> where FuzzUnit.Unit: Codable

/**
 A fuzzer can fuzz-test a function `test: (Unit) -> Bool`. It finds values of
 `Unit` for which `test` returns `false` or crashes.
 
 It is configurable by three generic type parameters:
 - `Generator` defines how to generate and evolve values of type `Unit`
 - `Properties` defines how to compute essential properties of `Unit` (such as their complexities or hash values)
 - `World` regulates the communication between the Fuzzer and the real-world,
   such as the file system, time, or random number generator.
 */
public final class Fuzzer <Unit, Generator, Properties, World>
    where
    Generator: FuzzUnitGenerator,
    Properties: FuzzUnitProperties,
    World: FuzzerWorld,
    Generator.Unit == Unit,
    Properties.Unit == Unit,
    World.Unit == Unit
{
    
    typealias State = FuzzerState<Unit, Properties, World>
    
    let state: State
    let generator: Generator
    let test: (Unit) -> Bool
    let signalsHandler: SignalsHandler
    
    public init(test: @escaping (Unit) -> Bool, generator: Generator, settings: FuzzerSettings, world: World) {
        self.generator = generator
        self.test = test
        self.state = State(unit: generator.baseUnit, settings: settings, world: world)
    
        let signals: [Signal] = [.segmentationViolation, .busError, .abort, .illegalInstruction, .floatingPointException, .interrupt, .softwareTermination, .fileSizeLimitExceeded]
        
        self.signalsHandler = SignalsHandler(signals: signals) { [state] signal in
            state.receive(signal: signal)
        }
        
        precondition(Foundation.Thread.isMainThread, "Fuzzer can only be initialized on the main thread")
        
        let idx = Foundation.Thread.callStackSymbols.firstIndex(where: { $0.contains(" main + ")})!
        let adr = Foundation.Thread.callStackReturnAddresses[idx].uintValue
        NormalizedPC.constant = adr
    }
}

extension Fuzzer where Unit: Codable, Properties == Generator, World == CommandLineFuzzerWorld<Generator.Unit, Generator> {
    
    
    /// Execute the fuzzer command given by `Commandline.arguments` for the given test function and generator.
    public static func launch(test: @escaping (Unit) -> Bool, generator: Generator) throws {
        
        let (parser, settingsBinder, worldBinder, _) = CommandLineFuzzerWorldInfo.argumentsParser()
        do {
            let res = try parser.parse(Array(CommandLine.arguments.dropFirst()))
            var settings: FuzzerSettings = FuzzerSettings()
            try settingsBinder.fill(parseResult: res, into: &settings)
            var world: CommandLineFuzzerWorldInfo = CommandLineFuzzerWorldInfo()
            try worldBinder.fill(parseResult: res, into: &world)

            let fuzzer = Fuzzer(test: test, generator: generator, settings: settings, world: CommandLineFuzzerWorld(info: world))
            switch fuzzer.state.settings.command {
            case .fuzz:
                try fuzzer.loop()
            case .minimize:
                try fuzzer.minimizeLoop()
            case .read:
                fuzzer.state.unit = try fuzzer.state.world.readInputFile()
                fuzzer.testCurrentUnit()
            }
        } catch let e {
            print(e)
            parser.printUsage(on: stdoutStream)
        }
    }
}

extension Fuzzer {
    /**
     Run and record the test function for the current test unit.
     Exit and save the artifact if the test function failed.
    */
    func testCurrentUnit() {
        TracePC.resetTestRecordings()

        TracePC.recording = true
        let success = test(state.unit)
        TracePC.recording = false

        guard success else {
            state.world.reportEvent(.testFailure, stats: state.stats)
            var features: [Feature] = []
            TracePC.collectFeatures { features.append($0) }
            try! state.world.saveArtifact(unit: state.unit, features: features, coverage: state.pool.coverageScore, kind: .testFailure)
            exit(FuzzerTerminationStatus.testFailure.rawValue)
        }

        state.stats.totalNumberOfRuns += 1
    }

    /**
     Analyze the recording of the last test function call.
     Return the current unit along with its associated analysis data iff
     the current unit is interesting and should be added to the unit pool.
    */
    func analyze() -> State.UnitPool.UnitInfo? {
        let currentUnitComplexity = Properties.complexity(of: state.unit)
        
        var bestUnitForFeatures: [Feature] = []
        var otherFeatures: [Feature] = []
        
        TracePC.collectFeatures { feature in
            guard let oldComplexity = state.pool.smallestUnitComplexityForFeature[feature.reduced] else {
                bestUnitForFeatures.append(feature)
                return
            }
            if currentUnitComplexity < oldComplexity {
                bestUnitForFeatures.append(feature)
                return
            } else {
                otherFeatures.append(feature)
                return
            }
        }
        
        guard !bestUnitForFeatures.isEmpty else {
            return nil
        }
        let newUnitInfo = State.UnitPool.UnitInfo(
            unit: state.unit,
            complexity: currentUnitComplexity,
            features: bestUnitForFeatures + otherFeatures
        )
        return newUnitInfo
    }

    /**
     Run and record the test function for the current test unit,
     analyze the recording, and update the unit pool if needed.
     */
    func processCurrentUnit() throws {
        testCurrentUnit()
        
        let result = analyze()
        state.updateStats()
        guard let newUnitInfo = result else {
            return
        }
        let effect = state.pool.add(newUnitInfo)
        try effect(&state.world)

        state.world.reportEvent(.new, stats: state.stats)
    }
    
    /**
     Change the current unit to a selection from the unit pool.
     Then repeatedly mutate and process the current unit, up to `mutateDepth` times.
     */
    func processNextUnits() throws {
        let idx = state.pool.randomIndex(&state.world.rand)
        let unit = state.pool[idx].unit
        state.unit = unit
        for _ in 0 ..< state.settings.mutateDepth {
            guard state.stats.totalNumberOfRuns < state.settings.maxNumberOfRuns else { break }
            guard generator.mutate(&state.unit, &state.world.rand) else { break  }
            guard Properties.complexity(of: state.unit) < state.settings.maxUnitComplexity else { continue }
            try processCurrentUnit()
        }
    }
    
    /**
     Process the units in the input corpus, or process the initial units
     given by the generator if the input corpus is empty.
    */
    func processInitialUnits() throws {
        var units = try state.world.readInputCorpus()
        if units.isEmpty {
            units += generator.initialUnits(&state.world.rand)
        }
        // Filter the units that are too complex
        units = units.filter { Properties.complexity(of: $0) <= state.settings.maxUnitComplexity }
        
        for u in units {
            state.unit = u
            try processCurrentUnit()
        }
    }
    
    /**
     Launch the regular fuzzing loop, which processes units, starting from the initial ones,
     until either a bug is found or the maximum number of iterations have been executed.
    */
    public func loop() throws {
        state.processStartTime = state.world.clock()
        state.world.reportEvent(.start, stats: state.stats)
        
        try processInitialUnits()
        state.world.reportEvent(.didReadCorpus, stats: state.stats)
            
        while state.stats.totalNumberOfRuns < state.settings.maxNumberOfRuns {
            try processNextUnits()
        }
        state.world.reportEvent(.done, stats: state.stats)
    }
    
    /**
     Launch the minimizing loop. It reads the unit to minimize from the input file, then
     processes simpler variations of that unit until either a bug is found or the maximum
     number of iterations have been executed.
    */
    public func minimizeLoop() throws {
        state.processStartTime = state.world.clock()
        state.world.reportEvent(.start, stats: state.stats)
        let input = try state.world.readInputFile()
        let favoredUnit = State.UnitPool.UnitInfo(
            unit: input,
            complexity: Properties.complexity(of: input),
            features: []
        )
        state.pool.favoredUnit = favoredUnit
        state.pool.updateScoresAndWeights()
        state.settings.maxUnitComplexity = favoredUnit.complexity.nextDown
        state.world.reportEvent(.didReadCorpus, stats: state.stats)
        while state.stats.totalNumberOfRuns < state.settings.maxNumberOfRuns {
            try processNextUnits()
        }
        state.world.reportEvent(.done, stats: state.stats)
    }
}
