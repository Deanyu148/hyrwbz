; Inno Setup 脚本 - 会议任务管理跟踪系统 (HYRWBZ)
; 兼容 Windows 10 / Windows 11
;
; 单 EXE 启动模式：
;   hyrwbz_frontend.exe 是主入口（桌面图标指向它）
;   hyrwbz_backend.exe 与之同目录，前端启动时自动拉起后端子进程（隐藏窗口）
;
; 编译前需将编译产物放置到 installer/dist/ 目录下：
;   installer/dist/hyrwbz_backend.exe    (Rust 后端，windows_subsystem=windows 无窗口)
;   installer/dist/frontend/              (Flutter Windows 构建产物目录)
; 由 CI 流水线在编译后自动复制到此目录。

#define MyAppName "会议任务管理跟踪系统"
#define MyAppNameEn "HYRWBZ"
#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif
#define MyAppPublisher "HYRWBZ"
#define MyAppExeName "hyrwbz_frontend.exe"
#define MyAppBackendName "hyrwbz_backend.exe"

[Setup]
AppId={{8E7C2A9F-3D4B-4F8A-9C1D-2A3B4C5D6E7F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppNameEn}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=hyrwbz_setup_{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
; 兼容 Windows 10 / Windows 11
MinVersion=10.0.10240
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
LZMAUseSeparateProcess=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: checkedonce

[Files]
; Rust 后端二进制（与前端 exe 同目录，前端启动时按相对路径找到）
Source: "dist\{#MyAppBackendName}"; DestDir: "{app}"; Flags: ignoreversion
; Flutter Windows 产物（整个 build/windows/x64/runner/Release 目录结构）
Source: "dist\frontend\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; 桌面图标直接指向 frontend exe，不再需要 run.bat
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; 卸载时结束后端进程
Filename: "{cmd}"; Parameters: "/C taskkill /F /IM {#MyAppBackendName}"; Flags: runhidden; RunOnceId: "KillBackend"
; 同时结束前端进程
Filename: "{cmd}"; Parameters: "/C taskkill /F /IM {#MyAppExeName}"; Flags: runhidden; RunOnceId: "KillFrontend"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
