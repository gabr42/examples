unit PublishSubscribe;

interface

uses
  System.SysUtils, System.Generics.Collections, System.SyncObjs;

type
  TPubSub = class
  public type
    TCallback = TProc<integer>;
    TLockingScheme = (lockNone, lockCS, lockMonitor, lockMREW, lockLightweightMREW);
  strict private
    FLockCS: TCriticalSection;
    FLockMREW: TMREWSync;
    FLockLight: TLightweightMREW;
    FSubscribers: TList<TCallback>;
    FLockReader: TProc;
    FUnlockReader: TProc;
    FLockWriter: TProc;
    FUnlockWriter: TProc;
    FOnEndNotify: TProc;
    FOnStartNotify: TProc;
  strict private
    procedure SetOnEndNotify(const Value: TProc);
    procedure SetOnStartNotify(const Value: TProc);
  public
    constructor Create(lockingScheme: TLockingScheme);
    destructor Destroy; override;
    procedure Subscribe(callback: TCallback);
    procedure Unsubscribe(callback: TCallback);
    procedure Notify(value: integer);
    property OnStartNotify: TProc read FOnStartNotify write SetOnStartNotify;
    property OnEndNotify: TProc read FOnEndNotify write SetOnEndNotify;
  end;

implementation

{ TPubSub }

constructor TPubSub.Create(lockingScheme: TLockingScheme);
begin
  inherited Create;
  FSubscribers := TList<TCallback>.Create;
  case lockingScheme of
    lockNone:
      begin
        FLockReader := procedure begin end;
        FLockWriter := procedure begin end;
        FUnlockReader := procedure begin end;
        FUnlockWriter := procedure begin end;
      end;
    lockCS:
      begin
        FLockCS := TCriticalSection.Create;
        FLockReader := procedure begin FLockCS.Acquire; end;
        FLockWriter := procedure begin FLockCS.Acquire; end;
        FUnlockReader := procedure begin FLockCS.Release; end;
        FUnlockWriter := procedure begin FLockCS.Release; end;
      end;
    lockMonitor:
      begin
        FLockCS := TCriticalSection.Create;
        FLockReader := procedure begin MonitorEnter(Self); end;
        FLockWriter := procedure begin MonitorEnter(Self); end;
        FUnlockReader := procedure begin MonitorExit(Self); end;
        FUnlockWriter := procedure begin MonitorExit(Self); end;
      end;
    lockMREW:
      begin
        FLockMREW := TMREWSync.Create;
        FLockReader := procedure begin FLockMREW.BeginRead; end;
        FLockWriter := procedure begin FLockMREW.BeginWrite; end;
        FUnlockReader := procedure begin FLockMREW.EndRead; end;
        FUnlockWriter := procedure begin FLockMREW.EndWrite; end;
      end;
    lockLightweightMREW:
      begin
        FLockReader := procedure begin FLockLight.BeginRead; end;
        FLockWriter := procedure begin FLockLight.BeginWrite; end;
        FUnlockReader := procedure begin FLockLight.EndRead; end;
        FUnlockWriter := procedure begin FLockLight.EndWrite; end;
      end;
  end;
end;

destructor TPubSub.Destroy;
begin
  FreeAndNil(FLockCS);
  FreeAndNil(FLockMREW);
  FreeAndNil(FSubscribers);
  inherited;
end;

procedure TPubSub.Notify(value: integer);
begin
  FLockReader();
  if assigned(FOnStartNotify) then
    FOnStartNotify();
  for var subscriber in FSubscribers do
    subscriber(value);
  if assigned(FOnEndNotify) then
    FOnEndNotify();
  FUnlockReader();
end;

procedure TPubSub.SetOnEndNotify(const Value: TProc);
begin
  FOnEndNotify := Value;
end;

procedure TPubSub.SetOnStartNotify(const Value: TProc);
begin
  FOnStartNotify := Value;
end;

procedure TPubSub.Subscribe(callback: TCallback);
begin
  FLockWriter();
  FSubscribers.Add(callback);
  FUnlockWriter();
end;

procedure TPubSub.Unsubscribe(callback: TCallback);
begin
  FLockWriter();
  FSubscribers.Remove(callback);
  FUnlockWriter();
end;

end.
