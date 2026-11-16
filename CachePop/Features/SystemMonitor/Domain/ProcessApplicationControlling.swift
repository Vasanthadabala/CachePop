import Foundation

@MainActor
protocol ProcessApplicationControlling {
    func canQuit(pid: Int32) -> Bool
    func quit(pid: Int32)
    func retainDetails(for processIDs: Set<Int32>)
    func releaseDetails()
}
