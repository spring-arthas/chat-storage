# Type Safety

> Type patterns and server data decoding conventions in this project.

---

## Overview

The project is written in Swift with strict typing. All server communication uses `Codable` for JSON encoding/decoding. There is no runtime validation library — validation is handled by Swift's type system and `InputValidator`.

---

## Codable and CodingKeys

Server field names differ from Swift naming conventions. Always use `CodingKeys` to map:

```swift
struct UserDO: Codable, Identifiable {
    let id: Int64
    let username: String
    let nickname: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id = "userId"       // server sends "userId"
        case username = "userName"
        case nickname = "nickName"
        case email = "mail"      // server sends "mail"
    }
}
```

Always document the server field name in comments when the mapping is non-obvious.

---

## ResponseWrapper<T>

All server responses are wrapped in `ResponseWrapper<T>`. This handles two server response formats:

```swift
// Format 1: { "success": true, "msg": "...", "data": {...} }
// Format 2: { "code": 200, "msg": "...", "data": {...} }

struct ResponseWrapper<T: Codable>: Codable {
    let success: Bool?
    let codeValue: Int?    // CodingKeys maps to "code"
    let message: String    // CodingKeys maps to "msg"
    let data: T?

    var code: Int {        // computed: codeValue ?? (success ? 200 : 400)
        ...
    }
}
```

Use `FrameParser.decodePayload(_:as:)` to decode a `Frame` into a `ResponseWrapper<T>`:

```swift
let response = try FrameParser.decodePayload(responseFrame, as: ResponseWrapper<UserDO>.self)
guard response.code == 200, let user = response.data else {
    throw AuthError.loginFailed(response.message)
}
```

---

## Inline Request Structs

For request bodies used only once, define `Codable` structs inline inside the function:

```swift
func createDirectory(pId: Int64, name: String) async throws {
    struct CreateDirRequest: Codable {
        let pId: Int64
        let dirName: String
    }
    let request = CreateDirRequest(pId: pId, dirName: name)
    let jsonData = try JSONEncoder().encode(request)
    // ...
}
```

This is the established pattern in `DirectoryService.swift`. Do not extract these to top-level types unless reused.

---

## Input Validation

Use `InputValidator` (in `InputValidator.swift`) for all user input validation in views:

```swift
guard InputValidator.isValidUsername(username) else {
    errorMessage = InputValidator.getUsernameErrorMessage(username)
    return
}
guard InputValidator.isValidPassword(password) else {
    errorMessage = InputValidator.getPasswordErrorMessage(password)
    return
}
```

`InputValidator` validates:
- Chinese mobile phone numbers (`1[3-9]\d{9}`)
- Email addresses
- Passwords (minimum 6 characters)

---

## Type Organization

| Category | Location |
|----------|---------|
| Server entity types | `Models/do/` |
| Protocol frame types | `Models/frame/` |
| Business models | `Models/business/` |
| Transfer task model | `Services/StorageTransferTask.swift` |
| Response wrapper | `Models/do/UserDO.swift` (bottom section) |
| Request types (one-off) | Inline inside the function that uses them |

---

## Forbidden Patterns

- **`Any` in Codable models**: Define explicit types. `FrameParser.decodeAsDictionary` returns `[String: Any]` only when the structure is truly dynamic (fallback parsing).
- **Force casting `as!`**: Use `guard let` or `if let` instead.
- **JSONSerialization for structured data**: Prefer `JSONDecoder().decode(MyType.self, from: data)`. Only use `JSONSerialization` as a fallback when the response structure is unknown at compile time.
