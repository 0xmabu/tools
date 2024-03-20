#stay away from ctrl+c/ctrl+v during data transfers or this will break ;)
function Invoke-ClipboardDataTransfer {
	[CmdletBinding()]
    Param (
        [Parameter(ParameterSetName='Send')]
        [Switch]$Send,
        [Parameter(ParameterSetName='Send')]
        [System.IO.FileInfo]$SourceFileObject,
        [Parameter(ParameterSetName='Send')]
        [String]$SourceFilePath,
        [Parameter(ParameterSetName='Send')]
        [Int32]$FileChunkSize = 1000000, #bytes
        [Parameter(ParameterSetName='Send')]
		[Int32]$AckWait = 1000, #milliseconds
        [Parameter(ParameterSetName='Send')]
        [Int32]$SendTimeout = 20000, #milliseconds

        [Parameter(ParameterSetName='Receive')]
        [Switch]$Receive,
        [Parameter(ParameterSetName='Receive')]
        [String]$DestinationFolderPath = ".\",
        [Parameter(ParameterSetName='Receive')]
		[Int32]$DataWait = 1000, #milliseconds
        [Parameter(ParameterSetName='Receive')]
        [Int32]$ReceiveTimeout = 20000 #milliseconds
    )

    function Send-FileOverClipboard {   
        $base64String = [Convert]::ToBase64String([IO.File]::ReadAllBytes($SourceFileObject))

        #send and send file meta info
        $fileInfo = @{
            name = $SourceFileObject.Name
            length = $SourceFileObject.Length
            hash = (Get-FileHash $SourceFileObject -Algorithm MD5).Hash
            chunks = [int]([math]::Ceiling($base64String.Length/$FileChunkSize))
        }

        $fileInfo |ConvertTo-Json -Compress |Set-Clipboard
		Write-Verbose "$([DateTime]::Now.ToString('HHHH:mm:ss:mmmm')) | SEND DATA $($fileInfo.hash):0:"
        Get-IncomingClipboardData -matchString "ACK:$($fileInfo.hash):0:" -waitTime $AckWait |Out-Null
        Write-Host "Connected, transferring file $($fileInfo.name) ($($fileInfo.length) bytes)"

        #create and send file chunks
        for ($i = 1; $i -le $fileInfo.chunks; $i++) {
            if ($base64String.Length -ge $FileChunkSize) {
                $data = $base64String.SubString(0,$FileChunkSize)
                $base64String = $base64String.SubString($FileChunkSize)
            }
            else {
                $data = $base64String
            }
    
            "$($fileInfo.hash):$($i):$($data)" |Set-Clipboard
            Write-Verbose "$([DateTime]::Now.ToString('HHHH:mm:ss:mmmm')) | SEND DATA $($fileInfo.hash):$($i):"
			
            Get-IncomingClipboardData -matchString "ACK:$($fileInfo.hash):$($i):" -waitTime $AckWait -timeOut $SendTimeout |Out-Null
            Write-Progress -Activity 'Sending data chunks...' -Status "$i of $($fileInfo.chunks) completed" -PercentComplete ($i/$fileInfo.chunks*100)
        }
    
        Write-Progress -Activity 'Sending data chunks...' -Completed
        Write-Host "File $($SourceFileObject.Name) transferred successfully"
    }

    function Receive-FileOverClipboard {
        while ($true) {
            Write-Host "Waiting for incoming file..."
            $fileInfo = Get-IncomingClipboardData -matchString "{.*}" -waitTime $dataWait |ConvertFrom-Json
            Write-Verbose "$([DateTime]::Now.ToString('HHHH:mm:ss:mmmm'))) | RCV DATA $($fileInfo.hash):0:"
            Write-Host "Connected, transferring file $($fileInfo.name) ($($fileInfo.length) bytes)"

            "ACK:$($fileInfo.hash):0:" |Set-Clipboard
            Write-Verbose "$([DateTime]::Now.ToString('HHHH:mm:ss:mmmm')) | SEND ACK $($fileInfo.hash):0:"
            
            $Base64String = [System.Text.StringBuilder]::new()

            for ($i = 1; $i -le $fileInfo.chunks; $i++) {
                $data = Get-IncomingClipboardData -matchString "$($fileInfo.hash):$($i):" -waitTime $dataWait -timeOut $ReceiveTimeout
                $ChunkString = $data.Split(':')[2]
                [void]$Base64String.Append($ChunkString)

                "ACK:$($fileInfo.hash):$($i):" |Set-Clipboard
                Write-Verbose "$([DateTime]::Now.ToString('HHHH:mm:ss:mmmm')) | SEND ACK $($fileInfo.hash):$($i):"
                Write-Progress -Activity 'Receiving data chunks...' -Status "$i of $($fileInfo.chunks) completed" -PercentComplete ($i/$fileInfo.chunks*100)
            }

            Write-Progress -Activity 'Receiving data chunks...' -Completed
            
            $dstFile = $DestinationFolderPath + $fileInfo.name
            [IO.File]::WriteAllBytes($dstFile, [Convert]::FromBase64String($Base64String.ToString()))
            $fileObj = Get-Item $dstFile
            $fileObjHash = (Get-FileHash $fileObj -Algorithm MD5).Hash

            if ($fileObjHash -ne $fileInfo.hash) {
                Remove-Item $fileObj
                throw "Hash mismatch for $($fileInfo.name)"
            }

            Write-Host "File $($fileInfo.name) transferred successfully"
        }
    }

    function Get-IncomingClipboardData {
        Param (
            $matchString,
            $waitTime,
            $timeOut
        )

        $timer = [Diagnostics.Stopwatch]::StartNew()

        while ($true) {
            Start-Sleep -Milliseconds $waitTime

            if ($timeOut -and $timer.ElapsedMilliseconds -gt $timeOut) {
                throw "Operation 'WAIT DATA $matchString' timed out"
            }
            else {
                $data = Get-Clipboard

                if ($data -match "^$matchString") {
                    Write-Verbose "$([DateTime]::Now.ToString('HHHH:mm:ss:mmmm')) | RCV DATA $matchString"
                    $timer.Stop()
                    return $data
                }
                else {
                    Write-Verbose "$([DateTime]::Now.ToString('HHHH:mm:ss:mmmm')) | WAIT DATA $matchString"
                }
            }
        }
    }

    if ($Send) {
        if (-not $SourceFileObject) {
            if (-not (Test-Path $SourceFilePath)) {
                Write-Error "Invalid destination path"
            }
            else {
                $SourceFileObject = Get-Item $SourceFilePath
            }
        }

        Send-FileOverClipboard
    }
    elseif ($Receive) {
        if (-not (Test-Path $DestinationFolderPath)) {
            Write-Error "Invalid destination path"
        }
        else {
            $DestinationFolderPath = (Get-Item $DestinationFolderPath).FullName + '\'
        }

        Receive-FileOverClipboard
    }
}

#Remove-Alias -Name cdt -ErrorAction SilentlyContinue
#New-Alias -Name cdt Invoke-ClipboardDataTransfer