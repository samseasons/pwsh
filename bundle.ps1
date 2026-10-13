# pwsh bundle.ps1 a/a.js a/y.js

$base64 = '$0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz'

function resolve($f, $file) {
    while ($f.StartsWith('../')) {
        $f = $f.Substring(3)
        $file = $file.Substring(0, $file.LastIndexOf('/'))
    }
    $f = $file.Substring(0, $file.LastIndexOf('/')) + '/' + $f
    $treats = @('', '/', '', '', '/', '\', '')
    $tricks = @('~', ':', './', '.\', '//', '\\', '../')
    for (($i = 0), ($length = $treats.Count); $i -lt $length; $i++) {
        $treat = $treats[$i]
        $trick = $tricks[$i]
        while ($f.IndexOf($trick) -ne -1) {
            $f = $f.Replace($trick, $treat)
        }
    }
    while ($f[0] -eq '/') {
        $f = $f.Substring(1)
    }
    if (-not $f.EndsWith('.js')) {
        $f += '.js'
    }
    return $f
}

function substitute($match, $next, $text) {
    $a = $text.IndexOf($match)
    $i = $match.Length
    $j = $next.Length
    while ($a -ne -1) {
        if ($base64.Contains($text[$a + $i]) -or ($a -ne 0 -and ($base64 + "`"'.").Contains($text[$a - 1]))) {
            $a = $text.IndexOf($match, $a + $i)
        } else {
            $text = $text.Substring(0, $a) + $next + $text.Substring($a + $i)
            $a = $text.IndexOf($match, $a + $j)
        }
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
    $defaults = @{}
    $exports = @{$file = @{}}
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
        $defaulted = ''
        $names = @{}
        $text = $text.Substring($i)
        $i = $text.IndexOf('from')
        $j = $text.IndexOf('"')
        $k = $text.IndexOf("'")
        if ($i -ne -1 -and ($i -lt $j -or $j -eq -1) -and ($i -lt $k -or $k -eq -1)) {
            $length = $text.Length
            while ($i -lt $length) {
                $j = $text[$i - 1]
                $k = $text[$i + 4]
                if (($j -eq ' ' -or $j -eq '}') -and ($k -eq ' ' -or $k -eq '"' -or $k -eq "'")) {
                    break
                }
                $i += 4
                $i += $text.Substring($i).IndexOf('from')
            }
            $variables = $text.Substring(0, $i)
            if (($j = $variables.IndexOf('{')) -ne -1) {
                $split = $variables.Substring($j + 1, $variables.IndexOf('}') - $j - 1).Split(',')
                $variables = $variables.Substring(0, $j)
                foreach ($name in $split) {
                    $name = $name.TrimStart("`t ").TrimEnd("`t ")
                    if (($k = $name.indexOf(' as ')) -ne -1) {
                        $names[$name.Substring(0, $k)] = $name.Substring($k + 4)
                    } elseif ($name) {
                        $names[$name] = $name
                    }
                }
            }
            if (($j = $variables.IndexOf(',')) -ne -1) {
                $variables = $variables.Substring(0, $j)
            }
            $name = $variables.TrimStart("`t ").TrimEnd("`t ")
            if ($name) {
                $defaulted = $name
                $names[$name] = $name
            }
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
                $exports[$f] = @{}
                $order += $f
            }
            if ($defaulted) {
                $defaults[$f] = $defaulted
            }
            foreach ($name in $names.Keys) {
                $exports[$f][$name] = $names[$name]
            }
        }
    }
    $dependencies = $false
    $mods = @()
    foreach ($f in $order) {
        if (-not $texts.ContainsKey($f)) {
            $mods += $f
            if (-not $modules.ContainsKey($f)) {
                $dependencies = $true
            }
        }
    }
    if ($dependencies) {
        $modules[$file] = $mods
        return
    }
    $declares = @('async', 'class', 'const', 'default', 'function', 'let', 'var')
    $defines = @("`n", ' ', '(', ',', '.', '[')
    $text = $texta
    while (($i = $text.IndexOf('export ')) -ne -1) {
        $text = $text.Substring($i + 7)
        if ($text.IndexOf('default ') -eq 0) {
            continue
        }
        foreach ($name in $declares) {
            $i = $text.IndexOf($name)
            if ($i -ne -1 -and $i -lt 3) {
                $text = $text.Substring($i + $name.Length)
            }
        }
        if (($i = $text.IndexOf("`n")) -ne -1) {
            $variables = $text.Substring(0, $i)
            $i = 0
            $length = $name.Length
            while ($i -lt $length -and $variables[$i] -eq ' ') {
                $i += 1
            }
            $split = @()
            if ($i -lt $length -and $variables[$i] -eq '{') {
                $variables = $variables.Substring($i + 1)
                $split = $variables.Substring(0, $variables.IndexOf('}')).Split(',')
            } else {
                $i = $variables.IndexOf('(')
                $j = $variables.IndexOf('=')
                if ($j -eq -1 -or ($i -lt $j -and $i -ne -1)) {
                    $split += $variables
                } else {
                    while ($j -ne -1 -and $variables[$j + 1] -ne '>') {
                        $split += $variables.Substring(0, $j)
                        $variables = $variables.Substring($j)
                        if (($j = $variables.IndexOf(',')) -eq -1) {
                            break
                        }
                        $variables = $variables.Substring($j)
                        $j = $variables.IndexOf('=')
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
                $exports[$file][$name] = $name
            }
        }
    }
    $defaulted = ''
    $text = $texta
    foreach ($f in $exports.Keys) {
        $path = $f.Substring(0, $f.Length - 3)
        $path = $path -replace "[^$base64]", '_'
        if ($f -eq $file) {
            $defaulted = $path
        }
        $exported = $exports[$f]
        foreach ($named in $exported.Keys) {
            $name = $exported[$named]
            if ($defaults.ContainsKey($f) -and $defaults[$f] -eq $name) {
                $text = substitute $name ('_' + $path) $text
            } else {
                $text = substitute $name ($named + '_' + $path) $text
            }
        }
    }
    $lines = $text.Split("`n")
    $text = ''
    foreach ($line in $lines) {
        $a = $line.TrimStart("`t ")
        if ($a.StartsWith('export default ')) {
            $line = '_' + $defaulted + ' = ' + $a.Substring(15)
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
            if ($modules.ContainsKey($file)) {
                $imports = $modules[$file] + $imports
            }
            if ($texts.ContainsKey($file)) {
                $imported += $file
                $imports = $imports[1..$imports.Count]
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