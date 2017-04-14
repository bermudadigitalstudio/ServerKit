import Foundation

public extension Int {
  public var is2xx: Bool {
    return (200 ..< 300 ~= self)
  }
}

let defaultTimeout = { DispatchWallTime.now() + .seconds(5) }

public func synchronize<T>(timeout: DispatchWallTime = defaultTimeout(), functions: [((@escaping (T) -> ()) -> Void)]) -> SyncResult<[T]> {
  let q = DispatchQueue(label: "sync-queue")
  let sema = DispatchSemaphore(value: 0)
  var result: [T] = []
  for f in functions {
    f { res in
      q.async {
        result.append(res)
        sema.signal()
      }
    }
  }
  for _ in functions {
    guard case .success = sema.wait(wallTimeout: timeout) else {
      return .timedOut
    }
  }
  return .success(result)
}

public enum SyncResult<T> {
  case success(T)
  case timedOut
  func map<U>(_ closure:(T) -> (U)) -> SyncResult<U> {
    switch self {
    case .timedOut: return .timedOut
    case .success(let t): return .success(closure(t))
    }
  }
}
public func synchronize<T>(timeout: DispatchWallTime = defaultTimeout(), function: @escaping ((@escaping (T) -> Void) -> Void)) -> SyncResult<T> {
  return synchronize(timeout: timeout, functions: [function]).map { $0.first! }
}

public enum Either<Left, Right> {
  case left(Left)
  case right(Right)
  func flatMap<T>(_ closure: (Left) -> (Either<T, Right>)) -> Either<T, Right> {
    switch self {
    case let .left(l):
      return closure(l)
    case let .right(r):
      return .right(r)
    }
  }
}
extension String: Error {}
public func validateSessionResponse(data: Data?, resp: URLResponse?, err: Error?) -> Either<(data: Data?, response: HTTPURLResponse), Error> {
  guard err == nil else {
    return .right(err!)
  }
  guard let response = resp as? HTTPURLResponse else {
    return .right("Did not receive meaningful HTTP response")
  }
  return .left((data: data, response: response))
}

public func validateSessionResponse(data: Data?, resp: URLResponse?, err: Error?) -> Either<(body: String?, response: HTTPURLResponse), Error> {
  return validateSessionResponse(data: data, resp: resp, err: err).flatMap({ (data: Data?, response: HTTPURLResponse) -> (Either<(body: String?, response: HTTPURLResponse), Error>) in
    if let d = data {
      guard let body = String(data: d, encoding: .utf8) else {
        return .right("Could not decode:\n\(String(describing: data))")
      }
      return .left((body: body, response: response))
    } else {
      return .left((body: nil, response: response))
    }
  })
}

public func check2xx(data: Data?, resp: HTTPURLResponse) -> Either<(data: Data?, resp: HTTPURLResponse), Error> {
  if resp.statusCode.is2xx {
    return .left((data: data, resp: resp))
  } else {
    return .right("Got non 2xx status code: \(resp.statusCode)")
  }
}

public func validateResponseIs2xxWithJSON(data: Data?, resp: URLResponse?, err: Error?) -> Either<Any, Error> {
  return validateSessionResponse(data: data, resp: resp, err: err).flatMap(check2xx).flatMap({ (data: Data?, response: HTTPURLResponse) -> (Either<Any, Error>) in
    do {
      guard let d = data else {
        throw "No json returned"
      }
      return .left(try JSONSerialization.jsonObject(with: d, options: []))
    } catch {
      return .right(error)
    }
  })
}

public func validateResponseIs2xxString(data: Data?, resp: URLResponse?, err: Error?) -> Either<String?, Error> {
  return validateSessionResponse(data: data, resp: resp, err: err).flatMap(check2xx).flatMap { (data, resp) -> (Either<String?, Error>) in
    guard let d = data else {
      return .left(nil)
    }
    guard let s = String(data: d, encoding: .utf8) else {
      return .right("Could not decode data")
    }
    return .left(s)
  }
}

public func encodeObjToJSONStringCrashingOnErrors(_ obj: Any) -> String {
  do {
    let data = try JSONSerialization.data(withJSONObject: obj, options: [])
    guard let s = String(data: data, encoding: .utf8) else {
      throw "Couldn't decode json data into string. Data: \(data)"
    }
    return s
  } catch {
    fatalError("Failed to encode message and user ID, got error: \(error)")
  }
}

public func encodeStringAsDataCrashingOnErrors(_ string: String) -> Data {
  guard let bodyAsData = string.data(using: .utf8) else {
    fatalError("Could not encode string as utf-8 data: \n\(string)")
  }
  return bodyAsData
}
