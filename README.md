```markdown
# PigiGo (MySocialApp)

PigiGo is a modern, cross-platform social networking application built with **Flutter**, **Supabase**, and **Firebase Cloud Messaging (FCM)**. It bridges the visual-first experience of Instagram with the real-time, high-density conversational mechanics of X (formerly Twitter).

---

## Features

- **Authentication & Profiles**
  - Email/Password sign-up and sign-in via Supabase Auth.
  - User session persistence and routing using `AuthGate`.
  - Customizable profile metadata (username, full name, avatar upload, and bio).
  - Dynamic follow and unfollow system with real-time follower/following counts.

- **Feed & Discovery**
  - Paginated infinite scroll feed (cursor-based loading).
  - Pull-to-refresh timeline synchronization.
  - Multi-media posting supporting raw text, high-res images, and embedded video clips.
  - Inline video playback previews powered by `chewie` and `video_player`.
  - Optimistic UI updates for likes and real-time comment tracking.
  - Debounced username search and discovery screen.

- **Real-Time Direct Messaging (DMs)**
  - Active conversation listing with recent message previews and timestamps.
  - Low-latency 1-on-1 private messaging via Supabase Realtime channels.
  - Auto-scrolling chat interface distinguishing sent and received message bubbles.

- **Push Notifications**
  - Token synchronization with Firebase Cloud Messaging (FCM).
  - Background and foreground in-app alerts via `flutter_local_notifications`.
  - Supabase Edge Function integration (`send-notification`) for backend trigger dispatching.

---

## Tech Stack

- **Client**: Flutter (Dart SDK ^3.5.4), Material Design 3 (Dark Theme default)
- **Backend & Database**: Supabase (PostgreSQL, Row Level Security, Realtime, Storage, Edge Functions)
- **Notifications**: Firebase Cloud Messaging (FCM), `flutter_local_notifications`
- **Key Packages**:
  - `supabase_flutter`: Supabase client integration
  - `flutter_bloc`: State management patterns
  - `go_router`: Declarative routing
  - `cached_network_image`: Image caching and memory optimization
  - `image_picker`: Local gallery and camera asset selection
  - `chewie` & `video_player`: Media playback engine
  - `timeago`: Relative human-readable timestamps

---

## Architecture Overview


```

lib/
├── auth/           # Login, registration, and AuthGate session routing
├── bloc/           # State management blocs and events
├── core/           # Constants, themes, network clients, and utilities
├── data/           # Repositories, models, and Supabase data providers
├── screens/
│   ├── feed/       # Home timeline, search, post detail, and video views
│   ├── messaging/  # DM conversation list and 1-on-1 chat interface
│   ├── profile/    # User profiles, follow lists, and edit profile modals
│   └── notifications/
├── services/       # Push notifications and external service integrations
└── widgets/        # Shared UI components, cards, and input fields

```

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`^3.5.4` or higher)
- [Supabase CLI](https://supabase.com/docs/guides/cli) or an active Supabase project
- [Firebase CLI](https://firebase.google.com/docs/cli) for FCM configuration

### 1. Clone the Repository

```bash
git clone [https://github.com/your-username/PigiGo.git](https://github.com/your-username/PigiGo.git)
cd PigiGo

```

### 2. Install Dependencies

```bash
flutter pub get

```

### 3. Configure Supabase

1. Create a project in [Supabase](https://supabase.com).
2. Run the provided database migration script located in `supabase/migrations/` (or run your initial schema setup in the Supabase SQL editor) to set up:
* Tables: `profiles`, `posts`, `likes`, `comments`, `follows`, `conversations`, `messages`, `fcm_tokens`, `stories`
* Row Level Security (RLS) policies
* Storage buckets: `avatars`, `post-images`, `chat-media`


3. Deploy the notification edge function:
```bash
supabase functions deploy send-notification

```



### 4. Configure Firebase Cloud Messaging

* **Android**: Add your `google-services.json` to `android/app/`.
* **iOS**: Add your `GoogleService-Info.plist` to `ios/Runner/` via Xcode.

### 5. Environment Variables & App Initialization

Update your Supabase URL and Anon Key in `lib/main.dart` (or via your local `.env` configuration):

```dart
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL',
  anonKey: 'YOUR_SUPABASE_ANON_KEY',
);

```

### 6. Run the App

```bash
flutter run

```

---

## Database & Security

All PostgreSQL tables enforce **Row Level Security (RLS)**:

* Profiles are publicly readable; profile updates are restricted to the account owner (`auth.uid() = id`).
* Posts are publicly readable; updates and deletions are restricted to the author (`auth.uid() = author_id`).
* Messages and conversations are restricted to conversation participants.
* Likes and follows are inserted and deleted strictly under the authenticated user's session identifier.

---
