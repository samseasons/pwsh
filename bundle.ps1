# ./bundle.ps1 a/a.js a/y.js

$base64 = '$0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz'

function resolve($f, $file) {
    if ($f.StartsWith('./')) {
        $f = $f.Substring(2)
    }
    $i = $f[0]
    if ($i -ne '.' -and $i -ne '/') {
        $f = $file.Substring(0, $file.LastIndexOf('/')) + '/' + $f
    } elseif ($f.StartsWith('../')) {
        while ($f.StartsWith('../')) {
            $f = $f.Substring(3)
            $file = $file.Substring(0, $file.LastIndexOf('/'))
        }
        $f = $file.Substring(0, $file.LastIndexOf('/')) + '/' + $f
    }
    if (-not $f.EndsWith('.js')) {
        $f += '.js'
    }
    return $f
}

function substitute($text, $past, $next) {
    $a = 0
    $i = $past.Length
    $j = $next.Length
    while (($a = $text.IndexOf($past, $a)) -ne -1) {
        if ($text.Length -lt $a + $i + 1) {
            break
        } elseif ($base64.Contains($text[$a + $i]) -or ($a -ne 0 -and ($base64 + "`"'.").Contains($text[$a - 1]))) {
            $a += $i
            continue
        }
        $text = $text.Substring(0, $a) + $next + $text.Substring($a + $i)
        $a += $j
    }
    return $text
}

function parse($file, $modules, $texts) {
    if (Test-Path -Path $file) {
        $text = (Get-Content $file) ?? ''
    } else {
        $texts[$file] = ''
        return
    }
    $lines = $text.Split("`n")
    $remove = $false
    $text = ''
    foreach ($line in $lines) {
        if ($line.TrimStart("`t ").StartsWith('//')) {
            continue
        }
        if (-not $remove -and ($i = $line.IndexOf('/*')) -ne -1 -and -not $line.Contains('//*')) {
            if (($j = $line.IndexOf('*/')) -ne -1) {
                $line = $line.Substring(0, $i) + ' ' + $line.Substring($j + 2)
            } else {
                $line = $line.Substring(0, $i)
                $remove = $true
            }
        }
        if ($remove) {
            if (($i = $line.IndexOf('*/')) -ne -1) {
                $line = $line.Substring($i + 2)
                $remove = $false
            } else {
                continue
            }
        }
        $line = $line.TrimEnd("`t ")
        if ($line) {
            $text += $line + "`n"
        }
    }
    $files = @{$file = @()}
    $order = @()
    $texta = $text
    while (($i = $text.IndexOf('import ')) -ne -1) {
        if ($i -ne 0) {
            $j = $text[$i - 1]
            if ($j -ne "`t" -and $j -ne "`n" -and $j -ne ' ') {
                $text = $text.Substring($i + 6)
                continue
            }
        }
        $i += 6
        while ($text[$i] -eq ' ') {
            $i += 1
        }
        $text = $text.Substring($i)
        $i = $text.IndexOf('from')
        $j = $text.IndexOf('"')
        $k = $text.IndexOf("'")
        $names = @()
        if ($i -ne -1 -and ($i -lt $j -or $j -eq -1) -and ($i -lt $k -or $k -eq -1)) {
            while ($i -lt $text.Length) {
                $j = $text[$i - 1]
                $k = $text[$i + 4]
                if (($j -eq ' ' -or $j -eq '}') -and ($k -eq ' ' -or $k -eq '"' -or $k -eq "'")) {
                    break
                }
                $i += 4
                $i += $text.Substring($i).IndexOf('from')
            }
            $names = $text.Substring(0, $i) -split "[ ,{}]" | Where-Object { $_ -ne '' }
            $i += 5
            while ($text[$i] -eq ' ') {
                $i += 1
            }
        } else {
            $i = 0
        }
        $f = $text[$i]
        if ($f -eq '"' -or $f -eq "'") {
            $text = $text.Substring($i + 1)
            $f = resolve $text.Substring(0, $text.IndexOf($f)) $file
            if ($f -notin $order) {
                $files[$f] = @()
                $order += $f
            }
            $files[$f] += $names
        }
    }
    $mods = @()
    $modules[$file] = @()
    foreach ($f in $order) {
        if (-not $texts.ContainsKey($f)) {
            $mods += $f
            if (-not $modules.ContainsKey($f)) {
                $modules[$file] = $mods
                return
            }
        }
    }
    $declares = @('async', 'class', 'const', 'default', 'function', 'let', 'var')
    $defines = @("`n", ' ', '(', ',', '.', '[')
    $text = $texta
    while (($i = $text.IndexOf('export ')) -ne -1) {
        $text = $text.Substring($i + 7)
        foreach ($name in $declares) {
            $i = $text.IndexOf($name)
            if ($i -ne -1 -and $i -lt 3) {
                $text = $text.Substring($i + $name.Length)
            }
        }
        $names = ''
        if (($i = $text.IndexOf("`n")) -ne -1) {
            $names = $text.Substring(0, $i)
        }
        $i = 0
        while ($names[$i] -eq ' ') {
            $i += 1
        }
        $split = @()
        if ($names[$i] -eq '{') {
            $names = $names.Substring($i + 1)
            $split = $names.Substring(0, $names.IndexOf('}')).Split(',')
        } else {
            $i = $names.IndexOf('(')
            $j = $names.IndexOf('=')
            if ($j -eq -1 -or ($i -lt $j -and $i -ne -1)) {
                $split += $names
            } else {
                while ($j -ne -1 -and $names[$j + 1] -ne '>') {
                    $split += $names.Substring(0, $j)
                    $names = $names.Substring($j)
                    if (($j = $names.IndexOf(',')) -eq -1) {
                        break
                    }
                    $names = $names.Substring($j)
                    $j = $names.IndexOf('=')
                }
            }
        }
        foreach ($name in $split) {
            while ($name[0] -in $defines) {
                $name = $name.Substring(1)
            }
            foreach ($i in $defines) {
                if (($j = $name.IndexOf($i)) -ne -1) {
                    $name = $name.Substring(0, $j)
                }
            }
            $files[$file] += $name
        }
    }
    $text = $texta
    foreach ($f in $files.Keys) {
        $path = $f.Substring(0, $f.Length - 3)
        $path = $path -replace "[^$base64]", '_'
        foreach ($name in $files[$f]) {
            $text = substitute $text $name ($name + '_' + $path)
        }
    }
    $lines = $text.Split("`n")
    $text = ''
    foreach ($line in $lines) {
        $a = $line.TrimStart("`t ")
        if ($a.StartsWith('export default ')) {
            $line = $a.Substring(15)
        } elseif ($a.StartsWith('export ')) {
            $line = $a.Substring(7)
            $a = $line.TrimStart("`t ")
            if ($a[0] -eq '{') {
                continue
            }
        }
        if ($line -and -not $a.StartsWith('import ')) {
            $text += $line + "`n"
        }
    }
    $texts[$file] = $text
}

function build($file, $output) {
    $file = $file ?? 'a/a.js'
    $output = $output ?? 'a/y.js'
    $imported = @()
    $imports = @($file)
    $modules = @{}
    $texts = @{}
    while ($imports.Count -ne 0) {
        $file = $imports[0]
        if ($file -in $imported) {
            $imports = $imports[1..$imports.Count]
        } else {
            parse $file $modules $texts
            $imports = $modules[$file] + $imports
            if ($texts.ContainsKey($file)) {
                $imported += $file
            }
        }
    }
    $text = ''
    foreach ($file in $imported) {
        $text += $texts[$file]
    }
    $text.TrimEnd("`n") > $output
}

build $args[0] $args[1]