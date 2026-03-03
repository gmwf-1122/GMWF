; ------------------------------------------------------------
; GMWF Installer Script (Updated & Safe Version)
; ------------------------------------------------------------

[Setup]
AppId={{A1B2C3D4-9F23-4C11-8ABC-1234567890AB}   ; Unique ID (keep this same forever)
AppName=GMWF
AppVersion=1.0.5
AppPublisher=GMWF Pvt. Ltd
AppPublisherURL=https://gmwf.pk/
AppSupportURL=https://gmwf.pk/
AppUpdatesURL=https://gmwf.pk/
DefaultDirName={pf}\GMWF
DefaultGroupName=GMWF
OutputDir=installer
OutputBaseFilename=GMWF_Setup_1_0_5
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
SetupIconFile="Installer\gmwf.ico"
WizardStyle=modern

; 🔥 Important upgrade behavior
CloseApplications=yes
RestartApplications=no
DisableDirPage=no
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\GMWF.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; --- Main Flutter Release Build ---
Source: "build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

; --- VC++ Redistributable ---
Source: "installer\vc_redist.x64.exe"; \
    DestDir: "{tmp}"; \
    Flags: deleteafterinstall

[Icons]
Name: "{group}\GMWF"; Filename: "{app}\GMWF.exe"; WorkingDir: "{app}"
Name: "{commondesktop}\GMWF"; Filename: "{app}\GMWF.exe"; WorkingDir: "{app}"

[Run]
; Install VC++ silently
Filename: "{tmp}\vc_redist.x64.exe"; \
    Parameters: "/install /quiet /norestart"; \
    StatusMsg: "Installing Microsoft Visual C++ Runtime..."; \
    Flags: waituntilterminated

; Launch app after install
Filename: "{app}\GMWF.exe"; \
    Description: "Launch GMWF"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Remove logs folder
Type: filesandordirs; Name: "{app}\logs"

; Optional: Remove leftover local cache (uncomment if needed)
; Type: filesandordirs; Name: "{localappdata}\GMWF"
