// Android polyfill for @ObservedObject
// On Apple platforms, ObservedObject comes from SwiftUI.
// On Android (SkipSwiftUI/Fuse mode), it's not provided, so we shim it here.
// This matches SkipUI's non-bridge approach: ObservedObject acts like Bindable
// for the purposes of compilation and binding creation.
#if os(Android)
import SwiftUI

@MainActor @propertyWrapper public struct ObservedObject<ObjectType: AnyObject> {
  public var wrappedValue: ObjectType

  public init(wrappedValue: ObjectType) {
    self.wrappedValue = wrappedValue
  }

  public var projectedValue: Wrapper {
    Wrapper(object: wrappedValue)
  }

  @dynamicMemberLookup
  public struct Wrapper {
    let object: ObjectType

    public subscript<Subject>(
      dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>
    ) -> Binding<Subject> {
      Binding(
        get: { object[keyPath: keyPath] },
        set: { object[keyPath: keyPath] = $0 }
      )
    }
  }
}
#endif
