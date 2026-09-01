# 会议任务管理跟踪系统 (HYRWBZ)

基于 Rust 后端 + Flutter 前端 + SQLite 数据库的会议任务跟踪管理系统，打包为 Windows 10/11 兼容安装软件。

## 用户原始需求

以下是用户给出的原始需求，逐字保留：

> 我现在有一个项目需求，使用rust后端加flutter前端构建。需求如下：
> 1.需接入SQLite数据库，可以相互导入/导出，且不加密。
> 2.任务完成后需构建Windows端软件，使用inno setup安装软件，需兼容Windows 10和Windows 11。
> 3.数据库模板已经放在仓库当中，文件名为template.csv，自行决定数据类型，其中要求"完成时间,实际完成时间,延期时间1,延期时间2,延期时间3,延期时间…"都是确定的日期，格式为YYYY/MM/DD。
> 4.数据条目需要导出，导出时采用Excel表格，导出内容由用户选择确定，即用户在软件中筛选完毕数据后，按筛选后的内容导出。
> 5.保留5份历史记录，导出Excel Sheet 1为当前数据，Sheet 2为第一份历史记录，做好Sheet的重命名，命名规则为保存的时间
>
> 以下是软件界面要求：
> 1.主界面要有添加/删除条目按钮，以及添加/删除延期按钮，在主界面要把重心放在显示具体数据条目上。
> 2.添加条目时，会议号由用户输入，内容为一串字符串，任务号从1开始，每次自动加1，每次添加不同会议号任务号都从1开始，当前存在的会议号，任务号自动获取最大值加1。
> 3.添加延期时，弹出延期窗口，由用户输入延期日期以及延期理由，延期日期的数据表结构自行确定，需要与会议号以及任务号关联，最大保留20条延期记录。
> 4.双击数据库条目打开编辑窗口，编辑窗口要可以编辑所有数据条目，并且添加一个确定框，由用户确定是否锁定当前会议号，锁定成功后下一次添加条目自动填入会议号，确定框需要持久化，即一直添加条目，只要用户不主动解锁会议号就自动填入会议号。
> 2.要有统计功能，即按照"会议号,任务号,责任部门,责任人,要求完成时间,实际完成时间,延期时间1,延期时间2,延期时间3,延期时间…"完成筛选，其中日期筛选需要弹出日期选择窗口，由用户确定起止日期，起止日期的确定需要有日期选择框和输入框，保证可以手动键盘输入日期，统计条件确定后自动在主界面显示。
>
> 全部要求完成后编写一份cnb流水线用于编译Windows软件，编译结果自动新建tag保存到release。将这份需求写入readme

## 技术架构

### 单 EXE 启动机制

为避免后端弹出控制台黑窗、并让前后端真正连通，采用 Flutter Windows 桌面 GUI 主进程 + Rust 后端子进程模式：

1. 桌面图标双击 → 启动 Flutter Windows GUI (hyrwbz_frontend.exe)
2. Flutter main() 启动时生成唯一 LocalSocket 地址并拉起同目录的 hyrwbz_backend.exe
3. Windows 使用命名管道 `\\.\pipe\hyrwbz_<pid>_<nonce>`，不监听 TCP 端口
4. 前后端通过带长度帧头的 JSON RPC 与原始二进制载荷通信
5. 前端在 10 秒内等待本地服务就绪，失败时显示错误提示
6. 导入、附件等二进制数据直接通过 LocalSocket 传输，不使用 Base64
7. 前端退出后主动结束后端，后端同时通过 parent-pid 看门狗兜底退出

### 数据存储

- SQLite 文件：%APPDATA%/hyrwbz/data.db（不加密）
- Excel 导出目录：%APPDATA%/hyrwbz/exports/
- 数据库导入：用户选择外部 data.db 覆盖当前

## 数据库结构

依据 template.csv，所有日期统一 YYYY/MM/DD。

### tasks 任务表

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK AUTOINCREMENT | 主键 |
| meeting_no | TEXT NOT NULL | 会议号 |
| task_no | INTEGER NOT NULL | 任务号（同会议号下从 1 自增） |
| task_desc | TEXT | 任务说明 |
| dept | TEXT | 责任部门 |
| owner | TEXT | 责任人 |
| required_date | TEXT | 要求完成时间 |
| actual_date | TEXT | 实际完成时间 |
| remark | TEXT | 说明及备注 |
| created_at | TEXT | 创建时间 |
| updated_at | TEXT | 更新时间 |
| | UNIQUE(meeting_no, task_no) | 联合唯一 |

### delays 延期表

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| task_id | 关联 tasks.id |
| meeting_no | 冗余会议号 |
| task_no | 冗余任务号 |
| delay_date | 延期日期 YYYY/MM/DD |
| delay_reason | 延期理由 |
| created_at | 创建时间 |

每个 task 最多 20 条，新增第 21 条自动删除最早一条。

### meta 元信息表

| key | value | 说明 |
| --- | --- | --- |
| locked_meeting_no | 字符串/空 | 持久化的会议号锁定状态 |

### snapshots 历史快照表

| snapshot_id | saved_at | payload |
| --- | --- | --- |
| INTEGER PK | TEXT | TEXT (JSON) |

最多保留 5 份，超出滚动删除最早一份。

## LocalSocket RPC 一览

前后端使用持久 LocalSocket 连接。每个帧包含 20 字节大端序帧头、JSON 元数据以及可选原始二进制载荷。

| RPC 方法 | 说明 |
| --- | --- |
| system.health | 健康检查与协议版本 |
| task.list/create/update/delete | 任务查询及增删改 |
| delay.list/create/delete | 延期记录管理 |
| meeting_lock.get/set | 锁定会议号管理 |
| snapshot.create/list | 历史快照管理 |
| export.excel/csv/database | 按筛选导出数据 |
| import.excel/csv/database | 通过二进制载荷导入数据 |
| attachment.list/upload/delete/download | 附件管理及原始字节传输 |

## Excel 导出规则

- 按当前主界面筛选结果导出
- 6 个 Sheet：Sheet1=当前数据（重命名为"当前数据"），Sheet2-6=5 份历史记录（重命名为快照保存时间 YYYYMMDD_HHMMSS）
- 列头遵循 template.csv

## 技术栈

| 层 | 技术 |
| --- | --- |
| 后端 | Rust + Tokio LocalSocket RPC + sqlx + SQLite (windows_subsystem=windows) |
| 前端 | Flutter Windows 桌面 (Process.start 拉起后端) |
| 数据库 | SQLite (不加密) |
| 导出 | rust_xlsxwriter |
| 安装 | Inno Setup |
| CI/CD | GitHub Actions + CNB 流水线 |

## 目录结构

```
.
├── backend/                  # Rust 后端
│   ├── Cargo.toml
│   ├── migrations/0001_init.sql
│   └── src/
│       ├── main.rs            # windows_subsystem=windows + LocalSocket 启动参数
│       ├── db.rs
│       ├── models.rs
│       ├── rpc.rs             # LocalSocket 帧协议与 RPC 分发
│       ├── service.rs         # 纯业务服务层
│       ├── excel.rs
│       └── import_export.rs
├── frontend/                  # Flutter Windows 桌面
│   ├── pubspec.yaml
│   └── lib/
│       ├── main.dart          # 启动时拉起后端子进程
│       ├── api.dart            # RPC 业务 API
│       ├── local_rpc.dart      # LocalSocket 客户端与帧编解码
│       ├── backend_manager.dart
│       ├── window_state.dart
│       ├── models.dart
│       └── screens/
├── installer/hyrwbz.iss
├── .github/workflows/build-windows.yml
├── .cnb.yml
├── template.csv
└── readme.md
```
