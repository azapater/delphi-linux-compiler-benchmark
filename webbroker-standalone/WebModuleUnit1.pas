unit WebModuleUnit1;

interface

uses
  System.SysUtils,
  System.Classes,
  Web.HTTPApp,
  System.JSON,
  WorkKernel;

function DemoRtlVersion: string;
function DemoCompilerVersion: string;
function DemoStarted: string;

type
  TWebModule1 = class(TWebModule)
    procedure WebModule1DefaultHandlerAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebModule1ApiTestAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
  end;

var
  WebModuleClass: TComponentClass = TWebModule1;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

var
  DemoStartedAt: string;

function DemoRtlVersion: string;
begin
  Result := IntToStr(GetRTLVersion shr 8) + '.' + IntToStr(GetRTLVersion and $FF);
end;

function DemoCompilerVersion: string;
begin
  Result := FormatFloat('0.0', CompilerVersion);
end;

function DemoStarted: string;
begin
  Result := DemoStartedAt;
end;

procedure TWebModule1.WebModule1DefaultHandlerAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
  Response.ContentType := 'text/html; charset=utf-8';
  Response.Content :=
    '<!DOCTYPE html><html><head><meta charset="utf-8">' +
    '<title>WebBroker standalone</title></head><body>' +
    '<p>CompilerVersion: ' + DemoCompilerVersion +
    '<br>RTL: ' + DemoRtlVersion +
    '<br>Started: ' + DemoStarted + '</p>' +
    '<p><a href="/api/test?work=' + IntToStr(CDefaultWork) +
    '">/api/test?work=' + IntToStr(CDefaultWork) + '</a></p>' +
    '</body></html>';
  Handled := True;
end;

procedure TWebModule1.WebModule1ApiTestAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
  JSONObj: TJSONObject;
  Work: Integer;
  Checksum: Int64;
begin
  Response.ContentType := 'application/json';
  // No query uses the default CPU workload. Pass ?work=0 to skip it.
  if Request.QueryFields.Values['work'] = '' then
    Work := CDefaultWork
  else
    Work := StrToIntDef(Request.QueryFields.Values['work'], 0);
  Checksum := BusyWork(Work);

  JSONObj := TJSONObject.Create;
  try
    JSONObj.AddPair('status', 'ok');
    JSONObj.AddPair('timestamp', FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    JSONObj.AddPair('path', Request.PathInfo);
    JSONObj.AddPair('method', Request.Method);
    JSONObj.AddPair('compiler_version', DemoCompilerVersion);
    JSONObj.AddPair('rtl', DemoRtlVersion);
    JSONObj.AddPair('started', DemoStarted);
    JSONObj.AddPair('work', IntToStr(Work));
    JSONObj.AddPair('checksum', IntToStr(Checksum));

    Response.Content := JSONObj.ToString;
  finally
    JSONObj.Free;
  end;

  Handled := True;
end;

initialization
  DemoStartedAt := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);

end.
