# VoiceGuardian - Complete Documentation

## Table of Contents

1. [Overview](#overview)
2. [Technology Stack](#technology-stack)
3. [Architecture Overview](#architecture-overview)
4. [User Journey & Flow](#user-journey--flow)
5. [Frontend (Flutter App) - Detailed](#frontend-flutter-app---detailed)
6. [Backend (FastAPI) - Detailed](#backend-fastapi---detailed)
7. [Database Schema](#database-schema)
8. [Real-time Features](#real-time-features)
9. [Setup & Installation](#setup--installation)

---

## Overview

**VoiceGuardian** is a mobile application that provides real-time voice call coaching using AI-powered transcription and toxicity detection. The app monitors conversations during calls and provides polite suggestions when inappropriate language is detected, helping users maintain respectful communication.

### Core Features

- 🔐 User authentication (register/login)
- 👥 Friend management system
- 📞 Real-time voice calls via Agora RTC
- 🎤 Live transcription during calls
- 🤖 AI-powered toxicity detection
- 🔊 Real-time voice coaching
- 📊 Respectfulness scoring
- 📱 Push notifications for incoming calls
- 📜 Call history tracking

---

## Technology Stack

### Frontend (Mobile App)

- **Framework**: Flutter 3.9+ (Dart)
- **State Management**: Provider
- **Authentication**: JWT tokens + Firebase Auth
- **Push Notifications**: Firebase Cloud Messaging (FCM)
- **Real-time Voice**: Agora RTC Engine 6.3.2
- **HTTP Client**: http package
- **WebSocket**: web_socket_channel
- **Storage**: SharedPreferences (local token storage)

### Backend (API Server)

- **Framework**: FastAPI (Python 3.11+)
- **Database**: SQLite (dev) / PostgreSQL (production capable)
- **ORM**: SQLModel (SQLAlchemy)
- **Authentication**: JWT (OAuth2)
- **Migrations**: Alembic
- **Push Notifications**: Firebase Admin SDK
- **Voice Infrastructure**: Agora RTC
- **Speech-to-Text**: Google Cloud Speech API
- **AI Services**:
  - Perspective API (toxicity detection)
  - Groq LLM (polite rephrasing)
  - TTS for coaching audio

### Infrastructure

- **Database**: SQLite (voiceguardian.db)
- **Real-time Protocol**: WebSocket (transcription)
- **API Protocol**: REST (HTTP/HTTPS)

---

## Architecture Overview

```
┌─────────────────┐         ┌──────────────────┐
│  Flutter App    │◄───────►│  FastAPI Backend │
│  (Mobile)       │   REST  │  (Python)        │
└────────┬────────┘         └─────────┬────────┘
         │                            │
         │                            │
    ┌────▼─────┐                 ┌────▼────┐
    │  Agora   │                 │ SQLite  │
    │  RTC     │                 │   DB    │
    └──────────┘                 └─────────┘
         │
         │
    ┌────▼──────────┐       ┌──────────────┐
    │  WebSocket    │       │   Firebase   │
    │  (Trans.)     │       │     FCM      │
    └───────────────┘       └──────────────┘
         │
    ┌────▼────────┐
    │  Google     │
    │  Speech API │
    └─────────────┘
         │
    ┌────▼────────┐
    │ Perspective │
    │   + Groq    │
    └─────────────┘
```

---

## User Journey & Flow

### 1. App Download & First Launch

**User Action**: Downloads and opens the app

**What Happens**:

1. App starts at `main.dart`
2. Firebase is initialized
3. `AuthWrapper` checks for stored JWT token
4. If no token → shows `LoginScreen`

**Files Involved**:

- `lib/main.dart` - App initialization
- `lib/screens/auth_wrapper.dart` - Route decision
- `lib/providers/auth_provider.dart` - Token management

### 2. User Registration

**User Action**: Taps "Register" and fills form

**Frontend Flow** (`lib/screens/register_screen.dart`):

```dart
// User fills: username, phone, password
_usernameController.text    // e.g., "john_doe"
_phoneController.text       // e.g., "+919876543210"
_passwordController.text    // e.g., "securePass123"

// Calls AuthProvider
await Provider.of<AuthProvider>(context).register(
  username, phone, password
);
```

**Backend Flow** (`app/api/v1/endpoints/users.py`):

```python
@router.post("/register")
def register_new_user(user_in: schemas.UserCreate):
    # Check if username exists
    if crud.get_user_by_username(db, username):
        raise HTTPException(400, "User exists")

    # Create user with hashed password
    user = crud.create_user(db, user_in)
    return user  # Returns UserRead schema
```

**Database Changes**:

```sql
INSERT INTO user (username, phone_number, hashed_password, respectfulness_score)
VALUES ('john_doe', '+919876543210', 'hashed...', 100.0);
```

**Auto-Login**: After registration, app automatically logs in the user.

### 3. User Login

**User Action**: Enters credentials and taps "Login"

**Frontend Flow** (`lib/screens/login_screen.dart`):

```dart
await Provider.of<AuthProvider>(context).login(
  _usernameController.text,  // "john_doe"
  _passwordController.text   // "securePass123"
);
```

**API Call** (`lib/services/api_service.dart`):

```dart
Future<Map<String, dynamic>> loginUser({
  required String username,
  required String password,
}) async {
  final url = Uri.parse('${Constants.baseUrl}/auth/token');

  final response = await http.post(
    url,
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: {
      "username": username,
      "password": password,
    },
  );
  return _handleResponse(response);
}
```

**Backend Flow** (`app/api/v1/endpoints/auth.py`):

```python
@router.post("/token")
def login_for_access_token(form_data: OAuth2PasswordRequestForm):
    # Authenticate user
    user = crud.authenticate_user(db, form_data.username, form_data.password)

    if not user:
        raise HTTPException(401, "Incorrect credentials")

    # Create JWT token
    access_token = create_access_token(
        data={"sub": user.username}
    )

    return {"access_token": access_token, "token_type": "bearer"}
```

**Token Storage** (`lib/providers/auth_provider.dart`):

```dart
Future<void> _saveToken(String token, String username) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('token', token);
  await prefs.setString('username', username);
  _token = token;

  // Register FCM token
  await _registerDeviceToken();
  notifyListeners();  // Triggers UI update → shows MainShell
}
```

**FCM Registration**:

```dart
Future<void> _registerDeviceToken() async {
  String? fcmToken = await _fcmService.getFcmToken();

  await _apiService.registerDeviceToken(
    token: authToken,  // JWT
    fcmToken: fcmToken // Firebase token
  );
}
```

**Backend Updates User**:

```python
@router.post("/register_device")
def register_device_token(
    current_user: User,
    device_in: DeviceRegister
):
    current_user.fcm_token = device_in.fcm_token
    db.commit()
    return {"message": "FCM token registered"}
```

**Result**: User is now logged in and sees the main app interface.

### 4. Main App Interface

**UI** (`lib/screens/main_shell.dart`):

Bottom navigation with 4 tabs:

- 🏠 **Home** - Friends list & call buttons
- 📜 **History** - Past calls
- 👥 **Friends** - Manage friend requests
- 👤 **Profile** - User info & respectfulness score

### 5. Adding Friends

**User Action**: Goes to Friends tab, enters friend's username

**Frontend** (`lib/screens/friends_screen.dart`):

```dart
await _apiService.sendFriendRequest(
  token: auth.token,
  username: "jane_smith"
);
```

**Backend** (`app/api/v1/endpoints/friends.py`):

```python
@router.post("/request")
def send_friend_request(
    current_user: User,
    payload: FriendRequestCreate
):
    addressee = crud.get_user_by_username(db, payload.username)

    # Create friendship record with status="pending"
    friendship = crud.create_friendship(
        db, current_user, addressee
    )
    return friendship
```

**Database**:

```sql
INSERT INTO friendship (requester_id, addressee_id, status)
VALUES (1, 2, 'pending');
```

**Friend Accepting Request**:

```dart
await _apiService.acceptFriendRequest(
  token: auth.token,
  friendshipId: 123
);
```

**Backend Updates**:

```python
@router.put("/accept")
def accept_friend_request(payload: FriendRequestUpdate):
    friendship = crud.get_friendship_by_id(db, payload.friendship_id)
    friendship.status = "accepted"
    db.commit()
```

### 6. Making a Voice Call

**User Action**: Taps call icon next to friend's name

**Frontend Flow** (`lib/screens/home_screen.dart`):

**Step 1: Initiate Call**

```dart
Future<void> _startCall(String friendUsername) async {
  // 1. Backend creates call record & notifies callee
  final response = await _apiService.initiateCall(
    token: authProvider.token,
    calleeUsername: "jane_smith"
  );

  final roomName = response['room_name'];  // "room_a1b2c3d4e5f6"
```

**Backend** (`app/api/v1/endpoints/calls.py`):

```python
@router.post("/initiate")
def initiate_call(
    current_user: User,
    payload: CallInitiate
):
    callee = crud.get_user_by_username(db, payload.callee_username)

    # Generate unique room
    room_name = f"room_{uuid.uuid4().hex[:12]}"

    # Create call record
    call_record = crud.create_call_record(
        db, caller=current_user, callee=callee, room_name=room_name
    )

    # Send push notification
    send_fcm_notification(
        token=callee.fcm_token,
        title=f"Incoming call from {current_user.username}",
        data={
            "type": "incoming_call",
            "room_name": room_name,
            "caller_name": current_user.username,
            "caller_respectfulness": str(current_user.respectfulness_score)
        }
    )

    return {"room_name": room_name}
```

**Database**:

```sql
INSERT INTO call_record
  (room_name, caller_id, callee_id, status, started_at)
VALUES
  ('room_a1b2c3d4e5f6', 1, 2, 'ringing', NOW());
```

**Step 2: Get Agora Token**

```dart
  // 2. Get Agora RTC token
  final uid = authProvider.username.hashCode.abs();  // Deterministic UID

  final tokenResponse = await _apiService.getAgoraToken(
    token: authProvider.token,
    channelName: roomName,
    uid: uid
  );

  final agoraToken = tokenResponse['token'];
```

**Backend Generates Agora Token**:

```python
@router.get("/agora_token")
def get_agora_token(channel_name: str, uid: int):
    token = RtcTokenBuilder.buildTokenWithUid(
        app_id=settings.AGORA_APP_ID,
        app_certificate=settings.AGORA_APP_CERTIFICATE,
        channel_name=channel_name,
        uid=uid,
        role=1,  # Publisher
        privilege_expired_ts=time.time() + 3600
    )

    return {"token": token, "channel_name": channel_name}
```

**Step 3: Navigate to Call Screen**

```dart
  // 3. Open call screen
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => CallScreen(
        channelName: roomName,
        peerUsername: "jane_smith",
        agoraToken: agoraToken,
        uid: uid,
        isIncoming: false,
      ),
    ),
  );
}
```

### 7. Receiving a Call

**Callee Device**: FCM notification arrives

**FCM Handler** (`lib/main.dart`):

```dart
void _showIncomingCallScreen(RemoteMessage message) {
  final data = message.data;

  if (data['type'] == 'incoming_call') {
    final roomName = data['room_name'];
    final callerName = data['caller_name'];
    final respectfulness = data['caller_respectfulness'];

    // Navigate to incoming call screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IncomingCallScreen(
          roomName: roomName,
          callerName: callerName,
          callerRespectfulness: respectfulness,
        ),
      ),
    );
  }
}
```

**Incoming Call UI** (`lib/screens/incoming_call_screen.dart`):

- Shows caller's name
- Shows respectfulness score
- Accept or Decline buttons

**If User Accepts**:

```dart
Future<void> _acceptCall() async {
  // Get Agora token
  final response = await _apiService.getAgoraToken(
    token: auth.token,
    channelName: widget.roomName,
    uid: auth.username.hashCode.abs(),
  );

  // Join call screen
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => CallScreen(
        channelName: widget.roomName,
        peerUsername: widget.callerName,
        agoraToken: response['token'],
        uid: auth.username.hashCode.abs(),
        isIncoming: true,
      ),
    ),
  );
}
```

### 8. Active Call with Real-time Features

**Call Screen Initialization** (`lib/screens/call_screen.dart`):

**Step 1: Join Agora Channel**

```dart
@override
void initState() {
  super.initState();
  _agoraService = Provider.of<AgoraCallService>(context, listen: false);
  _transcriptionService = Provider.of<TranscriptionService>(context, listen: false);

  // Set up coaching callback
  _transcriptionService.onRephrase = (original, rephrased, toxicity) async {
    // Request TTS audio
    final resp = await _apiService.synthesizeTts(
      token: _authProvider.token,
      text: rephrased,
    );

    // Play coaching audio
    await _agoraService.playCoachAudioBase64(resp['audio_mp3_base64']);
  };

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _joinChannel();
  });
}
```

**Step 2: Join Channel** (`lib/services/agora_call_service.dart`):

```dart
Future<void> joinChannel({
  required String token,
  required String channelName,
  required int uid,
  String? username,
}) async {
  // Connect transcription WebSocket
  if (_transcriptionService != null && username != null) {
    await _transcriptionService.connect(
      channelName: channelName,
      username: username,
    );
    _isTranscribing = true;
  }

  // Join Agora RTC channel
  await _engine.joinChannel(
    token: token,
    channelId: channelName,
    uid: uid,
    options: ChannelMediaOptions(
      channelProfile: ChannelProfileType.channelProfileCommunication,
      clientRoleType: ClientRoleType.clientRoleBroadcaster,
      autoSubscribeAudio: true,
      publishMicrophoneTrack: true,
    ),
  );
}
```

**Step 3: Audio Streaming** (`lib/services/transcription_service.dart`):

**WebSocket Connection**:

```dart
Future<void> connect({
  required String channelName,
  required String username,
}) async {
  // Connect to backend WebSocket
  final wsUrl = 'wss://your-backend/api/v1/calls/transcribe_audio';
  _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

  // Send start message
  _channel.sink.add(jsonEncode({
    'type': 'start',
    'channel_name': channelName,
    'username': username,
  }));

  // Listen for responses
  _channel.stream.listen((message) {
    _handleMessage(message);
  });
}
```

**Audio Frame Capture** (`lib/services/agora_call_service.dart`):

```dart
// Agora captures audio frames
AudioFrameObserver(
  onMixedAudioFrame: (channelId, audioFrame) {
    final data = audioFrame.buffer;  // PCM audio data
    _handleAudioFrame(data);
  },
)

void _handleAudioFrame(Uint8List buffer) {
  if (_isTranscribing && _transcriptionService.isConnected) {
    _transcriptionService.sendAudio(buffer);
  }
}
```

**Send to Backend**:

```dart
void sendAudio(Uint8List audioData) {
  final base64Audio = base64Encode(audioData);

  _channel.sink.add(jsonEncode({
    'type': 'audio',
    'data': base64Audio,
  }));
}
```

**Backend Transcription** (`app/api/v1/endpoints/calls.py`):

```python
@router.websocket("/transcribe_audio")
async def transcribe_audio_websocket(websocket: WebSocket):
    await websocket.accept()

    # Initialize Google Speech client
    streaming_config = speech.StreamingRecognitionConfig(
        config=speech.RecognitionConfig(
            encoding=speech.RecognitionConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=16000,
            language_code="en-US",
        ),
        interim_results=True,
    )

    async def audio_generator():
        while True:
            message = await websocket.receive_text()
            data = json.loads(message)

            if data['type'] == 'audio':
                # Decode base64 audio
                audio_bytes = base64.b64decode(data['data'])
                yield speech.StreamingRecognizeRequest(audio_content=audio_bytes)

    # Stream to Google Speech
    responses = _speech_client.streaming_recognize(
        config=streaming_config,
        requests=audio_generator(),
    )

    async for response in responses:
        for result in response.results:
            if result.is_final:
                transcript = result.alternatives[0].transcript

                # Send transcript
                await websocket.send_json({
                    "type": "transcript",
                    "text": transcript
                })

                # Check toxicity
                toxicity_score = await get_toxicity_score(transcript)

                if toxicity_score > PERSPECTIVE_THRESHOLD:
                    # Get polite rephrase
                    rephrased = await get_polite_rephrase(transcript)

                    # Send rephrase suggestion
                    await websocket.send_json({
                        "type": "rephrase",
                        "original": transcript,
                        "rephrased": rephrased,
                        "toxicity_score": toxicity_score
                    })
```

**Frontend Receives Rephrase**:

```dart
void _handleMessage(dynamic message) {
  final data = jsonDecode(message);

  switch (data['type']) {
    case 'rephrase':
      if (onRephrase != null) {
        onRephrase!(
          data['original'],
          data['rephrased'],
          data['toxicity_score']
        );
      }
      break;
  }
}
```

**Play Coaching Audio**:

```dart
// Triggered in CallScreen
_transcriptionService.onRephrase = (original, rephrased, toxicity) async {
  // Get TTS audio from backend
  final resp = await _apiService.synthesizeTts(
    token: _authProvider.token,
    text: rephrased,  // "Perhaps you could say: 'I respectfully disagree'"
  );

  // Play audio through Agora audio mixing
  await _agoraService.playCoachAudioBase64(resp['audio_mp3_base64']);
};
```

### 9. Ending a Call

**User Action**: Taps "End Call" button

```dart
Future<void> _endCall() async {
  // Leave Agora channel
  await _agoraService.leaveChannel();

  // Calculate duration
  final duration = DateTime.now().difference(_connectedAt).inSeconds;

  // Report to backend
  await _apiService.completeCall(
    token: _authProvider.token,
    roomName: widget.channelName,
    durationSeconds: duration,
    endedBy: _authProvider.username,
  );

  _callStateService.reset();
  Navigator.pop(context);
}
```

**Backend Updates** (`app/api/v1/endpoints/calls.py`):

```python
@router.post("/complete")
def complete_call(
    current_user: User,
    payload: CallComplete
):
    call_record = crud.get_call_record_by_room(db, payload.room_name)

    call_record.status = "completed"
    call_record.ended_at = datetime.utcnow()
    call_record.duration_seconds = payload.duration_seconds
    call_record.ended_by = payload.ended_by

    db.commit()
    return {"message": "Call completed"}
```

**Database**:

```sql
UPDATE call_record
SET status = 'completed',
    ended_at = NOW(),
    duration_seconds = 245,
    ended_by = 'john_doe'
WHERE room_name = 'room_a1b2c3d4e5f6';
```

---

## Frontend (Flutter App) - Detailed

### Directory Structure

```
lib/
├── main.dart                    # App entry point
├── firebase_options.dart        # Firebase config
├── providers/
│   └── auth_provider.dart       # Authentication state
├── services/
│   ├── api_service.dart         # HTTP API calls
│   ├── agora_call_service.dart  # Agora RTC management
│   ├── transcription_service.dart # WebSocket transcription
│   ├── call_state_service.dart  # Call lifecycle tracking
│   └── fcm_service.dart         # Push notifications
├── screens/
│   ├── auth_wrapper.dart        # Login/Main routing
│   ├── login_screen.dart        # Login UI
│   ├── register_screen.dart     # Registration UI
│   ├── main_shell.dart          # Bottom nav container
│   ├── home_screen.dart         # Friends list
│   ├── incoming_call_screen.dart # Incoming call UI
│   ├── call_screen.dart         # Active call UI
│   ├── history_screen.dart      # Call history
│   ├── friends_screen.dart      # Friend management
│   └── profile_screen.dart      # User profile
└── utils/
    └── constants.dart           # API URL, Agora App ID
```

### Key Files Explained

#### `lib/main.dart`

**Purpose**: App initialization and FCM setup

**Key Code**:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform
  );

  // Set up FCM handlers
  FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize Agora
  final agoraService = AgoraCallService();
  await agoraService.initialize(Constants.agoraAppId);

  runApp(MyApp(agoraService: agoraService));
}
```

**Provides**:

- Global navigation key for push notifications
- FCM message handlers
- Provider setup for state management

#### `lib/providers/auth_provider.dart`

**Purpose**: Manages authentication state

**Key Features**:

- Stores JWT token in SharedPreferences
- Auto-loads token on app start
- Registers FCM token with backend
- Provides `isLoggedIn` status

**Important Methods**:

```dart
// Login
Future<void> login(String username, String password) async {
  final response = await _apiService.loginUser(...);
  await _saveToken(response['access_token'], username);
}

// Register
Future<void> register(String username, String phone, String password) async {
  await _apiService.registerUser(...);
  await login(username, password);  // Auto-login
}

// Logout
Future<void> logout() async {
  await prefs.remove('token');
  _token = null;
  notifyListeners();  // Triggers UI update
}
```

#### `lib/services/api_service.dart`

**Purpose**: All HTTP API calls

**Base URL**: Configured in `constants.dart`

```dart
static const String baseUrl = "https://your-backend/api/v1";
```

**Key Methods**:

- `registerUser()` - POST /users/register
- `loginUser()` - POST /auth/token
- `registerDeviceToken()` - POST /users/register_device
- `getFriends()` - GET /friends/list
- `sendFriendRequest()` - POST /friends/request
- `initiateCall()` - POST /calls/initiate
- `getAgoraToken()` - GET /calls/agora_token
- `completeCall()` - POST /calls/complete
- `getCallHistory()` - GET /calls/history

#### `lib/services/agora_call_service.dart`

**Purpose**: Manages Agora RTC engine

**Key Features**:

- Initializes Agora RTC engine
- Joins/leaves channels
- Captures audio frames for transcription
- Plays coaching audio via audio mixing
- Mute/speaker controls

**Audio Frame Capture**:

```dart
AudioFrameObserver(
  onMixedAudioFrame: (channelId, audioFrame) {
    _handleAudioFrame(audioFrame.buffer);
  },
)

void _handleAudioFrame(Uint8List buffer) {
  if (_isTranscribing) {
    _transcriptionService.sendAudio(buffer);
  }
}
```

#### `lib/services/transcription_service.dart`

**Purpose**: WebSocket communication for transcription

**Flow**:

1. Connect to WebSocket
2. Send start message
3. Stream audio data (base64 encoded)
4. Receive transcript/rephrase messages

**Message Types**:

- **Sent**: `start`, `audio`, `stop`
- **Received**: `ready`, `transcript`, `rephrase`, `interim`, `error`

#### `lib/screens/call_screen.dart`

**Purpose**: Active call interface

**Features**:

- Shows peer name and status
- Call timer
- Mute/Unmute button
- Speaker toggle
- End call button
- Handles coaching audio playback

**Coaching Flow**:

```dart
_transcriptionService.onRephrase = (original, rephrased, toxicity) async {
  // Get TTS
  final resp = await _apiService.synthesizeTts(
    token: _authProvider.token,
    text: rephrased,
  );

  // Play audio
  await _agoraService.playCoachAudioBase64(resp['audio_mp3_base64']);
};
```

---

## Backend (FastAPI) - Detailed

### Directory Structure

```
app/
├── main.py                      # FastAPI app initialization
├── db.py                        # Database connection
├── models.py                    # SQLModel database models
├── schemas.py                   # Pydantic request/response models
├── crud.py                      # Database operations
├── deps.py                      # Dependency injection
├── core/
│   ├── config.py                # Environment settings
│   ├── security.py              # JWT & password hashing
│   ├── fcm.py                   # Firebase Admin SDK
│   └── ai_services.py           # Perspective + Groq
└── api/
    └── v1/
        ├── api.py               # Router aggregation
        └── endpoints/
            ├── auth.py          # Login endpoint
            ├── users.py         # User registration
            ├── friends.py       # Friend management
            └── calls.py         # Call endpoints + WebSocket
```

### Key Files Explained

#### `app/main.py`

**Purpose**: FastAPI application setup

```python
app = FastAPI(
    title="VoiceGuardian API",
    version="0.1.0"
)

@app.on_event("startup")
def _startup():
    create_db_and_tables()  # Create SQLite tables

# Include routers
app.include_router(api_router, prefix="/api/v1")
```

#### `app/models.py`

**Purpose**: Database table definitions

**User Model**:

```python
class User(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    username: str = Field(index=True, unique=True)
    phone_number: str = Field(index=True, unique=True)
    hashed_password: str
    respectfulness_score: float = Field(default=100.0)
    respectfulness_samples: int = Field(default=0)
    fcm_token: Optional[str] = Field(default=None)
```

**Friendship Model**:

```python
class Friendship(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    requester_id: int = Field(foreign_key="user.id")
    addressee_id: int = Field(foreign_key="user.id")
    status: str = Field(default="pending")  # "pending" | "accepted"
```

**CallRecord Model**:

```python
class CallRecord(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    room_name: str = Field(index=True, unique=True)
    caller_id: int = Field(foreign_key="user.id")
    callee_id: int = Field(foreign_key="user.id")
    status: str = Field(default="ringing")  # "ringing" | "connected" | "completed"
    started_at: datetime = Field(default_factory=datetime.utcnow)
    ended_at: Optional[datetime] = None
    duration_seconds: Optional[int] = None
    ended_by: Optional[str] = None
```

#### `app/api/v1/endpoints/auth.py`

**Purpose**: User login

```python
@router.post("/token", response_model=schemas.Token)
def login_for_access_token(
    db: Session = Depends(get_session),
    form_data: OAuth2PasswordRequestForm = Depends()
):
    user = crud.authenticate_user(db, form_data.username, form_data.password)

    if not user:
        raise HTTPException(401, "Incorrect credentials")

    access_token = create_access_token(data={"sub": user.username})

    return {"access_token": access_token, "token_type": "bearer"}
```

#### `app/api/v1/endpoints/calls.py`

**Purpose**: Call management and transcription

**Key Endpoints**:

**1. Get Agora Token**:

```python
@router.get("/agora_token")
def get_agora_token(
    current_user: User = Depends(get_current_user),
    channel_name: str = Query(...),
    uid: int = Query(...)
):
    token = RtcTokenBuilder.buildTokenWithUid(
        app_id=settings.AGORA_APP_ID,
        app_certificate=settings.AGORA_APP_CERTIFICATE,
        channel_name=channel_name,
        uid=uid,
        role=1,
        privilege_expired_ts=time.time() + 3600
    )

    return {"token": token}
```

**2. Initiate Call**:

```python
@router.post("/initiate")
def initiate_call(
    db: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
    payload: CallInitiate
):
    callee = crud.get_user_by_username(db, payload.callee_username)
    room_name = f"room_{uuid.uuid4().hex[:12]}"

    # Create call record
    call_record = crud.create_call_record(
        db, caller=current_user, callee=callee, room_name=room_name
    )

    # Send FCM push
    send_fcm_notification(
        token=callee.fcm_token,
        title=f"Incoming call from {current_user.username}",
        data={
            "type": "incoming_call",
            "room_name": room_name,
            "caller_name": current_user.username,
        }
    )

    return {"room_name": room_name}
```

**3. WebSocket Transcription**:

```python
@router.websocket("/transcribe_audio")
async def transcribe_audio_websocket(websocket: WebSocket):
    await websocket.accept()

    # Google Speech client
    streaming_config = speech.StreamingRecognitionConfig(...)

    # Stream audio to Google Speech
    async for response in speech_client.streaming_recognize(...):
        for result in response.results:
            if result.is_final:
                transcript = result.alternatives[0].transcript

                # Send transcript
                await websocket.send_json({
                    "type": "transcript",
                    "text": transcript
                })

                # Check toxicity
                toxicity_score = await get_toxicity_score(transcript)

                if toxicity_score > PERSPECTIVE_THRESHOLD:
                    rephrased = await get_polite_rephrase(transcript)

                    await websocket.send_json({
                        "type": "rephrase",
                        "original": transcript,
                        "rephrased": rephrased,
                        "toxicity_score": toxicity_score
                    })
```

#### `app/core/ai_services.py`

**Purpose**: AI integrations

**Toxicity Detection** (Perspective API):

```python
async def get_toxicity_score(text: str) -> float:
    response = await client.post(
        "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze",
        params={"key": settings.PERSPECTIVE_API_KEY},
        json={
            "comment": {"text": text},
            "requestedAttributes": {"TOXICITY": {}}
        }
    )

    score = response.json()["attributeScores"]["TOXICITY"]["summaryScore"]["value"]
    return score
```

**Polite Rephrasing** (Groq LLM):

```python
async def get_polite_rephrase(toxic_text: str) -> str:
    response = await client.post(
        "https://api.groq.com/openai/v1/chat/completions",
        headers={"Authorization": f"Bearer {settings.GROQ_API_KEY}"},
        json={
            "model": "llama3-8b-8192",
            "messages": [{
                "role": "system",
                "content": "Rephrase toxic speech into polite alternatives."
            }, {
                "role": "user",
                "content": toxic_text
            }]
        }
    )

    return response.json()["choices"][0]["message"]["content"]
```

---

## Database Schema

### SQLite Database: `voiceguardian.db`

**Tables**:

#### 1. `user`

| Column                 | Type    | Description           |
| ---------------------- | ------- | --------------------- |
| id                     | INTEGER | Primary key           |
| username               | TEXT    | Unique username       |
| phone_number           | TEXT    | Unique phone          |
| hashed_password        | TEXT    | Bcrypt hash           |
| respectfulness_score   | REAL    | 0-100 score           |
| respectfulness_samples | INTEGER | Number of samples     |
| fcm_token              | TEXT    | Firebase device token |

#### 2. `friendship`

| Column       | Type    | Description             |
| ------------ | ------- | ----------------------- |
| id           | INTEGER | Primary key             |
| requester_id | INTEGER | FK to user.id           |
| addressee_id | INTEGER | FK to user.id           |
| status       | TEXT    | "pending" or "accepted" |

**Unique Constraint**: (requester_id, addressee_id)

#### 3. `call_record`

| Column           | Type     | Description                         |
| ---------------- | -------- | ----------------------------------- |
| id               | INTEGER  | Primary key                         |
| room_name        | TEXT     | Agora channel name                  |
| caller_id        | INTEGER  | FK to user.id                       |
| callee_id        | INTEGER  | FK to user.id                       |
| status           | TEXT     | "ringing", "connected", "completed" |
| started_at       | DATETIME | Call start time                     |
| ended_at         | DATETIME | Call end time                       |
| duration_seconds | INTEGER  | Call duration                       |
| ended_by         | TEXT     | Username who ended call             |

---

## Real-time Features

### 1. Push Notifications (Firebase Cloud Messaging)

**Flow**:

1. App requests FCM token on login
2. Token stored in user record
3. When call initiated, backend sends FCM notification
4. App receives notification and shows incoming call UI

**Notification Types**:

- `incoming_call` - New call
- `call_cancelled` - Caller cancelled
- `call_declined` - Callee declined

### 2. Voice Calls (Agora RTC)

**Architecture**:

- Agora acts as SFU (Selective Forwarding Unit)
- Clients connect directly to Agora servers
- Backend only generates access tokens

**Audio Flow**:

1. User A joins channel "room_abc"
2. User B joins same channel
3. Agora relays audio between them
4. Each client captures mixed audio for transcription

### 3. Transcription (WebSocket + Google Speech)

**Flow**:

```
Flutter App → WebSocket → FastAPI → Google Speech
                ↓
         Perspective API
                ↓
            Groq LLM
                ↓
         WebSocket Response → Flutter → Agora Audio Mixing
```

**Message Types**:

- Client → Server: `start`, `audio`, `stop`
- Server → Client: `transcript`, `rephrase`, `interim`

---

## Setup & Installation

### Prerequisites

1. Python 3.11+
2. Flutter 3.9+
3. Firebase project (FCM enabled)
4. Agora account (App ID + Certificate)
5. Google Cloud (Speech-to-Text API)
6. Perspective API key
7. Groq API key

### Backend Setup

**1. Clone & Install**:

```bash
cd voiceguardian
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

**2. Environment Variables** (`.env`):

```env
DATABASE_URL=sqlite:///./voiceguardian.db
SECRET_KEY=your-secret-key
FIREBASE_SERVICE_ACCOUNT_KEY=/path/to/firebase-service-account.json
GOOGLE_APPLICATION_CREDENTIALS=/path/to/google-stt.json
PERSPECTIVE_API_KEY=AIzaSy...
GROQ_API_KEY=gsk_...
AGORA_APP_ID=91496d74...
AGORA_APP_CERTIFICATE=627dcefb...
```

**3. Database Setup**:

```bash
alembic upgrade head
```

**4. Run Server**:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

API Docs: http://localhost:8000/docs

### Frontend Setup

**1. Install Flutter** (3.9+)

**2. Clone & Install**:

```bash
cd voiceguardian_app
flutter pub get
```

**3. Configure Firebase**:

```bash
flutterfire configure
```

This generates `lib/firebase_options.dart`

**4. Update Constants** (`lib/utils/constants.dart`):

```dart
class Constants {
  // For Android emulator: use 10.0.2.2
  static const String baseUrl = "http://10.0.2.2:8000/api/v1";

  static const String agoraAppId = "your-agora-app-id";
}
```

**5. Run App**:

```bash
flutter run
```

---

## Environment Configuration

### Backend Environment Variables

| Variable                         | Purpose                | Example                        |
| -------------------------------- | ---------------------- | ------------------------------ |
| `DATABASE_URL`                   | Database connection    | `sqlite:///./voiceguardian.db` |
| `SECRET_KEY`                     | JWT signing            | `your-secret-key-here`         |
| `FIREBASE_SERVICE_ACCOUNT_KEY`   | Firebase Admin         | `/path/to/firebase.json`       |
| `GOOGLE_APPLICATION_CREDENTIALS` | Google Speech          | `/path/to/google-stt.json`     |
| `PERSPECTIVE_API_KEY`            | Toxicity detection     | `AIzaSy...`                    |
| `GROQ_API_KEY`                   | LLM rephrasing         | `gsk_...`                      |
| `AGORA_APP_ID`                   | Agora RTC              | `91496d74...`                  |
| `AGORA_APP_CERTIFICATE`          | Agora token generation | `627dcefb...`                  |

### Frontend Configuration

**`lib/utils/constants.dart`**:

```dart
class Constants {
  // Production
  static const String baseUrl = "https://your-backend/api/v1";

  // Development (Android Emulator)
  // static const String baseUrl = "http://10.0.2.2:8000/api/v1";

  // Development (iOS Simulator)
  // static const String baseUrl = "http://localhost:8000/api/v1";

  static const String agoraAppId = "91496d742dca43e596046340b9e4b4ad";
}
```

---

## Common Workflows

### User Registration → First Call

1. User downloads app
2. Taps "Register"
3. Enters username, phone, password
4. Backend creates user with score=100.0
5. Auto-login returns JWT token
6. FCM token registered
7. User adds friend
8. Friend accepts
9. User taps call icon
10. Backend sends FCM to friend
11. Friend accepts
12. Both join Agora channel
13. Real-time transcription starts
14. If toxic speech detected:
    - Perspective API scores it
    - Groq LLM rephrases
    - TTS audio plays
15. Call ends, duration saved

---

## API Endpoints Summary

### Authentication

- `POST /api/v1/auth/token` - Login
- `POST /api/v1/users/register` - Register
- `POST /api/v1/users/register_device` - Register FCM token
- `GET /api/v1/users/me` - Get profile

### Friends

- `GET /api/v1/friends/list` - Get friends
- `GET /api/v1/friends/pending` - Get pending requests
- `POST /api/v1/friends/request` - Send request
- `PUT /api/v1/friends/accept` - Accept request

### Calls

- `POST /api/v1/calls/initiate` - Start call
- `GET /api/v1/calls/agora_token` - Get RTC token
- `POST /api/v1/calls/accept` - Accept call
- `POST /api/v1/calls/decline` - Decline call
- `POST /api/v1/calls/cancel` - Cancel call
- `POST /api/v1/calls/complete` - End call
- `GET /api/v1/calls/history` - Get history
- `POST /api/v1/calls/tts` - Synthesize coaching audio
- `WebSocket /api/v1/calls/transcribe_audio` - Live transcription

---

## Technologies Deep Dive

### JWT Authentication

- Tokens expire in 7 days (configurable)
- Stored in SharedPreferences on device
- Sent as Bearer token in Authorization header

### Agora RTC

- Channel = virtual room
- UID = unique user identifier
- Token = time-limited access credential
- Audio mixing = playing coach audio during call

### Google Speech-to-Text

- Streaming recognition (real-time)
- LINEAR16 encoding, 16kHz sample rate
- Interim results for live feedback
- Final results for toxicity check

### Perspective API

- Google Jigsaw toxicity scoring
- Returns 0-1 score (higher = more toxic)
- Threshold configurable (default 0.7)

### Groq LLM

- LLaMA 3 8B model
- Fast inference (<2s)
- Generates polite alternatives

---

## Troubleshooting

### Common Issues

**1. "Network error" on login**

- Check `Constants.baseUrl` is correct
- For Android emulator, use `10.0.2.2` not `localhost`
- Ensure backend is running

**2. "FCM token not registered"**

- Check Firebase config
- Verify `google-services.json` (Android) or `GoogleService-Info.plist` (iOS)
- Re-run `flutterfire configure`

**3. "Failed to join channel"**

- Verify Agora App ID in `constants.dart`
- Check backend Agora credentials
- Ensure token generation works

**4. "No audio in call"**

- Check microphone permissions
- Try toggling mute/unmute
- Verify Agora engine initialized

**5. "Transcription not working"**

- Check Google Cloud credentials
- Verify Speech-to-Text API enabled
- Check WebSocket connection

---

## Security Considerations

1. **JWT Tokens**: Expire in 7 days, refresh on login
2. **Passwords**: Hashed with bcrypt (cost factor 12)
3. **API Keys**: Stored server-side only
4. **FCM Tokens**: Encrypted in transit
5. **Agora Tokens**: Short-lived (1 hour)
6. **HTTPS**: Use TLS in production
7. **Database**: Sanitize inputs via SQLModel

---

## Performance Notes

- **Database**: SQLite suitable for <10K users, migrate to PostgreSQL for scale
- **WebSocket**: One connection per call, scales to ~1000 concurrent calls
- **Google Speech**: Streaming mode, <500ms latency
- **Agora**: Handles millions of concurrent users
- **FCM**: Near-instant delivery (<1s)

---

## Future Enhancements

- [ ] Group calls (3+ participants)
- [ ] Video calling
- [ ] Call recording
- [ ] Advanced analytics dashboard
- [ ] Multi-language support
- [ ] Custom toxicity thresholds per user
- [ ] Sentiment analysis
- [ ] Call quality metrics

---

## Credits

**Developer**: TR Team  
**Tech Stack**: Flutter, FastAPI, Agora, Google Cloud, Firebase  
**AI Services**: Perspective API, Groq

---

**End of Documentation**

For issues or questions, refer to the codebase or contact the development team.
