import Vapor

import Dispatch

struct OpenSockets {
    private(set) static var sockets: [Int: WebSocket] = [:]
    
    static func insert(_ socket: WebSocket) -> Int {
        let out = id
        id += 1
        queue.sync {
            sockets[out] = socket
        }
        return out
    }
    
    static func remove(at id: Int) {
        queue.async {
            sockets[id] = nil
        }
    }
    
//    static func get(for id: Int) {
//        var out: WebSocket!
//        queue.sync {
//            out = sockets[id]
//        }
//    }
    
    static let queue = DispatchQueue.init(label: "WS")
    
    private static var id = 0
}

let enc = JSONEncoder()

/// Called after your application has initialized.
public func boot(_ app: Application) throws {
    
    app.eventLoop.scheduleRepeatedTask(initialDelay: .seconds(10), delay: .seconds(10)) { (task: RepeatedTask) in
        let _ = try app.client().get("https://baconipsum.com/api/?type=all-meat&paras=1&start-with-lorem=0")
            .flatMap { try $0.content.decode([String].self) }
            .do { (texts) in
                guard let text = texts.first else { return }
                
                let p = Post.init(user: User(name: Name(first: "Акакий", second: "Программистович")), text: text)
                
                postModel.insert(post: p)
                
                eventBuffer.append(element: .add(p.id))
                
                
                OpenSockets.sockets.values.forEach { ws in
                    ws.send(try! enc.encode(Events(error: nil, events: [.add(p.id)])))
                }
            }
    }
    
    app.eventLoop.scheduleRepeatedTask(initialDelay: .seconds(205), delay: .seconds(10)) { (task: RepeatedTask) in
        postModel.deleteRandom(on: app)
            .whenSuccess({ (id) in
                eventBuffer.append(element: .delete(id))
                
                OpenSockets.sockets.values.forEach {$0.send(try! enc.encode(Events(error: nil, events: [.delete(id)])))}
            })
    }
}
