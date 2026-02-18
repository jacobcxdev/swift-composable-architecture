#if DEBUG
  @preconcurrency import OpenCombineShim
  @_spi(Logging) @testable @preconcurrency import ComposableArchitecture
  import XCTest

  // MARK: - Category A Behavioral Parity Tests
  //
  // These tests verify that Android-specific code paths (the `#else` branches of platform guards)
  // produce behavior equivalent to the Apple paths. The guards stay — these tests ensure the
  // fallback implementations are correct.
  //
  // All tests run on BOTH platforms. On Apple they exercise the Apple path; on Android/Linux
  // they exercise the fallback path. The test assertions must pass on both.

  @Reducer
  fileprivate struct BindingFeature {
    @ObservableState
    struct State: Equatable {
      var text: String = ""
      var count: Int = 0
    }
    enum Action: BindableAction, Equatable {
      case binding(BindingAction<State>)
    }
    var body: some ReducerOf<Self> {
      BindingReducer()
    }
  }

  final class AndroidParityTests: BaseTCATestCase {

    // MARK: - Publishers.Merge Polyfill (Category A: !canImport(Combine))

    // On Apple: Uses Combine's Publishers.Merge
    // On Android: Uses hand-rolled MergeMany polyfill in Effect.swift
    // Contract: merged output contains all values from both upstreams; completes when both complete.

    @MainActor
    func testMergeEffectDeliversAllValues() async {
      struct State: Equatable { var values: [Int] = [] }
      enum Action: Equatable {
        case start
        case value(Int)
      }

      let store = await TestStore(initialState: State()) {
        Reduce(internal: { state, action in
          switch action {
          case .start:
            return .merge(
              .send(.value(1)),
              .send(.value(2))
            )
          case let .value(n):
            state.values.append(n)
            return .none
          }
        }) as Reduce<State, Action>
      }

      await store.send(.start)
      await store.receive(.value(1)) { $0.values = [1] }
      await store.receive(.value(2)) { $0.values = [1, 2] }
    }

    @MainActor
    func testMergeEffectWithRunAndSend() async {
      struct State: Equatable { var values: [Int] = [] }
      enum Action: Equatable {
        case start
        case fromRun(Int)
        case fromSend(Int)
      }

      let store = await TestStore(initialState: State()) {
        Reduce(internal: { state, action in
          switch action {
          case .start:
            return .merge(
              .run { send in await send(.fromRun(10)) },
              .send(.fromSend(20))
            )
          case let .fromRun(n):
            state.values.append(n)
            return .none
          case let .fromSend(n):
            state.values.append(n)
            return .none
          }
        }) as Reduce<State, Action>
      }

      await store.send(.start)
      // .send is publisher-based, .run is task-based. The publisher-based send
      // is delivered first since it's synchronous.
      await store.receive(.fromSend(20)) { $0.values = [20] }
      await store.receive(.fromRun(10)) { $0.values = [20, 10] }
    }

    // MARK: - Effect.concatenate (Sequential Delivery)

    @MainActor
    func testConcatenateDeliversSequentially() async {
      struct State: Equatable { var value = 0 }
      enum Action: Equatable {
        case start, first, second, third
      }

      let store = await TestStore(initialState: State()) {
        Reduce(internal: { state, action in
          switch action {
          case .start:
            return .concatenate(
              .send(.first),
              .send(.second),
              .send(.third)
            )
          case .first:
            state.value = 1
            return .none
          case .second:
            state.value = 2
            return .none
          case .third:
            state.value = 3
            return .none
          }
        }) as Reduce<State, Action>
      }

      await store.send(.start)
      await store.receive(.first) { $0.value = 1 }
      await store.receive(.second) { $0.value = 2 }
      await store.receive(.third) { $0.value = 3 }
    }

    // MARK: - Effect.cancel (Cancellation)

    @MainActor
    func testEffectCancellation() async {
      struct State: Equatable { var value = 0 }
      enum Action: Equatable {
        case start, cancel, response
      }

      let store = await TestStore(initialState: State()) {
        Reduce(internal: { state, action in
          switch action {
          case .start:
            return .run { _ in
              try await Task.never()
            }
            .cancellable(id: "longRunning")
          case .cancel:
            return .cancel(id: "longRunning")
          case .response:
            state.value = 1
            return .none
          }
        }) as Reduce<State, Action>
      }

      await store.send(.start)
      await store.send(.cancel)
    }

    // MARK: - CurrentValueRelay Thread Safety (Category A: os_unfair_lock vs NSRecursiveLock)

    // On Apple: Uses os_unfair_lock (non-recursive, spin lock)
    // On Android: Uses NSRecursiveLock
    // Contract: concurrent reads and writes don't crash or lose values.

    func testCurrentValueRelayConcurrentWrites() async {
      let relay = CurrentValueRelay(0)
      let values = LockIsolated<Set<Int>>([])
      let cancellable = relay.sink { (value: Int) in
        values.withValue { _ = $0.insert(value) }
      }

      await withTaskGroup(of: Void.self) { group in
        for i in 1...500 {
          group.addTask { @Sendable in
            relay.send(i)
          }
        }
      }

      XCTAssert(values.value.contains(0))
      XCTAssertEqual(values.value.count, 501)
      _ = cancellable
    }

    // MARK: - TestStore Send/Receive (Category A: useMainSerialExecutor vs effectDidSubscribe)

    // On Apple: TestStore uses useMainSerialExecutor for synchronization
    // On Android: TestStore uses effectDidSubscribe stream
    // Contract: send + receive correctly sequences actions and effects.

    @MainActor
    func testTestStoreSendReceive() async {
      struct State: Equatable { var value = 0 }
      enum Action: Equatable {
        case tap
        case response(Int)
      }

      let store = await TestStore(initialState: State()) {
        Reduce(internal: { state, action in
          switch action {
          case .tap:
            return .run { send in await send(.response(42)) }
          case let .response(n):
            state.value = n
            return .none
          }
        }) as Reduce<State, Action>
      }

      await store.send(.tap)
      await store.receive(.response(42)) { $0.value = 42 }
    }

    @MainActor
    func testTestStoreExhaustivity() async {
      struct State: Equatable { var count = 0 }
      enum Action: Equatable {
        case increment, decrement
      }

      let store = await TestStore(initialState: State()) {
        Reduce(internal: { state, action in
          switch action {
          case .increment:
            state.count += 1
            return .none
          case .decrement:
            state.count -= 1
            return .none
          }
        }) as Reduce<State, Action>
      }

      await store.send(.increment) { $0.count = 1 }
      await store.send(.decrement) { $0.count = 0 }
    }

    // MARK: - Effect.send Without Animation (Category A: withTransaction unavailable on Android)

    // On Apple: Effect.send(_:animation:) wraps in withTransaction
    // On Android: Only Effect.send(_:) is available (no animation parameter)
    // Contract: action is delivered to reducer; state mutation occurs; effect returned.

    @MainActor
    func testEffectSendDeliversAction() async {
      struct State: Equatable { var done = false }
      enum Action: Equatable {
        case start, delegated
      }

      let store = await TestStore(initialState: State()) {
        Reduce(internal: { state, action in
          switch action {
          case .start:
            return .send(.delegated)
          case .delegated:
            state.done = true
            return .none
          }
        }) as Reduce<State, Action>
      }

      await store.send(.start)
      await store.receive(.delegated) { $0.done = true }
    }

    // MARK: - DismissEffect Without Animation (Category A: withTransaction unavailable on Android)

    // On Apple: DismissEffect wraps dismiss in withTransaction(animation:)
    // On Android: DismissEffect calls dismiss closure directly
    // Contract: dismiss closure is invoked exactly once.

    @MainActor
    func testDismissEffectInvokesClosureOnce() async {
      let dismissCount = LockIsolated(0)

      let dismiss = DismissEffect {
        dismissCount.withValue { $0 += 1 }
      }

      await dismiss()

      XCTAssertEqual(dismissCount.value, 1)
    }

    @MainActor
    func testDismissEffectReportsIssueWhenNoDismissClosure() async {
      let dismiss = DismissEffect()

      XCTExpectFailure {
        $0.compactDescription.contains("couldn't be dismissed")
      }
      await dismiss()
    }

    // MARK: - BindingLocal Standalone (Category A: separate definition on Android)

    // On Apple: BindingLocal comes from SwiftUI environment
    // On Android: BindingLocal is defined standalone in Core.swift
    // Contract: .isActive returns true within its scope, false outside.

    @MainActor
    func testBindingLocalDefaultValue() {
      XCTAssertFalse(BindingLocal.isActive)
    }

    @MainActor
    func testBindingLocalActiveInScope() async {
      XCTAssertFalse(BindingLocal.isActive)

      await BindingLocal.$isActive.withValue(true) {
        XCTAssertTrue(BindingLocal.isActive)
      }

      XCTAssertFalse(BindingLocal.isActive)
    }

    // MARK: - Effect.run Delivers Values

    @MainActor
    func testEffectRunDeliversValues() async {
      struct State: Equatable { var text = "" }
      enum Action: Equatable {
        case fetch
        case received(String)
      }

      let store = await TestStore(initialState: State()) {
        Reduce(internal: { state, action in
          switch action {
          case .fetch:
            return .run { send in
              await send(.received("hello"))
            }
          case let .received(value):
            state.text = value
            return .none
          }
        }) as Reduce<State, Action>
      }

      await store.send(.fetch)
      await store.receive(.received("hello")) { $0.text = "hello" }
    }

    // MARK: - Binding Action Parity

    // Test that @BindableAction + BindingReducer works on both platforms.

    @MainActor
    func testBindingReducerMutatesState() async {
      let store = await TestStore(initialState: BindingFeature.State()) {
        BindingFeature()
      }

      await store.send(.binding(.set(\.text, "hello"))) {
        $0.text = "hello"
      }
      await store.send(.binding(.set(\.count, 42))) {
        $0.count = 42
      }
    }

    // MARK: - Logger Fallback (Category A: OSLog vs print)

    // On Apple: Uses OSLog-based Logger
    // On Android: Uses print-based fallback
    // Contract: logger.log() doesn't crash. No output equivalence needed.

    @MainActor
    func testLoggerDoesNotCrash() {
      Logger.shared.isEnabled = true
      Logger.shared.log("AndroidParityTests: logger smoke test")
      Logger.shared.isEnabled = false
    }
  }

  // MARK: - Category B: SwiftUI Integration (un-guarded code)

  import SwiftUI

  /// Tests verifying un-guarded TCA SwiftUI integrations compile and work correctly.
  /// These exercise the same code paths used on Android via SkipSwiftUI.
  @MainActor
  final class TCASwiftUIParityTests: BaseTCATestCase {

    // MARK: - ForEachStore

    @Reducer
    fileprivate struct ItemFeature {
      @ObservableState
      struct State: Equatable, Identifiable {
        let id: UUID
        var name: String
      }
      enum Action: Equatable {
        case tapped
      }
      var body: some ReducerOf<Self> {
        Reduce { state, action in .none }
      }
    }

    @Reducer
    fileprivate struct ListFeature {
      @ObservableState
      struct State: Equatable {
        var items: IdentifiedArrayOf<ItemFeature.State> = []
      }
      enum Action: Equatable {
        case items(IdentifiedActionOf<ItemFeature>)
      }
      var body: some ReducerOf<Self> {
        EmptyReducer()
          .forEach(\.items, action: \.items) {
            ItemFeature()
          }
      }
    }

    func testForEachStoreInstantiation() {
      // Verify ForEachStore can be created with a store — compilation check
      // for the un-guarded ForEachStore.swift.
      let store = Store(initialState: ListFeature.State()) {
        ListFeature()
      }
      let view = ForEachStore(store.scope(state: \.items, action: \.items)) { itemStore in
        Text(itemStore.name)
      }
      let _ = view.body
    }

    // MARK: - IfLetStore

    @Reducer
    fileprivate struct OptionalFeature {
      @ObservableState
      struct State: Equatable {
        var child: ItemFeature.State?
      }
      enum Action: Equatable {
        case child(ItemFeature.Action)
      }
      var body: some ReducerOf<Self> {
        EmptyReducer()
          .ifLet(\.child, action: \.child) {
            ItemFeature()
          }
      }
    }

    func testIfLetStoreInstantiation() {
      // Verify IfLetStore can be created — compilation check for un-guarded IfLetStore.swift.
      let store = Store(initialState: OptionalFeature.State()) {
        OptionalFeature()
      }
      let view = IfLetStore(store.scope(state: \.child, action: \.child)) { childStore in
        Text(childStore.name)
      }
      let _ = view.body
    }

    // MARK: - NavigationStackStore

    @Reducer
    fileprivate struct PathFeature {
      @ObservableState
      enum State: Equatable {
        case detail(ItemFeature.State)
      }
      enum Action: Equatable {
        case detail(ItemFeature.Action)
      }
      var body: some ReducerOf<Self> {
        Scope(state: \.detail, action: \.detail) {
          ItemFeature()
        }
      }
    }

    @Reducer
    fileprivate struct NavFeature {
      @ObservableState
      struct State: Equatable {
        var path = StackState<PathFeature.State>()
      }
      enum Action: Equatable {
        case path(StackActionOf<PathFeature>)
      }
      var body: some ReducerOf<Self> {
        EmptyReducer()
          .forEach(\.path, action: \.path) {
            PathFeature()
          }
      }
    }

    func testNavigationStackStoreInstantiation() {
      // Verify NavigationStackStore can be created — compilation check for
      // un-guarded NavigationStackStore.swift.
      let store = Store(initialState: NavFeature.State()) {
        NavFeature()
      }
      let view = NavigationStackStore(store.scope(state: \.path, action: \.path)) {
        Text("Root")
      } destination: { state in
        switch state {
        case .detail:
          Text("Detail")
        }
      }
      let _ = view.body
    }

    // MARK: - Sheet / Alert / ConfirmationDialog presentation modifiers

    @Reducer
    fileprivate struct PresentationFeature {
      @ObservableState
      struct State: Equatable {
        @Presents var detail: ItemFeature.State?
        @Presents var alert: AlertState<Action.Alert>?
        @Presents var dialog: ConfirmationDialogState<Action.Dialog>?
      }
      enum Action: Equatable {
        case detail(PresentationAction<ItemFeature.Action>)
        case alert(PresentationAction<Alert>)
        case dialog(PresentationAction<Dialog>)
        enum Alert: Equatable { case confirm }
        enum Dialog: Equatable { case option1, option2 }
      }
      var body: some ReducerOf<Self> {
        EmptyReducer()
          .ifLet(\.$detail, action: \.detail) { ItemFeature() }
          .ifLet(\.$alert, action: \.alert)
          .ifLet(\.$dialog, action: \.dialog)
      }
    }

    func testSheetPresentationModifier() {
      // Verify .sheet(store:) compiles — PresentationModifier + Sheet un-guarded.
      let store = Store(initialState: PresentationFeature.State()) {
        PresentationFeature()
      }
      let view = Text("Base")
        .sheet(store: store.scope(state: \.$detail, action: \.detail)) { detailStore in
          Text(detailStore.name)
        }
      XCTAssertNotNil(view)
    }

    func testAlertPresentationModifier() {
      // Verify .alert(store:) compiles — Alert.swift un-guarded.
      let store = Store(initialState: PresentationFeature.State()) {
        PresentationFeature()
      }
      let view = Text("Base")
        .alert(store: store.scope(state: \.$alert, action: \.alert))
      XCTAssertNotNil(view)
    }

    func testConfirmationDialogPresentationModifier() {
      // Verify .confirmationDialog(store:) compiles — ConfirmationDialog.swift un-guarded.
      let store = Store(initialState: PresentationFeature.State()) {
        PresentationFeature()
      }
      let view = Text("Base")
        .confirmationDialog(store: store.scope(state: \.$dialog, action: \.dialog))
      XCTAssertNotNil(view)
    }
  }
#endif
