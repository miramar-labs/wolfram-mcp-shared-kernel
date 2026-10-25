# Wolfram MCP, production installer. Run from an elevated PowerShell 5.1 console.
# Modes: install (default), status, uninstall. Does not modify Mathematica/AgentTools.
param(
    [ValidateSet('Install','Status','Uninstall')][string]$Mode = 'Install',
    [Parameter(Mandatory=$false)][string]$DgxAddress,
    [Parameter(Mandatory=$false)][string]$MsiAddress,
    [Parameter(Mandatory=$false)][string]$DgxSshTarget,
    [Parameter(Mandatory=$false)][string]$TunnelId,
    [int]$Port = 8765,
    [string]$WolframExe = 'C:\Program Files\Wolfram Research\Wolfram\15.0\wolfram.exe',
    [string]$TunnelExe,
    [string]$PythonDir
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'WolframMCP'
$runtime = Join-Path $root 'runtime'
$logdir = Join-Path $root 'logs'
$nodeSrc = 'C:\Program Files\nodejs\node.exe'
$npm = 'C:\Program Files\nodejs\npm.cmd'
$node = Join-Path $runtime 'node-wolfram.exe'
$proxy = Join-Path $runtime 'node_modules\mcp-proxy\dist\bin\mcp-proxy.mjs'
$wolfram = $WolframExe
$tunnel = if ($TunnelExe) { $TunnelExe } else { Join-Path $root 'tunnel\tunnel-client-runtime.exe' }
$pythonRoot = if ($PythonDir) { $PythonDir } else { Join-Path $env:USERPROFILE 'miniforge3' }
$pythonw = Join-Path $pythonRoot 'pythonw.exe'
$python = Join-Path $pythonRoot 'python.exe'
$supervisor = Join-Path $root 'supervisor.py'
$task = 'Wolfram MCP Unified'
$firewall = 'Wolfram MCP - DGX only'
$dgxHost = $DgxSshTarget

function Require-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run PowerShell as Administrator.' }
}
function Get-ProcStatus {
  Get-CimInstance Win32_Process | Where-Object {
    ($_.CommandLine -like ('*' + $root + '*') -and $_.Name -in @('pythonw.exe','node-wolfram.exe','tunnel-client-runtime.exe')) -or
    ($_.Name -eq 'wolfram.exe' -and $_.CommandLine -like '*Wolfram`AgentTools`StartMCPServer*')
  } | Select-Object ProcessId,ParentProcessId,Name,CommandLine
}
function Report {
  Write-Host '=== Wolfram MCP status ==='
  Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Select-Object TaskName,State
  Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,OwningProcess
  Get-ProcStatus | Select-Object ProcessId,ParentProcessId,Name | Format-Table -AutoSize
  Get-NetFirewallRule -DisplayName $firewall -ErrorAction SilentlyContinue | Select-Object DisplayName,Enabled,Action,Profile
  try {
    $response = Invoke-WebRequest -Uri 'http://127.0.0.1:18766/readyz' -UseBasicParsing -TimeoutSec 5
    Write-Host ('Tunnel readiness HTTP ' + [int]$response.StatusCode)
  } catch { Write-Warning ('Tunnel readiness unavailable: ' + $_.Exception.Message) }
  Write-Host ('Logs: ' + $logdir)
}
if ($Mode -eq 'Status') { Report; exit 0 }
Require-Admin
if ($Mode -eq 'Uninstall') {
  Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
  Get-NetFirewallRule -DisplayName $firewall -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  # Do not delete running processes or unrelated Wolfram sessions.
  Write-Host 'Task and scoped firewall rule removed.'
  Write-Host ('Installed files retained for inspection: ' + $root)
  Write-Host 'If any MCP-owned child remains, reboot before deleting the directory.'
  exit 0
}

# Validate parameters before modifying persistent system state.
foreach ($setting in @(@('DgxAddress',$DgxAddress),@('MsiAddress',$MsiAddress),@('DgxSshTarget',$DgxSshTarget),@('TunnelId',$TunnelId))) {
  if ([string]::IsNullOrWhiteSpace([string]$setting[1])) { throw ('Required for install: -' + $setting[0]) }
}
if ($TunnelId -notmatch '^tunnel_[A-Za-z0-9]+$') { throw 'Unexpected tunnel ID format.' }
foreach ($value in @($DgxAddress,$MsiAddress)) {
  $valid = $null
  if (-not [System.Net.IPAddress]::TryParse($value,[ref]$valid) -or $valid.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { throw "Expected IPv4 address: $value" }
}
if ($DgxSshTarget -notmatch '^[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+$') { throw 'Use a simple user@host SSH target, without shell metacharacters.' }
if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Port must be 1024..65535.' }
# Validate before modifying persistent system state.
foreach ($path in @($nodeSrc,$npm,$wolfram,$tunnel,$pythonw,$python)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Required component missing: $path" }
}
$key = [Environment]::GetEnvironmentVariable('CONTROL_PLANE_API_KEY','User')
if ([string]::IsNullOrWhiteSpace($key)) { throw 'CONTROL_PLANE_API_KEY is absent in the Windows User environment. No changes made.' }
$key = $null
if (@(Get-NetFirewallProfile | Where-Object { -not $_.Enabled }).Count -gt 0) { throw 'All Windows firewall profiles must remain enabled.' }
if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) { throw "Port $Port already used; refusing to replace existing listener." }
if (Get-NetTCPConnection -State Listen -LocalPort 18765 -ErrorAction SilentlyContinue) { throw 'Temporary Wolfram MCP test is still running on port 18765. Stop it before installing.' }
if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) { throw 'Production task already exists. Use -Mode Status, then uninstall before reinstalling.' }

New-Item -ItemType Directory -Force -Path $runtime,$logdir | Out-Null
Write-Host 'Installing pinned mcp-proxy@6.7.21 (no global npm modifications)...'
& $npm install --prefix $runtime --save-exact --no-audit --no-fund 'mcp-proxy@6.7.21'
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $proxy)) { throw 'Proxy installation failed; no scheduled task added.' }
# A dedicated Node binary path lets Windows firewall rules target only the MCP app.
Copy-Item -LiteralPath $nodeSrc -Destination $node -Force
& $node $proxy --version
if ($LASTEXITCODE -ne 0) { throw 'Pinned proxy verification failed.' }

# The supervisor uses a Windows Job Object to stop both children when the supervisor exits.
# It loads the already existing User-environment key at runtime, without copying it to disk.
$py = @'
import ctypes, ctypes.wintypes, os, pathlib, subprocess, sys, time, traceback, winreg
BASE = pathlib.Path(__file__).resolve().parent
LOG = BASE / "logs"
LOG.mkdir(parents=True, exist_ok=True)
NODE = BASE / "runtime" / "node-wolfram.exe"
PROXY = BASE / "runtime" / "node_modules" / "mcp-proxy" / "dist" / "bin" / "mcp-proxy.mjs"
TUNNEL = pathlib.Path(__TUNNEL_EXE__)
WOLFRAM = __WOLFRAM_EXE__
ID = __TUNNEL_ID__
PORT = __MCP_PORT__
CREATE_NO_WINDOW = 0x08000000
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000

# JOBOBJECT_BASIC_LIMIT_INFORMATION + IO_COUNTERS + memory fields, Windows x64.
class BASIC(ctypes.Structure):
    _fields_ = [("PerProcessUserTimeLimit",ctypes.c_int64),("PerJobUserTimeLimit",ctypes.c_int64),
                ("LimitFlags",ctypes.c_uint32),("MinimumWorkingSetSize",ctypes.c_size_t),
                ("MaximumWorkingSetSize",ctypes.c_size_t),("ActiveProcessLimit",ctypes.c_uint32),
                ("Affinity",ctypes.c_size_t),("PriorityClass",ctypes.c_uint32),
                ("SchedulingClass",ctypes.c_uint32)]
class IO(ctypes.Structure):
    _fields_ = [("ReadOperationCount",ctypes.c_uint64),("WriteOperationCount",ctypes.c_uint64),
                ("OtherOperationCount",ctypes.c_uint64),("ReadTransferCount",ctypes.c_uint64),
                ("WriteTransferCount",ctypes.c_uint64),("OtherTransferCount",ctypes.c_uint64)]
class EXTENDED(ctypes.Structure):
    _fields_ = [("BasicLimitInformation",BASIC),("IoInfo",IO),
                ("ProcessMemoryLimit",ctypes.c_size_t),("JobMemoryLimit",ctypes.c_size_t),
                ("PeakProcessMemoryUsed",ctypes.c_size_t),("PeakJobMemoryUsed",ctypes.c_size_t)]
k = ctypes.WinDLL("kernel32", use_last_error=True)
k.CreateJobObjectW.restype = ctypes.c_void_p
k.CreateJobObjectW.argtypes = (ctypes.c_void_p,ctypes.c_wchar_p)
k.SetInformationJobObject.restype = ctypes.c_int
k.SetInformationJobObject.argtypes = (ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p,ctypes.c_uint32)
k.AssignProcessToJobObject.restype = ctypes.c_int
k.AssignProcessToJobObject.argtypes = (ctypes.c_void_p,ctypes.c_void_p)
k.CloseHandle.argtypes = (ctypes.c_void_p,)

def make_job():
    job = k.CreateJobObjectW(None,None)
    if not job: raise ctypes.WinError(ctypes.get_last_error())
    limits = EXTENDED()
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    if not k.SetInformationJobObject(job,9,ctypes.byref(limits),ctypes.sizeof(limits)):
        raise ctypes.WinError(ctypes.get_last_error())
    return job

def get_key():
    value = os.environ.get("CONTROL_PLANE_API_KEY")
    if value: return value
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as reg:
        value, _ = winreg.QueryValueEx(reg,"CONTROL_PLANE_API_KEY")
    if not value: raise RuntimeError("Missing CONTROL_PLANE_API_KEY")
    return value

def launch(args,env,job,logname):
    file = open(LOG / logname,"ab",buffering=0)
    p = subprocess.Popen(args, cwd=str(BASE), stdin=subprocess.DEVNULL,
                         stdout=file,stderr=subprocess.STDOUT,env=env,
                         creationflags=CREATE_NO_WINDOW)
    if not k.AssignProcessToJobObject(job,ctypes.c_void_p(int(p._handle))):
        p.kill()
        raise ctypes.WinError(ctypes.get_last_error())
    return p

def main():
    with open(LOG / "supervisor.log","a",encoding="utf-8",buffering=1) as trace:
        while True:
            job = None
            try:
                key = get_key()
                job = make_job()
                env = os.environ.copy()
                env.pop("MCP_PROXY_API_KEY",None)
                expression = 'PacletSymbol["Wolfram/AgentTools","Wolfram`AgentTools`StartMCPServer"][]'
                proxy_args = [str(NODE),str(PROXY),"--host","0.0.0.0","--port",str(PORT),
                              "--server","stream","--",WOLFRAM,"-run",expression,"-noinit","-noprompt"]
                proxy = launch(proxy_args,env,job,"proxy.log")
                # Wait for backend to listen. Using socket avoids overlapping Wolfram starts.
                import socket
                for _ in range(90):
                    if proxy.poll() is not None: raise RuntimeError("Proxy exited before readiness")
                    try:
                        with socket.create_connection(("127.0.0.1",PORT),timeout=1): break
                    except OSError: time.sleep(1)
                else: raise RuntimeError("Proxy startup timeout")
                env["CONTROL_PLANE_API_KEY"] = key
                env["CONTROL_PLANE_TUNNEL_ID"] = ID
                env["MCP_SERVER_URL"] = f"url=http://127.0.0.1:{PORT}/mcp,channel=main"
                env["HEALTH_LISTEN_ADDR"] = "127.0.0.1:18766"
                tunnel = launch([str(TUNNEL),"run"],env,job,"tunnel.log")
                trace.write("Started proxy and tunnel; watching children.\n")
                while proxy.poll() is None and tunnel.poll() is None: time.sleep(2)
                trace.write("One component exited; restarting both.\n")
            except BaseException as e:
                trace.write(f"Error: {type(e).__name__}: {e}\n")
                traceback.print_exc(file=trace)
            finally:
                if job: k.CloseHandle(job)
            time.sleep(6)
if __name__ == "__main__": main()
'@
# Safely populate script literals with JSON-style escaped string constants.
$py = $py.Replace('__WOLFRAM_EXE__', (ConvertTo-Json -Compress -InputObject $wolfram))
$py = $py.Replace('__TUNNEL_ID__', (ConvertTo-Json -Compress -InputObject $TunnelId))
$py = $py.Replace('__TUNNEL_EXE__', (ConvertTo-Json -Compress -InputObject $tunnel))
$py = $py.Replace('__MCP_PORT__', [string]$Port)
[System.IO.File]::WriteAllText($supervisor,$py,[System.Text.UTF8Encoding]::new($false))
& $python -m py_compile $supervisor
if ($LASTEXITCODE -ne 0) { throw 'Supervisor syntax check failed; no task registered.' }

# Firewall: only DGX IP may reach port. The copied Node binary has a distinct
# executable path from the Windows auto-generated broad Node.js Block rule.
if (Get-NetFirewallRule -DisplayName $firewall -ErrorAction SilentlyContinue) { throw 'Existing MCP firewall rule requires manual review.' }
New-NetFirewallRule -DisplayName $firewall -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol TCP -LocalPort $Port -LocalAddress $MsiAddress -RemoteAddress $DgxAddress -Program $node | Out-Null
try {
  $action = New-ScheduledTaskAction -Execute $pythonw -Argument ('"' + $supervisor + '"') -WorkingDirectory $root
  $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType S4U -RunLevel Limited
  $trigger = New-ScheduledTaskTrigger -AtStartup
  $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
  Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
  Start-ScheduledTask -TaskName $task
  $ready = $false
  for ($i=0; $i -lt 100; $i++) {
    Start-Sleep -Seconds 1
    try {
      $r=Invoke-WebRequest -Uri 'http://127.0.0.1:18766/readyz' -UseBasicParsing -TimeoutSec 2
      if ([int]$r.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
  }
  if (-not $ready) { throw 'Tunnel did not report ready. See logs. Rollback required.' }
  $body = @{jsonrpc='2.0';id=1;method='initialize';params=@{protocolVersion='2025-03-26';capabilities=@{};clientInfo=@{name='production-install';version='1'}}} | ConvertTo-Json -Compress -Depth 6
  $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/mcp" -Method Post -Body $body -ContentType 'application/json' -Headers @{Accept='application/json, text/event-stream'} -UseBasicParsing -TimeoutSec 30
  if ($resp.Content -notmatch 'WolframLanguage') { throw 'MCP Wolfram initialization failed' }
  $procs = @(Get-CimInstance Win32_Process -Filter "Name='wolfram.exe'" | Where-Object {$_.CommandLine -like '*StartMCPServer*'})
  if ($procs.Count -ne 1) { throw "Expected one MCP Wolfram process; observed $($procs.Count)." }
  Write-Host 'PASS: Unified service ready, one MCP Wolfram process, local MCP initialized.'
  Report
  Write-Host 'Checking DGX LAN access and adding both clients...'
  $dgxUrl = "http://${MsiAddress}:$Port/mcp"
  $remoteProbe = "curl --noproxy '*' -s -o /dev/null -w '%{http_code}' --max-time 10 '$dgxUrl'"
  $probe = & ssh.exe -o BatchMode=yes -o ConnectTimeout=8 $dgxHost $remoteProbe
  if ($LASTEXITCODE -ne 0 -or $probe -ne '400') { throw "DGX LAN probe failed. Expected HTTP 400 for unauthenticated GET; got '$probe'." }
  # The MCP registration is intentionally a simple native HTTP configuration.
  $script:codexAdded = $false
  $script:claudeAdded = $false
  $codexInstall = "codex mcp add wolfram-windows --url '$dgxUrl'"
  $claudeInstall = "claude mcp add --scope user --transport http wolfram-windows '$dgxUrl'"
  & ssh.exe -o BatchMode=yes -o ConnectTimeout=8 $dgxHost $codexInstall
  if ($LASTEXITCODE -ne 0) { throw 'DGX Codex registration failed.' }; $script:codexAdded = $true
  & ssh.exe -o BatchMode=yes -o ConnectTimeout=8 $dgxHost $claudeInstall
  if ($LASTEXITCODE -ne 0) { throw 'DGX Claude Code registration failed.' }; $script:claudeAdded = $true
  Write-Host 'PASS: DGX reached the service and both client registrations were added.'
  Write-Host 'A live tool call from each client is still the final acceptance test.' 
  Write-Host 'The current ChatGPT connector should reuse the existing tunnel ID.'
} catch {
  Write-Warning ('Install validation failed: ' + $_.Exception.Message)
  if ($script:codexAdded) { & ssh.exe -o BatchMode=yes -o ConnectTimeout=8 $dgxHost 'codex mcp remove wolfram-windows' 2>$null | Out-Null }
  if ($script:claudeAdded) { & ssh.exe -o BatchMode=yes -o ConnectTimeout=8 $dgxHost 'claude mcp remove wolfram-windows -s user' 2>$null | Out-Null }
  Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
  Get-NetFirewallRule -DisplayName $firewall -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  Write-Warning 'Task and firewall rule rolled back; logs and files retained for diagnosis.'
  throw
}
