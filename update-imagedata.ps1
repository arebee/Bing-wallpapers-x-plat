# Insert image data into the files EXIF using EXIFTOOL
[string]$downloadFolder = $(Join-Path $([Environment]::GetFolderPath("MyPictures")) "Wallpapers")
$MyJsonImages = ConvertFrom-Json -InputObject $(Invoke-WebRequest -UseBasicParsing -Uri 'https://api45gabs.azurewebsites.net/api/sample/bingphotos').Content
foreach ($file in $(Get-ChildItem -Path $downloadFolder -File -Filter '*.jpg' | Sort-Object -Descending)) {
    $existingCopyRight = exiftool -Copyright $($file.FullName)
    if ($null -ne $existingCopyRight) {
        Write-Verbose "$($file.FullName) already has copyright info"
        continue
    }
    $startDate = $file.BaseName.Replace('-', '').Trim()    
    $imageMetadata = $MyJsonImages.Where{$PSItem.startdate -eq $startDate}[0]
    if (($null -eq $imageMetadata) -or ('' -eq $imageMetadata )) {
        Write-Verbose "No metadata available for $file"
    } else {  
        Write-Verbose "Processing $($file.FullName) for copyright info"
        Write-Verbose $($imageMetadata.copyright)
        
        $splitSourceCopyright = $imageMetadata.copyright.split('(')
        $description = $splitSourceCopyright[0].trim()
        $copyright = $splitSourceCopyright[1].substring(0, $splitSourceCopyright[1].length - 2)
        $title = $imageMetadata.title
        
        Write-Verbose $description
        Write-Verbose $copyright
        Write-Verbose "Updating $($file.FullName)"
        
        exiftool -overwrite_original -Title="$title" -Description="$description" -Copyright="$copyright" -CreatorWorkURL="$($imageMetadata.copyrightlink)" $($file.FullName)
    }
}
