import CXShim
import CXUtility

extension Publisher where Failure == Never {
    
    public func invoke<Target: AnyObject>(_ method: @escaping (Target) -> (Output) -> Void, on object: Target) -> AnyCancellable {
        let invoke = Subscribers.Invoke(object: object, method: method)
        self.subscribe(invoke)
        return AnyCancellable(invoke)
    }
    
    public func invoke<Target: AnyObject>(_ method: @escaping (Target) -> (Output) -> Void, weaklyOn object: Target) -> AnyCancellable {
        let invoke = Subscribers.Invoke(objectNoRetain: object, method: method)
        self.subscribe(invoke)
        return AnyCancellable(invoke)
    }
}

extension Publisher where Output == Void, Failure == Never {
    
    public func invoke<Target: AnyObject>(_ method: @escaping (Target) -> () -> Void, on object: Target) -> AnyCancellable {
        let invoke = Subscribers.Invoke(object: object, method: method)
        self.subscribe(invoke)
        return AnyCancellable(invoke)
    }
    
    public func invoke<Target: AnyObject>(_ method: @escaping (Target) -> () -> Void, weaklyOn object: Target) -> AnyCancellable {
        let invoke = Subscribers.Invoke(objectNoRetain: object, method: method)
        self.subscribe(invoke)
        return AnyCancellable(invoke)
    }
}

extension Subscribers {
    
    public final class Invoke<Target: AnyObject, Input>: Subscriber, Cancellable, CustomStringConvertible, CustomReflectable, CustomPlaygroundDisplayConvertible {
        
        public typealias Failure = Never
        
        enum RefBox {
            
            final class WeakBox {
                weak var object: Target?
                init(_ object: Target) {
                    self.object = object
                }
            }
            
            case _strong(Target)
            case _weak(WeakBox)
            
            static func strong(_ object: Target) -> RefBox {
                return ._strong(object)
            }
            
            static func weak(_ object: Target) -> RefBox {
                return ._weak(WeakBox(object))
            }
            
            var object: Target? {
                switch self {
                case let ._strong(object): return object
                case let ._weak(box): return box.object
                }
            }
        }
        
        enum Method {
            case withParameter((Target) -> (Input) -> Void)
            case withoutParameter((Target) -> () -> Void)
            
            var body: Any {
                switch self {
                case let .withParameter(body): return body
                case let .withoutParameter(body): return body
                }
            }
        }
        
        private var object: RefBox?
        
        private let method: Method
        
        private let lock = Lock()
        private var subscription: Subscription?
        
        init(object: RefBox, method: Method) {
            self.object = object
            self.method = method
        }
        
        public func receive(subscription: Subscription) {
            self.lock.lock()
            if self.subscription == nil {
                self.subscription = subscription
                self.lock.unlock()
                subscription.request(.unlimited)
            } else {
                self.lock.unlock()
                subscription.cancel()
            }
        }
        
        public func receive(_ value: Input) -> Subscribers.Demand {
            self.lock.lock()
            guard self.subscription != nil, let obj = self.object?.object else {
                self.lock.unlock()
                return .none
            }
            self.lock.unlock()
            switch method {
            case let .withParameter(body):
                body(obj)(value)
            case let .withoutParameter(body):
                body(obj)()
            }
            
            return .none
        }
        
        public func receive(completion: Subscribers.Completion<Never>) {
            self.cancel()
        }
        
        public func cancel() {
            self.lock.lock()
            guard let subscription = self.subscription else {
                self.lock.unlock()
                return
            }
            
            self.subscription = nil
            self.object = nil
            self.lock.unlock()
            
            subscription.cancel()
        }
        
        public var description: String {
            return "Invoke \(Target.self)"
        }
        
        public var customMirror: Mirror {
            return Mirror(self, children: [
                "object": self.object?.object as Any,
                "method": self.method.body,
                "upstreamSubscription": self.subscription as Any
            ])
        }
        
        public var playgroundDescription: Any {
            return self.description
        }
    }
}

extension Subscribers.Invoke {
    
    convenience init(object: Target, method: @escaping (Target) -> (Input) -> Void) {
        self.init(object: .strong(object), method: .withParameter(method))
    }
    
    convenience init(objectNoRetain object: Target, method: @escaping (Target) -> (Input) -> Void) {
        self.init(object: .weak(object), method: .withParameter(method))
    }
}

extension Subscribers.Invoke where Input == Void {
    
    convenience init(object: Target, method: @escaping (Target) -> () -> Void) {
        self.init(object: .strong(object), method: .withoutParameter(method))
    }
    
    convenience init(objectNoRetain object: Target, method: @escaping (Target) -> () -> Void) {
        self.init(object: .weak(object), method: .withoutParameter(method))
    }
}
