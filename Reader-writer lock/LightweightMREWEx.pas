unit LightweightMREWEx;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants, System.SyncObjs;

type
  TLightweightMREWEx = record
  private
    FRWLock: TLightweightMREW;
    FLockOwner: TThreadID;
    FLockCount: integer;
  public
    class operator Initialize(out Dest: TLightweightMREWEx);
    procedure BeginRead; inline;
    function TryBeginRead: Boolean; {$IF defined(LINUX) or defined(ANDROID)}overload;{$ENDIF} inline;
    {$IF defined(LINUX) or defined(ANDROID)}
    function TryBeginRead(Timeout: Cardinal): Boolean; overload; inline;
    {$ENDIF LINUX or ANDROID}
    procedure EndRead; inline;
    procedure BeginWrite;
    function TryBeginWrite: Boolean; {$IF defined(LINUX) or defined(ANDROID)}overload;
    function TryBeginWrite(Timeout: Cardinal): Boolean; overload;
    {$ENDIF LINUX or ANDROID}
    procedure EndWrite;
  end;

implementation

{ TLightweightMREWEx }

class operator TLightweightMREWEx.Initialize(out Dest: TLightweightMREWEx);
begin
  Dest.FLockOwner := 0;
end;

procedure TLightweightMREWEx.BeginRead;
begin
  FRWLock.BeginRead;
end;

procedure TLightweightMREWEx.BeginWrite;
begin
  if FLockOwner = TThread.Current.ThreadID then
    Inc(FLockCount)
  else begin
    FRWLock.BeginWrite;
    FLockOwner := TThread.Current.ThreadID;
    FLockCount := 1;
  end;
end;

procedure TLightweightMREWEx.EndRead;
begin
  FRWLock.EndRead;
end;

procedure TLightweightMREWEx.EndWrite;
begin
  if {TInterlocked.Read?}FLockOwner <> TThread.Current.ThreadID then
    raise Exception.Create('Not an owner');

  Dec(FLockCount);
  if FLockCount = 0 then begin
    FLockOwner := 0;
    FRWLock.EndWrite;
  end;
end;

function TLightweightMREWEx.TryBeginRead: Boolean;
begin
  Result := FRWLock.TryBeginRead;
end;

{$IF defined(LINUX) or defined(ANDROID)}
function TLightweightMREWEx.TryBeginRead(Timeout: Cardinal): Boolean;
begin
  Result := FRWLock.TryBeginRead(Timeout);
end;
{$ENDIF LINUX or ANDROID}

function TLightweightMREWEx.TryBeginWrite: Boolean;
begin
  if FLockOwner = TThread.Current.ThreadID then begin
    Inc(FLockCount);
    Result := true;
  end
  else begin
    Result := FRWLock.TryBeginWrite;
    if Result then begin
      FLockOwner := TThread.Current.ThreadID;
      FLockCount := 1;
    end;
  end;
end;

{$IF defined(LINUX) or defined(ANDROID)}
function TLightweightMREWEx.TryBeginWrite(Timeout: Cardinal): Boolean;
begin
  if FLockOwner = TThread.Current.ThreadID then begin
    Inc(FLockCount);
    Result := true;
  end
  else begin
    Result := FRWLock.TryBeginWrite(Timeout);
    if Result then begin
      FLockOwner := TThread.Current.ThreadID;
      FLockCount := 1;
    end;
  end;
end;
{$ENDIF LINUX or ANDROID}

end.
