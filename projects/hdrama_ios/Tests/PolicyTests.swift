import Foundation

func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
@main struct PolicyTests {
 static func main() {
  let signed=RequestPolicy.posterURL("/poster.jpg?token=a%2Bb&expires=123#section",base:"https://en.hdrama.net/series/a")!
  expect(signed.absoluteString == "https://en.hdrama.net/poster.jpg?token=a%2Bb&expires=123", "Poster signatures/query must survive resolution")
  expect(RequestPolicy.posterURL("http://images.example/a",base:"https://en.hdrama.net/") == nil,"Reject cleartext posters")
  expect(RequestPolicy.posterURL("https://name:pass@images.example/a",base:"https://en.hdrama.net/") == nil,"Reject credentials in poster URLs")
  let scoped=HTTPCookie(properties:[.domain:".hdrama.net",.path:"/series",.name:"session",.value:"test",.secure:"TRUE"])!
  expect(RequestPolicy.matches(scoped,url:URL(string:"https://en.hdrama.net/series/a")!),"Matching secure cookie")
  expect(!RequestPolicy.matches(scoped,url:URL(string:"https://en.hdrama.net/series-other")!),"Cookie path requires a slash boundary")
  expect(!RequestPolicy.matches(scoped,url:URL(string:"http://en.hdrama.net/series/a")!),"Secure cookies cannot go over HTTP")
  expect(!RequestPolicy.matches(scoped,url:URL(string:"https://hdrama.net.evil.example/series/a")!),"Domain lookalikes cannot receive cookies")
  let expired=HTTPCookie(properties:[.domain:"en.hdrama.net",.path:"/",.name:"old",.value:"test",.expires:Date(timeIntervalSince1970:1)])!
  expect(!RequestPolicy.matches(expired,url:URL(string:"https://en.hdrama.net/")!),"Expired cookies excluded")
  let home=URL(fileURLWithPath:"/var/mobile/Containers/Data/Application/NEW")
  expect(DownloadPaths.stored(home.appendingPathComponent("Library/Offline/a.mp4"),home:home) == "relative:Library/Offline/a.mp4","Store sandbox-relative paths")
  expect(DownloadPaths.resolve("/var/mobile/Containers/Data/Application/OLD/Library/Offline/a.mp4",home:home)?.path == home.path + "/Library/Offline/a.mp4","Legacy paths migrate across updates")
  expect(DownloadPaths.resolve("relative:Library/../../../../escape",home:home) == nil,"Reject path traversal")
  expect(DownloadPaths.resolve("/etc/passwd",home:home) == nil,"Reject unrelated absolute files")
  print("PASS: 12 request/path policy checks; not a full app/UI/device test suite")
 }
}
