; ------------------------------------------------------------
; GMWF Installer Script — Production Ready
; Handles: single instance kill, Hive lock cleanup,
;          safe upgrades, data preservation, future-proof
; ------------------------------------------------------------

[Setup]
AppId={{A1B2C3D4-9F23-4C11-8ABC-1234567890AB}
AppName=GMWF
AppVersion=1.2.9
AppPublisher=GMWF Pvt. Ltd
AppPublisherURL=https://gmwf.pk/
AppSupportURL=https://gmwf.pk/
AppUpdatesURL=https://gmwf.pk/

; Install to Program Files
DefaultDirName={pf}\GMWF
DefaultGroupName=GMWF

; Output
OutputDir=installer
OutputBaseFilename=GMWF-v1.2.9
SetupIconFile=Installer\gmwf.ico

; Compression
Compression=lzma2/ultra64
SolidCompression=yes

; Privileges
PrivilegesRequired=admin

; UI
WizardStyle=modern
DisableDirPage=no
DisableProgramGroupPage=yes

; Uninstall display
UninstallDisplayIcon={app}\gmwf.exe
UninstallDisplayName=GMWF

; ── Upgrade behavior ────────────────────────────────────────
; Kill the running app before files are copied so that
; gmwf.exe and the Hive .lock files are not held open.
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.lock,*.hive
RestartApplications=no

; Allow upgrading over existing install without prompting
; for uninstall first — files are overwritten in place.
; The AppId above ties all versions together so the old
; entry is automatically replaced in Add/Remove Programs.
; ────────────────────────────────────────────────────────────

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; ── Main Flutter Release Build ───────────────────────────────
Source: "build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

; ── VC++ Redistributable ─────────────────────────────────────
; Bundled so the app works on clean Windows installs with no
; internet. Deleted from {tmp} after install completes.
Source: "installer\vc_redist.x64.exe"; \
    DestDir: "{tmp}"; \
    Flags: deleteafterinstall

; ── App icon (used by shortcuts & uninstaller) ───────────────
Source: "Installer\gmwf.ico"; \
    DestDir: "{app}"; \
    Flags: ignoreversion

[Icons]
; Start Menu
Name: "{group}\GMWF";          Filename: "{app}\gmwf.exe"; WorkingDir: "{app}"; IconFilename: "{app}\gmwf.ico"
; Desktop shortcut
Name: "{commondesktop}\GMWF";  Filename: "{app}\gmwf.exe"; WorkingDir: "{app}"; IconFilename: "{app}\gmwf.ico"

[Run]
; 1. Install VC++ Runtime silently (skipped if already installed)
Filename: "{tmp}\vc_redist.x64.exe"; \
    Parameters: "/install /quiet /norestart"; \
    StatusMsg: "Installing Microsoft Visual C++ Runtime..."; \
    Flags: waituntilterminated

; 2. Launch app after install (user can untick this)
Filename: "{app}\gmwf.exe"; \
    Description: "Launch GMWF now"; \
    Flags: nowait postinstall skipifsilent

[UninstallRun]
; Kill the app if it is still running when the user uninstalls
Filename: "{cmd}"; \
    Parameters: "/c taskkill /f /im gmwf.exe"; \
    Flags: runhidden waituntilterminated; \
    RunOnceId: "KillGMWF"

[UninstallDelete]
; Remove crash logs and any leftover runtime files inside {app}
Type: filesandordirs; Name: "{app}\logs"
Type: filesandordirs; Name: "{app}\*.log"

; ── Hive data in AppData ─────────────────────────────────────
; IMPORTANT: The lines below are commented out intentionally.
; Uncommenting them will DELETE the user's local patient data,
; donation records, and cached credentials on uninstall.
; Only uncomment for a "full wipe" / factory-reset scenario.
;
; Type: filesandordirs; Name: "{userappdata}\com.example\gmwf"
; ─────────────────────────────────────────────────────────────

[Code]
// ── Pascal Script section ────────────────────────────────────
// Runs before the installer copies any files.
// 1. Kills any running gmwf.exe so file handles are released.
// 2. Deletes orphaned Hive .lock files that survive a crash,
//    which would otherwise cause the PathAccessException /
//    errno=32 "file in use" startup error on the next launch.

function KillProcessByName(ExeName: String): Boolean;
var
  ResultCode: Integer;
begin
  // taskkill returns 0 (success) or 128 (process not found) —
  // both are acceptable; we only care that we tried.
  Exec('taskkill.exe', '/f /im ' + ExeName,
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := (ResultCode = 0) or (ResultCode = 128);
end;

procedure DeleteHiveLockFiles();
var
  HiveDir: String;
  FindRec: TFindRec;
begin
  // This matches the path Flutter uses on Windows:
  // C:\Users\<user>\AppData\Roaming\com.example\gmwf\gmwf_hive\
  HiveDir := ExpandConstant('{userappdata}\com.example\gmwf\gmwf_hive\');

  if not DirExists(HiveDir) then
    Exit;

  // Delete every *.lock file — these are the files that cause
  // the "cannot access file, used by another process" crash.
  if FindFirst(HiveDir + '*.lock', FindRec) then
  begin
    try
      repeat
        DeleteFile(HiveDir + FindRec.Name);
      until not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    // Step 1: kill the process (releases file handles)
    KillProcessByName('gmwf.exe');

    // Small pause so the OS finishes releasing the handles
    // before we start copying files over them.
    Sleep(800);

    // Step 2: remove orphaned .lock files left by a crash
    DeleteHiveLockFiles();
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    KillProcessByName('gmwf.exe');
    Sleep(600);
  end;
end;
