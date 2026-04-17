# 星奈 Hoshina

<p align="left">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Supabase-Cloud%20Sync-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white" alt="Supabase">
  <img src="https://img.shields.io/badge/Hive-Local%20First-F59E0B?style=for-the-badge&logo=databricks&logoColor=white" alt="Hive">
  <img src="https://img.shields.io/badge/LLM-Agent-7C3AED?style=for-the-badge&logo=openai&logoColor=white" alt="LLM Agent">
</p>

<p align="left">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS-0F172A?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Status-Active%20Development-16A34A?style=flat-square" alt="Status">
  <img src="https://img.shields.io/badge/Welcome-Star%20this%20project-F59E0B?style=flat-square" alt="Star">
</p>

**星奈 Hoshina** 是一个面向二次元追番场景打造的 AI 原生番剧应用。

它将 **时间表追更、热度发现、番剧搜索、角色与声优检索、追番管理、更新提醒、云同步** 与 **内置 Agent 助手** 整合到一个完整体验里，目标不是只做一个“记清单”的工具，而是做一个真正能陪用户持续追番的产品。

English version: [README.en.md](./README.en.md)

---

## ✨ 核心特性

- 🗓 **当季时间表**
  以星期维度展示当前更新作品，更贴近真实追更习惯。
- 🔥 **热度排行榜**
  快速查看当前讨论度更高的作品，适合发现热门番剧。
- 🔎 **搜索 + 详情闭环**
  支持番剧搜索，并可查看评分、简介、标签、角色、声优与制作信息。
- 📚 **角色 / 声优 / 制作人员检索**
  支持查询角色资料、作品出演声优、以及导演、编剧、声优等现实人物信息。
- ✅ **个人追番系统**
  支持 `想看 / 在看 / 看完`、集数进度、私人评分、私人评价与提醒设置。
- 🔔 **每周更新提醒**
  支持为作品配置本地通知，点击通知可直接回到对应详情页。
- ☁️ **云端同步**
  基于 Supabase 同步追番状态、评分、评价与提醒配置，支持多设备延续使用。
- 🤖 **内置 AI 追番助手**
  星奈 Agent 支持自然语言进行搜番、查人、查角色、推荐和追番管理操作。
- 🧪 **可调试的 Agent 工具链**
  支持开发态调试轨迹、工具链展示与多轮行为排查，方便持续优化 Agent。

---

## 🧠 星奈 Agent 能力

星奈并不是一个单纯接了大模型接口的聊天框，而是一个接入了结构化工具与应用状态的 **Anime Agent**。

当前能力覆盖：

- 番剧搜索
- 番剧详情查询
- 角色搜索
- 番剧角色与声优查询
- 现实人物检索（声优 / 导演 / 编剧等）
- 人物关联角色查询
- 基于用户偏好的推荐
- 本地追番列表的状态与进度修改

你可以直接这样和星奈对话：

- `推荐几部恋爱校园番`
- `介绍一下《孤独摇滚》`
- `这部番有哪些角色和声优`
- `找一下新海诚`
- `若山诗音有哪些配音作品`
- `把柯南标记为已看完`

---

## 🚀 项目定位

很多番剧产品只解决一个环节，例如：

- 只做搜索
- 只做榜单
- 只做评分
- 只做追番状态记录
- 或者只接入一个泛用聊天机器人

**星奈 Hoshina** 想打通的是完整的追番链路：

**发现作品 → 查看详情 → 加入追番 → 记录进度 → 设置提醒 → 继续通过 AI 查询人物 / 声优 / 推荐**

因此，这个项目的重点不是“页面很多”，而是**围绕真实追番流程组织功能**。

---

## 📱 当前主要功能模块

- **时间表**
- **热度榜**
- **搜索**
- **我的追番**
- **账号**
- **Agent 聊天页**

每个追番条目当前可保存：

- 状态
- 当前观看进度
- 总集数
- 私人评分
- 私人评价
- 是否开启提醒
- 提醒星期与时间

这让星奈不仅是一个追番工具，也更像一个个人番剧记录系统。

---

## 🏗 技术栈

- **Flutter**
- **Dart**
- **Hive**：本地存储
- **Supabase**：认证与云同步
- **Bangumi API**：番剧 / 角色 / 人物数据来源
- **flutter_local_notifications**：本地通知提醒
- **timezone / flutter_timezone**：时区与周期提醒
- **HTTP-based LLM integration**：Agent 模块

---

## 📂 项目结构

```text
lib/
├── config/          # 配置
├── models/          # 数据模型
├── screens/         # 页面层
├── services/        # 认证、同步、通知、存储、LLM、API
├── services/agent/  # 星奈 Agent 与工具系统
└── widgets/         # 通用组件
```

---

## 🔄 数据与同步设计

项目整体采用 **本地优先 + 云同步增强** 的思路：

- Hive 保存本地追番数据
- 应用启动时恢复本地提醒
- 登录后通过 Supabase 进行用户级同步
- 新设备登录时可重新拉取云端偏好，并自动补齐缺失元数据

这样既能保证本地体验足够流畅，也能支持多设备使用场景。

---

## 📝 更新日志

### v0

- 项目启动于 `2026.4.9`
- 该版本最后更新于 `2026.4.15`
- 初始内部版本

### v1 · 2026.4.17

1. 修复了安卓冷启动白屏问题，并强化了账号登录与云端数据库的安全保护。
2. 为时间表与热度排行榜顶部人物图像加入了可横向拖动并松手回弹的动态交互。
3. 统一了番剧详情页标题在 Android 与 iOS 上的对齐逻辑，解决了安卓端标题未居中并与返回按键重叠的问题。
4. 补齐了私密评价的云端同步链路，修复了重新登录后评分仍在但评价内容丢失的问题。
5. 完善了“我的追番”的多设备镜像同步机制，支持新增、修改和删除状态在设备间同步。
6. 星奈 Agent 配置界面移除了 URL 尾部强制 `/chat/completions` 后缀，新增 DeepSeek、MiniMax、GLM、Kimi、Qwen 官方 API 地址与模型一键填入，并支持自定义填写，同时补充 API Key 申请跳转链接。
7. 将角色详情页展示顺序调整为：主角 → 配角 → 其他角色。
8. 新增 Agent 聊天界面复制按键。
9. 大幅优化星奈 Agent 的意图理解、工具调用与 ReAct 推理能力，新增支持查询番剧制作人员和声优信息，并重做了基于个人偏好的推荐系统。

---

## 🎯 适合谁

这个项目尤其适合：

- 每周稳定追更的番剧用户
- 想认真记录私人评分与评价的人
- 需要提醒驱动追番节奏的人
- 对 “Flutter + 工具型 LLM Agent + 消费级产品场景” 感兴趣的开发者

---

## 🛠 贡献方向

欢迎对以下方向提交改进：

- UI / UX
- 动效与交互
- Agent 能力
- 推荐策略
- 工具链稳定性
- 测试补全

如果你想从 Agent 层开始阅读代码，推荐优先看：

- `lib/services/agent/`
- `lib/services/llm_api_service.dart`
- `lib/screens/agent/agent_chat_page.dart`

---

## 📄 License

MIT License
