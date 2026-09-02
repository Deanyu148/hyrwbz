# 会议任务管理跟踪系统（HYRWBZ）

HYRWBZ 是一套面向 Windows 桌面的会议任务管理与跟踪工具，用于维护会议纪要任务、延期记录、责任部门、责任人、附件、筛选结果和历史快照。

项目采用 **Flutter 桌面前端 + Rust 异步后端 + SQLite**。前端启动时自动拉起同目录的后端进程，二者通过本地套接字通信，不开放 HTTP/TCP 端口；最终可生成 Windows 10/11 安装包和便携版压缩包。

前端采用统一 Material 3 视觉体系，集中管理颜色、圆角、输入框、按钮、通知面板和空状态组件；主界面使用分层卡片、状态标签、交替行色和统一的桌面间距，编辑、筛选及延期窗口共享一致的标题与表单样式。

## 目录

- [主要功能](#主要功能)
- [快速使用](#快速使用)
- [数据导入与导出](#数据导入与导出)
- [数据与配置文件位置](#数据与配置文件位置)
- [系统架构](#系统架构)
- [数据库结构](#数据库结构)
- [本地开发](#本地开发)
- [测试与构建](#测试与构建)
- [发布流水线](#发布流水线)
- [项目结构](#项目结构)
- [已知约束](#已知约束)

## 主要功能

### 任务管理

- 添加、查看、编辑和批量删除任务。
- 同一会议纪要号下，任务序号自动取当前最大值加一。
- 不同会议纪要号分别从任务序号 `1` 开始。
- 双击主表记录可打开编辑窗口，单击或长按可查看详情。
- 支持在添加任务时先选择多个附件，任务创建后自动上传。
- 支持在编辑窗口上传、下载、更新和删除附件。
- 双击编辑窗口中的附件名称，可使用系统默认程序打开附件。
- 更新附件时可选择直接编辑当前附件副本，或重新选择替换文件。

### 会议纪要号锁定

编辑任务时可以锁定当前会议纪要号。锁定后，新建任务会自动填入该会议纪要号；取消锁定后恢复手动输入。锁定状态保存在 SQLite 的 `meta` 表中，重启应用后仍然有效。

### 任务状态与日期输入

- 新建任务时，“实际完成时间”默认填写“进行中”。
- 对未完成任务，后端和历史空值会统一显示为“进行中”。
- 计划完成时间、实际完成时间和延期日期输入框都支持直接填写字符串。
- 只有点击输入框右侧的日历按钮才会打开日期选择器；输入框本身不会自动弹出日历。

### 延期记录

- 为单个任务添加延期日期和延期理由。
- 查看并删除历史延期记录。
- 每个任务最多保留最近 `20` 条延期记录；超过上限时自动删除最早记录。
- 主表显示最近一次延期日期和延期理由。
- 任务详情和 Excel 导出可展示完整延期历史。

### 多条件筛选

支持组合使用以下条件：

- 会议纪要号：模糊匹配。
- 任务序号：精确匹配。
- 责任部门：模糊匹配，多个值使用英文逗号分隔，值之间为“或”关系。
- 责任人：模糊匹配，多个值使用英文逗号分隔，值之间为“或”关系。
- 计划完成时间：开始日期和结束日期。
- 实际完成时间：开始日期和结束日期。
- 延期时间：开始日期和结束日期，只要任一延期记录落入范围即可。
- 延期次数：筛选延期记录数量大于或等于指定值的任务。
- 期望剩余天数：全部、半年内、一月内或三天内；优先按最后延期日期计算，没有延期时使用计划完成日期，逾期任务也包含在对应范围中。
- 附件状态：全部、有附件或无附件。

添加、编辑和筛选界面的责任部门/责任人输入框会自动把常见中文逗号、顿号等转换为英文逗号。例如：

```text
工程部，技术部、质量部
```

会自动转换为：

```text
工程部,技术部,质量部
```

### 日期输入

日期选择窗口同时提供日历和手动输入框，使用严格格式：

```text
YYYY/MM/DD
```

可选择的年份范围为 `2000` 至 `2100`。在按月显示的日期选择器中点击年份，会关闭当前按月视图并切换到按年份滚动的完整日期选择器；选择年份后可继续选择月份和日期，选定具体日期后直接返回日期输入界面。

### 通知与到期提醒

- 主界面通知按钮位于刷新按钮左侧；存在未读通知时按钮右上角显示红点。
- 鼠标悬停通知按钮会打开独立设计的紧凑预览组件，外层尺寸为 `390px` 宽、最高约 `498px`，标题栏高度保持原设计，最多显示前 `2` 条；点击按钮可进入单独设计的完整通知界面。
- 所有当前通知和历史通知的正文均以 `序号<主表第一栏序号>，` 开头，例如 `序号7，`，不使用“任务序号”字段。未读通知项前显示红点，鼠标悬停显示“点击查看详情”。简易预览和完整通知界面的正文均使用加大字号，通知项会按换行后的文字内容自动调整高度，文字左对齐并垂直居中，上下各保留约半行文字高度的留白。
- 点击具体通知并打开对应任务详情时会标记该条通知为已读。
- 紧凑通知栏右上角提供“全部已读”图标按钮，完整通知界面右上角提供“全部已读”文字按钮，可一次标记当天全部通知。
- 只提醒未完成任务：优先使用最后一条延期日期，没有延期时使用计划完成日期。
- 距期望完成时间小于 `7` 天时生成提醒；后台每 `30` 秒扫描核心数据库中的全部任务并重建当前通知，不受主界面筛选条件影响。
- 通知按钮和完整通知界面每 `30` 秒拉取一次最新结果；到期当天和逾期通知使用专用文案。
- 通知按剩余天数升序排列。
- 通知数据独立保存在程序目录下的 `notifications.db`，其中持久记录每条通知的已读/未读状态；后台异步刷新不会修改核心 `data.db`。
- 新进入提醒范围或任务内容发生变化后重新生成的通知默认为未读；导入 Excel、CSV、数据库或全量 ZIP 后，当天通知会重新计算并全部保持未读。
- 通知历史最多保留最近 `30` 条；完整通知界面顶部可进入历史通知页面。
- 历史通知支持三天内、一周内、全部以及精确开始/结束日期筛选，并可继续使用全文搜索。

### 历史快照

- 可手动保存当前全部任务及延期数据的历史快照。
- 最多保留最近 `5` 份，超出后自动删除最早快照。
- Excel 导出时，当前筛选结果写入“当前数据”工作表，历史快照按保存时间写入后续工作表。

### 全文搜索

- 主界面顶部提供与刷新按钮平齐的任务搜索栏，搜索会叠加在当前结构化筛选结果上。
- 任务全文检索使用程序目录下独立的 `search_index.db`，索引库预先汇总任务、附件状态和全部延期字段，避免每次输入都在前端重复拼接并扫描完整对象。
- 输入停止约 `240ms` 后才发起索引查询；任务、延期、附件或导入数据发生变化时索引会标记为失效，并在下一次搜索前以事务方式自动重建。
- 索引服务异常时前端会回退到原有本地搜索逻辑，保证搜索功能仍可使用。
- 完整通知界面顶部提供通知搜索栏和手动刷新按钮；定时刷新后会继续保留当前搜索条件。
- 输入多个空格分隔关键词时，所有关键词都必须在同一条数据中命中。
- 使用双引号或单引号可以搜索完整短语，例如 `"设备 验收"`。
- 使用减号可以排除包含某个关键词的数据，例如 `工程部 -张三`。
- 英文字母搜索不区分大小写，输入内容变化后经过约 `240ms` 防抖再更新结果。
- 任务搜索覆盖会议纪要号、任务序号、任务内容、部门、责任人、计划/实际完成时间、备注、附件状态及全部延期日期和理由。
- 通知搜索覆盖通知文案、会议纪要号、任务序号、期望日期、剩余天数、通知日期和已读状态。

### 主表布局、排序与窗口状态

- 主表总宽度始终适配窗口内容宽度。
- 可拖动表头列边界调整分隔线左侧栏目的宽度，宽度差额全部由最右侧“备注”栏吸收，不改变相邻栏目及其他普通栏目的宽度。
- 列宽有最小值限制，避免栏目被完全压缩。
- 调整窗口大小时，已设置的列宽按比例适配新窗口。
- 可点击可排序表头右侧的上下箭头进行排序；再次点击同一列会切换升序/降序。
- 默认按会议纪要号升序排列。
- 支持排序的列：序号、会议纪要号、任务序号、责任部门、责任人、计划完成时间、实际完成时间、最后延期。
- 任务内容、延期理由、附件和备注不参与排序。
- 数字采用自然数顺序，日期按日期先后顺序，中文按首个汉字拼音顺序；空值在升序时排在前面。
- 自动保存并恢复窗口大小、位置、最大化状态和各列宽度。
- 当保存的窗口位置不再位于当前显示器范围内时，会自动修正到可见区域。

## 快速使用

### 安装版

1. 从 Release 下载 `hyrwbz_setup_<版本号>.exe`。
2. 运行安装程序。
3. 通过桌面或开始菜单中的“会议任务管理跟踪系统”启动。
4. 前端会自动启动同目录下的 `hyrwbz_backend.exe`，无需单独运行服务。

### 便携版

1. 下载 `hyrwbz_portable_<版本号>.zip`。
2. 完整解压到一个可写目录。
3. 运行 `hyrwbz_frontend.exe`。
4. 请勿只复制前端 EXE；Flutter DLL、`data` 目录和 `hyrwbz_backend.exe` 必须保持在发布目录中。

> 应用会在程序目录写入数据库、附件和默认导出文件。便携版应解压到当前用户具有写权限的位置。

## 数据导入与导出

### CSV 模板

仓库根目录的 `template.csv` 给出了基础列顺序：

```csv
序号,会议纪要号,任务序号,任务内容,责任部门,责任人,计划完成时间,延期时间,实际完成时间,备注
```

导入时以中文表头名称定位列，因此建议保留上述列名。

### 导入 Excel

支持选择 `.xlsx` 或 `.xls` 文件，后端使用 `calamine` 自动识别格式。

导入规则：

- 只读取工作簿的第一个工作表。
- 以“会议纪要号 + 任务序号”作为任务唯一标识。
- 已存在的任务会更新，不存在的任务会创建。
- 识别基础表头中的“延期时间”，同时兼容系统 Excel 导出中的“延期1”。
- 当前导入逻辑一次读取一列延期日期；完整多次延期应在软件中维护。
- 缺少会议纪要号或任务序号为 `0`/无法解析的行会跳过。
- 对部分缺少 `xl/_rels/workbook.xml.rels` 的精简 XLSX 文件会尝试自动修复后读取。

在选择文件前，应用会询问是否把文件中的“备注”移动到数据库的“延期理由”：

- **否，保留备注**：默认选项，备注继续写入任务备注。
- **是，移动**：当该行存在延期日期时，清空任务备注并把备注写入对应延期理由。
- 如果该行没有延期日期，即使选择“移动”，备注也仍保留在任务备注中，避免内容丢失。
- 如果相同任务、相同延期日期的记录已经存在，选择“移动”会更新已有延期理由，不会重复创建延期。

### 导入 CSV

CSV 导入与 Excel 使用相同的任务更新、延期和备注移动规则。责任部门和责任人中的中文逗号、顿号等会自动转换为英文逗号，并支持：

- UTF-8；
- UTF-8 BOM；
- GBK（常见于中文版 Excel 另存为 CSV）。

### 导出 Excel

Excel 导出基于当前主界面的筛选条件：

- 文件名：`hyrwbz_export_YYYYMMDD_HHMMSS.xlsx`。
- 第一个工作表名为“当前数据”，内容为当前筛选结果。
- 后续最多包含 `5` 个历史快照工作表。
- 快照工作表使用保存时间命名，例如 `20260902_013045`。
- 延期列按当前数据中的最大延期次数动态生成：`延期1/理由1`、`延期2/理由2`……
- 导出时可选择目标目录；取消目录选择时使用程序目录下的 `exports`。

### 导出 CSV

CSV 导出同样使用当前筛选条件：

- 文件名：`hyrwbz_export_YYYYMMDD_HHMMSS.csv`。
- 使用 UTF-8 BOM，便于 Excel 直接打开中文内容。
- 列结构与 `template.csv` 一致。
- 当任务有多条延期记录时，CSV 只导出第一条延期日期；如需完整延期历史，请使用 Excel 导出。

### 导入/导出数据库

- 导出数据库会把当前 `data.db` 复制为 `exports/data_YYYYMMDD_HHMMSS.db`。
- 导入数据库通过 SQLite `ATTACH`，按表替换 `tasks`、`delays`、`meta`、`snapshots` 和 `attachments` 的数据。
- 数据库文件不加密，可以使用 SQLite 工具直接查看。

### 导入/导出所有文件

主界面的“导出”菜单提供“导出所有文件”，会将以下内容打包为一个 ZIP：

```text
data.db
attachments/
└── <会议纪要号>/<任务序号>/<附件文件>
```

- 文件名：`hyrwbz_all_files_YYYYMMDD_HHMMSS.zip`。
- 可选择导出目录；取消选择时使用程序目录下的 `exports`。
- “导入所有文件”选择 ZIP 后，会要求确认，并用 ZIP 中的数据库和附件目录替换当前数据。
- ZIP 导入会拒绝不安全的路径，并要求压缩包中存在 `data.db`。
- 如果需要完整备份或迁移，请使用“导出所有文件”，不要只导出数据库。

## 数据与配置文件位置

### 程序目录

后端以自身可执行文件所在目录为数据根目录：

```text
<程序目录>/
├── hyrwbz_frontend.exe
├── hyrwbz_backend.exe
├── data.db
├── notifications.db
├── search_index.db
├── attachments/
│   └── <会议纪要号>/<任务序号>/<UUID>_<原文件名>
└── exports/
    ├── hyrwbz_export_*.xlsx
    ├── hyrwbz_export_*.csv
    ├── hyrwbz_all_files_*.zip
    └── data_*.db
```

- `data.db`：主 SQLite 数据库。
- `notifications.db`：通知、通知历史和已读状态数据库。
- `search_index.db`：可自动重建的独立任务全文搜索索引数据库。
- `attachments/`：附件实体文件。
- `exports/`：未指定导出目录时的默认输出位置。

### 用户配置目录

窗口和表格布局保存在：

```text
%APPDATA%/hyrwbz/window_state_v2.json
%APPDATA%/hyrwbz/task_column_widths_v1.json
```

若系统没有 `APPDATA` 环境变量，则回退到前端可执行文件目录。

## 系统架构

```text
┌───────────────────────────────────────────────┐
│ Flutter Windows 前端                          │
│                                               │
│ Home/Edit/Filter/Delay UI                      │
│        │                                      │
│        ▼                                      │
│ Api → LocalRpcClient → dart_ipc               │
└──────────────────────┬────────────────────────┘
                       │ 本地套接字
                       │ Windows: Named Pipe
                       │ Unix: Unix Domain Socket
┌──────────────────────▼────────────────────────┐
│ Rust Tokio 后端                               │
│                                               │
│ 并发 RPC 分发 → Service → sqlx / SQLite         │
│                 ├→ 独立搜索索引数据库          │
│                 ├→ Excel / CSV                │
│                 └→ 附件文件                   │
└───────────────────────────────────────────────┘
```

### 进程生命周期

1. 用户启动 `hyrwbz_frontend.exe`。
2. 前端生成唯一套接字地址：
   - Windows：`\\.\pipe\hyrwbz_<pid>_<nonce>`；
   - Linux/macOS：系统临时目录中的 `.sock` 文件。
3. 前端使用 `--socket-path` 和 `--parent-pid` 参数启动 `hyrwbz_backend.exe`。
4. 前端最多尝试约 `10` 秒连接并调用 `system.health`。
5. 前端关闭时主动关闭 RPC 并结束后端进程。
6. 后端同时每秒检查父进程，父进程消失后自动退出。
7. Windows Release 后端使用 GUI 子系统，不显示控制台窗口。

### RPC 帧协议

前后端使用持久本地连接。每个帧由以下部分组成：

| 偏移 | 长度 | 内容 |
| --- | ---: | --- |
| 0 | 4 字节 | Magic：`HYRW` |
| 4 | 2 字节 | 协议版本，大端序，当前为 `1` |
| 6 | 2 字节 | 标志位：响应、错误 |
| 8 | 4 字节 | JSON 长度，大端序 |
| 12 | 8 字节 | 二进制载荷长度，大端序 |
| 20 | 可变 | JSON 元数据 |
| 后续 | 可变 | 原始二进制数据 |

限制：

- JSON 最大 `1 MiB`；
- 二进制载荷最大 `512 MiB`；
- 附件、Excel、CSV 和数据库文件直接传输原始字节，不使用 Base64。
- 同一持久连接中的多个请求可并发执行，响应根据请求 ID 匹配，不要求按请求顺序返回；写入端统一串行化，避免帧交叉。

### 性能设计

- 主数据库使用 SQLite WAL、`synchronous=NORMAL`、内存临时表、20 MiB 页面缓存和 10 秒忙等待，兼顾桌面端响应速度与可靠性。
- 常用任务日期、更新时间、延期和附件关联字段建立独立索引。
- 延期日期范围和延期次数筛选直接下推到 SQLite，减少无关任务与延期数据进入应用层。
- 批量加载延期记录使用参数绑定查询，并按任务 ID 一次回填，避免逐条任务查询。
- 通知查询使用短时刷新缓存；任务或延期变化会主动使缓存失效，避免界面轮询重复扫描全部任务。
- 搜索使用独立的 `search_index.db` 和延迟触发机制，业务数据库发生变化后按需重建。

### RPC 方法

| 方法 | 作用 |
| --- | --- |
| `system.health` | 健康检查和协议版本 |
| `task.list` | 按条件查询任务 |
| `search.tasks` | 使用独立索引数据库全文搜索任务并返回任务 ID |
| `task.create` | 创建任务并自动分配任务序号 |
| `task.update` | 更新任务 |
| `task.delete` | 删除任务 |
| `delay.list` | 查询任务延期记录 |
| `delay.create` | 添加延期记录 |
| `delay.delete` | 删除延期记录 |
| `meeting_lock.get` | 获取锁定的会议纪要号 |
| `meeting_lock.set` | 设置或清除会议纪要号锁定 |
| `notification.list` | 查询当天到期通知并刷新独立通知数据库 |
| `notification.history` | 按日期范围查询最近 30 条历史通知 |
| `notification.mark_read` | 用户点击具体通知后标记该条通知为已读 |
| `notification.mark_all_read` | 将当天所有通知标记为已读 |
| `snapshot.create` | 保存历史快照 |
| `snapshot.list` | 查询历史快照 |
| `export.excel` | 导出 Excel |
| `export.csv` | 导出 CSV |
| `export.database` | 导出 SQLite 数据库 |
| `export.all_files` | 将数据库和附件打包为 ZIP |
| `import.excel` | 导入 Excel |
| `import.csv` | 导入 CSV |
| `import.database` | 导入 SQLite 数据库 |
| `import.all_files` | 从 ZIP 导入数据库和附件 |
| `attachment.list` | 查询附件 |
| `attachment.upload` | 上传附件 |
| `attachment.download` | 下载附件 |
| `attachment.delete` | 删除附件 |

## 数据库结构

数据库迁移位于 `backend/migrations/0001_init.sql`，构建时由 `backend/build.rs` 嵌入后端程序，启动时自动执行。

### `tasks`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PK | 自增主键 |
| `meeting_no` | TEXT | 会议纪要号 |
| `task_no` | INTEGER | 同一会议纪要号下的任务序号 |
| `task_desc` | TEXT | 任务内容 |
| `dept` | TEXT | 责任部门，可存储逗号分隔的多个值 |
| `owner` | TEXT | 责任人，可存储逗号分隔的多个值 |
| `required_date` | TEXT | 计划完成时间 |
| `actual_date` | TEXT | 实际完成时间 |
| `remark` | TEXT | 备注 |
| `created_at` | TEXT | 创建时间 |
| `updated_at` | TEXT | 更新时间 |

唯一约束：`UNIQUE(meeting_no, task_no)`。

### `delays`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PK | 自增主键 |
| `task_id` | INTEGER | 关联 `tasks.id` |
| `meeting_no` | TEXT | 冗余保存会议纪要号 |
| `task_no` | INTEGER | 冗余保存任务序号 |
| `delay_date` | TEXT | 延期日期 |
| `delay_reason` | TEXT | 延期理由 |
| `created_at` | TEXT | 创建时间 |

### `meta`

键值表，目前用于保存：

```text
locked_meeting_no
```

### `snapshots`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `snapshot_id` | INTEGER PK | 自增主键 |
| `saved_at` | TEXT | 快照时间 |
| `payload` | TEXT | 任务和延期数据的 JSON |

### `attachments`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PK | 自增主键 |
| `task_id` | INTEGER | 关联 `tasks.id` |
| `filename` | TEXT | 用户原始文件名 |
| `stored_name` | TEXT | `attachments` 目录中的相对存储路径 |
| `created_at` | TEXT | 上传时间 |

## 本地开发

### 环境要求

Windows 本地完整构建建议安装：

- Windows 10 或 Windows 11 x64；
- Git；
- Rust stable，MSVC 工具链；
- Flutter stable，Dart SDK `>=3.4.0 <4.0.0`；
- Visual Studio 2022 的“使用 C++ 的桌面开发”组件；
- Inno Setup 6（仅构建安装包时需要）。

项目主要依赖：

| 层 | 组件 |
| --- | --- |
| 后端异步运行时 | Tokio |
| 本地套接字 | interprocess 2.4.3 |
| SQLite | sqlx 0.8 |
| Excel 导出 | rust_xlsxwriter |
| Excel 导入 | calamine |
| CSV/编码 | csv、encoding_rs |
| Flutter IPC | dart_ipc |
| 窗口管理 | window_manager、screen_retriever |
| 中文排序 | pinyin |
| 文件选择 | file_picker |

### 1. 构建后端

```powershell
Set-Location backend
cargo test --all-targets
cargo build --release
```

输出：

```text
backend/target/release/hyrwbz_backend.exe
```

开发环境下，前端也会尝试查找：

```text
backend/target/debug/hyrwbz_backend.exe
```

### 2. 生成 Flutter Windows Runner

仓库只保留 `frontend/windows/README.txt` 占位说明，完整 Windows Runner 由 Flutter CLI 生成：

```powershell
Set-Location frontend
flutter create --platforms=windows --project-name=hyrwbz_frontend --overwrite .
git checkout -- lib/ test/ pubspec.yaml
Remove-Item -Force test\widget_test.dart -ErrorAction SilentlyContinue
flutter pub get
```

`flutter create` 会生成默认 `test/widget_test.dart`，该文件引用模板 `MyApp`，因此需要删除并恢复仓库自己的源码、测试和 `pubspec.yaml`。

### 3. 分析、测试并构建前端

```powershell
flutter analyze
flutter test
flutter build windows --release
```

输出目录：

```text
frontend/build/windows/x64/runner/Release/
```

### 4. 组合运行目录

把后端复制到 Flutter Release 目录：

```powershell
Copy-Item ..\backend\target\release\hyrwbz_backend.exe `
  build\windows\x64\runner\Release\
```

然后运行：

```powershell
.\build\windows\x64\runner\Release\hyrwbz_frontend.exe
```

## 测试与构建

### 后端测试

```powershell
Set-Location backend
cargo test --all-targets
```

当前测试覆盖：

- RPC 帧二进制往返；
- 非法 Magic 拒绝；
- RPC CRUD 与无 Base64 附件传输；
- Windows 命名管道健康检查；
- Excel/CSV 导入及备注转延期理由逻辑。

### 前端测试

```powershell
Set-Location frontend
flutter analyze
flutter test
```

当前测试覆盖：

- RPC 分片输入、连续帧和二进制载荷；
- 主表列宽总和、拖动限制和窗口缩放适配；
- 列宽配置序列化；
- 窗口越界修正和最小尺寸；
- 中文逗号、顿号等自动转换为英文逗号。
- 数字、日期和中文拼音排序。
- 搜索分词、短语匹配、排除词、独立任务索引数据库以及任务/通知全文搜索。
- 历史通知预设/精确日期筛选和历史通知已读状态。
- 期望剩余天数筛选，以及按月/按年两种日期选择模式切换。

### 本地构建安装包

先完成后端和前端 Release 构建，然后在仓库根目录执行：

```powershell
New-Item -ItemType Directory -Force installer\dist\frontend | Out-Null
Copy-Item -Recurse -Force frontend\build\windows\x64\runner\Release\* `
  installer\dist\frontend\
Copy-Item -Force backend\target\release\hyrwbz_backend.exe installer\dist\

& 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' `
  '/DMyAppVersion=0.1.0' `
  installer\hyrwbz.iss
```

安装包输出到：

```text
build/installer/hyrwbz_setup_0.1.0.exe
```

安装器配置：

- x64；
- Windows 最低版本 `10.0.10240`；
- 支持 Windows 10/11；
- 可创建桌面快捷方式；
- 卸载前结束前后端进程。

## 发布流水线

### GitHub Actions

`.github/workflows/build-windows.yml` 是 Windows 构建和发布流水线。

触发方式：

- 向 `main` 推送代码；
- 手动 `workflow_dispatch`，可选择是否标记为预发布。

只修改 README、工作流、CNB 配置或 `.gitignore` 时不会触发自动构建。

主要步骤：

1. 使用 GitHub Release 列表计算新版本号；没有历史版本时从 `0.1.0` 开始。
2. 执行 `cargo test --all-targets` 和 Rust Release 构建。
3. 生成 Flutter Windows Runner。
4. 执行 `flutter analyze`、`flutter test` 和 Windows Release 构建。
5. 生成便携版 ZIP。
6. 使用 Inno Setup 生成安装包。
7. 上传 Actions Artifact。
8. 创建 Tag 和 GitHub Release，并上传安装包及便携版。

流水线声明：

```yaml
permissions:
  contents: write
```

并使用 GitHub 自动生成的 `${{ secrets.GITHUB_TOKEN }}` 查询和创建当前仓库 Release，正常情况下不需要手动添加同名 Secret。

### CNB

`.cnb.yml` 当前负责：

- `main` 分支推送后强制镜像到 GitHub 同名分支；
- 通过网页按钮手动同步到 GitHub；
- 拉取最近一次 GitHub Actions 运行状态和失败 Job 日志；
- 把 GitHub Releases 及附件镜像到 CNB。

`.cnb/web_trigger.yml` 定义了网页按钮。CNB 相关的 `GITHUB_TOKEN` 和 `CNB_TOKEN` 通过私有密钥配置注入，不能直接提交到本仓库。

`scripts/mirror_release.py` 仅依赖 Python 标准库，用于同步 Release、Tag 和附件，并处理目标端已有版本及顺序修复。

## 项目结构

```text
.
├── backend/
│   ├── Cargo.toml
│   ├── build.rs                    # 将 SQL migration 嵌入后端
│   ├── migrations/
│   │   ├── 0001_init.sql
│   │   └── 0002_performance_indexes.sql
│   └── src/
│       ├── main.rs                 # 参数、父进程看门狗、RPC 服务启动
│       ├── db.rs                   # SQLite 初始化和数据路径
│       ├── models.rs               # RPC/数据库数据模型
│       ├── rpc.rs                  # 本地套接字帧协议与 RPC 分发
│       ├── service.rs              # 任务、延期、筛选、附件业务逻辑
│       ├── notifications.rs        # 独立通知数据库、缓存和异步刷新逻辑
│       ├── search_index.rs         # 独立全文搜索索引数据库
│       ├── excel.rs                # Excel 与历史快照导出
│       └── import_export.rs        # Excel/CSV/数据库导入导出
├── frontend/
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart               # Flutter 入口
│   │   ├── app_theme.dart          # 统一配色、控件和桌面主题
│   │   ├── app_widgets.dart        # 面板、状态标签、空状态等通用组件
│   │   ├── backend_manager.dart    # 后端进程启动和退出管理
│   │   ├── notifications.dart      # 通知栏、通知界面和按钮
│   │   ├── notification_model.dart  # 通知数据模型
│   │   ├── local_rpc.dart          # RPC 客户端、帧编解码
│   │   ├── api.dart                # 业务 RPC 封装
│   │   ├── attachment_launcher.dart # 附件临时副本和系统打开
│   │   ├── models.dart             # 前端数据模型
│   │   ├── input_formatters.dart   # 逗号自动归一化
│   │   ├── search_query.dart       # 搜索语法解析和全文匹配
│   │   ├── search_field.dart       # 顶部通用搜索栏
│   │   ├── task_search.dart        # 任务全文搜索字段
│   │   ├── notification_search.dart # 通知全文搜索字段
│   │   ├── task_sort.dart           # 主表排序和比较规则
│   │   ├── table_layout.dart       # 响应式、可拖动列宽算法
│   │   ├── table_layout_store.dart # 列宽持久化
│   │   ├── window_state.dart       # 窗口状态持久化
│   │   └── screens/
│   │       ├── home_screen.dart
│   │       ├── edit_screen.dart
│   │       ├── delay_screen.dart
│   │       ├── filter_screen.dart
│   │       └── date_picker_dialog.dart
│   ├── test/
│   └── windows/README.txt          # Windows Runner 生成说明
├── installer/
│   └── hyrwbz.iss                  # Inno Setup 安装脚本
├── scripts/
│   ├── gen_test_xls.py             # 生成测试 XLS 数据
│   └── mirror_release.py           # GitHub Release 镜像到 CNB
├── .github/workflows/
│   └── build-windows.yml
├── .cnb.yml
├── .cnb/web_trigger.yml
├── template.csv
└── readme.md
```

## 已知约束

- 当前正式交付目标是 Windows x64；代码中保留了 Linux/macOS 本地套接字路径，但仓库没有维护对应平台 Runner 和发布流程。
- 日期字段在 SQLite 中以文本保存。应用日期选择器使用 `YYYY/MM/DD`，直接导入文件时应自行保证格式一致，便于字符串范围筛选。
- Excel/CSV 导入只处理第一个延期日期列，不会恢复一行中的全部动态延期列。
- CSV 导出只包含第一条延期日期，不包含延期理由和完整延期历史。
- 单独导出的 SQLite 数据库不包含外部附件文件；完整备份请使用“导出所有文件”生成 ZIP。
- 通知数据库是独立的 `notifications.db`，只保存到期提醒和最近 30 条通知历史，不属于核心业务数据库导入/导出表。
- 搜索索引使用独立的 `search_index.db`，它是可重建缓存，不会打包进完整备份 ZIP；导入或修改业务数据后会自动失效并在下一次搜索时重建。
- 单独删除附件会同步删除实体文件；删除整条任务时会在事务中级联清理延期和附件记录，并在提交后删除对应附件实体文件。
- 数据库与附件位于程序目录，运行目录必须具有写权限。
- 仓库当前未提供许可证文件；分发和使用范围由项目维护者另行确定。
