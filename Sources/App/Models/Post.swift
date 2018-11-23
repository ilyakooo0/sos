//
//  Post.swift
//  App
//
//  Created by Ilya on 22/11/2018.
//

import Foundation
import Vapor

class Model {
    var posts: [Int: Post] = [:]
    
    enum Error: AbortError {
        var status: HTTPResponseStatus {return .notFound}
        
        var reason: String {return "User not found."}
        
        var identifier: String {return "userNotFound"}
                
        case notFound
    }
    
    func getPost(for id: Post.Id, on worker: Worker) -> Future<Post> {
        let out = worker.eventLoop.newPromise(Post.self)
        
        queue.async {
            if let post = self.posts[id] {
                out.succeed(result: post)
            } else {
                out.fail(error: Error.notFound)
            }
        }
        
        return out.futureResult
    }
    
    func deleteRandom(on worker: Worker) -> Future<Post.Id> {
        let out = worker.eventLoop.newPromise(Post.Id.self)
        
        if let post = self.posts.randomElement() {
            self.queue.sync(flags: .barrier) {
                self.posts[post.key] = nil
                out.succeed(result: post.key)
            }
        } else {
            out.fail(error: Error.notFound)
        }
        
        return out.futureResult

    }
    
    func insert(post: Post) {
        queue.sync(flags: .barrier) {
            posts[post.id] = post
        }
    }
    
    private let queue = DispatchQueue(label: "soy.iko.Model")
}

let postModel = Model()

enum Event: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .delete(let id):
            try container.encode(id, forKey: .id)
            try container.encode("delete", forKey: .type)
        case .add(let id):
            try container.encode(id, forKey: .id)
            try container.encode("add", forKey: .type)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case id
    }
    
    case delete(Post.Id)
    case add(Post.Id)
}

struct CyclicBuffer<T> {
    var buffer: [T?]
    
    var index = 0
    let size: Int
    init(of size: Int) {
        self.size = size
        buffer = Array(repeating: nil, count: size)
    }
    
    mutating func append(element: T?) {
        queue.sync(flags: .barrier) {
            buffer[index] = element
            index = (index+1)%size
        }
    }
    
    func get(last number: Int, loop: Worker) -> Future<ArraySlice<T?>> {
        
        let out = loop.eventLoop.newPromise(ArraySlice<T?>.self)
        
//        var out: ArraySlice<T?>!
        queue.async {
            out.succeed(result: (self.buffer[self.index+1..<self.size] + self.buffer[0...max(number-1, self.index)]))
        }
        
        return out.futureResult
    }
    
    private let queue = DispatchQueue(label: "soy.iko.Buffer")
}

var eventBuffer = CyclicBuffer<Event>(of: 100)

struct Events: Encodable {
    let error: String?
    let events: [Event]?
}

struct Post: Content {
    typealias Id = Int
    
    let user: User
    let text: String
    
    let id: Id = {
        lastID += 1;
        return lastID
    }()
    
    static private var lastID: Int = 0
}

struct User: Content {
    let name: Name
}

struct Name: Content {
    let first: String
    let second: String
}
