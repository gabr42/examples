unit rwLockMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants, System.Threading,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.StdCtrls,
  PublishSubscribe, FMX.Edit, FMX.Layouts, FMX.ListBox;

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
    procedure btnBenchmarkClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    FMaxPubConcurrency: int64;
    FNumSubscriptions: integer;
    FNumNotifications: integer;
    FPubConcurrency: integer;
    FPublishers: TArray<ITask>;
    FPubSub: TPubSub;
    FSubscribers: TArray<ITask>;
    FStopBenchmark: boolean;
  strict protected
    function GetScheme: TPubSub.TLockingScheme;
    procedure MeasureRawSpeed;
    procedure PrimeThreadPool(numThreads: integer);
    procedure Publisher;
    procedure Subscriber;
  public
  end;

var
  frmRWLockMain: TfrmRWLockMain;

implementation

uses
  System.SyncObjs, System.Diagnostics;

{$R *.fmx}

procedure TfrmRWLockMain.btnBenchmarkClick(Sender: TObject);
begin
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
  for var i := Low(FPublishers) to High(FPublishers) do
    FPublishers[i] := TTask.Run(Publisher);
  SetLength(FSubscribers, inpNumSub.Text.ToInteger);
  for var i := Low(FSubscribers) to High(FSubscribers) do
    FSubscribers[i] := TTask.Run(Subscriber);

  Timer1.Interval := 1000 * inpDuration.Text.ToInteger;
  Timer1.Enabled := true;
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
end;

procedure TfrmRWLockMain.PrimeThreadPool(numThreads: integer);
var
  tasks: TArray<ITask>;
  numRunning: int64;
begin
  SetLength(tasks, numThreads);
  TThreadPool.Default.SetMinWorkerThreads(numThreads);

  numRunning := 0;
  for var i := Low(tasks) to High(tasks) do
    tasks[i] := TTask.Run(
      procedure
      begin
        TInterlocked.Increment(numRunning);
        while TInterlocked.Read(numRunning) < Length(tasks) do
          Sleep(10);
      end);

  for var i := Low(tasks) to High(tasks) do
    tasks[i].Wait();
end;

procedure TfrmRWLockMain.Publisher;
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
end;

procedure TfrmRWLockMain.Subscriber;
var
  callback: TPubSub.TCallback;
  numSub: integer;
begin
  callback :=
    procedure (value: integer)
    begin
      var a: extended := 0;
      for var i := 1 to 10000 do
        a := cos(a);
    end;

  numSub := 0;
  while not FStopBenchmark do begin
    Sleep(10);
    FPubSub.Subscribe(callback);
    FPubSub.Unsubscribe(callback);
    Inc(numSub);
  end;

  AtomicIncrement(FNumSubscriptions, numSub);
end;

procedure TfrmRWLockMain.Timer1Timer(Sender: TObject);
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

  lbLog.Items.Add('Number of Subscribe/Unsubscribe calls: ' + FNumSubscriptions.ToString);
  lbLog.Items.Add('Number of Notify calls: ' + FNumNotifications.ToString);
  lbLog.Items.Add('Maximum level of Notify concurrency: ' + FMaxPubConcurrency.ToString);
  btnBenchmark.Enabled := true;
end;

end.
