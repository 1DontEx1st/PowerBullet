<#
.Synopsis
   Use this Function to use the pushbullet service to send push messages to your browser, computer or device 
.DESCRIPTION
   *****To use this function, you must register for a PushBullet account and copy your API key from under 'Account Settings'
   
   *****As of this release (Halloween Day, 2014) Lists and File Upload support are not yet functional
   
   Use this Function as a stand-alone push service, or embed within your other functions to perform dynamic messaging as needed

   
.EXAMPLE
   Send-PushMessage -msg "Hello world" -title "Mandatory first message text" 

   #You will receive a push message on all of your configured devices with a "Hello World" message
   
.EXAMPLE
   get-winevent -LogName System | Select -first 1500 | ? Id -eq '1074' | % {Send-PushMessage -Title "Reboot detected on System" -msg ("Reboot detected on " + $_.MachineName + "@ " +  $_.TimeCreated) -Type Message}


   #In this more complex scenario, if an event of 1074 (System Reboot) is noted within the most recent 1500 events, send a message using PushBullet with information from the event.  
.NOTES
    If this function halts with a Warning message of "Please place your API Key within line 48 and try again", be certain to provide your API key on line 48.
#>
Function Send-PushMessage {
[CmdletBinding(DefaultParameterSetName='Message')]


param(
        [Parameter(Mandatory=$false,ParameterSetName="File")]$FileName,
        [Parameter(Mandatory=$true, ParameterSetName="File")]$FileType,
        [Parameter(Mandatory=$false, ParameterSetName="File")]
        [Parameter(Mandatory=$true, ParameterSetName="Link")]$url,
        
        [Parameter(Mandatory=$false,ParameterSetName="Address")]$PlaceName,
        [Parameter(Mandatory=$true, ParameterSetName="Address")]$PlaceAddress,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Address","Message","File","List","Link")]
        [Alias("Content")] 
        $Type,
        
        [switch]$UploadFile,
        [string[]]$items,
        $title="PushBullet Message",
        $msg)
begin{
    $api = "***YourAPIHere***"
    $PushURL = "https://api.pushbullet.com/v2/pushes"
    $devices = "https://api.pushbullet.com/v2/devices"
    $uploadRequestURL   = "https://api.pushbullet.com/v2/upload-request"
    $uploads = "https://s3.amazonaws.com/pushbullet-uploads"

    $cred = New-Object System.Management.Automation.PSCredential ($api,(ConvertTo-SecureString $api -AsPlainText -Force))

    if (($PlaceName) -or ($PlaceAddress)){$type = "address"}

    if ($api -eq "***YourAPIHere***"){Write-warning "Please place your API Key within line 48 and try again"
        BREAK}
    }

process{

    switch($Type){
    'Address'{Write-Verbose "Sending an Address"<#SendaMessagestuff#>
                $body = @{
                    type = "address"
                    title = $Placename
                    address = $PlaceAddress
                    }
             }
    'Message'{Write-Verbose "Sending a message"<#SendaMessagestuff#>
                $body = @{
                    type = "note"
                    title = $title
                    body = $msg
                    }
             }
    'List'   {Write-Verbose "Sending a list "<#SendaListstuff#>
             $body = @{
                    type = "list"
                    title = $title
                    items = $items
                    
                    } 
                    
                    "body preview"
                    $body
                    #$body = $body | ConvertTo-Json 
             }
    'Link'   {Write-Verbose "Sending a link "<#SendaLinkstuff#>
             $body = @{
                    type = "link"
                    title = $title
                    body = $msg
                    url = $url
                    } 

             }
    'File'   {Write-Verbose "Sending a file "<#SendaFilestuff#>
              If ($UploadFile) {  
                $fileLeaf = $filename | split-path -leaf
                $UploadRequest = @{
                    file_name = $FileLeaf
                    file_type  = $FileType
                }
        
                #Ref: Pushing files https://docs.pushbullet.com/v2/pushes/#pushing-files
                # "Once the file has been uploaded, set the file_name, file_url, and file_type returned in the response to the upload request as the parameters for a new push with type=file."
            
                #Create Upload request first
                $attempt = Invoke-WebRequest -Uri $uploadRequestURL -Credential $cred -Method Post -Body $UploadRequest -ErrorAction SilentlyContinue
                If ($attempt.StatusCode -eq "200"){Write-Verbose "Upload Request OK"}
                else {Write-Warning "error encountered, check `$Uploadattempt for more info"
                        $global:Uploadattempt = $attempt}

#                #Have to include the data field from the full response in order to begin an upload
#                $UploadApproval = $attempt.Content | ConvertFrom-Json | select -ExpandProperty data 
                #Data is not needed, it's the other stuff
                $json = $attempt.Content | ConvertFrom-Json
                $uploadURL = $json.upload_url

                $fileBytes = [System.IO.File]::ReadAllBytes($fileName);
                $fileEnc = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetString($fileBytes);
                $boundary = [System.Guid]::NewGuid().ToString(); 
                $LF = "`r`n";

                $bodyLines = ( 
                    "--$boundary",
                    "Content-Disposition: form-data; name=`"file`"; filename=`"$fileLeaf`"",
                    "Content-Type: application/octet-stream$LF",
                    $fileEnc,
                    "--$boundary--$LF" 
                ) -join $LF

                $uploaded = Invoke-WebRequest -uri $uploadURL -Method Post -ContentType "multipart/form-data; boundary=`"$boundary`"" -Body $bodyLines #-Credential $cred

                If ($uploaded.StatusCode -eq "204"){Write-Verbose "File upload OK"}
                else {Write-Warning "error encountered, check `$Uploadattempt for more info"
                        $global:Uploadattempt = $uploaded}
            
                #End Of Upload File scriptblock
                $body = @{
                    type = "file"
                    file_name = $json.file_name
                    file_type = $json.file_type
                    file_url = $json.file_url
                    body = $msg
                    } 
                }
            Else {
                #If we don't need to upload the file
                
                $body = @{
                    type = "file"
                    file_name = $fileName
                    file_type = $filetype
                    file_url = $url
                    body = $msg
                    } 
                
            }
            $global:UploadApproval = $UploadApproval
            BREAK
            #End of File switch

            }
    #End of Switch Statement
    }

    write-debug "Test-value of `$body before it gets passed to Invoke-WebRequest"

    $Sendattempt = Invoke-WebRequest -Uri $PushURL -Credential $cred -Method Post -Body $body -ErrorAction SilentlyContinue

    If ($Sendattempt.StatusCode -eq "200"){Write-Verbose "OK"}
        else {Write-Warning "error encountered, check `$attempt for more info"
              $global:Sendattempt = $Sendattempt  }
    }

end{$global:Sendattempt = $Sendattempt}

}
