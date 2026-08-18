
import ShellTesting

extension awkTest {

  @Suite("T.multibyte") struct Tmultibyte : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let mb = try inFile("multibyte")
      let mbc = try mb.readAsString()
      try await run(output: mbc,
                    args: "{ print $0 }", mb)
    }
    
    @Test("second") func second() async throws {
      let mb = try inFile("multibyte")
      let mbx = try inFile("multibyte-replaced").readAsString()
      try await run(output: mbx,
                    args: "{ gsub(/ö/, \"Ü\"); print }", mb)
    }

    @Test("third") func third() async throws {
      let mb = try inFile("multibyte")
      let mbx = try inFile("multibyte-onlysomembchars").readAsString()
      try await run(output: mbx,
                    args: "{ gsub(/[^Ü-ö]/, \"\"); print }", mb)
    }

    @Test("fourth") func fourth() async throws {
      let mb = try inFile("multibyte")
      let mbx = try inFile("multibyte-noletters").readAsString()
      let prog = """
        {
          gsub(/[[=a=][=A=][=b=][=B=][=c=][=C=][=d=][=D=][=e=][=E=]]/, "")
          gsub(/[[=f=][=F=][=g=][=G=][=h=][=H=][=i=][=I=][=j=][=J=]]/, "")
          gsub(/[[=k=][=K=][=l=][=L=][=m=][=M=][=n=][=N=][=o=][=O=]]/, "")
          gsub(/[[=p=][=P=][=q=][=Q=][=r=][=R=][=s=][=S=][=t=][=T=]]/, "")
          gsub(/[[=u=][=U=][=v=][=V=][=w=][=W=][=x=][=X=][=y=][=Y=]]/, "")
          gsub(/[[=z=][=Z=]]/, "")
          print
        }
        """
      try await run(output: mbx,
                    args: prog, mb)
    }

    @Test("fifth") func fifth() async throws {
      let mb = try inFile("multibyte")
      let mbx = try inFile("multibyte-noalpha").readAsString()
      let prog = """
        {
          gsub(/[[:alpha:]]/, \"\")
          print
        }
        """
      try await run(output: mbx, args: prog, mb)
    }
    
    @Test("sixth") func sixth() async throws {
      let fooc = "/Ü/\n"
      let foo1 = try tmpfile("foo1", fooc)
      defer { rm(foo1) }
      try await run(withStdin: foo1, output: fooc,
                    args: "-f", foo1, foo1)
    }
    
    @Test("seventh") func seventh() async throws {
      let fooc = "/[Üö]/\n"
      let foo1 = try tmpfile("foo1", fooc)
      defer { rm(foo1) }
      try await run(withStdin: foo1, output: fooc,
                    args: "-f", foo1, foo1)
    }
    
    @Test("eighth") func eighth() async throws {
      let inp = """
        This is a line.
        Patterns like /[Üö]/ do not work yet. Example, run awk /[Üö]/
        over a file containing just Ü.
        This is another line.
        
        """
      let foo0 = try tmpfile("foo0", inp)
      defer { rm(foo0) }
      let outp = """
        Patterns like /[Üö]/ do not work yet. Example, run awk /[Üö]/
        over a file containing just Ü.
        
        """
      try await run(output: outp,
                    args: "/[Üö]/", foo0 )
    }
  }
}
