# 星奈 Hoshina

[中文](#中文) | [English](#english)

## 中文

**星奈 Hoshina** 是一款面向二次元追番用户的 Flutter 应用，把“找番、看番、记番、追更、问 AI”整合进同一个体验里。

它不是一个只会记清单的工具，也不是单纯接了个聊天框的番剧 App；星奈更像一个真正能陪你追番的助手：

- 看当季时间表
- 查热度榜和作品详情
- 搜角色、声优、导演、编剧
- 记录想看 / 在看 / 看完和观看进度
- 开启每周更新提醒
- 通过 AI 助手直接问作品、人物、推荐和追番操作

### 项目亮点

- **时间表首页**
  按星期查看正在播出的作品，更适合追更用户。
- **热度榜**
  快速了解当前讨论度更高的番剧。
- **搜索与详情**
  支持作品搜索，并提供评分、简介、标签、角色、声优、制作信息等内容。
- **追番管理**
  可记录状态、进度、私评分、私评语和提醒设置。
- **本地提醒**
  为每周更新作品安排通知提醒，点击通知可回到对应详情页。
- **云端同步**
  基于 Supabase 同步用户偏好、评分、进度和提醒信息。
- **内置 AI 追番助手**
  星奈支持自然语言完成：
  - 搜番
  - 查角色和声优
  - 查导演、编剧等人物信息
  - 基于偏好推荐番剧
  - 直接修改追番状态和进度
- **可调试的 Agent 工具链**
  支持开发态调试轨迹，方便排查 prompt、tool calling 和多轮行为问题。

### 星奈 Agent 的特点

星奈不是一个泛用聊天机器人，而是一个**接入了结构化工具和应用状态的 Anime Agent**。

它可以基于以下能力工作：

- 番剧搜索
- 番剧详情查询
- 角色搜索
- 番剧角色与声优查询
- 现实人物检索（声优 / 导演 / 编剧等）
- 人物关联角色查询
- 用户偏好种子提取
- 本地追番列表读写操作

### 核心功能

#### 1. 番剧发现

- 当季时间表
- 热度榜
- 标题搜索
- 详情页浏览

#### 2. 追番管理

- `想看 / 在看 / 看完`
- 集数进度更新
- 私人评分
- 私人短评
- 每周更新提醒

#### 3. 人物与角色信息

- 查角色资料
- 查作品角色与声优
- 查声优、导演、编剧等现实人物
- 查某位声优配过哪些角色 / 作品

#### 4. AI 助手体验

你可以直接对星奈说：

- `推荐几部恋爱校园番`
- `介绍一下《孤独摇滚》`
- `这部番有哪些角色和声优`
- `找一下新海诚`
- `青山吉能有哪些配音作品`
- `把柯南标记为已看完`

### 技术栈

- **Flutter**
- **Dart**
- **Hive**：本地存储
- **Supabase**：认证与云同步
- **Bangumi API**：番剧 / 角色 / 人物数据来源
- **flutter_local_notifications**：本地通知提醒
- **timezone / flutter_timezone**：时区与周期提醒
- **HTTP LLM 接入**：AI Agent 模块

### 项目结构

```text
lib/
  config/          配置
  models/          数据模型
  screens/         页面
  services/        认证、同步、通知、存储、LLM、API
  services/agent/  星奈 Agent 与工具系统
  widgets/         通用组件
```

### 当前 App 覆盖的主要页面

- **时间表**
- **热度榜**
- **搜索**
- **我的追番**
- **账号**
- **Agent 聊天页**

### 数据能力

每个追番条目不只是“是否看过”，还可以保存：

- 状态
- 当前看到第几集
- 总集数
- 私评分
- 私评语
- 是否开启提醒
- 提醒星期与时间

这让星奈既是追番工具，也更像一个个人番剧记录本。

### 本地优先 + 云同步

星奈整体偏向本地优先体验：

- 追番数据保存在 Hive
- 提醒会在启动时从本地恢复
- 登录后通过 Supabase 同步偏好数据
- 新设备拉取云端数据时，缺失的元信息会从 Bangumi 再补齐

这样既保证使用流畅，也能兼顾账号级持久化。

### AI Agent 配置

LLM 相关配置通过应用内设置页完成，而不是写死在代码里。你可以配置：

- 模型名
- API URL
- API Key
- 消息显示上限
- 工具轮次上限
- 是否开启调试轨迹

这让星奈适合做多模型实验，也方便持续迭代 Agent 能力。

### 适合谁

星奈尤其适合：

- 每周追更的番剧用户
- 想认真管理私人追番列表的人
- 需要更新提醒的人
- 对“工具化 LLM + Flutter 产品”感兴趣的开发者

### 更新日志

- **v0 版本**
  项目启动于 `2026.4.9`，该版本最后更新于 `2026.4.15`。
  初始内部版本。
- **v1 版本**
  更新日期：`2026.4.17`
  1. 修复了安卓冷启动白屏问题，并全面强化了账号登录与云端数据库的安全保护。
  2. 为时间表与热度排行榜顶部人物图像加入了可横向拖动并松手回弹的动态交互，让页面表现更灵动自然。
  3. 统一了番剧详情页标题在 Android 与 iOS 上的对齐逻辑，解决了安卓端标题未居中并与返回按键重叠的显示问题。
  4. 补齐了私密评价的云端同步链路，修复了用户重新登录后评分仍在但评价内容被清空的问题。
  5. 完善了“我的追番”的多设备镜像同步机制，支持在不同设备间同步新增、修改以及删除后的追番状态。
  6. 星奈 Agent 配置界面移除了 URL 尾部强制 `/chat/completions` 后缀，新增 DeepSeek、MiniMax、GLM、Kimi、Qwen 一键填入官方 API 地址与适配模型功能，并支持自定义填写；底部也添加了对应厂商 API Key 申请跳转链接。
  7. 将角色详情页的角色展示顺序调整为：主角 → 配角 → 其他角色（如旁白、闲角等）。
  8. 新增 Agent 聊天界面复制按键。
  9. 大幅优化星奈 Agent 的意图理解、工具调用与 ReAct 推理能力，新增支持查询番剧制作人员和声优信息，并重做升级了基于个人偏好的 Agent 推荐系统。

### Roadmap

- 更强的推荐结果质量
- 更丰富的搜索筛选能力
- 更完整的 staff / cast 展示
- 更顺滑的 LLM 配置与 onboarding
- 更多测试覆盖 Agent 行为与核心页面流程

### 贡献

欢迎对 UI、交互、Agent、推荐策略、工具链稳定性和测试补全等方向提交改进。

如果你想从 AI 层开始看代码，推荐优先阅读：

- `lib/services/agent/`
- `lib/services/llm_api_service.dart`
- `lib/screens/agent/agent_chat_page.dart`

### License

当前仓库尚未声明 License；如果计划正式开源发布，建议补充许可证文件。

---

## English

**Hoshina** is a Flutter anime tracking app that brings together discovery, watchlist management, reminders, and an in-app AI anime assistant in one product.

It is not just a watchlist tool, and not just a chatbox attached to an anime UI. Hoshina is designed as a real companion for anime fans who want to:

- follow seasonal shows
- search titles and inspect rich details
- manage personal watch status and progress
- receive weekly episode reminders
- ask an AI assistant about anime, cast, staff, recommendations, and watchlist actions

### Highlights

- **Seasonal calendar**
  Browse currently airing anime by weekday.
- **Heat ranking**
  Quickly see what is trending right now.
- **Search and detail pages**
  Explore anime metadata, scores, summaries, tags, characters, cast, and production information.
- **Watchlist management**
  Track `Want to Watch`, `Watching`, `Completed`, plus progress, private rating, and notes.
- **Local reminders**
  Schedule weekly notifications and jump back into the relevant detail page from a notification tap.
- **Cloud sync**
  Sync user preferences, progress, ratings, reviews, and reminder settings with Supabase.
- **Built-in AI anime assistant**
  Hoshina can:
  - search anime
  - inspect characters and voice actors
  - search directors, writers, and other creators
  - recommend titles from user preferences
  - update watchlist status and progress through natural language
- **Debuggable agent workflow**
  The app includes development-time agent trace support for prompt/tool debugging.

### What Makes The Agent Different

Hoshina is not a generic chatbot. It is a **tool-based anime agent** connected to structured data and app state.

It can operate over:

- anime search results
- anime details
- character search
- anime cast / voice actor lists
- person search for seiyuu, directors, writers, etc.
- person-to-character relationships
- user preference seeds
- local watchlist actions

Recent improvements also made the agent more robust:

### Core Features

#### 1. Anime Discovery

- seasonal calendar
- heat ranking
- title search
- rich detail pages

#### 2. Watchlist Management

- `Want to Watch / Watching / Completed`
- episode progress updates
- private ratings
- private reviews
- weekly reminders

#### 3. Character / Staff / Seiyuu Lookup

- search characters
- inspect a title's cast and voice actors
- search real-world people such as voice actors, directors, and writers
- inspect which roles a voice actor has voiced

#### 4. AI-Native Anime Experience

You can talk to Hoshina with prompts like:

- `Recommend some school romance anime`
- `Tell me about Bocchi the Rock!`
- `Who are the characters and voice actors in this anime?`
- `Search for Makoto Shinkai`
- `What roles has Aoyama Yoshino voiced?`
- `Mark Conan as completed`

### Tech Stack

- **Flutter**
- **Dart**
- **Hive** for local storage
- **Supabase** for auth and cloud sync
- **Bangumi API** for anime / character / person data
- **flutter_local_notifications** for reminders
- **timezone / flutter_timezone** for weekly scheduling
- **HTTP-based LLM integration** for the AI agent

### Project Structure

```text
lib/
  config/          app configuration
  models/          domain models
  screens/         UI screens
  services/        auth, sync, storage, notifications, API, LLM
  services/agent/  Hoshina agent and tool system
  widgets/         reusable components
```

### Main Screens

- **Calendar**
- **Heat Ranking**
- **Search**
- **My Watchlist**
- **Account**
- **Agent Chat**

### Rich Personal Tracking

Each tracked anime entry can store:

- watch status
- current episode
- total episodes
- private rating
- private review
- reminder enabled / disabled
- reminder weekday and time

This makes Hoshina useful both as a tracker and as a personal anime journal.

### Local-First + Cloud Sync

The app is built around a local-first workflow:

- watchlist data is stored in Hive
- reminders are restored locally on startup
- user preferences are synced with Supabase after login
- missing metadata can be re-hydrated from Bangumi when syncing on a new device

### AI Agent Configuration

LLM settings are configured inside the app, not hard-coded in source. You can set:

- model name
- API URL
- API key
- message display limit
- tool round limit
- debug trace visibility

This makes Hoshina flexible for multi-model experimentation and ongoing agent iteration.

### Who This Project Is For

Hoshina is a strong fit for:

- anime fans who follow weekly seasonal releases
- users who want a more personal watchlist workflow
- people who rely on reminder-based follow-up
- developers interested in tool-using LLMs inside a real Flutter product

### Changelog

- **v0**
  Project started on `2026.4.9`, with the last update for this version on `2026.4.15`.
  Initial internal build.
- **v1**
  Release date: `2026.4.17`
  1. Fixed the Android cold-start white screen issue and strengthened security around login and cloud database flows.
  2. Added horizontal drag-and-release rebound interaction to the top character imagery in the calendar and heat ranking pages for a more lively UI.
  3. Unified title alignment logic on the anime detail page across Android and iOS, fixing Android title centering and back-button overlap issues.
  4. Completed the cloud sync pipeline for private reviews, fixing the issue where ratings remained after re-login but review text was lost.
  5. Improved multi-device mirror sync for “My Watchlist”, including add, update, and delete synchronization across devices.
  6. Updated the Hoshina Agent settings page by removing the forced `/chat/completions` suffix from API URLs, adding one-click presets for DeepSeek, MiniMax, GLM, Kimi, and Qwen official endpoints and model suggestions, while still supporting custom input; also added vendor API key application links.
  7. Adjusted character detail ordering to: main characters → supporting characters → other roles such as narration or extras.
  8. Added a copy button to the Agent chat interface.
  9. Significantly improved Hoshina Agent intent understanding, tool-calling, and ReAct reasoning; added support for querying anime production staff and seiyuu information; and redesigned the preference-based recommendation system.

### Roadmap

- stronger recommendation quality
- richer search filtering
- more complete staff / cast presentation
- smoother LLM onboarding and setup UX
- broader test coverage for agent behavior and critical app flows

### Contributing

Improvements to UI, UX, agent behavior, recommendation logic, tool stability, and tests are welcome.

If you want to start from the AI layer, begin with:

- `lib/services/agent/`
- `lib/services/llm_api_service.dart`
- `lib/screens/agent/agent_chat_page.dart`

### License

This repository does not currently declare a license. Add one before formal open-source distribution.
