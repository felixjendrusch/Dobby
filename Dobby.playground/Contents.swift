import Dobby

let mock = Mock<(Int, Int)>()
mock.expect(matches((1, 2)))
mock.record((1, 2))

let stub = Stub<(Int, Int), Int>()
let disposable = stub.on(matches((2, 2)), returnValue: 10)
disposable.dispose()
stub.on(any()) { x, y in x * y }
try! stub.invoke((2, 2))

let callback: (Int, Int) -> Int = { x, y in
    mock.record((x, y))
    return try! stub.invoke((x, y))
}

protocol MyProtocol {
    func myMultiply(x: Int, y: Int) -> Int
}

struct MyStructMock: MyProtocol {
    let mock = Mock<(Int, Int)>()
    let stub = Stub<(Int, Int), Int>()
    func myMultiply(x: Int, y: Int) -> Int {
        mock.record((x, y))
        return try! stub.invoke((x, y))
    }
}

class MyClass {
    func myMultiply(x: Int, y: Int) -> Int {
        return x * y
    }
}

class MyClassMock: MyClass {
    let mock = Mock<(Int, Int)>()
    let stub = Stub<(Int, Int), Int>()
    override func myMultiply(x: Int, y: Int) -> Int {
        mock.record((x, y))
        return try! stub.invoke((x, y))
    }
}

let matcher: Matcher<[String: [String: Int?]]> = matches(["foo": matches(["bar": not(some(matches { $0 == 2 }))])])
matcher.matches(["foo": ["bar": 2]])


