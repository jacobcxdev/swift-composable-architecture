#if canImport(OSLog)
import OSLog
#endif
import Foundation
import OpenCombineShim

@_spi(Logging)
#if swift(<5.10)
  @MainActor(unsafe)
#else
  @preconcurrency@MainActor
#endif
public final class Logger {
  public static let shared = Logger()
  public var isEnabled = false
  @Published public var logs: [String] = []
  #if DEBUG
    #if canImport(OSLog)
    @available(iOS 14, macOS 11, tvOS 14, watchOS 7, *)
    var logger: os.Logger {
      os.Logger(subsystem: "composable-architecture", category: "store-events")
    }
    public func log(level: OSLogType = .default, _ string: @autoclosure () -> String) {
      guard self.isEnabled else { return }
      let string = string()
      if isRunningForPreviews {
        print("\(string)")
      } else {
        if #available(iOS 14, macOS 11, tvOS 14, watchOS 7, *) {
          self.logger.log(level: level, "\(string)")
        }
      }
      self.logs.append(string)
    }
    #else
    public func log(_ string: @autoclosure () -> String) {
      guard self.isEnabled else { return }
      let string = string()
      print("\(string)")
      self.logs.append(string)
    }
    #endif
    public func clear() {
      self.logs = []
    }
  #else
    #if canImport(OSLog)
    @inlinable @inline(__always)
    public func log(level: OSLogType = .default, _ string: @autoclosure () -> String) {
    }
    #else
    @inlinable @inline(__always)
    public func log(_ string: @autoclosure () -> String) {
    }
    #endif
    @inlinable @inline(__always)
    public func clear() {
    }
  #endif
}

private let isRunningForPreviews: Bool = {
  #if canImport(Darwin)
  return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  #else
  return false
  #endif
}()
