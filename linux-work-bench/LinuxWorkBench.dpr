program LinuxWorkBench;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Diagnostics,
  WorkKernel in 'WorkKernel.pas';

function RtlVersionText: string;
begin
  Result := IntToStr(GetRTLVersion shr 8) + '.' + IntToStr(GetRTLVersion and $FF);
end;

procedure RunBench(Passes, Repeats: Integer);
var
  Sw: TStopwatch;
  I: Integer;
  Checksum: Int64;
  TotalMs, PerMs: Double;
begin
  Checksum := 0;
  Sw := TStopwatch.StartNew;
  for I := 1 to Repeats do
    Checksum := BusyWork(Passes);
  Sw.Stop;

  TotalMs := Sw.Elapsed.TotalMilliseconds;
  if Repeats > 0 then
    PerMs := TotalMs / Repeats
  else
    PerMs := 0;

  Writeln(Format('  passes=%-5d  repeats=%-5d  checksum=%d',
    [Passes, Repeats, Checksum]));
  Writeln(Format('  total=%0.1f ms   per call=%0.3f ms', [TotalMs, PerMs]));
end;

var
  Passes, Repeats: Integer;
begin
  try
    Passes := CDefaultWork;
    Repeats := 200;
    if ParamCount >= 1 then
      Passes := StrToIntDef(ParamStr(1), CDefaultWork);
    if ParamCount >= 2 then
      Repeats := StrToIntDef(ParamStr(2), 200);
    if Passes < 1 then
      Passes := CDefaultWork;
    if Repeats < 1 then
      Repeats := 1;

{$IFDEF LINUX}
    Writeln('CompilerVersion ', FormatFloat('0.0', CompilerVersion),
      '   RTL ', RtlVersionText, '   Target Linux64');
{$ELSE}
    Writeln('CompilerVersion ', FormatFloat('0.0', CompilerVersion),
      '   RTL ', RtlVersionText, '   Target not Linux');
    Writeln('Rebuild for Linux64 / Release and run via PAServer.');
{$ENDIF}
{$IFDEF DEBUG}
    Writeln('WARNING: this is a Debug build. Use Release or the numbers are noise.');
{$ENDIF}
    Writeln;
    Writeln('Warmup...');
    BusyWork(Passes);
    Writeln('Go.');
    Writeln;
    RunBench(Passes, 1);
    Writeln;
    RunBench(Passes, Repeats);
    Writeln;
    Writeln('Build this twice (13.1 and 13.2), Linux64, Release.');
    Writeln('Both binaries must print the same checksum. Compare "per call" ms.');
    Writeln('Optional args: LinuxWorkBench [passes] [repeats]   default 400 200');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
