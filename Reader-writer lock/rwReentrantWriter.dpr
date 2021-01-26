program rwReentrantWriter;

uses
  System.StartUpCopy,
  FMX.Forms,
  rwReentrantMain in 'rwReentrantMain.pas' {frmReentrantMain};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmReentrantMain, frmReentrantMain);
  Application.Run;
end.
