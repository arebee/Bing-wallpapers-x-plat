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
    $filesUpdatedCount = 0
    $AltMetadataUri = 'https://api45gabs.azurewebsites.net/api/sample/bingphotos'
    $Const_Bing_Metadata_URL_1 = "https://www.bing.com/HPImageArchive.aspx?format=js&mkt=$PSCulture&pid=hp&idx=0&n=8"
    $Const_Bing_Metadata_URL_2 = "https://www.bing.com/HPImageArchive.aspx?format=js&mkt=$PSCulture&pid=hp&idx=8&n=8"

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
        $filesToProcess = $(Get-ChildItem -Filter "*.jpg" -Path "$Path\*" -Include "????-??-??.jpg" -Exclude "????-??-??_meta.jpg")
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
    # $MyJsonImages = ConvertFrom-Json -InputObject $(Invoke-WebRequest -UseBasicParsing -Uri $AltMetadataUri).Content
    [System.Collections.ArrayList]$CombinedImageMetadata = ConvertFrom-Json -InputObject $(Invoke-WebRequest -UseBasicParsing -Uri $AltMetadataUri).Content
    
    # Fetch metadata from the Bing Image of the Day endpoint.
    Write-Verbose "Getting Bing Metadata"
    [System.Collections.ArrayList]$BingMetadata = $(ConvertFrom-Json((Invoke-WebRequest -Uri $Const_Bing_Metadata_URL_1).Content)).Images
    [System.Collections.ArrayList]$BingMetadata += $(ConvertFrom-Json((Invoke-WebRequest -Uri $Const_Bing_Metadata_URL_2).Content)).Images
    
    Write-Verbose $CombinedImageMetadata.Count
    foreach ($item in $BingMetadata) {
        $MatchesInCombined = $CombinedImageMetadata.Where({ $_.startdate -eq $item.startdate })
        foreach ($match in $MatchesInCombined) {
            Add-Member -Type NoteProperty -Name desc -Value $item.desc -InputObject $match -Force
            Add-Member -Type NoteProperty -Name caption -Value $item.caption -InputObject $match -Force
            Add-Member -Type NoteProperty -Name copyrightonly -Value $item.copyrightonly -InputObject $match -Force
        }
    }
    
    # Process each file
    foreach ($file in ($filesToProcess | Sort-Object -Descending)) {
        Write-Verbose "`nProcessing '$($file.FullName)'"
        $existingCopyRight = exiftool -Copyright $($file.FullName)
        if ($null -ne $existingCopyRight) {
            Write-Verbose "$($file.FullName) already has copyright info"
            continue
        }
        $startDate = $file.BaseName.Replace('-', '').Trim()    
        $imageMetadata = $CombinedImageMetadata.Where{ $_.startdate -eq $startDate }[0]
        if (($null -eq $imageMetadata) -or ('' -eq $imageMetadata )) {
            Write-Verbose "No metadata available for $file"
            continue
        }
        
        if ($imageMetadata.PSObject.Properties.Name -contains 'desc'){
            $description = $imageMetadata.desc
            $copyright = $imageMetadata.copyrightonly
            $caption = $imageMetadata.caption
        } else {
            Write-Verbose "Transforming copyright info into description and copyright"
            Write-Verbose $($imageMetadata.copyright)
            $splitSourceCopyright = $imageMetadata.copyright.split('(')
            $description = $splitSourceCopyright[0].trim()
            $copyright = $splitSourceCopyright[1].substring(0, $splitSourceCopyright[1].length - 2)
            $caption = $description
        }
        
        $title = $imageMetadata.title
        
        Write-Verbose "Title: $title"
        Write-Verbose "Caption: $caption"
        Write-Verbose "Description: $description"
        Write-Verbose "Copyright: $copyright"
        
        if ($WhatIfPreference) {
            "WhatIf: Updating $($file.FullName) to $($file.BaseName + "_meta" + $file.Extension)"
            continue    
        }
        Write-Verbose "Updating $($file.FullName) to $($file.BaseName + "_meta" + $file.Extension)"
        
        # Update the file with metadata and then rename the file
        $null = exiftool -overwrite_original -Title="$title" -iptc:ObjectName="$caption" -iptc:Caption-Abstract="$caption" -Description="$description" -Copyright="$copyright" -CreatorWorkURL="$($imageMetadata.copyrightlink)" $($file.FullName)
        $null = Rename-Item -Path $file.FullName $($file.BaseName + "_meta" + $file.Extension)
        $filesUpdatedCount++
    }
    Write-Verbose ""
    Write-Verbose "Summary"
    Write-Verbose "$($filesToProcess.Count) image(s) identified to process"
    Write-Verbose "$($filesUpdatedCount) image(s) updated"
}
