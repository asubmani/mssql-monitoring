# Replace with your Workspace ID
 $WorkspaceID = "ENTER WORKSPACE ID HERE"   
 # Replace with your Primary Key
 $SharedKey = "USE YOUR KEY vhrAcgBdERpzURl/ZSf2tk/HXF4Ynuky4LpAo41hU1Wr9NZxgegASZIP6lhQng=="  
 #Specify the name of the record type that we'll be creating.
 $LogType = "MySQLPerfCheck"
 $TimeStampField = ""
 # Function to create the authorization signature.
Function Build-Signature ($WorkspaceID, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $WorkspaceID,$encodedHash
    return $authorization
}
# Function to create and post the request
Function Post-OMSData($WorkspaceID, $sharedKey, $body, $logType) 
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
     $signature = Build-Signature `
        -WorkspaceID $WorkspaceID `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -fileName $fileName `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $WorkspaceID + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode
} 
# Sql query function that fetches data
function VerifySQL([string] $dbServerName, [string] $databaseName, [string] $Query)
{
    $ServerInstance = $dbServerName
    $Database = $databaseName
    $ConnectionTimeout = 30
    $QueryTimeout = 120    
    $conn=new-object System.Data.SqlClient.SQLConnection
    $ConnectionString = "Server={0};Database={1};Integrated Security=True;Connect Timeout={2}" -f $ServerInstance,$Database,$ConnectionTimeout
    $conn.ConnectionString=$ConnectionString
    $conn.Open()
    $da=New-Object System.Data.SqlClient.SqlDataAdapter($Query,$conn)
    $dt = New-Object "System.Data.DataTable"
    [void]$da.fill($dt)    
    $conn.Close()
    return $dt
}

$sqloutput= VerifySQl $dataBaseServerName $databaseName "sql query goes here"
$sql2json = $sqloutput | Select-Object * -ExcludeProperty ItemArray, Table, RowError, RowState, HasErrors | ConvertTo-Json

Post-OMSData -WorkspaceID $WorkspaceID -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($sql2json)) -logType $logType