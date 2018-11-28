
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
 - in-memory pool of inputs
 - statistics
 - state of the external world
 - etc.
 */
public final class FuzzerState <Input, Properties, World, Sensor>
    where
    World: FuzzerWorld,
    World.Input == Input,
    Sensor: FuzzerSensor,
    Sensor.Feature == World.Feature,
    Properties: FuzzerInputProperties,
    Properties.Input == Input
{
    /// A collection of previously-tested inputs that are considered interesting
    let pool: InputPool = InputPool()
    
    var poolThreshold: Int = 64
    
    /// The current inputs that are being tested
    var inputs: [Input]
    
    /// The index of the input being tested
    var inputIndex: Int
    
    /// Various statistics about the current fuzzer run.
    var stats: FuzzerStats
    /// The initial settings passed to the fuzzer
    var settings: FuzzerSettings
    /// The time at which the fuzzer started. Used for computing the average execution speed.
    var processStartTime: UInt = 0
    /// 
    var sensor: Sensor
    /**
     A property managing the effects and coeffects produced and needed by the fuzzer.
    
     It provides a random number generator, performs file operations, gives the current
     time, the memory consumption, etc.
     */
    var world: World

    init(inputs: [Input], inputIndex: Int, settings: FuzzerSettings, world: World, sensor: Sensor) {
        self.inputs = inputs
        self.inputIndex = inputIndex
        self.stats = FuzzerStats()
        self.settings = settings
        self.world = world
        self.sensor = sensor
    }

    /// Gather statistics about the state of the fuzzer and store them in `self.stats`.
    func updateStats() {
        let now = world.clock()
        let seconds = Double(now - processStartTime) / 1_000_000
        stats.executionsPerSecond = Int((Double(stats.totalNumberOfRuns) / seconds).rounded())
        stats.poolSize = pool.inputs.count
        stats.score = Int((pool.score * 10).rounded())
        let avgCplx = pool.smallestInputComplexityForFeature.values.reduce(0, +) / Double(pool.smallestInputComplexityForFeature.count)
        stats.averageComplexity = Int((avgCplx * 100).rounded())
        //stats.rss = Int(world.getPeakMemoryUsage())
    }
    
    /// Handle the signal sent to the process and exit.
    func receive(signal: Signal) -> Never {
        world.reportEvent(.caughtSignal(signal), stats: stats)
        switch signal {
        case .illegalInstruction, .abort, .busError, .floatingPointException:
            var features: [Sensor.Feature] = []
            sensor.iterateOverCollectedFeatures { features.append($0) }
            try! world.saveArtifact(input: inputs[inputIndex], features: features, score: pool.score, kind: .crash)
            exit(FuzzerTerminationStatus.crash.rawValue)
            
        case .interrupt:
            exit(FuzzerTerminationStatus.success.rawValue)
            
        default:
            exit(FuzzerTerminationStatus.unknown.rawValue)
        }
    }
}

/**
 A fuzzer can fuzz-test a function `test: (Input) -> Bool`. It finds values of
 `Input` for which `test` returns `false` or crashes.
 
 It is configurable by four generic type parameters:
 - `Generator` defines how to generate and evolve values of type `Input`
 - `Properties` defines how to compute essential properties of `Input` (such as their complexities or hash values)
 - `World` regulates the communication between the Fuzzer and the real-world,
   such as the file system, time, or random number generator.
 - `Sensor` collects, from a test function execution, the measurements to optimize (e.g. code coverage)
 
 This type is a bit too complex to make part of the public API and end users
 should only used (partly) specialized versions of it, like CommandLineFuzzer.
 */
final class Fuzzer <Input, Generator, World, Sensor>
    where
    Generator: FuzzerInputGenerator,
    World: FuzzerWorld,
    Sensor: FuzzerSensor,
    World.Feature == Sensor.Feature,
    Generator.Input == Input,
    World.Input == Input
{
    
    typealias State = FuzzerState<Input, Generator, World, Sensor>
    
    let state: State
    let generator: Generator
    let test: (Input) -> Bool
    let signalsHandler: SignalsHandler
    
    init(test: @escaping (Input) -> Bool, generator: Generator, settings: FuzzerSettings, world: World, sensor: Sensor) {
        self.generator = generator
        self.test = test
        self.state = State(inputs: [generator.baseInput], inputIndex: 0, settings: settings, world: world, sensor: sensor)
    
        let signals: [Signal] = [.segmentationViolation, .busError, .abort, .illegalInstruction, .floatingPointException, .interrupt, .softwareTermination, .fileSizeLimitExceeded]
        
        self.signalsHandler = SignalsHandler(signals: signals) { [state] signal in
            state.receive(signal: signal)
        }
        
        precondition(Foundation.Thread.isMainThread, "Fuzzer can only be initialized on the main thread")
        // :shame: please send help
        let idx = Foundation.Thread.callStackSymbols.firstIndex(where: { $0.contains(" main + ")})!
        let adr = Foundation.Thread.callStackReturnAddresses[idx].uintValue
        NormalizedPC.constant = adr
    }
}

// note: it is not a typealias because I feel bad for the typechecker
public enum CommandLineFuzzer <Generator: FuzzerInputGenerator> {
    public typealias Input = Generator.Input
    typealias SpecializedFuzzer = Fuzzer<Input, Generator, CommandLineFuzzerWorld<Input, Generator>, CodeCoverageSensor>

    /// Execute the fuzzer command given by `Commandline.arguments` for the given test function and generator.
    public static func launch(test: @escaping (Input) -> Bool, generator: Generator) throws {
        let (parser, settingsBinder, worldBinder, _) = CommandLineFuzzerWorldInfo.argumentsParser()
        var settings: FuzzerSettings
        var world: CommandLineFuzzerWorldInfo
        do {
            let res = try parser.parse(Array(CommandLine.arguments.dropFirst()))
            settings = FuzzerSettings()
            try settingsBinder.fill(parseResult: res, into: &settings)
            world = CommandLineFuzzerWorldInfo()
            try worldBinder.fill(parseResult: res, into: &world)
        } catch let e {
            print(e)
            parser.printUsage(on: stdoutStream)
            return
        }
        let fuzzer = SpecializedFuzzer(test: test, generator: generator, settings: settings, world: CommandLineFuzzerWorld(info: world), sensor: .shared)
        switch fuzzer.state.settings.command {
        case .fuzz:
            try fuzzer.loop()
        case .minimize:
            try fuzzer.minimizeLoop()
        case .read:
            fuzzer.state.inputs = [try fuzzer.state.world.readInputFile()]
            try fuzzer.testCurrentInputs()
        }
    }
}

extension Fuzzer {
    
    /**
     Run and record the test function for the current test inputs.
     Exit and save the artifact if the test function failed.
     */
    func testCurrentInputs() throws {
        for i in state.inputs {
            try testInput(i)
        }
    }
    
    func testInput(_ input: Input) throws {
        state.sensor.resetCollectedFeatures()
        
        state.sensor.isRecording = true
        let success = test(input)
        state.sensor.isRecording = false
        
        guard success else {
            state.world.reportEvent(.testFailure, stats: state.stats)
            var features: [Sensor.Feature] = []
            state.sensor.iterateOverCollectedFeatures { features.append($0) }
            try state.world.saveArtifact(input: input, features: features, score: state.pool.score, kind: .testFailure)
            exit(FuzzerTerminationStatus.testFailure.rawValue)
        }
        
        state.stats.totalNumberOfRuns += 1
    }

    /**
     Analyze the recording of the last test function call.
     Return the current input along with its associated analysis data iff
     the current input is interesting and should be added to the input pool.
    */
    func analyze() -> State.InputPool.Element? {
        
        // it is slow to recreate the array here each time
        // move them to FuzzerState to improve performance a bit
        var bestInputForFeatures: [Sensor.Feature] = []
        var otherFeatures: [Sensor.Feature] = []

        let currentInputComplexity = Generator.adjustedComplexity(of: state.inputs[state.inputIndex])
        
        state.sensor.iterateOverCollectedFeatures { feature in
            guard let oldComplexity = state.pool.smallestInputComplexityForFeature[feature] else {
                bestInputForFeatures.append(feature)
                return
            }
            if currentInputComplexity < oldComplexity {
                bestInputForFeatures.append(feature)
                return
            } else {
                otherFeatures.append(feature)
                return
            }
        }
        
        guard !bestInputForFeatures.isEmpty else {
            return nil
        }

        return State.InputPool.Element(
            input: state.inputs[state.inputIndex],
            complexity: currentInputComplexity,
            features: bestInputForFeatures + otherFeatures
        )
    }

    /**
     Run and record the test function for the current test input,
     analyze the recording, and update the input pool if needed.
     */
    func processCurrentInputs() throws {
        var newPoolElements: [State.InputPool.Element] = []
        for (input, i) in zip(state.inputs, state.inputs.indices) {
            state.inputIndex = i
            try testInput(input)
            let result = analyze()
            if let newPoolElement = result {
                newPoolElements.append(newPoolElement)
            }
        }
        guard !newPoolElements.isEmpty else {
            return
        }
        let effect = state.pool.add(newPoolElements)
        try effect(&state.world)
        
        state.updateStats()
        state.world.reportEvent(.new, stats: state.stats)
    }
    
    /**
     Change the current input to a selection from the input pool.
     Then repeatedly mutate and process the current input, up to `mutateDepth` times.
     */
    func processNextInputs() throws {
        state.inputs = []
        state.inputIndex = 0
        
        while state.inputs.count < 50 {
            let idx = state.pool.randomIndex(&state.world.rand)
            var newInput = state.pool[idx].input
        
            var complexity: Double = state.pool[idx].complexity - 1.0
            for _ in 0 ..< state.settings.mutateDepth {
                guard
                    state.stats.totalNumberOfRuns < state.settings.maxNumberOfRuns,
                    generator.mutate(&newInput, state.settings.maxInputComplexity - complexity, &state.world.rand)
                    else {
                        break
                }
                complexity = Generator.complexity(of: newInput)
                guard complexity < state.settings.maxInputComplexity else {
                    continue
                }
                state.inputs.append(newInput)
            }
        }
        
        try processCurrentInputs()
    }
    
    /**
     Process the inputs in the input corpus, or process the initial inputs
     given by the generator if the input corpus is empty.
    */
    func processInitialInputs() throws {
        var inputs = try state.world.readInputCorpus()
        if inputs.isEmpty {
            print(state.settings.maxInputComplexity)
            inputs += generator.initialInputs(maxComplexity: state.settings.maxInputComplexity, &state.world.rand)
        }
        // Filter the inputs that are too complex
        inputs = inputs.filter { Generator.complexity(of: $0) <= state.settings.maxInputComplexity }
        state.inputs = inputs
        state.inputIndex = 0
        try processCurrentInputs()
        
    }
    
    /**
     Launch the regular fuzzing loop, which processes inputs, starting from the initial ones,
     until either a bug is found or the maximum number of iterations have been executed.
    */
    public func loop() throws {
        state.processStartTime = state.world.clock()
        state.world.reportEvent(.start, stats: state.stats)
        
        try processInitialInputs()
        state.world.reportEvent(.didReadCorpus, stats: state.stats)
            
        while state.stats.totalNumberOfRuns < state.settings.maxNumberOfRuns {
            if state.pool.inputs.count > state.poolThreshold {
                print("RESETTING POOL")
                state.inputs = state.pool.inputs.map { $0.input }
                state.inputIndex = 0
                state.pool.empty()
                try processCurrentInputs()
                state.poolThreshold = (state.pool.inputs.count * 3) / 2
                state.pool.verify()
            } else {
                try processNextInputs()
            }
        }
        state.world.reportEvent(.done, stats: state.stats)
    }
    
    /**
     Launch the minimizing loop. It reads the input to minimize from the input file, then
     processes simpler variations of that input until either a bug is found or the maximum
     number of iterations have been executed.
    */
    public func minimizeLoop() throws {
        state.processStartTime = state.world.clock()
        state.world.reportEvent(.start, stats: state.stats)
        let input = try state.world.readInputFile()
        let favoredInput = State.InputPool.Element(
            input: input,
            complexity: Generator.adjustedComplexity(of: input),
            features: []
        )
        state.pool.favoredInput = favoredInput
        let effect = state.pool.updateScores()
        try effect(&state.world)
        state.settings.maxInputComplexity = Generator.complexity(of: input).nextDown
        state.world.reportEvent(.didReadCorpus, stats: state.stats)
        while state.stats.totalNumberOfRuns < state.settings.maxNumberOfRuns {
            try processNextInputs()
        }
        state.world.reportEvent(.done, stats: state.stats)
    }
}
