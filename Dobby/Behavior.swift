/// A value type-erased expectation.
fileprivate struct Expectation: CustomStringConvertible {
    fileprivate let description: String

    /// The matching closure of this expectation.
    ///
    /// Given the index of a recorded interaction, the closure is supposed to
    /// check whether the corresponding value fulfills this expectation.
    fileprivate let matches: (Int) -> Bool

    /// The recorder that is expected (not) to record an interaction with a
    /// corresponding matching value.
    fileprivate let recorder: InteractionRecording

    /// Whether this expectation is negative.
    fileprivate let negative: Bool

    /// The file in which this expectation was set up.
    fileprivate let file: StaticString

    /// The line at which this expectation was set up.
    fileprivate let line: UInt

    /// Creates a new value type-erased expectation with the given description,
    /// matching closure, recorder, and negative flag.
    fileprivate init(description: String, matches: @escaping (Int) -> Bool, recorder: InteractionRecording, negative: Bool, file: StaticString, line: UInt) {
        self.description = description
        self.matches = matches

        self.recorder = recorder
        self.negative = negative

        self.file = file
        self.line = line
    }

    /// Creates a new value type-erased expectation with the given matcher,
    /// recorder, and negative flag using the matcher's textual representation
    /// as description.
    fileprivate init<Matcher: MatcherConvertible, Recorder: ValueRecording>(matcher: Matcher, recorder: Recorder, negative: Bool, file: StaticString, line: UInt) where Matcher.ValueType == Recorder.Value {
        let actualMatcher = matcher.matcher()

        // The matching closure captures the value type of the recorder.
        let matches = { (index: Int) -> Bool in
            let actualValue = recorder.valueForInteraction(at: index)
            return actualMatcher.matches(actualValue)
        }

        self.init(description: actualMatcher.description, matches: matches, recorder: recorder, negative: negative, file: file, line: line)
    }
}

///// A expectation-based verification.
//fileprivate struct Verification {
//    /// The expectation that is to be verified.
//    fileprivate let expectation: Expectation
//
//    /// Whether the expectation has been fulfilled.
//    fileprivate var fulfilled = false
//
//    /// Creates a new verification with the given expectation.
//    fileprivate init(expectation: Expectation) {
//        self.expectation = expectation
//    }
//}

/// An iterator over a given set of interaction recorders, producing their
/// interactions in chronological order.
fileprivate struct InteractionRecordingIterator: IteratorProtocol {
    fileprivate struct Element {
        fileprivate let recorder: InteractionRecording

        fileprivate var currentIndex: Int

        fileprivate var currentInteraction: Interaction {
            return recorder.interactions[AnyIndex(currentIndex)]
        }

        fileprivate var timestamp: Timestamp {
            return currentInteraction.timestamp
        }
    }

    private var elements: [Element]

    private mutating func heapify(at index: Int) {
        var parentIndex = index

        while parentIndex < elements.count {
            let leftChildIndex = 2 * parentIndex + 1
            let rightChildIndex = 2 * parentIndex + 2

            var smallestIndex = parentIndex

            if leftChildIndex < elements.count && elements[leftChildIndex].timestamp < elements[smallestIndex].timestamp {
                smallestIndex = leftChildIndex
            }

            if rightChildIndex < elements.count && elements[rightChildIndex].timestamp < elements[smallestIndex].timestamp {
                smallestIndex = rightChildIndex
            }

            if smallestIndex == parentIndex {
                break
            }

            let parent = elements[parentIndex]
            elements[parentIndex] = elements[smallestIndex]
            elements[smallestIndex] = parent
            
            parentIndex = smallestIndex
        }
    }

    fileprivate init(recorders: Set<AnyInteractionRecording>) {
        elements = recorders.map({ recorder in
            return Element(recorder: recorder, currentIndex: 0)
        })

        for index in stride(from: (elements.count / 2 - 1), through: 0, by: -1) {
            heapify(at: index)
        }
    }

    fileprivate mutating func next() -> Element? {
        guard let element = elements.first else {
            return nil
        }

        if element.currentIndex + 1 == element.recorder.interactions.count {
            if elements.count == 1 {
                elements.removeLast()
            } else {
                elements[0] = elements.removeLast()
            }
        } else {
            elements[0].currentIndex += 1
        }

        heapify(at: 0)

        return element
    }
}

/// A behavior that can verify set up expectations with multiple interaction
/// recorders, strictly or nicely, ordered or unordered.
public final class _Behavior {
    /// Whether this behavior is strict (or nice).
    private let strict: Bool

    /// Whether the order of expectations matters.
    private let ordered: Bool

    /// All set up expectations.
    private var expectations: [Expectation] = []
    private let expectationsQueue = DispatchQueue(label: "com.trivago.dobby.behavior-expectationsQueue", attributes: .concurrent)

    /// Creates a new behavior with the given strict and ordered flags.
    public init(strict: Bool = true, ordered: Bool = true) {
        self.strict = strict
        self.ordered = ordered
    }

    /// Creates a new behavior with the given nice and ordered flags.
    public convenience init(nice: Bool, ordered: Bool = true) {
        self.init(strict: nice == false, ordered: ordered)
    }

    /// Sets up the given matcher as expectation for the given recorder.
    public func expect<Matcher: MatcherConvertible, Recorder: ValueRecording>(_ matcher: Matcher, in recorder: Recorder, file: StaticString = #file, line: UInt = #line) where Matcher.ValueType == Recorder.Value {
        let expectation = Expectation(matcher: matcher, recorder: recorder, negative: false, file: file, line: line)

        expectationsQueue.sync(flags: .barrier, execute: {
            expectations.append(expectation)
        })
    }

    public func verify() {
        var expectations = expectationsQueue.sync(execute: {
            return self.expectations
        })

        let recorders = Set(expectations.map({ expectation in
            return AnyInteractionRecording(expectation.recorder)
        }))

        let iterator = InteractionRecordingIterator(recorders: recorders)

        interaction: for element in IteratorSequence(iterator) {
            for (index, expectation) in expectations.enumerated() {
                if expectation.recorder.objectIdentifier == element.recorder.objectIdentifier && expectation.matches(element.currentIndex) {
                    if expectation.negative == false {
                        expectations.remove(at: index)
                    } else {
                        print("Interaction <\(String(describing: element.currentInteraction))> not allowed")
                    }

                    continue interaction
                } else if ordered {
                    if strict {
                        print("Interaction <\(String(describing: element.currentInteraction))> does not match expectation <\(expectation)> (\(expectation.file):\(expectation.line))")
                    }

                    if expectation.negative == false {
                        continue interaction
                    }
                }
            }

            if strict {
                print("Interaction <\(String(describing: element.currentInteraction))> not expected")
            }
        }

        for expectation in expectations {
            if expectation.negative == false {
                print("Expectation <\(expectation)> not fulfilled")
            }
        }
    }
}
