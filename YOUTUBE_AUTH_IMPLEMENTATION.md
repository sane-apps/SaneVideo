# YouTube OAuth2 Authentication Implementation Plan

## Current Status
- ✅ UI for entering Client ID/Secret exists
- ✅ Keychain storage for credentials implemented
- ✅ Basic service structure exists
- ❌ OAuth2 flow not implemented (skeleton only)
- ❌ Redirect URI is placeholder
- ❌ Token refresh not implemented
- ❌ Actual upload API calls not implemented

## What's Needed

### 1. Google Cloud Console Setup

**Required Steps:**
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create/select a project
3. Enable "YouTube Data API v3"
4. Create OAuth 2.0 credentials:
   - Application type: **macOS** (or "Desktop app")
   - Authorized redirect URIs: `com.sanevideo.SaneVideo:/oauth2callback`
   - Download credentials JSON

### 2. Update Info.plist

**Add URL scheme for OAuth callback:**

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.sanevideo.SaneVideo</string>
        </array>
    </dict>
</array>
```

### 3. Implement OAuth2 Flow

**File: `SaneVideo/Services/Export/YouTubeService.swift`**

**Required Implementation:**

```swift
import AuthenticationServices

// 1. OAuth2 Authorization
func authenticate() async throws {
    let clientID = await APIKeyManager.shared.getYouTubeClientID()
    guard let clientID = clientID, !clientID.isEmpty else {
        throw YouTubeError.missingCredentials
    }
    
    let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=\(scopes.joined(separator: " "))")!
    
    // Use ASWebAuthenticationSession for OAuth
    let session = ASWebAuthenticationSession(
        url: authURL,
        callbackURLScheme: "com.sanevideo.SaneVideo"
    ) { callbackURL, error in
        // Handle callback
    }
    
    session.presentationContextProvider = self
    session.start()
}

// 2. Exchange Authorization Code for Tokens
func exchangeCodeForTokens(_ code: String) async throws {
    // POST to https://oauth2.googleapis.com/token
    // Get access_token and refresh_token
    // Store refresh_token in Keychain
}

// 3. Refresh Access Token
func refreshAccessToken() async throws {
    // Use refresh_token to get new access_token
    // Called automatically when access_token expires
}

// 4. Implement Actual Upload
func upload(videoURL: URL, title: String, description: String) async throws {
    // 1. Ensure authenticated (get/refresh token)
    // 2. Upload video metadata first
    // 3. Upload video file in chunks
    // 4. Monitor progress
}
```

### 4. Update Redirect URI

**File: `SaneVideo/Services/Export/YouTubeService.swift`**

Change:
```swift
private let redirectURI = "com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID:/oauth2callback"
```

To:
```swift
private let redirectURI = "com.sanevideo.SaneVideo:/oauth2callback"
```

**Or make it dynamic:**
```swift
private var redirectURI: String {
    "com.sanevideo.SaneVideo:/oauth2callback"
}
```

### 5. Handle OAuth Callback

**File: `SaneVideo/SaneVideoApp.swift`**

Add URL handling:
```swift
.onOpenURL { url in
    if url.scheme == "com.sanevideo.SaneVideo" {
        // Handle OAuth callback
        Task {
            await ServiceContainer.shared.youtubeService.handleOAuthCallback(url)
        }
    }
}
```

### 6. Implement Token Management

**Add to `YouTubeService`:**
- Store access_token (in-memory, expires quickly)
- Store refresh_token (in Keychain, long-lived)
- Auto-refresh when access_token expires
- Handle token expiration gracefully

### 7. Implement Upload API

**YouTube Data API v3 Upload Flow:**
1. **Resumable Upload Initiation:**
   - POST to `https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status`
   - Get upload URL

2. **Upload Video File:**
   - PUT to upload URL with video file
   - Monitor progress
   - Handle resumable upload (if interrupted)

3. **Error Handling:**
   - Network errors
   - Quota exceeded
   - Invalid credentials
   - File size limits

## Implementation Steps

### Phase 1: OAuth2 Setup (1-2 hours)
1. **Google Cloud Setup** (30 min)
   - Create project
   - Enable API
   - Create credentials
   - Configure redirect URI

2. **Info.plist Update** (5 min)
   - Add URL scheme

3. **Basic OAuth Flow** (45 min)
   - Implement `ASWebAuthenticationSession`
   - Handle callback
   - Exchange code for tokens
   - Store tokens

### Phase 2: Token Management (30 min)
1. **Token Refresh** (20 min)
   - Implement refresh logic
   - Auto-refresh on expiration
   - Error handling

2. **Token Storage** (10 min)
   - Verify Keychain integration
   - Test persistence

### Phase 3: Upload Implementation (2-3 hours)
1. **Resumable Upload** (1 hour)
   - Implement upload initiation
   - Handle chunked upload
   - Progress tracking

2. **Error Handling** (30 min)
   - Network retries
   - Quota handling
   - User-friendly errors

3. **Testing** (1 hour)
   - Test full flow
   - Test error cases
   - Test token refresh

## Files to Modify

1. **`SaneVideo/Services/Export/YouTubeService.swift`**
   - Implement OAuth2 flow
   - Implement upload API
   - Add token management

2. **`SaneVideo/Info.plist`**
   - Add URL scheme

3. **`SaneVideo/SaneVideoApp.swift`**
   - Add URL handling

4. **`SaneVideo/Services/Security/APIKeyManager.swift`**
   - Verify token storage methods

## Testing Checklist

- [ ] OAuth2 flow completes successfully
- [ ] Tokens stored in Keychain
- [ ] Token refresh works
- [ ] Upload completes successfully
- [ ] Progress tracking works
- [ ] Error handling works
- [ ] Works after app restart (token persistence)

## Estimated Time: 4-6 hours

## Dependencies
- Google Cloud Console account
- YouTube Data API v3 enabled
- OAuth 2.0 credentials configured
- Network access for API calls

## Security Considerations
- ✅ Credentials stored in Keychain (secure)
- ✅ Tokens stored in Keychain (secure)
- ⚠️ OAuth flow must use secure redirect
- ⚠️ Validate all API responses
- ⚠️ Handle token expiration gracefully

