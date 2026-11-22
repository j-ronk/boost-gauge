import Testing

struct FixtureTests {
    @Test func loads() {
        #expect(Fixture.string("Core/hello.txt") == "hello\n")
    }
}
