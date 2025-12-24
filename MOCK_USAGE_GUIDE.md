# Mock Usage Guide
## How to Use Mockolo-Generated Mocks in Tests

## ✅ Correct Approach

**Mockolo generates mocks** → **You use them in your tests**

### Workflow

1. **Generate Mocks** (using Mockolo):
   ```bash
   ./Scripts/SaneMaster.rb gen_mock --target Core/Protocols
   ```
   This creates `CameraServiceProtocolMock`, `ExportServiceProtocolMock`, etc. in `SaneVideoTests/Mocks/Mocks.swift`

2. **Use Generated Mocks in Tests**:
   ```swift
   import XCTest
   @testable import SaneVideo
   
   @MainActor
   final class MyTests: XCTestCase {
       var mockCamera: CameraServiceProtocolMock!
       
       override func setUp() {
           // Use Mockolo-generated mock
           mockCamera = CameraServiceProtocolMock()
           
           // Configure behavior
           mockCamera.isActive = true
           mockCamera.startHandler = {
               // Custom async behavior
           }
           
           // Inject into service container
           ServiceContainer.shared.cameraService = mockCamera
       }
       
       func testSomething() async throws {
           // Use the mock
           let sut = MyService(camera: mockCamera)
           
           // Test code...
           
           // Verify calls
           XCTAssertEqual(mockCamera.startCallCount, 1)
       }
   }
   ```

---

## ❌ What NOT to Do

**Don't create manual mocks** when Mockolo-generated mocks exist:

```swift
// ❌ BAD: Manual mock (outdated)
class MockCameraService: CameraServiceProtocol {
    // Manual implementation...
}

// ✅ GOOD: Use Mockolo-generated mock
let mockCamera = CameraServiceProtocolMock()
```

---

## 📋 Current Status

### ✅ Using Mockolo Mocks
- `CameraServiceProtocolMock` - Generated, ready to use
- `ExportServiceProtocolMock` - Generated, ready to use
- `ProjectStoreProtocolMock` - Generated, ready to use

### ⚠️ Still Using Manual Mocks
- `MockAudioService` - AudioService is a class, not a protocol
  - **Solution**: Consider creating `AudioServiceProtocol` and using Mockolo

### ✅ Updated Tests
- `StateMachineVerificationTests.swift` - Now uses `CameraServiceProtocolMock`

---

## 🎯 Best Practices

1. **Always use Mockolo-generated mocks** for protocols
2. **Don't create manual mocks** - generate them instead
3. **Update existing tests** to use generated mocks
4. **For classes**: Consider creating protocols if you need mocks

---

## 🔧 Migration Checklist

- [x] Generate mocks with Mockolo
- [x] Update `StateMachineVerificationTests` to use `CameraServiceProtocolMock`
- [ ] Update other tests that use manual mocks
- [ ] Consider creating `AudioServiceProtocol` for `MockAudioService`
- [ ] Update test templates to show Mockolo usage

---

**Key Point**: Mockolo generates mocks FOR you to use IN your tests. You still write the tests yourself, but use the generated mocks instead of creating them manually.

