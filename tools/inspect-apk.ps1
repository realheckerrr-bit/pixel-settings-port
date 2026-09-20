param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]] $Apk
)

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-U16([byte[]] $Data, [int] $Offset) {
    return [BitConverter]::ToUInt16($Data, $Offset)
}

function Read-U32([byte[]] $Data, [int] $Offset) {
    return [BitConverter]::ToUInt32($Data, $Offset)
}

function Read-StringPool([byte[]] $Data, [int] $ChunkOffset) {
    $count = Read-U32 $Data ($ChunkOffset + 8)
    $flags = Read-U32 $Data ($ChunkOffset + 16)
    $stringsStart = Read-U32 $Data ($ChunkOffset + 20)
    $offsetsStart = $ChunkOffset + (Read-U16 $Data ($ChunkOffset + 2))
    $utf8 = (($flags -band 0x100) -ne 0)
    $strings = New-Object 'System.Collections.Generic.List[string]'

    for ($index = 0; $index -lt $count; $index++) {
        $position = $ChunkOffset + $stringsStart + (Read-U32 $Data ($offsetsStart + ($index * 4)))
        if ($utf8) {
            $first = $Data[$position]
            $position++
            if (($first -band 0x80) -ne 0) { $position++ }
            $length = $Data[$position]
            $position++
            if (($length -band 0x80) -ne 0) {
                $length = (($length -band 0x7f) -shl 8) -bor $Data[$position]
                $position++
            }
            $strings.Add([Text.Encoding]::UTF8.GetString($Data, $position, $length))
        } else {
            $length = Read-U16 $Data $position
            $position += 2
            if (($length -band 0x8000) -ne 0) {
                $length = (($length -band 0x7fff) -shl 16) -bor (Read-U16 $Data $position)
                $position += 2
            }
            $strings.Add([Text.Encoding]::Unicode.GetString($Data, $position, $length * 2))
        }
    }
    return $strings.ToArray()
}

function Resolve-Value([int] $Type, [uint32] $Value, [string[]] $Strings) {
    switch ($Type) {
        0x03 { if ($Value -lt $Strings.Count) { return $Strings[$Value] }; return "#$Value" }
        0x10 { return [int64]$Value }
        0x11 { return ('0x{0:x8}' -f $Value) }
        0x12 { return ($Value -ne 0) }
        0x01 { return ('@0x{0:x8}' -f $Value) }
        0x02 { return ('?0x{0:x8}' -f $Value) }
        default { return @{ type = ('0x{0:x2}' -f $Type); value = $Value } }
    }
}

function Read-Axml([byte[]] $Data) {
    $strings = @()
    $elements = New-Object 'System.Collections.Generic.List[object]'
    $offset = 0
    while (($offset + 8) -le $Data.Length) {
        $chunkType = Read-U16 $Data $offset
        $headerSize = Read-U16 $Data ($offset + 2)
        $chunkSize = Read-U32 $Data ($offset + 4)
        if (($chunkSize -lt $headerSize) -or (($offset + $chunkSize) -gt $Data.Length)) { break }

        if (($offset -eq 0) -and ($chunkType -eq 0x0003)) {
            $offset += $headerSize
            continue
        }

        if ($chunkType -eq 0x0001) {
            $strings = Read-StringPool $Data $offset
        } elseif (($chunkType -eq 0x0102) -and ($strings.Count -gt 0)) {
            $nameIndex = Read-U32 $Data ($offset + 20)
            $name = if ($nameIndex -lt $strings.Count) { $strings[$nameIndex] } else { "#$nameIndex" }
            $attributeStart = Read-U16 $Data ($offset + 24)
            $attributeSize = Read-U16 $Data ($offset + 26)
            $attributeCount = Read-U16 $Data ($offset + 28)
            $attributeOffset = $offset + 16 + $attributeStart
            $attributes = [ordered]@{}
            for ($index = 0; $index -lt $attributeCount; $index++) {
                $current = $attributeOffset + ($index * $attributeSize)
                $attrNameIndex = Read-U32 $Data ($current + 4)
                $rawIndex = Read-U32 $Data ($current + 8)
                $type = $Data[$current + 15]
                $value = Read-U32 $Data ($current + 16)
                $attrName = if ($attrNameIndex -lt $strings.Count) { $strings[$attrNameIndex] } else { "#$attrNameIndex" }
                $attrValue = if (($rawIndex -ne 0xffffffff) -and ($rawIndex -lt $strings.Count)) {
                    $strings[$rawIndex]
                } else {
                    Resolve-Value $type $value $strings
                }
                $attributes[$attrName] = $attrValue
            }
            $elements.Add([ordered]@{ tag = $name; attributes = $attributes })
        }
        $offset += $chunkSize
    }

    $manifest = if (($elements.Count -gt 0) -and ($elements[0].tag -eq 'manifest')) { $elements[0] } else { @{ attributes = @{} } }
    $result = [ordered]@{
        package = $manifest.attributes['package']
        versionCode = $manifest.attributes['versionCode']
        versionName = $manifest.attributes['versionName']
        minSdk = $null
        targetSdk = $null
        permissions = New-Object 'System.Collections.Generic.List[object]'
        components = New-Object 'System.Collections.Generic.List[object]'
        elements = $elements.ToArray()
    }
    foreach ($element in $elements) {
        switch ($element.tag) {
            'uses-sdk' {
                $result.minSdk = $element.attributes['minSdkVersion']
                $result.targetSdk = $element.attributes['targetSdkVersion']
            }
            'uses-permission' { $result.permissions.Add($element.attributes['name']) }
            { $_ -in @('activity', 'activity-alias', 'receiver', 'service', 'provider') } {
                $component = [ordered]@{ type = $element.tag }
                foreach ($key in $element.attributes.Keys) { $component[$key] = $element.attributes[$key] }
                $result.components.Add($component)
            }
        }
    }
    return $result
}

function Inspect-Apk([string] $Path) {
    $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path))
    try {
        $entry = $zip.GetEntry('AndroidManifest.xml')
        $stream = $entry.Open()
        try {
            $bytes = New-Object byte[] $entry.Length
            $read = 0
            while ($read -lt $bytes.Length) { $read += $stream.Read($bytes, $read, $bytes.Length - $read) }
        } finally { $stream.Dispose() }
        $result = Read-Axml $bytes
        $entries = $zip.Entries | ForEach-Object { $_.FullName }
        $result.apk = [IO.Path]::GetFileName($Path)
        $result.size = (Get-Item -LiteralPath $Path).Length
        $result.signatureFiles = @($entries | Where-Object { $_ -match '^META-INF/.*\.(RSA|DSA|EC)$' })
        $result.hasNativeLibraries = @($entries | Where-Object { $_ -like 'lib/*' }).Count -gt 0
        return $result
    } finally { $zip.Dispose() }
}

@(foreach ($path in $Apk) { Inspect-Apk $path }) | ConvertTo-Json -Depth 8
