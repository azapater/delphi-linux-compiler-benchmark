program Standalone;
{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  IPPeerServer,
  IPPeerAPI,
  IdHTTPWebBrokerBridge,
  Web.WebReq,
  Web.WebBroker,
  WebModuleUnit1 in 'WebModuleUnit1.pas' {WebModule1: TWebModule},
  WorkKernel in 'WorkKernel.pas';

{$R *.res}

function BindPort(APort: Integer): Boolean;
var
  LTestServer: IIPTestServer;
begin
  Result := True;
  try
    LTestServer := PeerFactory.CreatePeer('', IIPTestServer) as IIPTestServer;
    LTestServer.TestOpenPort(APort, nil);
  except
    Result := False;
  end;
end;

procedure RunServer(APort: Integer);
var
  LServer: TIdHTTPWebBrokerBridge;
begin
  if not BindPort(APort) then
  begin
    Writeln('Port ', APort, ' is already in use.');
    Exit;
  end;

  LServer := TIdHTTPWebBrokerBridge.Create(nil);
  try
    LServer.DefaultPort := APort;
    LServer.MaxConnections := 0;
    LServer.ListenQueue := 500;
    LServer.KeepAlive := False;
    LServer.Bindings.Clear;
    LServer.Active := True;

    Writeln('CompilerVersion: ', DemoCompilerVersion);
    Writeln('RTL: ', DemoRtlVersion);
    Writeln('Started: ', DemoStarted);
    Writeln('Listening on port ', APort);
    Writeln('Default work=', CDefaultWork, '. Pass ?work=0 to skip CPU work.');
    Writeln('  http://<linux-host>:', APort, '/');
    Writeln('  http://<linux-host>:', APort, '/api/test?work=', CDefaultWork);
    Writeln('Press ENTER to stop.');
    Readln;

    LServer.Active := False;
    LServer.Bindings.Clear;
  finally
    LServer.Free;
  end;
end;

begin
  try
    if WebRequestHandler <> nil then
      WebRequestHandler.WebModuleClass := WebModuleClass;
    RunServer(8081);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end
end.
