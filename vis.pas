unit vis;

// Delphi port of vis.h from the Winamp SDK
// Strict 8-byte alignment for Winamp 5+

{$A8}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.IniFiles;

const
  WM_WA_IPC = WM_USER;
  IPC_GETOUTPUTTIME = 105;
  IPC_GETLISTPOS = 125;
  IPC_GETPLAYLISTTITLE = 212;

  VIS_SPECTRUM_CHANNELS = 2;
  VIS_WAVEFORM_CHANNELS = 2;

  VIS_LATENCY = 0;
  VIS_DELAY = 1;

type
  TVisMode = (vmSpectrum, vmWaveform);

  PWinampVisModule = ^TWinampVisModule;

  TWinampVisModule = record
    description: PAnsiChar;
    hwndParent: HWND;
    hDllInstance: HINST;
    sRate: Cardinal;
    nCh: Cardinal;
    latencyMs: Cardinal;
    delayMs: Cardinal;
    spectrumNCh: Cardinal;
    waveformNCh: Cardinal;

    spectrumData: array [0 .. 1, 0 .. 575] of Byte;
    waveformData: array [0 .. 1, 0 .. 575] of Byte;

    config: procedure(const PVisModule: PWinampVisModule); cdecl;
    init: function(const PVisModule: PWinampVisModule): Integer; cdecl;
    render: function(const PVisModule: PWinampVisModule): Integer; cdecl;
    quit: procedure(const PVisModule: PWinampVisModule); cdecl;
    userData: Pointer;
  end;

  PWinampVisHeader = ^TWinampVisHeader;

  TWinampVisHeader = record
    version: Integer;
    description: PAnsiChar;
    getModule: function(Which: Integer): PWinampVisModule; cdecl;
  end;

var
  HDR: TWinampVisHeader;
  VisModule: TWinampVisModule;

  LiveSRate: Cardinal = 44100; // Default fallback

  useWireframes: Boolean = False;
  useReflection: Boolean = False;

  PluginStart: DWORD = 0;
  ElapsedTime: DWORD = 0;

  PendingRebuild: Boolean = False;

  FrameCount: Integer = 0;
  FPSTimer: DWORD = 0;

  gVisMode: TVisMode = vmSpectrum;

  gVPW: Integer;
  gVPH: Integer;

  DataCS: TRTLCriticalSection; // Thread Safety

procedure LogExc(const Context: string); // Exception handler and logging
procedure ProcessKeys(const PVisModule: PWinampVisModule);
function winampVisGetHeader: PWinampVisHeader; cdecl;

implementation

uses
  window.gl, render.gl;

var
  LogCSInited: LongBool = False;

procedure EnsureLogCS;
begin
  if not LogCSInited then
  begin
    try
      InitializeCriticalSection(LogCS);
      LogCSInited := True;
    except
      // If this fails, logging must still not crash the plugin.
      LogCSInited := False;
    end;
  end;
end;

// Utility functions
function GetPluginsDir: string;
var
  P: Integer;
  Path: string;
begin
  Path := ParamStr(0);
  P := Length(Path);
  while (P > 0) and (Path[P] <> '\') do
    Dec(P);
  Result := Copy(Path, 1, P) + 'Plugins\';
end;

procedure LoadSettings;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(GetPluginsDir + 'plugin.ini');
  try
    Settings.Width := Ini.ReadInteger('tocspectrum', 'Width', 800);
    Settings.Height := Ini.ReadInteger('tocspectrum', 'Height', 600);
    Settings.FullScreen := Ini.ReadBool('tocspectrum', 'FullScreen', False);
    Settings.VSync := Ini.ReadBool('tocspectrum', 'VSync', False);
  finally
    Ini.Free;
  end;
end;

// Gets the user's temp folder properly using Windows API
function GetSafeLogFile: string;
var
  Buffer: array [0 .. MAX_PATH] of Char;
begin
  FillChar(Buffer, SizeOf(Buffer), 0);
  GetTempPath(MAX_PATH, Buffer);
  Result := IncludeTrailingPathDelimiter(StrPas(Buffer)) + 'tocspectrum_crash.log';
end;

// Convert Winamp's legacy PAnsiChar metadata (Title) into a Delphi string.
function SafeAnsiPtrToString(P: PAnsiChar): string;
begin
  Result := '';
  if P = nil then
    Exit;
  try
    // Copy immediately; Winamp pointer lifetime is not guaranteed across calls
    Result := string(AnsiString(P));
  except
    Result := '';
  end;
end;

procedure LogExc(const Context: string);
var
  LogFile: string;
  F: TextFile;
  E: Exception;
  MemStatus: TMemoryStatus;
  DllName: array [0 .. MAX_PATH] of Char;
  CrashAddr, BaseAddr, RelAddr: NativeUInt;
  HaveCS: Boolean;
begin
  EnsureLogCS;
  HaveCS := LogCSInited;

  if HaveCS then
    EnterCriticalSection(LogCS);
  try
    try
      LogFile := GetSafeLogFile;

      AssignFile(F, LogFile);
      if FileExists(LogFile) then
        Append(F)
      else
        Rewrite(F);

      GlobalMemoryStatus(MemStatus);
      GetModuleFileName(HInstance, DllName, MAX_PATH);
      E := Exception(ExceptObject);

      if E <> nil then
        CrashAddr := NativeUInt(ExceptAddr)
      else
        CrashAddr := 0;

      BaseAddr := HInstance;
      RelAddr := CrashAddr - BaseAddr;

      Writeln(F, '===================================================================');
      Writeln(F, Format('Time      : %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now)]));
      Writeln(F, Format('Module    : %s', [ExtractFileName(StrPas(DllName))]));
      Writeln(F, Format('Context   : %s', [Context]));
      Writeln(F, Format('Thread ID : %d', [GetCurrentThreadId]));
      Writeln(F, '-------------------------------------------------------------------');

      if E <> nil then
      begin
        Writeln(F, Format('Exception : %s', [E.ClassName]));
        Writeln(F, Format('Message   : %s', [E.Message]));
        Writeln(F, '-------------------------------------------------------------------');
        Writeln(F, 'ADDRESS DEBUGGING (Use Map File)');
        Writeln(F, Format('Crash Address (Absolute) : $%.8x', [CrashAddr]));
        Writeln(F, Format('DLL Base Address         : $%.8x', [BaseAddr]));
        Writeln(F, Format('Relative Offset          : $%.8x  <-- LOOK FOR THIS IN MAP FILE', [RelAddr]));
      end
      else
      begin
        Writeln(F, 'Error: Non-Delphi Exception or Access Violation caught without object.');
        Writeln(F, Format('ExceptAddr: $%.8x', [NativeUInt(ExceptAddr)]));
      end;

      Writeln(F, '-------------------------------------------------------------------');
      Writeln(F, 'SYSTEM STATUS');
      Writeln(F, Format('Memory Load: %d%%', [MemStatus.dwMemoryLoad]));
      Writeln(F, Format('Free RAM   : %d KB', [MemStatus.dwAvailPhys div 1024]));
      Writeln(F, '');

      CloseFile(F);
    except
      // Never let logging kill Winamp.
    end;
  finally
    if HaveCS then
      LeaveCriticalSection(LogCS);
  end;
end;

// VIS functions
//

// Returns the TWinampVisModule record (the actual plugin instance data) to Winamp
function getModule(Which: Integer): PWinampVisModule; cdecl;
begin
  if Which = 0 then
    Result := @VisModule
  else
    Result := nil;
end;

// Called by Winamp when the plugin loads. Initializes settings, creates the OpenGL
// window (glCreateWnd), and starts the ElapsedTime clock.
function init(const PVisModule: PWinampVisModule): Integer; cdecl;
begin
  try
    EnsureLogCS;

    LoadSettings;

    if not glCreateWnd(PVisModule, Settings.Width, Settings.Height, 32, Settings.FullScreen) then
    begin
      glKillWnd;
      Result := 1;
      Exit;
    end;

    PluginStart := GetTickCount;
    ElapsedTime := 0;

    Active := True;

    Result := 0;
  except
    LogExc('VIS>Init');
    Result := 1;
  end;
end;

// The main loop called by Winamp(approx.every 25 ms).
// Fetches audio data, playback time, metadata, and triggers the draw call.
function render(const PVisModule: PWinampVisModule): Integer; cdecl;

var
  CurrentTick: DWORD;
  FPSStr: string;

  // Winamp stats
  PosMs, LenSec, ListPos: Integer;
  CurrMin, CurrSec, TotMin, TotSec: Integer;

  TitlePtr: PAnsiChar;
  TitleStr: string;
  TrackInfo: string;
begin
  try
    if (PVisModule = nil) or (not Active) then
      Exit(1);

    // Always get the AUDIO clock every frame (ms), this drives renderer animations
    PosMs := SendMessage(PVisModule^.hwndParent, WM_WA_IPC, 0, IPC_GETOUTPUTTIME);

    Inc(FrameCount);
    CurrentTick := GetTickCount;

    // Only update the title/FPS display once per second
    if CurrentTick - FPSTimer >= 1000 then
    begin
      // Length (sec)
      LenSec := SendMessage(PVisModule^.hwndParent, WM_WA_IPC, 1, IPC_GETOUTPUTTIME);

      // Title
      ListPos := SendMessage(PVisModule^.hwndParent, WM_WA_IPC, 0, IPC_GETLISTPOS);
      TitlePtr := PAnsiChar(SendMessage(PVisModule^.hwndParent, WM_WA_IPC, ListPos, IPC_GETPLAYLISTTITLE));
      TitleStr := SafeAnsiPtrToString(TitlePtr);

      if PosMs = -1 then
      begin
        TrackInfo := '[Stopped]';
      end
      else
      begin
        if LenSec < 0 then
          LenSec := 0;

        CurrMin := (PosMs div 1000) div 60;
        CurrSec := (PosMs div 1000) mod 60;
        TotMin := LenSec div 60;
        TotSec := LenSec mod 60;

        if TitleStr = '' then
          TrackInfo := Format('[%d:%.2d/%d:%.2d]', [CurrMin, CurrSec, TotMin, TotSec])
        else
          TrackInfo := Format('[%s] [%d:%.2d/%d:%.2d]', [TitleStr, CurrMin, CurrSec, TotMin, TotSec]);
      end;

      FPSStr := Format('%s %s [FPS: %d | Tris: %d | VSync %s]', [WND_TITLE, TrackInfo, FrameCount, getNumTris, BoolToStr(Settings.VSync, True)]);

      SetWindowText(h_Wnd, PChar(FPSStr));

      FrameCount := 0;
      FPSTimer := CurrentTick;
    end;

    // ElapsedTime is AUDIO POSITION in ms (stable across all systems)
    if PosMs < 0 then
      ElapsedTime := 0
    else
      ElapsedTime := DWORD(PosMs);

    case gVisMode of
      vmSpectrum:
        UpdateSpectrumData(PVisModule);
      vmWaveform:
        UpdateWaveformData(PVisModule);
    end;

    glRenderFrame(ElapsedTime);
    ProcessKeys(PVisModule);

    Result := 0;
  except
    LogExc('render');
    Active := False;
    Result := 1;
  end;
end;

// Callback for the "Configure" button in Winamp.
procedure config(const PVisModule: PWinampVisModule); cdecl;
begin
  //
end;

// Called when the plugin is unloaded. Destroys the GL window, unregisters classes, and cleans up threading objects.
procedure quit(const PVisModule: PWinampVisModule); cdecl;
begin
  PendingRebuild := False;
  Active := False;

  glKillWnd;

  if ClassRegistered then
  begin
    UnregisterClass(WND_CLASS, PVisModule^.hDllInstance);
    ClassRegistered := False;
  end;

  if LogCSInited then
  begin
    DeleteCriticalSection(LogCS);
    LogCSInited := False;
  end;
end;

// Helpers

// Ensure we're actually posting messages to a valid recipient
function IsValidWinampWnd(h: HWND): Boolean; inline;
begin
  Result := (h <> 0) and IsWindow(h);
end;

// Polls the keyboard state to send control commands (Next, Prev, Vol) back to Winamp.
procedure ProcessKeys(const PVisModule: PWinampVisModule);
var
  hWA: HWND;
begin
  if PVisModule = nil then
    Exit;

  hWA := PVisModule^.hwndParent;
  if not IsValidWinampWnd(hWA) then
    Exit;

  if keys[VK_LEFT] then
    PostMessage(hWA, WM_COMMAND, 40044, 0);
  if keys[VK_RIGHT] then
    PostMessage(hWA, WM_COMMAND, 40048, 0);
  if keys[VK_UP] then
    PostMessage(hWA, WM_COMMAND, 40058, 0);
  if keys[VK_DOWN] then
    PostMessage(hWA, WM_COMMAND, 40059, 0);
end;

// The singular export Winamp calls to discover the plugin. Returns the header structure.
function winampVisGetHeader: PWinampVisHeader; cdecl;
begin
  HDR.version := $101;
  HDR.description := LibDesc;
  HDR.getModule := getModule;

  FillChar(VisModule, SizeOf(VisModule), 0);
  VisModule.description := ModDesc;
  VisModule.latencyMs := VIS_LATENCY;
  VisModule.delayMs := VIS_DELAY;
  VisModule.spectrumNCh := VIS_SPECTRUM_CHANNELS;
  VisModule.waveformNCh := VIS_WAVEFORM_CHANNELS;
  VisModule.config := config;
  VisModule.init := init;
  VisModule.render := render;
  VisModule.quit := quit;
  VisModule.userData := nil;

  Result := @HDR;
end;

end.
