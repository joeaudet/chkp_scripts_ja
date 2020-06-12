#########################
### Declare Variables ###
#########################

$username = "<API_USERNAME>"
$password = "<API_PASSWORD>"
$IP = Read-Host -Prompt "Please enter IP to search for: "
$MDSIP = Read-Host -Prompt "Please enter MDS IP: "
$base_url = "https://$($MDSIP)/web_api/v1.3"
$hostentries=@{}
$sessions=@{}

#########################

###allow self signed certs
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

#########################

function ExceptionErrorHandler {
	$global:helpme = $body
	$global:helpmoref = $moref
	$global:result = $_.Exception.Response.GetResponseStream()
	$global:reader = New-Object System.IO.StreamReader($global:result)
	$global:responseBody = $global:reader.ReadToEnd();
	$resp_error_code = $global:responsebody | ConvertFrom-Json | Select-Object -ExpandProperty code
	$resp_message = $global:responsebody | ConvertFrom-Json | Select-Object -ExpandProperty message
	$resp_statusCode = [int]$_.Exception.Response.StatusCode
	Write-Host -BackgroundColor:Black -ForegroundColor:Red "Status: A system exception was caught."
	Write-Host -BackgroundColor:Black -ForegroundColor:Red "Response HTTP Code" $resp_statusCode
	Write-Host -BackgroundColor:Black -ForegroundColor:Red "Response body:"
	Write-Host -BackgroundColor:Black -ForegroundColor:Red $global:responsebody
	break
}

function ErrorLogout{
	Write-Host -BackgroundColor:Black -ForegroundColor:Red "Error encountered, logging out of session"
	$response = logout $base_url $session
}

function login {
	Param([Parameter()]$base_url, $username, $password, $domain)
	
	$headers = @{
		"Content-Type" = "application/json"
	}
	
	$body = (ConvertTo-Json -compress @{
		"user" = $username;
		"password" = $password;
		"domain" = $domain
	})

	try{
		$response = Invoke-WebRequest "$($base_url)/login" -Method 'POST' -Headers $headers -Body $body -ErrorAction Stop
		$session = $response | ConvertFrom-Json | Select-Object -ExpandProperty sid
		if($response.StatusCode -eq 200){
			$sessions.Add($session,$domain)
		}
	}
	catch{
		Write-Host "An error occurred while logging in, exiting"
		### Since 4xx HTTP codes are handled as exceptions, run this function to properly parse the output
		ExceptionErrorHandler
		Exit 1
	}
	
	return $session
}

function logout {
	Param([Parameter()]$base_url, $session)

	$headers = @{
		"Content-Type" = "application/json";
		"X-chkp-sid" = $session
	}

	$body = (ConvertTo-Json @{ })

	try{
		$Response = Invoke-RestMethod "$($base_url)/logout" -Method 'POST' -Headers $headers -Body $body -ErrorAction Stop
	}
	catch{
		Write-Host "Error logging out"
		### Since 4xx HTTP codes are handled as exceptions, run this function to properly parse the output
		ExceptionErrorHandler
		Exit 1
	}
}

function show-domains {
	Param([Parameter()]$base_url, $session, $IP)

	$headers = @{
		"Content-Type" = "application/json";
		"X-chkp-sid" = $session
	}

	$body = (ConvertTo-Json @{

	})

	try{
		$response = Invoke-WebRequest "$($base_url)/show-domains" -Method 'POST' -Headers $headers -Body $body
		#Convert output to PS object for iteration
		$resp = $response | ConvertFrom-Json
		#Logout from the MDS session, no longer needed to be kept open
		logout $base_url $session
		
		#If a status code 200, proceed to loop over each domain in the list
		if($response.StatusCode -eq 200){
			foreach ($domain in $resp.objects)
			{
				if ($domain.type -eq "domain"){
				Write-Host "Searching domain $($domain.name) for $IP"
				#Login to the current domain in the list
				$sessionx = login $base_url $username $password $domain.name
				#Run a show-objects for the IP in question
				show-objects $base_url $sessionx $IP
				#Logout of the domain when done
				logout $base_url $sessionx
				}
			}

			#Output the results of the hashtable we stored any results in, formatting the headers from the default Name / Value
			Write-Host "----------"
			Write-Host "Found the following entries for $($IP):"
			$hostentries | Format-Hashtable -KeyHeader Hostname -ValueHeader Domain
			
			#Exit the script since all work is complete
			Exit 1
		}
	}
	catch{
		Write-Host "Error showing domains, exiting"
		### Since 4xx HTTP codes are handled as exceptions, run this function to properly parse the output
		ExceptionErrorHandler
		Exit 1
	} 
}

function show-objects {
	Param([Parameter()]$base_url, $session, $IP)

	$headers = @{
		"Content-Type" = "application/json";
		"X-chkp-sid" = $session
	}

	#Search for an object by IP address, type host, max limit is 500 results by API design (shouldn't be necessary to paginate)
	$body = (ConvertTo-Json @{
		"limit"="500";
		"offset"="0";
		"type"="host";
		"filter"="$($IP)";
		"ip-only"="true";
	})

	try{
		$response = Invoke-WebRequest "$($base_url)/show-objects" -Method 'POST' -Headers $headers -Body $body -ErrorAction Stop
		$resp = $response | ConvertFrom-Json
		if($response.StatusCode -eq 200){
			foreach ($entry in $resp.objects)
			{
				#For every result add to the hashtable. This was chosen over an array because of dynamic expansion, and only unique values are kept
				$hostentries.Add($entry.name,$entry.domain.name)
			}
		}
	}
	catch{

	} 
}

function Format-Hashtable {
    param(
      [Parameter(Mandatory,ValueFromPipeline)]
      [hashtable]$Hashtable,

      [ValidateNotNullOrEmpty()]
      [string]$KeyHeader = 'Name',

      [ValidateNotNullOrEmpty()]
      [string]$ValueHeader = 'Value'
    )

    $Hashtable.GetEnumerator() |Select-Object @{Label=$KeyHeader;Expression={$_.Key}},@{Label=$ValueHeader;Expression={$_.Value}}

}

#Start the function off by performing a login to the System Data domain
$session = login $base_url $username $password "System Data"

#Grab a list of domains, then loop through those searching each domain for the IP in question
show-domains $base_url $session $IP