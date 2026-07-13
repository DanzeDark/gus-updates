Option Explicit

Dim shell, ps, command

Set shell = CreateObject("WScript.Shell")

ps = "$ErrorActionPreference='Stop';Add-Type -AssemblyName System.Windows.Forms;$base='https://danzedark.github.io/gus-updates';$url=$base+'/Install-Gus-Web.ps1';$tmp=Join-Path ([IO.Path]::GetTempPath()) ('Install-Gus-Web_'+[Guid]::NewGuid().ToString('N')+'.ps1');try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing;& $tmp -BaseUrl $base}catch{[System.Windows.Forms.MessageBox]::Show(('Gus setup failed:'+[Environment]::NewLine+$_.Exception.Message),'Gus setup','OK','Error')|Out-Null}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}"
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command " & Chr(34) & ps & Chr(34)

shell.Run command, 0, False
