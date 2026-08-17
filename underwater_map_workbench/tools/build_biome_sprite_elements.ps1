[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:ExpectedMagickVersion = '7.1.2-29'
$script:CanvasWidth = 1672
$script:CanvasHeight = 941
$script:PaddingPx = 16
$script:OutputPackName = 'biomes_v3_sprite_elements_v1'
$script:OutputResRoot = "res://assets/diving/world/layout_guides/style_references/$($script:OutputPackName)"

$scriptRoot = $PSScriptRoot
$workbenchRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot '..'))
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $workbenchRoot '..'))
$styleReferenceRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'assets/diving/world/layout_guides/style_references'))
$finalRoot = [System.IO.Path]::GetFullPath((Join-Path $styleReferenceRoot $script:OutputPackName))
$magickCommand = Get-Command magick -ErrorAction Stop
$script:Magick = $magickCommand.Source

function New-SourceSpec {
    param(
        [Parameter(Mandatory = $true)][string]$PackId,
        [Parameter(Mandatory = $true)][string]$BiomeId,
        [Parameter(Mandatory = $true)][string]$LayerId,
        [Parameter(Mandatory = $true)][string]$LayerRole,
        [Parameter(Mandatory = $true)][string]$SourceRelativePath,
        [Parameter(Mandatory = $true)][string[]]$GroupRects,
        [Parameter(Mandatory = $true)][string]$GroupingPolicy
    )

    return [pscustomobject][ordered]@{
        pack_id = $PackId
        biome_id = $BiomeId
        layer_id = $LayerId
        layer_role = $LayerRole
        source_relative_path = $SourceRelativePath
        group_rects = @($GroupRects)
        grouping_policy = $GroupingPolicy
    }
}

function New-BaseSpec {
    param(
        [Parameter(Mandatory = $true)][string]$BiomeId,
        [Parameter(Mandatory = $true)][string]$SourceRelativePath
    )

    return [pscustomobject][ordered]@{
        pack_id = 'core'
        biome_id = $BiomeId
        layer_id = 'L00'
        layer_role = 'base_color'
        source_relative_path = $SourceRelativePath
    }
}

$baseSpecs = @(
    (New-BaseSpec -BiomeId 'r1_rooftops' -SourceRelativePath 'biomes_v3_six_layer/r1_rooftops/r1_rooftops_l00_base_color.png'),
    (New-BaseSpec -BiomeId 'r2_green_estates' -SourceRelativePath 'biomes_v3_six_layer/r2_green_estates/r2_green_estates_l00_base_color.png'),
    (New-BaseSpec -BiomeId 'r3_rust_belt' -SourceRelativePath 'biomes_v3_six_layer/r3_rust_belt/r3_rust_belt_l00_base_color.png'),
    (New-BaseSpec -BiomeId 'r4_black_heart' -SourceRelativePath 'biomes_v3_six_layer/r4_black_heart/r4_black_heart_l00_base_color.png')
)

$sourceSpecs = @(
    (New-SourceSpec -PackId 'core' -BiomeId 'r1_rooftops' -LayerId 'L01' -LayerRole 'ultra_far_silhouettes' -SourceRelativePath 'biomes_v3_six_layer/r1_rooftops/r1_rooftops_l01_ultra_far_silhouettes.png' -GroupRects @('0,426,332,311', '348,21,512,243', '904,18,460,246', '1217,299,455,361') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r1_rooftops' -LayerId 'L02' -LayerRole 'far_structures' -SourceRelativePath 'biomes_v3_six_layer/r1_rooftops/r1_rooftops_l02_far_structures.png' -GroupRects @('226,106,289,147', '247,721,286,87', '298,438,190,77', '891,120,558,162', '1007,647,323,147', '1083,438,86,74') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r1_rooftops' -LayerId 'L03' -LayerRole 'mid_drift_props' -SourceRelativePath 'biomes_v3_six_layer/r1_rooftops/r1_rooftops_l03_mid_drift_props.png' -GroupRects @('90,173,411,238', '223,604,220,188', '652,158,366,215', '726,501,193,296', '1189,551,296,234', '1199,189,310,191') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r1_rooftops' -LayerId 'L04' -LayerRole 'near_terrain_skin' -SourceRelativePath 'biomes_v3_six_layer/r1_rooftops/r1_rooftops_l04_near_terrain_skin.png' -GroupRects @('0,24,544,282', '0,562,440,358', '1155,514,517,375', '1181,43,491,249') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r1_rooftops' -LayerId 'L05' -LayerRole 'foreground_occluders' -SourceRelativePath 'biomes_v3_six_layer/r1_rooftops/r1_rooftops_l05_foreground_occluders.png' -GroupRects @('0,24,438,212', '0,701,352,240', '1243,726,429,215', '1332,31,340,191') -GroupingPolicy 'logical_components'),

    (New-SourceSpec -PackId 'core' -BiomeId 'r2_green_estates' -LayerId 'L01' -LayerRole 'ultra_far_silhouettes' -SourceRelativePath 'biomes_v3_six_layer/r2_green_estates/r2_green_estates_l01_ultra_far_silhouettes.png' -GroupRects @('10,439,208,330', '197,721,266,214', '316,359,140,320', '410,251,66,171', '1250,595,260,312', '1394,65,268,584') -GroupingPolicy 'logical_components_detection_dilate_4px'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r2_green_estates' -LayerId 'L02' -LayerRole 'far_structures' -SourceRelativePath 'biomes_v3_six_layer/r2_green_estates/r2_green_estates_l02_far_structures.png' -GroupRects @('0,299,267,578', '347,101,98,254', '1179,605,168,214', '1427,498,193,313', '1487,97,185,326') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r2_green_estates' -LayerId 'L03' -LayerRole 'mid_drift_props' -SourceRelativePath 'biomes_v3_six_layer/r2_green_estates/r2_green_estates_l03_mid_drift_props.png' -GroupRects @('434,564,138,195', '463,151,111,158', '764,541,189,146', '922,126,117,168', '1108,456,194,154') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r2_green_estates' -LayerId 'L04' -LayerRole 'near_terrain_skin' -SourceRelativePath 'biomes_v3_six_layer/r2_green_estates/r2_green_estates_l04_near_terrain_skin.png' -GroupRects @('0,0,331,483', '0,399,240,542', '1263,0,409,857') -GroupingPolicy 'logical_components_no_dilation'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r2_green_estates' -LayerId 'L05' -LayerRole 'foreground_occluders' -SourceRelativePath 'biomes_v3_six_layer/r2_green_estates/r2_green_estates_l05_foreground_occluders.png' -GroupRects @('0,0,200,542', '0,559,137,219', '1412,0,260,195', '1562,297,110,454') -GroupingPolicy 'four_edge_assemblages'),

    (New-SourceSpec -PackId 'core' -BiomeId 'r3_rust_belt' -LayerId 'L01' -LayerRole 'ultra_far_silhouettes' -SourceRelativePath 'biomes_v3_six_layer/r3_rust_belt/r3_rust_belt_l01_ultra_far_silhouettes.png' -GroupRects @('155,346,60,124', '232,561,100,213', '238,35,113,225', '1174,39,182,193', '1246,742,55,119', '1342,516,124,147', '1470,261,89,189') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r3_rust_belt' -LayerId 'L02' -LayerRole 'far_structures' -SourceRelativePath 'biomes_v3_six_layer/r3_rust_belt/r3_rust_belt_l02_far_structures.png' -GroupRects @('34,121,147,583', '102,517,315,398', '381,26,146,455', '1018,23,342,431', '1094,465,136,452', '1281,189,359,724') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r3_rust_belt' -LayerId 'L03' -LayerRole 'mid_drift_props' -SourceRelativePath 'biomes_v3_six_layer/r3_rust_belt/r3_rust_belt_l03_mid_drift_props.png' -GroupRects @('249,540,258,281', '295,109,251,311', '702,480,245,215', '1025,127,355,302', '1147,560,243,218') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r3_rust_belt' -LayerId 'L04' -LayerRole 'near_terrain_skin' -SourceRelativePath 'biomes_v3_six_layer/r3_rust_belt/r3_rust_belt_l04_near_terrain_skin.png' -GroupRects @('0,0,335,896', '1339,0,333,911') -GroupingPolicy 'two_edge_assemblages'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r3_rust_belt' -LayerId 'L05' -LayerRole 'foreground_occluders' -SourceRelativePath 'biomes_v3_six_layer/r3_rust_belt/r3_rust_belt_l05_foreground_occluders.png' -GroupRects @('0,0,281,941', '1329,0,343,941') -GroupingPolicy 'two_side_assemblages'),

    (New-SourceSpec -PackId 'core' -BiomeId 'r4_black_heart' -LayerId 'L01' -LayerRole 'ultra_far_silhouettes' -SourceRelativePath 'biomes_v3_six_layer/r4_black_heart/r4_black_heart_l01_ultra_far_silhouettes.png' -GroupRects @('109,0,422,941', '1084,0,588,941') -GroupingPolicy 'two_side_assemblages'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r4_black_heart' -LayerId 'L02' -LayerRole 'far_structures' -SourceRelativePath 'biomes_v3_six_layer/r4_black_heart/r4_black_heart_l02_far_structures.png' -GroupRects @('189,0,336,842', '1065,0,454,534', '1151,492,333,404') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r4_black_heart' -LayerId 'L03' -LayerRole 'mid_drift_props' -SourceRelativePath 'biomes_v3_six_layer/r4_black_heart/r4_black_heart_l03_mid_drift_props.png' -GroupRects @('345,579,169,186', '408,140,167,194', '751,672,181,142', '756,397,167,111', '1109,646,220,102', '1132,125,164,234') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r4_black_heart' -LayerId 'L04' -LayerRole 'near_terrain_skin' -SourceRelativePath 'biomes_v3_six_layer/r4_black_heart/r4_black_heart_l04_near_terrain_skin.png' -GroupRects @('12,0,517,941', '1181,0,470,922') -GroupingPolicy 'two_side_assemblages'),
    (New-SourceSpec -PackId 'core' -BiomeId 'r4_black_heart' -LayerId 'L05' -LayerRole 'foreground_occluders' -SourceRelativePath 'biomes_v3_six_layer/r4_black_heart/r4_black_heart_l05_foreground_occluders.png' -GroupRects @('0,0,490,941', '1122,0,550,941') -GroupingPolicy 'two_side_assemblages'),

    (New-SourceSpec -PackId 'r1_rooftops_supplement_v1' -BiomeId 'r1_rooftops' -LayerId 'L01' -LayerRole 'ultra_far_silhouettes' -SourceRelativePath 'r1_rooftops_l01_l04_supplement_v1/layers/r1_rooftops_supplement_v1_l01_ultra_far_silhouettes.png' -GroupRects @('0,453,318,228', '267,78,405,190', '558,765,567,123', '998,94,381,136', '1253,415,419,236') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'r1_rooftops_supplement_v1' -BiomeId 'r1_rooftops' -LayerId 'L02' -LayerRole 'far_structures' -SourceRelativePath 'r1_rooftops_l01_l04_supplement_v1/layers/r1_rooftops_supplement_v1_l02_far_structures.png' -GroupRects @('171,737,259,95', '179,111,340,103', '205,333,137,196', '525,569,148,105', '676,155,174,123', '914,725,220,67', '1111,109,382,126', '1282,354,247,137', '1299,741,194,80') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'r1_rooftops_supplement_v1' -BiomeId 'r1_rooftops' -LayerId 'L03' -LayerRole 'mid_drift_props' -SourceRelativePath 'r1_rooftops_l01_l04_supplement_v1/layers/r1_rooftops_supplement_v1_l03_mid_drift_props.png' -GroupRects @('91,571,306,151', '106,166,172,237', '380,243,150,161', '480,546,259,178', '669,211,199,179', '806,566,236,140', '988,121,148,288', '1117,610,247,84', '1230,278,311,70', '1427,549,181,170') -GroupingPolicy 'logical_components'),
    (New-SourceSpec -PackId 'r1_rooftops_supplement_v1' -BiomeId 'r1_rooftops' -LayerId 'L04' -LayerRole 'near_terrain_skin' -SourceRelativePath 'r1_rooftops_l01_l04_supplement_v1/layers/r1_rooftops_supplement_v1_l04_near_terrain_skin.png' -GroupRects @('0,24,473,252', '0,403,295,240', '4,696,433,245', '860,0,438,186', '1010,686,656,246', '1369,229,303,317') -GroupingPolicy 'logical_components')
)

function Invoke-Magick {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & $script:Magick @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick failed with exit code $LASTEXITCODE. Arguments: $($Arguments -join ' ')"
    }
}

function Assert-ExactOwnedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$ExpectedLeaf
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $prefix = $fullParent + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing filesystem mutation outside '$fullParent': '$fullPath'."
    }
    if ([System.IO.Path]::GetFileName($fullPath) -ne $ExpectedLeaf) {
        throw "Refusing filesystem mutation for unexpected leaf '$fullPath'."
    }
}

function Get-ResPath {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $fullPath = [System.IO.Path]::GetFullPath($AbsolutePath)
    $prefix = $projectRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the Godot project: '$fullPath'."
    }
    return 'res://' + $fullPath.Substring($prefix.Length).Replace('\', '/')
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Parse-Rect {
    param([Parameter(Mandatory = $true)][string]$Value)

    $parts = @($Value.Split(',') | ForEach-Object { [int]$_ })
    if ($parts.Count -ne 4) {
        throw "Invalid rect '$Value'."
    }
    $rect = [pscustomobject][ordered]@{
        x = $parts[0]
        y = $parts[1]
        width = $parts[2]
        height = $parts[3]
    }
    if ($rect.x -lt 0 -or $rect.y -lt 0 -or $rect.width -le 0 -or $rect.height -le 0 -or ($rect.x + $rect.width) -gt $script:CanvasWidth -or ($rect.y + $rect.height) -gt $script:CanvasHeight) {
        throw "Rect '$Value' is outside the source canvas."
    }
    return $rect
}

function Get-AlphaComponents {
    param([Parameter(Mandatory = $true)][string]$MaskPath)

    $lines = & $script:Magick $MaskPath '-define' 'connected-components:verbose=true' '-connected-components' '8' 'null:' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick connected-components failed for '$MaskPath'."
    }

    $components = [System.Collections.Generic.List[object]]::new()
    $pattern = '^\s*(?<id>\d+):\s+(?<width>\d+)x(?<height>\d+)\+(?<x>-?\d+)\+(?<y>-?\d+)\s+(?<cx>-?[0-9.]+),(?<cy>-?[0-9.]+)\s+(?<area>[0-9.eE+\-]+)\s+(?<color>.+)$'
    foreach ($line in $lines) {
        $text = $line.ToString()
        if ($text -notmatch $pattern) {
            continue
        }
        $color = $Matches.color.Trim()
        $isWhite = $color -eq 'srgb(255,255,255)' -or $color -eq 'gray(255)' -or $color -eq 'graya(255,1)'
        if (-not $isWhite) {
            continue
        }
        $components.Add([pscustomobject][ordered]@{
            id = [int]$Matches.id
            x = [int]$Matches.x
            y = [int]$Matches.y
            width = [int]$Matches.width
            height = [int]$Matches.height
            cx = [double]::Parse($Matches.cx, [System.Globalization.CultureInfo]::InvariantCulture)
            cy = [double]::Parse($Matches.cy, [System.Globalization.CultureInfo]::InvariantCulture)
            area = [double]::Parse($Matches.area, [System.Globalization.CultureInfo]::InvariantCulture)
        })
    }
    if ($components.Count -eq 0) {
        throw "No non-transparent components found in '$MaskPath'."
    }
    return @($components)
}

function Get-ComponentGroupIndex {
    param(
        [Parameter(Mandatory = $true)]$Component,
        [Parameter(Mandatory = $true)][object[]]$Rects
    )

    $bestIndex = -1
    $bestCategory = [int]::MaxValue
    $bestOverlapRatio = -1.0
    $bestDistance = [double]::PositiveInfinity
    $bestCenterDistance = [double]::PositiveInfinity

    for ($index = 0; $index -lt $Rects.Count; $index++) {
        $rect = $Rects[$index]
        $rectRight = $rect.x + $rect.width
        $rectBottom = $rect.y + $rect.height
        $componentRight = $Component.x + $Component.width
        $componentBottom = $Component.y + $Component.height
        $inside = $Component.cx -ge $rect.x -and $Component.cx -lt $rectRight -and $Component.cy -ge $rect.y -and $Component.cy -lt $rectBottom
        $intersectionWidth = [Math]::Max(0, [Math]::Min($componentRight, $rectRight) - [Math]::Max($Component.x, $rect.x))
        $intersectionHeight = [Math]::Max(0, [Math]::Min($componentBottom, $rectBottom) - [Math]::Max($Component.y, $rect.y))
        $intersection = $intersectionWidth * $intersectionHeight
        $componentBoxArea = [Math]::Max(1, $Component.width * $Component.height)
        $overlapRatio = [double]$intersection / [double]$componentBoxArea

        $dx = 0.0
        if ($Component.cx -lt $rect.x) {
            $dx = $rect.x - $Component.cx
        }
        elseif ($Component.cx -gt $rectRight) {
            $dx = $Component.cx - $rectRight
        }
        $dy = 0.0
        if ($Component.cy -lt $rect.y) {
            $dy = $rect.y - $Component.cy
        }
        elseif ($Component.cy -gt $rectBottom) {
            $dy = $Component.cy - $rectBottom
        }
        $distance = ($dx * $dx) + ($dy * $dy)
        $rectCenterX = $rect.x + ($rect.width / 2.0)
        $rectCenterY = $rect.y + ($rect.height / 2.0)
        $centerDistance = (($Component.cx - $rectCenterX) * ($Component.cx - $rectCenterX)) + (($Component.cy - $rectCenterY) * ($Component.cy - $rectCenterY))
        $category = if ($inside) { 0 } else { 1 }

        $isBetter = $false
        if ($category -lt $bestCategory) {
            $isBetter = $true
        }
        elseif ($category -eq $bestCategory -and $overlapRatio -gt $bestOverlapRatio) {
            $isBetter = $true
        }
        elseif ($category -eq $bestCategory -and [Math]::Abs($overlapRatio - $bestOverlapRatio) -lt 0.0000001 -and $distance -lt $bestDistance) {
            $isBetter = $true
        }
        elseif ($category -eq $bestCategory -and [Math]::Abs($overlapRatio - $bestOverlapRatio) -lt 0.0000001 -and [Math]::Abs($distance - $bestDistance) -lt 0.0000001 -and $centerDistance -lt $bestCenterDistance) {
            $isBetter = $true
        }

        if ($isBetter) {
            $bestIndex = $index
            $bestCategory = $category
            $bestOverlapRatio = $overlapRatio
            $bestDistance = $distance
            $bestCenterDistance = $centerDistance
        }
    }
    if ($bestIndex -lt 0) {
        throw 'Could not assign an alpha component to a logical group.'
    }
    return $bestIndex
}

function Get-UnionRect {
    param([Parameter(Mandatory = $true)][object[]]$Components)

    $minX = ($Components | Measure-Object -Property x -Minimum).Minimum
    $minY = ($Components | Measure-Object -Property y -Minimum).Minimum
    $maxX = ($Components | ForEach-Object { $_.x + $_.width } | Measure-Object -Maximum).Maximum
    $maxY = ($Components | ForEach-Object { $_.y + $_.height } | Measure-Object -Maximum).Maximum
    return [pscustomobject][ordered]@{
        x = [int]$minX
        y = [int]$minY
        width = [int]($maxX - $minX)
        height = [int]($maxY - $minY)
    }
}

function Get-EdgeContacts {
    param([Parameter(Mandatory = $true)]$Rect)

    $contacts = [System.Collections.Generic.List[string]]::new()
    if ($Rect.x -eq 0) { $contacts.Add('left') }
    if ($Rect.y -eq 0) { $contacts.Add('top') }
    if (($Rect.x + $Rect.width) -eq $script:CanvasWidth) { $contacts.Add('right') }
    if (($Rect.y + $Rect.height) -eq $script:CanvasHeight) { $contacts.Add('bottom') }
    return @($contacts)
}

function Format-GeometryOffset {
    param([int]$X, [int]$Y)
    $xText = if ($X -ge 0) { "+$X" } else { "$X" }
    $yText = if ($Y -ge 0) { "+$Y" } else { "$Y" }
    return "$xText$yText"
}

function Get-AbsoluteError {
    param(
        [Parameter(Mandatory = $true)][string]$First,
        [Parameter(Mandatory = $true)][string]$Second
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $metric = & $script:Magick compare '-metric' 'AE' $First $Second 'null:' 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    $metricText = ($metric | ForEach-Object { $_.ToString() }) -join ' '
    if ($metricText -notmatch '^\s*(?<value>[0-9.eE+\-]+)') {
        throw "Could not parse ImageMagick AE metric: '$metricText'."
    }
    $value = [double]::Parse($Matches.value, [System.Globalization.CultureInfo]::InvariantCulture)
    if ($exitCode -notin @(0, 1)) {
        throw "ImageMagick compare failed with exit code $exitCode."
    }
    return [int64][Math]::Round($value)
}

function New-Reconstruction {
    param(
        [Parameter(Mandatory = $true)]$Spec,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][object[]]$Elements,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$WorkRoot
    )

    $key = "$($Spec.pack_id)_$($Spec.biome_id)_$($Spec.layer_id)"
    $reconstructionDirectory = Join-Path $TargetRoot 'derived/reconstructions'
    New-Item -ItemType Directory -Path $reconstructionDirectory -Force | Out-Null
    $reconstructionPath = Join-Path $reconstructionDirectory "${key}_reconstruction.png"
    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('-size')
    $arguments.Add("$($script:CanvasWidth)x$($script:CanvasHeight)")
    $arguments.Add('canvas:none')
    foreach ($element in $Elements) {
        $elementPath = [System.IO.Path]::GetFullPath((Join-Path $TargetRoot $element.output_relative_path))
        $arguments.Add($elementPath)
        $arguments.Add('-geometry')
        $arguments.Add((Format-GeometryOffset -X $element.reconstruction_top_left_px[0] -Y $element.reconstruction_top_left_px[1]))
        $arguments.Add('-compose')
        $arguments.Add('Over')
        $arguments.Add('-composite')
    }
    $arguments.Add('-colorspace')
    $arguments.Add('sRGB')
    $arguments.Add('-type')
    $arguments.Add('TrueColorAlpha')
    $arguments.Add('-depth')
    $arguments.Add('8')
    $arguments.Add('-strip')
    $arguments.Add('-define')
    $arguments.Add('png:compression-level=9')
    $arguments.Add('-define')
    $arguments.Add('png:compression-strategy=1')
    $arguments.Add('-define')
    $arguments.Add('png:color-type=6')
    $arguments.Add($reconstructionPath)
    Invoke-Magick -Arguments @($arguments)

    $sourceAlpha = Join-Path $WorkRoot "${key}_source_alpha.png"
    $reconstructionAlpha = Join-Path $WorkRoot "${key}_reconstruction_alpha.png"
    Invoke-Magick -Arguments @($SourcePath, '-alpha', 'extract', '-depth', '8', '-strip', $sourceAlpha)
    Invoke-Magick -Arguments @($reconstructionPath, '-alpha', 'extract', '-depth', '8', '-strip', $reconstructionAlpha)
    $alphaAe = Get-AbsoluteError -First $sourceAlpha -Second $reconstructionAlpha

    $flattenMetrics = [ordered]@{}
    foreach ($background in @('black', 'white')) {
        $sourceFlat = Join-Path $WorkRoot "${key}_source_${background}.png"
        $reconstructionFlat = Join-Path $WorkRoot "${key}_reconstruction_${background}.png"
        Invoke-Magick -Arguments @($SourcePath, '-background', $background, '-alpha', 'remove', '-alpha', 'off', '-depth', '8', '-strip', $sourceFlat)
        Invoke-Magick -Arguments @($reconstructionPath, '-background', $background, '-alpha', 'remove', '-alpha', 'off', '-depth', '8', '-strip', $reconstructionFlat)
        $flattenMetrics[$background] = Get-AbsoluteError -First $sourceFlat -Second $reconstructionFlat
    }

    if ($alphaAe -ne 0 -or $flattenMetrics.black -ne 0 -or $flattenMetrics.white -ne 0) {
        throw "Reconstruction mismatch for '$key': alpha=$alphaAe black=$($flattenMetrics.black) white=$($flattenMetrics.white)."
    }

    $relative = [System.IO.Path]::GetRelativePath($TargetRoot, $reconstructionPath).Replace('\', '/')
    return [pscustomobject][ordered]@{
        output_path = "$($script:OutputResRoot)/$relative"
        output_relative_path = $relative
        output_sha256 = Get-Sha256 -Path $reconstructionPath
        alpha_absolute_error_pixels = $alphaAe
        black_flatten_absolute_error_pixels = $flattenMetrics.black
        white_flatten_absolute_error_pixels = $flattenMetrics.white
    }
}

function Process-Source {
    param(
        [Parameter(Mandatory = $true)]$Spec,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$WorkRoot
    )

    $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $styleReferenceRoot $Spec.source_relative_path))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Missing source layer '$sourcePath'."
    }
    $dimensions = (& $script:Magick identify '-format' '%w,%h,%[channels],%z' $sourcePath).Trim()
    if ($LASTEXITCODE -ne 0 -or $dimensions -notmatch "^$($script:CanvasWidth),$($script:CanvasHeight),") {
        throw "Unexpected source dimensions for '$sourcePath': '$dimensions'."
    }

    $key = "$($Spec.pack_id)_$($Spec.biome_id)_$($Spec.layer_id)"
    $binaryMask = Join-Path $WorkRoot "${key}_alpha_nonzero.png"
    Invoke-Magick -Arguments @($sourcePath, '-alpha', 'extract', '-threshold', '0', '-type', 'bilevel', '-colorspace', 'sRGB', '-depth', '8', '-strip', "PNG24:$binaryMask")
    $components = @(Get-AlphaComponents -MaskPath $binaryMask)
    $rects = @($Spec.group_rects | ForEach-Object { Parse-Rect -Value $_ })
    $groups = @()
    for ($index = 0; $index -lt $rects.Count; $index++) {
        $groups += ,([System.Collections.Generic.List[object]]::new())
    }
    foreach ($component in $components) {
        $groupIndex = Get-ComponentGroupIndex -Component $component -Rects $rects
        $groups[$groupIndex].Add($component)
    }
    for ($index = 0; $index -lt $groups.Count; $index++) {
        if ($groups[$index].Count -eq 0) {
            throw "Logical group $($index + 1) has no pixels for '$key'."
        }
    }

    $namespace = if ($Spec.pack_id -eq 'core') { $Spec.biome_id } else { $Spec.pack_id }
    $outputDirectoryRelative = "$namespace/$($Spec.layer_id.ToLowerInvariant())_$($Spec.layer_role)"
    $outputDirectory = Join-Path $TargetRoot $outputDirectoryRelative
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $elementRecords = [System.Collections.Generic.List[object]]::new()

    for ($index = 0; $index -lt $groups.Count; $index++) {
        $elementNumber = $index + 1
        $elementToken = 'e{0:d2}' -f $elementNumber
        $groupComponents = @($groups[$index])
        $unionRect = Get-UnionRect -Components $groupComponents
        $semanticRect = $rects[$index]
        $edgeContacts = @(Get-EdgeContacts -Rect $semanticRect)
        $componentIds = @($groupComponents | Sort-Object id | ForEach-Object { $_.id })
        $keep = $componentIds -join ','
        $groupMask = Join-Path $WorkRoot "${key}_${elementToken}_mask.png"
        $alphaProduct = Join-Path $WorkRoot "${key}_${elementToken}_alpha.png"

        Invoke-Magick -Arguments @($binaryMask, '-define', "connected-components:keep=$keep", '-define', 'connected-components:mean-color=true', '-connected-components', '8', '-depth', '8', '-strip', "PNG24:$groupMask")
        Invoke-Magick -Arguments @($sourcePath, '-alpha', 'extract', $groupMask, '-compose', 'Multiply', '-composite', '-alpha', 'off', '-depth', '8', '-strip', $alphaProduct)

        $fileStem = "$namespace`_$($Spec.layer_id.ToLowerInvariant())_$($Spec.layer_role)_$elementToken"
        $outputPath = Join-Path $outputDirectory "$fileStem.png"
        $cropGeometry = "$($unionRect.width)x$($unionRect.height)+$($unionRect.x)+$($unionRect.y)"
        Invoke-Magick -Arguments @($sourcePath, $alphaProduct, '-compose', 'CopyAlpha', '-composite', '-crop', $cropGeometry, '+repage', '-compose', 'Over', '-bordercolor', 'none', '-border', "$($script:PaddingPx)", '-colorspace', 'sRGB', '-type', 'TrueColorAlpha', '-depth', '8', '-strip', '-define', 'png:compression-level=9', '-define', 'png:compression-strategy=1', '-define', 'png:color-type=6', $outputPath)

        $outputWidth = $unionRect.width + (2 * $script:PaddingPx)
        $outputHeight = $unionRect.height + (2 * $script:PaddingPx)
        $actualOutput = (& $script:Magick identify '-format' '%w,%h,%[channels],%z,%[fx:minima.a],%[fx:maxima.a]' $outputPath).Trim()
        $outputPattern = "^$outputWidth,$outputHeight,srgba(?: 4\.0)?,8,0,(?<alphaMax>[0-9.]+)$"
        if ($LASTEXITCODE -ne 0 -or $actualOutput -notmatch $outputPattern) {
            throw "Unexpected output properties for '$outputPath': '$actualOutput'."
        }
        $alphaMax = [double]::Parse($Matches.alphaMax, [System.Globalization.CultureInfo]::InvariantCulture)
        if ($alphaMax -le 0.0) {
            throw "Output has no visible alpha for '$outputPath'."
        }

        $outputRelativePath = [System.IO.Path]::GetRelativePath($TargetRoot, $outputPath).Replace('\', '/')
        $initialPositionX = $unionRect.x + ($unionRect.width / 2.0)
        $initialPositionY = $unionRect.y + ($unionRect.height / 2.0)
        $isEdgeLocked = $edgeContacts.Count -gt 0
        $elementRecords.Add([pscustomobject][ordered]@{
            visual_asset_id = "$namespace.$($Spec.layer_id.ToLowerInvariant()).$elementToken"
            biome_id = $Spec.biome_id
            pack_id = $Spec.pack_id
            layer_id = $Spec.layer_id
            layer_role = $Spec.layer_role
            output_path = "$($script:OutputResRoot)/$outputRelativePath"
            output_relative_path = $outputRelativePath
            output_sha256 = Get-Sha256 -Path $outputPath
            output_dimensions_px = @($outputWidth, $outputHeight)
            source_rect_px = @($unionRect.x, $unionRect.y, $unionRect.width, $unionRect.height)
            semantic_group_rect_px = @($semanticRect.x, $semanticRect.y, $semanticRect.width, $semanticRect.height)
            crop_padding_px = $script:PaddingPx
            reconstruction_top_left_px = @(($unionRect.x - $script:PaddingPx), ($unionRect.y - $script:PaddingPx))
            sprite2d_centered = $true
            sprite2d_initial_position_px = @($initialPositionX, $initialPositionY)
            pivot_px = @(($outputWidth / 2.0), ($outputHeight / 2.0))
            source_component_ids_diagnostic = $componentIds
            source_component_count = $componentIds.Count
            edge_contacts = $edgeContacts
            edge_locked = $isEdgeLocked
            source_clipped = $isEdgeLocked
            free_reposition_safe = -not $isEdgeLocked
            requires_outpaint_for_free_move = $isEdgeLocked
            reference_only = $true
            runtime_wired = $false
        })
    }

    $reconstruction = New-Reconstruction -Spec $Spec -SourcePath $sourcePath -Elements @($elementRecords) -TargetRoot $TargetRoot -WorkRoot $WorkRoot
    return [pscustomobject][ordered]@{
        pack_id = $Spec.pack_id
        biome_id = $Spec.biome_id
        layer_id = $Spec.layer_id
        layer_role = $Spec.layer_role
        source_path = Get-ResPath -AbsolutePath $sourcePath
        source_sha256 = Get-Sha256 -Path $sourcePath
        source_canvas_px = @($script:CanvasWidth, $script:CanvasHeight)
        source_alpha_mode = 'srgba8'
        detection_contract = [pscustomobject][ordered]@{
            semantic_seed_alpha_threshold_8bit = 16
            semantic_seed_min_area_px = 500
            exact_extraction_alpha_threshold = 'alpha_gt_0'
            connectivity = 8
            grouping_policy = $Spec.grouping_policy
            ownership_rule = 'nearest_audited_logical_rect; ties resolve by audited element order'
        }
        expected_element_count = $Spec.group_rects.Count
        actual_element_count = $elementRecords.Count
        elements = @($elementRecords)
        reconstruction = $reconstruction
    }
}

function New-ContactSheet {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][object[]]$Elements,
        [Parameter(Mandatory = $true)][string]$TargetRoot
    )

    $sortedElements = @($Elements | Sort-Object output_relative_path)
    if ($sortedElements.Count -eq 0) {
        throw "No elements available for contact sheet '$Name'."
    }
    $derivedRoot = Join-Path $TargetRoot 'derived/contact_sheets'
    New-Item -ItemType Directory -Path $derivedRoot -Force | Out-Null
    $outputPath = Join-Path $derivedRoot "$Name.png"
    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('montage')
    foreach ($element in $sortedElements) {
        $path = [System.IO.Path]::GetFullPath((Join-Path $TargetRoot $element.output_relative_path))
        $elementToken = $element.visual_asset_id.Split('.')[-1]
        $edgeSuffix = if ($element.edge_locked) { ' [EDGE]' } else { '' }
        $label = "$($element.layer_id) $elementToken $($element.output_dimensions_px[0])x$($element.output_dimensions_px[1])$edgeSuffix"
        foreach ($value in @('(', $path, '-set', 'label', $label, ')')) { $arguments.Add($value) }
    }
    foreach ($value in @('-thumbnail', '240x160', '-background', '#102028', '-fill', 'white', '-stroke', 'none', '-pointsize', '14', '-tile', '6x', '-geometry', '240x190+8+8', '-depth', '8', '-strip', '-define', 'png:compression-level=9', '-define', 'png:compression-strategy=1', $outputPath)) {
        $arguments.Add($value)
    }
    Invoke-Magick -Arguments @($arguments)
    $relative = [System.IO.Path]::GetRelativePath($TargetRoot, $outputPath).Replace('\', '/')
    return [pscustomobject][ordered]@{
        output_path = "$($script:OutputResRoot)/$relative"
        output_relative_path = $relative
        output_sha256 = Get-Sha256 -Path $outputPath
        element_count = $sortedElements.Count
    }
}

function Build-Pack {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)

    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
    $workRoot = Join-Path $TargetRoot '.build_work'
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    $baseRecords = [System.Collections.Generic.List[object]]::new()
    foreach ($baseSpec in $baseSpecs) {
        $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $styleReferenceRoot $baseSpec.source_relative_path))
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Missing L00 source '$sourcePath'."
        }
        $outputRelative = "$($baseSpec.biome_id)/l00_base_color/$($baseSpec.biome_id)_l00_base_color.png"
        $outputPath = Join-Path $TargetRoot $outputRelative
        New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $outputPath -Force
        $sourceHash = Get-Sha256 -Path $sourcePath
        $outputHash = Get-Sha256 -Path $outputPath
        if ($sourceHash -ne $outputHash) {
            throw "L00 byte copy mismatch for '$sourcePath'."
        }
        $baseRecords.Add([pscustomobject][ordered]@{
            visual_asset_id = "$($baseSpec.biome_id).l00.base_color"
            biome_id = $baseSpec.biome_id
            pack_id = 'core'
            layer_id = 'L00'
            layer_role = 'base_color'
            source_path = Get-ResPath -AbsolutePath $sourcePath
            source_sha256 = $sourceHash
            output_path = "$($script:OutputResRoot)/$($outputRelative.Replace('\', '/'))"
            output_relative_path = $outputRelative.Replace('\', '/')
            output_sha256 = $outputHash
            output_dimensions_px = @($script:CanvasWidth, $script:CanvasHeight)
            full_canvas_base = $true
            sprite2d_centered = $true
            sprite2d_initial_position_px = @(($script:CanvasWidth / 2.0), ($script:CanvasHeight / 2.0))
            reference_only = $true
            runtime_wired = $false
        })
    }

    $sourceRecords = [System.Collections.Generic.List[object]]::new()
    $allElements = [System.Collections.Generic.List[object]]::new()
    foreach ($spec in $sourceSpecs) {
        Write-Host "Splitting $($spec.pack_id)/$($spec.biome_id)/$($spec.layer_id)..."
        $sourceRecord = Process-Source -Spec $spec -TargetRoot $TargetRoot -WorkRoot $workRoot
        $sourceRecords.Add($sourceRecord)
        foreach ($element in $sourceRecord.elements) { $allElements.Add($element) }
    }

    $contactSheets = [System.Collections.Generic.List[object]]::new()
    foreach ($biomeId in @('r1_rooftops', 'r2_green_estates', 'r3_rust_belt', 'r4_black_heart')) {
        $elements = @($allElements | Where-Object { $_.pack_id -eq 'core' -and $_.biome_id -eq $biomeId })
        $contactSheets.Add((New-ContactSheet -Name "${biomeId}_core_sprite_elements_contact_sheet" -Elements $elements -TargetRoot $TargetRoot))
    }
    $supplementElements = @($allElements | Where-Object { $_.pack_id -eq 'r1_rooftops_supplement_v1' })
    $contactSheets.Add((New-ContactSheet -Name 'r1_rooftops_supplement_v1_sprite_elements_contact_sheet' -Elements $supplementElements -TargetRoot $TargetRoot))

    $edgeLockedCore = @($allElements | Where-Object { $_.pack_id -eq 'core' -and $_.edge_locked }).Count
    $edgeLockedSupplement = @($allElements | Where-Object { $_.pack_id -eq 'r1_rooftops_supplement_v1' -and $_.edge_locked }).Count
    if ($baseRecords.Count -ne 4 -or @($allElements | Where-Object pack_id -eq 'core').Count -ne 84 -or $supplementElements.Count -ne 30) {
        throw "Unexpected pack counts: L00=$($baseRecords.Count), core=$(@($allElements | Where-Object pack_id -eq 'core').Count), supplement=$($supplementElements.Count)."
    }
    if ($edgeLockedCore -ne 31 -or $edgeLockedSupplement -ne 7) {
        throw "Unexpected edge-locked counts: core=$edgeLockedCore supplement=$edgeLockedSupplement."
    }

    $manifest = [pscustomobject][ordered]@{
        schema_version = 1
        pack_id = $script:OutputPackName
        status = 'reference_only_runtime_unwired'
        generated_from = @(
            'res://assets/diving/world/layout_guides/style_references/biomes_v3_six_layer/biome_six_layer_reference_set_v3.json',
            'res://assets/diving/world/layout_guides/style_references/r1_rooftops_l01_l04_supplement_v1/r1_rooftops_l01_l04_supplement_v1.json'
        )
        authority_note = 'This manifest is provenance for PNG derivatives only. Godot scenes own production transforms and visibility; these IDs are not gameplay stable IDs.'
        sprite2d_contract = [pscustomobject][ordered]@{
            texture_type = 'srgba8_png'
            centered = $true
            crop_padding_px = $script:PaddingPx
            initial_position_space = 'source_canvas_pixels_top_left_origin'
            source_canvas_px = @($script:CanvasWidth, $script:CanvasHeight)
            independent_transform = $true
        }
        edge_policy = [pscustomobject][ordered]@{
            source_edge_contact_means_clipped = $true
            free_reposition_safe_when_edge_locked = $false
            recommendation = 'Keep on the matching canvas edge or outpaint before moving into open water.'
        }
        toolchain = [pscustomobject][ordered]@{
            generator = 'res://underwater_map_workbench/tools/build_biome_sprite_elements.ps1'
            imagemagick_version = $script:ExpectedMagickVersion
            deterministic_check = 'powershell -ExecutionPolicy Bypass -File .\\tools\\build_biome_sprite_elements.ps1 -Check'
        }
        counts = [pscustomobject][ordered]@{
            base_layer_png = $baseRecords.Count
            core_movable_element_png = @($allElements | Where-Object pack_id -eq 'core').Count
            r1_supplement_movable_element_png = $supplementElements.Count
            total_sprite_ready_png = $baseRecords.Count + $allElements.Count
            core_edge_locked = $edgeLockedCore
            r1_supplement_edge_locked = $edgeLockedSupplement
        }
        base_layers = @($baseRecords)
        sources = @($sourceRecords)
        contact_sheets = @($contactSheets)
    }

    $manifestPath = Join-Path $TargetRoot 'biome_sprite_element_set_v1.json'
    $json = $manifest | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($manifestPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

    $resolvedWorkRoot = [System.IO.Path]::GetFullPath($workRoot)
    Assert-ExactOwnedPath -Path $resolvedWorkRoot -Parent $TargetRoot -ExpectedLeaf '.build_work'
    Remove-Item -LiteralPath $resolvedWorkRoot -Recurse -Force
}

function Compare-Pack {
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedRoot,
        [Parameter(Mandatory = $true)][string]$ActualRoot
    )

    if (-not (Test-Path -LiteralPath $ExpectedRoot -PathType Container)) {
        throw "Cannot check missing generated pack '$ExpectedRoot'."
    }
    $expectedFiles = @(Get-ChildItem -LiteralPath $ExpectedRoot -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($ExpectedRoot, $_.FullName).Replace('\', '/') } | Sort-Object)
    $actualFiles = @(Get-ChildItem -LiteralPath $ActualRoot -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($ActualRoot, $_.FullName).Replace('\', '/') } | Sort-Object)
    if (($expectedFiles -join "`n") -ne ($actualFiles -join "`n")) {
        throw 'Generated pack file list differs from the deterministic candidate.'
    }
    foreach ($relative in $expectedFiles) {
        $expectedHash = Get-Sha256 -Path (Join-Path $ExpectedRoot $relative)
        $actualHash = Get-Sha256 -Path (Join-Path $ActualRoot $relative)
        if ($expectedHash -ne $actualHash) {
            throw "Generated pack differs at '$relative'."
        }
    }
}

$versionLine = (& $script:Magick '-version' | Select-Object -First 1).ToString()
if ($versionLine -notmatch [regex]::Escape("Version: ImageMagick $($script:ExpectedMagickVersion)")) {
    throw "Expected ImageMagick $($script:ExpectedMagickVersion), got '$versionLine'."
}

if ($Check) {
    $tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $tempLeaf = "codex_$($script:OutputPackName)_check_$([Guid]::NewGuid().ToString('N'))"
    $candidateRoot = [System.IO.Path]::GetFullPath((Join-Path $tempParent $tempLeaf))
    Assert-ExactOwnedPath -Path $candidateRoot -Parent $tempParent -ExpectedLeaf $tempLeaf
    try {
        Build-Pack -TargetRoot $candidateRoot
        Compare-Pack -ExpectedRoot $finalRoot -ActualRoot $candidateRoot
        Write-Host "PASS: $($script:OutputPackName) is deterministic and current."
    }
    finally {
        if (Test-Path -LiteralPath $candidateRoot) {
            Assert-ExactOwnedPath -Path $candidateRoot -Parent $tempParent -ExpectedLeaf $tempLeaf
            Remove-Item -LiteralPath $candidateRoot -Recurse -Force
        }
    }
    exit 0
}

$stagingLeaf = "$($script:OutputPackName).__staging"
$stagingRoot = [System.IO.Path]::GetFullPath((Join-Path $styleReferenceRoot $stagingLeaf))
Assert-ExactOwnedPath -Path $stagingRoot -Parent $styleReferenceRoot -ExpectedLeaf $stagingLeaf
if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
Build-Pack -TargetRoot $stagingRoot
Assert-ExactOwnedPath -Path $finalRoot -Parent $styleReferenceRoot -ExpectedLeaf $script:OutputPackName
if (Test-Path -LiteralPath $finalRoot) {
    Remove-Item -LiteralPath $finalRoot -Recurse -Force
}
Move-Item -LiteralPath $stagingRoot -Destination $finalRoot
Write-Host "Built $($script:OutputPackName) at '$finalRoot'."
