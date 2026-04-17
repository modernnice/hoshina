# Hoshina

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2)](https://dart.dev/)
[![Supabase](https://img.shields.io/badge/Supabase-Cloud%20Sync-green)](https://supabase.com/)
[![Hive](https://img.shields.io/badge/Hive-Local%20First-orange)](https://github.com/isar/hive)
[![LLM Agent](https://img.shields.io/badge/LLM-Agent-purple)](#-hoshina-agent-capabilities)
[![Star](https://img.shields.io/badge/Welcome-Star%20this%20project-yellow)](https://github.com/)

**Hoshina** is an AI-native anime tracking app built around the full weekly anime workflow.

It combines **seasonal discovery, heat ranking, search, anime details, cast and seiyuu lookup, personal watchlist management, weekly reminders, cloud sync, and an in-app anime agent** into one coherent product experience.

中文版: [README.md](./README.md)

---

## ✨ Core Features

- 🗓 **Seasonal anime calendar**
  Browse currently airing anime by weekday for a more natural “follow weekly releases” flow.
- 🔥 **Heat ranking**
  Quickly discover which shows are drawing the most attention right now.
- 🔎 **Search + detail loop**
  Search anime and inspect detail pages with scores, summaries, tags, cast, and production information.
- 📚 **Character / seiyuu / staff lookup**
  Search characters, cast members, and real-world people such as voice actors, directors, and writers.
- ✅ **Personal watchlist system**
  Manage `Want to Watch / Watching / Completed`, episode progress, private ratings, reviews, and reminders.
- 🔔 **Weekly update reminders**
  Schedule local notifications and jump directly back into the relevant detail page.
- ☁️ **Cloud sync**
  Sync watch state, ratings, reviews, and reminder preferences through Supabase.
- 🤖 **Built-in AI anime assistant**
  Hoshina Agent supports natural language search, recommendation, lookup, and watchlist actions.
- 🧪 **Debuggable agent workflow**
  Includes development-time traces and tool-chain visibility for agent debugging and iteration.

---

## 🧠 Hoshina Agent Capabilities

Hoshina is not just a generic chatbot attached to anime data. It is a structured **Anime Agent** connected to real tools and app state.

Current capabilities include:

- anime search
- anime detail lookup
- character search
- anime cast / voice actor lookup
- real-world people search (seiyuu / director / writer, etc.)
- person-to-character relationship lookup
- preference-based recommendation
- local watchlist state and progress updates

Example prompts:

- `Recommend some school romance anime`
- `Tell me about Bocchi the Rock!`
- `Who are the characters and voice actors in this anime?`
- `Search for Makoto Shinkai`
- `What roles has Wakayama Shion voiced?`
- `Mark Conan as completed`

---

## 🚀 Product Vision

Many anime apps solve only one piece of the experience:

- search
- rankings
- ratings
- watchlist tracking
- or chat

**Hoshina** is built to connect the full anime-following loop:

**discover → inspect → add to watchlist → track progress → set reminders → continue through AI**

That product continuity is the defining characteristic of the project.

---

## 📱 Main Modules

- **Calendar**
- **Heat Ranking**
- **Search**
- **My Watchlist**
- **Account**
- **Agent Chat**

Each tracked item can currently store:

- watch status
- current episode
- total episodes
- private rating
- private review
- reminder enabled / disabled
- reminder weekday and time

This makes Hoshina useful as both a tracker and a personal anime journal.

---

## 🏗 Tech Stack

- **Flutter**
- **Dart**
- **Hive** for local storage
- **Supabase** for auth and cloud sync
- **Bangumi API** for anime / character / person data
- **flutter_local_notifications** for reminders
- **timezone / flutter_timezone** for scheduling
- **HTTP-based LLM integration** for the agent layer

---

## 📂 Project Structure

```text
lib/
├── config/          # configuration
├── models/          # domain models
├── screens/         # UI screens
├── services/        # auth, sync, notifications, storage, API, LLM
├── services/agent/  # Hoshina agent and tool system
└── widgets/         # reusable components
```

---

## 🔄 Data & Sync Design

The app follows a **local-first with cloud enhancement** approach:

- Hive stores local watchlist data
- reminders are restored at startup
- Supabase synchronizes account-bound watch preferences after login
- missing metadata can be re-hydrated on a new device

This keeps the experience fast locally while still supporting multi-device continuity.

---

## 📝 Changelog

### v0

- Project started on `2026.4.9`
- Last updated on `2026.4.15`
- Initial internal version

### v1 · 2026.4.17

1. Fixed the Android cold-start white screen issue and strengthened security around login and cloud database flows.
2. Added horizontal drag-and-release rebound interaction to the top character imagery in the calendar and heat ranking pages.
3. Unified title alignment logic on anime detail pages across Android and iOS, fixing Android title centering and back-button overlap issues.
4. Completed the cloud sync pipeline for private reviews, fixing the issue where ratings remained after re-login but review text disappeared.
5. Improved multi-device mirrored sync for “My Watchlist”, including add, update, and delete propagation across devices.
6. Updated the Hoshina Agent settings page by removing the forced `/chat/completions` suffix from API URLs, adding one-click presets for DeepSeek, MiniMax, GLM, Kimi, and Qwen official endpoints and models, while keeping custom configuration support; also added API key application links.
7. Reordered character detail display to: main characters → supporting characters → other roles.
8. Added a copy button to the Agent chat interface.
9. Significantly improved Hoshina Agent intent understanding, tool-calling, and ReAct reasoning; added support for querying anime production staff and seiyuu information; and redesigned the preference-based recommendation system.

---

## 🎯 Who This Project Is For

Hoshina is a strong fit for:

- anime fans who follow weekly seasonal shows
- users who care about private ratings and personal reviews
- people who rely on reminder-driven viewing habits
- developers interested in “Flutter + tool-using LLM agents + consumer product workflows”

---

## 🛠 Contribution Directions

Contributions are welcome across:

- UI / UX
- motion and interaction polish
- agent behavior
- recommendation logic
- tool stability
- test coverage

If you want to start from the AI layer, begin with:

- `lib/services/agent/`
- `lib/services/llm_api_service.dart`
- `lib/screens/agent/agent_chat_page.dart`

---

## 📄 License

MIT License
