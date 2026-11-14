{ ============================================================================
  Elospeed StemPacker  -  Hell oder dunkel wie StemMaker
  ----------------------------------------------------------------------------
  Liest "Design" aus StemMaker.ini ([Main] Design=auto|hell|dunkel), zuerst
  im StemMaker-Ordner, dann in %APPDATA%\StemMaker. Fehlt die Angabe
  (StemPacker allein), gilt Automatisch = wie Windows.

  Wie in StemMaker (uDesign) färbt die Bibliothek metadarkstyle (Ordner
  ..\..\darkstyle) Fenster, Knöpfe, Listen, Menüs und die Titelleiste um.
  Das geht nur einmal beim Start, vor dem ersten Fenster. Braucht Windows 10
  ab 1809; ältere Windows und Wine bleiben hell.
  ============================================================================ }
unit uPackDesign;

{$mode objfpc}{$H+}

interface

{ einmal beim Start aufrufen, vor Application.Initialize }
procedure PackDesignAnwenden;

implementation

uses
  SysUtils, IniFiles, uLang, uStatusDraw
  {$IFDEF LCLWIN32}
  , uDarkStyleParams, uMetaDarkStyle, uDarkStyleSchemes
  {$ENDIF};

function DesignWert: string;
var
  Ini: TIniFile;
  IniName: string;
  i: Integer;
begin
  Result := '';
  for i := 1 to 2 do
  begin
    if i = 1 then
      IniName := AppBaseDir + 'StemMaker.ini'
    else
      IniName := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA')) +
        'StemMaker' + PathDelim + 'StemMaker.ini';
    if not FileExists(IniName) then Continue;
    try
      Ini := TIniFile.Create(IniName);
      try
        Result := LowerCase(Trim(Ini.ReadString('Main', 'Design', '')));
      finally
        Ini.Free;
      end;
    except
      Result := '';
    end;
    if Result <> '' then Break;
  end;
end;

procedure PackDesignAnwenden;
{$IFDEF LCLWIN32}
var
  W: string;
{$ENDIF}
begin
  {$IFDEF LCLWIN32}
  W := DesignWert;
  if W = 'hell' then
    PreferredAppMode := pamForceLight
  else if W = 'dunkel' then
    PreferredAppMode := pamForceDark
  else
    PreferredAppMode := pamAllowDark;     // wie Windows
  try
    ApplyMetaDarkStyle(DefaultDark);
  except
    { sollte nie passieren - dann eben hell }
  end;
  DunklesDesign := IsDarkModeEnabled;
  {$ENDIF}
end;

end.
