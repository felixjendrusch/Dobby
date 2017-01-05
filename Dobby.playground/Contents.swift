@testable import Dobby

let a = Recorder<Int>()
let b = Recorder<String>()

a.record(2)
b.record("foo")
a.record(4)
b.record("bar")

let behavior = _Behavior()
behavior.expect(2, in: a)
behavior.expect("foo", in: b)
behavior.expect(4, in: a)
behavior.expect("bar", in: b)
behavior.verify()
