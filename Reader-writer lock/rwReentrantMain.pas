unit rwReentrantMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs;

type
  TfrmReentrantMain = class(TForm)
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  frmReentrantMain: TfrmReentrantMain;

implementation

uses
  System.SyncObjs;

{$R *.fmx}

type
  TReentrantMREW = record
  private
    FRWLock: TLightweightMREW;
    FLockOwner: TThreadID;
    FLockCount: integer;
  public
    class operator Initialize(out Dest: TReentrantMREW);
    procedure BeginRead; inline;
    function TryBeginRead: Boolean; inline;
    {$IF defined(LINUX) or defined(ANDROID)}
    function TryBeginRead(Timeout: Cardinal): Boolean; overload; inline;
    {$ENDIF LINUX or ANDROID}
    procedure EndRead; inline;
    procedure BeginWrite;
    function TryBeginWrite: Boolean;
    {$IF defined(LINUX) or defined(ANDROID)}
    function TryBeginWrite(Timeout: Cardinal): Boolean; overload;
    {$ENDIF LINUX or ANDROID}
    procedure EndWrite;
  end;

{ TReentrantMREW }

class operator TReentrantMREW.Initialize(out Dest: TReentrantMREW);
begin
  Dest.FLockOwner := 0;
end;

procedure TReentrantMREW.BeginRead;
begin
  FRWLock.BeginRead;
end;

procedure TReentrantMREW.BeginWrite;
begin
  if FLockOwner = TThread.Current.ThreadID then
    Inc(FLockCount)
  else begin
    BeginWrite;
    FLockOwner := TThread.Current.ThreadID;
    FLockCount := 1;
  end;
end;

procedure TReentrantMREW.EndRead;
begin
  FRWLock.EndRead;
end;

procedure TReentrantMREW.EndWrite;
begin
  if {TInterlocked.Read?}FLockOwner <> TThread.Current.ThreadID then
    raise Exception.Create('Not an owner');

  Dec(FLockCount);
  if FLockCount = 0 then begin
    FLockOwner := 0;
    EndWrite;
  end;
end;

function TReentrantMREW.TryBeginRead: Boolean;
begin
  Result := FRWLock.TryBeginRead;
end;

{$IF defined(LINUX) or defined(ANDROID)}
function TReentrantMREW.TryBeginRead(Timeout: Cardinal): Boolean;
begin
  Result := FRWLock.TryBeginRead(Timeout);
end;
{$ENDIF LINUX or ANDROID}

function TReentrantMREW.TryBeginWrite: Boolean;
begin
  if FLockOwner = TThread.Current.ThreadID then
    Inc(FLockCount)
  else begin
    Result := TryBeginWrite;
    if Result then begin
      FLockOwner := TThread.Current.ThreadID;
      FLockCount := 1;
    end;
  end;
end;

{$IF defined(LINUX) or defined(ANDROID)}
function TReentrantMREW.TryBeginWrite(Timeout: Cardinal): Boolean;
begin
  if FLockOwner = TThread.Current.ThreadID then
    Inc(FLockCount)
  else begin
    Result := TryBeginWrite(Timeout);
    if Result then begin
      FLockOwner := TThread.Current.ThreadID;
      FLockCount := 1;
    end;
  end;
end;
{$ENDIF LINUX or ANDROID}

end.
