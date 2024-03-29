param ([string] $filePath)

if (-not $filePath) {
	Write-Error "-filePath parameter is required to save downloaded file"
	exit
}

function Http-Web-Request {
	param([string]$method = "GET", [string]$url, [object]$headers = @{}, [object]$postData = @{}, [System.Net.CookieContainer] $cookies )
	
	
    # Compose the URL and create the request
	# Querystring parameters are assumed to be in $url
    [System.Net.HttpWebRequest] $request = [System.Net.HttpWebRequest] [System.Net.WebRequest]::Create($url)

    # Add the method (GET, POST, etc.)
    $request.Method = $method
	
    ## Add an headers to the request
    foreach($key in $headers.keys)
    {
        $request.Headers.Add($key, $headers[$key])
    }
	
    # Store cookies
	$request.CookieContainer = $cookies
	
    # Send a custom user agent if you want
    $request.UserAgent = "Mozilla/4.0+"

    # Create the request body if the verb accepts it (NOTE: utf-8 is assumed here)
    if ($method -eq "POST") {
		$postDataString = [string]::Empty
	
		foreach($data in $postData.keys) {
			$postDataString += ($data + "=" + [System.Web.HttpUtility]::UrlEncode($postData[$data]) + "&")
		}
		
		if ($postDataString.EndsWith("&")) {
			$postDataString = $postDataString.TrimEnd("&")
		}
		
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($postDataString)
        $request.ContentType = "application/x-www-form-urlencoded"
        $request.ContentLength = $bytes.Length
        
        [System.IO.Stream] $outputStream = [System.IO.Stream]$request.GetRequestStream()
        $outputStream.Write($bytes,0,$bytes.Length)  
        $outputStream.Close()
    }

    # This is where we actually make the call.  
    try
    {
        [System.Net.HttpWebResponse] $response = [System.Net.HttpWebResponse] $request.GetResponse()     
		return $response
    }
    # This catches errors from the server (404, 500, 501, etc.)
    catch [Net.WebException] { 
        [System.Net.HttpWebResponse] $resp = [System.Net.HttpWebResponse] $_.Exception.Response
		
		$err = "WebException occurred when attempting to download license file : $($resp.StatusCode) - $($resp.StatusDescription)"
		Write-Error $err
		
        throw $err
    }
	catch {
		$err = "Exception occurred when attempting to download license file : $_"
		Write-Error $err
	}
}

function Get-Response-Content {
	param(
		[System.Net.HttpWebResponse]
		[Parameter(ValueFromPipeline=$true)]
		$response
	)
    
	$sr = New-Object System.IO.StreamReader($response.GetResponseStream())       
    return $sr.ReadToEnd()
}

function Http-Download {
	param([string]$url, [string] $saveAs)
	
	$client = New-Object System.Net.WebClient

	try {
		Write-Host "Downloading file $url"
		
		[void](Register-ObjectEvent $client DownloadProgressChanged -action {     

			$downloaded = ($eventargs.BytesReceived / 1024 / 1024)
			$total = ($eventargs.TotalBytesToReceive / 1024 / 1024)
			
		    Write-Progress -Activity "Downloading..." -Status ("{0:N2} MB of {1:N2} MB" -f $downloaded, $total) -PercentComplete $eventargs.ProgressPercentage
		})

	    [void](Register-ObjectEvent $client DownloadFileCompleted -SourceIdentifier Finished)

	    $client.DownloadFileAsync([Uri]$url, $saveAs)

	    # optionally wait, but you can break out and it will still write progress
	    Wait-Event -SourceIdentifier Finished

	} finally { 
	    $client.dispose()
	}

}

function Get-McAfee-FileName {
param (
	[Parameter(ValueFromPipeline=$true)]
	[string] $content
)

	$regex = "<IMG\s*SRC=`".*?`"\s*ALT=\`"\[FILE\]`">\s*<A\s*HREF=`"(?<filename>.*?)`"?>"
	[Void]($content -match $regex) #gets the first match
	
	$filename = $matches["filename"]
	
	if (-not ($filename -match "\.exe")) {
		Write-Error "Incorrect match on filename: $filename"
		exit
	}
	
	return $filename
}

# Start executing the script here. This is where it all goes down

$update_file = Http-Web-Request -url "http://download.nai.com/products/licensed/superdat/english/intel/" | Get-Response-Content | Get-McAfee-FileName
Http-Download -url "http://download.nai.com/products/licensed/superdat/english/intel/$update_file" -saveAs $filePath