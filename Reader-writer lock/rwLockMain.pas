unit rwLockMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants, System.Threading,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Edit, FMX.Layouts, FMX.ListBox,
  PublishSubscribe;

type
  TfrmRWLockMain = class(TForm)
    btnBenchmark: TButton;
    lblNumSub: TLabel;
    inpNumSub: TEdit;
    lblDuration: TLabel;
    inpDuration: TEdit;
    Timer1: TTimer;
    lbLog: TListBox;
    lblLocking: TLabel;
    cbxLockingScheme: TComboBox;
    lblNumPublishers: TLabel;
    inpNumPub: TEdit;
    btnCopyToClipboard: TButton;
    procedure btnBenchmarkClick(Sender: TObject);
    procedure btnCopyToClipboardClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    FMaxPubConcurrency: int64;
    FNumSubscriptions: integer;
    FNumNotifications: integer;
    FPubConcurrency: integer;
    FPublishers: TArray<ITask>;
    FPubNotifications: TArray<integer>;
    FPubSub: TPubSub;
    FSubscribers: TArray<ITask>;
    FStopBenchmark: boolean;
    FTestPool: TThreadPool;
  strict protected
    function GetScheme: TPubSub.TLockingScheme;
    procedure MeasureRawSpeed;
    procedure PrimeThreadPool(numThreads: integer);
    procedure Publisher(idx: integer);
    procedure Subscriber;
  public
  end;

var
  frmRWLockMain: TfrmRWLockMain;

implementation

uses
  System.SyncObjs, System.Diagnostics,
  FMX.Clipboard, FMX.Platform;

{$R *.fmx}

procedure TfrmRWLockMain.btnBenchmarkClick(Sender: TObject);

  function MakePublisher(idx: integer): TProc;
  begin
    Result :=
      procedure
      begin
        Publisher(idx);
      end;
  end;

begin
  FTestPool := TThreadPool.Create;

  lbLog.Items.Add('Benchmarking ' + cbxLockingScheme.Items[cbxLockingScheme.ItemIndex]);
  btnBenchmark.Enabled := false;
  Application.ProcessMessages;

  MeasureRawSpeed;

  FStopBenchmark := false;
  FNumSubscriptions := 0;
  FNumNotifications := 0;
  FMaxPubConcurrency := 0;
  FPubConcurrency := 0;

  PrimeThreadPool(inpNumPub.Text.ToInteger + inpNumSub.Text.ToInteger);

  FPubSub := TPubSub.Create(GetScheme);
  FPubSub.OnStartNotify :=
    procedure
    var
      numPub: integer;
      maxPub: integer;
    begin
      numPub := TInterlocked.Increment(FPubConcurrency);
      repeat
        maxPub := TInterlocked.Read(FMaxPubConcurrency);
      until (numPub <= maxPub)
             or (TInterlocked.CompareExchange(FMaxPubConcurrency, numPub, maxPub) = maxPub);
    end;
  FPubSub.OnEndNotify :=
    procedure
    begin
      TInterlocked.Decrement(FPubConcurrency);
    end;

  SetLength(FPublishers, inpNumPub.Text.ToInteger);
  SetLength(FPubNotifications, Length(FPublishers));
  for var i := Low(FPublishers) to High(FPublishers) do
    FPublishers[i] := TTask.Run(MakePublisher(i), FTestPool);
  SetLength(FSubscribers, inpNumSub.Text.ToInteger);
  for var i := Low(FSubscribers) to High(FSubscribers) do
    FSubscribers[i] := TTask.Run(Subscriber, FTestPool);

  Timer1.Interval := 1000 * inpDuration.Text.ToInteger;
  Timer1.Enabled := true;
end;

procedure TfrmRWLockMain.btnCopyToClipboardClick(Sender: TObject);
var
  Svc: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Svc.SetClipboard(lbLog.Items.Text);
end;

function TfrmRWLockMain.GetScheme: TPubSub.TLockingScheme;
begin
  case cbxLockingScheme.ItemIndex of
    0: Result := lockNone;
    1: Result := lockCS;
    2: Result := lockMonitor;
    3: Result := lockMREW;
    4: Result := lockLightweightMREW;
    else raise Exception.Create('Unknown locking scheme');
  end;
end;

procedure TfrmRWLockMain.MeasureRawSpeed;
var
  sw: TStopwatch;
  cntRead: integer;
  cntWrite: integer;
begin
  if cbxLockingScheme.ItemIndex < 1 then
    Exit;

  cntRead := 0;
  cntWrite := 0;
  case cbxLockingScheme.ItemIndex of
    1: // critical section
      begin
        var cs := TCriticalSection.Create;
        try
          sw := TStopwatch.StartNew;
          while sw.ElapsedMilliseconds < 1000 do begin
            cs.Acquire;
            cs.Release;
            Inc(cntRead);
          end;
        finally FreeAndNil(cs); end;
      end;
    2: // TMonitor
      begin
        sw := TStopwatch.StartNew;
        while sw.ElapsedMilliseconds < 1000 do begin
          MonitorEnter(Self);
          MonitorExit(Self);
          Inc(cntRead);
        end;
      end;
    3: // TMREWSync
      begin
        var mrew := TMREWSync.Create;
        try
          sw := TStopwatch.StartNew;
          while sw.ElapsedMilliseconds < 1000 do begin
            mrew.BeginRead;
            mrew.EndRead;
            Inc(cntRead);
          end;
          sw := TStopwatch.StartNew;
          while sw.ElapsedMilliseconds < 1000 do begin
            mrew.BeginWrite;
            mrew.EndWrite;
            Inc(cntWrite);
          end;
        finally FreeAndNil(mrew); end;
      end;
    4: // TLightweightMREW
      begin
        var mrew: TLightweightMREW;
        sw := TStopwatch.StartNew;
        while sw.ElapsedMilliseconds < 1000 do begin
          mrew.BeginRead;
          mrew.EndRead;
          Inc(cntRead);
        end;
        sw := TStopwatch.StartNew;
        while sw.ElapsedMilliseconds < 1000 do begin
          mrew.BeginWrite;
          mrew.EndWrite;
          Inc(cntWrite);
        end;
    end;
  end;

  if cntWrite = 0 then
    lbLog.Items.Add('Read/write: ' + cntRead.ToString + '/sec')
  else
    lbLog.Items.Add('Read: ' + cntRead.ToString + '/sec, write: ' + cntWrite.ToString + '/sec');
  Application.ProcessMessages;
end;

procedure TfrmRWLockMain.PrimeThreadPool(numThreads: integer);
var
  tasks: TArray<ITask>;
  numRunning: int64;
begin
  FTestPool.SetMaxWorkerThreads(numThreads+2);
  FTestPool.SetMinWorkerThreads(numThreads);

  SetLength(tasks, numThreads);

  numRunning := 0;
  for var i := Low(tasks) to High(tasks) do
    tasks[i] := TTask.Run(
      procedure
      begin
        TInterlocked.Increment(numRunning);
        while TInterlocked.Read(numRunning) < Length(tasks) do
          Sleep(10);
      end,
      FTestPool);

  for var i := Low(tasks) to High(tasks) do
    tasks[i].Wait();
end;

procedure TfrmRWLockMain.Publisher(idx: integer);
var
  id: integer;
begin
  id := 0;
  while not FStopBenchmark do begin
    Sleep(0);
    Inc(id);
    FPubSub.Notify(id);
  end;
  AtomicIncrement(FNumNotifications, id);
  FPubNotifications[idx] := id;
end;

procedure TfrmRWLockMain.Subscriber;
var
  callback: TPubSub.TCallback;
  numSub: integer;
begin
  callback :=
    procedure (value: integer)
    begin
      Sleep(50);
    end;

  numSub := 0;
  while not FStopBenchmark do begin
    FPubSub.Subscribe(callback);
    Sleep(10);
    FPubSub.Unsubscribe(callback);
    Inc(numSub);
  end;

  AtomicIncrement(FNumSubscriptions, numSub);
end;

procedure TfrmRWLockMain.Timer1Timer(Sender: TObject);
var
  i: integer;
  s: string;
begin
  Timer1.Enabled := false;
  FStopBenchmark := true;

  for var publisher in FPublishers do
    publisher.Wait();
  FPublishers := nil;
  for var subscriber in FSubscribers do
    subscriber.Wait();
  FSubscribers := nil;
  FreeAndNil(FPubSub);

  s := '';
  for i in FPubNotifications do
    s := s + i.ToString + ' ';

  lbLog.Items.Add('Number of Subscribe/Unsubscribe calls: ' + FNumSubscriptions.ToString);
  lbLog.Items.Add('Number of Notify calls: ' + FNumNotifications.ToString);
  lbLog.Items.Add('Notify calls per thread: ' + s);
  lbLog.Items.Add('Maximum level of Notify concurrency: ' + FMaxPubConcurrency.ToString);
  btnBenchmark.Enabled := true;

  FreeAndNil(FTestPool);
end;

end.
