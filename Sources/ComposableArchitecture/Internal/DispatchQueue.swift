import Dispatch
#if os(Android)
import Foundation
#endif

func mainActorNow<R: Sendable>(execute block: @MainActor @Sendable () -> R) -> R {
  #if os(Android)
  if Thread.isMainThread {
    return MainActor._assumeIsolated {
      block()
    }
  } else {
    return DispatchQueue.main.sync {
      MainActor._assumeIsolated {
        block()
      }
    }
  }
  #else
  if DispatchQueue.getSpecific(key: key) == value {
    return MainActor._assumeIsolated {
      block()
    }
  } else {
    return DispatchQueue.main.sync {
      MainActor._assumeIsolated {
        block()
      }
    }
  }
  #endif
}

#if !os(Android)
private let key: DispatchSpecificKey<UInt8> = {
  let key = DispatchSpecificKey<UInt8>()
  DispatchQueue.main.setSpecific(key: key, value: value)
  return key
}()
private let value: UInt8 = 0
#endif
