# Insert image data into the files EXIF using EXIFTOOL
[string]$downloadFolder = $(Join-Path $([Environment]::GetFolderPath("MyPictures")) "Wallpapers")
$fileCount = $(Get-ChildItem -Filter "*.jpg" "$downloadFolder\*" -Include "????-??-??.jpg" -Exclude "????-??-??_meta.jpg")
if ($null -eq $fileCount) {
    Write-Verbose 'No files to process'
    return
}
Write-Verbose "$($fileCount.Count) image(s) to process"
$MyJsonImages = ConvertFrom-Json -InputObject $(Invoke-WebRequest -UseBasicParsing -Uri 'https://api45gabs.azurewebsites.net/api/sample/bingphotos').Content
[xml]$MyXmlImages = ''
foreach ($file in ($fileCount | Sort-Object -Descending)) {
    $existingCopyRight = exiftool -Copyright $($file.FullName)
    if ($null -ne $existingCopyRight) {
        Write-Verbose "$($file.FullName) already has copyright info"
        continue
    }
    $startDate = $file.BaseName.Replace('-', '').Trim()    
    $imageMetadata = $MyJsonImages.Where{ $PSItem.startdate -eq $startDate }[0]
    if (($null -eq $imageMetadata) -or ('' -eq $imageMetadata )) {
        # Check the XML data
        try {
            Write-Verbose "XML path"
            if ($MyXmlImages.HasChildNodes = $false) {
                $MyXmlImages = (Invoke-WebRequest -Uri "https://www.bing.com/HPImageArchive.aspx?format=xml&mkt=$PSCulture&pid=hp&idx=0&n=8").Content
            }
            $hash = @{"copyright" = ''; "title" = '' }
            $imageMetadata = [pscustomobject]$hash
            Write-Verbose "//image[startdate[text() = '$startDate']]"
            $imageMetadata.copyright = $(Select-Xml -Xml $MyXmlImages -XPath "//image[startdate[text() = '$startDate']]").Node.SelectSingleNode('copyright').InnerText.Trim()
            Write-Verbose "ImageMetadata.Copyright: $($imageMetadata.copyright)"
            $imageMetadata.title = $(Select-Xml -Xml $MyXmlImages -XPath "//image[startdate[text() = '$startDate']]").Node.SelectSingleNode('headline').InnerText.Trim()
            Write-Verbose "ImageMetadata.title: $($imageMetadata.title)"
            if ([string]::IsNullOrEmpty($imageMetadata.title)) {
                Write-Verbose "No metadata available for $file"
                continue
            }
        }
        catch {
            Write-Verbose "No metadata available for $file"
            continue
        }
    }
    Write-Verbose "Processing $($file.FullName) for copyright info"
    Write-Verbose $($imageMetadata.copyright)
        
    $splitSourceCopyright = $imageMetadata.copyright.split('(')
    $description = $splitSourceCopyright[0].trim()
    $copyright = $splitSourceCopyright[1].substring(0, $splitSourceCopyright[1].length - 2)
    $title = $imageMetadata.title
        
    Write-Verbose $description
    Write-Verbose $copyright
    Write-Verbose "Updating $($file.FullName)"
        
    $null = exiftool -overwrite_original -Title="$title" -Description="$description" -Copyright="$copyright" -CreatorWorkURL="$($imageMetadata.copyrightlink)" $($file.FullName)
    Rename-Item -Path $file.FullName $($file.BaseName + "_meta" + $file.Extension)
    
}
