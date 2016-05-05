/// <summary>
///     Represents a stream of discrete events/firings.
/// </summary>
/// <typeparam name="T">The type of values fired by the stream.</typeparam>
public class Stream<T>
{
    typealias TV = (T) -> Void
    
    internal let node: Node<T>
    private var disposables: Array<Listener>
    private var firings: Array<T>
    internal let KeepListenersAlive: IKeepListenersAlive
    internal let lock = NSObject()
    
    /// <summary>
    ///     Creates a stream that never fires.
    /// </summary>
    /// <typeparam name="T">The type of the values that would be fired by the stream if it did fire values.</typeparam>
    /// <returns>A stream that never fires.</returns>
    public static func Never<T>() -> Stream<T> {
        return Stream<T>()
    }

    init()
    {
        self.KeepListenersAlive = KeepListenersAliveImplementation()
        self.node = Node<T>(rank: 0)
        self.disposables = []
        self.firings = []
    }

    internal convenience init(keepListenersAlive: IKeepListenersAlive)
    {
        self.init(keepListenersAlive: keepListenersAlive, node: Node<T>(rank: 0), disposables: [Listener](), firings: [T]())
    }

    private init(keepListenersAlive: IKeepListenersAlive, node: Node<T>, disposables: [Listener], firings: [T])
    {
        self.KeepListenersAlive = keepListenersAlive
        self.node = node
        self.disposables = disposables
        self.firings = firings
    }

    /// <summary>
    ///     Listen for events/firings on this stream.  The returned <see cref="IListener" /> may be
    ///     disposed to stop listening.  This is an OPERATIONAL mechanism for interfacing between
    ///     the world of I/O and FRP.
    /// </summary>
    /// <param name="handler">The handler to execute for values fired by the stream.</param>
    /// <returns>An <see cref="IListener" /> which may be disposed to stop listening.</returns>
    /// <remarks>
    ///     <para>
    ///         No assumptions should be made about what thread the handler is called on and it should not block.
    ///         Neither <see cref="StreamSink{T}.Send" /> nor <see cref="CellSink{T}.Send" /> may be called from the
    ///         handler.
    ///         They will throw an exception because this method is not meant to be used to create new primitives.
    ///     </para>
    ///     <para>
    ///         If the <see cref="IListener" /> is not disposed, it will continue to listen until this stream is either
    ///         disposed or garbage collected.
    ///     </para>
    ///     <para>
    ///         To ensure this <see cref="IListener" /> is disposed as soon as the stream it is listening to is either
    ///         disposed, pass the returned listener to this stream's <see cref="AddCleanup" /> method.
    ///     </para>
    /// </remarks>
    public func Listen(handler: (T)->Void) -> Listener?
    {
        var innerListener = self.ListenWeak(handler)
        var listener: Listener?

        listener = Listener(
        unlisten: {
            objc_sync_enter(self.lock)
            defer { objc_sync_exit(self.lock) }

            // ReSharper disable AccessToModifiedClosure
            if (listener != nil)
            {
                self.KeepListenersAlive.StopKeepingListenerAlive(listener!)
            }
            // ReSharper restore AccessToModifiedClosure
        })

        objc_sync_enter(self.lock)
        defer { objc_sync_exit(self.lock) }

        self.KeepListenersAlive.KeepListenerAlive(listener!)

        return listener
    }

    /// <summary>
    ///     Listen for events/firings on this stream.  The returned <see cref="IListener" /> may be
    ///     disposed to stop listening, or it will automatically stop listening when it is garbage collected.
    ///     This is an OPERATIONAL mechanism for interfacing between the world of I/O and FRP.
    /// </summary>
    /// <param name="handler">The handler to execute for values fired by the stream.</param>
    /// <returns>An <see cref="IListener" /> which may be disposed to stop listening.</returns>
    /// <remarks>
    ///     <para>
    ///         No assumptions should be made about what thread the handler is called on and it should not block.
    ///         Neither <see cref="StreamSink{T}.Send" /> nor <see cref="CellSink{T}.Send" /> may be called from the
    ///         handler.
    ///         They will throw an exception because this method is not meant to be used to create new primitives.
    ///     </para>
    ///     <para>
    ///         If the <see cref="IListener" /> is not disposed, it will continue to listen until this stream is either
    ///         disposed or garbage collected or the listener itself is garbage collected.
    ///     </para>
    ///     <para>
    ///         To ensure this <see cref="IListener" /> is disposed as soon as the stream it is listening to is either
    ///         disposed, pass the returned listener to this stream's <see cref="AddCleanup" /> method.
    ///     </para>
    /// </remarks>
    func ListenWeak(handler: TV) -> Listener {
        return self.Listen(INode.Null, action: {(trans2, a) in handler(a) })
    }

    /// <summary>
    ///     Attach a listener to this stream so it gets disposed when this stream is disposed.
    /// </summary>
    /// <param name="listener">The listener to dispose along with this stream.</param>
    /// <returns>A new stream equivalent to this stream which will dispose <paramref name="listener" /> when it is disposed.</returns>
    public func AddCleanup(listener: Listener) -> Stream<T> {
        return Transaction.NoThrowRun({
            var fsNew = self.disposables
            fsNew.append(listener)
            return Stream<T>(keepListenersAlive: self.KeepListenersAlive, node: self.node, disposables: fsNew, firings: self.firings)
        })
    }

    /// <summary>
    ///     Handle the first event on this stream and then automatically unregister.
    /// </summary>
    /// <typeparam name="T">The type of values fired by the stream.</typeparam>
    /// <param name="handler">The handler to execute for values fired by this stream.</param>
    /// <returns></returns>
    public func ListenOnce(handler: (T)->Void) -> Listener? {
        let listener = self.Listen({ a in
            handler(a)
        })
        return listener
    }
    
/*
    /// <summary>
    ///     Handle the first event on this stream and then automatically unregister.
    /// </summary>
    /// <typeparam name="T">The type of values fired by the stream.</typeparam>
    /// <returns>A task which completes when a value is fired by this stream.</returns>
    public func ListenOnce() -> Task<T> {
        return self.ListenOnce(CancellationToken.None)
    }

    /// <summary>
    ///     Handle the first event on this stream and then automatically unregister.
    /// </summary>
    /// <typeparam name="T">The type of values fired by the stream.</typeparam>
    /// <param name="token">The cancellation token.</param>
    /// <returns>A task which completes when a value is fired by this stream.</returns>
    public func ListenOnce(token: CancellationToken) -> Task<T> {
        let tcs = TaskCompletionSource<T>()

        let listener = self.Listen({ a in
            tcs.TrySetResult(a)
        })

        token.Register { tcs.TrySetCanceled() }

        return tcs.Task
    }
*/
    internal func Listen(target: INode, action: (Transaction, T)->Void) -> Listener {
        return Transaction.Apply { trans1 in self.Listen(target, trans: trans1, action: action, suppressEarlierFirings: false) }
    }

    internal func Listen(target: INode, trans: Transaction, action: (Transaction, T) -> Void, suppressEarlierFirings: Bool) -> Listener {
        
        let t = self.node.Link(action, target: target)
        let nodeTarget = t.1
        if (t.0)
        {
            trans.SetNeedsRegenerating()
        }
        // ReSharper disable once LocalVariableHidesMember
        let firings = self.firings
        if (!suppressEarlierFirings && !firings.isEmpty)
        {
            trans.Prioritized(target, action: { trans2 in
                // Anything sent already in this transaction must be sent now so that
                // there's no order dependency between send and listen.
                for a in firings {
                    Transaction.InCallback += 1
                    defer { Transaction.InCallback -= 1 }
                    // Don't allow transactions to interfere with Sodium internals.
                    action(trans2, a)
                }
            })
        }
        return ListenerImplementation(stream: self, action: action, target: nodeTarget)
    }

    /// <summary>
    ///     Transform the stream values according to the supplied function, so the returned
    ///     stream's values reflect the value of the function applied to the input stream's values.
    /// </summary>
    /// <typeparam name="TResult">The type of values fired by the returned stream.</typeparam>
    /// <param name="f">
    ///     Function to apply to convert the values.  It may construct FRP logic or use <see cref="Cell{T}.Sample()" />,
    ///     in which case it is equivalent to calling <see cref="Snapshot{TResult}(Cell{TResult})" /> on the cell.
    ///     Other than this, the function must be a pure function.
    /// </param>
    /// <returns>A stream which fires values transformed by <paramref name="f" /> for each value fired by this stream.</returns>
    public func Map<TResult>(f: (T) -> TResult) -> Stream<TResult>
    {
        let out = Stream<TResult>(keepListenersAlive: self.KeepListenersAlive)
        let l = self.Listen(out.node, action: { (trans2, a) in out.Send(trans2, a: f(a))} )
        return out.UnsafeAddCleanup(l)
    }

    /// <summary>
    ///     Transform the stream values to the specified constant value.
    /// </summary>
    /// <typeparam name="TResult">The type of the constant value fired by the returned stream.</typeparam>
    /// <param name="value">
    ///     The constant value to return from this mapping.
    /// </param>
    /// <returns>A stream which fires the constant value for each value fired by this stream.</returns>
    public func MapTo<TResult>(value: TResult) -> Stream<TResult> {
        return self.Map({ _ in value })
    }

    /// <summary>
    ///     Create a cell with the specified initial value, that is updated by this stream's values.
    /// </summary>
    /// <param name="initialValue">The initial value of the cell.</param>
    /// <returns>A cell with the specified initial value, that is updated by this stream's values.</returns>
    /// <remarks>
    ///     There is an implicit delay state updates caused by stream event firings don't become
    ///     visible as the cell's current value as viewed by
    ///     <see cref="Stream{T}.Snapshot{T2, TResult}(Cell{T2}, Func{T, T2, TResult})" />
    ///     until the following transaction. To put this another way,
    ///     <see cref="Stream{T}.Snapshot{T2, TResult}(Cell{T2}, Func{T, T2, TResult})" /> always sees the value of a cell as
    ///     it was before
    ///     any state changes from the current transaction.
    /// </remarks>
    public func Hold(initialValue: T)  -> Cell<T> {
        return Transaction.Apply{trans in Cell<T>(stream: self, initialValue: initialValue) }
    }

    public func HoldLazy(initialValue: () -> T) -> AnyCell<T> {
        return Transaction.Apply {trans in self.HoldLazy(trans, initialValue: initialValue)}
    }

    /// <summary>
    ///     Create a cell with the specified lazily initialized initial value, that is updated by this stream's values.
    /// </summary>
    /// <param name="initialValue">The lazily initialized initial value of the cell.</param>
    /// <returns>A cell with the specified lazily initialized initial value, that is updated by this stream's values.</returns>
//    public func HoldLazy(@autoclosure(escaping) autoInitialValue: () -> T) -> Cell<T> {
//        return Transaction.Apply {trans in self.HoldLazy(trans, initialValue: autoInitialValue)}
//    }

    internal func HoldLazy(trans: Transaction, lazy: Lazy<T>) -> AnyCell<T> {
        return AnyCell<T>(LazyCell<T>(stream: self, lazyInitialValue: lazy))
    }

    internal func HoldLazy(trans: Transaction, initialValue: () -> T) -> AnyCell<T> {
        return AnyCell<T>(LazyCell<T>(stream: self, lazyInitialValue: initialValue))
    }

    /// <summary>
    ///     Return a stream whose events are the values of the cell at the time of the stream event firing.
    /// </summary>
    /// <typeparam name="TResult">The return type.</typeparam>
    /// <param name="c">The cell to combine with.</param>
    /// <returns>A stream whose events are the values of the cell at the time of the stream event firing.</returns>
    public func Snapshot<TResult, C:CellType where C.Element==TResult>(c: C) -> Stream<TResult>
    {
        return self.Snapshot(c, f: { (a, b) in b })
    }

    /// <summary>
    ///     Return a stream whose events are the result of the combination using the specified
    ///     function of the input stream's value and the value of the cell at the time of the stream event firing.
    /// </summary>
    /// <typeparam name="T1">The type of the cell.</typeparam>
    /// <typeparam name="TResult">The return type.</typeparam>
    /// <param name="c">The cell to combine with.</param>
    /// <param name="f">A function to convert the stream value and cell value into a return value.</param>
    /// <returns>
    ///     A stream whose events are the result of the combination using the specified function of the input stream's
    ///     value and the value of the cell at the time of the stream event firing.
    /// </returns>
    public func Snapshot<T1, TResult, C1 : CellType where C1.Element==T1>(c: C1, f: (T, T1) -> TResult) -> Stream<TResult> {
        let out = Stream<TResult>(keepListenersAlive: self.KeepListenersAlive)
        let l = self.Listen(out.node, action: { (trans2, a) in out.Send(trans2, a: f(a, c.sampleNoTransaction()))} )
        return out.UnsafeAddCleanup(l)
    }

    /// <summary>
    ///     Return a stream whose events are the result of the combination using the specified
    ///     function of the input stream's value and the value of the cells at the time of the stream event firing.
    /// </summary>
    /// <typeparam name="T1">The type of the first cell.</typeparam>
    /// <typeparam name="T2">The type of the second cell.</typeparam>
    /// <typeparam name="TResult">The return type.</typeparam>
    /// <param name="c1">The first cell to combine with.</param>
    /// <param name="c2">The second cell to combine with.</param>
    /// <param name="f">A function to convert the stream value and cell value into a return value.</param>
    /// <returns>
    ///     A stream whose events are the result of the combination using the specified function of the input stream's
    ///     value and the value of the cells at the time of the stream event firing.
    /// </returns>
    public func Snapshot<T1, T2, TResult>(c1: Cell<T1>, c2: Cell<T2>, f: (T, T1, T2) -> TResult) -> Stream<TResult> {
        let out = Stream<TResult>(keepListenersAlive: self.KeepListenersAlive)
        let l = self.Listen(out.node, action: { (trans2, a) in out.Send(trans2, a: f(a, c1.sampleNoTransaction(), c2.sampleNoTransaction()))} )
        return out.UnsafeAddCleanup(l)
    }

    /// <summary>
    ///     Return a stream whose events are the result of the combination using the specified
    ///     function of the input stream's value and the value of the cells at the time of the stream event firing.
    /// </summary>
    /// <typeparam name="T1">The type of the first cell.</typeparam>
    /// <typeparam name="T2">The type of the second cell.</typeparam>
    /// <typeparam name="T3">The type of the third cell.</typeparam>
    /// <typeparam name="TResult">The return type.</typeparam>
    /// <param name="c1">The first cell to combine with.</param>
    /// <param name="c2">The second cell to combine with.</param>
    /// <param name="c3">The third cell to combine with.</param>
    /// <param name="f">A function to convert the stream value and cell value into a return value.</param>
    /// <returns>
    ///     A stream whose events are the result of the combination using the specified function of the input stream's
    ///     value and the value of the cells at the time of the stream event firing.
    /// </returns>
    public func Snapshot<T1, T2, T3, TResult>(c1: Cell<T1>, c2: Cell<T2>, c3: Cell<T3>, f: (T, T1, T2, T3) -> TResult) -> Stream<TResult> {
        let out = Stream<TResult>(keepListenersAlive: self.KeepListenersAlive)
        let l = self.Listen(out.node, action: { (trans2, a) in out.Send(trans2, a: f(a, c1.sampleNoTransaction(), c2.sampleNoTransaction(), c3.sampleNoTransaction()))} )
        return out.UnsafeAddCleanup(l)
    }

    /// <summary>
    ///     Return a stream whose events are the result of the combination using the specified
    ///     function of the input stream's value and the value of the cells at the time of the stream event firing.
    /// </summary>
    /// <typeparam name="T1">The type of the first cell.</typeparam>
    /// <typeparam name="T2">The type of the second cell.</typeparam>
    /// <typeparam name="T3">The type of the third cell.</typeparam>
    /// <typeparam name="T4">The type of the fourth cell.</typeparam>
    /// <typeparam name="TResult">The return type.</typeparam>
    /// <param name="c1">The first cell to combine with.</param>
    /// <param name="c2">The second cell to combine with.</param>
    /// <param name="c3">The third cell to combine with.</param>
    /// <param name="c4">The fourth cell to combine with.</param>
    /// <param name="f">A function to convert the stream value and cell value into a return value.</param>
    /// <returns>
    ///     A stream whose events are the result of the combination using the specified function of the input stream's
    ///     value and the value of the cells at the time of the stream event firing.
    /// </returns>
    public func Snapshot<T1, T2, T3, T4, TResult>(c1: Cell<T1>, c2: Cell<T2>, c3: Cell<T3>, c4: Cell<T4>, f: (T, T1, T2, T3, T4) -> TResult) -> Stream<TResult> {
        let out = Stream<TResult>(keepListenersAlive: self.KeepListenersAlive)
        let l = self.Listen(out.node, action: { (trans2, a) in out.Send(trans2, a: f(a, c1.sampleNoTransaction(), c2.sampleNoTransaction(), c3.sampleNoTransaction(), c4.sampleNoTransaction()))} )
        return out.UnsafeAddCleanup(l)
    }

    /// <summary>
    ///     Merges this stream with another stream and drops the other stream's value in the simultaneous case.
    /// </summary>
    /// <param name="s">The stream to merge with.</param>
    /// <returns>
    ///     A stream that is the result of merging this stream with another stream and dropping the other stream's value in
    ///     the simultaneous case.
    /// </returns>
    /// <remarks>
    ///     <para>
    ///         In the case where two stream events are simultaneous (i.e. both
    ///         within the same transaction), the event value from this stream will take precedence, and
    ///         the event value from <paramref name="s" /> will be dropped.
    ///         To specify a custom combining function, use <see cref="Stream{T}.Merge(Stream{T}, Func{T, T, T})" />.
    ///         s1.OrElse(s2) is equivalent to s1.Merge(s2, (l, r) =&gt l).
    ///     </para>
    ///     <para>
    ///         The name OrElse is used instead of Merge to make it clear that care should be taken because stream events can
    ///         be dropped.
    ///     </para>
    /// </remarks>
    public func OrElse(s: Stream<T>) -> Stream<T> {
        return self.Merge(s, f: { (left, right) in left })
    }

    private func Merge(s: Stream<T>) -> Stream<T> {
        let out = Stream<T>(keepListenersAlive: self.KeepListenersAlive)
        let left = Node<T>(rank: 0)
        let right = out.node
        let nodeTarget = left.Link( { (t, v) in }, target: right).1
        let h = out.Send
        let l1 = self.Listen(left, action: h)
        let l2 = s.Listen(right, action: h)
        return out.UnsafeAddCleanup([l1, l2, Listener(unlisten: { left.Unlink(nodeTarget) })])
    }

    /// <summary>
    ///     Merge two streams of the same type into one, so that stream event values on either input appear on the returned
    ///     stream.
    /// </summary>
    /// <param name="s">The stream to merge this stream with.</param>
    /// <param name="f">
    ///     Function to combine the values. It may construct FRP logic or use <see cref="Cell{T}.Sample" />.
    ///     Apart from this the function must be pure.
    /// </param>
    /// <returns>
    ///     A stream which is the combination of event values from this stream and stream
    ///     <param name="s" />
    ///     .
    /// </returns>
    /// <remarks>
    ///     If the events are simultaneous (that is, one event from this stream and one from <paramref name="s" />
    ///     occurring in the same transaction), combine them into one using the specified combining function
    ///     so that the returned stream is guaranteed only ever to have one event per transaction.
    ///     The event from this stream will appear at the left input of the combining function, and
    ///     the event from <paramref name="s" /> will appear at the right.
    /// </remarks>
    func Merge(s: Stream<T>, f: (T, T) -> T) -> Stream<T> {
        return Transaction.Apply { trans in self.Merge(s).Coalesce(trans, f: f) }
    }

    func Coalesce(trans1: Transaction, f: (T, T) -> T) -> Stream<T> {
        let out = Stream<T>(keepListenersAlive: self.KeepListenersAlive)
        let h = CoalesceHandler.Create(f, out: out)
        let l = self.Listen(out.node, trans: trans1, action: h, suppressEarlierFirings: false)
        return out.UnsafeAddCleanup(l)
    }

    /// <summary>
    ///     Clean up the output by discarding any firing other than the last one.
    /// </summary>
    /// <param name="trans">The transaction to get the last firing from.</param>
    /// <returns>A stream containing only the last event firing from the specified transaction.</returns>
    internal func LastFiringOnly(trans: Transaction) -> Stream<T>
    {
        return self.Coalesce(trans, f: { (first, second) in second } )
    }

    /// <summary>
    ///     Return a stream that only outputs events for which the predicate returns <code>true</code>.
    /// </summary>
    /// <param name="predicate">The predicate used to filter the cell.</param>
    /// <returns>A stream that only outputs events for which the predicate returns <code>true</code>.</returns>
    public func Filter(predicate: (T)->Bool) -> Stream<T> {
        let out = Stream<T>(keepListenersAlive: self.KeepListenersAlive)
        let l = self.Listen(out.node, action: { (trans2, a) in
            if (predicate(a))
            {
                out.Send(trans2, a: a)
            }
        })
        return out.UnsafeAddCleanup(l)
    }

    /// <summary>
    ///     Return a stream that only outputs events from the input stream when the specified cell's value is <code>true</code>
    ///     .
    /// </summary>
    /// <param name="c">The cell that acts as a gate.</param>
    /// <returns>A stream that only outputs events from the input stream when the specified cell's value is <code>true</code>.</returns>
    public func Gate(c: Cell<Bool>) -> Stream<T> {
        // TODO: Wha?  returning nil confuses the compiler, and makes no sense even
        return self.Snapshot(c, f: {(a: T, pred: Bool) in return pred ? a : a })
    }

    /// <summary>
    ///     Return a stream that only outputs events which have a different value than the previous event.
    /// </summary>
    /// <returns>A stream that only outputs events which have a different value than the previous event.</returns>
    /*
extension on T:Comparable???
public func Calm() -> Stream<T> {
        return self.Calm(EqualityComparer<T>.Default)
    }


    /// <summary>
    ///     Return a stream that only outputs events which have a different value than the previous event.
    /// </summary>
    /// <param name="comparer">The equality comparer to use to determine if two items are equal.</param>
    /// <returns>A stream that only outputs events which have a different value than the previous event.</returns>
    public func Calm(IEqualityComparer<T> comparer) -> Stream<T> {
        return self.Calm(Lazy<IMaybe<T>>(Maybe.Nothing<T>), comparer)
    }

    internal func Calm(Lazy<IMaybe<T>> init, IEqualityComparer<T> comparer) -> Stream<T> {
        return self.CollectLazy(init, (a, lastA) =>
        {
            if (lastA.Match(v => comparer.Equals(v, a), () => false))
            {
                return Tuple.Create(Maybe.Nothing<T>(), lastA)
            }

            IMaybe<T> ma = Maybe.Just(a)
            return Tuple.Create(ma, ma)
        }).FilterMaybe()
    }
*/
    /// <summary>
    ///     Transform a stream with a generalized state loop (a Mealy machine).
    ///     The function is passed the input and the old state and returns the new state and output value.
    /// </summary>
    /// <typeparam name="TState">The type of the state of the Mealy machine.</typeparam>
    /// <typeparam name="TReturn">The type of the return value.</typeparam>
    /// <param name="initialState">The initial state of the Mealy machine.</param>
    /// <param name="f">
    ///     Function to apply to update the state.  It may construct FRP logic or use
    ///     <see cref="Cell{T}.Sample" />, in which case it is equivalent to snapshotting the cell with
    ///     <see cref="Snapshot{TReturn}(Cell{TReturn})" />.  Apart from this, the function must be pure.
    /// </param>
    /// <returns>A stream resulting from the transformation of this stream by the Mealy machine.</returns>
    public func Collect<TState, TReturn>(initialState: TState , f: (T,TState)->(TReturn,TState)) -> Stream<TReturn> { return self.CollectLazy(initialState, f: f) }

    /// <summary>
    ///     Transform a stream with a generalized state loop (a Mealy machine) using a lazily evaluated initial state.
    ///     The function is passed the input and the old state and returns the new state and output value.
    /// </summary>
    /// <typeparam name="TState">The type of the state of the Mealy machine.</typeparam>
    /// <typeparam name="TReturn">The type of the return value.</typeparam>
    /// <param name="initialState">The lazily evaluated initial state of the Mealy machine.</param>
    /// <param name="f">
    ///     Function to apply to update the state.  It may construct FRP logic or use
    ///     <see cref="Cell{T}.Sample" />, in which case it is equivalent to snapshotting the cell with
    ///     <see cref="Snapshot{TReturn}(Cell{TReturn})" />.  Apart from this, the function must be pure.
    /// </param>
    /// <returns>A stream resulting from the transformation of this stream by the Mealy machine.</returns>
    public func CollectLazy<TState, TReturn>(@autoclosure(escaping) initialState: () -> TState, f: (T,TState) -> (TReturn, TState)) -> Stream<TReturn> {
        return Transaction.NoThrowRun({
            let es = StreamLoop<TState>()
            let s = es.HoldLazy(initialState)
            let ebs = self.Snapshot(s, f: f)
            let eb = ebs.Map{ $0.0}
            let esOut = ebs.Map{ $0.1}
            es.Loop(esOut)
            return eb
        })
    }

    /// <summary>
    ///     Accumulate on this stream, outputting the new state each time an event fires.
    /// </summary>
    /// <typeparam name="TReturn">The type of the accumulated state.</typeparam>
    /// <param name="initialState">The initial state.</param>
    /// <param name="f">
    ///     Function to apply to update the state.  It may construct FRP logic or use
    ///     <see cref="Cell{T}.Sample" />, in which case it is equivalent to snapshotting the cell with
    ///     <see cref="Snapshot{TReturn}(Cell{TReturn})" />.  Apart from this, the function must be pure.
    /// </param>
    /// <returns>A cell holding the accumulated state of this stream.</returns>
    public func Accum<TReturn>(initialState: TReturn, f: (T,TReturn) -> TReturn) -> AnyCell<TReturn> { return self.AccumLazy(initialState, f: f) }

    public func AccumLazy<TReturn>(@autoclosure(escaping) initialState: () -> TReturn, f: (T,TReturn)->TReturn) -> AnyCell<TReturn> {
        return Transaction.NoThrowRun(
        {
            let es = StreamLoop<TReturn>()
            let s = es.HoldLazy(initialState)
            let esOut = self.Snapshot(s, f: f)
            es.Loop(esOut)
            return esOut.HoldLazy(initialState)
        })
    }

    /// <summary>
    ///     Return a stream that outputs only one value: the next event of the input stream starting from the transaction in
    ///     which this method was invoked.
    /// </summary>
    /// <returns>
    ///     A stream that outputs only one value: the next event of the input stream starting from the transaction in
    ///     which this method was invoked.
    /// </returns>
    public func Once() -> Stream<T>
    {
        // This is a bit long-winded but it's efficient because it unregisters
        // the listener.
        let out = Stream<T>(keepListenersAlive: self.KeepListenersAlive)
        var l: Listener

        l = self.Listen(out.node, action: { (trans, a) in
            out.Send(trans, a: a)
        })
        return out.UnsafeAddCleanup(l)
    }

    // This is not thread-safe, so one of these two conditions must apply:
    // 1. We are within a transaction, since in the current implementation
    //    a transaction locks out all other threads.
    // 2. The object on which this is being called was created has not yet
    //    been returned from the method where it was created, so it can't
    //    be shared between threads.
    internal func UnsafeAddCleanup(cleanup: Listener) -> Stream<T>
    {
        self.disposables.append(cleanup)
        return self
    }

    internal func UnsafeAddCleanup(ls: [Listener]) -> Stream<T>
    {
        self.disposables.appendContentsOf(ls)
        return self
    }

    func Send(trans: Transaction, a: T)
    {
        if (self.firings.isEmpty)
        {
            trans.Last({ self.firings.removeAll() })
        }
        self.firings.append(a)

        let targets = Set<NodeTarget<T>>(self.node.GetListeners())
        for target in targets {
            trans.Prioritized(target.node, action: { trans2 in
                Transaction.InCallback += 1
                defer { Transaction.InCallback -= 1 }
                // Don't allow transactions to interfere with Sodium internals.
                // Dereference the weak reference
                
                    // If it hasn't been garbage collected, call it.
                    target.Action(trans2, a)
                //}
                //else
                //{
                    // If it has been garbage collected, remove it.
                //    self.node.RemoveListener(target)
                //}
            })
        }
    }
}

class ListenerImplementation<T> : Listener
{
    // It's essential that we keep the action alive, since the node uses
    // a weak reference.
    // ReSharper disable once NotAccessedField.Local
    private let action: (Transaction, T) -> Void
    // It's essential that we keep the listener alive while the caller holds
    // the Listener, so that the garbage collector doesn't get triggered.
    private let stream: Stream<T>
    
    private let target: NodeTarget<T>
    
    init(stream: Stream<T>, action: (Transaction, T) -> Void, target: NodeTarget<T>) {
        self.stream = stream
        self.action = action
        self.target = target
        super.init(unlisten: { })
    }
    
    internal override func Unlisten()
    {
        self.stream.node.Unlink(self.target)
    }
}

private class KeepListenersAliveImplementation : IKeepListenersAlive
{
    private var listeners = Set<Listener>()
    private var childKeepListenersAliveList = Array<IKeepListenersAlive>()
    
    func KeepListenerAlive(listener: Listener) {
        self.listeners.insert(listener)
    }
    
    func StopKeepingListenerAlive(listener: Listener) {
        self.listeners.remove(listener)
    }
    
    func Use(childKeepListenersAlive: IKeepListenersAlive) {
        self.childKeepListenersAliveList.append(childKeepListenersAlive)
    }
}
