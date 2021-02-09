program rwReentrantWriter;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils, System.Threading, System.Diagnostics, System.Classes, System.SyncObjs,
  LightweightMREWEx,
  Synch in 'Synch.pas';

procedure TestIsReentrant;
var
  rw: TLightweightMREWEx;
begin
  // Simple test checking whether BeginWrite is actually reentrant.

  rw.BeginWrite;
  rw.BeginWrite; // should succeed; should not hang or crash
  rw.EndWrite;
  rw.BeginWrite;
  rw.EndWrite;
  rw.EndWrite;
  Write('.');
end;

procedure TestTryBeginWrite;
var
  rw: TLightweightMREWEx;
begin
  // Simple test checking is TryBeginWrite also works.

  Assert(rw.TryBeginWrite);
  Assert(rw.TryBeginWrite);
  rw.EndWrite;
  Assert(rw.TryBeginWrite);
  rw.EndWrite;
  rw.EndWrite;
  Write('.');
end;

procedure TestReadAfterWrite;
var
  rw: TLightweightMREWEx;
begin
  // Tests whether BeginRead after BeginWrite works ok.

  rw.BeginWrite;
  Assert(not rw.TryBeginRead);
  rw.BeginWrite;
  Assert(not rw.TryBeginRead);
  rw.EndWrite;
  Assert(not rw.TryBeginRead);
  rw.EndWrite;
  Assert(rw.TryBeginRead);
  Write('.');
end;

procedure TestReadAfterTryWrite;
var
  rw: TLightweightMREWEx;
begin
  // Tests whether BeginRead after TryBeginWrite works ok.

  Assert(rw.TryBeginWrite);
  Assert(not rw.TryBeginRead);
  Assert(rw.TryBeginWrite);
  Assert(not rw.TryBeginRead);
  rw.EndWrite;
  Assert(not rw.TryBeginRead);
  rw.EndWrite;
  Assert(rw.TryBeginRead);
  Write('.');
end;

procedure TestMTReentrant;
var
  rw: TLightweightMREWEx;
  s: TSynch;
  t1, t2: ITask;
begin
  // Test reentrancy with multiple threads

  s := TSynch.Create;

  t1 := TTask.Run(
    procedure
    begin
      s.SnW('t1', 'run1');
      rw.BeginWrite;
      s.SnW('run2', 'ok2');
      rw.EndWrite;
      s.Signal('cont2');
    end);
  t2 := TTask.Run(
    procedure
    begin
      s.SnW('t2', 'run2');
      Assert(not rw.TryBeginWrite);
      s.SnW('ok2', 'cont2');
      Assert(rw.TryBeginWrite);
    end);

  s.WaitFor('t1'); s.WaitFor('t2');
  s.Signal('run1');

  t1.Wait();
  t2.Wait();

  FreeAndNil(s);

  Write('.');
end;

procedure StressTestMT;
const
  CNumTasks = 10;
  CTestDuration = 10 {sec};
var
  numWriters: integer;
  rw: TLightweightMREWEx;
  tasks: TArray<ITask>;
  writes: TArray<integer>;

  function MakeTask(idx: integer): TProc;
  begin
    Result :=
      procedure
      var
        sw: TStopwatch;
      begin
        sw := TStopwatch.StartNew;
        while sw.ElapsedMilliseconds < (CTestDuration * 1000) do begin
          rw.BeginWrite;
          Assert(AtomicIncrement(numWriters) = 1);
          writes[idx] := writes[idx] + 1;
          rw.BeginWrite;
          var a: real := 1;
          for var i := 1 to Random(1000) do
            a := Cos(a);
          rw.EndWrite;
          Assert(AtomicDecrement(numWriters) = 0);
          rw.EndWrite;
        end;
      end;
  end;

begin
  // Stress test reentrant BeginWrite
  // Possible failure points:
  // - lockup
  // - exception
  // - two threads acquire lock for writing at the same time

  numWriters := 0;

  SetLength(writes, CNumTasks);
  SetLength(tasks, CNumTasks);
  for var i := Low(tasks) to High(tasks) do
    tasks[i] := TTask.Create(MakeTask(i));

  for var i := Low(tasks) to High(tasks) do
    tasks[i].Start;

  for var i := Low(tasks) to High(tasks) do
    tasks[i].Wait;

  for var i := Low(tasks) to High(tasks) do
    tasks[i] := nil;

  for var i := Low(writes) to High(writes) do
    Write(writes[i], ' ');
  Writeln;
end;

procedure StressTestMTTry;
const
  CNumTasks = 10;
  CTestDuration = 10 {sec};
var
  numWriters: integer;
  rw: TLightweightMREWEx;
  tasks: TArray<ITask>;
  writes: TArray<integer>;

  function MakeTask(idx: integer): TProc;
  begin
    Result :=
      procedure
      var
        sw: TStopwatch;
      begin
        sw := TStopwatch.StartNew;
        while sw.ElapsedMilliseconds < (CTestDuration * 1000) do begin
          {$IF defined(LINUX) or defined(ANDROID)}
          if rw.TryBeginWrite(Random(10)) then
          {$ELSE}
          if rw.TryBeginWrite then
          {$ENDIF}
          begin
            Assert(AtomicIncrement(numWriters) = 1);
            writes[idx] := writes[idx] + 1;
            {$IF defined(LINUX) or defined(ANDROID)}
            Assert(rw.TryBeginWrite(Random(10))
            );
            {$ELSE}
            Assert(rw.TryBeginWrite);
            {$ENDIF}
            var a: real := 1;
            for var i := 1 to Random(1000) do
              a := Cos(a);
            rw.EndWrite;
            Assert(AtomicDecrement(numWriters) = 0);
            rw.EndWrite;
          end;
        end;
      end;
  end;

begin
  // Stress test reentrant TryBeginWrite with timeout
  // Possible failure points:
  // - lockup
  // - exception
  // - two threads acquire lock for writing at the same time

  numWriters := 0;

  SetLength(writes, CNumTasks);
  SetLength(tasks, CNumTasks);
  for var i := Low(tasks) to High(tasks) do
    tasks[i] := TTask.Create(MakeTask(i));

  for var i := Low(tasks) to High(tasks) do
    tasks[i].Start;

  for var i := Low(tasks) to High(tasks) do
    tasks[i].Wait;

  for var i := Low(tasks) to High(tasks) do
    tasks[i] := nil;

  for var i := Low(writes) to High(writes) do
    Write(writes[i], ' ');
  Writeln;
end;

begin
  try
    TestIsReentrant;
    TestTryBeginWrite;
    TestReadAfterWrite;
    TestReadAfterTryWrite;
    TestMTReentrant;
    Writeln;
    StressTestMT;
    StressTestMTTry;
    Writeln('OK');
    Readln;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
