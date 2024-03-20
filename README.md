# tools
## Clipboard Data Transfer
This tool can be used to transfer files over the MSRDP protocol from within PowerShell, utilizing the "Clipboard Virtual Extension" of the protocol, documented here: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpeclip/.

 It can be a direct connection MSRDP connection between two computers, or it can be a chained connection involving multiple jump hosts. As long as all computers in the chain have not enabled the policy "Do not allow Clipboard redirection", it should work.

The function uses the Get-Clipboard and Set-Clipboard cmdlets to transfer files between a "sender" and a "receiver".

Load the script in the current PowerShell session:
>. .\clipboard_transfer.ps1

Start as receiver:
>Invoke-ClipboardDataTransfer -Receive

Start as sender with single target file:
>Invoke-ClipboardDataTransfer -Send -SourceFilePath C:\temp\foo.txt

.. or as sender looping through multiple files:
>Get-Item C:\temp\\*.txt |%{ Invoke-ClipboardDataTransfer -Send -SourceFileObject $_ }

Additional parameters exists that let you define timeout values and data chunk sizes when sending data. This can be useful if you're dealing with a low-quality connection. Also stay away from ctrl+c/ctrl+v operations on your host during data transfers or this will break ;)