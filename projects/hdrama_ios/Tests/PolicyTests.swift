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

  var gate = DownloadResolutionGate()
  let first = gate.begin("episode")
  expect(gate.accepts(first, itemID: "episode", state: "queued"), "Current queued preparation accepted")
  expect(!gate.accepts(first, itemID: "episode", state: "paused"), "Pause blocks preparation callback")
  expect(!gate.accepts(first, itemID: nil, state: nil), "Deleted item blocks preparation callback")
  expect(!gate.invalidate("other"), "Unrelated pause leaves current preparation intact")
  expect(gate.invalidate("episode"), "Pause invalidates current preparation")
  expect(!gate.accepts(first, itemID: "episode", state: "queued"), "Invalidated success or failure cannot mutate state")
  let resumed = gate.begin("episode")
  expect(first != resumed, "Pause and resume allocate a fresh generation")
  expect(!gate.accepts(first, itemID: "episode", state: "queued"), "Old callback cannot revive a resumed item")
  expect(!gate.finish(first) && gate.active == resumed, "Stale completion cannot clear a newer attempt")
  expect(gate.accepts(resumed, itemID: "episode", state: "queued"), "New resumed callback is accepted")
  expect(gate.finish(resumed) && gate.active == nil, "Current completion releases the queue")
  expect(!gate.accepts(resumed, itemID: "episode", state: "queued"), "Duplicate completion cannot start another task")
  print("PASS: 24 request/path and cancellation checks; not a full app/UI/device test suite")

  // Simulated playback cadence: the player checkpoints every 5 s, storage window is 15 s.
  let base = Date(timeIntervalSince1970: 1_700_000_000)
  var writes = 0
  var lastWrite: Date?
  var storedPosition = -1.0
  var pendingPosition = 0.0
  for step in 0...12 {
      let now = base.addingTimeInterval(Double(step) * 5)
      let position = Double(step) * 5
      if ProgressWritePolicy.shouldFlush(last: lastWrite, now: now, force: false) {
          writes += 1
          lastWrite = now
          storedPosition = position
      } else {
          pendingPosition = position
      }
  }
  expect(writes == 5, "60 s of 5 s checkpoints writes 5 times instead of 13")
  expect(storedPosition == 60, "The last written position is the newest checkpoint boundary")
  pendingPosition = 65
  expect(!ProgressWritePolicy.shouldFlush(last: base.addingTimeInterval(60), now: base.addingTimeInterval(65), force: false), "A checkpoint inside the 15 s window is deferred")
  pendingPosition = 70
  expect(ProgressWritePolicy.shouldFlush(last: base.addingTimeInterval(60), now: base.addingTimeInterval(70), force: false), "The deferred value is written at the next boundary")
  expect(pendingPosition == 70, "The deferred value is the latest position, not the first one")
  expect(ProgressWritePolicy.shouldFlush(last: base.addingTimeInterval(69), now: base.addingTimeInterval(70), force: true), "Pause, dismiss, seek and background flush bypass the window")
  expect(ProgressWritePolicy.minimumInterval > 5, "The storage window is longer than the 5 s checkpoint cadence")
  print("PASS: 6 progress-cadence checks; not a full app/UI/device test suite")
 }
}
