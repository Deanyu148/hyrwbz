; Inno Setup 脚本 - 会议任务管理跟踪系统 (HYRWBZ)
; 兼容 Windows 10 / Windows 11
; 编译前需将编译产物放置到 installer/dist/ 目录下：
;   installer/dist/hyrwbz_backend.exe   (Rust 后端)
;   installer/dist/frontend/             (Flutter Windows 构建产物目录)
; 由 CI 流水线在编译后自动复制到此目录。

#define MyAppName "会议任务管理跟踪系统"
#define MyAppNameEn "HYRWBZ"
#define MyAppVersion "0.1.0"
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
; Rust 后端二进制
Source: "dist\{#MyAppBackendName}"; DestDir: "{app}"; Flags: ignoreversion
; Flutter Windows 产物（整个 build/windows/x64/runner/Release 目录结构）
Source: "dist\frontend\*"; DestDir: "{app}\frontend"; Flags: ignoreversion recursesubdirs createallsubdirs
; 启动脚本（启动 frontend 前先启动 backend）
Source: "dist\run.bat"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\run.bat"; IconFilename: "{app}\frontend\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\run.bat"; IconFilename: "{app}\frontend\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\run.bat"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; 卸载时结束后端进程
Filename: "{cmd}"; Parameters: "/C taskkill /F /IM {#MyAppBackendName}"; Flags: runhidden; RunOnceId: "KillBackend"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
