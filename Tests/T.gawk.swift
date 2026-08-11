
import ShellTesting

extension awkTest {

  @Suite("T.gawk") struct Tgawk : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
