
import ShellTesting

extension awkTest {

  @Suite("T.intexpr") struct Tintexpr : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let prog = """
        NF == 0    { next }
        $1 == "pat"  { pattern = $2; next }
        {
          check = ($1 ~ pattern)
          printf("%s ~ /%s/ -> should be %d, is %d\\n", $1, pattern, $2, check)
        }
        
        """
      
      let input = """
        pat  ab{0}c
        ac  1
        abc  0

        pat  a(b{0})c
        ac  1
        abc  0

        pat  ab{0}*c
        ac  1
        abc  0

        pat  a(b{0})*c
        ac  1
        abc  0

        pat  ab{0,}c
        ac  1
        abc  1

        pat  a(b{0,})c
        ac  1
        abc  1

        pat  ab{0,}*c
        ac  1
        abc  1

        pat  a(b{0,})*c
        ac  1
        abc  1

        pat  ab{1}c
        ac  0
        abc  1
        abbc  0

        pat  ab{1,}c
        ac  0
        abc  1
        abbc  1
        abbbc  1
        abbbbc  1

        pat  ab{0,1}c
        ac  1
        abc  1
        abbc  0

        pat  ab{0,3}c
        ac  1
        abc  1
        abbc  1
        abbbc  1
        abbbbc  0

        pat  ab{1,3}c
        ac  0
        abc  1
        abbc  1
        abbbc  1
        abbbbc  0
        
        """
      
      let output = """
        ac ~ /ab{0}c/ -> should be 1, is 1
        abc ~ /ab{0}c/ -> should be 0, is 0
        ac ~ /a(b{0})c/ -> should be 1, is 1
        abc ~ /a(b{0})c/ -> should be 0, is 0
        ac ~ /ab{0}*c/ -> should be 1, is 1
        abc ~ /ab{0}*c/ -> should be 0, is 0
        ac ~ /a(b{0})*c/ -> should be 1, is 1
        abc ~ /a(b{0})*c/ -> should be 0, is 0
        ac ~ /ab{0,}c/ -> should be 1, is 1
        abc ~ /ab{0,}c/ -> should be 1, is 1
        ac ~ /a(b{0,})c/ -> should be 1, is 1
        abc ~ /a(b{0,})c/ -> should be 1, is 1
        ac ~ /ab{0,}*c/ -> should be 1, is 1
        abc ~ /ab{0,}*c/ -> should be 1, is 1
        ac ~ /a(b{0,})*c/ -> should be 1, is 1
        abc ~ /a(b{0,})*c/ -> should be 1, is 1
        ac ~ /ab{1}c/ -> should be 0, is 0
        abc ~ /ab{1}c/ -> should be 1, is 1
        abbc ~ /ab{1}c/ -> should be 0, is 0
        ac ~ /ab{1,}c/ -> should be 0, is 0
        abc ~ /ab{1,}c/ -> should be 1, is 1
        abbc ~ /ab{1,}c/ -> should be 1, is 1
        abbbc ~ /ab{1,}c/ -> should be 1, is 1
        abbbbc ~ /ab{1,}c/ -> should be 1, is 1
        ac ~ /ab{0,1}c/ -> should be 1, is 1
        abc ~ /ab{0,1}c/ -> should be 1, is 1
        abbc ~ /ab{0,1}c/ -> should be 0, is 0
        ac ~ /ab{0,3}c/ -> should be 1, is 1
        abc ~ /ab{0,3}c/ -> should be 1, is 1
        abbc ~ /ab{0,3}c/ -> should be 1, is 1
        abbbc ~ /ab{0,3}c/ -> should be 1, is 1
        abbbbc ~ /ab{0,3}c/ -> should be 0, is 0
        ac ~ /ab{1,3}c/ -> should be 0, is 0
        abc ~ /ab{1,3}c/ -> should be 1, is 1
        abbc ~ /ab{1,3}c/ -> should be 1, is 1
        abbbc ~ /ab{1,3}c/ -> should be 1, is 1
        abbbbc ~ /ab{1,3}c/ -> should be 0, is 0
        
        """
      
      try await run(withStdin: input, output: output,
                    args: prog)
    }
  }
}
