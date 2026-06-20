# RabbitMQ Windows Installation Runbook

## Purpose

This document provides a complete RabbitMQ installation and troubleshooting guide for a Windows machine.

It is written for future reuse so RabbitMQ can be installed, verified, and fixed without rediscovering the same issues again.

This guide assumes RabbitMQ is being installed for local microservice development, such as the ZBank project.

## Target Setup

Expected final result:

- Erlang installed
- RabbitMQ Server installed
- RabbitMQ Windows service running
- RabbitMQ Management Plugin enabled
- RabbitMQ Management UI accessible at `http://localhost:15672`
- Default local credentials working:

```text
username: guest
password: guest
```

Spring Boot applications should connect to:

```yaml
spring:
  rabbitmq:
    host: localhost
    port: 5672
    username: guest
    password: guest
```

## Important Ports

| Port | Purpose |
|---|---|
| `5672` | AMQP port used by applications such as Spring Boot |
| `15672` | RabbitMQ Management UI |
| `4369` | Erlang Port Mapper Daemon, used by RabbitMQ CLI/tools |
| `25672` | RabbitMQ Erlang distribution port, used by node/CLI communication |

## Prerequisite: Chocolatey

Chocolatey is recommended for installing RabbitMQ on Windows because it installs RabbitMQ and required dependencies such as Erlang.

Check if Chocolatey is installed:

```powershell
choco -v
```

If `choco` is not recognized, check the default Chocolatey path:

```powershell
Test-Path -LiteralPath "C:\ProgramData\chocolatey\bin\choco.exe"
```

If this returns `True`, Chocolatey is installed but not available in the current terminal PATH.

Use the full path:

```powershell
C:\ProgramData\chocolatey\bin\choco.exe -v
```

## Always Use Administrator PowerShell

RabbitMQ installation and service management require administrator permissions.

Open PowerShell like this:

1. Open Start menu.
2. Search for `PowerShell`.
3. Right-click `Windows PowerShell`.
4. Select `Run as administrator`.

If Chocolatey is run without Administrator rights, installation can fail with errors such as:

```text
Access to the path 'C:\ProgramData\chocolatey\.chocolatey' is denied.
Unable to obtain lock file access
```

## Installation Command

From Administrator PowerShell, run:

```powershell
C:\ProgramData\chocolatey\bin\choco.exe install rabbitmq -y
```

If `choco` works directly, this is also fine:

```powershell
choco install rabbitmq -y
```

Chocolatey should install:

- Erlang
- RabbitMQ Server
- RabbitMQ Windows service

## Expected Successful Installation Output

You should see messages similar to:

```text
rabbitmq has been installed.
RabbitMQ installation completed
rabbitmq_management plugin is enabled.
The install of rabbitmq was successful.
Chocolatey installed 2/2 packages.
```

The RabbitMQ management plugin may say:

```text
Offline change; changes will take effect at broker restart.
```

That is normal. Restart the RabbitMQ service after installation.

## RabbitMQ Default Installation Location

Chocolatey commonly installs RabbitMQ here:

```text
C:\Program Files\RabbitMQ Server\rabbitmq_server-<version>
```

For example:

```text
C:\Program Files\RabbitMQ Server\rabbitmq_server-4.3.1
```

The RabbitMQ command tools are inside:

```text
C:\Program Files\RabbitMQ Server\rabbitmq_server-4.3.1\sbin
```

Important tools:

```text
rabbitmq-service.bat
rabbitmqctl.bat
rabbitmq-plugins.bat
```

## If RabbitMQ Commands Are Not Recognized

After installation, commands like these may fail:

```powershell
rabbitmq-service restart
rabbitmqctl status
rabbitmq-plugins enable rabbitmq_management
```

Error:

```text
The term 'rabbitmq-service' is not recognized
```

This means RabbitMQ's `sbin` folder is not in PATH for the current terminal.

Use the full path instead:

```powershell
& "C:\Program Files\RabbitMQ Server\rabbitmq_server-4.3.1\sbin\rabbitmq-service.bat" start
& "C:\Program Files\RabbitMQ Server\rabbitmq_server-4.3.1\sbin\rabbitmqctl.bat" status
```

Or move into the `sbin` folder:

```powershell
cd "C:\Program Files\RabbitMQ Server\rabbitmq_server-4.3.1\sbin"
```

Then run commands using `.\`:

```powershell
.\rabbitmq-service.bat start
.\rabbitmqctl.bat status
.\rabbitmq-plugins.bat enable rabbitmq_management
```

PowerShell requires `.\` when running scripts from the current folder.

## Refreshing PATH After Installation

Chocolatey may print:

```text
Environment Vars have changed. Close/reopen your shell to see the changes or type refreshenv.
```

Try:

```powershell
refreshenv
```

If `refreshenv` does not work, import the Chocolatey profile:

```powershell
Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1
refreshenv
```

If it still does not work:

1. Close PowerShell.
2. Reopen PowerShell as Administrator.
3. Retry RabbitMQ commands.

## Add RabbitMQ to PATH Manually

If short commands are still unavailable, add RabbitMQ `sbin` to Machine PATH.

Run in Administrator PowerShell:

```powershell
$rabbitPath = "C:\Program Files\RabbitMQ Server\rabbitmq_server-4.3.1\sbin"
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$rabbitPath", "Machine")
```

Then close and reopen PowerShell as Administrator.

After reopening, these should work:

```powershell
rabbitmqctl status
rabbitmq-plugins enable rabbitmq_management
```

Note: depending on RabbitMQ version, `rabbitmq-service` may not support a `restart` command. Use `stop` and `start`.

## Enable RabbitMQ Management Plugin

Chocolatey may enable it automatically.

To enable manually:

```powershell
cd "C:\Program Files\RabbitMQ Server\rabbitmq_server-4.3.1\sbin"
.\rabbitmq-plugins.bat enable rabbitmq_management
```

Expected plugins:

```text
rabbitmq_management
rabbitmq_management_agent
rabbitmq_web_dispatch
```

If the output says:

```text
Offline change; changes will take effect at broker restart.
```

Restart the RabbitMQ service.

## RabbitMQ Service Commands

Move to the `sbin` folder:

```powershell
cd "C:\Program Files\RabbitMQ Server\rabbitmq_server-4.3.1\sbin"
```

Install service if needed:

```powershell
.\rabbitmq-service.bat install
```

Start service:

```powershell
.\rabbitmq-service.bat start
```

Stop service:

```powershell
.\rabbitmq-service.bat stop
```

Remove service:

```powershell
.\rabbitmq-service.bat remove
```

Important: some RabbitMQ Windows service scripts do not support:

```powershell
.\rabbitmq-service.bat restart
```

If `restart` only shows help output, use:

```powershell
.\rabbitmq-service.bat stop
.\rabbitmq-service.bat start
```

## Verify RabbitMQ Status

Run:

```powershell
.\rabbitmqctl.bat status
```

Successful output should include details such as:

```text
Status of node rabbit@<hostname>
Runtime
RabbitMQ version
Erlang configuration
Listeners
```

## Open RabbitMQ Management UI

Open:

```text
http://localhost:15672
```

Default login:

```text
username: guest
password: guest
```

If the page does not open:

1. Check that RabbitMQ service is started.
2. Check that `rabbitmq_management` plugin is enabled.
3. Restart service after enabling plugin.
4. Check whether port `15672` is blocked by firewall or another process.

## Common Issue: RabbitMQ Installed But `rabbitmqctl status` Fails

Error may look like:

```text
Error: unable to perform an operation on node 'rabbit@<hostname>'
TCP connection succeeded but Erlang distribution failed
suggestion: check if the Erlang cookie is identical for all server nodes and CLI tools
```

Factual meaning:

- RabbitMQ service is probably running.
- The CLI can reach RabbitMQ over TCP.
- Authentication between the CLI and RabbitMQ node failed.
- The most likely cause is an Erlang cookie mismatch.

## Erlang Cookie Explanation

RabbitMQ is built on Erlang.

RabbitMQ CLI tools such as `rabbitmqctl` authenticate to the RabbitMQ node using a shared secret file called:

```text
.erlang.cookie
```

The RabbitMQ Windows service usually runs under the system profile:

```text
C:\Windows\System32\config\systemprofile\.erlang.cookie
```

Your Administrator PowerShell runs under your user profile:

```text
C:\Users\<YourUserName>\.erlang.cookie
```

Both files must contain the same cookie value.

If they differ, RabbitMQ may be running but `rabbitmqctl status` fails.

## Fix Erlang Cookie Mismatch

Replace `<YourUserName>` with your Windows username.

For this machine, the observed username was:

```text
Sonik
```

Run in Administrator PowerShell:

```powershell
Copy-Item -LiteralPath "C:\Windows\System32\config\systemprofile\.erlang.cookie" -Destination "C:\Users\Sonik\.erlang.cookie" -Force
```

Then run:

```powershell
cd "C:\Program Files\RabbitMQ Server\rabbitmq_server-4.3.1\sbin"
.\rabbitmqctl.bat status
```

If it still fails, fix file permissions:

```powershell
icacls "C:\Users\Sonik\.erlang.cookie" /inheritance:r
icacls "C:\Users\Sonik\.erlang.cookie" /grant:r "Sonik:F"
```

Then retry:

```powershell
.\rabbitmqctl.bat status
```

## Diagnosing Whether RabbitMQ Is Running

Even if `rabbitmqctl status` fails, RabbitMQ may still be running.

In the error output, these lines indicate the service/node is reachable:

```text
connected to epmd (port 4369)
epmd reports node 'rabbit' uses port 25672
TCP connection succeeded but Erlang distribution failed
```

That means:

- Erlang port mapper is reachable.
- RabbitMQ node exists.
- TCP connection succeeded.
- Authentication failed because of Erlang distribution/cookie mismatch.

It is not an installation failure.

## Check Windows Service

Open services UI:

```powershell
services.msc
```

Look for:

```text
RabbitMQ
```

Status should be:

```text
Running
```

You can also use PowerShell:

```powershell
Get-Service | Where-Object { $_.Name -like "*Rabbit*" }
```

## Check Ports

Check AMQP port:

```powershell
netstat -ano | findstr :5672
```

Check Management UI port:

```powershell
netstat -ano | findstr :15672
```

If port `15672` is missing, the management plugin may not be enabled or RabbitMQ may need a restart.

## Chocolatey Lock File Issue

If a previous install failed, Chocolatey may leave a lock file.

Error example:

```text
Unable to obtain lock file access on C:\ProgramData\chocolatey\lib\<lock-id>
```

If no Chocolatey installation is currently running, remove the specific lock file shown in the error.

Example:

```powershell
Remove-Item -LiteralPath "C:\ProgramData\chocolatey\lib\<lock-id>" -Force
```

Then retry:

```powershell
C:\ProgramData\chocolatey\bin\choco.exe install rabbitmq -y
```

## Clean Verification Checklist

Run these from Administrator PowerShell:

```powershell
cd "C:\Program Files\RabbitMQ Server\rabbitmq_server-4.3.1\sbin"
.\rabbitmq-service.bat start
.\rabbitmq-plugins.bat enable rabbitmq_management
.\rabbitmq-service.bat stop
.\rabbitmq-service.bat start
.\rabbitmqctl.bat status
```

Then open:

```text
http://localhost:15672
```

Login:

```text
guest
guest
```

## ZBank RabbitMQ Connection Values

Use these values in ZBank service configuration:

```yaml
spring:
  rabbitmq:
    host: localhost
    port: 5672
    username: guest
    password: guest
```

ZBank RabbitMQ topology:

```text
Exchange:
  zbank.exchange
  type: topic

Queues:
  card-activation-queue
  card-management-queue
  notification-queue

Routing keys:
  zbank.application.submitted
  zbank.card.activated
```

## Full Recovery Sequence

If RabbitMQ installation gets into a confusing state, use this sequence.

Run from Administrator PowerShell:

```powershell
cd "C:\Program Files\RabbitMQ Server\rabbitmq_server-4.3.1\sbin"
.\rabbitmq-service.bat stop
Copy-Item -LiteralPath "C:\Windows\System32\config\systemprofile\.erlang.cookie" -Destination "C:\Users\Sonik\.erlang.cookie" -Force
icacls "C:\Users\Sonik\.erlang.cookie" /inheritance:r
icacls "C:\Users\Sonik\.erlang.cookie" /grant:r "Sonik:F"
.\rabbitmq-plugins.bat enable rabbitmq_management
.\rabbitmq-service.bat start
.\rabbitmqctl.bat status
```

Then check:

```text
http://localhost:15672
```

## Final Notes

The most common Windows RabbitMQ problems are not RabbitMQ business logic problems.

They are usually:

- PowerShell is not running as Administrator.
- Chocolatey is installed but not on PATH.
- RabbitMQ `sbin` folder is not on PATH.
- `refreshenv` is unavailable in the current shell.
- `rabbitmq-service.bat restart` is unsupported.
- RabbitMQ service is running, but `rabbitmqctl` fails because the Erlang cookie differs.

If the service starts and the management UI opens, RabbitMQ is ready for local Spring Boot development.
