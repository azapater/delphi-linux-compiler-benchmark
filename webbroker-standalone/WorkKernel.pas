unit WorkKernel;

interface

// Fill+sum over a fixed 8192-int buffer, repeated Passes times.
// Independent stores plus a reduction. LLVM 20 can vectorize this;
// the older Linux compiler (LLVM 3.3) usually cannot.
//
// Passes = 400 is the comparison used in the blog measurements.
function BusyWork(Passes: Integer): Int64;

const
  CDefaultWork = 400;

implementation

const
  CWorkLen = 8192;

function BusyWork(Passes: Integer): Int64;
var
  I, R: Integer;
  A: TArray<Integer>;
  Sum: Int64;
begin
  if Passes <= 0 then
    Exit(0);

  SetLength(A, CWorkLen);
  Sum := 0;
  for R := 1 to Passes do
  begin
    for I := 0 to CWorkLen - 1 do
      A[I] := I * 17 + (R and 255);
    for I := 0 to CWorkLen - 1 do
      Sum := Sum + A[I];
  end;
  Result := Sum;
end;

end.
