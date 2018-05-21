
import Darwin

/*
#include "FuzzerDefs.h"
#include "FuzzerDictionary.h"
#include "FuzzerValueBitMap.h"
#include <set>

namespace fuzzer {

// TableOfRecentCompares (TORC) remembers the most recently performed
// comparisons of type T.
// We record the arguments of CMP instructions in this table unconditionally
// because it seems cheaper this way than to compute some expensive
// conditions inside __sanitizer_cov_trace_cmp*.
// After the unit has been executed we may decide to use the contents of
// this table to populate a Dictionary.
template<class T, size_t kSizeT>
struct TableOfRecentCompares {
  static const size_t kSize = kSizeT;
  struct Pair {
    T A, B;
  };
  ATTRIBUTE_NO_SANITIZE_ALL
  void Insert(size_t Idx, const T &Arg1, const T &Arg2) {
    Idx = Idx % kSize;
    Table[Idx].A = Arg1;
    Table[Idx].B = Arg2;
  }

  Pair Get(size_t I) { return Table[I % kSize]; }

  Pair Table[kSize];
};

template <size_t kSizeT>
struct MemMemTable {
  static const size_t kSize = kSizeT;
  Word MemMemWords[kSize];
  Word EmptyWord;

  void Add(const uint8_t *Data, size_t Size) {
    if (Size <= 2) return;
    Size = std::min(Size, Word::GetMaxSize());
    size_t Idx = SimpleFastHash(Data, Size) % kSize;
    MemMemWords[Idx].Set(Data, Size);
  }
  const Word &Get(size_t Idx) {
    for (size_t i = 0; i < kSize; i++) {
      const Word &W = MemMemWords[(Idx + i) % kSize];
      if (W.size()) return W;
    }
    EmptyWord.Set(nullptr, 0);
    return EmptyWord;
  }
};
*/

// The coverage counters and PCs.
// These are declared as global variables named "__sancov_*" to simplify
// experiments with inlined instrumentation.

// __sancov_trace_pc_pcs
var PCs = UnsafeMutableBufferPointer<PC>.allocate(capacity: TracePC.maxNumPCs)
// __sancov_trace_pc_guard_8bit_counters
var eightBitCounters = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: TracePC.maxNumPCs)

func counterToFeature <T: BinaryInteger> (_ counter: T) -> CUnsignedInt {
    precondition(counter > 0)
   
    if counter >= 128 { return 7 }
    if counter >= 32  { return 6 }
    if counter >= 16  { return 5 }
    if counter >= 8   { return 4 }
    if counter >= 4   { return 3 }
    if counter >= 3   { return 2 }
    if counter >= 2   { return 1 }
    return 0
}

struct PCTableEntry {
    let pc: PC
    let flags: uintptr_t;
}

typealias PC = uintptr_t
extension PC {
    var positive: Bool {
        return self > 0
    }
}

struct TracePC {
    // How many bits of PC are used from __sanitizer_cov_trace_pc
    static let maxNumPCs: size_t = 1 << 21
    static let tracePCBits: size_t = 18
    
    var numGuards: size_t
    var modules: [UnsafeMutableBufferPointer<UInt32>]
    
    var modulePCTables: [UnsafeMutableBufferPointer<PCTableEntry>]
    var numPCInPCTables: size_t
    
    var numInline8bitCounters: size_t
    var numModulesWithInline8BitCounters: size_t
    
    var valueProfileMap: ValueBitMap
    
    var observedPCs: Set<PC>
    var observedFuncs: Set<PC>
    
    var useCounters: Bool
    var useValueProfile: Bool
    var printNewPCs: Bool
    var printNewFuncs: size_t
    
    var moduleCounters: [UnsafeMutableBufferPointer<UInt8>]
    
    func numPCs() -> size_t {
        return numGuards == 0 ? (1 << TracePC.tracePCBits) : min(TracePC.maxNumPCs, numGuards+1)
    }
    
    mutating func handleInit(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
        guard start != stop && start.pointee == 0 else { return }
        // assert
        let buffer = UnsafeMutableBufferPointer(start: start, count: stop - start)
        for i in buffer.indices {
            numGuards += 1
            if numGuards == TracePC.maxNumPCs {
                print("""
                WARNING: The binary has too many instrumented PCs.
                         You may want to reduce the size of the binary
                         for more efficient fuzzing and precise coverage data
                """)
            }
            buffer[i] = UInt32(numGuards % TracePC.maxNumPCs)
        }
        modules.append(buffer)
    }
    
    mutating func handleInline8BitCountersInit(start: UnsafeMutablePointer<UInt8>, stop: UnsafeMutablePointer<UInt8>) {
        // TODO
    }
    
    mutating func handlePCsInit(start: UnsafeMutablePointer<PCTableEntry>, stop: UnsafeMutablePointer<PCTableEntry>) {
        guard modulePCTables.last?.baseAddress != start else { return }
        // assert
        let buffer = UnsafeMutableBufferPointer(start: start, count: stop - start)
        modulePCTables.append(buffer)
        numPCInPCTables += buffer.count
    }
    
    mutating func handleCallerCallee(caller: uintptr_t, callee: uintptr_t) {
        let bits: uintptr_t = 12
        let mask = (1 << bits) - 1
        let idx: uintptr_t = (caller & mask) | ((callee & mask) << bits)
        _ = valueProfileMap.addValueModPrime(idx)
    }
    
    func getTotalPCCoverage() -> size_t {
        guard !observedPCs.isEmpty else {
            return (1 ..< numPCs()).reduce(0) { $0 + (PCs[$1].positive ? 1 : 0) }
        }
        return observedPCs.count
    }
    
    mutating func updateObservedPCs() {
        var coveredFuncs: [PC] = []
        
        func observePC(_ pc: PC) {
            if observedPCs.insert(pc).inserted, printNewPCs {
                print("\tNEW_PC: TODO")// TODO
            }
        }
        
        func observe(_ TE: PCTableEntry) {
            if TE.flags & 1 != 0, observedFuncs.insert(TE.pc).inserted, printNewFuncs > 0 {
                coveredFuncs.append(TE.pc)
            }
            observePC(TE.pc)
        }
        
        Cond:
        if numPCInPCTables > 0 {
            if numInline8bitCounters == numPCInPCTables {
                for i in 0 ..< numModulesWithInline8BitCounters {
                    assert(moduleCounters[i].count == modulePCTables[i].count)
                    for j in moduleCounters[i].indices where moduleCounters[i][j] > 0 {
                        observe(modulePCTables[i][j])
                    }
                }
            }
        } else if numGuards == numPCInPCTables {
            var guardIdx = 1
            for i in modules.indices {
                for j in modules[i].indices {
                    guardIdx += 1
                    if eightBitCounters[guardIdx] > 0 {
                        observe(modulePCTables[i][j])
                    }
                }
            }
        }
        // skip clang counters parts
        for _ in 0 ..< min(coveredFuncs.count, printNewFuncs) {
            // print
            // TODO
        }
    }
    
    typealias Feature = size_t
    
    func collectFeatures(_ handleFeature: (Feature) -> Void) {
        let Counters = eightBitCounters
        let N = numPCs()
        
        func handle8BitCounter(_ handleFeature: (Feature) -> Void, _ firstFeature: Feature, _ idx: size_t, _ counter: UInt8) -> Void {
            handleFeature(firstFeature + idx * 8 + size_t(counterToFeature(counter)))
        }
        
        var firstFeature: Feature = 0
        if numInline8bitCounters == 0 {
            for i in Counters.indices where Counters[i] != 0 {
                handle8BitCounter(handleFeature, firstFeature, i, Counters[i])
            }
            firstFeature += N * 8
        }
        else {
            for i in 0 ..< numModulesWithInline8BitCounters {
                for j in moduleCounters[i].indices where moduleCounters[i][j] != 0 {
                    handle8BitCounter(handleFeature, firstFeature, j, moduleCounters[i][j])
                }
            }
        }
        // omit clang counters
        // omit extra counters
        if useValueProfile {
            valueProfileMap.forEach {
                handleFeature(firstFeature + $0)
            }
            firstFeature += Feature(type(of: valueProfileMap).mapSizeInBits)
        }
        
        // omit lowest stack thingy
    }
    
    mutating func handle8Inline8BitCountersInit(start: UnsafeMutablePointer<UInt8>, stop: UnsafeMutablePointer<UInt8>) {
        guard start != stop else { return }
        guard !(numModulesWithInline8BitCounters != 0 && moduleCounters.last!.baseAddress == start) else {
            return
        }
        precondition(numModulesWithInline8BitCounters < moduleCounters.count)
        let buffer = UnsafeMutableBufferPointer(start: start, count: stop - start)
        moduleCounters[numModulesWithInline8BitCounters] = buffer
        numInline8bitCounters += buffer.count
    }

    mutating func handleCmp <T: BinaryInteger> (pc: PC, arg1: T, arg2: T) {
        let argxor = arg1 ^ arg2
        var argdist: T = 0
        // SLOW
        for i in 0 ..< MemoryLayout<T>.size * 8 {
            argdist += (argxor & (0b1 << i) >> i)
        }
        let idx = ((pc & 4095) + 1) * numericCast(argdist)
        
    }
    /*
void TracePC::HandleCmp(uintptr_t PC, T Arg1, T Arg2) {
  uint64_t ArgXor = Arg1 ^ Arg2;
  uint64_t ArgDistance = __builtin_popcountll(ArgXor) + 1; // [1,65]
  uintptr_t Idx = ((PC & 4095) + 1) * ArgDistance;
  if (sizeof(T) == 4)
      TORC4.Insert(ArgXor, Arg1, Arg2);
  else if (sizeof(T) == 8)
      TORC8.Insert(ArgXor, Arg1, Arg2);
  ValueProfileMap.AddValue(Idx);
}

     */
}

/*
class TracePC {
  template <class T> void HandleCmp(uintptr_t PC, T Arg1, T Arg2);
  template <class Callback> void CollectFeatures(Callback CB) const;

  void ResetMaps() {
    ValueProfileMap.Reset();
    if (NumModules)
      memset(Counters(), 0, GetNumPCs());
    ClearExtraCounters();
    ClearInlineCounters();
    ClearClangCounters();
  }

  void ClearInlineCounters();

  void UpdateFeatureSet(size_t CurrentElementIdx, size_t CurrentElementSize);
  void PrintFeatureSet();

  void PrintModuleInfo();

  void PrintCoverage();
  void DumpCoverage();

  void AddValueForMemcmp(void *caller_pc, const void *s1, const void *s2,
                         size_t n, bool StopAtZero);

  TableOfRecentCompares<uint32_t, 32> TORC4;
  TableOfRecentCompares<uint64_t, 32> TORC8;
  TableOfRecentCompares<Word, 32> TORCW;
  MemMemTable<1024> MMT;

  size_t GetNumPCs() const {
    return NumGuards == 0 ? (1 << kTracePcBits) : Min(kNumPCs, NumGuards + 1);
  }
  uintptr_t GetPC(size_t Idx) {
    assert(Idx < GetNumPCs());
    return PCs()[Idx];
  }

  void RecordInitialStack();
  uintptr_t GetMaxStackOffset() const;

  template<class CallBack>
  void ForEachObservedPC(CallBack CB) {
    for (auto PC : ObservedPCs)
      CB(PC);
  }

private:
  bool UseCounters = false;
  bool UseValueProfile = false;
  bool DoPrintNewPCs = false;
  size_t NumPrintNewFuncs = 0;

  struct Module {
    uint32_t *Start, *Stop;
  };

  Module Modules[4096];
  size_t NumModules;  // linker-initialized.
  size_t NumGuards;  // linker-initialized.

  struct { uint8_t *Start, *Stop; } ModuleCounters[4096];
  size_t NumModulesWithInline8bitCounters;  // linker-initialized.
  size_t NumInline8bitCounters;

  struct PCTableEntry {
    uintptr_t PC, PCFlags;
  };

  struct { const PCTableEntry *Start, *Stop; } ModulePCTable[4096];
  size_t NumPCTables;
  size_t NumPCsInPCTables;

  uint8_t *Counters() const;
  uintptr_t *PCs() const;

  Set<uintptr_t> ObservedPCs;
  Set<uintptr_t> ObservedFuncs;

  ValueBitMap ValueProfileMap;
  uintptr_t InitialStack;
};

template <class Callback>
// void Callback(size_t FirstFeature, size_t Idx, uint8_t Value);
ATTRIBUTE_NO_SANITIZE_ALL
void ForEachNonZeroByte(const uint8_t *Begin, const uint8_t *End,
                        size_t FirstFeature, Callback Handle8bitCounter) {
  typedef uintptr_t LargeType;
  const size_t Step = sizeof(LargeType) / sizeof(uint8_t);
  const size_t StepMask = Step - 1;
  auto P = Begin;
  // Iterate by 1 byte until either the alignment boundary or the end.
  for (; reinterpret_cast<uintptr_t>(P) & StepMask && P < End; P++)
    if (uint8_t V = *P)
      Handle8bitCounter(FirstFeature, P - Begin, V);

  // Iterate by Step bytes at a time.
  for (; P < End; P += Step)
    if (LargeType Bundle = *reinterpret_cast<const LargeType *>(P))
      for (size_t I = 0; I < Step; I++, Bundle >>= 8)
        if (uint8_t V = Bundle & 0xff)
          Handle8bitCounter(FirstFeature, P - Begin + I, V);

  // Iterate by 1 byte until the end.
  for (; P < End; P++)
    if (uint8_t V = *P)
      Handle8bitCounter(FirstFeature, P - Begin, V);
}

// Given a non-zero Counters returns a number in [0,7].
template<class T>
unsigned CounterToFeature(T Counter) {
    assert(Counter);
    unsigned Bit = 0;
    /**/ if (Counter >= 128) Bit = 7;
    else if (Counter >= 32) Bit = 6;
    else if (Counter >= 16) Bit = 5;
    else if (Counter >= 8) Bit = 4;
    else if (Counter >= 4) Bit = 3;
    else if (Counter >= 3) Bit = 2;
    else if (Counter >= 2) Bit = 1;
    return Bit;
}

template <class Callback>  // void Callback(size_t Feature)
ATTRIBUTE_NO_SANITIZE_ADDRESS
__attribute__((noinline))
void TracePC::CollectFeatures(Callback HandleFeature) const {
  uint8_t *Counters = this->Counters();
  size_t N = GetNumPCs();
  auto Handle8bitCounter = [&](size_t FirstFeature,
                               size_t Idx, uint8_t Counter) {
    HandleFeature(FirstFeature + Idx * 8 + CounterToFeature(Counter));
  };

  size_t FirstFeature = 0;

  if (!NumInline8bitCounters) {
    ForEachNonZeroByte(Counters, Counters + N, FirstFeature, Handle8bitCounter);
    FirstFeature += N * 8;
  }

  if (NumInline8bitCounters) {
    for (size_t i = 0; i < NumModulesWithInline8bitCounters; i++) {
      ForEachNonZeroByte(ModuleCounters[i].Start, ModuleCounters[i].Stop,
                         FirstFeature, Handle8bitCounter);
      FirstFeature += 8 * (ModuleCounters[i].Stop - ModuleCounters[i].Start);
    }
  }

  if (size_t NumClangCounters = ClangCountersEnd() - ClangCountersBegin()) {
    auto P = ClangCountersBegin();
    for (size_t Idx = 0; Idx < NumClangCounters; Idx++)
      if (auto Cnt = P[Idx])
        HandleFeature(FirstFeature + Idx * 8 + CounterToFeature(Cnt));
    FirstFeature += NumClangCounters;
  }

  ForEachNonZeroByte(ExtraCountersBegin(), ExtraCountersEnd(), FirstFeature,
                     Handle8bitCounter);
  FirstFeature += (ExtraCountersEnd() - ExtraCountersBegin()) * 8;

  if (UseValueProfile) {
    ValueProfileMap.ForEach([&](size_t Idx) {
      HandleFeature(FirstFeature + Idx);
    });
    FirstFeature += ValueProfileMap.SizeInBits();
  }

  if (auto MaxStackOffset = GetMaxStackOffset())
    HandleFeature(FirstFeature + MaxStackOffset);
}

extern TracePC TPC;

}  // namespace fuzzer

#endif  // LLVM_FUZZER_TRACE_PC

 */


struct ValueBitMap {
    static let mapSizeInBits: uintptr_t = 1 << 16
    static let mapPrimeMod: uintptr_t = 65371 // Largest Prime < kMapSizeInBits
    static let bitsInWord = uintptr_t(MemoryLayout<uintptr_t>.size * 8)
    static let mapSizeInWords: uintptr_t = ValueBitMap.mapSizeInBits / ValueBitMap.bitsInWord
    
    var map: [uintptr_t] = Array(repeating: 0, count: Int(ValueBitMap.mapSizeInWords))
    
    mutating func reset() {
        for i in map.indices { map[i] = 0 }
    }
    
    // Computes a hash function of Value and sets the corresponding bit.
    // Returns true if the bit was changed from 0 to 1.
    mutating func addValue(_ value: uintptr_t) -> Bool {
        let idx = value % ValueBitMap.mapSizeInBits
        let wordIdx = idx / ValueBitMap.bitsInWord
        let bitIdx = idx % ValueBitMap.bitsInWord
        let old = map[Int(wordIdx)]
        let new = old | (1 << bitIdx)
        map[Int(wordIdx)] = new
        return new != old
    }
    
    mutating func addValueModPrime(_ value: uintptr_t) -> Bool {
        return addValue(value % ValueBitMap.mapPrimeMod)
    }
    
    subscript(idx: uintptr_t) -> Bool {
        precondition(idx < ValueBitMap.mapSizeInBits)
        let wordIdx = idx / ValueBitMap.bitsInWord
        let bitIdx = idx % ValueBitMap.bitsInWord
        return (map[Int(wordIdx)] & (1 << bitIdx)) != 0 // TODO: 1UL?
    }
    
    var sizeInBits: uintptr_t { return ValueBitMap.mapSizeInBits }
    
    func forEach(_ f: (size_t) -> Void) {
        for i in 0 ..< ValueBitMap.mapSizeInWords {
            let M = map[Int(i)]
            guard M != 0 else { continue }
            for j in 0 ..< MemoryLayout<uintptr_t>.size * 8 {
                guard M & (uintptr_t(1) << j) != 0 else { continue }
                f(Int(i) * MemoryLayout<uintptr_t>.size * 8 + j)
            }
            
        }
    }
}
