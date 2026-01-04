# Update-BingImageOfTheDayMetadata.ps1
# Insert image data from the Bing Image of the Day feed into Bing Wallpaper images files using EXIFTOOL
#
# Copyright 2025, 2026 Richard Burte
# License: MIT license

<#
    .SYNOPSIS
    Fetch the Bing wallpaper image of the day metadata and then write into Bing Wallpaper images files using EXIFTOOL.
    Bing "Image of the Day" files are identified as matching the ????-??-??.jpg pattern in the Path

    .DESCRIPTION
    Fetch the Bing wallpaper image of the day. Can download previous day images as well. Skips downloading existing wallpapers.
    Requires EXIFTOOL in path. e.g. 'brew install exiftool' or 'winget install --id=OliverBetz.ExifTool'

    .PARAMETER Path
    Specify the location of an image, or a path to serch for Bing Images of the Day.
    Default: Wallpaper folder in your Pictures folder.
    
    .INPUTS
    None. You can't pipe objects to Update-BingImageOfTheDayMetadata.

    .OUTPUTS
    Writes data to images that match in specified path.

    .LINK
    Git Repo: https://github.com/arebee/Bing-wallpapers-x-plat
#>


function Update-BingImageOfTheDayMetadata {
    [CmdletBinding(SupportsShouldProcess)]
    Param(
        [string]$Path = $(Join-Path $([Environment]::GetFolderPath("MyPictures")) "Wallpapers")
    )

    $AltMetadataUri = 'https://api45gabs.azurewebsites.net/api/sample/bingphotos'

    # Test if EXIFTOOL is available on the path 
    if ($null -eq (get-Command -Name exiftool -ErrorAction Ignore)) {
        Write-Error "ExifTool is not available. Exiting."
        return
    }

    # Test if the Path provided is a container or leaf
    # If it is a leaf, test that its extension is in jpg or jpeg then add it to an array
    # Otherwise filter the children of the container.

    if (Test-Path -Path $Path -PathType Container) {
        # List the files that should have metadata added. Instead of examining all files we look at those that 
        # do not have _meta as the last part of the filename. This convention improves the speed of execution.
        $filesToProcess = $(Get-ChildItem -Filter "*.jpg" "$Path\*" -Include "????-??-??.jpg" -Exclude "????-??-??_meta.jpg")
        if ($null -eq $filesToProcess) {
            Write-Verbose 'No files to process.'
            return
        }
    }
    else {
        # Leaf file test it ends in jpg or jpeg
        $FileInf = Get-Item -Path $Path -ErrorAction Stop
        if (($FileInf.Extension.ToLowerInvariant() -ne '.jpg') -and ($FileInf.Extension.ToLowerInvariant() -ne '.jpg')) {
            Write-Error "File is not a .jpg or .jpeg. Exiting"
            return
        }
        else {
            $filesToProcess = , $FileInf
        }
    }

    Write-Verbose "$($filesToProcess.Count) image(s) to process"
    if ($filesToProcess.Count -eq 0) { return }

    # Fetch the metadata to apply from the Alternative endpoint.
    Write-Verbose "Getting Alt Metadata"
    $MyJsonImages = ConvertFrom-Json -InputObject $(Invoke-WebRequest -UseBasicParsing -Uri $AltMetadataUri).Content
    
    # Fetch metadata from the Bing Image of the Day endpoint.
    [xml]$MyXmlImages = ''
    Write-Verbose "Getting Bing XML Metadata"
    $MyXmlImages = (Invoke-WebRequest -Uri "https://www.bing.com/HPImageArchive.aspx?format=xml&mkt=$PSCulture&pid=hp&idx=0&n=8").Content
    
    # Process each file
    foreach ($file in ($filesToProcess | Sort-Object -Descending)) {
        Write-Verbose ""
        Write-Verbose "Processing '$($file.FullName)'"
        $existingCopyRight = exiftool -Copyright $($file.FullName)
        if ($null -ne $existingCopyRight) {
            Write-Verbose "$($file.FullName) already has copyright info"
            continue
        }
        $startDate = $file.BaseName.Replace('-', '').Trim()    
        $imageMetadata = $MyJsonImages.Where{ $PSItem.startdate -eq $startDate }[0]
        if (($null -eq $imageMetadata) -or ('' -eq $imageMetadata )) {
            # Check the XML data for the file, and create an equivilent object if it is found
            try {
                Write-Verbose "Check Bing official endpoint data."
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
    
        Write-Verbose "Transforming copyright info into description and copyright"
        Write-Verbose $($imageMetadata.copyright)
        
        $splitSourceCopyright = $imageMetadata.copyright.split('(')
        $description = $splitSourceCopyright[0].trim()
        $copyright = $splitSourceCopyright[1].substring(0, $splitSourceCopyright[1].length - 2)
        $title = $imageMetadata.title
        
        Write-Verbose "Description: $description"
        Write-Verbose "Copyright: $copyright"
        
        if ($WhatIfPreference) {
            "WhatIf: Updating $($file.FullName) to $($file.BaseName + "_meta" + $file.Extension)"
            continue
        }
        Write-Verbose "Updating $($file.FullName) to $($file.BaseName + "_meta" + $file.Extension)"
        
        # Update the file with metadata and then rename the file
        $null = exiftool -overwrite_original -Title="$title" -Description="$description" -Copyright="$copyright" -CreatorWorkURL="$($imageMetadata.copyrightlink)" $($file.FullName)
        $null = Rename-Item -Path $file.FullName $($file.BaseName + "_meta" + $file.Extension)
    }
}
