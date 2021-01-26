program rwLock;

uses
  System.StartUpCopy,
  FMX.Forms,
  rwLockMain in 'rwLockMain.pas' {frmRWLockMain},
  PublishSubscribe in 'PublishSubscribe.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmRWLockMain, frmRWLockMain);
  Application.Run;
end.
