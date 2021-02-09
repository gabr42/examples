unit Synch;

interface

uses
  System.SyncObjs,
  System.Generics.Collections;

type
  TSynch = class // based on TOmniSynchronizer<T> from OtlSync.Utils
  strict private
    FEvents: TObjectDictionary<string, TEvent>;
    FLock  : TCriticalSection;
  strict protected
    function  Ensure(const name: string): TEvent;
  public
    constructor Create;
    destructor  Destroy; override;
    procedure Signal(const name: string); inline;
    function  WaitFor(const name: string; timeout: cardinal = INFINITE): boolean;
    function SnW(const sigName, waitName: string; timeout: cardinal = INFINITE): boolean;
  end; { TSynch }

implementation

uses
  System.SysUtils;

{ TSynch }

constructor TSynch.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FEvents := TObjectDictionary<string, TEvent>.Create;
end;

destructor TSynch.Destroy;
begin
  FreeAndNil(FEvents);
  FreeAndNil(FLock);
  inherited;
end;

function TSynch.Ensure(const name: string): TEvent;
var
  event: TEvent;
begin
  FLock.Acquire;
  try
    if FEvents.TryGetValue(name, Result) then
      Exit;
    event := TEvent.Create(nil, true, false, '');
    Result := event;
    FEvents.Add(name, Result);
  finally FLock.Release; end;
end;

procedure TSynch.Signal(const name: string);
begin
  Ensure(name).SetEvent;
end;

function TSynch.SnW(const sigName, waitName: string; timeout: cardinal):
  boolean;
begin
  Signal(sigName);
  Result := WaitFor(waitName, timeout);
end;

function TSynch.WaitFor(const name: string; timeout: cardinal): boolean;
begin
  Result := Ensure(name).WaitFor(timeout) = wrSignaled;
end;

end.
