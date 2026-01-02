# Update-BingWallpaperMetadata.ps1
# Insert image data from the Bing Wallpaper feed into Bing Wallpaper images files using EXIFTOOL
#
# Copyright 2025 Richard Burte
# License: MIT license

<#
    .SYNOPSIS
    Fetch the Bing wallpaper image of the day metadata and then write into Bing Wallpaper images files using EXIFTOOL.

    .DESCRIPTION
    Fetch the Bing wallpaper image of the day. Can download previous day images as well. Skips downloading existing wallpapers.
    Requires EXIFTOOL in path. e.g. 'brew install exiftool' or 'winget install --id=OliverBetz.ExifTool'

    .PARAMETER Path
    Specify the location where wallpapers will be downloaded.
    Default: Wallpaper folder in your Pictures folder.
    
    .INPUTS
    None. You can't pipe objects to Update-BingWallpaperMetadata.

    .OUTPUTS
    Writes data to images that match in specified path.

    .LINK
    Git Repo: https://github.com/arebee/Bing-wallpapers-x-plat

#>

Param(
    [string]$Path = $(Join-Path $([Environment]::GetFolderPath("MyPictures")) "Wallpapers")
)

$fileCount = $(Get-ChildItem -Filter "*.jpg" "$Path\*" -Include "????-??-??.jpg" -Exclude "????-??-??_meta.jpg")
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
